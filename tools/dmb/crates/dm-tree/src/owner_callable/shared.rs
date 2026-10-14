//! Shared exact callable anchors; current namespace reduction stays local.
use super::*;
type Lease =
    dm_session::ObservedArtifactLease<CallableOwner, SourceQuery, SourceAnswer, SourceDomain>;
pub(super) enum CallableValues {
    Local(CallableStore),
    Shared {
        owner: Arc<crate::SharedNormalizedDeclarations>,
        lease: Lease,
    },
}
impl CallableValues {
    pub(super) fn shared(owner: Arc<crate::SharedNormalizedDeclarations>) -> Self {
        let lease = owner.callables.lease();
        Self::Shared { owner, lease }
    }
    pub(super) fn fresh(&self) -> Self {
        match self {
            Self::Local(_) => Self::Local(CallableStore::current_revision()),
            Self::Shared { owner, .. } => Self::shared(Arc::clone(owner)),
        }
    }
    pub(super) fn retain_current_keys<'a>(&self, keys: impl IntoIterator<Item = &'a [u8]>) {
        match self {
            Self::Local(store) => store.retain_current_keys(keys),
            Self::Shared { lease, .. } => lease.retain_current_keys(keys),
        }
    }
    pub(super) fn visit_storage(
        &self,
        visit: impl FnMut(
            dm_session::ObservedArtifactStorageView<
                '_,
                CallableOwner,
                SourceQuery,
                SourceAnswer,
                SourceDomain,
            >,
        ),
    ) {
        match self {
            Self::Local(store) => store.visit_storage(visit),
            Self::Shared { lease, .. } => lease.visit_storage(visit),
        }
    }
    pub(super) fn lookup<
        R: dm_session::ObservationHost<SourceQuery, SourceAnswer, SourceDomain>,
    >(
        &self,
        key: &[u8],
        host: &R,
    ) -> Option<Arc<CallableOwner>> {
        self.visit_explained(key, host, &mut |_| true).0
    }
    pub(super) fn visit_explained<
        R: dm_session::ObservationHost<SourceQuery, SourceAnswer, SourceDomain>,
    >(
        &self,
        key: &[u8],
        host: &R,
        accept: &mut dyn FnMut(&Arc<CallableOwner>) -> bool,
    ) -> (Option<Arc<CallableOwner>>, Option<SourceQuery>) {
        match self {
            Self::Local(store) => store.visit_explained(key, host, accept),
            Self::Shared { lease, .. } => lease.visit_explained(key, host, accept),
        }
    }
    pub(super) fn insert_with_owned(
        &self,
        key: Arc<[u8]>,
        reads: Vec<dm_session::Observation<SourceQuery, SourceAnswer, SourceDomain>>,
        versions: Vec<(SourceDomain, u128)>,
        weight: usize,
        create: impl FnOnce() -> CallableOwner,
    ) -> Option<Arc<CallableOwner>> {
        match self {
            Self::Local(store) => store.insert_with_owned(key, reads, versions, weight, create),
            Self::Shared { lease, .. } => {
                lease.insert_with_owned(key, reads, versions, weight, create)
            }
        }
    }
}
