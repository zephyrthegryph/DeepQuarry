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
    Owned(dm_preprocess::SourceText),
    Live(usize),
}
pub(crate) type SharedContributionStore =
    ObservedArtifactStore<Contribution, (), ChunkSourceAnswer, ()>;
type Lease = ObservedArtifactLease<Contribution, (), ChunkSourceAnswer, ()>;
pub(super) enum DeclarationValues {
    Local(Arc<SharedContributionStore>, Lease),
    Shared(Arc<SharedContributionStore>, Lease),
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
        let store = SharedContributionStore::shared_current_rosters();
        Self::Local(Arc::clone(&store), store.lease())
    }
}
impl DeclarationValues {
    pub(super) fn fork(&self) -> Self {
        match self {
            Self::Local(store, _) => Self::Local(Arc::clone(store), store.lease()),
            Self::Shared(store, _) => Self::Shared(Arc::clone(store), store.lease()),
        }
    }
    pub(super) fn shared(owner: &crate::SharedNormalizedDeclarations) -> Self {
        Self::Shared(
            Arc::clone(&owner.contributions),
            owner.contributions.lease(),
        )
    }
    pub(super) fn is_shared(&self) -> bool {
        matches!(self, Self::Shared(..))
    }
    pub(super) fn retain(&self, keys: &[Vec<u8>]) {
        match self {
            Self::Local(_, lease) => lease.retain_current_keys(keys.iter().map(Vec::as_slice)),
            Self::Shared(_, lease) => lease.retain_current_keys(keys.iter().map(Vec::as_slice)),
        }
    }
    pub(super) fn get(&self, key: &[u8], text: &str, offset: usize) -> Option<CurrentContribution> {
        match self {
            Self::Local(_, lease) | Self::Shared(_, lease) => {
                let mut bound = None;
                let admitted = lease
                    .visit_explained(key, &Host(text), &mut |value| {
                        bound = CurrentContribution::bind(Arc::clone(value), text, offset);
                        bound.is_some()
                    })
                    .0?;
                // The generic source replay and coordinate binding both succeeded
                // for this exact admitted owner; do not bind the same leaf twice.
                bound
                    .filter(|current| Arc::ptr_eq(&current.value, &admitted))
                    .map(|mut current| {
                        current.stored = true;
                        current
                    })
            }
        }
    }
    /// SAME exact source replay and candidate loop, with checked producer/domain
    /// admission before any pending claim. Actual IO never becomes a cache miss.
    pub(super) fn get_checked(&self,key:&[u8],text:&str,offset:usize,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<Option<CurrentContribution>>{
        checked_status(a)?;
        let mut bound=None;
        let lease=match self{Self::Local(_,lease)|Self::Shared(_,lease)=>lease};
        let(receipt,_)=lease.try_visit_explained_accepted(key,&Host(text),&mut|value|->std::io::Result<bool>{
            if !value.syntax.initializer_admission_matches(a)?{return Ok(false);}
            bound=CurrentContribution::bind(Arc::clone(value),text,offset);
            Ok(bound.is_some())
        })?;
        checked_status(a)?;
        Ok(receipt.and_then(|receipt|bound.filter(|current|Arc::ptr_eq(&current.value,&receipt.value)).map(|mut current|{current.stored=true;current})))
    }
    /// A fresh checked producer must retain its actual original header even
    /// when an older contribution has equal source and read ledger. Use the
    /// existing physical-variant path; never replace escaped owners or graft.
    pub(super) fn publish_checked(&self,key:&[u8],current:&mut CurrentContribution,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<Option<()>>{
        if !current.value.syntax.initializer_admission_matches(a)?{
            return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"checked declaration publication lacks completed same-counter original header"));
        }
        let lease=match self{Self::Local(_,lease)|Self::Shared(_,lease)=>lease};
        let reads=vec![Observation{query:(),domain:(),answer:ChunkSourceAnswer::Owned(current.value.source.clone())}].into();
        let Some(value)=lease.insert_fresh_with_qualified_receipt(Arc::from(key),reads,0,||current.value.as_ref().clone())else{return Ok(None)};
        if !Arc::ptr_eq(&value.syntax,&current.value.syntax)||!value.syntax.initializer_admission_matches(a)?{
            return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"fresh declaration publication substituted original header owner"));
        }
        current.value=value;current.stored=true;Ok(Some(()))
    }
    pub(super) fn publish(&self, key: &[u8], current: &mut CurrentContribution) -> Option<()> {
        let value = match self {
            Self::Local(_, lease) | Self::Shared(_, lease) => lease.insert_with_owned(
                Arc::from(key),
                vec![Observation {
                    query: (),
                    domain: (),
                    answer: ChunkSourceAnswer::Owned(current.value.source.clone()),
                }],
                0,
                || current.value.as_ref().clone(),
            )?,
        };
        if value.source != current.value.source
            || value.skeletons.as_ref() != current.value.skeletons.as_ref()
        {
            return None;
        }
        // The same native source owner can be upgraded by a fresh primary parse.
        // Share only source-code facts; original acquisition receipts stay current.
        value.syntax.adopt_primary_headers(&current.value.syntax);
        current.value = value;
        current.stored = true;
        Some(())
    }
    pub(super) fn visit_claimed_body_candidates(&self,index:&mut super::super::relative_declarations::BodyCodeCandidates,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<()>{
        let lease=match self{Self::Local(_,lease)|Self::Shared(_,lease)=>lease};
        lease.try_visit_claimed_values(&||checked_status(a),&mut|value|index.capture(&value.syntax,a))
    }
    pub(super) fn visit_storage(&self, mut visit: impl FnMut(DeclarationStorageView<'_>)) {
        match self {
            Self::Local(_, lease) | Self::Shared(_, lease) => {
                lease.visit_storage(|view| match view {
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
                    ObservedArtifactStorageView::Entry { key, reads, value } => {
                        visit(DeclarationStorageView::SharedEntry {
                            key,
                            reads,
                            contribution: value.view(),
                        })
                    }
                })
            }
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

fn checked_status(a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<()>{let status=a.checkpoint();if let Some(actual)=a.take_operational_error(){return Err(actual);}status}
