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
    ///
    /// The claims this lease inherited are the previous request's, which held exactly `previous`'s owners: releasing the
    /// owners that left keeps exactly the current ones, and with none gone the claims are not walked at all.
    pub(crate) fn adopt_changed(&self, mut index: KeyedDeclarations, previous: &KeyedDeclarations) -> KeyedDeclarations {
        let started = std::time::Instant::now();
        // One step over both owner maps (both in owner order): the owners that left, and the owners whose rows are not the
        // previous allocation. An owner whose contribution is the previous one is already admitted and claimed.
        let mut removed = Vec::new();
        let mut replayed = Vec::new();
        let mut kept_rows = Vec::new();
        {
            let mut before = previous.owners.iter().peekable();
            for (&owner, candidate) in &index.owners {
                while before.peek().is_some_and(|(old, _)| **old < owner) {
                    removed.push(before.next().expect("peeked").0.bits());
                }
                match before.peek() {
                    Some((old, kept)) if **old == owner => {
                        if !Arc::ptr_eq(kept, candidate) {
                            if Arc::ptr_eq(&kept.rows, &candidate.rows) {
                                kept_rows.push((owner, Arc::clone(kept)));
                            } else {
                                replayed.push(owner);
                            }
                        }
                        before.next();
                    }
                    _ => replayed.push(owner),
                }
            }
            removed.extend(before.map(|(owner, _)| owner.bits()));
        }
        let compared = started.elapsed();
        if !removed.is_empty() {
            removed.sort_unstable();
            self.lease.retain_where(|stored| owner_bits(stored).is_none_or(|bits| removed.binary_search(&bits).is_err()));
        }
        let released = started.elapsed();
        let admitted: Vec<_> = replayed
            .iter()
            .map(|&owner| (owner, self.admit(&index, owner, &index.owners[&owner])))
            .collect();
        for (owner, value) in kept_rows.into_iter().chain(admitted) {
            index.owners.insert(owner, value);
        }
        crate::change_set::record_outcome(format!(
            "authored adoption: {} owners replayed, {} left: compare={:.3}s release={:.3}s admit={:.3}s",
            replayed.len(),
            removed.len(),
            compared.as_secs_f64(),
            (released - compared).as_secs_f64(),
            (started.elapsed() - released).as_secs_f64()
        ));
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
