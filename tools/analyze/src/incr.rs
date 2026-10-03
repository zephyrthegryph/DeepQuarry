//! Per-file incremental caches for whole-tree lints.
//!
//! A whole-tree lint is a fold over per-file facts followed by a per-file judgement that reads the
//! fold. Doing both from scratch on any edit costs seconds; doing them through this module costs
//! one file's worth of work plus a cheap merge:
//!
//! * [`facts`]: `f(file)` cached on disk by the file's content key (path + hash). A pure function of
//!   the one file.
//! * [`keyed`]: `f(file)` that also reads some shared context (an index built from every file's
//!   facts). The context is named by a [`ctx_key`], and the cached results are valid only while the
//!   key is unchanged. A one-line edit that changes no fact leaves the key alone, so every other
//!   file's result is served from disk.
//! * [`two_phase`]: both, wired together: facts, merge, judge.
//!
//! Contract for the closures: deterministic, depend only on the file (via `f.raw()` etc. and
//! `f.rel`) and on what the context key covers. A result type must round-trip through bincode and
//! `Default` must mean "nothing found" (those files cost no space). Results are cached only for
//! the files of the current run; entries for removed or edited files are dropped on save.
//!
//! The store lives beside the lint caches (`data/analyze-cache/incr-<name>.bin`) under the same
//! engine/scope stamp, so a rebuilt engine or an edited scope list can never serve a stale entry.
//! Cache errors are never fatal: a missing or corrupt file is a miss.
//!
//! ALLOW questions asked through `sys::kept_recorded` inside a cached closure are captured with the
//! result and replayed on a hit, so the unused-ALLOW check sees them either way.

use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};

use rayon::prelude::*;
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};

use crate::lint::AllowUse;
use crate::tree::{Hash, SourceFile};

struct Config {
    dir: PathBuf,
    stamp: String,
    enabled: bool,
}

static CONFIG: OnceLock<Mutex<Option<Config>>> = OnceLock::new();

fn cfg() -> &'static Mutex<Option<Config>> {
    CONFIG.get_or_init(|| Mutex::new(None))
}

/// Called by the engine once per run: where the stores live and which stamp they carry.
pub fn configure(dir: PathBuf, stamp: String, enabled: bool) {
    *cfg().lock().unwrap() = Some(Config { dir, stamp, enabled });
}

#[derive(Serialize, Deserialize, Default)]
struct StoreFile {
    stamp: String,
    ctx: Hash,
    /// `fkey` -> bincode of `(R, allow uses)`.
    map: HashMap<Hash, Vec<u8>>,
    /// `fkey`s whose result is `R::default()` with no allow use.
    clean: HashSet<Hash>,
}

fn store_path(dir: &std::path::Path, name: &str, shard: Option<usize>) -> PathBuf {
    let safe: String = name.chars().map(|c| if c.is_ascii_alphanumeric() || c == '-' { c } else { '_' }).collect();
    match shard {
        Some(k) => dir.join(format!("incr-{}.{}.bin", safe, k)),
        None => dir.join(format!("incr-{}.bin", safe)),
    }
}

static SUSPENDED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// Turns the on-disk stores off (selftests run fixture trees through lints that use them: their
/// entries must not replace the real tree's).
pub fn suspend(on: bool) {
    SUSPENDED.store(on, std::sync::atomic::Ordering::SeqCst);
}

fn config() -> Option<(PathBuf, String)> {
    if SUSPENDED.load(std::sync::atomic::Ordering::SeqCst) {
        return None;
    }
    let g = cfg().lock().unwrap();
    g.as_ref().filter(|c| c.enabled).map(|c| (c.dir.clone(), c.stamp.clone()))
}

fn load_at(path: &std::path::Path, stamp: &str, ctx: Hash) -> StoreFile {
    let loaded = std::fs::read(path).ok().and_then(|b| de::<StoreFile>(&b).ok());
    match loaded {
        Some(s) if s.stamp == stamp && s.ctx == ctx => s,
        _ => StoreFile { stamp: stamp.to_string(), ctx, ..Default::default() },
    }
}

fn load(name: &str, ctx: Hash) -> (StoreFile, Option<(PathBuf, String)>) {
    let Some((dir, stamp)) = config() else { return (StoreFile::default(), None) };
    let path = store_path(&dir, name, None);
    let st = load_at(&path, &stamp, ctx);
    (st, Some((path, stamp)))
}

fn save(path: &std::path::Path, st: &StoreFile) {
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    if let Ok(bytes) = ser(st) {
        let tmp = path.with_extension(format!("tmp{}", std::process::id()));
        if std::fs::write(&tmp, &bytes).is_ok() {
            let _ = std::fs::rename(&tmp, path);
        } else {
            let _ = std::fs::remove_file(&tmp);
        }
    }
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

/// The cache directory of this run, when caching is on.
pub fn dir() -> Option<PathBuf> {
    config().map(|c| c.0)
}

/// The engine/scope stamp of this run, when caching is on.
pub fn stamp() -> Option<String> {
    config().map(|c| c.1)
}

/// One value cached under `key`: `compute()` runs only when the stored key differs.
pub fn cached<T: Serialize + DeserializeOwned>(name: &str, key: Hash, compute: impl FnOnce() -> T) -> T {
    let (st, target) = load(name, key);
    if let Some(b) = st.map.get(&0) {
        if let Ok(v) = de::<T>(b) {
            return v;
        }
    }
    let v = compute();
    if let (Some((path, _)), Ok(b)) = (target, ser(&v)) {
        let mut st = st;
        st.map.clear();
        st.map.insert(0, b);
        save(&path, &st);
    }
    v
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

/// A store this large is split in [`SHARDS`] files by file-key hash: an edit rewrites one small shard,
/// and the shards load in parallel.
const SHARDS: usize = 16;
const SHARD_MIN_FILES: usize = 1024;

fn shard_of(k: Hash) -> usize {
    ((k ^ (k >> 64)) as usize) % SHARDS
}

/// `f(file)` for every file, cached per file under `ctx`. See the module docs.
pub fn keyed<R>(name: &str, ctx: Hash, files: &[&SourceFile], f: impl Fn(&SourceFile) -> R + Sync) -> Vec<R>
where
    R: Serialize + DeserializeOwned + Default + PartialEq + Send,
{
    let sharded = files.len() >= SHARD_MIN_FILES;
    let n = if sharded { SHARDS } else { 1 };
    let target = config();
    let mut stores: Vec<StoreFile> = match &target {
        None => (0..n).map(|_| StoreFile::default()).collect(),
        Some((dir, stamp)) => (0..n)
            .into_par_iter()
            .map(|k| load_at(&store_path(dir, name, if sharded { Some(k) } else { None }), stamp, ctx))
            .collect(),
    };
    let shard = |file: &SourceFile| if sharded { shard_of(file.fkey) } else { 0 };
    let mut uses: Vec<AllowUse> = Vec::new();
    let results: Vec<(R, bool, Vec<AllowUse>)> = files
        .par_iter()
        .map(|file| {
            let st = &stores[shard(file)];
            if st.clean.contains(&file.fkey) {
                return (R::default(), false, Vec::new());
            }
            if let Some(b) = st.map.get(&file.fkey) {
                if let Ok((r, u)) = de::<(R, Vec<AllowUse>)>(b) {
                    return (r, false, u);
                }
            }
            let before = crate::dm::sys::take_recorded();
            let r = f(file);
            let u = crate::dm::sys::take_recorded();
            crate::dm::sys::restore_recorded(before);
            (r, true, u)
        })
        .collect();
    let before: Vec<usize> = stores.iter().map(|s| s.map.len() + s.clean.len()).collect();
    let mut dirty = vec![false; n];
    let mut maps: Vec<HashMap<Hash, Vec<u8>>> = (0..n).map(|_| HashMap::new()).collect();
    let mut cleans: Vec<HashSet<Hash>> = (0..n).map(|_| HashSet::new()).collect();
    let mut out = Vec::with_capacity(results.len());
    for (file, (r, was_fresh, u)) in files.iter().zip(results) {
        let k = shard(file);
        dirty[k] |= was_fresh;
        if r == R::default() && u.is_empty() {
            cleans[k].insert(file.fkey);
        } else if !was_fresh {
            // Served from the store: keep its bytes as they are.
            if let Some(b) = stores[k].map.remove(&file.fkey) {
                maps[k].insert(file.fkey, b);
            }
        } else if let Ok(b) = ser(&(&r, &u)) {
            maps[k].insert(file.fkey, b);
        }
        uses.extend(u);
        out.push(r);
    }
    if let Some((dir, _)) = &target {
        for k in 0..n {
            if dirty[k] || maps[k].len() + cleans[k].len() != before[k] {
                stores[k].map = std::mem::take(&mut maps[k]);
                stores[k].clean = std::mem::take(&mut cleans[k]);
                save(&store_path(dir, name, if sharded { Some(k) } else { None }), &stores[k]);
            }
        }
    }
    crate::dm::sys::replay_recorded(uses);
    out
}

/// Per-file facts: `f(file)` cached by content alone.
pub fn facts<F>(name: &str, files: &[&SourceFile], f: impl Fn(&SourceFile) -> F + Sync) -> Vec<F>
where
    F: Serialize + DeserializeOwned + Default + PartialEq + Send,
{
    keyed(name, 0, files, f)
}

/// Facts, merge, judge. `merge` receives the facts in `files` order; the judge reads the merged
/// index. The judge's results are cached while the facts' key (every non-empty fact, in order)
/// is unchanged.
pub fn two_phase<F, I, R>(
    name: &str,
    files: &[&SourceFile],
    facts_fn: impl Fn(&SourceFile) -> F + Sync,
    merge: impl FnOnce(&[(&SourceFile, &F)]) -> I,
    judge: impl Fn(&SourceFile, &I) -> R + Sync,
) -> (I, Vec<R>)
where
    F: Serialize + DeserializeOwned + Default + PartialEq + Send + Sync,
    I: Sync,
    R: Serialize + DeserializeOwned + Default + PartialEq + Send,
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
