//! Request claims on the existing observed core; no second payload store.
//! Shared leases replay exact answers rather than trusting issuer-local versions.
use dm_session::observations::ObservationHost;
use dm_session::{
    ArtifactAttempt, ArtifactPublication, Observation, ObservedArtifactLease,
    ObservedArtifactStorageView, ObservedArtifactStore, Receipt,
};
use std::sync::Arc;
type Lease<T, Q, A, D> = ObservedArtifactLease<T, Q, A, D>;
pub(crate) struct PublicationStore<T, Q, A, D> {
    core: Arc<ObservedArtifactStore<T, Q, A, D>>,
    publication: Option<Arc<ArtifactPublication<Lease<T, Q, A, D>>>>,
    attempt: Option<ArtifactAttempt<Lease<T, Q, A, D>>>,
}
impl<T, Q, A, D> PublicationStore<T, Q, A, D> {
    pub(crate) fn current_revision() -> Self {
        let core = ObservedArtifactStore::shared_current_rosters();
        let publication = Arc::new(ArtifactPublication::default());
        let attempt = Some(publication.begin(core.lease()));
        Self {
            core,
            publication: Some(publication),
            attempt,
        }
    }
    pub(crate) fn with_limit(bytes: usize) -> Self {
        let core = ObservedArtifactStore::shared_current_rosters_with_limit(bytes);
        let publication = Arc::new(ArtifactPublication::default());
        let attempt = Some(publication.begin(core.lease()));
        Self {
            core,
            publication: Some(publication),
            attempt,
        }
    }
    pub(crate) fn for_request(&self, publishable: bool) -> Self {
        let attempt = self.publication.as_ref().map(|owner| {
            if publishable {
                owner.begin(self.core.lease())
            } else {
                owner.begin_ephemeral(self.core.lease())
            }
        });
        Self {
            core: Arc::clone(&self.core),
            publication: self.publication.clone(),
            attempt,
        }
    }
    pub(crate) fn publish_successful(&self) -> bool {
        self.attempt
            .as_ref()
            .is_none_or(ArtifactAttempt::publish_successful)
    }
    pub(crate) fn retain_current_keys<'a>(&self, keys: impl IntoIterator<Item = &'a [u8]>) {
        match &self.attempt {
            Some(attempt) => {
                attempt.with_pending(|lease| lease.retain_current_keys(keys));
            }
            None => self.core.retain_current_keys(keys),
        }
    }
    /// Explicit performance-cache eviction; does not alter publication generation identity.
    pub(crate) fn evict_all_claims(&self) {
        self.retain_current_keys(std::iter::empty::<&[u8]>());
        if let Some(owner) = &self.publication {
            owner.with_published(|lease| lease.retain_current_keys(std::iter::empty::<&[u8]>()));
        }
    }
    pub(crate) fn visit_storage(
        &self,
        visitor: impl FnMut(ObservedArtifactStorageView<'_, T, Q, A, D>),
    ) {
        self.core.visit_storage(visitor);
    }
}
impl<T: Send + Sync, Q: Clone + Ord, A: Clone + Eq, D: Clone + Ord> PublicationStore<T, Q, A, D> {
    pub(crate) fn lookup<H: ObservationHost<Q, A, D>>(
        &self,
        key: &[u8],
        host: &H,
    ) -> Option<Arc<T>> {
        self.visit_explained(key, host, &mut |_| true).0
    }
    pub(crate) fn visit_explained<H: ObservationHost<Q, A, D>>(
        &self,
        key: &[u8],
        host: &H,
        accept: &mut dyn FnMut(&Arc<T>) -> bool,
    ) -> (Option<Arc<T>>, Option<Q>) {
        match &self.attempt {
            Some(attempt) => attempt
                .with_pending(|lease| lease.visit_explained(key, host, accept))
                .unwrap_or((None, None)),
            None => self.core.visit_explained(key, host, accept),
        }
    }
    pub(crate) fn insert_with(
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
    pub(crate) fn insert_with_owned(
        &self,
        key: Arc<[u8]>,
        reads: Vec<Observation<Q, A, D>>,
        versions: Vec<(D, u128)>,
        weight: usize,
        create: impl FnOnce() -> T,
    ) -> Option<Arc<T>> {
        self.insert_with_receipt(key, reads.into(), versions.into(), weight, create)
    }
    pub(crate) fn insert_with_receipt(
        &self,
        key: Arc<[u8]>,
        reads: Receipt<Q, A, D>,
        versions: Arc<[(D, u128)]>,
        weight: usize,
        create: impl FnOnce() -> T,
    ) -> Option<Arc<T>> {
        match &self.attempt {
            Some(attempt) => attempt
                .with_pending(|lease| lease.insert_with_receipt(key, reads, weight, create))
                .flatten(),
            None => self
                .core
                .insert_with_receipt(key, reads, versions, weight, create),
        }
    }
}

#[cfg(test)]
#[path = "artifact_publication_store_tests.rs"]
mod tests;

pub(crate) type Store<T, Q, A, D> = PublicationStore<T, Q, A, D>;
