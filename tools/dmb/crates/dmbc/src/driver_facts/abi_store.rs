//! Backing of the ABI unit artifacts: one daemon-wide core with a lease per session, or a private current-revision store.
//!
//! A unit artifact is a pure function of what its receipt reads (`Inputs`, which names the shared engine payload, the
//! procedure metadata by content, the predecessor layout, and the semantic answers), so two sessions whose trees hold an
//! equal unit validate one stored variant against their own answers and claim it instead of each decoding or computing
//! and owning a copy. The rules are the other shared cores' (`shared_store.rs`): a variant is found by exact key,
//! validated by the asking session's own reads, and freed when the last lease releases it. Domain versions are the
//! tokens of one daemon process (content digests or process-wide issuer counters), so an equal version in two sessions
//! names one certified state.
//!
//! Whole-batch recipes (`DMB_ABI_BATCH_REPLAY`, `DMB_ABI_BATCH_RECIPES`) bind to one session's frontend and stay private.
use super::observations::{Answer, Domain, Query};
use super::Artifact;
use dm_session::{
    ObservationHost, ObservedArtifact, ObservedArtifactLease, ObservedArtifactStorageView,
    ObservedArtifactStore, PressurePrune, Receipt,
};
use std::sync::Arc;

type Core = ObservedArtifactStore<Artifact, Query, Answer, Domain>;
type Lease = ObservedArtifactLease<Artifact, Query, Answer, Domain>;
type View<'a> = ObservedArtifactStorageView<'a, Artifact, Query, Answer, Domain>;
type Found = (Option<ObservedArtifact<Artifact, Query, Answer, Domain>>, Option<Query>);

/// The purpose name of the daemon-wide core (`DMB_SHARED_STORE_PRIVATE=abi` keeps it private).
pub(in crate::driver_facts) const CORE: &str = "abi.units";

pub(in crate::driver_facts) enum AbiStore {
    Private(Core),
    Shared { core: Arc<Core>, lease: Lease },
}

impl AbiStore {
    /// The daemon's core when the shared store is active and nothing session-bound is stored, else a private store.
    pub(in crate::driver_facts) fn new(session_bound: bool) -> Self {
        if !session_bound {
            if let Some(core) = crate::shared_store::shared_core::<Artifact, Query, Answer, Domain>(CORE) {
                let lease = core.lease();
                return Self::Shared { core, lease };
            }
        }
        Self::Private(Core::current_revision())
    }
    pub(in crate::driver_facts) fn is_shared(&self) -> bool {
        matches!(self, Self::Shared { .. })
    }
    pub(in crate::driver_facts) fn visit_storage(&self, visit: impl FnMut(View<'_>)) {
        match self {
            Self::Private(store) => store.visit_storage(visit),
            Self::Shared { lease, .. } => lease.visit_storage(visit),
        }
    }
    pub(in crate::driver_facts) fn retain_current_keys<'a>(&self, keys: impl IntoIterator<Item = &'a [u8]>) {
        match self {
            Self::Private(store) => store.retain_current_keys(keys),
            Self::Shared { lease, .. } => lease.retain_current_keys(keys),
        }
    }
    pub(in crate::driver_facts) fn visit_receipted_with(
        &self,
        key: &[u8],
        validate: &mut dyn FnMut(&Receipt<Query, Answer, Domain>) -> Option<Query>,
        accept: &mut dyn FnMut(&Arc<Artifact>) -> bool,
    ) -> Found {
        match self {
            Self::Private(store) => store.visit_receipted_with(key, validate, accept),
            Self::Shared { lease, .. } => lease.visit_receipted_with(key, validate, accept),
        }
    }
    pub(in crate::driver_facts) fn visit_receipted<H: ObservationHost<Query, Answer, Domain>>(
        &self,
        key: &[u8],
        host: &H,
        accept: &mut dyn FnMut(&Arc<Artifact>) -> bool,
    ) -> Found {
        match self {
            Self::Private(store) => store.visit_receipted(key, host, accept),
            Self::Shared { lease, .. } => lease.visit_explained_accepted(key, host, accept),
        }
    }
    /// Store (or find the equal stored variant of) a computed unit; the session claims it either way.
    pub(in crate::driver_facts) fn insert_with_receipt(
        &self,
        key: Arc<[u8]>,
        reads: Receipt<Query, Answer, Domain>,
        weight: usize,
        create: impl FnOnce() -> Artifact,
    ) -> Option<Arc<Artifact>> {
        match self {
            Self::Private(store) => store.insert_with_receipt(key, reads, weight, create),
            Self::Shared { lease, .. } => {
                lease.insert_with_qualified_receipt(key, reads, weight, create)
            }
        }
    }
    /// Candidates for the scheduler: every stored variant of the keys, with whether this session claims it.
    pub(in crate::driver_facts) fn visit_candidates<K: AsRef<[u8]>>(
        &self,
        keys: impl IntoIterator<Item = K>,
        mut visit: impl FnMut(View<'_>, bool),
    ) {
        match self {
            Self::Private(store) => store.visit_key_storage(keys, |view| visit(view, true)),
            Self::Shared { lease, .. } => lease.visit_key_storage(keys, visit),
        }
    }
    /// Claim a variant the scheduler validated (a private store keeps every variant resident already).
    pub(in crate::driver_facts) fn claim(&self, key: &[u8], value: &Arc<Artifact>) {
        if let Self::Shared { lease, .. } = self {
            lease.claim_stored(key, value);
        }
    }
    pub(in crate::driver_facts) fn prune_for_pressure(
        &self,
        limit: usize,
        charge: impl FnMut(
            &Arc<[u8]>,
            &Receipt<Query, Answer, Domain>,
            &Arc<Artifact>,
        ) -> Option<usize>,
    ) -> PressurePrune {
        match self {
            Self::Private(store) => store.prune_for_pressure(limit, charge),
            Self::Shared { core, .. } => core.prune_for_pressure(limit, charge),
        }
    }
    #[cfg(test)]
    pub(in crate::driver_facts) fn insert_with_owned(
        &self,
        key: Arc<[u8]>,
        reads: Vec<dm_session::Observation<Query, Answer, Domain>>,
        weight: usize,
        create: impl FnOnce() -> Artifact,
    ) -> Option<Arc<Artifact>> {
        match self {
            Self::Private(store) => store.insert_with_owned(key, reads, weight, create),
            Self::Shared { lease, .. } => lease.insert_with_owned(key, reads, weight, create),
        }
    }
    #[cfg(test)]
    pub(in crate::driver_facts) fn lookup<H: ObservationHost<Query, Answer, Domain>>(
        &self,
        key: &[u8],
        host: &H,
    ) -> Option<Arc<Artifact>> {
        match self {
            Self::Private(store) => store.lookup(key, host),
            Self::Shared { lease, .. } => lease.visit_explained(key, host, &mut |_| true).0,
        }
    }
}

#[cfg(test)]
#[path = "abi_store_tests.rs"]
mod tests;
