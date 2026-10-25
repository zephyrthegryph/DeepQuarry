//! Shared current rosters own exact admitted variants, never another host's keys.
//!
//! A lease's roster is not a map of its own: every variant carries the set of lease slots claiming it ([`Holders`]), and a
//! lease's roster is the variants naming its slot (at most one per exact key). A session whose claims equal another
//! session's therefore adds one bit per variant instead of a map entry per key, and nothing is deferred: a claim of a
//! variant already stored sets its bit under the shared read lock; a claim that replaces another variant of the same key
//! (or stores a new one) takes the write lock and frees the replaced variant when nobody else holds it.
use super::*;
use std::sync::atomic::{AtomicU64, Ordering::AcqRel, Ordering::Acquire};

pub struct ObservedArtifactLease<T, Q, A, D> {
    store: Arc<ObservedArtifactStore<T, Q, A, D>>,
    slot: u32,
}
/// Most leases one core can have at once (a lease per session and variant of the daemon).
const SLOTS: u32 = 128;
/// The lease slots claiming one variant. Atomic so an existing claim is made under the shared read lock.
#[derive(Default)]
pub(super) struct Holders([AtomicU64; 2]);
impl Clone for Holders {
    fn clone(&self) -> Self {
        Self([
            AtomicU64::new(self.0[0].load(Acquire)),
            AtomicU64::new(self.0[1].load(Acquire)),
        ])
    }
}
impl Holders {
    fn position(slot: u32) -> (usize, u64) {
        ((slot / 64) as usize, 1u64 << (slot % 64))
    }
    fn set(&self, slot: u32) {
        let (word, bit) = Self::position(slot);
        self.0[word].fetch_or(bit, AcqRel);
    }
    fn clear(&self, slot: u32) {
        let (word, bit) = Self::position(slot);
        self.0[word].fetch_and(!bit, AcqRel);
    }
    fn has(&self, slot: u32) -> bool {
        let (word, bit) = Self::position(slot);
        self.0[word].load(Acquire) & bit != 0
    }
    pub(super) fn is_empty(&self) -> bool {
        self.0.iter().all(|word| word.load(Acquire) == 0)
    }
    pub(super) fn count(&self) -> usize {
        self.0
            .iter()
            .map(|word| word.load(Acquire).count_ones() as usize)
            .sum()
    }
}
#[cfg(test)]
impl<T, Q, A, D> Resident<T, Q, A, D> {
    /// Variants at least one lease claims.
    pub(super) fn claimed_variants(&self) -> usize {
        self.claim_counts().len()
    }
    /// The number of leases claiming each claimed variant.
    pub(super) fn claim_counts(&self) -> Vec<usize> {
        self.buckets
            .values()
            .flatten()
            .map(|entry| entry.holders.count())
            .filter(|count| *count > 0)
            .collect()
    }
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
            state: std::sync::RwLock::new(Resident {
                buckets: BTreeMap::new(),
                bytes: 0,
                slots: 0,
            }),
            retention: Retention::SharedCurrentRosters(limit),
        })
    }
    pub fn lease(self: &Arc<Self>) -> ObservedArtifactLease<T, Q, A, D> {
        assert!(matches!(self.retention, Retention::SharedCurrentRosters(_)));
        let mut state = self.state.write().unwrap_or_else(|error| error.into_inner());
        let slot = (!state.slots).trailing_zeros();
        assert!(
            slot < SLOTS,
            "more than {SLOTS} live leases on one artifact core"
        );
        state.slots |= 1u128 << slot;
        ObservedArtifactLease {
            store: Arc::clone(self),
            slot,
        }
    }
}
/// Release `slot`'s claim on every variant whose key `doomed` accepts; a variant nobody else holds is removed. The removed
/// variants are returned for destruction AFTER unlocking.
fn release_matching<T, Q, A, D>(
    state: &mut Resident<T, Q, A, D>,
    slot: u32,
    mut doomed: impl FnMut(&[u8]) -> bool,
) -> Vec<Variant<T, Q, A, D>> {
    let mut detached = Vec::new();
    let mut freed = 0usize;
    state.buckets.retain(|_, bucket| {
        let mut index = 0;
        while index < bucket.len() {
            let entry = &bucket[index];
            if entry.holders.has(slot) && doomed(&entry.key) {
                entry.holders.clear(slot);
                if entry.holders.is_empty() {
                    let removed = bucket.remove(index);
                    freed += removed.weight;
                    detached.push(removed);
                    continue;
                }
            }
            index += 1;
        }
        !bucket.is_empty()
    });
    state.bytes = state.bytes.saturating_sub(freed);
    detached
}
/// Make the stored variant `pointer` of `key` this lease's claim for the key: the lease's other variant of the same exact
/// key (its previous claim) is released, and removed when nobody else holds it. Returns what was removed.
fn assign<T, Q, A, D>(
    state: &mut Resident<T, Q, A, D>,
    slot: u32,
    key: &[u8],
    hash: u128,
    pointer: usize,
) -> Vec<Variant<T, Q, A, D>> {
    let mut detached = Vec::new();
    let Some(bucket) = state.buckets.get_mut(&hash) else {
        return detached;
    };
    let mut freed = 0usize;
    let mut index = 0;
    while index < bucket.len() {
        let entry = &bucket[index];
        if entry.key.as_ref() == key {
            if Arc::as_ptr(&entry.value) as usize == pointer {
                entry.holders.set(slot);
            } else if entry.holders.has(slot) {
                entry.holders.clear(slot);
                if entry.holders.is_empty() {
                    let removed = bucket.remove(index);
                    freed += removed.weight;
                    detached.push(removed);
                    continue;
                }
            }
        }
        index += 1;
    }
    state.bytes = state.bytes.saturating_sub(freed);
    detached
}
impl<T, Q, A, D> Drop for ObservedArtifactLease<T, Q, A, D> {
    fn drop(&mut self) {
        let mut state = self
            .store
            .state
            .write()
            .unwrap_or_else(|error| error.into_inner());
        let detached = release_matching(&mut state, self.slot, |_| true);
        state.slots &= !(1u128 << self.slot);
        drop(state);
        drop(detached);
    }
}
impl<T, Q, A, D> ObservedArtifactLease<T, Q, A, D> {
    pub fn retain_current_keys<'a>(&self, keys: impl IntoIterator<Item = &'a [u8]>) {
        let keys: std::collections::BTreeSet<_> = keys.into_iter().collect();
        let mut state = self
            .store
            .state
            .write()
            .unwrap_or_else(|error| error.into_inner());
        let detached = release_matching(&mut state, self.slot, |key| !keys.contains(key));
        drop(state);
        drop(detached);
    }
    /// Keep this lease's claims on keys the predicate accepts and release the rest; sibling leases are untouched.
    /// For rosters that are "everything except" a computable set.
    pub fn retain_where(&self, mut keep_key: impl FnMut(&[u8]) -> bool) {
        let mut state = self
            .store
            .state
            .write()
            .unwrap_or_else(|error| error.into_inner());
        let detached = release_matching(&mut state, self.slot, |key| !keep_key(key));
        drop(state);
        drop(detached);
    }
    /// This visits the shared core, including sibling leases. Addresses identify
    /// actual common allocations; private lease/index nodes remain unreported.
    pub fn visit_storage(&self, visit: impl FnMut(ObservedArtifactStorageView<'_, T, Q, A, D>)) {
        self.store.visit_storage(visit);
    }
    /// Whole shared-core accounting, including sibling leases. This is neither
    /// this lease's private byte charge nor complete heap coverage.
    pub fn storage_accounting(&self) -> ArtifactStorageAccounting {
        self.store.storage_accounting()
    }
}
impl<T, Q, A, D: Ord + Clone> ObservedArtifactLease<T, Q, A, D> {
    fn claim(&self, key: &[u8], receipt: ObservedArtifact<T, Q, A, D>) -> Option<Arc<T>> {
        self.claim_key(key, None, receipt)
    }
    pub(super) fn claim_shared(
        &self,
        key: Arc<[u8]>,
        receipt: ObservedArtifact<T, Q, A, D>,
    ) -> Option<Arc<T>> {
        self.claim_key(&key, Some(Arc::clone(&key)), receipt)
    }
    #[inline(never)]
    fn claim_key(
        &self,
        key: &[u8],
        shared_key: Option<Arc<[u8]>>,
        receipt: ObservedArtifact<T, Q, A, D>,
    ) -> Option<Arc<T>> {
        static CLAIM: dm_profile::Accumulator = dm_profile::Accumulator::new("store.claim_locked");
        static ASSIGN: dm_profile::Accumulator = dm_profile::Accumulator::new("store.assign");
        let _claim = CLAIM.time();
        let pointer = Arc::as_ptr(&receipt.value) as usize;
        let hash = xxhash_rust::xxh3::xxh3_128(key);
        {
            let state = self
                .store
                .state
                .read()
                .unwrap_or_else(|error| error.into_inner());
            if let Some(bucket) = state.buckets.get(&hash) {
                let target = bucket
                    .iter()
                    .find(|entry| Arc::ptr_eq(&entry.value, &receipt.value) && entry.key.as_ref() == key);
                if let Some(target) = target {
                    // Replacing this lease's claim on another variant of the key needs the write lock (that variant may
                    // be freed); an unchanged or first claim of a stored variant is one bit under the read lock.
                    let replacing = bucket.iter().any(|entry| {
                        !std::ptr::eq(entry, target)
                            && entry.key.as_ref() == key
                            && entry.holders.has(self.slot)
                    });
                    if !replacing {
                        target.holders.set(self.slot);
                        return Some(receipt.value);
                    }
                }
            }
        }
        let mut state = self
            .store
            .state
            .write()
            .unwrap_or_else(|error| error.into_inner());
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
        let key = stored_key
            .clone()
            .or(shared_key)
            .unwrap_or_else(|| Arc::from(key));
        if stored_key.is_none() {
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
                holders: Default::default(),
            });
            state.bytes = state.bytes.saturating_add(receipt.weight);
        }
        let assign_timer = ASSIGN.time();
        let detached = assign(&mut state, self.slot, &key, hash, pointer);
        drop(assign_timer);
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
    /// Current local-input acceptance and observer delivery precede a pending
    /// claim. The strong request-bound capability already proves all read values.
    pub fn claim_current<H>(
        &self,
        candidate: UnchangedCandidate<'_, '_, T, Q, A, D, H>,
        locally_current: impl FnOnce(&[u8], &Arc<T>) -> bool,
        observed: impl FnMut(&Arc<[Observation<Q, A, D>]>),
    ) -> Option<Arc<T>> {
        let (key, accepted) = candidate.admit_current(locally_current, observed)?;
        self.claim(&key, accepted)
    }
    pub fn claim_unchanged<H>(
        &self,
        candidate: UnchangedCandidate<'_, '_, T, Q, A, D, H>,
        key: &[u8],
        locally_current: impl FnOnce(&Arc<T>) -> bool,
        observed: impl FnMut(&Arc<[Observation<Q, A, D>]>),
    ) -> Option<Arc<T>> {
        let accepted = candidate.admit(key, locally_current, observed)?;
        self.claim(key, accepted)
    }
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
        self.visit_receipted_with_value(
            key,
            &mut |reads, versions, _| validate(reads, versions),
            accept,
        )
    }
    /// Use the same candidate loop and pending claim rule with producer payload
    /// certificates. Declined validation/acceptance never claims a variant.
    pub fn visit_receipted_with_value(
        &self,
        key: &[u8],
        validate: &mut dyn FnMut(&crate::Receipt<Q, A, D>, &[(D, u128)], &Arc<T>) -> Option<Q>,
        accept: &mut dyn FnMut(&Arc<T>) -> bool,
    ) -> (Option<ObservedArtifact<T, Q, A, D>>, Option<Q>) {
        let (receipt, changed) = self.store.visit_receipted_with_value(key, validate, accept);
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
        self.insert_with_qualified_receipt(key, reads, Arc::from([]), weight, create)
    }
    /// Versions must be qualified for the actual immutable answer provider.
    /// Ordinary cross-host visit_explained still replays exact answers.
    pub fn insert_with_qualified_receipt(
        &self,
        key: Arc<[u8]>,
        reads: crate::Receipt<Q, A, D>,
        versions: Arc<[(D, u128)]>,
        weight: usize,
        create: impl FnOnce() -> T,
    ) -> Option<Arc<T>> {
        self.insert_qualified(key, reads, versions, weight, None, false, create)
    }
    /// Publish a freshly computed result after consumer input admission missed.
    /// Equal locator/read ledgers alone do not certify equal producer inputs.
    /// Existing published/escaped owners stay immutable; only this lease adopts
    /// the new physical variant, through the ordinary claim/index lifetime path.
    pub fn insert_fresh_with_qualified_receipt(
        &self,
        key: Arc<[u8]>,
        reads: crate::Receipt<Q, A, D>,
        versions: Arc<[(D, u128)]>,
        weight: usize,
        create: impl FnOnce() -> T,
    ) -> Option<Arc<T>> {
        self.insert_qualified(key, reads, versions, weight, None, true, create)
    }
    /// Republish a current immutable producer value only for this exact already
    /// admitted payload and ledger. Previous publication claims remain live;
    /// replacing this request's claim does not mutate escaped values.
    pub fn rebind_with_qualified_receipt(
        &self,
        previous: &Arc<T>,
        key: Arc<[u8]>,
        reads: crate::Receipt<Q, A, D>,
        versions: Arc<[(D, u128)]>,
        weight: usize,
        create: impl FnOnce() -> T,
    ) -> Option<Arc<T>> {
        self.insert_qualified(key, reads, versions, weight, Some(previous), false, create)
    }
    fn insert_qualified(
        &self,
        key: Arc<[u8]>,
        reads: crate::Receipt<Q, A, D>,
        versions: Arc<[(D, u128)]>,
        weight: usize,
        previous: Option<&Arc<T>>,
        fresh: bool,
        create: impl FnOnce() -> T,
    ) -> Option<Arc<T>> {
        // Only this small bridge specializes on the caller's closure type.
        // Keep producer capture on the stack; admission/budget checks in the
        // shared body happen before taking it, under the same lock as before.
        let mut create = Some(create);
        self.insert_qualified_produced(key, reads, versions, weight, previous, fresh, &mut || {
            create
                .take()
                .expect("artifact producer invoked more than once")()
        })
    }
    // Do not re-inline the heavy store mutation body into every producer bridge.
    #[inline(never)]
    fn insert_qualified_produced(
        &self,
        key: Arc<[u8]>,
        reads: crate::Receipt<Q, A, D>,
        versions: Arc<[(D, u128)]>,
        weight: usize,
        previous: Option<&Arc<T>>,
        fresh: bool,
        produce: &mut dyn FnMut() -> T,
    ) -> Option<Arc<T>> {
        let hash = xxhash_rust::xxh3::xxh3_128(&key);
        let mut state = self
            .store
            .state
            .write()
            .unwrap_or_else(|error| error.into_inner());
        if let Some(previous) = previous {
            if !state.buckets.get(&hash).into_iter().flatten().any(|entry| {
                entry.key == key
                    && entry.reads == reads
                    && entry.versions == versions
                    && Arc::ptr_eq(&entry.value, previous)
            }) {
                return None;
            }
        }
        let existing = state
            .buckets
            .get(&hash)
            .into_iter()
            .flatten()
            .find(|entry| {
                !fresh
                    && previous.is_none()
                    && entry.key == key
                    && entry.reads == reads
                    && entry.versions == versions
            })
            .map(|entry| (Arc::clone(&entry.value), Arc::clone(&entry.key)));
        if existing.is_none() && !self.permits_charge(state.bytes, weight) {
            return None;
        }
        let bucket = state
            .buckets
            .entry(hash)
            .or_insert_with(|| Vec::with_capacity(1));
        let (value, key) = if let Some(existing) = existing {
            existing
        } else {
            let value = Arc::new(produce());
            bucket.push(Variant {
                key: Arc::clone(&key),
                reads,
                versions,
                value: Arc::clone(&value),
                weight,
                holders: Default::default(),
            });
            state.bytes = state.bytes.saturating_add(weight);
            (value, key)
        };
        let detached = assign(&mut state, self.slot, &key, hash, Arc::as_ptr(&value) as usize);
        drop(state);
        drop(detached);
        Some(value)
    }
}

impl<T: Send + Sync, Q: Clone + Ord, A: Clone + Eq, D: Clone + Ord>
    ObservedArtifactLease<T, Q, A, D>
{
    /// Same candidate loop, ledger admission and claim rule as exact slice lookup.
    pub fn visit_borrowed_receipted_with_value(
        &self,
        digest: u128,
        matches_key: &dyn Fn(&[u8]) -> bool,
        validate: &mut dyn FnMut(&Receipt<Q, A, D>, &[(D, u128)], &Arc<T>) -> Option<Q>,
        accept: &mut dyn FnMut(&Arc<T>) -> bool,
    ) -> (Option<ObservedArtifact<T, Q, A, D>>, Option<Q>) {
        let (accepted, changed) =
            self.store
                .visit_borrowed_receipted_with_value(digest, matches_key, validate, accept);
        let accepted = accepted.and_then(|(key, receipt)| {
            self.claim_shared(
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
}

#[cfg(test)]
mod tests;

#[cfg(test)]
#[path = "leased/fresh_tests.rs"]
mod fresh_tests;
