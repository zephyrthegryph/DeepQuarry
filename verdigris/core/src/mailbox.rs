//! A lock-free single-slot mailbox that always holds the newest value.
//!
//! This is how a worker publishes a view (§3.3) and how a finished frame
//! hands its world back: the writer [`put`](Latest::put)s, the reader
//! [`take`](Latest::take)s, and both are one atomic swap. Neither side ever
//! waits for the other, so a reader on the DM thread never blocks on a
//! writer (§3.1, §3.8). A value put while an older one is still unread
//! replaces it; the older one is dropped by the writer.

use std::marker::PhantomData;
use std::ptr;
use std::sync::atomic::{AtomicPtr, Ordering};

pub struct Latest<T> {
    ptr: AtomicPtr<T>,
    _owns: PhantomData<Box<T>>,
}

// SAFETY: the slot only moves owned `T`s between threads, like a channel.
unsafe impl<T: Send> Send for Latest<T> {}
// SAFETY: every access is a single atomic swap that transfers exclusive
// ownership of the pointed-to box; no `&T` is ever shared through it.
unsafe impl<T: Send> Sync for Latest<T> {}

impl<T> Default for Latest<T> {
    fn default() -> Self {
        Self::new()
    }
}

impl<T> Latest<T> {
    #[must_use]
    pub const fn new() -> Self {
        Self {
            ptr: AtomicPtr::new(ptr::null_mut()),
            _owns: PhantomData,
        }
    }

    /// Stores `value`, replacing (and dropping) any unread value. Returns
    /// `true` if an unread value was replaced.
    pub fn put(&self, value: T) -> bool {
        let new = Box::into_raw(Box::new(value));
        let old = self.ptr.swap(new, Ordering::AcqRel);
        if old.is_null() {
            false
        } else {
            // SAFETY: `old` came from `Box::into_raw` in a previous `put`,
            // and the swap removed it from the slot, so we own it.
            drop(unsafe { Box::from_raw(old) });
            true
        }
    }

    /// Takes the newest value, leaving the slot empty.
    pub fn take(&self) -> Option<T> {
        let old = self.ptr.swap(ptr::null_mut(), Ordering::AcqRel);
        if old.is_null() {
            None
        } else {
            // SAFETY: as in `put`: the swap transferred ownership to us.
            Some(*unsafe { Box::from_raw(old) })
        }
    }

    /// Whether a value is waiting. Only a hint: the other side may race it.
    #[must_use]
    pub fn is_full(&self) -> bool {
        !self.ptr.load(Ordering::Acquire).is_null()
    }
}

impl<T> Drop for Latest<T> {
    fn drop(&mut self) {
        drop(self.take());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    #[test]
    fn keeps_only_the_newest() {
        let slot = Latest::new();
        assert!(!slot.put(1));
        assert!(slot.put(2));
        assert!(slot.is_full());
        assert_eq!(slot.take(), Some(2));
        assert_eq!(slot.take(), None);
    }

    #[test]
    fn concurrent_put_take_never_loses_the_last_value() {
        let slot = Arc::new(Latest::new());
        let writer = {
            let slot = Arc::clone(&slot);
            std::thread::spawn(move || {
                for i in 0..100_000u32 {
                    slot.put(i);
                }
            })
        };
        let mut last = None;
        while !writer.is_finished() {
            if let Some(v) = slot.take() {
                assert!(last.is_none_or(|l| v > l), "values arrive in order");
                last = Some(v);
            }
        }
        writer.join().unwrap();
        if let Some(v) = slot.take() {
            last = Some(v);
        }
        assert_eq!(last, Some(99_999));
    }
}
