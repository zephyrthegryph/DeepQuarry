//! Whole-tree indexes over every proc body, kept between runs.
//!
//! The global-var index and the write index (`globals.rs`, `reads::WriteIndex`) scan every proc body of the model on every run that builds
//! it. An index is a function of its per-proc facts, and a proc's facts are a function of its body, which is a function of its file's content
//! in the run's macro environment ([`Sem::location_key`]). So `data/analyze-cache/body-<name>.bin` keeps the index with, per file, the
//! content key it was built from and a digest of the facts of the procs in it. A run scans only the procs of the files whose key changed:
//! when their facts digest as before (an edit that changes no call, no global write, no written name), the stored index is the index;
//! otherwise every body is scanned and the index built again. `ctx` names anything else the facts depend on (the global var names, for the
//! global index); `DQ_BODY_FACTS=off` scans every time.

use std::collections::HashMap;

use dreammaker::objtree::ProcRef;
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};

use super::Sem;

#[derive(Serialize, Deserialize)]
struct Store<I> {
    engine: String,
    ctx: u128,
    /// file -> (content key, digest of its procs' facts in order).
    files: HashMap<String, (u128, u128)>,
    index: I,
}

fn digest<T: Serialize>(facts: &[&T]) -> u128 {
    let mut h = blake3::Hasher::new();
    for f in facts {
        h.update(&crate::incr::ser(f).unwrap_or_default());
        h.update(b"|");
    }
    u128::from_le_bytes(h.finalize().as_bytes()[..16].try_into().unwrap())
}

/// `build(facts)` with `facts[i] = fact(procs[i])`: the stored index when the procs of every changed file have the facts they had.
pub fn indexed<T, I>(sem: &Sem, name: &str, ctx: u128, procs: &[ProcRef], fact: impl Fn(ProcRef) -> T + Sync, build: impl FnOnce(Vec<T>) -> I) -> I
where
    T: Serialize + Send,
    I: Serialize + DeserializeOwned,
{
    let dir = crate::incr::dir();
    if !sem.cacheable() || dir.is_none() || matches!(std::env::var("DQ_BODY_FACTS").as_deref(), Ok("off")) {
        return build(super::par_map(procs, |p| fact(*p)));
    }
    let trace = std::env::var_os("DQ_ANALYZE_TRACE").is_some();
    let path = dir.unwrap().join(format!("body-{}.bin", name));
    let engine = crate::cache::ENGINE_HASH.to_string();
    let stored: Option<Store<I>> = std::fs::read(&path).ok().and_then(|b| crate::incr::de::<Store<I>>(&b).ok()).filter(|s| s.engine == engine && s.ctx == ctx);
    // Each proc's file, and each file's key and procs (in `procs` order).
    let mut by_file: HashMap<&str, (u128, Vec<usize>)> = HashMap::new();
    for (i, p) in procs.iter().enumerate() {
        let loc = p.get().location;
        let file = sem.file_of(loc).unwrap_or("");
        by_file.entry(file).or_insert_with(|| (sem.location_key(loc), Vec::new())).1.push(i);
    }
    let save = |s: &Store<I>| {
        if let Ok(bytes) = crate::incr::ser(s) {
            let tmp = path.with_extension(format!("tmp{}", std::process::id()));
            if std::fs::write(&tmp, &bytes).is_ok() && std::fs::rename(&tmp, &path).is_err() {
                let _ = std::fs::remove_file(&tmp);
            }
        }
    };
    if let Some(mut st) = stored {
        let same_set = st.files.len() == by_file.len() && by_file.keys().all(|f| st.files.contains_key(*f));
        if same_set {
            let changed: Vec<&str> = by_file.iter().filter(|(f, (k, _))| st.files[**f].0 != *k).map(|(f, _)| *f).collect();
            if changed.is_empty() {
                return st.index;
            }
            let idx: Vec<usize> = changed.iter().flat_map(|f| by_file[f].1.iter().copied()).collect();
            let made: Vec<T> = super::par_map(&idx, |&i| fact(procs[i]));
            let mut at = 0;
            let mut same = true;
            let mut digests: Vec<(&str, u128)> = Vec::new();
            for f in &changed {
                let n = by_file[f].1.len();
                let d = digest(&made[at..at + n].iter().collect::<Vec<_>>());
                at += n;
                if d != st.files[*f].1 {
                    same = false;
                    break;
                }
                digests.push((f, d));
            }
            if same {
                for (f, _) in digests {
                    st.files.get_mut(f).expect("in the set").0 = by_file[f].0;
                }
                save(&st);
                if trace {
                    eprintln!("analyze: body index {}: {} file(s) rescanned, facts unchanged: index kept", name, changed.len());
                }
                return st.index;
            }
            if trace {
                eprintln!("analyze: body index {}: a changed file's facts differ: rebuilt", name);
            }
        }
    }
    let facts: Vec<T> = super::par_map(procs, |p| fact(*p));
    let mut files: HashMap<String, (u128, u128)> = HashMap::new();
    for (f, (k, idx)) in &by_file {
        files.insert(f.to_string(), (*k, digest(&idx.iter().map(|&i| &facts[i]).collect::<Vec<_>>())));
    }
    let index = build(facts);
    let st = Store { engine, ctx, files, index };
    save(&st);
    st.index
}
