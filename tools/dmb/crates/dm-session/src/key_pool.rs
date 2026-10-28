//! Artifact keys by content, shared by every session of a daemon.
//!
//! A session builds the key bytes of each unit it asks the artifact cores about, and keeps them (rosters, location memos). Two
//! sessions over equal inputs (a second worktree, the game and test variants) build equal bytes, and each used to hold its
//! own copy. [`share`] returns the live allocation equal to `key`. The pool is weak, keeps nothing alive, and a hit is
//! decided by the bytes. A process that never calls [`enable`] (a one-shot compile, a unit test) keeps private keys.
use std::{
    collections::HashMap,
    sync::{Arc, Mutex, OnceLock, Weak},
};

static ENABLED: OnceLock<()> = OnceLock::new();
static POOL: Mutex<Option<HashMap<u128, Weak<[u8]>>>> = Mutex::new(None);

pub fn enable() {
    let _ = ENABLED.set(());
}
pub fn share(key: Arc<[u8]>) -> Arc<[u8]> {
    if ENABLED.get().is_none() {
        return key;
    }
    let digest = xxhash_rust::xxh3::xxh3_128(&key);
    let mut pool = POOL.lock().unwrap_or_else(|error| error.into_inner());
    let pool = pool.get_or_insert_with(Default::default);
    if let Some(held) = pool.get(&digest).and_then(Weak::upgrade) {
        if *held == *key {
            return held;
        }
        return key;
    }
    pool.insert(digest, Arc::downgrade(&key));
    if pool.len() > 4096 && pool.len().is_power_of_two() {
        pool.retain(|_, held| held.strong_count() > 0);
    }
    key
}
