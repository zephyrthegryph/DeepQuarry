//! Immutable result ownership with budgeted or current-revision retention.
use crate::{
    observations::{Observation, ObservationHost},
    ResolverRead,
};
#[cfg(test)]
use dm_ir::Resolver;
use dm_ir::{ReadDomain, ResolveQuery, ResolvedMeaning};
use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
};
pub const DEFAULT_RESIDENT_BYTES: usize = 8 * 1024 * 1024;
/// Exact key/read acceptance issued by this store; the ledger shares its backing.
pub struct ObservedArtifact<T, Q, A, D> {
    pub value: Arc<T>,
    pub reads: Arc<[Observation<Q, A, D>]>,
    pub versions: Arc<[(D, u128)]>,
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
        reads: &'a Arc<[Observation<Q, A, D>]>,
        versions: &'a Arc<[(D, u128)]>,
        value: &'a Arc<T>,
    },
}
#[derive(Clone)]
struct Variant<T, Q = ResolveQuery, A = ResolvedMeaning, D = ReadDomain> {
    key: Arc<[u8]>,
    reads: Arc<[Observation<Q, A, D>]>,
    versions: Arc<[(D, u128)]>,
    value: Arc<T>,
    weight: usize,
}
struct Resident<T, Q, A, D> {
    buckets: BTreeMap<u128, Vec<Variant<T, Q, A, D>>>,
    bytes: usize,
}

/// Hashes choose buckets only; exact key bytes and all semantic answers authorize
/// reuse. Budgeted stores evict insertion-ordered variants; current-revision
/// stores keep one answer per exact key and prune against the caller's roster.
pub struct ObservedArtifactStore<T, Q, A, D> {
    state: Mutex<Resident<T, Q, A, D>>,
    retention: Retention,
}
#[derive(Clone, Copy)]
enum Retention {
    Budgeted(usize),
    /// The caller supplies the complete current key roster before worker use.
    /// One value per exact key; history is replaced rather than accumulated.
    RetainedCurrentRevision,
}
impl<T, Q, A, D> Default for ObservedArtifactStore<T, Q, A, D> {
    fn default() -> Self {
        Self::with_limit(DEFAULT_RESIDENT_BYTES)
    }
}
impl<T, Q, A, D> ObservedArtifactStore<T, Q, A, D> {
    /// Explicit census only. The callback runs under the store lock and must not
    /// call back into this store. No value/key cloning or serialization occurs.
    pub fn visit_storage(
        &self,
        mut visit: impl FnMut(ObservedArtifactStorageView<'_, T, Q, A, D>),
    ) {
        let state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        visit(ObservedArtifactStorageView::Store {
            buckets: state.buckets.len(),
            entries: state.buckets.values().map(Vec::len).sum(),
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
                    versions: &entry.versions,
                    value: &entry.value,
                });
            }
        }
    }
    pub fn with_limit(limit: usize) -> Self {
        Self {
            state: Mutex::new(Resident {
                buckets: BTreeMap::new(),
                bytes: 0,
            }),
            retention: Retention::Budgeted(limit),
        }
    }
    pub fn current_revision() -> Self {
        Self {
            state: Mutex::new(Resident {
                buckets: BTreeMap::new(),
                bytes: 0,
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
        let keys: std::collections::BTreeSet<&[u8]> = keys.into_iter().collect();
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        state.buckets.retain(|_, bucket| {
            bucket.retain(|entry| keys.contains(entry.key.as_ref()));
            !bucket.is_empty()
        });
        state.bytes = state
            .buckets
            .values()
            .flatten()
            .map(|entry| entry.weight)
            .sum();
    }
    pub fn admitted_bytes(&self) -> usize {
        self.state
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .bytes
    }
    pub fn available_bytes(&self) -> usize {
        match self.retention {
            Retention::Budgeted(limit) => limit.saturating_sub(self.admitted_bytes()),
            Retention::RetainedCurrentRevision => 0,
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
        let hash = xxhash_rust::xxh3::xxh3_128(key);
        // Resolver work takes place outside the store lock, allowing parallel units.
        let candidates = {
            let state = self.state.lock().unwrap_or_else(|error| error.into_inner());
            state
                .buckets
                .get(&hash)
                .into_iter()
                .flatten()
                .filter(|entry| entry.key.as_ref() == key)
                .map(|entry| {
                    (
                        Arc::clone(&entry.reads),
                        Arc::clone(&entry.versions),
                        Arc::clone(&entry.value),
                    )
                })
                .collect::<Vec<_>>()
        };
        let mut changed = None;
        for (reads, versions, value) in candidates.into_iter().rev() {
            let matching = crate::observations::certified_domains(&versions, |domain| {
                resolver.version(domain)
            });
            let mismatch = crate::observations::first_changed(
                &reads,
                &matching,
                |query| resolver.answer(query),
                |current, previous| resolver.equivalent(current, previous),
            );
            if let Some(query) = mismatch {
                changed = Some(query.clone());
            } else if accept(&value) {
                return (
                    Some(ObservedArtifact {
                        value,
                        reads,
                        versions,
                    }),
                    None,
                );
            }
        }
        (None, changed)
    }
    pub fn insert_with(
        &self,
        key: Arc<[u8]>,
        reads: Vec<Observation<Q, A, D>>,
        versions: Vec<(D, u128)>,
        weight: usize,
        create: impl FnOnce() -> T,
    ) -> bool {
        self.insert_with_owned(key, reads, versions, weight, create)
            .is_some()
    }
    /// Return the actual immutable stored owner without cloning the produced payload.
    /// Budget rejection does not invoke the producer; borrowed owners survive pruning.
    pub fn insert_with_owned(
        &self,
        key: Arc<[u8]>,
        reads: Vec<Observation<Q, A, D>>,
        versions: Vec<(D, u128)>,
        weight: usize,
        create: impl FnOnce() -> T,
    ) -> Option<Arc<T>> {
        self.insert_with_shared(key, reads.into(), versions.into(), weight, create)
    }
    /// Admit the issuer's existing immutable ledger without copying its answers.
    pub fn insert_with_shared(
        &self,
        key: Arc<[u8]>,
        reads: Arc<[Observation<Q, A, D>]>,
        versions: Arc<[(D, u128)]>,
        weight: usize,
        create: impl FnOnce() -> T,
    ) -> Option<Arc<T>> {
        let hash = xxhash_rust::xxh3::xxh3_128(&key);
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
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
                .or_insert_with(|| Vec::with_capacity(1))
                .push(Variant {
                    key,
                    reads,
                    versions,
                    value: Arc::clone(&value),
                    weight,
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
                    versions,
                    value: Arc::clone(&value),
                    weight,
                });
                state.bytes = state.bytes - removed_weight + weight;
                return Some(value);
            }
        }
        let value = Arc::new(create());
        bucket.push(Variant {
            key,
            reads,
            versions,
            value: Arc::clone(&value),
            weight,
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
        self.insert_with(key, reads, Vec::new(), weight, || value);
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
    struct Value(Arc<AtomicUsize>);
    #[test]
    fn current_revision_singleton_bucket_has_no_variant_growth_slack() {
        let store: ArtifactStore<usize> = ArtifactStore::current_revision();
        let key: Arc<[u8]> = Arc::from(b"singleton".as_slice());
        for value in 0..3 {
            store.insert_with(Arc::clone(&key), vec![], vec![], 1, || value);
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
        let versions: Arc<[(ReadDomain, u128)]> = vec![(query.domain(), 7)].into();
        assert!(store
            .insert_with_shared(
                Arc::clone(&key),
                Arc::clone(&reads),
                Arc::clone(&versions),
                1,
                || (),
            )
            .is_some());
        let (accepted, _) = store.visit_receipted(&key, &Host, &mut |_| true);
        let accepted = accepted.unwrap();
        assert!(Arc::ptr_eq(&reads, &accepted.reads));
        assert!(Arc::ptr_eq(&versions, &accepted.versions));
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
            .insert_with_owned(Arc::clone(&key), vec![], vec![], 1, || {
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
            .insert_with_owned(key, vec![], vec![], 1, || panic!(
                "oversized producers must not run"
            ))
            .is_none());
    }
    #[test]
    fn diagnostic_storage_borrows_actual_owner_without_cloning_it() {
        let store = ArtifactStore::current_revision();
        let key: Arc<[u8]> = Arc::from(b"diagnostic".as_slice());
        store.insert_with(Arc::clone(&key), Vec::new(), Vec::new(), 7, || vec![1u8, 2]);
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
                versions,
            } => {
                assert!(Arc::ptr_eq(borrowed_key, &key));
                assert!(Arc::ptr_eq(value, &retained));
                assert_eq!(Arc::strong_count(value), count);
                assert!(reads.is_empty() && versions.is_empty());
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
        store.insert_with(Arc::clone(&key), vec![], vec![], 1, || {
            Value(Arc::clone(&drops))
        });
        let reader = store.lookup(&key, &Host).unwrap();
        store.insert_with(Arc::clone(&key), vec![], vec![], 2, || {
            Value(Arc::clone(&drops))
        });
        assert_eq!(store.admitted_bytes(), 2);
        assert_eq!(
            store
                .state
                .lock()
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
        store.insert_with(Arc::clone(&key), vec![], vec![], 1, || 1u32);
        // Force the bucket collision independently of the hashing implementation.
        store
            .state
            .lock()
            .unwrap()
            .buckets
            .get_mut(&hash)
            .unwrap()
            .push(Variant {
                key: Arc::from(b"b".as_slice()),
                reads: Arc::from([]),
                versions: Arc::from([]),
                value: Arc::new(9),
                weight: 3,
            });
        store.state.lock().unwrap().bytes += 3;
        store.insert_with(key, vec![], vec![], 2, || 2u32);
        let state = store.state.lock().unwrap();
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
        store.insert_with(Arc::clone(&key), reads(false), vec![], 1, || 1u32);
        assert!(store.lookup(&key, &Presence(true)).is_none());
        store.insert_with(Arc::clone(&key), reads(true), vec![], 2, || 2u32);
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
            store.insert_with(Arc::from(b"a".as_slice()), vec![], vec![], 1, || Value(
                Arc::clone(&drops)
            ))
        );
        let reader = store.lookup(b"a", &Host).unwrap();
        assert!(
            store.insert_with(Arc::from(b"b".as_slice()), vec![], vec![], 1, || Value(
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
            !store.insert_with(Arc::from(b"a".as_slice()), vec![], vec![], 2, || {
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
        store.insert_with(Arc::from(b"a".as_slice()), reads, vec![], 1, || 7u32);
        let (accepted, changed) = store.visit_receipted(b"a", &Host, &mut |_| true);
        assert!(changed.is_none());
        let accepted = accepted.unwrap();
        let state = store.state.lock().unwrap();
        let original = &state.buckets[&xxhash_rust::xxh3::xxh3_128(b"a")][0];
        assert!(Arc::ptr_eq(&accepted.reads, &original.reads));
        assert!(Arc::ptr_eq(&accepted.versions, &original.versions));
        drop(state);
        store.insert_with(Arc::from(b"b".as_slice()), vec![], vec![], 1, || 8u32);
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
        store.insert_with(Arc::from(b"a".as_slice()), vec![], vec![], 1, || 7u32);
        // Force a collision structurally instead of assuming real hash behavior.
        let mut state = store.state.lock().unwrap();
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
