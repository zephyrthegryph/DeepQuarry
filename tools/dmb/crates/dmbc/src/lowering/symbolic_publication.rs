//! Request claims over the existing symbolic artifact and exact observation ledger.
use super::*;
type Store = dm_session::ArtifactStore<Record>;
pub(super) type Lease = dm_session::ObservedArtifactLease<
    Record,
    dm_ir::ResolveQuery,
    dm_ir::ResolvedMeaning,
    dm_ir::ReadDomain,
>;
pub(super) struct Leases {
    pub(super) records: Lease,
    code: Option<crate::symbolic::shared_procedure_code::Lease>,
}
pub(super) struct Owner {
    pub(super) values: Arc<Store>,
    publication: Arc<dm_session::ArtifactPublication<Leases>>,
}
impl Default for Owner {
    fn default() -> Self {
        let values = Store::shared_current_rosters();
        values.enable_incidence();
        Self {
            values,
            publication: Arc::new(Default::default()),
        }
    }
}
pub(super) fn locator(identity: UnitIdentity, exact_key: &[u8]) -> Vec<u8> {
    // Exact identity is a locator only; current key, ledger, ABI and origins still admit.
    let mut key = crate::symbolic::shared_procedure_code::key(identity, None);
    key.extend_from_slice(exact_key);
    key
}
impl SessionSymbolicMemo {
    pub(crate) fn current_revision() -> Self {
        Self {
            publication: Some(Arc::new(Owner::default())),
            ..Self::default()
        }
    }
    pub(crate) fn for_request(&self, publishable: bool) -> Arc<Self> {
        let Some(owner) = &self.publication else {
            // Standalone compatibility fixtures have no persistent publication owner.
            return Arc::new(Self::default());
        };
        let lease = Leases {
            records: owner.values.lease(),
            code: self.shared_code_pool.as_ref().map(|pool| pool.lease()),
        };
        let attempt = if publishable {
            owner.publication.begin(lease)
        } else {
            owner.publication.begin_ephemeral(lease)
        };
        Arc::new(Self {
            publication: Some(Arc::clone(owner)),
            attempt: Some(attempt),
            shared_code: None,
            shared_code_pool: self.shared_code_pool.clone(),
            receipt_groups: Arc::clone(&self.receipt_groups),
            admitted: Arc::clone(&self.admitted),
            reused: Arc::clone(&self.reused),
            pruned: Arc::clone(&self.pruned),
            declines: Arc::clone(&self.declines),
            ..Self::default()
        })
    }
    pub(super) fn share_current_code(&self, value: &mut crate::symbolic::PreparedContribution) {
        if let Some(attempt) = &self.attempt {
            attempt.with_pending(|leases| {
                if let Some(lease) = &leases.code {
                    value.share_code(lease);
                }
            });
        } else if let Some(lease) = &self.shared_code {
            value.share_code(lease);
        }
    }
    pub(crate) fn publish_successful(&self) -> bool {
        self.attempt
            .as_ref()
            .is_some_and(|attempt| attempt.publish_successful())
    }
    pub(super) fn insert_record(&self, identity: UnitIdentity, record: Record) -> bool {
        if record
            .reads
            .iter()
            .any(|read| read.domain != read.query.domain())
        {
            return false;
        }
        if let Some(attempt) = &self.attempt {
            let key = locator(identity, &record.key);
            let reads = record.reads.clone();
            let versions = Arc::clone(&record.versions);
            // Current-roster symbolic retention has no byte admission policy;
            // actual payload ownership remains reported by the explicit census.
            attempt
                .with_pending(|leases| {
                    leases.records.insert_with_qualified_receipt(
                        key.into(),
                        reads,
                        versions,
                        1,
                        || record,
                    )
                })
                .flatten()
                .is_some()
        } else {
            self.records
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .insert(identity, Arc::new(record));
            true
        }
    }
    pub(super) fn visit_records(&self, mut visit: impl FnMut(&Arc<Record>)) -> usize {
        let mut count = 0;
        if let Some(owner) = &self.publication {
            owner.values.visit_storage(|view| {
                if let dm_session::ArtifactStorageView::Entry { value, .. } = view {
                    count += 1;
                    visit(value);
                }
            });
        }
        // The map exists only for standalone compatibility callers. Production
        // request facades exclusively insert/claim through the shared core.
        let records = self
            .records
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        records.values().for_each(visit);
        count + records.len()
    }
}

#[cfg(test)]
#[path = "symbolic_publication_tests.rs"]
mod tests;
