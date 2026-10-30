//! Same legacy sharded plumbing, independent of ownership Index/model.
use crate::{incr,tree::SourceFile};
use rayon::prelude::*;
use serde::{Serialize,de::DeserializeOwned};
/// How many stores a sharded cache is split into.
const SHARDS: usize = 16;

fn shard_of(rel: &str) -> usize {
    let mut h: u32 = 0x811c_9dc5;
    for b in rel.bytes() {
        h = (h ^ b as u32).wrapping_mul(0x0100_0193);
    }
    h as usize % SHARDS
}

/// [`crate::incr::keyed`] over [`SHARDS`] stores, by path hash. One edit rewrites one small store instead of
/// the whole set, and the stores load in parallel. Results are in `files` order. ALLOW uses recorded
/// through `sys::kept_recorded` are carried back to the calling thread.
pub fn sharded_keyed<R>(
    name: &str,
    ctx: u128,
    files: &[&SourceFile],
    f: impl Fn(&SourceFile) -> R + Sync,
) -> Vec<R>
where
    R: Serialize + DeserializeOwned + Default + PartialEq + Send,
{
    let scope=super::captured::inputs(files);
    let mut groups: Vec<Vec<usize>> = vec![Vec::new(); SHARDS];
    for (i, file) in files.iter().enumerate() {
        groups[shard_of(&file.rel)].push(i);
    }
    let compute=|(s,idxs):(usize,&Vec<usize>)|{
            let part: Vec<&SourceFile> = idxs.iter().map(|&i| files[i]).collect();
            let recording=super::captured::RecordedGuard::new();
            let r = incr::keyed(&format!("{}-{}", name, s), ctx, &part, &f);
            let uses=recording.finish();
            (r, uses)
        };
    let outs:Vec<(Vec<R>,Vec<crate::lint::AllowUse>)>=if scope.is_some(){
        groups.iter().enumerate().map(compute).collect()
    }else{groups.par_iter().enumerate().map(compute).collect()};
    if let Some(scope)=scope.as_ref(){scope.require().unwrap_or_else(|error|panic!("{error}"));}
    let mut slots: Vec<Option<R>> = Vec::with_capacity(files.len());
    slots.resize_with(files.len(), || None);
    let mut all_uses = Vec::new();
    for (idxs, (rs, uses)) in groups.iter().zip(outs) {
        for (&i, r) in idxs.iter().zip(rs) {
            slots[i] = Some(r);
        }
        all_uses.extend(uses);
    }
    crate::dm::sys::replay_recorded(all_uses);
    slots.into_iter().map(|r| r.unwrap_or_default()).collect()
}

/// [`crate::incr::facts`], sharded (see [`sharded_keyed`]).
pub fn sharded_facts<F>(
    name: &str,
    files: &[&SourceFile],
    f: impl Fn(&SourceFile) -> F + Sync,
) -> Vec<F>
where
    F: Serialize + DeserializeOwned + Default + PartialEq + Send,
{
    sharded_keyed(name, 0, files, f)
}


#[cfg(test)]pub(super) fn shard_for_test(rel:&str)->usize{shard_of(rel)}
