//! Exact engine-scoped normalized rows. Current source issuers remain local.
use super::*;
type Store = ObservedArtifactStore<ResolvedOwner, SourceQuery, SourceAnswer, SourceDomain>;
type Lease =
    dm_session::ObservedArtifactLease<ResolvedOwner, SourceQuery, SourceAnswer, SourceDomain>;

/// Source-neutral normalized artifacts shared by hosts of one exact engine.
/// Lifetime is the union of current host rosters, not an invented byte budget.
pub struct SharedNormalizedDeclarations {
    values: Arc<Store>,
}
impl Default for SharedNormalizedDeclarations {
    fn default() -> Self {
        Self {
            values: Store::shared_current_rosters(),
        }
    }
}
pub(super) enum NormalizedValues {
    Local(Store),
    Shared {
        owner: Arc<SharedNormalizedDeclarations>,
        lease: Lease,
    },
}
impl NormalizedValues {
    pub(super) fn shared(owner: Arc<SharedNormalizedDeclarations>) -> Self {
        let lease = owner.values.lease();
        Self::Shared { owner, lease }
    }
    pub(super) fn fresh(&self) -> Self {
        match self {
            Self::Local(_) => Self::Local(Store::current_revision()),
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
                ResolvedOwner,
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
    pub(super) fn visit_explained<
        R: dm_session::ObservationHost<SourceQuery, SourceAnswer, SourceDomain>,
    >(
        &self,
        key: &[u8],
        host: &R,
        accept: &mut dyn FnMut(&Arc<ResolvedOwner>) -> bool,
    ) -> (Option<Arc<ResolvedOwner>>, Option<SourceQuery>) {
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
        create: impl FnOnce() -> ResolvedOwner,
    ) -> Option<Arc<ResolvedOwner>> {
        match self {
            Self::Local(store) => store.insert_with_owned(key, reads, versions, weight, create),
            Self::Shared { lease, .. } => {
                lease.insert_with_owned(key, reads, versions, weight, create)
            }
        }
    }
}
