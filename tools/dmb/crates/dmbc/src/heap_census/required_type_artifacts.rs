//! Retained symbolic ancestry owners, observed without canonical serialization.
use super::*;
impl HeapCensus {
    pub(crate) fn required_type_artifacts(
        &mut self,
        store: &crate::required_types::RequiredTypeArtifacts,
    ) {
        use dm_session::ObservedArtifactStorageView as V;
        store.visit_storage(|view| match view {
            V::Store { entries, .. } => self.observe_items("required_types.index", entries),
            V::Bucket {
                address,
                len,
                capacity,
                element_size,
            } => {
                self.buffer(
                    "required_types.buckets",
                    address,
                    len.saturating_mul(element_size),
                    capacity.saturating_mul(element_size),
                );
            }
            V::Entry {
                key,
                reads,
                versions,
                value,
            } => {
                self.slice("required_types.keys", key, true);
                self.slice("required_types.reads", reads, true);
                self.slice("required_types.versions", versions, true);
                if self.arc_object("required_types.closure", value) {
                    self.vec_payload("required_types.ordered", &value.ordered);
                }
            }
        });
        store.fields.visit_storage(|view| match view {
            V::Store { entries, .. } => self.observe_items("required_fields.index", entries),
            V::Bucket {
                address,
                len,
                capacity,
                element_size,
            } => {
                self.buffer(
                    "required_fields.buckets",
                    address,
                    len.saturating_mul(element_size),
                    capacity.saturating_mul(element_size),
                );
            }
            V::Entry {
                key,
                reads,
                versions,
                value,
            } => {
                self.slice("required_fields.keys", key, true);
                if self.slice("required_fields.reads", reads, true) {
                    for read in reads.iter() {
                        super::resident_owner_projection::inspect_field(self, &read.answer);
                    }
                }
                self.slice("required_fields.versions", versions, true);
                if self.arc_object("required_fields.requests", value) {
                    self.vec_payload("required_fields.ordered", value);
                }
            }
        });
        store.parents.visit_storage(|view| match view {
            V::Store { entries, .. } => self.observe_items("required_parents.index", entries),
            V::Bucket {
                address,
                len,
                capacity,
                element_size,
            } => {
                self.buffer(
                    "required_parents.buckets",
                    address,
                    len.saturating_mul(element_size),
                    capacity.saturating_mul(element_size),
                );
            }
            V::Entry {
                key,
                reads,
                versions,
                value,
            } => {
                self.slice("required_parents.keys", key, true);
                if self.slice("required_parents.reads", reads, true) {
                    for read in reads.iter() {
                        self.slice("required_parents.type_roster", &read.answer, true);
                    }
                }
                self.slice("required_parents.versions", versions, true);
                if self.arc_object("required_parents.map", value) {
                    self.observe_items("required_parents.entries", value.len());
                }
            }
        });
        self.unknown("required_types.index","private BTree nodes and allocator metadata excluded; accessible key/read/closure buffers counted, current-roster retention has no byte admission budget");
    }
}
impl crate::lowering_memo::ProcedureMemo {
    pub fn required_type_retention_census(&self) -> Option<HeapCensusReport> {
        self.required_types.as_ref().map(|store| {
            let mut census = HeapCensus::new("retained_required_types");
            if census.arc_object("required_types.store", store) {
                census.required_type_artifacts(store);
            }
            census.finish()
        })
    }
}
