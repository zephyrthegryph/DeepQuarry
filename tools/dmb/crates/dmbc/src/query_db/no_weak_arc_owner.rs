//! Private no-Weak std Arc owner. This is resource lifetime work, NOT a custom
//! reference count, alternate semantic value or allocator-layout authority.
use std::{mem::ManuallyDrop, ops::Deref, sync::Arc};
pub(super) struct NoWeakArc<T> {
    inner: ManuallyDrop<Arc<T>>,
}
impl<T> NoWeakArc<T> {
    pub(super) fn same_owner(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.inner, &other.inner)
    }
    pub(super) fn new(value: T) -> Self {
        Self {
            inner: ManuallyDrop::new(Arc::new(value)),
        }
    }
    #[cfg(not(dmb_arc_probe))]
    pub(super) fn census_identity(&self) -> usize {
        Arc::as_ptr(&self.inner) as usize
    }
    #[cfg(not(dmb_arc_probe))]
    pub(super) fn census_layout(
        &self,
        c: &mut crate::heap_census::HeapCensus,
        name: &str,
        layout: std::alloc::Layout,
    ) {
        c.qualified_arc(name, &self.inner, layout);
    }
    #[cfg(not(dmb_arc_probe))]
    pub(super) fn census(&self, c: &mut crate::heap_census::HeapCensus, name: &str) {
        c.arc_object(name, &self.inner);
    }
}
impl<T> Clone for NoWeakArc<T> {
    fn clone(&self) -> Self {
        Self {
            inner: ManuallyDrop::new(Arc::clone(&self.inner)),
        }
    }
}
impl<T> Deref for NoWeakArc<T> {
    type Target = T;
    fn deref(&self) -> &T {
        self.inner.as_ref()
    }
}
impl<T> Drop for NoWeakArc<T> {
    fn drop(&mut self) {
        // EVERY strong owner takes this path and no Weak can be issued. into_inner
        // guarantees exactly one winner even with concurrent last drops. Unlike
        // try_unwrap(...).ok(), no loser can run ordinary Arc::drop on the payload.
        // Audited std1.99.1 Arc::into_inner explicitly drops its implicit Weak (thus
        // the no-Weak allocation) BEFORE returning T; only then do we drop/recredit T.
        let owner = unsafe { ManuallyDrop::take(&mut self.inner) };
        drop(Arc::into_inner(owner));
    }
}
#[cfg(all(test, not(dmb_arc_probe)))]
mod tests {
    use super::*;
    use crate::query_db::source_allocation::SourceLedger;
    #[test]
    fn concurrent_last_resource_owners_recredit_exactly_once() {
        let ledger = SourceLedger::new(128);
        let first = NoWeakArc::new(ledger.reserve(100).unwrap());
        let second = first.clone();
        let barrier = std::sync::Barrier::new(3);
        std::thread::scope(|scope| {
            let b = &barrier;
            scope.spawn(move || {
                b.wait();
                drop(first);
            });
            let b = &barrier;
            scope.spawn(move || {
                b.wait();
                drop(second);
            });
            barrier.wait();
        });
        assert_eq!(ledger.snapshot().live, 0);
        assert_eq!(ledger.snapshot().reserves, 1);
    }
}
