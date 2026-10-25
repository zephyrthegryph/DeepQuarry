//! Procedure words by exact content, shared by the sessions of a daemon.
//!
//! The linked, wired and stripped words of a procedure are a pure function of its symbolic code and the numeric
//! assignments of the tables it was linked against, so two sessions of the same tree (a second worktree, the game and the
//! test variant) produce equal words for most procedures. Each used to hold its own copy; an image made here is interned,
//! so equal words are one allocation and the wire cache of a shared artifact, which hits on the identity of its base
//! words, hits across sessions too. The pool is weak (it keeps nothing alive) and exists only in a daemon
//! (`shared_store::activate`): a one-shot compile or a unit test has one session and keeps its words private.
use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock, Weak};

const SHARDS: usize = 64;
struct Shard {
    words: HashMap<u128, Weak<Vec<u32>>>,
    /// Length at which the shard next drops its dead entries.
    prune_at: usize,
}
pub(crate) struct ImagePool {
    shards: Box<[Mutex<Shard>]>,
}
impl ImagePool {
    pub(crate) fn new() -> Self {
        Self {
            shards: (0..SHARDS)
                .map(|_| {
                    Mutex::new(Shard {
                        words: HashMap::new(),
                        prune_at: 4096,
                    })
                })
                .collect(),
        }
    }
    fn digest(words: &[u32]) -> u128 {
        // SAFETY: a `u32` slice is `len * 4` initialized bytes with no padding; the bytes only feed a hash.
        let bytes = unsafe {
            std::slice::from_raw_parts(words.as_ptr().cast::<u8>(), std::mem::size_of_val(words))
        };
        xxhash_rust::xxh3::xxh3_128(bytes)
    }
    /// The pooled allocation equal to `words`, or `words` itself (now pooled).
    pub(crate) fn intern(&self, words: Arc<Vec<u32>>) -> Arc<Vec<u32>> {
        if words.is_empty() {
            return words;
        }
        let digest = Self::digest(&words);
        let mut shard = self.shards[(digest as usize) % SHARDS]
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if let Some(held) = shard.words.get(&digest).and_then(Weak::upgrade) {
            // The digest names the words; the words themselves decide.
            if Arc::ptr_eq(&held, &words) || *held == *words {
                return held;
            }
            return words;
        }
        shard.words.insert(digest, Arc::downgrade(&words));
        if shard.words.len() >= shard.prune_at {
            shard.words.retain(|_, held| held.strong_count() > 0);
            shard.prune_at = (shard.words.len() * 2).max(4096);
        }
        words
    }
}
/// The daemon's pool; none in a process with no daemon store.
fn daemon_pool() -> Option<&'static ImagePool> {
    crate::shared_store::active()?;
    static POOL: OnceLock<ImagePool> = OnceLock::new();
    Some(POOL.get_or_init(ImagePool::new))
}
/// `words` interned in the daemon's pool (unchanged without one).
pub(crate) fn intern_words(words: Arc<Vec<u32>>) -> Arc<Vec<u32>> {
    match daemon_pool() {
        Some(pool) => pool.intern(words),
        None => words,
    }
}
/// `image` with its words interned.
pub(crate) fn intern(image: super::ProcedureImage) -> super::ProcedureImage {
    super::ProcedureImage {
        words: intern_words(image.words),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn equal_words_are_one_allocation_while_any_holder_lives() {
        let pool = ImagePool::new();
        let first = pool.intern(Arc::new(vec![1, 2, 3, 4_000_001]));
        let second = pool.intern(Arc::new(vec![1, 2, 3, 4_000_001]));
        assert!(Arc::ptr_eq(&first, &second));
        let other = pool.intern(Arc::new(vec![1, 2, 3, 4_000_002]));
        assert!(!Arc::ptr_eq(&first, &other));
        drop((first, second));
        let again = pool.intern(Arc::new(vec![1, 2, 3, 4_000_001]));
        assert_eq!(*again, [1, 2, 3, 4_000_001]);
        assert!(pool.intern(Arc::new(Vec::new())).is_empty());
    }
    #[test]
    fn no_daemon_store_keeps_words_private() {
        let words = Arc::new(vec![9, 9, 9]);
        let same = intern_words(Arc::clone(&words));
        assert!(Arc::ptr_eq(&words, &same));
        assert!(daemon_pool().is_none(), "unit tests never activate a shared store");
    }
}
