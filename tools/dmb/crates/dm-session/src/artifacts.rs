//! Immutable result ownership with bounded resident retention.
use crate::{matching_domains, ResolverRead};
use dm_ir::{ReadDomain, ResolveQuery, Resolver};
use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
};
pub const DEFAULT_RESIDENT_BYTES: usize = 8 * 1024 * 1024;
#[derive(Clone)]
struct Variant<T> {
    key: Arc<[u8]>,
    reads: Arc<[ResolverRead]>,
    versions: Arc<[(ReadDomain, u128)]>,
    value: Arc<T>,
    weight: usize,
}
struct Resident<T> {
    buckets: BTreeMap<u128, Vec<Variant<T>>>,
    bytes: usize,
}

/// Hashes choose buckets only; exact key bytes and all semantic answers authorize
/// reuse. Variants are insertion ordered; the oldest of at most four is evicted.
pub struct ArtifactStore<T> {
    state: Mutex<Resident<T>>,
    limit: usize,
}
impl<T> Default for ArtifactStore<T> {
    fn default() -> Self {
        Self::with_limit(DEFAULT_RESIDENT_BYTES)
    }
}
impl<T> ArtifactStore<T> {
    pub fn with_limit(limit: usize) -> Self {
        Self {
            state: Mutex::new(Resident {
                buckets: BTreeMap::new(),
                bytes: 0,
            }),
            limit,
        }
    }
    pub fn admitted_bytes(&self) -> usize {
        self.state
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .bytes
    }
    pub fn available_bytes(&self) -> usize {
        self.limit.saturating_sub(self.admitted_bytes())
    }
}
impl<T: Send + Sync> ArtifactStore<T> {
    pub fn lookup<R: Resolver>(&self, key: &[u8], resolver: &R) -> Option<Arc<T>> {
        self.lookup_explained(key, resolver).0
    }
    pub fn lookup_explained<R: Resolver>(
        &self,
        key: &[u8],
        resolver: &R,
    ) -> (Option<Arc<T>>, Option<ResolveQuery>) {
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
            let matching = matching_domains(&versions, resolver);
            let mismatch = reads.iter().find(|read| {
                !matching.contains(&read.domain)
                    && resolver.resolve(read.query).canonical_bytes()
                        != read.answer.canonical_bytes()
            });
            if let Some(read) = mismatch {
                changed = Some(read.query);
            } else {
                return (Some(value), None);
            }
        }
        (None, changed)
    }
    pub fn insert(&self, key: Arc<[u8]>, reads: Vec<ResolverRead>, value: T) {
        let weight = key.len()
            + std::mem::size_of::<T>()
            + reads
                .iter()
                .map(|read| read.answer.canonical_bytes().len())
                .sum::<usize>();
        self.insert_with(key, reads, Vec::new(), weight, || value);
    }
    pub fn insert_with(
        &self,
        key: Arc<[u8]>,
        reads: Vec<ResolverRead>,
        versions: Vec<(ReadDomain, u128)>,
        weight: usize,
        create: impl FnOnce() -> T,
    ) -> bool {
        let hash = xxhash_rust::xxh3::xxh3_128(&key);
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        // Resident storage evicts before admitting a new value. Results are
        // independently published; an oversized value needs no resident copy.
        if weight > self.limit {
            return false;
        }
        while state.bytes.saturating_add(weight) > self.limit {
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
                bucket.push(Variant {
                    key,
                    reads: reads.into(),
                    versions: versions.into(),
                    value: Arc::new(create()),
                    weight,
                });
                state.bytes = state.bytes - removed_weight + weight;
                return true;
            }
        }
        bucket.push(Variant {
            key,
            reads: reads.into(),
            versions: versions.into(),
            value: Arc::new(create()),
            weight,
        });
        state.bytes += weight;
        true
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
    impl Drop for Value {
        fn drop(&mut self) {
            self.0.fetch_add(1, Ordering::SeqCst);
        }
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
