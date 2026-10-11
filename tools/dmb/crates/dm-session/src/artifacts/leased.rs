//! Shared current rosters own exact admitted variants, never another host's keys.
use super::*;

pub struct ObservedArtifactLease<T, Q, A, D> {
    store: Arc<ObservedArtifactStore<T, Q, A, D>>,
    id: u64,
}
impl<T, Q, A, D> ObservedArtifactStore<T, Q, A, D> {
    pub fn shared_current_rosters() -> Arc<Self> {
        Self::shared_rosters(None)
    }
    /// Limit the aggregate charge of all live physical variants. Existing
    /// successful rosters are never evicted to admit a new pending claim.
    pub fn shared_current_rosters_with_limit(limit: usize) -> Arc<Self> {
        Self::shared_rosters(Some(limit))
    }
    fn shared_rosters(limit: Option<usize>) -> Arc<Self> {
        Arc::new(Self {
            state: Mutex::new(Resident {
                buckets: BTreeMap::new(),
                bytes: 0,
                leases: BTreeMap::new(),
                next_lease: 0,
                claims: BTreeMap::new(),
                incidence: None,
            }),
            retention: Retention::SharedCurrentRosters(limit),
        })
    }
    pub fn lease(self: &Arc<Self>) -> ObservedArtifactLease<T, Q, A, D> {
        assert!(matches!(self.retention, Retention::SharedCurrentRosters(_)));
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        let id = state.next_lease;
        state.next_lease = id
            .checked_add(1)
            .expect("artifact lease identity exhausted");
        state.leases.insert(id, BTreeMap::new());
        ObservedArtifactLease {
            store: Arc::clone(self),
            id,
        }
    }
}
// Claim counts index exact live value allocations; addresses never authorize reuse.
// Removed variants are returned to the caller for destruction AFTER unlocking.
fn release<T, Q, A, D>(
    state: &mut Resident<T, Q, A, D>,
    pointer: usize,
) -> Option<Variant<T, Q, A, D>> {
    let (hash, count) = state.claims.get_mut(&pointer).expect("claimed variant");
    if *count > 1 {
        *count -= 1;
        return None;
    }
    let hash = *hash;
    state.claims.remove(&pointer);
    let bucket = state.buckets.get_mut(&hash).expect("claimed bucket");
    let index = bucket
        .iter()
        .position(|entry| Arc::as_ptr(&entry.value) as usize == pointer)
        .expect("claimed value");
    let removed = bucket.remove(index);
    if bucket.is_empty() {
        state.buckets.remove(&hash);
    }
    if let Some(index) = &mut state.incidence {
        index.remove(pointer as u64);
    }
    state.bytes = state.bytes.saturating_sub(removed.weight);
    Some(removed)
}
fn assign<T, Q, A, D>(
    state: &mut Resident<T, Q, A, D>,
    id: u64,
    key: Arc<[u8]>,
    hash: u128,
    pointer: usize,
) -> Option<Variant<T, Q, A, D>> {
    let previous = state
        .leases
        .get_mut(&id)
        .expect("live lease")
        .insert(key, pointer);
    if previous == Some(pointer) {
        return None;
    }
    let claim = state.claims.entry(pointer).or_insert((hash, 0));
    claim.1 = claim
        .1
        .checked_add(1)
        .expect("variant claim count exhausted");
    previous.and_then(|old| release(state, old))
}
impl<T, Q, A, D> Drop for ObservedArtifactLease<T, Q, A, D> {
    fn drop(&mut self) {
        let mut state = self
            .store
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let roster = state.leases.remove(&self.id).expect("live lease");
        let detached: Vec<_> = roster
            .values()
            .filter_map(|pointer| release(&mut state, *pointer))
            .collect();
        drop(state);
        drop(detached);
        drop(roster);
    }
}
impl<T, Q, A, D> ObservedArtifactLease<T, Q, A, D> {
    pub fn retain_current_keys<'a>(&self, keys: impl IntoIterator<Item = &'a [u8]>) {
        let keys: std::collections::BTreeSet<_> = keys.into_iter().collect();
        let mut state = self
            .store
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let roster = state.leases.get_mut(&self.id).expect("live lease");
        let removed: Vec<_> = roster
            .keys()
            .filter(|key| !keys.contains(key.as_ref()))
            .cloned()
            .collect();
        let removed: Vec<_> = removed
            .into_iter()
            .map(|key| {
                let pointer = roster.remove(&key).expect("current claim");
                (key, pointer)
            })
            .collect();
        let detached: Vec<_> = removed
            .iter()
            .filter_map(|(_, pointer)| release(&mut state, *pointer))
            .collect();
        drop(state);
        drop(detached);
        drop(removed);
    }
    /// This visits the shared core, including sibling leases. Addresses identify
    /// actual common allocations; private lease/index nodes remain unreported.
    pub fn visit_storage(&self, visit: impl FnMut(ObservedArtifactStorageView<'_, T, Q, A, D>)) {
        self.store.visit_storage(visit);
    }
}
impl<T, Q, A, D: Ord + Clone> ObservedArtifactLease<T, Q, A, D> {
    fn claim(&self, key: &[u8], receipt: ObservedArtifact<T, Q, A, D>) -> Option<Arc<T>> {
        let mut state = self
            .store
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let pointer = Arc::as_ptr(&receipt.value) as usize;
        let hash = xxhash_rust::xxh3::xxh3_128(key);
        // Another lease can disappear during exact replay outside the lock.
        // The borrowed receipt remains alive and can reattach the SAME variant.
        let stored_key = state
            .buckets
            .get(&hash)
            .into_iter()
            .flatten()
            .find(|entry| Arc::ptr_eq(&entry.value, &receipt.value) && entry.key.as_ref() == key)
            .map(|entry| Arc::clone(&entry.key));
        if stored_key.is_none() && !self.permits_charge(state.bytes, receipt.weight) {
            return None;
        }
        let key = stored_key.clone().unwrap_or_else(|| Arc::from(key));
        if stored_key.is_none() {
            let incidence_reads = state.incidence.as_ref().map(|_| receipt.reads.clone());
            let bucket = state
                .buckets
                .entry(hash)
                .or_insert_with(|| Vec::with_capacity(1));
            bucket.push(Variant {
                key: Arc::clone(&key),
                reads: receipt.reads,
                versions: receipt.versions,
                value: Arc::clone(&receipt.value),
                weight: receipt.weight,
            });
            if let (Some(index), Some(reads)) = (&mut state.incidence, incidence_reads) {
                index.insert(pointer as u64, hash, &reads);
            }
            state.bytes = state.bytes.saturating_add(receipt.weight);
        }
        let detached = assign(&mut state, self.id, key, hash, pointer);
        drop(state);
        drop(detached);
        Some(receipt.value)
    }
    fn permits_charge(&self, charged: usize, additional: usize) -> bool {
        match self.store.retention {
            Retention::SharedCurrentRosters(Some(limit)) => charged
                .checked_add(additional)
                .is_some_and(|total| total <= limit),
            Retention::SharedCurrentRosters(None) => true,
            _ => unreachable!("lease requires shared current rosters"),
        }
    }
}
/// Cross-owner reuse cannot trust an unqualified process-local version number.
/// Always replay the ordinary exact answers using the caller's current host.
struct Exact<'a, R>(&'a R);
impl<Q, A: Eq, D, R: ObservationHost<Q, A, D>> ObservationHost<Q, A, D> for Exact<'_, R> {
    fn answer(&self, query: &Q) -> A {
        self.0.answer(query)
    }
    fn equivalent(&self, current: &A, previous: &A) -> bool {
        self.0.equivalent(current, previous)
    }
}
impl<T: Send + Sync, Q: Clone + Ord, A: Clone + Eq, D: Clone + Ord>
    ObservedArtifactLease<T, Q, A, D>
{
    pub fn visit_explained<R: ObservationHost<Q, A, D>>(
        &self,
        key: &[u8],
        host: &R,
        accept: &mut dyn FnMut(&Arc<T>) -> bool,
    ) -> (Option<Arc<T>>, Option<Q>) {
        let (receipt, changed) = self.visit_explained_accepted(key, host, accept);
        (receipt.map(|receipt| receipt.value), changed)
    }
    /// Return the SAME accepted read owners after ordinary exact host and caller
    /// admission. Declined candidates never acquire a pending lease claim.
    pub fn visit_explained_accepted<R: ObservationHost<Q, A, D>>(
        &self,
        key: &[u8],
        host: &R,
        accept: &mut dyn FnMut(&Arc<T>) -> bool,
    ) -> (Option<ObservedArtifact<T, Q, A, D>>, Option<Q>) {
        let (receipt, changed) = self.store.visit_receipted(key, &Exact(host), accept);
        let accepted = receipt.and_then(|receipt| {
            let claim = ObservedArtifact {
                value: Arc::clone(&receipt.value),
                reads: receipt.reads.clone(),
                versions: Arc::clone(&receipt.versions),
                weight: receipt.weight,
            };
            self.claim(key, claim)?;
            Some(receipt)
        });
        (accepted, changed)
    }
    /// SAME exact-key candidate loop with caller-supplied current receipt proof.
    /// `validate` must authenticate every observation against this immutable
    /// request before returning None. Claims follow full consumer admission.
    pub fn visit_receipted_with(
        &self,
        key: &[u8],
        validate: &mut dyn FnMut(&crate::Receipt<Q, A, D>, &[(D, u128)]) -> Option<Q>,
        accept: &mut dyn FnMut(&Arc<T>) -> bool,
    ) -> (Option<ObservedArtifact<T, Q, A, D>>, Option<Q>) {
        let (receipt, changed) = self.store.visit_receipted_with(key, validate, accept);
        let accepted = receipt.and_then(|receipt| {
            self.claim(
                key,
                ObservedArtifact {
                    value: Arc::clone(&receipt.value),
                    reads: receipt.reads.clone(),
                    versions: Arc::clone(&receipt.versions),
                    weight: receipt.weight,
                },
            )?;
            Some(receipt)
        });
        (accepted, changed)
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
    pub fn insert_with_owned(
        &self,
        key: Arc<[u8]>,
        reads: Vec<Observation<Q, A, D>>,
        _versions: Vec<(D, u128)>,
        weight: usize,
        create: impl FnOnce() -> T,
    ) -> Option<Arc<T>> {
        self.insert_with_receipt(key, reads.into(), weight, create)
    }
    /// Exact replay across host issuers deliberately ignores domain versions.
    pub fn insert_with_receipt(
        &self,
        key: Arc<[u8]>,
        reads: crate::observations::Receipt<Q, A, D>,
        weight: usize,
        create: impl FnOnce() -> T,
    ) -> Option<Arc<T>> {
        let hash = xxhash_rust::xxh3::xxh3_128(&key);
        let mut state = self
            .store
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let existing = state
            .buckets
            .get(&hash)
            .into_iter()
            .flatten()
            .find(|entry| entry.key == key && entry.reads == reads)
            .map(|entry| (Arc::clone(&entry.value), Arc::clone(&entry.key)));
        if existing.is_none() && !self.permits_charge(state.bytes, weight) {
            return None;
        }
        let incidence_reads = state.incidence.as_ref().map(|_| reads.clone());
        let bucket = state
            .buckets
            .entry(hash)
            .or_insert_with(|| Vec::with_capacity(1));
        let (value, key) = if let Some(existing) = existing {
            existing
        } else {
            let value = Arc::new(create());
            bucket.push(Variant {
                key: Arc::clone(&key),
                reads,
                versions: Arc::from([]),
                value: Arc::clone(&value),
                weight,
            });
            if let (Some(index), Some(reads)) = (&mut state.incidence, incidence_reads) {
                index.insert(Arc::as_ptr(&value) as usize as u64, hash, &reads);
            }
            state.bytes = state.bytes.saturating_add(weight);
            (value, key)
        };
        let detached = assign(&mut state, self.id, key, hash, Arc::as_ptr(&value) as usize);
        drop(state);
        drop(detached);
        Some(value)
    }
}

#[cfg(test)]
mod tests;
