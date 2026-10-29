//! Pointer-deduplicated lease metadata plus its existing lexical owners.
use super::*;
impl HeapCensus {
    pub(crate) fn source_acquisition(&mut self, acquired: &dm_preprocess::SourceAcquisitionLease) {
        use dm_preprocess::source_acquisition::AcquisitionStorage as Storage;
        acquired.visit_storage(|storage| match storage {
            Storage::Object { address, bytes } => {
                self.buffer("source_acquisition.metadata", address, bytes, bytes);
            }
            Storage::Receipt {
                address,
                bytes,
                value,
            } => {
                if self.buffer("source_acquisition.metadata", address, bytes, bytes) {
                    if let Some((path, fact_path, issuer)) =
                        crate::input_snapshot::recorded_source_receipt_storage(value)
                    {
                        self.path("source_acquisition.receipt_paths", path);
                        self.path("source_acquisition.receipt_paths", fact_path);
                        self.arc_object("source_acquisition.issuer", issuer);
                    } else {
                        self.unknown(
                            "source_acquisition.metadata",
                            "opaque custom provider receipt nested allocations not exposed",
                        );
                    }
                }
            }
            Storage::Source(source) => self.source_text("source_acquisition.text", source),
        });
        self.unknown("source_acquisition.metadata","Known capacities expose lease/core/receipt records only; capture admission separately adds 2*usize control-block allowance per unique Arc metadata owner, plus entry-path and issuer owners");
    }
    pub(crate) fn semantic_source_evidence(
        &mut self,
        evidence: &Arc<crate::input_snapshot::SemanticSourceEvidence>,
    ) {
        if !self.arc_object("semantic_source_admission", evidence) {
            return;
        }
        // Separate callback passes avoid holding two mutable census borrows.
        evidence.visit_storage(
            |address, bytes| {
                self.buffer("semantic_source_admission.entries", address, bytes, bytes);
            },
            |_, _| {},
        );
        evidence.visit_storage(
            |_, _| {},
            |path, acquired| {
                self.arc_path("semantic_source_admission.paths", path);
                if let Some(acquired) = acquired {
                    self.source_acquisition(acquired);
                }
            },
        );
    }
}
#[cfg(test)]
#[path = "acquisition_tests.rs"]
mod tests;
