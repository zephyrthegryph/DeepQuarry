//! Exact engine-scoped local shape owners; dense/source issuance stays local.
use super::*;
type Lease = dm_session::ObservedArtifactLease<LocalOwner, SourceQuery, SourceAnswer, SourceDomain>;

pub(super) enum LocalShapeValues {
    Local(LocalShapeStore),
    Shared {
        owner: Arc<crate::SharedNormalizedDeclarations>,
        lease: Lease,
    },
}
impl LocalShapeValues {
    pub(super) fn shared(owner: Arc<crate::SharedNormalizedDeclarations>) -> Self {
        let lease = owner.local_shapes.lease();
        Self::Shared { owner, lease }
    }
    pub(super) fn fresh(&self) -> Self {
        match self {
            Self::Local(_) => Self::Local(LocalShapeStore::current_revision()),
            Self::Shared { owner, .. } => Self::shared(Arc::clone(owner)),
        }
    }
    pub(super) fn retain_current_keys<'a>(&self, keys: impl IntoIterator<Item = &'a [u8]>) {
        match self {
            Self::Local(store) => store.retain_current_keys(keys),
            Self::Shared { lease, .. } => lease.retain_current_keys(keys),
        }
    }
    /// Shared visitors expose the entire engine-scoped core, including sibling
    /// leases. Pointer-deduplicated census must not call this per-host bytes.
    pub(super) fn visit_storage(
        &self,
        visit: impl FnMut(
            dm_session::ObservedArtifactStorageView<
                '_,
                LocalOwner,
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
    ) -> Option<Arc<LocalOwner>> {
        match self {
            Self::Local(store) => store.lookup(key, host),
            Self::Shared { lease, .. } => lease.visit_explained(key, host, &mut |_| true).0,
        }
    }
    pub(super) fn insert_with_owned(
        &self,
        key: Arc<[u8]>,
        reads: Vec<dm_session::Observation<SourceQuery, SourceAnswer, SourceDomain>>,
        versions: Vec<(SourceDomain, u128)>,
        weight: usize,
        create: impl FnOnce() -> LocalOwner,
    ) -> Option<Arc<LocalOwner>> {
        match self {
            Self::Local(store) => store.insert_with_owned(key, reads, versions, weight, create),
            Self::Shared { lease, .. } => {
                lease.insert_with_owned(key, reads, versions, weight, create)
            }
        }
    }
}
