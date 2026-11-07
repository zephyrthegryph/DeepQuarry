//! Exact exceptional source payload owners; no duplicate normal byte buffer.
use super::*;
impl HeapCensus {
    pub fn exceptional_source_inputs<P: crate::input_snapshot::SnapshotProvider>(
        &mut self,
        inputs: &crate::input_snapshot::RecordingInputs<P>,
    ) {
        self.unknown(
            "source_originals.index",
            "private BTreeMap node backing excluded",
        );
        let result = inputs.visit_exceptional_source_originals(|path, bytes| {
            let owner = "source_originals.bytes";
            self.path(owner, path);
            if self.shared_bytes_owner(owner, bytes) {
                self.vec_payload(owner, bytes.shared_owner().bytes());
            }
        });
        if let Err(error) = result {
            self.unknown("source_originals.error", &error.to_string());
        }
    }
}
