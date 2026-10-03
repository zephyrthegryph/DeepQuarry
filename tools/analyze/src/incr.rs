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

fn store_path(dir: &std::path::Path, name: &str) -> PathBuf {
    let safe: String = name.chars().map(|c| if c.is_ascii_alphanumeric() || c == '-' { c } else { '_' }).collect();
    dir.join(format!("incr-{}.bin", safe))
}

fn load(name: &str, ctx: Hash) -> (StoreFile, Option<(PathBuf, String)>) {
    let g = cfg().lock().unwrap();
    let Some(c) = g.as_ref() else { return (StoreFile::default(), None) };
    if !c.enabled {
        return (StoreFile::default(), None);
    }
    let path = store_path(&c.dir, name);
    let loaded = std::fs::read(&path).ok().and_then(|b| bincode::deserialize::<StoreFile>(&b).ok());
    let st = match loaded {
        Some(s) if s.stamp == c.stamp && s.ctx == ctx => s,
        _ => StoreFile { stamp: c.stamp.clone(), ctx, ..Default::default() },
    };
    (st, Some((path, c.stamp.clone())))
}

fn save(path: &std::path::Path, st: &StoreFile) {
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    if let Ok(bytes) = bincode::serialize(st) {
        let tmp = path.with_extension(format!("tmp{}", std::process::id()));
        if std::fs::write(&tmp, &bytes).is_ok() {
            let _ = std::fs::rename(&tmp, path);
        } else {
            let _ = std::fs::remove_file(&tmp);
        }
    }
}

/// A 128-bit key of any serializable value (a merged index, a list of facts).
pub fn ctx_key<T: Serialize + ?Sized>(v: &T) -> Hash {
    let bytes = bincode::serialize(v).unwrap_or_default();
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

/// `f(file)` for every file, cached per file under `ctx`. See the module docs.
pub fn keyed<R>(name: &str, ctx: Hash, files: &[&SourceFile], f: impl Fn(&SourceFile) -> R + Sync) -> Vec<R>
where
    R: Serialize + DeserializeOwned + Default + PartialEq + Send,
{
    let (mut st, target) = load(name, ctx);
    let mut uses: Vec<AllowUse> = Vec::new();
    let results: Vec<(R, bool, Vec<AllowUse>)> = files
        .par_iter()
        .map(|file| {
            if st.clean.contains(&file.fkey) {
                return (R::default(), false, Vec::new());
            }
            if let Some(b) = st.map.get(&file.fkey) {
                if let Ok((r, u)) = bincode::deserialize::<(R, Vec<AllowUse>)>(b) {
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
    let before = st.map.len() + st.clean.len();
    let mut fresh = false;
    let mut map: HashMap<Hash, Vec<u8>> = HashMap::new();
    let mut clean: HashSet<Hash> = HashSet::new();
    let mut out = Vec::with_capacity(results.len());
    for (file, (r, was_fresh, u)) in files.iter().zip(results) {
        fresh |= was_fresh;
        if r == R::default() && u.is_empty() {
            clean.insert(file.fkey);
        } else if !was_fresh {
            // Served from the store: keep its bytes as they are.
            if let Some(b) = st.map.remove(&file.fkey) {
                map.insert(file.fkey, b);
            }
        } else if let Ok(b) = bincode::serialize(&(&r, &u)) {
            map.insert(file.fkey, b);
        }
        uses.extend(u);
        out.push(r);
    }
    if let Some((path, _)) = target {
        if fresh || map.len() + clean.len() != before {
            st.map = map;
            st.clean = clean;
            save(&path, &st);
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
