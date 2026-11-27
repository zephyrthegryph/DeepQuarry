//! Running analyze more than once in one process (the dmbc daemon hosts it: `dmbc analyze` sends its request there).
//!
//! analyze was written as one run per process: its run state lives in statics. A hosted request must start from the state a fresh
//! process starts from, so every static that a run fills is either a [`RunCell`] or cleared by [`reset_run_state`]. What stays
//! between requests is only what does not depend on the tree or the run: compiled regex patterns, interned names, the lint
//! registry. Output and environment are per request through `dq_hostio`.
//!
//! The invariant [`reset_run_state`] relies on: no reference into run state outlives the request. A request runs on its own
//! threads (`crate::cli::run_hosted`), which have all finished, and the store writer has been joined, before the reset.

use std::sync::atomic::{AtomicPtr, Ordering};
use std::sync::Mutex;

/// A once-per-run cell: `OnceLock` semantics within a request, emptied by [`reset_run_state`].
pub struct RunCell<T: Send + Sync + 'static> {
    ptr: AtomicPtr<T>,
    init: Mutex<()>,
}

impl<T: Send + Sync + 'static> RunCell<T> {
    pub const fn new() -> Self {
        RunCell { ptr: AtomicPtr::new(std::ptr::null_mut()), init: Mutex::new(()) }
    }

    pub fn get(&self) -> Option<&'static T> {
        let p = self.ptr.load(Ordering::Acquire);
        // SAFETY: a non-null pointer came from `Box::into_raw` and is freed only by `clear`, which runs when no request holds a
        // reference (module invariant).
        (!p.is_null()).then(|| unsafe { &*p })
    }

    pub fn get_or_init(&self, f: impl FnOnce() -> T) -> &'static T {
        if let Some(v) = self.get() {
            return v;
        }
        let _g = self.init.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(v) = self.get() {
            return v;
        }
        let p = Box::into_raw(Box::new(f()));
        self.ptr.store(p, Ordering::Release);
        // SAFETY: as in `get`.
        unsafe { &*p }
    }

    /// `OnceLock::set`: fails when the cell already holds a value.
    pub fn set(&self, v: T) -> Result<(), T> {
        let _g = self.init.lock().unwrap_or_else(|e| e.into_inner());
        if self.get().is_some() {
            return Err(v);
        }
        self.ptr.store(Box::into_raw(Box::new(v)), Ordering::Release);
        Ok(())
    }

    /// Drops the value. Only [`reset_run_state`] calls this.
    fn clear(&self) {
        let p = self.ptr.swap(std::ptr::null_mut(), Ordering::AcqRel);
        if !p.is_null() {
            // SAFETY: the pointer came from `Box::into_raw` and nothing refers to it any more (module invariant).
            drop(unsafe { Box::from_raw(p) });
        }
    }
}

impl<T: Send + Sync + 'static> Default for RunCell<T> {
    fn default() -> Self {
        Self::new()
    }
}

/// Clears what a run left behind, so the next request in this process starts as a fresh process would.
pub fn reset_run_state() {
    crate::cli::reset();
    crate::run::reset();
    crate::incr::reset();
    crate::shared::reset();
    crate::tree::reset();
    crate::util::reset();
    crate::sem::walk_cache::reset();
    crate::sem::procs::reset();
    crate::sem::incremental::reset();
    crate::lints::check_grep::reset();
    dreammaker::objtree::reset_run_state();
}

/// Lets `reset_run_state` clear a run cell from another module.
pub(crate) fn clear<T: Send + Sync + 'static>(cell: &RunCell<T>) {
    cell.clear();
}
