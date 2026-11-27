//! Exact authored rows shared before semantic normalization; no source issuer.
use super::*;
use dm_session::{Observation, ObservationHost, ObservedArtifactLease, ObservedArtifactStore};
type Answer = Option<Arc<[DeclarationRow]>>;
type Store = ObservedArtifactStore<TypeContribution, SymbolId, Answer, ()>;
pub(crate) struct SharedAuthored {
    store: Arc<Store>,
}
impl SharedAuthored {
    pub(crate) fn new() -> Self {
        Self {
            store: Store::shared_current_rosters(),
        }
    }
    pub(crate) fn lease(self: &Arc<Self>) -> AuthoredLease {
        AuthoredLease {
            store: Arc::clone(&self.store),
            lease: self.store.lease(),
            id: next_lease_id(),
        }
    }
}
pub(crate) struct AuthoredLease {
    store: Arc<Store>,
    lease: ObservedArtifactLease<TypeContribution, SymbolId, Answer, ()>,
    /// Names this lease in the `AdmittedAuthored` it admits, so the next request knows whose claims it inherited.
    id: u64,
}
fn next_lease_id() -> u64 {
    static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
    NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
}
struct Host<'a>(&'a KeyedDeclarations);
impl ObservationHost<SymbolId, Answer, ()> for Host<'_> {
    fn answer(&self, owner: &SymbolId) -> Answer {
        self.0.owner(*owner).map(|value| Arc::clone(&value.rows))
    }
}
const KEY_PREFIX: &[u8] = b"authored-owner-rows-v1";
fn key(owner: SymbolId) -> Arc<[u8]> {
    let mut key = KEY_PREFIX.to_vec();
    key.extend_from_slice(&owner.bits().to_le_bytes());
    key.into()
}
/// The owner bits a stored key names (`key`'s inverse); `None` for a key of another shape.
fn owner_bits(stored: &[u8]) -> Option<u64> {
    Some(u64::from_le_bytes(stored.strip_prefix(KEY_PREFIX)?.try_into().ok()?))
}
impl AuthoredLease {
    pub(crate) fn fork(&self) -> Self {
        Self {
            store: Arc::clone(&self.store),
            lease: self.store.lease(),
            id: next_lease_id(),
        }
    }
    pub(crate) fn id(&self) -> u64 {
        self.id
    }
    /// Take over every claim `previous` holds (one pass, no replay); see `ObservedArtifactLease::claim_all_held_by`.
    pub(crate) fn inherit(&self, previous: &Self) -> usize {
        self.lease.claim_all_held_by(&previous.lease)
    }
    #[cfg(test)]
    pub(crate) fn claimed(&self) -> usize {
        self.lease.claimed()
    }
    pub(crate) fn visit_storage(
        &self,
        visit: impl FnMut(
            dm_session::ObservedArtifactStorageView<'_, TypeContribution, SymbolId, Answer, ()>,
        ),
    ) {
        self.lease.visit_storage(visit);
    }
    pub(crate) fn clear(&self) {
        self.lease.retain_current_keys(std::iter::empty());
    }
    /// `adopt` for a lease that inherited the claims of the lease that admitted `previous`: an owner whose rows are the
    /// previous request's (the same allocation: `KeyedDeclarations::capture_view` shares an unchanged owner's
    /// contribution) keeps the previous admitted value, which this lease already claims; only the other owners are
    /// replayed. Owners no longer present release their claim, as `adopt`'s `retain_current_keys` does.
    pub(crate) fn adopt_changed(&self, mut index: KeyedDeclarations, previous: &KeyedDeclarations) -> KeyedDeclarations {
        let current: std::collections::HashSet<u64> = index.owners.keys().map(|owner| owner.bits()).collect();
        self.lease.retain_where(|stored| owner_bits(stored).is_none_or(|bits| current.contains(&bits)));
        let mut admitted = BTreeMap::new();
        for (&owner, candidate) in &index.owners {
            if let Some(kept) = previous.owners.get(&owner).filter(|kept| Arc::ptr_eq(&kept.rows, &candidate.rows)) {
                admitted.insert(owner, Arc::clone(kept));
                continue;
            }
            admitted.insert(owner, self.admit(&index, owner, candidate));
        }
        index.owners = admitted;
        index
    }
    fn admit(&self, index: &KeyedDeclarations, owner: SymbolId, candidate: &Arc<TypeContribution>) -> Arc<TypeContribution> {
        self.lease
            .visit_explained(&key(owner), &Host(index), &mut |value| value.owner == owner)
            .0
            .unwrap_or_else(|| {
                self.lease
                    .insert_with_owned(
                        key(owner),
                        vec![Observation { query: owner, domain: (), answer: Some(Arc::clone(&candidate.rows)) }],
                        0,
                        || candidate.as_ref().clone(),
                    )
                    .expect("current roster unbudgeted")
            })
    }
    pub(crate) fn adopt(&self, mut index: KeyedDeclarations) -> KeyedDeclarations {
        let keys: Vec<_> = index.owners.keys().copied().map(key).collect();
        self.lease
            .retain_current_keys(keys.iter().map(AsRef::as_ref));
        let mut admitted = BTreeMap::new();
        for (&owner, candidate) in &index.owners {
            admitted.insert(owner, self.admit(&index, owner, candidate));
        }
        index.owners = admitted;
        index
    }
}

#[cfg(test)]
mod tests;
