//! Physical sharing only: exact observation equality is required, never a token.
//! Weak entries do not retain receipts after their ordinary artifact owners drop.
use super::Observation;
use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex, Weak},
};
const MAX_CANDIDATES: usize = 8;
type Groups<Q, A, D> = BTreeMap<(Q, usize), Vec<Weak<[Observation<Q, A, D>]>>>;
pub struct ReceiptGroupPool<Q, A, D> {
    groups: Mutex<Groups<Q, A, D>>,
}
impl<Q, A, D> Default for ReceiptGroupPool<Q, A, D> {
    fn default() -> Self {
        Self {
            groups: Mutex::new(BTreeMap::new()),
        }
    }
}
impl<Q: Ord + Clone, A: Eq, D: Eq> ReceiptGroupPool<Q, A, D> {
    /// Locators select candidates only. Query, domain and every answer must match.
    /// Empty leaves bypass the index. Callers preserve canonical group ordering.
    pub fn intern(&self, reads: Vec<Observation<Q, A, D>>) -> Arc<[Observation<Q, A, D>]> {
        let Some(first) = reads.first() else {
            return reads.into();
        };
        let key = (first.query.clone(), reads.len());
        let mut groups = self
            .groups
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let bucket = groups.entry(key).or_default();
        bucket.retain(|owner| owner.strong_count() != 0);
        for candidate in bucket.iter().filter_map(Weak::upgrade) {
            if candidate.as_ref() == reads.as_slice() {
                return candidate;
            }
        }
        // Sharing is optional. Bound both exact candidate scans and retained
        // weak descriptors; collision overflow remains an ordinary fresh leaf.
        if bucket.len() >= MAX_CANDIDATES {
            return reads.into();
        }
        let owner: Arc<[_]> = reads.into();
        bucket.push(Arc::downgrade(&owner));
        owner
    }
    /// Explicit lifecycle cleanup for dead physical locators; never hot replay.
    pub fn prune(&self) {
        self.groups
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .retain(|_, bucket| {
                bucket.retain(|owner| owner.strong_count() != 0);
                !bucket.is_empty()
            });
    }
    /// Exact Vec backing; BTree keys/node capacity remains private overhead.
    pub fn visit_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        let groups = self
            .groups
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        for bucket in groups.values() {
            let size = std::mem::size_of::<Weak<[Observation<Q, A, D>]>>();
            visit(
                bucket.as_ptr() as usize,
                bucket.len().saturating_mul(size),
                bucket.capacity().saturating_mul(size),
            );
        }
    }
}
