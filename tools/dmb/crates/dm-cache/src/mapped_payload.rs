//! Lifetime ownership for an accepted payload in the existing immutable segment.
use super::{RecordKey, RecordView, Segment};
use crate::CacheSnapshot;
use std::{ops::Range, sync::Arc};

/// Immutable bytes from an accepted current candidate. This owns only its
/// existing segment, never a snapshot, source tree or additional cache. It
/// preserves byte lifetime; callers must reissue semantic/current-source proofs
/// on reuse. Supersession does not mutate escaped owners. No alignment or native
/// endian layout is promised, so word consumers must read little-endian bytes.
#[derive(Clone)]
pub struct MappedPayload {
    segment: Arc<Segment>,
    key: RecordKey,
    range: Range<usize>,
}
impl MappedPayload {
    fn capture(segment: &Arc<Segment>, view: RecordView<'_>) -> Self {
        let start = (view.payload.as_ptr() as usize)
            .checked_sub(segment.map.as_ptr() as usize)
            .expect("accepted payload belongs to this mapped segment");
        let end = start
            .checked_add(view.payload.len())
            .expect("mapped range overflow");
        assert!(end <= segment.map.len(), "accepted mapped payload extent");
        Self {
            segment: Arc::clone(segment),
            key: view.key,
            range: start..end,
        }
    }
    pub fn bytes(&self) -> &[u8] {
        &self.segment.map[self.range.clone()]
    }
    pub fn key(&self) -> RecordKey {
        self.key
    }
    /// A checked byte region of the SAME accepted payload. This issues no new
    /// semantic admission and performs no cast to aligned typed memory.
    pub fn subrange(&self, range: Range<usize>) -> Option<Self> {
        if range.start > range.end || range.end > self.range.len() {
            return None;
        }
        Some(Self {
            segment: Arc::clone(&self.segment),
            key: self.key,
            range: self.range.start.checked_add(range.start)?
                ..self.range.start.checked_add(range.end)?,
        })
    }
    /// Physical mapping owner/count for deduplicated retention accounting.
    /// Arc control blocks and private index backing remain outside this count.
    pub fn mapping_storage(&self) -> (usize, usize) {
        (Arc::as_ptr(&self.segment) as usize, self.segment.map.len())
    }
}
impl CacheSnapshot {
    /// SAME checksum, whole typed-bucket validation, candidate order, rejection
    /// and used-key accounting as get_candidate; only accepted byte ownership
    /// differs. A false/invalid candidate cannot mint a mapped owner.
    pub fn get_candidate_mapped(
        &self,
        key: RecordKey,
        validate_and_accept: impl Fn(&[u8], &[(u64, &[u8])]) -> Result<bool, String>,
    ) -> Option<MappedPayload> {
        self.get_candidate_with(key, validate_and_accept, MappedPayload::capture)
    }
}
#[cfg(test)]
#[path = "mapped_payload_tests.rs"]
mod tests;
