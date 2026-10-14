//! Shared lexical backing and its lazy span-fingerprint cache.
use super::*;
impl HeapCensus {
    pub(super) fn source_text(&mut self, owner: &str, value: &dm_preprocess::SourceText) {
        value.visit_fingerprint_storage(|pointer, logical, capacity| {
            self.buffer(owner, pointer, logical, capacity);
        });
        value.visit_storage(|pointer, size, storage| {
            if self.buffer(owner, pointer, size, size) {
                match storage {
                    dm_preprocess::SourceTextStorage::Original(text) => self.arc_text(owner, text),
                    dm_preprocess::SourceTextStorage::Transformed(text) => self.string(owner, text),
                }
            }
        });
    }
}
