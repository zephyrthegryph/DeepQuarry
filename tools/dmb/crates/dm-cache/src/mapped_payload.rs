//! Lifetime ownership for a checksum/container-validated payload in the existing immutable segment.
use super::{RecordKey, RecordView, Segment};
use crate::CacheSnapshot;
use std::{ops::Range, sync::Arc};

/// Immutable bytes with a checked container lifetime. Acceptance is a separate
/// caller proof: callback-local backing can exist before typed/current admission.
/// This owns only its
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
        Self::capture_bytes(segment, view.key, view.payload)
    }
    fn capture_bytes(segment: &Arc<Segment>, key: RecordKey, payload: &[u8]) -> Self {
        let start = (payload.as_ptr() as usize)
            .checked_sub(segment.map.as_ptr() as usize)
            .expect("accepted payload belongs to this mapped segment");
        let end = start
            .checked_add(payload.len())
            .expect("mapped range overflow");
        assert!(end <= segment.map.len(), "accepted mapped payload extent");
        Self {
            segment: Arc::clone(segment),
            key,
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
    /// Preserve a borrowed decoded field only when its exact extent belongs to
    /// this payload. Pointer containment licenses storage lifetime, not meaning.
    pub fn subslice(&self, bytes: &[u8]) -> Option<Self> {
        let start = (bytes.as_ptr() as usize).checked_sub(self.bytes().as_ptr() as usize)?;
        self.subrange(start..start.checked_add(bytes.len())?)
    }
    /// Physical mapping owner/count for deduplicated retention accounting.
    /// Arc control blocks and private index backing remain outside this count.
    pub fn mapping_storage(&self) -> (usize, usize) {
        (Arc::as_ptr(&self.segment) as usize, self.segment.map.len())
    }
}
impl CacheSnapshot {
    /// Provide byte-lifetime backing after container/checksum validation, during
    /// SAME typed/current admission. The backing is NOT semantic acceptance;
    /// rejected callbacks may hold bytes but cannot mark this key reachable or
    /// authorize compiler output. Only Ok(true) returns the admitted view.
    pub fn get_candidate_backed<'a>(
        &'a self,
        key: RecordKey,
        validate_and_accept: impl Fn(&[u8], &[(u64, &[u8])], &MappedPayload) -> Result<bool, String>,
    ) -> Option<RecordView<'a>> {
        self.get_candidate_with(
            key,
            |bytes, symbols, segment| {
                let backing = MappedPayload::capture_bytes(segment, key, bytes);
                validate_and_accept(bytes, symbols, &backing)
            },
            |_, view| view,
        )
    }

    /// SAME checksum, whole typed-bucket validation, candidate order, rejection
    /// and used-key accounting as get_candidate; only accepted byte ownership
    /// differs. A false/invalid candidate cannot mint a mapped owner.
    pub fn get_candidate_mapped(
        &self,
        key: RecordKey,
        validate_and_accept: impl Fn(&[u8], &[(u64, &[u8])]) -> Result<bool, String>,
    ) -> Option<MappedPayload> {
        self.get_candidate_with(
            key,
            |bytes, symbols, _| validate_and_accept(bytes, symbols),
            MappedPayload::capture,
        )
    }
}
#[cfg(test)]
#[path = "mapped_payload_tests.rs"]
mod tests;
