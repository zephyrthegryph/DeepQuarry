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
pub(super) struct BorrowedLocator<'a, 'source> {
    prefix: Vec<u8>,
    key: &'a crate::lowering_memo::key_recipe::CurrentKey<'source>,
    tail: &'a crate::lowering_memo::key_recipe::PreparedKey,
}
impl<'a, 'source> BorrowedLocator<'a, 'source> {
    pub(super) fn new(
        identity: UnitIdentity,
        key: &'a crate::lowering_memo::key_recipe::CurrentKey<'source>,
        tail: &'a crate::lowering_memo::key_recipe::PreparedKey,
    ) -> Self {
        Self {
            prefix: crate::symbolic::shared_procedure_code::key(identity, None),
            key,
            tail,
        }
    }
    pub(super) fn digest(&self) -> u128 {
        let mut hash = xxhash_rust::xxh3::Xxh3::new();
        hash.update(&self.prefix);
        self.key
            .visit_fragments(self.tail, |part| hash.update(part));
        hash.digest128()
    }
    pub(super) fn matches(&self, candidate: &[u8]) -> bool {
        candidate
            .strip_prefix(self.prefix.as_slice())
            .is_some_and(|key| self.key.matches(key, None, self.tail))
    }
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
        self.insert_record_rebinding(identity, record, None)
    }
    pub(super) fn insert_record_rebinding(
        &self,
        identity: UnitIdentity,
        record: Record,
        previous: Option<&Arc<Record>>,
    ) -> bool {
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
                    if let Some(previous) = previous.filter(|previous| {
                        previous.key == record.key
                            && previous.reads == reads
                            && previous.versions == versions
                    }) {
                        return leases.records.rebind_with_qualified_receipt(
                            previous,
                            key.into(),
                            reads,
                            versions,
                            1,
                            || record,
                        );
                    }
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

#[cfg(test)]
#[path = "symbolic_locator_tests.rs"]
mod locator_tests;
