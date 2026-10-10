//! Engine-scoped immutable relative contributions, with exact live byte replay.
use super::*;
use dm_session::{
    Observation, ObservationHost, ObservedArtifactLease, ObservedArtifactStorageView,
    ObservedArtifactStore,
};
/// Stored receipts own exact bytes. Live answers borrow the request through Host;
/// length is descriptive only: equivalent always compares every current byte.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ChunkSourceAnswer {
    Owned(Arc<str>),
    Live(usize),
}
pub(crate) type SharedContributionStore =
    ObservedArtifactStore<Contribution, (), ChunkSourceAnswer, ()>;
type Lease = ObservedArtifactLease<Contribution, (), ChunkSourceAnswer, ()>;
pub(super) enum DeclarationValues {
    Local(ArtifactStore<Contribution>),
    Shared(Lease),
}
struct Host<'a>(&'a str);
impl ObservationHost<(), ChunkSourceAnswer, ()> for Host<'_> {
    fn answer(&self, _: &()) -> ChunkSourceAnswer {
        ChunkSourceAnswer::Live(self.0.len())
    }
    fn equivalent(&self, current: &ChunkSourceAnswer, previous: &ChunkSourceAnswer) -> bool {
        matches!((current, previous), (ChunkSourceAnswer::Live(length), ChunkSourceAnswer::Owned(bytes))
            if *length == self.0.len() && bytes.as_ref() == self.0)
    }
}
impl Default for DeclarationValues {
    fn default() -> Self {
        Self::Local(ArtifactStore::current_revision())
    }
}
impl DeclarationValues {
    pub(super) fn shared(owner: &crate::SharedNormalizedDeclarations) -> Self {
        Self::Shared(owner.contributions.lease())
    }
    pub(super) fn is_shared(&self) -> bool {
        matches!(self, Self::Shared(_))
    }
    pub(super) fn retain(&self, keys: &[Vec<u8>]) {
        match self {
            Self::Local(store) => store.retain_current_keys(keys.iter().map(Vec::as_slice)),
            Self::Shared(lease) => lease.retain_current_keys(keys.iter().map(Vec::as_slice)),
        }
    }
    pub(super) fn get(&self, key: &[u8], text: &str, offset: usize) -> Option<CurrentContribution> {
        let value = match self {
            Self::Local(store) => store.lookup(key, &NoReads)?,
            Self::Shared(lease) => {
                lease
                    .visit_explained(key, &Host(text), &mut |value| {
                        CurrentContribution::bind(Arc::clone(value), text, offset).is_some()
                    })
                    .0?
            }
        };
        CurrentContribution::bind(value, text, offset)
    }
    pub(super) fn publish(&self, key: &[u8], current: &mut CurrentContribution) -> Option<()> {
        let value = match self {
            Self::Local(store) => {
                store.insert_with_owned(Arc::from(key), vec![], vec![], 0, || {
                    current.value.as_ref().clone()
                })?
            }
            Self::Shared(lease) => lease.insert_with_owned(
                Arc::from(key),
                vec![Observation {
                    query: (),
                    domain: (),
                    answer: ChunkSourceAnswer::Owned(Arc::clone(&current.value.source)),
                }],
                vec![],
                0,
                || current.value.as_ref().clone(),
            )?,
        };
        if value.source != current.value.source
            || value.skeletons.as_ref() != current.value.skeletons.as_ref()
        {
            return None;
        }
        current.value = value;
        Some(())
    }
    pub(super) fn visit_storage(&self, mut visit: impl FnMut(DeclarationStorageView<'_>)) {
        match self {
            Self::Local(store) => store.visit_storage(|view| match view {
                ArtifactStorageView::Store { buckets, entries } => {
                    visit(DeclarationStorageView::Store { buckets, entries })
                }
                ArtifactStorageView::Bucket {
                    address,
                    len,
                    capacity,
                    element_size,
                } => visit(DeclarationStorageView::Bucket {
                    address,
                    len,
                    capacity,
                    element_size,
                }),
                ArtifactStorageView::Entry {
                    key,
                    reads,
                    versions,
                    value,
                } => visit(DeclarationStorageView::Entry {
                    key,
                    reads,
                    versions,
                    contribution: value.view(),
                }),
            }),
            Self::Shared(lease) => lease.visit_storage(|view| match view {
                ObservedArtifactStorageView::Store { buckets, entries } => {
                    visit(DeclarationStorageView::Store { buckets, entries })
                }
                ObservedArtifactStorageView::Bucket {
                    address,
                    len,
                    capacity,
                    element_size,
                } => visit(DeclarationStorageView::Bucket {
                    address,
                    len,
                    capacity,
                    element_size,
                }),
                ObservedArtifactStorageView::Entry {
                    key,
                    reads,
                    versions,
                    value,
                } => visit(DeclarationStorageView::SharedEntry {
                    key,
                    reads,
                    versions,
                    contribution: value.view(),
                }),
            }),
        }
    }
}
impl Contribution {
    fn view(&self) -> DeclarationContributionView<'_> {
        DeclarationContributionView {
            allocation_address: self as *const Self as usize,
            allocation_size: std::mem::size_of::<Self>(),
            syntax: &self.syntax,
            source: &self.source,
            skeletons: &self.skeletons,
            facts: &self.facts,
            facts_owner: &self.facts,
            ledger: &self.ledger,
            event_leaf: &self.event_leaf,
        }
    }
}

#[cfg(test)]
#[path = "shared_tests.rs"]
mod tests;
