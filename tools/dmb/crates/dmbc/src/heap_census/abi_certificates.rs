//! Borrowed ABI certificates and retained artifact payloads; never reserialize.
use super::*;
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
                            crate::driver_facts::abi_artifacts::observations::Answer::Semantic(answer) =>
                                super::resident_weight::answer(self, answer),
                            crate::driver_facts::abi_artifacts::observations::Answer::Inputs(inputs) => {
                                if self.arc_object("prepared_abi.observed_inputs", inputs) {
                                    self.procedure_metadata("prepared_abi.metadata", &inputs.metadata);
                                    if let Some(abi) = &inputs.predecessor { self.abi(abi); }
                                    self.abi_engine_owner(&inputs.engine);
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
                    self.shared_procedure_inputs(&value.inputs);
                    self.abi(&value.abi);
                    if let Some(certificate) = &value.canonical {
                        self.prepared_canonical(certificate);
                    }
                }
            }
        });
    }
}
