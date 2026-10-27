//! Immutable result ownership with budgeted or current-revision retention.
use crate::{
    observations::{Observation, ObservationHost, Receipt},
    ResolverRead,
};
#[cfg(test)]
use dm_ir::Resolver;
use dm_ir::{ReadDomain, ResolveQuery, ResolvedMeaning};
use std::{
    collections::BTreeMap,
    sync::Arc,
};
mod certified;
#[cfg(test)]
mod certified_tests;
pub use certified::{UnchangedCandidate, UnchangedCandidates};
mod borrowed_lookup;
mod storage_accounting;
pub use storage_accounting::{
    ArtifactStorageAccounting, ArtifactStorageCoverage,
    ArtifactStorageExclusion,
};
mod leased;
mod pressure;
pub use pressure::{PressureAllocation, PressurePrune};
#[cfg(test)]
mod payload_validation_tests;
pub use leased::ObservedArtifactLease;
pub const DEFAULT_RESIDENT_BYTES: usize = 8 * 1024 * 1024;
/// Exact key/read acceptance issued by this store; the ledger shares its backing.
pub struct ObservedArtifact<T, Q, A, D> {
    pub value: Arc<T>,
    pub reads: Receipt<Q, A, D>,
    weight: usize,
}

/// Diagnostic-only borrowed storage. Bucket bytes are exposed Vec allocations;
/// BTree nodes/control blocks are deliberately not represented as exact bytes.
pub enum ObservedArtifactStorageView<'a, T, Q, A, D> {
    Store {
        buckets: usize,
        entries: usize,
    },
    Bucket {
        address: usize,
        len: usize,
        capacity: usize,
        element_size: usize,
    },
    Entry {
        key: &'a Arc<[u8]>,
        reads: &'a Receipt<Q, A, D>,
        value: &'a Arc<T>,
    },
}
#[derive(Clone)]
struct Variant<T, Q = ResolveQuery, A = ResolvedMeaning, D = ReadDomain> {
    key: Arc<[u8]>,
    reads: Receipt<Q, A, D>,
    value: Arc<T>,
    weight: usize,
    /// The leases claiming this variant, one bit per lease slot. A lease's roster is the set of variants naming its slot
    /// (at most one per exact key), so rosters cost one bit per claim instead of a map entry per lease and key.
    holders: leased::Holders,
}
/// The variants of one hash. Almost every hash holds exactly one, which is stored inline instead of in a vector of its own.
pub(super) enum Bucket<V> {
    Empty,
    One(V),
    Many(Vec<V>),
}
impl<V> Default for Bucket<V> {
    fn default() -> Self {
        Self::Empty
    }
}
impl<V: Clone> Clone for Bucket<V> {
    fn clone(&self) -> Self {
        match self {
            Self::Empty => Self::Empty,
            Self::One(value) => Self::One(value.clone()),
            Self::Many(values) => Self::Many(values.clone()),
        }
    }
}
impl<V> Bucket<V> {
    pub(super) fn push(&mut self, value: V) {
        *self = match std::mem::take(self) {
            Self::Empty => Self::One(value),
            Self::One(first) => Self::Many(vec![first, value]),
            Self::Many(mut values) => {
                values.push(value);
                Self::Many(values)
            }
        };
    }
    pub(super) fn capacity(&self) -> usize {
        match self {
            Self::Empty => 0,
            Self::One(_) => 1,
            Self::Many(values) => values.capacity(),
        }
    }
    pub(super) fn retain(&mut self, mut keep: impl FnMut(&V) -> bool) {
        *self = match std::mem::take(self) {
            Self::Empty => Self::Empty,
            Self::One(value) => {
                if keep(&value) {
                    Self::One(value)
                } else {
                    Self::Empty
                }
            }
            Self::Many(mut values) => {
                values.retain(|value| keep(value));
                match values.len() {
                    0 => Self::Empty,
                    1 => Self::One(values.pop().unwrap()),
                    _ => Self::Many(values),
                }
            }
        };
    }
    pub(super) fn remove(&mut self, index: usize) -> V {
        match std::mem::take(self) {
            Self::Empty => panic!("remove from an empty bucket"),
            Self::One(value) => {
                assert_eq!(index, 0, "bucket index out of range");
                value
            }
            Self::Many(mut values) => {
                let removed = values.remove(index);
                *self = match values.len() {
                    0 => Self::Empty,
                    1 => Self::One(values.pop().unwrap()),
                    _ => Self::Many(values),
                };
                removed
            }
        }
    }
}
impl<V> std::ops::Deref for Bucket<V> {
    type Target = [V];
    fn deref(&self) -> &[V] {
        match self {
            Self::Empty => &[],
            Self::One(value) => std::slice::from_ref(value),
            Self::Many(values) => values,
        }
    }
}
impl<V> std::ops::DerefMut for Bucket<V> {
    fn deref_mut(&mut self) -> &mut [V] {
        match self {
            Self::Empty => &mut [],
            Self::One(value) => std::slice::from_mut(value),
            Self::Many(values) => values,
        }
    }
}
impl<'a, V> IntoIterator for &'a Bucket<V> {
    type Item = &'a V;
    type IntoIter = std::slice::Iter<'a, V>;
    fn into_iter(self) -> Self::IntoIter {
        self.iter()
    }
}
struct Resident<T, Q, A, D> {
    buckets: BTreeMap<u128, Bucket<Variant<T, Q, A, D>>>,
    bytes: usize,
    /// Lease slots in use (bit set = held by a live lease).
    slots: u128,
}

/// Hashes choose buckets only; exact key bytes and all semantic answers authorize
/// reuse. Budgeted stores evict insertion-ordered variants; current-revision
/// stores keep one answer per exact key and prune against the caller's roster.
pub struct ObservedArtifactStore<T, Q, A, D> {
    state: std::sync::RwLock<Resident<T, Q, A, D>>,
    retention: Retention,
}
#[derive(Clone, Copy)]
enum Retention {
    Budgeted(usize),
    /// The caller supplies the complete current key roster before worker use.
    /// One value per exact key; history is replaced rather than accumulated.
    RetainedCurrentRevision,
    SharedCurrentRosters(Option<usize>),
}
impl<T, Q, A, D> Default for ObservedArtifactStore<T, Q, A, D> {
    fn default() -> Self {
        Self::with_limit(DEFAULT_RESIDENT_BYTES)
    }
}
impl<T, Q, A, D> ObservedArtifactStore<T, Q, A, D> {
    /// Explicit census only. The callback runs under the store lock and must not
    /// call back into this store. No value/key cloning or serialization occurs.
    /// `storage_accounting` describes the excluded private control owners; this
    /// visitor alone cannot establish complete retained heap-byte coverage.
    pub fn visit_storage(
        &self,
        mut visit: impl FnMut(ObservedArtifactStorageView<'_, T, Q, A, D>),
    ) {
        let state = self.state.write().unwrap_or_else(|error| error.into_inner());
        visit(ObservedArtifactStorageView::Store {
            buckets: state.buckets.len(),
            entries: state.buckets.values().map(|bucket| bucket.len()).sum::<usize>(),
        });
        for bucket in state.buckets.values() {
            visit(ObservedArtifactStorageView::Bucket {
                address: bucket.as_ptr() as usize,
                len: bucket.len(),
                capacity: bucket.capacity(),
                element_size: std::mem::size_of::<Variant<T, Q, A, D>>(),
            });
            for entry in bucket {
                visit(ObservedArtifactStorageView::Entry {
                    key: &entry.key,
                    reads: &entry.reads,
                    value: &entry.value,
                });
            }
        }
    }
    /// Borrow unadmitted live candidates for the requested exact key roster.
    /// Existing bucket routing is lookup only: every key is compared in full.
    /// This exposes storage, not a reuse certificate. Consumers must still check
    /// current local inputs and replay the complete semantic receipt. The callback
    /// runs under the store lock, must not resolve or reenter this store, and sees
    /// keys in caller order with variants in their existing bucket order.
    pub fn visit_key_storage<K: AsRef<[u8]>>(
        &self,
        keys: impl IntoIterator<Item = K>,
        mut visit: impl FnMut(ObservedArtifactStorageView<'_, T, Q, A, D>),
    ) {
        let state = self.state.write().unwrap_or_else(|error| error.into_inner());
        for key in keys {
            let key = key.as_ref();
            let hash = xxhash_rust::xxh3::xxh3_128(key);
            if let Some(bucket) = state.buckets.get(&hash) {
                for entry in bucket.iter().filter(|entry| entry.key.as_ref() == key) {
                    visit(ObservedArtifactStorageView::Entry {
                        key: &entry.key,
                        reads: &entry.reads,
                        value: &entry.value,
                    });
                }
            }
        }
    }
    pub fn with_limit(limit: usize) -> Self {
        Self {
            state: std::sync::RwLock::new(Resident {
                buckets: BTreeMap::new(),
                bytes: 0,
                slots: 0,
            }),
            retention: Retention::Budgeted(limit),
        }
    }
    pub fn current_revision() -> Self {
        Self {
            state: std::sync::RwLock::new(Resident {
                buckets: BTreeMap::new(),
                bytes: 0,
                slots: 0,
            }),
            retention: Retention::RetainedCurrentRevision,
        }
    }
    /// Call once before parallel admission of the complete current roster.
    /// Borrowed readers remain valid after their store entry is pruned.
    pub fn retain_current_keys<'a>(&self, keys: impl IntoIterator<Item = &'a [u8]>) {
        if !matches!(self.retention, Retention::RetainedCurrentRevision) {
            return;
        }
        let keys: std::collections::HashSet<&[u8]> = keys.into_iter().collect();
        self.retain_where(|key| keys.contains(key));
    }
    /// [`Self::retain_current_keys`] with the current roster given as a
    /// predicate over existing keys, for callers whose roster is "everything
    /// except" a computable set (no key list has to be materialized).
    pub fn retain_where(&self, mut keep_key: impl FnMut(&[u8]) -> bool) {
        if !matches!(self.retention, Retention::RetainedCurrentRevision) {
            return;
        }
        let mut state = self.state.write().unwrap_or_else(|error| error.into_inner());
        state.buckets.retain(|_, bucket| {
            bucket.retain(|entry| keep_key(entry.key.as_ref()));
            !bucket.is_empty()
        });
        state.bytes = state
            .buckets
            .values()
            .flatten()
            .map(|entry| entry.weight)
            .sum();
    }
    /// Advisory membership only; callers still perform ordinary exact admission.
    pub fn is_empty(&self) -> bool {
        self.state
            .write()
            .unwrap_or_else(|error| error.into_inner())
            .buckets
            .is_empty()
    }
    pub fn admitted_bytes(&self) -> usize {
        self.state
            .write()
            .unwrap_or_else(|error| error.into_inner())
            .bytes
    }
    pub fn available_bytes(&self) -> usize {
        match self.retention {
            Retention::Budgeted(limit) => limit.saturating_sub(self.admitted_bytes()),
            Retention::SharedCurrentRosters(Some(limit)) => {
                limit.saturating_sub(self.admitted_bytes())
            }
            Retention::RetainedCurrentRevision | Retention::SharedCurrentRosters(None) => 0,
        }
    }
}
impl<T: Send + Sync, Q: Clone + Ord, A: Clone + Eq, D: Clone + Ord>
    ObservedArtifactStore<T, Q, A, D>
{
    pub fn lookup<R: ObservationHost<Q, A, D>>(&self, key: &[u8], resolver: &R) -> Option<Arc<T>> {
        self.lookup_explained(key, resolver).0
    }
    pub fn lookup_explained<R: ObservationHost<Q, A, D>>(
        &self,
        key: &[u8],
        resolver: &R,
    ) -> (Option<Arc<T>>, Option<Q>) {
        self.visit_explained(key, resolver, &mut |_| true)
    }
    /// Consumer rejection continues to the next exact read-valid variant.
    pub fn visit_explained<R: ObservationHost<Q, A, D>>(
        &self,
        key: &[u8],
        resolver: &R,
        accept: &mut dyn FnMut(&Arc<T>) -> bool,
    ) -> (Option<Arc<T>>, Option<Q>) {
        let (accepted, changed) = self.visit_receipted(key, resolver, accept);
        (accepted.map(|accepted| accepted.value), changed)
    }
    pub fn visit_receipted<R: ObservationHost<Q, A, D>>(
        &self,
        key: &[u8],
        resolver: &R,
        accept: &mut dyn FnMut(&Arc<T>) -> bool,
    ) -> (Option<ObservedArtifact<T, Q, A, D>>, Option<Q>) {
        // One-shot users need no request certificate map or extra owner cells.
        // Both routes preserve the same exact-key candidate loop and replay core.
        self.visit_receipted_with(
            key,
            &mut |reads| {
                crate::observations::first_changed_iter(
                    reads.iter(),
                    |query| resolver.answer(query),
                    |current, previous| resolver.equivalent(current, previous),
                )
                .cloned()
            },
            accept,
        )
    }
    /// Reuse one immutable request's certificate checks across exact-key visits.
    /// Producer-local inputs remain ordinary recorded queries and must be
    /// answered by this host; consumers with per-unit adapters can instead use
    /// `visit_receipted_with` and `request.certified_domains` for their guard.
    /// No validity is retained across requests or installed into store history.
    pub fn visit_receipted_in<R: ObservationHost<Q, A, D>>(
        &self,
        key: &[u8],
        request: &crate::ReceiptAdmission<'_, Q, A, D, R>,
        accept: &mut dyn FnMut(&Arc<T>) -> bool,
    ) -> (Option<ObservedArtifact<T, Q, A, D>>, Option<Q>) {
        self.visit_receipted_with(
            key,
            &mut |reads| request.first_changed_receipted(reads, |_| {}),
            accept,
        )
    }
    /// The callback must validate the entire candidate receipt against the current
    /// immutable host before returning None. Candidate order and consumer rejection
    /// are identical to ordinary replay; callbacks run outside the store lock.
    pub fn visit_receipted_with(
        &self,
        key: &[u8],
        validate: &mut dyn FnMut(&Receipt<Q, A, D>) -> Option<Q>,
        accept: &mut dyn FnMut(&Arc<T>) -> bool,
    ) -> (Option<ObservedArtifact<T, Q, A, D>>, Option<Q>) {
        self.visit_receipted_with_value(
            key,
            &mut |reads, _| validate(reads),
            accept,
        )
    }
    /// The actual immutable candidate payload may carry producer-qualified
    /// certificates. Validate every receipt observation before returning None;
    /// payload access is not admission. Both callbacks run outside store locks.
    pub fn visit_receipted_with_value(
        &self,
        key: &[u8],
        validate: &mut dyn FnMut(&Receipt<Q, A, D>, &Arc<T>) -> Option<Q>,
        accept: &mut dyn FnMut(&Arc<T>) -> bool,
    ) -> (Option<ObservedArtifact<T, Q, A, D>>, Option<Q>) {
        let (accepted, changed) = self.visit_borrowed_receipted_with_value(
            xxhash_rust::xxh3::xxh3_128(key),
            &|candidate| candidate == key,
            validate,
            accept,
        );
        (accepted.map(|(_, receipt)| receipt), changed)
    }

    pub fn insert_with(
        &self,
        key: Arc<[u8]>,
        reads: Vec<Observation<Q, A, D>>,
        weight: usize,
        create: impl FnOnce() -> T,
    ) -> bool {
        self.insert_with_owned(key, reads, weight, create)
            .is_some()
    }
    /// Return the actual immutable stored owner without cloning the produced payload.
    /// Budget rejection does not invoke the producer; borrowed owners survive pruning.
    pub fn insert_with_owned(
        &self,
        key: Arc<[u8]>,
        reads: Vec<Observation<Q, A, D>>,
        weight: usize,
        create: impl FnOnce() -> T,
    ) -> Option<Arc<T>> {
        self.insert_with_shared(key, reads.into(), weight, create)
    }
    /// Admit the issuer's existing immutable ledger without copying its answers.
    pub fn insert_with_shared(
        &self,
        key: Arc<[u8]>,
        reads: Arc<[Observation<Q, A, D>]>,
        weight: usize,
        create: impl FnOnce() -> T,
    ) -> Option<Arc<T>> {
        self.insert_with_receipt(key, reads.into(), weight, create)
    }
    /// Share existing canonical receipt leaves without flattening or reminting.
    pub fn insert_with_receipt(
        &self,
        key: Arc<[u8]>,
        reads: Receipt<Q, A, D>,
        weight: usize,
        create: impl FnOnce() -> T,
    ) -> Option<Arc<T>> {
        let hash = xxhash_rust::xxh3::xxh3_128(&key);
        let mut state = self.state.write().unwrap_or_else(|error| error.into_inner());
        // Resident storage evicts before admitting a new value. Results are
        // independently published; an oversized value needs no resident copy.
        if let Retention::RetainedCurrentRevision = self.retention {
            let mut removed = 0;
            if let Some(bucket) = state.buckets.get_mut(&hash) {
                bucket.retain(|entry| {
                    if entry.key == key {
                        removed += entry.weight;
                        false
                    } else {
                        true
                    }
                });
            }
            state.bytes -= removed;
            let value = Arc::new(create());
            // Current-revision keys normally own one variant. Vec's implicit
            // first push reserves four large entries per key; hundreds of
            // thousands of owner facts would retain that unused capacity.
            // Collisions still grow normally and preserve exact-key siblings.
            state
                .buckets
                .entry(hash)
                .or_default()
                .push(Variant {
                    key,
                    reads,
                    value: Arc::clone(&value),
                    weight,
                    holders: Default::default(),
                });
            state.bytes += weight;
            return Some(value);
        }
        let Retention::Budgeted(limit) = self.retention else {
            unreachable!()
        };
        if weight > limit {
            return None;
        }
        while state.bytes.saturating_add(weight) > limit {
            let Some(oldest_bucket) = state.buckets.keys().next().copied() else {
                break;
            };
            let bucket = state.buckets.get_mut(&oldest_bucket).unwrap();
            let removed = bucket.remove(0);
            let empty = bucket.is_empty();
            state.bytes -= removed.weight;
            if empty {
                state.buckets.remove(&oldest_bucket);
            }
        }
        let bucket = state.buckets.entry(hash).or_default();
        // A hash collision must not evict another exact key's independent variants.
        if bucket.iter().filter(|entry| entry.key == key).count() >= 4 {
            if let Some(index) = bucket.iter().position(|entry| entry.key == key) {
                // Removing a variant releases accounted storage below.
                let removed = bucket.remove(index);
                let removed_weight = removed.weight;
                let value = Arc::new(create());
                bucket.push(Variant {
                    key,
                    reads,
                    value: Arc::clone(&value),
                    weight,
                    holders: Default::default(),
                });
                state.bytes = state.bytes - removed_weight + weight;
                return Some(value);
            }
        }
        let value = Arc::new(create());
        bucket.push(Variant {
            key,
            reads,
            value: Arc::clone(&value),
            weight,
            holders: Default::default(),
        });
        state.bytes += weight;
        Some(value)
    }
}

pub type ArtifactStore<T> = ObservedArtifactStore<T, ResolveQuery, ResolvedMeaning, ReadDomain>;
pub type AcceptedArtifact<T> = ObservedArtifact<T, ResolveQuery, ResolvedMeaning, ReadDomain>;
pub type ArtifactStorageView<'a, T> =
    ObservedArtifactStorageView<'a, T, ResolveQuery, ResolvedMeaning, ReadDomain>;
impl<T: Send + Sync> ArtifactStore<T> {
    pub fn insert(&self, key: Arc<[u8]>, reads: Vec<ResolverRead>, value: T) {
        let weight = key.len()
            + std::mem::size_of::<T>()
            + reads
                .iter()
                .map(|read| read.answer.canonical_bytes().len())
                .sum::<usize>();
        self.insert_with(key, reads, weight, || value);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_ir::ResolvedMeaning;
    use std::sync::atomic::{AtomicUsize, Ordering};
    struct Host;
    impl Resolver for Host {
        fn resolve(&self, _: ResolveQuery) -> ResolvedMeaning {
            ResolvedMeaning::Missing
        }
    }
    #[test]
    fn custom_receipt_validation_preserves_rejection_and_old_replay() {
        let store: ObservedArtifactStore<usize, u32, bool, ()> =
            ObservedArtifactStore::current_revision();
        let key: Arc<[u8]> = Arc::from(b"validated".as_slice());
        assert!(store
            .insert_with_owned(
                key.clone(),
                vec![Observation {
                    query: 1,
                    domain: (),
                    answer: false
                }],
                0,
                || 7
            )
            .is_some());
        let (value, changed) = store.visit_receipted_with(
            &key,
            &mut |reads| {
                assert_eq!(reads.len(), 1);
                Some(1)
            },
            &mut |_| panic!("rejected proof cannot reach consumer"),
        );
        assert!(value.is_none());
        assert_eq!(changed, Some(1));
        struct Current;
        impl ObservationHost<u32, bool, ()> for Current {
            fn answer(&self, _: &u32) -> bool {
                false
            }
        }
        assert_eq!(*store.lookup(&key, &Current).unwrap(), 7);
        let (value, changed) = store.visit_receipted_with(&key, &mut |_| None, &mut |_| false);
        assert!(value.is_none());
        assert_eq!(changed, None);
    }
    struct Value(Arc<AtomicUsize>);
    #[test]
    fn current_revision_singleton_bucket_has_no_variant_growth_slack() {
        let store: ArtifactStore<usize> = ArtifactStore::current_revision();
        let key: Arc<[u8]> = Arc::from(b"singleton".as_slice());
        for value in 0..3 {
            store.insert_with(Arc::clone(&key), vec![], 1, || value);
            let mut buckets = 0;
            store.visit_storage(|view| {
                if let ObservedArtifactStorageView::Bucket { len, capacity, .. } = view {
                    buckets += 1;
                    assert_eq!(len, 1);
                    assert_eq!(capacity, 1);
                }
            });
            assert_eq!(buckets, 1);
            assert_eq!(*store.lookup(&key, &Host).unwrap(), value);
        }
    }
    #[test]
    fn shared_admission_preserves_exact_key_and_ledger_owners() {
        let store: ArtifactStore<()> = ArtifactStore::current_revision();
        let key: Arc<[u8]> = Arc::from(b"shared-receipt".as_slice());
        let query = ResolveQuery::Ancestry(dm_ir::SymbolId::of("/shared"));
        let reads: Arc<[ResolverRead]> = vec![ResolverRead {
            query,
            domain: query.domain(),
            answer: ResolvedMeaning::Missing,
        }]
        .into();
        assert!(store
            .insert_with_shared(
                Arc::clone(&key),
                Arc::clone(&reads),
                1,
                || (),
            )
            .is_some());
        let (accepted, _) = store.visit_receipted(&key, &Host, &mut |_| true);
        let accepted = accepted.unwrap();
        assert!(Arc::ptr_eq(&reads, accepted.reads.flat().unwrap()));
        store.visit_storage(|view| {
            if let ObservedArtifactStorageView::Entry { key: stored, .. } = view {
                assert!(Arc::ptr_eq(&key, stored));
            }
        });
    }
    #[test]
    fn produced_owner_is_shared_and_survives_current_roster_pruning() {
        let store = ArtifactStore::current_revision();
        let key: Arc<[u8]> = Arc::from(b"produced".as_slice());
        let produced = store
            .insert_with_owned(Arc::clone(&key), vec![], 1, || {
                Value(Arc::new(AtomicUsize::new(0)))
            })
            .unwrap();
        let found = store.lookup(&key, &Host).unwrap();
        assert!(Arc::ptr_eq(&produced, &found));
        store.retain_current_keys(std::iter::empty());
        assert!(store.lookup(&key, &Host).is_none());
        assert!(Arc::ptr_eq(&produced, &found));
        let rejected = ArtifactStore::<Value>::with_limit(0);
        assert!(rejected
            .insert_with_owned(key, vec![], 1, || panic!(
                "oversized producers must not run"
            ))
            .is_none());
    }
    #[test]
    fn diagnostic_storage_borrows_actual_owner_without_cloning_it() {
        let store = ArtifactStore::current_revision();
        let key: Arc<[u8]> = Arc::from(b"diagnostic".as_slice());
        store.insert_with(Arc::clone(&key), Vec::new(), 7, || vec![1u8, 2]);
        let retained = store.lookup(&key, &Host).unwrap();
        let count = Arc::strong_count(&retained);
        let mut saw = (false, false, false);
        store.visit_storage(|storage| match storage {
            ArtifactStorageView::Store { buckets, entries } => {
                assert_eq!((buckets, entries), (1, 1));
                saw.0 = true;
            }
            ArtifactStorageView::Bucket {
                address,
                len,
                capacity,
                element_size,
            } => {
                assert_ne!(address, 0);
                assert_eq!(len, 1);
                assert!(capacity >= len);
                assert_eq!(element_size, std::mem::size_of::<Variant<Vec<u8>>>());
                saw.1 = true;
            }
            ArtifactStorageView::Entry {
                key: borrowed_key,
                value,
                reads,
            } => {
                assert!(Arc::ptr_eq(borrowed_key, &key));
                assert!(Arc::ptr_eq(value, &retained));
                assert_eq!(Arc::strong_count(value), count);
                assert!(reads.is_empty());
                saw.2 = true;
            }
        });
        assert_eq!(saw, (true, true, true));
        assert_eq!(store.admitted_bytes(), 7);
    }
    impl Drop for Value {
        fn drop(&mut self) {
            self.0.fetch_add(1, Ordering::SeqCst);
        }
    }
    #[test]
    fn current_revision_replaces_same_key_and_prunes_deleted_readers_safely() {
        let drops = Arc::new(AtomicUsize::new(0));
        let store = ArtifactStore::current_revision();
        let key: Arc<[u8]> = Arc::from(b"current".as_slice());
        store.insert_with(Arc::clone(&key), vec![], 1, || {
            Value(Arc::clone(&drops))
        });
        let reader = store.lookup(&key, &Host).unwrap();
        store.insert_with(Arc::clone(&key), vec![], 2, || {
            Value(Arc::clone(&drops))
        });
        assert_eq!(store.admitted_bytes(), 2);
        assert_eq!(
            store
                .state
                .write()
                .unwrap()
                .buckets
                .values()
                .flatten()
                .count(),
            1
        );
        store.retain_current_keys(std::iter::empty());
        assert_eq!(store.admitted_bytes(), 0);
        assert_eq!(drops.load(Ordering::SeqCst), 1);
        drop(reader);
        assert_eq!(drops.load(Ordering::SeqCst), 2);
    }
    #[test]
    fn current_revision_preserves_collision_siblings_on_exact_replacement() {
        let store = ArtifactStore::current_revision();
        let key: Arc<[u8]> = Arc::from(b"a".as_slice());
        let hash = xxhash_rust::xxh3::xxh3_128(&key);
        store.insert_with(Arc::clone(&key), vec![], 1, || 1u32);
        // Force the bucket collision independently of the hashing implementation.
        store
            .state
            .write()
            .unwrap()
            .buckets
            .get_mut(&hash)
            .unwrap()
            .push(Variant {
                key: Arc::from(b"b".as_slice()),
                reads: Vec::new().into(),
                value: Arc::new(9),
                weight: 3,
                holders: Default::default(),
            });
        store.state.write().unwrap().bytes += 3;
        store.insert_with(key, vec![], 2, || 2u32);
        let state = store.state.write().unwrap();
        assert_eq!(state.bytes, 5);
        let bucket = &state.buckets[&hash];
        assert_eq!(bucket.len(), 2);
        assert_eq!(
            *bucket
                .iter()
                .find(|entry| entry.key.as_ref() == b"b")
                .unwrap()
                .value,
            9
        );
    }
    #[test]
    fn current_revision_changed_read_replaces_the_prior_semantic_variant() {
        struct Presence(bool);
        impl Resolver for Presence {
            fn resolve(&self, _: ResolveQuery) -> ResolvedMeaning {
                ResolvedMeaning::Presence(self.0)
            }
        }
        let store = ArtifactStore::current_revision();
        let query = ResolveQuery::HasMemberVar {
            owner: dm_ir::SymbolId::of("/x"),
            name: dm_ir::SymbolId::of("value"),
        };
        let key: Arc<[u8]> = Arc::from(b"same-expression".as_slice());
        let reads = |value| {
            vec![ResolverRead {
                domain: query.domain(),
                query,
                answer: ResolvedMeaning::Presence(value),
            }]
        };
        store.insert_with(Arc::clone(&key), reads(false), 1, || 1u32);
        assert!(store.lookup(&key, &Presence(true)).is_none());
        store.insert_with(Arc::clone(&key), reads(true), 2, || 2u32);
        assert_eq!(store.lookup(&key, &Presence(true)).as_deref(), Some(&2));
        assert!(store.lookup(&key, &Presence(false)).is_none());
        assert_eq!(store.admitted_bytes(), 2);
    }
    #[test]
    fn consumer_rejection_continues_to_older_read_valid_variant() {
        let store = ArtifactStore::default();
        store.insert(Arc::from(b"exact".as_slice()), vec![], 1u32);
        store.insert(Arc::from(b"exact".as_slice()), vec![], 2u32);
        let mut visited = Vec::new();
        let (value, changed) = store.visit_explained(b"exact", &Host, &mut |value| {
            visited.push(**value);
            **value == 1
        });
        assert_eq!(visited, [2, 1]);
        assert_eq!(value.as_deref(), Some(&1));
        assert!(changed.is_none());
    }
    #[test]
    fn artifact_readers_outlive_store_eviction_then_release_last_owner() {
        let drops = Arc::new(AtomicUsize::new(0));
        let store = ArtifactStore::with_limit(1);
        assert!(
            store.insert_with(Arc::from(b"a".as_slice()), vec![], 1, || Value(
                Arc::clone(&drops)
            ))
        );
        let reader = store.lookup(b"a", &Host).unwrap();
        assert!(
            store.insert_with(Arc::from(b"b".as_slice()), vec![], 1, || Value(
                Arc::clone(&drops)
            ))
        );
        assert!(store.lookup(b"a", &Host).is_none());
        assert_eq!(drops.load(Ordering::SeqCst), 0);
        drop(store);
        assert_eq!(drops.load(Ordering::SeqCst), 1);
        drop(reader);
        assert_eq!(drops.load(Ordering::SeqCst), 2);
    }
    #[test]
    fn oversized_artifact_does_not_construct_or_retain_payload() {
        let store = ArtifactStore::<u32>::with_limit(1);
        let calls = AtomicUsize::new(0);
        assert!(
            !store.insert_with(Arc::from(b"a".as_slice()), vec![], 2, || {
                calls.fetch_add(1, Ordering::SeqCst);
                7
            })
        );
        assert_eq!(calls.load(Ordering::SeqCst), 0);
        assert_eq!(store.admitted_bytes(), 0);
    }
    #[test]
    fn accepted_receipt_shares_validated_ledger_and_survives_store_eviction() {
        let store = ArtifactStore::with_limit(1);
        let query = ResolveQuery::Ancestry(dm_ir::SymbolId::of("/datum"));
        let reads = vec![ResolverRead {
            query,
            domain: query.domain(),
            answer: Host.resolve(query),
        }];
        store.insert_with(Arc::from(b"a".as_slice()), reads, 1, || 7u32);
        let (accepted, changed) = store.visit_receipted(b"a", &Host, &mut |_| true);
        assert!(changed.is_none());
        let accepted = accepted.unwrap();
        let state = store.state.write().unwrap();
        let original = &state.buckets[&xxhash_rust::xxh3::xxh3_128(b"a")][0];
        assert!(Arc::ptr_eq(
            accepted.reads.flat().unwrap(),
            original.reads.flat().unwrap()
        ));
        drop(state);
        store.insert_with(Arc::from(b"b".as_slice()), vec![], 1, || 8u32);
        assert!(store.lookup(b"a", &Host).is_none());
        assert_eq!(accepted.reads[0].query, query);
        assert_eq!(
            accepted.reads[0].answer.canonical_bytes(),
            Host.resolve(query).canonical_bytes()
        );
        assert_eq!(*accepted.value, 7);
    }
    #[test]
    fn collision_bucket_cannot_authorize_different_exact_key() {
        let store = ArtifactStore::with_limit(10);
        store.insert_with(Arc::from(b"a".as_slice()), vec![], 1, || 7u32);
        // Force a collision structurally instead of assuming real hash behavior.
        let mut state = store.state.write().unwrap();
        let variant = state
            .buckets
            .remove(&xxhash_rust::xxh3::xxh3_128(b"a"))
            .unwrap();
        state
            .buckets
            .insert(xxhash_rust::xxh3::xxh3_128(b"b"), variant);
        drop(state);
        assert!(store.lookup(b"b", &Host).is_none());
    }
}
