//! Successful current ownership over the existing procedure observation core.
use super::*;
type RichLease = dm_session::ObservedArtifactLease<
    CachedProcedure,
    ResolveQuery,
    dm_ir::ResolvedMeaning,
    ReadDomain,
>;
pub struct RetainedProcedures {
    pub(crate) values: Arc<LoweringMemo<CachedProcedure>>,
    publication: Arc<dm_session::ArtifactPublication<RichLease>>,
    pub(super) insertion: Mutex<()>,
}
impl Default for RetainedProcedures {
    fn default() -> Self {
        Self {
            values: LoweringMemo::shared_current_rosters(),
            publication: Arc::new(Default::default()),
            insertion: Mutex::new(()),
        }
    }
}
impl RetainedProcedures {
    pub(super) fn can_insert(&self, weight: usize) -> bool {
        let mut used = 0usize;
        self.values.visit_storage(|view| {
            if let dm_session::ArtifactStorageView::Entry { value, .. } = view {
                used = used.saturating_add(value.retained_weight);
            }
        });
        used.checked_add(weight)
            .is_some_and(|total| total <= RESIDENT_LIMIT)
    }
    fn can_claim(&self, candidate: &Arc<CachedProcedure>) -> bool {
        let mut used = 0usize;
        let mut already_owned = false;
        self.values.visit_storage(|view| {
            if let dm_session::ArtifactStorageView::Entry { value, .. } = view {
                used = used.saturating_add(value.retained_weight);
                already_owned |= Arc::ptr_eq(value, candidate);
            }
        });
        already_owned
            || used
                .checked_add(candidate.retained_weight)
                .is_some_and(|total| total <= RESIDENT_LIMIT)
    }
    fn begin(&self, publishable: bool) -> dm_session::ArtifactAttempt<RichLease> {
        let lease = self.values.lease();
        if publishable {
            self.publication.begin(lease)
        } else {
            self.publication.begin_ephemeral(lease)
        }
    }
    pub(crate) fn visit_storage(
        &self,
        visit: impl FnMut(dm_session::ArtifactStorageView<'_, CachedProcedure>),
    ) {
        self.values.visit_storage(visit);
    }
}
impl ProcedureMemo {
    pub fn with_resident_for_request(
        policy: u128,
        owner: Arc<RetainedProcedures>,
        disk: Option<Arc<crate::runner_disk::LazyDisk>>,
        publishable: bool,
    ) -> Self {
        let mut memo = Self::with_resident(policy, Arc::clone(&owner.values), disk);
        memo.rich_attempt = Some(owner.begin(publishable));
        memo.rich_owner = Some(owner);
        memo.publishable = publishable;
        memo
    }
    pub(crate) fn visit_resident<R: Resolver>(
        &self,
        key: &[u8],
        host: &R,
        accept: &mut dyn FnMut(&Arc<CachedProcedure>) -> bool,
    ) -> (
        Option<dm_session::AcceptedArtifact<CachedProcedure>>,
        Option<ResolveQuery>,
    ) {
        if let Some(attempt) = &self.rich_attempt {
            // Claims can reattach a value if its previous lease vanished during
            // validation. Serialize that charge with insertion; drops only free.
            let owner = self.rich_owner.as_ref().expect("request rich owner");
            let _guard = owner
                .insertion
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            attempt
                .with_pending(|lease| {
                    lease.visit_explained_accepted(key, host, &mut |value| {
                        owner.can_claim(value) && accept(value)
                    })
                })
                .unwrap_or((None, None))
        } else {
            self.values.visit_receipted(key, host, accept)
        }
    }
    /// Called only after successful complete compilation/output admission.
    pub(crate) fn publish_successful(&self) {
        if !self.publishable {
            return;
        }
        if let Some(owner) = &self.symbolic {
            owner.publish_successful();
        }
        if let Some(owner) = &self.initializers {
            owner.publish_successful();
        }
        if let Some(owner) = &self.startup {
            owner.publish_successful();
        }
        if let Some(owner) = &self.initializer_fragments {
            owner.publish_successful();
        }
        if let Some(owner) = &self.initializer_assemblies {
            owner.publish_successful();
        }
        if let Some(owner) = &self.class_projections {
            owner.publish_successful();
        }
        if let Some(owner) = &self.required_types {
            owner.publish_successful();
        }
        if let Some(owner) = &self.link_bindings {
            owner.publish_successful();
        }
        self.publish_procedures();
    }
    pub(crate) fn publish_procedures(&self) -> bool {
        self.rich_attempt
            .as_ref()
            .is_some_and(|attempt| attempt.publish_successful())
    }
}

#[cfg(test)]
#[path = "publication_tests.rs"]
mod tests;
