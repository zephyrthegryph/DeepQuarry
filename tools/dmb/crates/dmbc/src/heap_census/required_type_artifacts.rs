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
                self.receipt("required_types.reads", reads);
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
                if self.receipt("required_fields.reads", reads) {
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
                if self.receipt("required_parents.reads", reads) {
                    for read in reads.iter() {
                        self.slice("required_parents.type_roster", &read.answer, true);
                    }
                }
                self.slice("required_parents.versions", versions, true);
                self.required_parent_map(value);
            }
        });
        store.allocations.visit_storage(|view| match view {
            V::Store { entries, .. } => self.observe_items("required_allocations.index", entries),
            V::Bucket {
                address,
                len,
                capacity,
                element_size,
            } => {
                self.buffer(
                    "required_allocations.buckets",
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
                self.slice("required_allocations.keys", key, true);
                if self.receipt("required_allocations.reads", reads) {
                    for read in reads.iter() {
                        if let Some(spelling) = &read.answer {
                            self.string("required_allocations.spellings", spelling);
                        }
                    }
                }
                self.slice("required_allocations.versions", versions, true);
                self.required_allocation_roster(value);
            }
        });
        store.prefixes.visit_storage(|view| match view {
            V::Store { entries, .. } => self.observe_items("required_prefix.index", entries),
            V::Bucket { address, len, capacity, element_size } => {
                self.buffer("required_prefix.buckets", address,
                    len.saturating_mul(element_size), capacity.saturating_mul(element_size));
            }
            V::Entry { key, reads, versions, value } => {
                self.slice("required_prefix.keys", key, true);
                if self.receipt("required_prefix.reads", reads) {
                    for read in reads.iter() {
                        self.required_allocation_roster(&read.answer.source);
                        self.vec_payload("required_prefix.fixed", &read.answer.fixed);
                        self.required_parent_map(&read.answer.parents);
                    }
                }
                self.slice("required_prefix.versions", versions, true);
                if self.arc_object("required_prefix.payload", value) {
                    self.vec_payload("required_prefix.order", &value.order);
                    self.vec_payload("required_prefix.requests", &value.requests);
                    self.collection_entries::<dm_ir::SymbolId>("required_prefix.needed",
                        &value.needed as *const _ as usize, value.needed.len());
                    self.unknown("required_prefix.needed", "private HashSet bucket/control backing unavailable; logical entry lower bounds only");
                }
            }
        });
        store.selected.visit_storage(|view| match view {
            V::Store { entries, .. } => self.observe_items("required_selected.index", entries),
            V::Bucket { address, len, capacity, element_size } => {
                self.buffer("required_selected.buckets", address,
                    len.saturating_mul(element_size), capacity.saturating_mul(element_size));
            }
            V::Entry { key, reads, versions, value } => {
                self.slice("required_selected.keys", key, true);
                if self.receipt("required_selected.reads", reads) {
                    for read in reads.iter() {
                        self.slice("required_selected.current_types", &read.answer.types, true);
                        if self.arc_object("required_selected.membership", &read.answer.needed) {
                            self.collection_entries::<dm_ir::SymbolId>("required_selected.membership",
                                Arc::as_ptr(&read.answer.needed) as usize, read.answer.needed.len());
                            self.unknown("required_selected.membership", "private HashSet bucket/control backing unavailable; logical entry lower bounds only");
                        }
                    }
                }
                self.slice("required_selected.versions", versions, true);
                if self.arc_object("required_selected.output", value) {
                    self.slice("required_selected.output_roster", value.as_ref(), true);
                }
            }
        });
        self.unknown("required_types.index","private BTree nodes and allocator metadata excluded; accessible key/read/closure buffers counted, current-roster retention has no byte admission budget");
    }
    fn required_allocation_roster(
        &mut self,
        owner: &Arc<crate::type_creation_order::AllocationRoster>,
    ) {
        if self.arc_object("required_allocations.roster", owner) {
            self.slice("required_allocations.order", owner.shared_order(), true);
        }
    }
    fn required_parent_map(
        &mut self,
        owner: &Arc<std::collections::BTreeMap<dm_ir::SymbolId, Option<dm_ir::SymbolId>>>,
    ) {
        if self.arc_object("required_parents.map", owner) {
            self.collection_entries::<(dm_ir::SymbolId, Option<dm_ir::SymbolId>)>(
                "required_parents.entries",
                Arc::as_ptr(owner) as usize,
                owner.len(),
            );
            self.unknown("required_parents.entries", "private BTree node backing/control capacity unavailable; logical entry lower bounds only");
        }
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
