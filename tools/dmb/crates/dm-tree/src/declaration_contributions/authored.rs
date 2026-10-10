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
            lease: self.store.lease(),
        }
    }
}
pub(crate) struct AuthoredLease {
    lease: ObservedArtifactLease<TypeContribution, SymbolId, Answer, ()>,
}
struct Host<'a>(&'a KeyedDeclarations);
impl ObservationHost<SymbolId, Answer, ()> for Host<'_> {
    fn answer(&self, owner: &SymbolId) -> Answer {
        self.0.owner(*owner).map(|value| Arc::clone(&value.rows))
    }
}
fn key(owner: SymbolId) -> Arc<[u8]> {
    let mut key = b"authored-owner-rows-v1".to_vec();
    key.extend_from_slice(&owner.bits().to_le_bytes());
    key.into()
}
impl AuthoredLease {
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
    pub(crate) fn adopt(&self, mut index: KeyedDeclarations) -> KeyedDeclarations {
        let keys: Vec<_> = index.owners.keys().copied().map(key).collect();
        self.lease
            .retain_current_keys(keys.iter().map(AsRef::as_ref));
        let mut admitted = BTreeMap::new();
        for (&owner, candidate) in &index.owners {
            let value = self
                .lease
                .visit_explained(&key(owner), &Host(&index), &mut |value| {
                    value.owner == owner
                })
                .0
                .unwrap_or_else(|| {
                    self.lease
                        .insert_with_owned(
                            key(owner),
                            vec![Observation {
                                query: owner,
                                domain: (),
                                answer: Some(Arc::clone(&candidate.rows)),
                            }],
                            vec![],
                            0,
                            || candidate.as_ref().clone(),
                        )
                        .expect("current roster unbudgeted")
                });
            admitted.insert(owner, value);
        }
        index.owners = admitted;
        index
    }
}

#[cfg(test)]
mod tests;
