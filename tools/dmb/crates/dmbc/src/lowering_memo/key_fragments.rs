//! One byte-order producer for persisted keys and their disk locators.
use super::*;
impl CurrentKey<'_> {
    pub(crate) fn visit_fragments(&self, prepared: &PreparedKey, mut visit: impl FnMut(&[u8])) {
        let metadata = self.metadata.canonical_bytes();
        visit(PREFIX);
        visit(&self.prefix);
        for part in [metadata.as_slice(), self.source] {
            visit(&(part.len() as u64).to_le_bytes());
            visit(part);
        }
        visit(&[self.termination]);
        if self.references {
            visit(&[0]);
            visit(dm_ir::SELECTED_REFERENCES_POLICY);
        }
        if self.selections {
            visit(b"selected-facts-only-v1");
        }
        prepared.visit_fragments(&mut visit);
    }
    pub fn materialize(&self, prepared: &PreparedKey) -> Vec<u8> {
        let mut key = Vec::new();
        self.visit_fragments(prepared, |part| key.extend_from_slice(part));
        key
    }
    pub(crate) fn record_key(&self, prepared: &PreparedKey) -> dm_cache::RecordKey {
        let mut hash = xxhash_rust::xxh3::Xxh3::new();
        self.visit_fragments(prepared, |part| hash.update(part));
        dm_cache::RecordKey {
            stage: 2,
            version: super::super::PROCEDURE_VERSION,
            content: hash.digest128(),
        }
    }
}

impl PreparedKey {
    fn visit_fragments(&self, mut visit: impl FnMut(&[u8])) {
        match self {
            Self::Parsed(bytes) => visit(bytes),
            Self::Issued(bytes) => {
                visit(bytes);
                visit(&[1]);
                let transform = crate::procedure_policy::PreparedReplay::TRANSFORM;
                visit(&(transform.len() as u64).to_le_bytes());
                visit(transform);
            }
        }
    }
    #[cfg(test)]
    pub(super) fn append(&self, bytes: &mut Vec<u8>) {
        self.visit_fragments(|part| bytes.extend_from_slice(part));
    }
}
#[cfg(test)]
#[path = "key_fragments_tests.rs"]
mod tests;
