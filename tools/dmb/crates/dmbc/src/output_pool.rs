//! Finished output images by exact content, shared by the sessions of a daemon.
//!
//! A session retains the encoded `.dmb` it published (about 70 MB for the production world) so the next request can splice
//! into it. Two sessions of the same tree (a second worktree root) encode equal images, and each used to hold its own copy.
//! The writer hands every finished image to this pool (`byond_dmb::dmb::set_image_interner`, installed by
//! `shared_store::activate`): an image equal to one another session still holds becomes that allocation. The pool is weak
//! (it keeps nothing alive) and keyed by the content digest the writer computed; the bytes themselves decide a hit, so a
//! digest collision cannot alias two images. A one-shot compile or a unit test never installs it.
use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock, Weak};

static POOL: OnceLock<Mutex<HashMap<u128, Weak<Vec<u8>>>>> = OnceLock::new();

/// `bytes` itself, or the live allocation equal to it.
pub(crate) fn intern(bytes: Arc<Vec<u8>>, content_hash: u128) -> Arc<Vec<u8>> {
    let mut pool = POOL
        .get_or_init(Default::default)
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    if let Some(held) = pool.get(&content_hash).and_then(Weak::upgrade) {
        if Arc::ptr_eq(&held, &bytes) || *held == *bytes {
            return held;
        }
        return bytes;
    }
    pool.insert(content_hash, Arc::downgrade(&bytes));
    if pool.len() > 64 {
        pool.retain(|_, held| held.strong_count() > 0);
    }
    bytes
}
