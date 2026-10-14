//! Current-answer byte ownership, not a certificate or cached verdict.
use crate::ResolvedMeaning;
use std::sync::Arc;
#[derive(Clone, Debug)]
pub struct CanonicalResolvedAnswer {
    answer: ResolvedMeaning,
    canonical: Arc<[u8]>,
}
impl CanonicalResolvedAnswer {
    pub fn new(answer: ResolvedMeaning) -> Self {
        let canonical = answer.canonical_bytes().into();
        Self { answer, canonical }
    }
    pub fn answer(&self) -> &ResolvedMeaning {
        &self.answer
    }
    pub fn into_parts(self) -> (ResolvedMeaning, Arc<[u8]>) {
        (self.answer, self.canonical)
    }
    pub fn canonical(&self) -> &[u8] {
        &self.canonical
    }
    pub(crate) fn with_bytes(answer: ResolvedMeaning, canonical: Arc<[u8]>) -> Self {
        Self { answer, canonical }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn canonical_pair_borrow_and_consumption_preserve_exact_answer_evidence() {
        let pair = CanonicalResolvedAnswer::new(ResolvedMeaning::Presence(false));
        assert_eq!(pair.answer().canonical_bytes(), pair.canonical());
        let cloned = pair.clone();
        let (answer, bytes) = pair.into_parts();
        assert_eq!(answer, *cloned.answer());
        assert_eq!(answer.canonical_bytes(), bytes.as_ref());
        assert_eq!(bytes.as_ptr(), cloned.canonical().as_ptr());
    }
}
