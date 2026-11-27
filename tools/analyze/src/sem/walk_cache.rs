//! Walk results kept between runs: after a one-file edit only the walks that entered a changed proc are walked again.
//!
//! A walk ([`ReadsEngine::analyze`](super::reads::ReadsEngine::analyze) / `analyze_handler`) is a function of
//!
//! * the bodies of the procs it entered, directly or through the memoized context-free walks it reached,
//! * the declarations of the vars it looked up (`Sem::var_decl`: type, flags and where it is declared),
//! * everything else it can consult, which is the same for every walk of a run: the type structure (paths, parents, which vars and procs
//!   each type defines, their declared types, parameters and initial constants), the declarations (`Decls::key`), the annotations, the
//!   global-var index and the write index, and the engine's settings.
//!
//! The walk records the first two as it goes (a thread-local frame per walk and per memoized node, [`record`]); the third is one digest
//! per run and engine kind ([`context`]). `data/analyze-cache/walks.bin` keeps each walk's result with the digests of what it read. A
//! later run serves a walk from it when its context digest is unchanged and every proc body and var declaration it read digests the same
//! (a body moved down by an edit above it digests differently: its lines are in the result). `DQ_WALK_VERIFY=1` walks everything anyway
//! and counts the stored results that differ (it must print 0); `DQ_WALK_CACHE=off` disables it.
//!
//! A process that serves many runs (the dmbc daemon) keeps the store decoded between them ([`Resident`]): the end of a run folds its walks
//! into it, and the next run of the same cache directory and engine takes it instead of reading and decoding the files. The files are
//! still written, so a new process starts warm.

use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, OnceLock, RwLock};

use serde::{Deserialize, Serialize};

use super::reads::ReadSet;
use super::Sem;

const FILE: &str = "walks.bin";

/// What a walk read that can differ between runs of the same context.
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Dep {
    /// Every definition of `owner`'s own proc `name` (its body, parameters and location).
    Proc(String, String),
    /// `Sem::var_decl(ty, name)`.
    Var(String, String),
}

fn dep_id(d: &Dep) -> u64 {
    let mut h = blake3::Hasher::new();
    match d {
        Dep::Proc(a, b) => {
            h.update(b"P");
            h.update(a.as_bytes());
            h.update(b"|");
            h.update(b.as_bytes());
        }
        Dep::Var(a, b) => {
            h.update(b"V");
            h.update(a.as_bytes());
            h.update(b"|");
            h.update(b.as_bytes());
        }
    }
    u64::from_le_bytes(h.finalize().as_bytes()[..8].try_into().unwrap())
}

/// Every dependency id seen this run, with what it names.
static DEPS: crate::host::RunCell<RwLock<HashMap<u64, Dep>>> = crate::host::RunCell::new();

fn deps() -> &'static RwLock<HashMap<u64, Dep>> {
    DEPS.get_or_init(Default::default)
}

thread_local! {
    static FRAMES: RefCell<Vec<HashSet<u64>>> = const { RefCell::new(Vec::new()) };
    static KNOWN: RefCell<HashSet<u64>> = RefCell::new(HashSet::new());
}

fn enabled() -> bool {
    static ON: dq_hostio::EnvCached<bool> = dq_hostio::EnvCached::new();
    ON.get(|| !matches!(dq_hostio::var("DQ_WALK_CACHE").as_deref(), Ok("off") | Ok("0")) && crate::incr::dir().is_some())
}

fn verify() -> bool {
    dq_hostio::var_os("DQ_WALK_VERIFY").is_some()
}

fn trace() -> bool {
    dq_hostio::var_os("DQ_ANALYZE_TRACE").is_some()
}

/// Records a dependency of the walk (or memoized node) running on this thread, if any.
pub fn record(make: impl FnOnce() -> Dep) {
    FRAMES.with(|f| {
        let mut f = f.borrow_mut();
        let Some(top) = f.last_mut() else { return };
        let d = make();
        let id = dep_id(&d);
        if top.insert(id) {
            let new = KNOWN.with(|k| k.borrow_mut().insert(id));
            if new {
                deps().write().unwrap().entry(id).or_insert(d);
            }
        }
    });
}

/// Starts a frame (a walk, or a memoized node computed inside one).
pub fn push_frame() {
    FRAMES.with(|f| f.borrow_mut().push(HashSet::new()));
}

/// Ends the frame started last and returns what it recorded.
pub fn pop_frame() -> Vec<u64> {
    let set = FRAMES.with(|f| f.borrow_mut().pop()).unwrap_or_default();
    let mut v: Vec<u64> = set.into_iter().collect();
    v.sort_unstable();
    v
}

/// Adds a memoized node's dependencies to the running frame (the walk reached the node).
pub fn extend(ids: &[u64]) {
    FRAMES.with(|f| {
        if let Some(top) = f.borrow_mut().last_mut() {
            top.extend(ids.iter().copied());
        }
    });
}

/// A `&'static str` field of a stored result (a rule or effect kind: a small fixed set), interned once.
pub fn intern(s: String) -> &'static str {
    static INTERN: OnceLock<Mutex<HashSet<&'static str>>> = OnceLock::new();
    let mut g = INTERN.get_or_init(Default::default).lock().unwrap();
    if let Some(x) = g.get(s.as_str()) {
        return x;
    }
    let leaked: &'static str = Box::leak(s.into_boxed_str());
    g.insert(leaked);
    leaked
}

/// One file of the store: the walks it holds, with the dependency table they index.
#[derive(Serialize, Deserialize, Default)]
struct Stored {
    engine: String,
    /// Every dependency the entries name, with its digest when the entry was walked.
    deps: Vec<(Dep, u64)>,
    entries: Vec<Entry>,
}

#[derive(Serialize, Deserialize)]
struct Entry {
    key: String,
    context: u128,
    /// Indexes into `Stored::deps`.
    deps: Vec<u32>,
    set: LazySet,
}

/// What [`finish`] serializes: the same layout, borrowing the results.
#[derive(Serialize)]
struct StoredRef<'a> {
    engine: String,
    deps: Vec<(Dep, u64)>,
    entries: Vec<EntryRef<'a>>,
}

#[derive(Serialize)]
struct EntryRef<'a> {
    key: &'a str,
    context: u128,
    deps: Vec<u32>,
    set: &'a LazySet,
}

/// A stored walk: context, dependency ids with their digests, result.
type Kept = (u128, Vec<(u64, u64)>, LazySet);

/// A stored result: its encoded bytes, decoded on first use (by the walk thread that asks, so a store is read without decoding it).
#[derive(Clone)]
pub struct LazySet {
    raw: Option<Box<[u8]>>,
    cell: OnceLock<Arc<ReadSet>>,
}

impl LazySet {
    fn of(set: Arc<ReadSet>) -> LazySet {
        let cell = OnceLock::new();
        let _ = cell.set(set);
        LazySet { raw: None, cell }
    }

    fn get(&self) -> Arc<ReadSet> {
        self.cell
            .get_or_init(|| Arc::new(self.raw.as_ref().map(|b| crate::incr::de::<ReadSet>(b).expect("a stored walk decodes (the store is stamped with the analyzer build)")).unwrap_or_default()))
            .clone()
    }
}

impl Serialize for LazySet {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        match (&self.raw, self.cell.get()) {
            (Some(raw), _) => s.serialize_bytes(raw),
            (None, Some(set)) => s.serialize_bytes(&crate::incr::ser(&**set).map_err(serde::ser::Error::custom)?),
            (None, None) => s.serialize_bytes(&[]),
        }
    }
}

impl<'de> Deserialize<'de> for LazySet {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> Result<LazySet, D::Error> {
        struct V;
        impl<'de> serde::de::Visitor<'de> for V {
            type Value = Box<[u8]>;
            fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
                f.write_str("an encoded walk result")
            }
            fn visit_bytes<E: serde::de::Error>(self, v: &[u8]) -> Result<Box<[u8]>, E> {
                Ok(v.into())
            }
            fn visit_byte_buf<E: serde::de::Error>(self, v: Vec<u8>) -> Result<Box<[u8]>, E> {
                Ok(v.into_boxed_slice())
            }
        }
        Ok(LazySet { raw: Some(d.deserialize_byte_buf(V)?), cell: OnceLock::new() })
    }
}

/// The store is a base file and a delta of the walks made since: a run that walked a few things rewrites the delta only, and the base
/// when the delta has grown past a quarter of it.
const DELTA: &str = "walks-delta.bin";

struct Loaded {
    base: HashMap<String, Kept>,
    delta: HashMap<String, Kept>,
}

/// The store as the last run of a cache directory left it, kept decoded for the next run of the same directory and engine: every walk with
/// the digests of what it read (each is validated when it is asked for, as a stored one is), and the dependency table they index.
struct Resident {
    dir: std::path::PathBuf,
    engine: String,
    deps: HashMap<u64, Dep>,
    walks: HashMap<String, Kept>,
}

static RESIDENT: Mutex<Option<Resident>> = Mutex::new(None);

/// The kept store, when it belongs to `dir` and this engine (it is moved into the run that takes it).
fn take_resident(dir: &std::path::Path) -> Option<Resident> {
    let mut g = RESIDENT.lock().unwrap_or_else(|e| e.into_inner());
    if g.as_ref().is_some_and(|r| r.dir == dir && r.engine == engine()) {
        return g.take();
    }
    None
}

/// Drops the kept store (the host sheds memory; the files on disk are current).
pub fn shed() {
    *RESIDENT.lock().unwrap_or_else(|e| e.into_inner()) = None;
}

/// Whether a host keeps stores between runs (the walks then stay decoded for the next run).
fn keep_resident() -> bool {
    crate::incr::hosted()
}

static LOADED: crate::host::RunCell<Option<Loaded>> = crate::host::RunCell::new();
/// The walks this run made: key -> (context, dep ids, result).
static FRESH: crate::host::RunCell<Mutex<HashMap<String, (u128, Vec<u64>, LazySet)>>> = crate::host::RunCell::new();
static HITS: AtomicUsize = AtomicUsize::new(0);
static MISSES: AtomicUsize = AtomicUsize::new(0);
static DIFFERED: AtomicUsize = AtomicUsize::new(0);

fn fresh() -> &'static Mutex<HashMap<String, (u128, Vec<u64>, LazySet)>> {
    FRESH.get_or_init(Default::default)
}

fn engine() -> String {
    format!("{}|walks-v2", crate::cache::ENGINE_HASH)
}

fn read_file(path: &std::path::Path) -> HashMap<String, Kept> {
    let Ok(bytes) = std::fs::read(path) else { return HashMap::new() };
    let Ok(st) = crate::incr::de::<Stored>(&bytes) else { return HashMap::new() };
    if st.engine != engine() {
        return HashMap::new();
    }
    let ids: Vec<(u64, u64)> = st.deps.iter().map(|(d, g)| (dep_id(d), *g)).collect();
    {
        let mut table = deps().write().unwrap();
        for ((d, _), (id, _)) in st.deps.into_iter().zip(ids.iter()) {
            table.entry(*id).or_insert(d);
        }
    }
    st.entries.into_iter().map(|e| (e.key, (e.context, e.deps.iter().map(|&i| ids[i as usize]).collect(), e.set))).collect()
}

fn loaded() -> Option<&'static Loaded> {
    LOADED
        .get_or_init(|| {
            if !enabled() {
                return None;
            }
            let t0 = std::time::Instant::now();
            let dir = crate::incr::dir()?;
            if let Some(r) = take_resident(&dir) {
                {
                    let mut table = deps().write().unwrap();
                    for (id, d) in r.deps {
                        table.entry(id).or_insert(d);
                    }
                }
                if trace() {
                    eprintln!("analyze: walk cache: took {} walks kept in memory in {:.1?}", r.walks.len(), t0.elapsed());
                }
                return Some(Loaded { base: r.walks, delta: HashMap::new() });
            }
            let (base, delta) = std::thread::scope(|s| {
                let b = s.spawn(|| read_file(&dir.join(FILE)));
                let d = read_file(&dir.join(DELTA));
                (b.join().unwrap_or_default(), d)
            });
            if dq_hostio::var_os("DQ_WALK_SIZES").is_some() {
                let mut by: std::collections::BTreeMap<String, (usize, usize)> = Default::default();
                for (k, (_, _, set)) in base.iter() {
                    let flavor = k.splitn(3, '|').take(3).collect::<Vec<_>>().join("|");
                    let fl: String = flavor.chars().rev().take(12).collect::<String>().chars().rev().collect();
                    let e = by.entry(fl).or_default();
                    e.0 += 1;
                    e.1 += set.raw.as_ref().map(|r| r.len()).unwrap_or(0);
                }
                for (k, (n, b)) in by {
                    eprintln!("WALKS {} {} walks {} MB", k, n, b >> 20);
                }
            }
            if trace() {
                eprintln!("analyze: walk cache: loaded {} + {} walks in {:.1?}", base.len(), delta.len(), t0.elapsed());
            }
            Some(Loaded { base, delta })
        })
        .as_ref()
}

/// Reads the store and decodes every stored walk (a warm worker does this before its request: `crate::warm`).
pub fn prewarm() {
    if let Some(l) = loaded() {
        let sets: Vec<&LazySet> = l.base.values().chain(l.delta.values()).map(|(_, _, s)| s).collect();
        super::par_map(&sets, |s| {
            let _ = s.get();
        });
    }
}

/// Starts reading the store on a side thread (it is read while the model loads).
pub fn prefetch() {
    if enabled() {
        let _ = std::thread::Builder::new().name("walk-cache-load".into()).spawn(|| {
            let c0 = crate::util::thread_cpu_ms();
            loaded();
            if crate::util::cpu_accounting() {
                crate::util::cpu_account("walk cache load thread".into(), crate::util::thread_cpu_ms() - c0);
            }
        });
    }
}

/// The current digest of each dependency, computed once per run: every dependency the store names on all cores at the first lookup
/// (read without a lock after that), the ones this run's walks add as they come.
pub struct Digests {
    pre: OnceLock<HashMap<u64, u64>>,
    map: RwLock<HashMap<u64, u64>>,
}

impl Digests {
    pub fn new() -> Digests {
        Digests { pre: OnceLock::new(), map: RwLock::new(HashMap::new()) }
    }

    fn get(&self, sem: &Sem, id: u64) -> u64 {
        let pre = self.pre.get_or_init(|| {
            let table: Vec<(u64, Dep)> = deps().read().unwrap().iter().map(|(k, d)| (*k, d.clone())).collect();
            let gs: Vec<u64> = super::par_map(&table, |(_, d)| digest_dep(sem, d));
            table.into_iter().map(|(k, _)| k).zip(gs).collect()
        });
        if let Some(v) = pre.get(&id) {
            return *v;
        }
        if let Some(v) = self.map.read().unwrap().get(&id) {
            return *v;
        }
        let dep = deps().read().unwrap().get(&id).cloned();
        let v = match dep {
            Some(d) => digest_dep(sem, &d),
            None => 0,
        };
        self.map.write().unwrap().insert(id, v);
        v
    }
}

impl Default for Digests {
    fn default() -> Self {
        Digests::new()
    }
}

fn h64(bytes: &[u8]) -> u64 {
    u64::from_le_bytes(blake3::hash(bytes).as_bytes()[..8].try_into().unwrap())
}

/// What a dependency digests as: the content of the files its definitions sit in, in the run's macro environment (the definitions of a
/// proc are a function of that; which files they sit in is structure, in the context digest), plus the declaration's shape for a var.
fn digest_dep(sem: &Sem, d: &Dep) -> u64 {
    match d {
        Dep::Proc(owner, name) => {
            let Some(t) = sem.ty(owner) else { return 2 };
            let defs = t.proc_definitions(name);
            if defs.is_empty() {
                return 3;
            }
            let mut h = blake3::Hasher::new();
            for v in &defs {
                h.update(&sem.site_key(v.site()).to_le_bytes());
            }
            u64::from_le_bytes(h.finalize().as_bytes()[..8].try_into().unwrap()) | 1
        }
        Dep::Var(ty, name) => match sem.var_decl_unrecorded(ty, name) {
            Some(v) => h64(format!("{}|{}|{}|{}|{}|{}", v.declared, v.is_static, v.is_const, v.is_tmp, v.file, v.line).as_bytes()) | 1,
            None => 2,
        },
    }
}

/// A stored result for `key`, when its context and every dependency still digest the same.
fn lookup(key: &str, context: u128, sem: &Sem, digests: &Digests) -> Option<Arc<ReadSet>> {
    let why = dq_hostio::var_os("DQ_WALK_WHY").is_some();
    let l = loaded()?;
    let Some((ctx, ds, set)) = l.delta.get(key).or_else(|| l.base.get(key)) else {
        if why {
            eprintln!("analyze: walk cache: miss {}: not stored", key);
        }
        return None;
    };
    if *ctx != context {
        if why {
            eprintln!("analyze: walk cache: miss {}: context", key);
        }
        return None;
    }
    let tv = std::time::Instant::now();
    let _tv = TimeOn(&T_VALIDATE, tv);
    for (id, g) in ds {
        if digests.get(sem, *id) != *g {
            if why {
                eprintln!("analyze: walk cache: miss {}: {:?} changed", key, deps().read().unwrap().get(id));
            }
            return None;
        }
    }
    drop(_tv);
    let td = std::time::Instant::now();
    let r = set.get();
    T_DECODE.fetch_add(td.elapsed().as_micros() as usize, Ordering::Relaxed);
    Some(r)
}

static T_VALIDATE: AtomicUsize = AtomicUsize::new(0);
static T_DECODE: AtomicUsize = AtomicUsize::new(0);

struct TimeOn(&'static AtomicUsize, std::time::Instant);

impl Drop for TimeOn {
    fn drop(&mut self) {
        self.0.fetch_add(self.1.elapsed().as_micros() as usize, Ordering::Relaxed);
    }
}

/// Serves `key` from the store or walks it (recording what it reads) and keeps the result.
pub fn walk(key: impl FnOnce() -> String, context: impl FnOnce() -> u128, sem: &Sem, digests: &Digests, run: impl FnOnce() -> ReadSet) -> Arc<ReadSet> {
    if !enabled() {
        return Arc::new(run());
    }
    let t0 = std::time::Instant::now();
    let key = key();
    let context = context();
    let t1 = std::time::Instant::now();
    let cached = lookup(&key, context, sem, digests);
    T_CTX.fetch_add((t1 - t0).as_micros() as usize, Ordering::Relaxed);
    T_LOOKUP.fetch_add(t1.elapsed().as_micros() as usize, Ordering::Relaxed);
    if let Some(c) = cached {
        if !verify() {
            HITS.fetch_add(1, Ordering::Relaxed);
            return c;
        }
        return walk_verify(key, c, run);
    }
    push_frame();
    let set = Arc::new(run());
    let ids = pop_frame();
    MISSES.fetch_add(1, Ordering::Relaxed);
    fresh().lock().unwrap().insert(key, (context, ids, LazySet::of(set.clone())));
    set
}

static T_CTX: AtomicUsize = AtomicUsize::new(0);
static T_LOOKUP: AtomicUsize = AtomicUsize::new(0);

/// `DQ_WALK_VERIFY`: walks a served key anyway and counts a difference.
fn walk_verify(key: String, cached: Arc<ReadSet>, run: impl FnOnce() -> ReadSet) -> Arc<ReadSet> {
    push_frame();
    let set = run();
    let _ = pop_frame();
    HITS.fetch_add(1, Ordering::Relaxed);
    let a = bincode::serialize(&*cached).unwrap_or_default();
    let b = bincode::serialize(&set).unwrap_or_default();
    if a != b {
        DIFFERED.fetch_add(1, Ordering::Relaxed);
        eprintln!("analyze: walk cache: VERIFY: stored result of {} differs from a fresh walk", key);
    }
    Arc::new(set)
}

static DIGESTS: crate::host::RunCell<Digests> = crate::host::RunCell::new();
static MODEL: crate::host::RunCell<std::sync::Arc<super::SemBox>> = crate::host::RunCell::new();

/// The run's dependency digests (one full model per process).
pub fn digests() -> &'static Digests {
    DIGESTS.get_or_init(Digests::new)
}

/// Remembers the run's full model, for [`finish`].
pub(crate) fn set_model(b: std::sync::Arc<super::SemBox>) {
    let _ = MODEL.set(b);
}

type Row<'a> = (&'a str, u128, Vec<u64>, &'a LazySet);

fn write(path: &std::path::Path, entries: &[Row<'_>], sem: &Sem) -> usize {
    let digests = digests();
    let table = deps().read().unwrap();
    let mut index: HashMap<u64, u32> = HashMap::new();
    let mut st = StoredRef { engine: engine(), deps: Vec::new(), entries: Vec::with_capacity(entries.len()) };
    for (key, context, ids, set) in entries {
        let mut idx = Vec::with_capacity(ids.len());
        let mut complete = true;
        for id in ids {
            let i = match index.get(id) {
                Some(i) => *i,
                None => {
                    let Some(d) = table.get(id) else {
                        complete = false;
                        break;
                    };
                    let i = st.deps.len() as u32;
                    st.deps.push((d.clone(), digests.get(sem, *id)));
                    index.insert(*id, i);
                    i
                }
            };
            idx.push(i);
        }
        if complete {
            st.entries.push(EntryRef { key, context: *context, deps: idx, set });
        }
    }
    drop(table);
    let n = st.entries.len();
    if let Ok(bytes) = crate::incr::ser(&st) {
        let tmp = path.with_extension(format!("tmp{}", std::process::id()));
        if std::fs::write(&tmp, &bytes).is_ok() && std::fs::rename(&tmp, path).is_err() {
            let _ = std::fs::remove_file(&tmp);
        }
        std::mem::forget(bytes);
    }
    std::mem::forget(st);
    n
}

/// Writes the walks of this run back (called before the process exits; nothing when every walk was served).
pub fn finish() {
    let (hits, misses) = (HITS.load(Ordering::Relaxed), MISSES.load(Ordering::Relaxed));
    if trace() && hits + misses > 0 {
        eprintln!("analyze: walk cache: context {} ms, lookups {} ms (validate {} ms, decode {} ms; summed over threads)", T_CTX.load(Ordering::Relaxed) / 1000, T_LOOKUP.load(Ordering::Relaxed) / 1000, T_VALIDATE.load(Ordering::Relaxed) / 1000, T_DECODE.load(Ordering::Relaxed) / 1000);
        eprintln!("analyze: walk cache: {} walks served, {} walked{}", hits, misses, if verify() { format!(", {} differed", DIFFERED.load(Ordering::Relaxed)) } else { String::new() });
    }
    let Some(dir) = crate::incr::dir() else { return };
    if misses == 0 {
        keep(&dir, HashMap::new());
        return;
    }
    let Some(sem) = MODEL.get().and_then(|b| b.sem.as_ref()) else { return };
    let t0 = std::time::Instant::now();
    let fresh = std::mem::take(&mut *fresh().lock().unwrap());
    if keep_resident() {
        let digests = digests();
        let kept: HashMap<String, Kept> =
            fresh.iter().map(|(k, (c, ids, set))| (k.clone(), (*c, ids.iter().map(|id| (*id, digests.get(sem, *id))).collect(), set.clone()))).collect();
        keep(&dir, kept);
    }
    let digests = digests();
    let empty = Loaded { base: HashMap::new(), delta: HashMap::new() };
    let l = loaded().unwrap_or(&empty);
    // A stored walk stays while everything it read digests as it did; this run's walks replace theirs.
    let valid = |ds: &[(u64, u64)]| ds.iter().all(|(id, g)| digests.get(sem, *id) == *g);
    let mut delta: Vec<Row<'_>> = Vec::new();
    for (k, (c, ds, set)) in &l.delta {
        if !fresh.contains_key(k) && valid(ds) {
            delta.push((k.as_str(), *c, ds.iter().map(|(id, _)| *id).collect(), set));
        }
    }
    for (k, (c, ids, set)) in &fresh {
        delta.push((k.as_str(), *c, ids.clone(), set));
    }
    delta.sort_by(|a, b| a.0.cmp(b.0));
    let rebase = l.base.is_empty() || delta.len() * 4 > l.base.len();
    let (what, n) = if rebase {
        let mut all = delta;
        let have: HashSet<&str> = all.iter().map(|e| e.0).collect();
        let mut more: Vec<Row<'_>> = Vec::new();
        for (k, (c, ds, set)) in &l.base {
            if !have.contains(k.as_str()) && valid(ds) {
                more.push((k.as_str(), *c, ds.iter().map(|(id, _)| *id).collect(), set));
            }
        }
        all.extend(more);
        all.sort_by(|a, b| a.0.cmp(b.0));
        let n = write(&dir.join(FILE), &all, sem);
        let _ = std::fs::remove_file(dir.join(DELTA));
        std::mem::forget(all);
        ("base", n)
    } else {
        let n = write(&dir.join(DELTA), &delta, sem);
        std::mem::forget(delta);
        ("delta", n)
    };
    std::mem::forget(fresh);
    if trace() {
        eprintln!("analyze: walk cache: wrote the {} ({} walks) in {:.1?}", what, n, t0.elapsed());
    }
}

/// Folds this run's walks (`fresh`, with their digests) into the store this run read and keeps it decoded for the next run of `dir`
/// (hosted only). A stored walk is kept as it is: it is validated when a later run asks for it.
fn keep(dir: &std::path::Path, fresh: HashMap<String, Kept>) {
    if !keep_resident() || !enabled() {
        return;
    }
    let t0 = std::time::Instant::now();
    let mut walks: HashMap<String, Kept> = HashMap::new();
    if let Some(l) = loaded() {
        walks.reserve(l.base.len() + l.delta.len() + fresh.len());
        for (k, v) in l.base.iter().chain(l.delta.iter()) {
            walks.insert(k.clone(), v.clone());
        }
    }
    let n_fresh = fresh.len();
    walks.extend(fresh);
    let table = deps().read().unwrap().clone();
    let n = walks.len();
    *RESIDENT.lock().unwrap_or_else(|e| e.into_inner()) = Some(Resident { dir: dir.to_path_buf(), engine: engine(), deps: table, walks });
    if trace() {
        eprintln!("analyze: walk cache: kept {} walks in memory ({} new) in {:.1?}", n, n_fresh, t0.elapsed());
    }
}

/// Lets go of the run's model (the end of a hosted run hands it to `model_store::keep_resident`).
pub(crate) fn release_model() {
    crate::host::clear(&MODEL);
}

/// Run state for `crate::host::reset_run_state`.
pub(crate) fn reset() {
    crate::host::clear(&DEPS);
    crate::host::clear(&LOADED);
    crate::host::clear(&FRESH);
    crate::host::clear(&DIGESTS);
    crate::host::clear(&MODEL);
    for c in [&HITS, &MISSES, &DIFFERED, &T_VALIDATE, &T_DECODE, &T_CTX, &T_LOOKUP] {
        c.store(0, Ordering::Relaxed);
    }
}
