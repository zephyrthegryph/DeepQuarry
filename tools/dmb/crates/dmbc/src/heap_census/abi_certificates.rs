//! Borrowed ABI certificates and retained artifact payloads; never reserialize.
use super::*;
#[path = "abi_compact.rs"]
pub(crate) mod compact;
#[path = "abi_input_indexes.rs"]
pub(crate) mod input_indexes;
impl HeapCensus {
    pub(crate) fn prepared_canonical(
        &mut self,
        certificate: &Arc<crate::procedure_policy::PreparedCanonical>,
    ) {
        if self.arc_object("prepared_abi.certificate", certificate) {
            certificate.visit_storage(|inputs, bytes, abi| {
                self.shared_procedure_inputs(inputs);
                self.slice("prepared_abi.canonical_bytes", bytes, true);
                if let Some(abi) = abi {
                    self.abi(abi);
                }
            });
        }
    }
    fn abi_engine_owner(&mut self, engine: &Arc<crate::runner_host::EnginePayload>) {
        if self.arc_object("prepared_abi.engine_owner", engine) {
            self.slice("prepared_abi.engine_bytes", &engine.bytes, true);
            self.unknown("prepared_abi.engine_owner", "shared engine parsed snapshot, normalized-declaration and optional link owners retain private/nested storage not exposed here; bytes counted exactly");
        }
    }
    pub(crate) fn abi_artifacts(&mut self, artifacts: &crate::driver_facts::AbiArtifacts) {
        if let Some(engine) = artifacts.engine_owner() {
            self.abi_engine_owner(engine);
        }
        artifacts.visit_group_storage(|address, len, capacity| {
            self.buffer("prepared_abi.receipt_group_index", address, len, capacity);
            self.unknown(
                "prepared_abi.receipt_group_index",
                "private weak-group BTree keys/nodes excluded",
            );
        });
        artifacts.visit_storage(|view| match view {
            dm_session::ObservedArtifactStorageView::Store { buckets, entries } => {
                self.observe_items("prepared_abi.artifact_index", entries);
                if buckets != 0 {
                    self.unknown(
                        "prepared_abi.artifact_index",
                        "private observed-store BTree backing and control blocks excluded",
                    );
                }
            }
            dm_session::ObservedArtifactStorageView::Bucket {
                address,
                len,
                capacity,
                element_size,
            } => {
                self.buffer(
                    "prepared_abi.artifact_buckets",
                    address,
                    len.saturating_mul(element_size),
                    capacity.saturating_mul(element_size),
                );
            }
            dm_session::ObservedArtifactStorageView::Entry {
                key,
                reads,
                versions,
                value,
            } => {
                self.slice("prepared_abi.artifact_keys", key, true);
                if self.receipt("prepared_abi.reads", reads) {
                    for read in reads.iter() {
                        match &read.answer {
                            crate::driver_facts::abi_artifacts::observations::Answer::Unissued => {},
                            crate::driver_facts::abi_artifacts::observations::Answer::Semantic(answer) =>
                                super::resident_weight::answer(self, answer),
                            crate::driver_facts::abi_artifacts::observations::Answer::BatchInputs(inputs) => {
                                if self.arc_object("prepared_abi.batch_inputs", inputs) {
                                    self.callable_abi_graph(&inputs.graph);
                                    self.observe_items("prepared_abi.weak_engine_issuer", 1);
                                    self.observe_items("prepared_abi.batch_boundaries", inputs.boundaries.len());
                                    self.unknown("prepared_abi.batch_boundaries", "private BTree backing excluded");
                                    for boundary in inputs.boundaries.values() {
                                        if let crate::driver_facts::abi_artifacts::observations::Boundary::Intrinsic{layout,..}=boundary {
                                            for bytes in [&layout.display_name,&layout.description].into_iter().flatten() {self.vec_payload("prepared_abi.boundary_layout",bytes);}
                                            if let dm_codegen_byond::procedure_abi::Category::Text(bytes)=&layout.category {self.vec_payload("prepared_abi.boundary_layout",bytes);}
                                        }
                                    }
                                }
                            }
                            crate::driver_facts::abi_artifacts::observations::Answer::Inputs(inputs) => {
                                if self.arc_object("prepared_abi.observed_inputs", inputs) {
                                    self.procedure_metadata("prepared_abi.metadata", &inputs.metadata);
                                    if let Some(ancestry) = &inputs.ancestry { self.slice("prepared_abi.ancestry", ancestry, true); }
                                    if let Some(abi) = &inputs.predecessor { self.abi(abi); }
                                    self.observe_items("prepared_abi.weak_engine_issuer", 1);
                                    if let crate::driver_facts::abi_artifacts::observations::Boundary::Intrinsic{layout,..} = &inputs.boundary {
                                        for bytes in [&layout.display_name,&layout.description].into_iter().flatten() {
                                            self.vec_payload("prepared_abi.boundary_layout", bytes);
                                        }
                                        if let dm_codegen_byond::procedure_abi::Category::Text(bytes)=&layout.category {
                                            self.vec_payload("prepared_abi.boundary_layout", bytes);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                self.slice("prepared_abi.versions", versions, true);
                if self.arc_object("prepared_abi.artifact_payload", value) {
                    match value.as_ref() {
                        crate::driver_facts::abi_artifacts::Artifact::Unit(unit) => self.abi_unit_artifact(unit),
                        crate::driver_facts::abi_artifacts::Artifact::Batch(recipe) => {
                            if self.arc_object("prepared_abi.batch_recipe", recipe) {
                                if self.slice("prepared_abi.batch_units", &recipe.units, true) {
                                    for (_, unit) in recipe.units.iter() { self.abi_unit_artifact(unit); }
                                }
                                if self.slice("prepared_abi.batch_rows", &recipe.rows, true) {
                                    for row in recipe.rows.iter() {
                                        self.abi_unit_artifact(&row.unit);
                                        self.receipt("prepared_abi.batch_row_reads", &row.reads);
                                        self.slice("prepared_abi.batch_row_versions", &row.versions, true);
                                    }
                                }
                                if let Some(binding) = recipe.binding.lock().unwrap_or_else(|e| e.into_inner()).as_ref() {
                                    self.prepared_abi_units(binding);
                                }
                                if self.vec_payload("prepared_abi.batch_keys", &recipe.keys) {
                                    for key in &recipe.keys {self.slice("prepared_abi.artifact_keys",key,true);}
                                }
                            }
                        }
                    }
                }
            }
        });
        if let Some((leaves, variants, domains, subscriptions)) =
            artifacts.visit_incidence_storage(|leaf| {
                self.slice("prepared_abi.incidence_reads", leaf, true);
            })
        {
            self.observe_items(
                "prepared_abi.incidence_index",
                leaves + variants + domains + subscriptions,
            );
            if leaves + variants + domains + subscriptions != 0 {
                self.unknown("prepared_abi.incidence_index","private reverse-index BTree nodes and control blocks excluded; retained receipt leaves share existing ledger");
            }
        }
    }
    fn abi_unit_artifact(&mut self, unit: &Arc<crate::driver_facts::abi_artifacts::UnitArtifact>) {
        if self.arc_object("prepared_abi.unit_payload", unit) {
            self.shared_procedure_inputs(&unit.inputs);
            self.abi(&unit.abi);
            if let Some(certificate) = &unit.canonical {
                self.prepared_canonical(certificate);
            }
        }
    }
    pub(crate) fn callable_abi_graph(&mut self, graph: &Arc<dm_tree::frontend::CallableAbiGraph>) {
        if self.arc_object("frontend.callable_abi_graph", graph) {
            graph.visit_storage(|entries, ancestry| {
                if self.vec_payload("frontend.callable_abi_meanings", entries) {
                    for entry in entries {
                        self.procedure_metadata("prepared_abi.metadata", &entry.metadata);
                    }
                }
                if self.vec_payload("frontend.callable_abi_ancestry_descriptors", ancestry) {
                    for (_, paths) in ancestry {
                        self.slice("frontend.callable_abi_ancestry", paths, true);
                    }
                }
            });
        }
    }
    pub(crate) fn callable_abi_roster(
        &mut self,
        roster: &Arc<dm_tree::frontend::CallableAbiRoster>,
    ) {
        if self.arc_object("frontend.callable_abi_roster", roster) {
            self.callable_abi_graph(roster.graph());
            roster.visit_storage(|entries, types| {
                if self.vec_payload("frontend.callable_abi_entries", entries) {
                    for entry in entries {
                        self.procedure_metadata("prepared_abi.metadata", &entry.metadata);
                    }
                }
                if self.slice("frontend.callable_abi_types", types, true) {
                    for ty in types.iter() {
                        self.slice("frontend.callable_abi_type_members", &ty.members, true);
                    }
                }
            });
        }
    }
}
