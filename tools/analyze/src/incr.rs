//! Per-file results of whole-tree lints, as queries in a `dm_query::Db` (lean_unified "One program", 1+3 ENGINE).
//!
//! A whole-tree lint is a fold over per-file facts followed by a per-file judgement that reads the fold:
//!
//! * [`facts`]: `f(file)`, keyed by the file's content key (path + hash): a pure function of the one file.
//! * [`keyed`]: `f(file)` that also reads a shared context (an index built from every file's facts), named by a [`ctx_key`]. A
//!   one-line edit that changes no fact leaves the key alone, so every other file's result is the one already held.
//! * [`two_phase`]: both, wired together: facts, merge, judge.
//! * [`cached`]: one value under one key.
//! * [`keyed_reading`]: `f(file)` that reads an [`Index`] entry by entry through a [`Reads`] accessor: each entry it reads is recorded
//!   with its digest, and the file's result is kept while every entry it read digests the same (an entry it found missing counts as
//!   read too). A judgement that reads a few entries of a large index is then not re-run when other entries change.
//!
//! Contract for the closures: deterministic, depend only on the file (`f.raw()` etc. and `f.rel`) and on what the context key covers.
//! A result type round-trips through bincode, and `Default` means "nothing found".
//!
//! **Where the values live.** One `dm_query::Db` per stamp (engine build, scope list, parse flavor), kept for the life of the
//! process: inside the dmbc daemon it outlives the request and serves every worktree, so a later request reads every unchanged
//! file's result as it is in memory, without decoding it. Every entry is named by what decides it (`ENTRY(store, context, content
//! key)`, `VALUE(store, key)`), so it is valid for any root and never goes stale: an edit asks for other entries. Entries are computed
//! by the caller's closure (`Db::get_with`); their hash is their encoding's.
//!
//! **Persistence.** The encoded results also go to slot files, one per (store, stamp), read back the first time a process asks a
//! store (a new process, or a restarted daemon, starts warm): `persist-<hash>.bin` in [`persist_dir`] (the run's cache directory
//! standalone, `data/analyze-cache`; the daemon names its own with [`set_persist_dir`]). [`flush`] writes the changed slots at the end
//! of a run. Leases bound them: each root (cache directory) holds a lease on every entry its latest run asked for; past the byte
//! budget (`DQ_ANALYZE_STORE_BUDGET_MB`, default 768) entries no root holds go first, oldest first, then held ones, oldest first, from
//! memory and disk alike. Cache errors are never fatal: a missing or corrupt slot is a miss.
//!
//! ALLOW questions asked through `sys::kept_recorded` inside a closure are kept with its result and replayed on a hit, so the
//! unused-ALLOW check sees them either way.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

use dm_query::{Db, Key, Kind, Outcome, QueryError};
use rayon::prelude::*;
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};

use crate::lint::AllowUse;
use crate::tree::{Hash, SourceFile};

const ENTRY: Kind = Kind(1);
const VALUE: Kind = Kind(2);
const ITEM_OVERHEAD: u64 = 48;
/// The hash of a clean result (`R::default()`, no allow use).
const CLEAN: Hash = 0x5eed_c1ea_0000_0000_0000_0000_0000_0001;

fn budget() -> u64 {
    dq_hostio::var("DQ_ANALYZE_STORE_BUDGET_MB").ok().and_then(|v| v.parse::<u64>().ok()).unwrap_or(768) << 20
}

struct Config {
    dir: PathBuf,
    stamp: String,
    enabled: bool,
}

static CONFIG: Mutex<Option<Config>> = Mutex::new(None);
static SUSPENDED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
/// Where a host keeps the slot files (the daemon: one directory per binary image), instead of the run's cache directory.
static PERSIST_DIR: Mutex<Option<PathBuf>> = Mutex::new(None);

/// Called by the engine once per run: where its caches live and which stamp they carry.
pub fn configure(dir: PathBuf, stamp: String, enabled: bool) {
    *CONFIG.lock().unwrap_or_else(|e| e.into_inner()) = Some(Config { dir, stamp, enabled });
}

/// A host names the directory slot files persist to (`None`: the run's cache directory).
pub fn set_persist_dir(dir: Option<PathBuf>) {
    *PERSIST_DIR.lock().unwrap_or_else(|e| e.into_inner()) = dir;
}

/// Whether a host keeps the stores (`set_persist_dir`): the machine-wide disk copy (`shared.rs`) steps aside.
pub fn hosted() -> bool {
    PERSIST_DIR.lock().unwrap_or_else(|e| e.into_inner()).is_some()
}

/// Turns the stores off (selftests run fixture trees through lints that use them: their entries must not replace the real tree's).
pub fn suspend(on: bool) {
    SUSPENDED.store(on, Ordering::SeqCst);
}

fn config() -> Option<(PathBuf, String)> {
    if SUSPENDED.load(Ordering::SeqCst) {
        return None;
    }
    let g = CONFIG.lock().unwrap_or_else(|e| e.into_inner());
    g.as_ref().filter(|c| c.enabled).map(|c| (c.dir.clone(), c.stamp.clone()))
}

/// The cache directory of this run, when caching is on.
pub fn dir() -> Option<PathBuf> {
    config().map(|c| c.0)
}

/// The engine/scope stamp of this run, when caching is on.
pub fn stamp() -> Option<String> {
    config().map(|c| c.1)
}

/// Where slot files of this run persist.
pub fn persist_dir() -> Option<PathBuf> {
    let (dir, _) = config()?;
    Some(PERSIST_DIR.lock().unwrap_or_else(|e| e.into_inner()).clone().unwrap_or(dir))
}

/// The on-disk encoding: bincode with variable-length integers (lengths, lines and offsets cost a byte or two, not eight).
pub fn ser<T: Serialize + ?Sized>(v: &T) -> Result<Vec<u8>, bincode::Error> {
    use bincode::Options;
    bincode::DefaultOptions::new().with_varint_encoding().serialize(v)
}

/// Reads what [`ser`] wrote.
pub fn de<T: DeserializeOwned>(b: &[u8]) -> Result<T, bincode::Error> {
    use bincode::Options;
    bincode::DefaultOptions::new().with_varint_encoding().deserialize(b)
}

/// A 128-bit key of any serializable value (a merged index, a list of facts).
pub fn ctx_key<T: Serialize + ?Sized>(v: &T) -> Hash {
    let bytes = ser(v).unwrap_or_default();
    u128::from_le_bytes(blake3::hash(&bytes).as_bytes()[..16].try_into().unwrap())
}

/// Mixes several keys into one.
pub fn mix(keys: &[Hash]) -> Hash {
    let mut h = blake3::Hasher::new();
    for k in keys {
        h.update(&k.to_le_bytes());
    }
    u128::from_le_bytes(h.finalize().as_bytes()[..16].try_into().unwrap())
}

fn h(parts: &[&[u8]]) -> u128 {
    let mut x = blake3::Hasher::new();
    for p in parts {
        x.update(p);
        x.update(&[0xff]);
    }
    u128::from_le_bytes(x.finalize().as_bytes()[..16].try_into().unwrap())
}

/// One persisted entry: its encoding (`None`: the clean result), the run that last asked for it, and the lease bits of the roots
/// whose latest run asked for it.
struct Item {
    bytes: Option<Arc<[u8]>>,
    seen: u64,
    leases: u64,
}

fn item_bytes(b: &Option<Arc<[u8]>>) -> u64 {
    b.as_ref().map_or(0, |b| b.len() as u64) + ITEM_OVERHEAD
}

/// One store's persisted entries, by `(context, key)`.
#[derive(Default)]
struct Slot {
    items: HashMap<(Hash, Hash), Item>,
    loaded: bool,
    dirty: bool,
}

#[derive(Serialize, Deserialize)]
struct SlotFile {
    store: String,
    stamp: String,
    items: Vec<(Hash, Hash, Option<Vec<u8>>)>,
}

/// One stamp's database, its slots, the roots holding leases and the run counter.
struct Session {
    db: Db,
    stamp: String,
    slots: Mutex<HashMap<String, Arc<Mutex<Slot>>>>,
    /// Roots (cache directories) by lease bit.
    roots: Mutex<Vec<PathBuf>>,
    run: AtomicU64,
    /// The lease bit of the run in progress (runs go one at a time).
    lease: AtomicU64,
    bytes: AtomicU64,
}

static SESSION: Mutex<Option<Arc<Session>>> = Mutex::new(None);
/// The run whose leases were renewed ([`Session::begin_run`] once per run).
static BEGUN: Mutex<Option<(PathBuf, u64)>> = Mutex::new(None);

/// This run's session: the one kept for its stamp, or a new one when the stamp moved (a scope edit, another parse flavor).
fn session() -> Option<Arc<Session>> {
    let (dir, stamp) = config()?;
    let s = {
        let mut g = SESSION.lock().unwrap_or_else(|e| e.into_inner());
        match g.as_ref() {
            Some(s) if s.stamp == stamp => Arc::clone(s),
            _ => {
                let db = Db::new();
                db.define_local(ENTRY, "incr-entry");
                db.define_local(VALUE, "incr-value");
                let s = Arc::new(Session {
                    db,
                    stamp,
                    slots: Mutex::new(HashMap::new()),
                    roots: Mutex::new(Vec::new()),
                    run: AtomicU64::new(1),
                    lease: AtomicU64::new(0),
                    bytes: AtomicU64::new(0),
                });
                *g = Some(Arc::clone(&s));
                s
            }
        }
    };
    s.begin_run(&dir);
    Some(s)
}

fn slot_path(dir: &Path, store: &str, stamp: &str) -> PathBuf {
    dir.join(format!("persist-{:032x}.bin", h(&[store.as_bytes(), stamp.as_bytes()])))
}

fn entry_node(store: &str, ctx: Hash, key: Hash) -> Key {
    Key::new(ENTRY, h(&[store.as_bytes(), &ctx.to_le_bytes(), &key.to_le_bytes()]))
}

fn value_node(store: &str, key: Hash) -> Key {
    Key::new(VALUE, h(&[store.as_bytes(), &key.to_le_bytes()]))
}

impl Session {
    /// Once per run: this root's lease bit, dropped from every entry (what this run asks for claims it again).
    fn begin_run(&self, dir: &Path) {
        let run = self.run.load(Ordering::Relaxed);
        let mut begun = BEGUN.lock().unwrap_or_else(|e| e.into_inner());
        if begun.as_ref().is_some_and(|(d, r)| d == dir && *r == run) {
            return;
        }
        *begun = Some((dir.to_path_buf(), run));
        let bit = {
            let mut roots = self.roots.lock().unwrap_or_else(|e| e.into_inner());
            let i = match roots.iter().position(|r| r == dir) {
                Some(i) => i,
                None => {
                    if roots.len() >= 64 {
                        roots.remove(0);
                    }
                    roots.push(dir.to_path_buf());
                    roots.len() - 1
                }
            };
            1u64 << i
        };
        self.lease.store(bit, Ordering::Relaxed);
        for slot in self.slots.lock().unwrap_or_else(|e| e.into_inner()).values() {
            for it in slot.lock().unwrap_or_else(|e| e.into_inner()).items.values_mut() {
                it.leases &= !bit;
            }
        }
    }

    fn slot(&self, store: &str) -> Arc<Mutex<Slot>> {
        let s = Arc::clone(self.slots.lock().unwrap_or_else(|e| e.into_inner()).entry(store.to_string()).or_default());
        {
            let mut g = s.lock().unwrap_or_else(|e| e.into_inner());
            if !g.loaded {
                g.loaded = true;
                if let Some(dir) = persist_dir() {
                    if let Some(file) = std::fs::read(slot_path(&dir, store, &self.stamp)).ok().and_then(|b| de::<SlotFile>(&b).ok()) {
                        if file.store == store && file.stamp == self.stamp {
                            let run = self.run.load(Ordering::Relaxed);
                            for (c, k, b) in file.items {
                                let bytes: Option<Arc<[u8]>> = b.map(Into::into);
                                self.bytes.fetch_add(item_bytes(&bytes), Ordering::Relaxed);
                                g.items.entry((c, k)).or_insert(Item { bytes, seen: run.saturating_sub(1), leases: 0 });
                            }
                        }
                    }
                }
            }
        }
        s
    }

    /// Stores a computed entry's encoding in its slot.
    fn keep(&self, slot: &Mutex<Slot>, at: (Hash, Hash), bytes: Option<Arc<[u8]>>) {
        let (run, lease) = (self.run.load(Ordering::Relaxed), self.lease.load(Ordering::Relaxed));
        self.bytes.fetch_add(item_bytes(&bytes), Ordering::Relaxed);
        let mut g = slot.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(old) = g.items.insert(at, Item { bytes, seen: run, leases: lease }) {
            self.bytes.fetch_sub(item_bytes(&old.bytes), Ordering::Relaxed);
        }
        g.dirty = true;
    }

    /// Past `budget` bytes: entries no root holds go first, oldest first, then held ones, oldest first (memory and slot alike).
    fn evict(&self, budget: u64) {
        if self.bytes.load(Ordering::Relaxed) <= budget {
            return;
        }
        let slots: Vec<(String, Arc<Mutex<Slot>>)> =
            self.slots.lock().unwrap_or_else(|e| e.into_inner()).iter().map(|(k, v)| (k.clone(), Arc::clone(v))).collect();
        for leased_pass in [false, true] {
            let mut gens: Vec<u64> = Vec::new();
            for (_, s) in &slots {
                gens.extend(s.lock().unwrap_or_else(|e| e.into_inner()).items.values().filter(|i| (i.leases != 0) == leased_pass).map(|i| i.seen));
            }
            gens.sort_unstable();
            gens.dedup();
            for g in gens {
                if self.bytes.load(Ordering::Relaxed) <= budget {
                    return;
                }
                for (store, slot) in &slots {
                    let mut sl = slot.lock().unwrap_or_else(|e| e.into_inner());
                    let mut gone = Vec::new();
                    sl.items.retain(|(c, k), i| {
                        if i.seen == g && (i.leases != 0) == leased_pass {
                            self.bytes.fetch_sub(item_bytes(&i.bytes), Ordering::Relaxed);
                            gone.push((*c, *k));
                            false
                        } else {
                            true
                        }
                    });
                    if !gone.is_empty() {
                        sl.dirty = true;
                        for (c, k) in gone {
                            self.db.remove(entry_node(store, c, k));
                            self.db.remove(value_node(store, c));
                        }
                    }
                }
            }
        }
    }
}

/// What a cached closure produced: its result and the allow uses it recorded.
type Stored<R> = (R, Vec<AllowUse>);

/// `f(i)` for every `keys[i]`, each an entry of the store `name` under the context `ctx`.
fn run_keyed<R>(name: &str, ctx: Hash, keys: &[Hash], f: impl Fn(usize) -> R + Sync) -> Vec<R>
where
    R: Serialize + DeserializeOwned + Default + PartialEq + Clone + Send + Sync + 'static,
{
    let Some(s) = session() else {
        return (0..keys.len()).into_par_iter().map(&f).collect();
    };
    let slot = s.slot(name);
    let computed = AtomicUsize::new(0);
    let results: Vec<Arc<Stored<R>>> = (0..keys.len())
        .into_par_iter()
        .map(|i| {
            let node = entry_node(name, ctx, keys[i]);
            let got = s.db.get_with::<Stored<R>>(node, &mut |_| {
                let persisted = slot.lock().unwrap_or_else(|e| e.into_inner()).items.get(&(ctx, keys[i])).map(|it| it.bytes.clone());
                let decoded: Option<(Stored<R>, Hash)> = match persisted {
                    Some(None) => Some(((R::default(), Vec::new()), CLEAN)),
                    Some(Some(b)) => de::<Stored<R>>(&b).ok().map(|v| (v, h(&[&b]))),
                    None => None,
                };
                let (value, hash) = match decoded {
                    Some(v) => v,
                    None => {
                        computed.fetch_add(1, Ordering::Relaxed);
                        let before = crate::dm::sys::take_recorded();
                        let r = f(i);
                        let u = crate::dm::sys::take_recorded();
                        crate::dm::sys::restore_recorded(before);
                        let (bytes, hash) = if r == R::default() && u.is_empty() {
                            (None, CLEAN)
                        } else {
                            let b = ser(&(&r, &u)).map_err(|_| QueryError::Missing(node))?;
                            let hash = h(&[&b]);
                            (Some(Arc::<[u8]>::from(b)), hash)
                        };
                        s.keep(&slot, (ctx, keys[i]), bytes);
                        ((r, u), hash)
                    }
                };
                Ok(Outcome::new(value, hash, 64))
            });
            // A query error (a cycle cannot happen here): compute without the store.
            got.unwrap_or_else(|_| Arc::new((f(i), Vec::new())))
        })
        .collect();
    {
        let (run, lease) = (s.run.load(Ordering::Relaxed), s.lease.load(Ordering::Relaxed));
        let mut g = slot.lock().unwrap_or_else(|e| e.into_inner());
        for k in keys {
            if let Some(item) = g.items.get_mut(&(ctx, *k)) {
                item.seen = run;
                item.leases |= lease;
            }
        }
    }
    let n = computed.load(Ordering::Relaxed);
    stats_add(name, keys.len() - n, n);
    let mut uses = Vec::new();
    let mut out = Vec::with_capacity(results.len());
    for r in results {
        uses.extend(r.1.iter().cloned());
        out.push(r.0.clone());
    }
    crate::dm::sys::replay_recorded(uses);
    out
}

/// `f(file)` for every file, cached per file under `ctx`. See the module docs.
pub fn keyed<R>(name: &str, ctx: Hash, files: &[&SourceFile], f: impl Fn(&SourceFile) -> R + Sync) -> Vec<R>
where
    R: Serialize + DeserializeOwned + Default + PartialEq + Clone + Send + Sync + 'static,
{
    let t_all = std::time::Instant::now();
    let keys: Vec<Hash> = files.iter().map(|file| file.fkey).collect();
    let r = run_keyed(name, ctx, &keys, |i| f(files[i]));
    if trace_on() {
        let ms = t_all.elapsed().as_secs_f64() * 1000.0;
        if ms >= 4.0 {
            eprintln!("incr {:<34} {:>7.1} ms (files {})", name, ms, files.len());
        }
    }
    r
}

/// [`keyed`] over items named by content keys instead of files: `f(i)` for `keys[i]`, cached per key under `ctx` in the store `name`.
/// For results that are a function of something other than a tree file (a file of the semantic model, under its macro environment).
pub fn keyed_by<R>(name: &str, ctx: Hash, keys: &[Hash], f: impl Fn(usize) -> R + Sync) -> Vec<R>
where
    R: Serialize + DeserializeOwned + Default + PartialEq + Clone + Send + Sync + 'static,
{
    run_keyed(name, ctx, keys, f)
}

/// Per-file facts: `f(file)` cached by content alone.
pub fn facts<F>(name: &str, files: &[&SourceFile], f: impl Fn(&SourceFile) -> F + Sync) -> Vec<F>
where
    F: Serialize + DeserializeOwned + Default + PartialEq + Clone + Send + Sync + 'static,
{
    keyed(name, 0, files, f)
}

/// An index a judgement reads entry by entry ([`keyed_reading`]): its entries and the digest of each.
pub struct Index<K, V> {
    map: HashMap<K, V>,
    digests: HashMap<u128, Hash>,
}

impl<K: std::hash::Hash + Eq + Serialize, V: Serialize> Index<K, V> {
    pub fn new(map: HashMap<K, V>) -> Self {
        let digests = map.iter().map(|(k, v)| (ctx_key(k), ctx_key(v))).collect();
        Index { map, digests }
    }

    /// The entries, unrecorded (for the merge that built them, not for a judgement).
    pub fn entries(&self) -> &HashMap<K, V> {
        &self.map
    }
}

/// What a judgement reads of an [`Index`]: every entry it looks up is recorded with the digest it had.
pub struct Reads<'i, K, V> {
    idx: &'i Index<K, V>,
    got: std::cell::RefCell<Vec<(u128, Hash)>>,
}

/// The digest recorded for an entry that was looked up and not there.
const ABSENT: Hash = 0;

impl<'i, K: std::hash::Hash + Eq + Serialize, V> Reads<'i, K, V> {
    /// The entry of `k`, recorded.
    pub fn get<Q>(&self, k: &Q) -> Option<&'i V>
    where
        K: std::borrow::Borrow<Q>,
        Q: std::hash::Hash + Eq + Serialize + ?Sized,
    {
        let kh = ctx_key(k);
        self.got.borrow_mut().push((kh, self.idx.digests.get(&kh).copied().unwrap_or(ABSENT)));
        self.idx.map.get(k)
    }
}

/// What a [`keyed_reading`] entry keeps: the result, its allow uses, and the entries it read with their digests.
type Receipted<R> = (R, Vec<AllowUse>, Vec<(u128, Hash)>);

/// `f(file)` for every file, cached per file under `ctx` and the [`Index`] entries `f` read through its [`Reads`] (see the module docs).
pub fn keyed_reading<K, V, R>(name: &str, ctx: Hash, files: &[&SourceFile], idx: &Index<K, V>, f: impl Fn(&SourceFile, &Reads<K, V>) -> R + Sync) -> Vec<R>
where
    K: std::hash::Hash + Eq + Serialize + Sync,
    V: Sync,
    R: Serialize + DeserializeOwned + Default + PartialEq + Clone + Send + Sync + 'static,
{
    let current = |receipt: &[(u128, Hash)]| receipt.iter().all(|(k, d)| idx.digests.get(k).copied().unwrap_or(ABSENT) == *d);
    let run = |file: &SourceFile| -> Receipted<R> {
        let reads = Reads { idx, got: std::cell::RefCell::new(Vec::new()) };
        let before = crate::dm::sys::take_recorded();
        let r = f(file, &reads);
        let u = crate::dm::sys::take_recorded();
        crate::dm::sys::restore_recorded(before);
        let mut got = reads.got.into_inner();
        got.sort_unstable();
        got.dedup();
        (r, u, got)
    };
    let Some(s) = session() else {
        return files.par_iter().map(|file| run(file).0).collect();
    };
    let slot = s.slot(name);
    let computed = AtomicUsize::new(0);
    let results: Vec<Arc<Receipted<R>>> = files
        .par_iter()
        .map(|file| {
            let node = entry_node(name, ctx, file.fkey);
            let mut fresh = |_: &mut dm_query::Ctx<'_>| -> Result<Outcome, QueryError> {
                let persisted = slot.lock().unwrap_or_else(|e| e.into_inner()).items.get(&(ctx, file.fkey)).and_then(|it| it.bytes.clone());
                if let Some(v) = persisted.as_ref().and_then(|b| de::<Receipted<R>>(b).ok().map(|v| (v, h(&[b])))) {
                    if current(&v.0 .2) {
                        return Ok(Outcome::new(v.0, v.1, 64));
                    }
                }
                computed.fetch_add(1, Ordering::Relaxed);
                let v = run(file);
                let b = ser(&v).map_err(|_| QueryError::Missing(node))?;
                let hash = h(&[&b]);
                s.keep(&slot, (ctx, file.fkey), Some(b.into()));
                Ok(Outcome::new(v, hash, 64))
            };
            match s.db.get_with::<Receipted<R>>(node, &mut fresh) {
                Ok(v) if current(&v.2) => v,
                // Held, but an entry it read changed: computed again in its place.
                Ok(_) => {
                    s.db.remove(node);
                    s.db.get_with::<Receipted<R>>(node, &mut fresh).unwrap_or_else(|_| Arc::new(run(file)))
                }
                Err(_) => Arc::new(run(file)),
            }
        })
        .collect();
    {
        let (run_no, lease) = (s.run.load(Ordering::Relaxed), s.lease.load(Ordering::Relaxed));
        let mut g = slot.lock().unwrap_or_else(|e| e.into_inner());
        for file in files {
            if let Some(item) = g.items.get_mut(&(ctx, file.fkey)) {
                item.seen = run_no;
                item.leases |= lease;
            }
        }
    }
    let n = computed.load(Ordering::Relaxed);
    stats_add(name, files.len() - n, n);
    let mut uses = Vec::new();
    let mut out = Vec::with_capacity(results.len());
    for r in results {
        uses.extend(r.1.iter().cloned());
        out.push(r.0.clone());
    }
    crate::dm::sys::replay_recorded(uses);
    out
}

/// Facts, merge, judge. `merge` receives the facts in `files` order; the judge reads the merged index. The judge's results are
/// cached while the facts' key (every non-empty fact, in order) is unchanged.
pub fn two_phase<F, I, R>(
    name: &str,
    files: &[&SourceFile],
    facts_fn: impl Fn(&SourceFile) -> F + Sync,
    merge: impl FnOnce(&[(&SourceFile, &F)]) -> I,
    judge: impl Fn(&SourceFile, &I) -> R + Sync,
) -> (I, Vec<R>)
where
    F: Serialize + DeserializeOwned + Default + PartialEq + Clone + Send + Sync + 'static,
    I: Sync,
    R: Serialize + DeserializeOwned + Default + PartialEq + Clone + Send + Sync + 'static,
{
    let fs = facts(&format!("{}-facts", name), files, facts_fn);
    let default = F::default();
    let nonempty: Vec<(&str, &F)> = files.iter().zip(fs.iter()).filter(|(_, x)| **x != default).map(|(f, x)| (f.rel.as_str(), x)).collect();
    let key = ctx_key(&nonempty);
    let pairs: Vec<(&SourceFile, &F)> = files.iter().copied().zip(fs.iter()).collect();
    let idx = merge(&pairs);
    let rs = keyed(&format!("{}-judge", name), key, files, |file| judge(file, &idx));
    (idx, rs)
}

/// One value cached under `key`: `compute()` runs only when no value is held for this key. The store keeps the latest key's value.
pub fn cached<T>(name: &str, key: Hash, compute: impl FnOnce() -> T) -> T
where
    T: Serialize + DeserializeOwned + Clone + Send + Sync + 'static,
{
    let Some(s) = session() else { return compute() };
    let slot = s.slot(name);
    let node = value_node(name, key);
    let mut compute = Some(compute);
    let mut fresh = false;
    let got = s.db.get_with::<T>(node, &mut |_| {
        let persisted = slot.lock().unwrap_or_else(|e| e.into_inner()).items.get(&(key, 0)).and_then(|it| it.bytes.clone());
        if let Some((v, hash)) = persisted.as_ref().and_then(|b| de::<T>(b).ok().map(|v| (v, h(&[b])))) {
            return Ok(Outcome::new(v, hash, 64));
        }
        let Some(c) = compute.take() else { return Err(QueryError::Missing(node)) };
        fresh = true;
        let v = c();
        let b = ser(&v).map_err(|_| QueryError::Missing(node))?;
        let hash = h(&[&b]);
        // One value per store: a new key replaces the old one.
        let old: Vec<(Hash, Hash)> = slot.lock().unwrap_or_else(|e| e.into_inner()).items.keys().copied().filter(|k| *k != (key, 0)).collect();
        {
            let mut g = slot.lock().unwrap_or_else(|e| e.into_inner());
            for k in &old {
                if let Some(it) = g.items.remove(k) {
                    s.bytes.fetch_sub(item_bytes(&it.bytes), Ordering::Relaxed);
                }
            }
        }
        for (k, _) in old {
            s.db.remove(value_node(name, k));
        }
        s.keep(&slot, (key, 0), Some(b.into()));
        Ok(Outcome::new(v, hash, 64))
    });
    {
        let (run, lease) = (s.run.load(Ordering::Relaxed), s.lease.load(Ordering::Relaxed));
        if let Some(it) = slot.lock().unwrap_or_else(|e| e.into_inner()).items.get_mut(&(key, 0)) {
            it.seen = run;
            it.leases |= lease;
        }
    }
    stats_add(name, usize::from(!fresh), usize::from(fresh));
    match got {
        Ok(v) => (*v).clone(),
        Err(_) => match compute.take() {
            Some(c) => c(),
            None => panic!("incr::cached({name}): the value was computed but could not be kept"),
        },
    }
}

fn trace_on() -> bool {
    static ON: dq_hostio::EnvCached<bool> = dq_hostio::EnvCached::new();
    ON.get(|| dq_hostio::var("DQ_ANALYZE_TRACE_INCR").is_ok())
}

/// Served and computed entries per store this run ([`stats`]).
static STATS: Mutex<Option<HashMap<String, (usize, usize)>>> = Mutex::new(None);

fn stats_add(name: &str, served: usize, computed: usize) {
    let mut g = STATS.lock().unwrap_or_else(|e| e.into_inner());
    let e = g.get_or_insert_with(HashMap::new).entry(name.to_string()).or_default();
    e.0 += served;
    e.1 += computed;
}

/// One line on what this run's stores held and computed (`store=computed/asked` for every store that computed anything).
pub fn stats() -> String {
    let (entries, bytes) = usage();
    let g = STATS.lock().unwrap_or_else(|e| e.into_inner());
    let empty = HashMap::new();
    let m = g.as_ref().unwrap_or(&empty);
    let mut rows: Vec<String> = m.iter().filter(|(_, v)| v.1 > 0).map(|(k, v)| format!("{}={}/{}", k, v.1, v.0 + v.1)).collect();
    rows.sort();
    let computed: usize = m.values().map(|v| v.1).sum();
    let asked: usize = m.values().map(|v| v.0 + v.1).sum();
    format!(
        "analysis stores: {} entries, {:.1} MB encoded; computed {} of {} [{}]",
        entries,
        bytes as f64 / (1u64 << 20) as f64,
        computed,
        asked,
        rows.join(" ")
    )
}

/// (entries, encoded bytes) the kept session holds.
pub fn usage() -> (usize, u64) {
    let Some(s) = SESSION.lock().unwrap_or_else(|e| e.into_inner()).clone() else { return (0, 0) };
    let n = s.slots.lock().unwrap_or_else(|e| e.into_inner()).values().map(|sl| sl.lock().unwrap_or_else(|e| e.into_inner()).items.len()).sum();
    (n, s.bytes.load(Ordering::Relaxed))
}

/// The end of a run: evicts past the byte budget, writes the changed slots, and starts the next run's count.
pub fn flush() {
    let Some((_, stamp)) = config() else { return };
    let Some(s) = SESSION.lock().unwrap_or_else(|e| e.into_inner()).clone().filter(|s| s.stamp == stamp) else { return };
    s.evict(budget());
    s.run.fetch_add(1, Ordering::Relaxed);
    let Some(dir) = persist_dir() else { return };
    let slots: Vec<(String, Arc<Mutex<Slot>>)> = s.slots.lock().unwrap_or_else(|e| e.into_inner()).iter().map(|(k, v)| (k.clone(), Arc::clone(v))).collect();
    let _ = std::fs::create_dir_all(&dir);
    slots.par_iter().for_each(|(store, slot)| {
        let mut g = slot.lock().unwrap_or_else(|e| e.into_inner());
        if !g.dirty {
            return;
        }
        g.dirty = false;
        let file = SlotFile {
            store: store.clone(),
            stamp: s.stamp.clone(),
            items: g.items.iter().map(|((c, k), it)| (*c, *k, it.bytes.as_ref().map(|b| b.to_vec()))).collect(),
        };
        drop(g);
        if let Ok(bytes) = ser(&file) {
            write_atomic(&slot_path(&dir, store, &s.stamp), &bytes);
        }
    });
}

/// A scratch name no other writer shares: threads of one process may save the same path.
fn unique_tmp(path: &Path) -> PathBuf {
    static SEQ: AtomicUsize = AtomicUsize::new(0);
    path.with_extension(format!("tmp{}-{}", std::process::id(), SEQ.fetch_add(1, Ordering::Relaxed)))
}

fn write_atomic(path: &Path, bytes: &[u8]) {
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let tmp = unique_tmp(path);
    if std::fs::write(&tmp, bytes).is_ok() {
        let _ = std::fs::rename(&tmp, path);
    } else {
        let _ = std::fs::remove_file(&tmp);
    }
}

/// Drops the kept session (the host sheds memory; the slots on disk are current after every run). Returns the bytes it held.
pub fn shed() -> u64 {
    SESSION.lock().unwrap_or_else(|e| e.into_inner()).take().map_or(0, |s| s.bytes.load(Ordering::Relaxed))
}

/// Run state for `crate::host::reset_run_state` (the session stays: it is what the next request reads).
pub(crate) fn reset() {
    *CONFIG.lock().unwrap_or_else(|e| e.into_inner()) = None;
    SUSPENDED.store(false, Ordering::SeqCst);
    *STATS.lock().unwrap_or_else(|e| e.into_inner()) = None;
}
