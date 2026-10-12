//! Current-answer byte ownership, not a certificate or cached verdict.
use crate::ResolvedMeaning;
use std::sync::Arc;
#[derive(Clone, Debug)]
pub struct CanonicalResolvedAnswer {
    pub answer: ResolvedMeaning,
    canonical: Arc<[u8]>,
}
impl CanonicalResolvedAnswer {
    pub fn new(answer: ResolvedMeaning) -> Self {
        let canonical = answer.canonical_bytes().into();
        Self { answer, canonical }
    }
    pub fn canonical(&self) -> &[u8] {
        &self.canonical
    }
    pub(crate) fn with_bytes(answer: ResolvedMeaning, canonical: Arc<[u8]>) -> Self {
        Self { answer, canonical }
    }
}
