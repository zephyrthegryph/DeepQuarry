//! Borrowed ABI certificates and retained artifact payloads; never reserialize.
use super::*;
impl HeapCensus {
    pub(crate) fn prepared_canonical(
        &mut self,
        certificate: &Arc<crate::procedure_policy::PreparedCanonical>,
    ) {
        if self.arc_object("prepared_abi.certificate", certificate) {
            certificate.visit_storage(|inputs, bytes, abi| {
                self.procedure_inputs(inputs);
                self.slice("prepared_abi.canonical_bytes", bytes, true);
                if let Some(abi) = abi {
                    self.abi(abi);
                }
            });
        }
    }
    pub(crate) fn abi_artifacts(&mut self, artifacts: &crate::driver_facts::AbiArtifacts) {
        artifacts.visit_storage(|view| match view {
            dm_session::ArtifactStorageView::Store { buckets, entries } => {
                self.observe_items("prepared_abi.artifact_index", entries);
                if buckets != 0 {
                    self.unknown(
                        "prepared_abi.artifact_index",
                        "private observed-store BTree backing and control blocks excluded",
                    );
                }
            }
            dm_session::ArtifactStorageView::Bucket {
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
            dm_session::ArtifactStorageView::Entry {
                key,
                reads,
                versions,
                value,
            } => {
                self.slice("prepared_abi.artifact_keys", key, true);
                self.retained_symbolic_ledger(reads, versions);
                if self.arc_object("prepared_abi.artifact_payload", value) {
                    self.procedure_inputs(&value.inputs);
                    self.abi(&value.abi);
                    if let Some(certificate) = &value.canonical {
                        self.prepared_canonical(certificate);
                    }
                }
            }
        });
    }
}
