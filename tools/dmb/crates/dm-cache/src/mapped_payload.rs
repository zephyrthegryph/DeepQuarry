//! Lifetime ownership for a checksum/container-validated payload in the existing immutable segment.
use super::{AlignedBytes, RecordKey, RecordView, Segment};
use crate::CacheSnapshot;
use std::{ops::Range, sync::Arc};

/// Immutable bytes with a checked container lifetime. Acceptance is a separate
/// caller proof: callback-local backing can exist before typed/current admission.
/// This owns only its
/// existing immutable mapping, never its Segment index, snapshot, source tree
/// or additional cache. It
/// preserves byte lifetime; callers must reissue semantic/current-source proofs
/// on reuse. Supersession does not mutate escaped owners. No alignment or native
/// endian layout is promised, so word consumers must read little-endian bytes.
#[derive(Clone)]
pub struct MappedPayload {
    backing: Backing,
    key: RecordKey,
    range: Range<usize>,
}
/// Where the bytes live: the file mapping, or (for a compressed record) the decoded copy the segment made of it.
#[derive(Clone)]
enum Backing {
    Map(Arc<memmap2::Mmap>),
    Decoded(Arc<AlignedBytes>),
}
impl Backing {
    fn bytes(&self) -> &[u8] {
        match self {
            Backing::Map(map) => map,
            Backing::Decoded(owner) => owner.bytes(),
        }
    }
}
impl MappedPayload {
    fn capture(segment: &Arc<Segment>, view: RecordView<'_>) -> Self {
        Self::capture_bytes(segment, view.key, view.payload)
    }
    fn capture_bytes(segment: &Arc<Segment>, key: RecordKey, payload: &[u8]) -> Self {
        let in_map = (payload.as_ptr() as usize)
            .checked_sub(segment.map_ptr())
            .filter(|start| start + payload.len() <= segment.map_len());
        let (backing, start) = match in_map {
            Some(start) => (Backing::Map(Arc::clone(segment.map_arc())), start),
            None => {
                let owner = segment
                    .decoded_owner(key)
                    .expect("accepted payload belongs to this segment's mapping or decoded copy");
                let start = (payload.as_ptr() as usize)
                    .checked_sub(owner.bytes().as_ptr() as usize)
                    .expect("accepted decoded payload belongs to its owner");
                (Backing::Decoded(owner), start)
            }
        };
        let end = start
            .checked_add(payload.len())
            .expect("mapped range overflow");
        assert!(end <= backing.bytes().len(), "accepted mapped payload extent");
        Self {
            backing,
            key,
            range: start..end,
        }
    }
    /// Whether the bytes are the file mapping itself (reclaimable pages) and not a decoded private copy.
    pub fn is_mapped(&self) -> bool {
        matches!(self.backing, Backing::Map(_))
    }
    pub fn bytes(&self) -> &[u8] {
        &self.backing.bytes()[self.range.clone()]
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
            backing: self.backing.clone(),
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
    /// Exact fixed heap owner of this mapping. The file-backed extent is
    /// reported separately; it is not a Rust heap buffer or private-byte sample.
    /// Arc control/allocator allowance is the caller's existing policy.
    pub fn visit_owned_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        match &self.backing {
            Backing::Map(map) => {
                let size = std::mem::size_of::<memmap2::Mmap>();
                visit(Arc::as_ptr(map) as usize, size, size);
            }
            Backing::Decoded(owner) => {
                // The decoded buffer itself, as a Vec<u8> owner reports its allocation.
                let capacity = owner.bytes().len().div_ceil(16) * 16;
                visit(owner.bytes().as_ptr() as usize, owner.bytes().len(), capacity);
            }
        }
    }
    /// File-backed extent and shared mapping identity, separate from heap.
    /// No Segment index/rejection state is retained by this byte owner.
    pub fn mapping_storage(&self) -> (usize, usize) {
        match &self.backing {
            Backing::Map(map) => (Arc::as_ptr(map) as usize, map.len()),
            // A decoded copy is heap, reported through `visit_owned_storage`, not as a file-backed extent.
            Backing::Decoded(owner) => (owner.bytes().as_ptr() as usize, owner.bytes().len()),
        }
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
