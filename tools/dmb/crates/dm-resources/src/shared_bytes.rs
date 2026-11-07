//! Immutable captured bytes whose original vector allocation transfers intact.
use sha2::{Digest, Sha256};
use std::{
    ops::Deref,
    sync::{Arc, OnceLock, Weak},
};

use dm_preprocess::source_arena_credit::{SourceArenaControlCredit, SourceArenaCredit};

/// One immutable payload owner; memoized facts cannot outlive or detach from its bytes.
pub struct SharedBytesOwner {
    bytes: Vec<u8>,
    fingerprint: OnceLock<PayloadFingerprint>,
    // Rust drops fields in declaration order: Vec storage before its grant.
    payload: Option<SourceArenaCredit>,
    control: Option<SourceArenaControlCredit>,
}
#[derive(Debug)]
struct PayloadFingerprint {
    sha256: [u8; 32],
    nqcrc: u32,
}
impl SharedBytesOwner {
    /// Borrowed allocation view for retained-owner accounting; mutation is unavailable.
    pub fn bytes(&self) -> &Vec<u8> {
        &self.bytes
    }
}
impl PartialEq for SharedBytesOwner {
    fn eq(&self, other: &Self) -> bool {
        self.bytes == other.bytes
    }
}
impl Eq for SharedBytesOwner {}

pub struct SharedBytes(Option<Arc<SharedBytesOwner>>);
impl Clone for SharedBytes {
    fn clone(&self) -> Self { Self(Some(Arc::clone(self.arc()))) }
}
impl std::fmt::Debug for SharedBytes {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_tuple("SharedBytes").field(&self.as_slice()).finish()
    }
}
impl PartialEq for SharedBytes {
    fn eq(&self, other: &Self) -> bool { self.shared_owner() == other.shared_owner() }
}
impl Eq for SharedBytes {}
impl Drop for SharedBytes {
    fn drop(&mut self) {
        if let Some(owner) = self.0.take() {
            drop(Arc::into_inner(owner));
        }
    }
}

/// The actual weak Arc drops before its immutable control grant alias.
#[derive(Clone, Default)]
pub struct WeakSharedBytes {
    owner: Weak<SharedBytesOwner>,
    control: Option<SourceArenaControlCredit>,
}
impl WeakSharedBytes {
    pub fn upgrade(&self) -> Option<SharedBytes> { self.owner.upgrade().map(|owner| SharedBytes(Some(owner))) }
    pub fn as_ptr(&self) -> *const SharedBytesOwner { self.owner.as_ptr() }
    pub fn strong_count(&self) -> usize { self.owner.strong_count() }
    pub fn ptr_eq(&self, other: &Self) -> bool { Weak::ptr_eq(&self.owner, &other.owner) }
    pub fn source_arena_control_credit(&self) -> Option<&SourceArenaControlCredit> { self.control.as_ref() }
}
impl SharedBytes {
    fn arc(&self) -> &Arc<SharedBytesOwner> { self.0.as_ref().expect("live shared bytes") }
    pub fn owner_address(&self) -> usize { Arc::as_ptr(self.arc()) as usize }
    pub fn downgrade(&self) -> WeakSharedBytes {
        WeakSharedBytes { owner: Arc::downgrade(self.arc()), control: self.arc().control.clone() }
    }
    pub fn source_arena_payload_credit(&self) -> Option<&SourceArenaCredit> { self.arc().payload.as_ref() }
    pub fn source_arena_control_credit(&self) -> Option<&SourceArenaControlCredit> { self.arc().control.as_ref() }
    pub fn owner_allocation_bytes() -> usize {
        std::mem::size_of::<SharedBytesOwner>() + 2 * std::mem::size_of::<usize>()
    }
    #[doc(hidden)]
    pub fn from_source_arena(
        bytes: Vec<u8>, payload: SourceArenaCredit, control: SourceArenaControlCredit,
    ) -> std::io::Result<Self> {
        if bytes.capacity() != payload.reserved_bytes()
            || Self::owner_allocation_bytes() != control.reserved_bytes()
        {
            // Drop the actual buffer before dropping the rejected credits.
            drop(bytes);
            return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,
                "exceptional raw byte backing differs from its admitted storage"));
        }
        Ok(Self(Some(Arc::new(SharedBytesOwner {
            bytes, fingerprint: OnceLock::new(), payload: Some(payload), control: Some(control),
        }))))
    }
    pub fn bytes(&self) -> &Vec<u8> { self.shared_owner().bytes() }
    pub fn as_slice(&self) -> &[u8] {
        self.arc().bytes.as_slice()
    }
    pub fn capacity(&self) -> usize {
        self.arc().bytes.capacity()
    }
    pub fn shared_owner(&self) -> &SharedBytesOwner {
        self.arc()
    }
    /// Initialize both canonical facts once, on the capture worker that first hashes bytes.
    fn fingerprint(&self) -> &PayloadFingerprint {
        self.arc().fingerprint.get_or_init(|| {
            let mut sha256 = Sha256::new();
            let mut nqcrc = u32::MAX;
            // Both algorithms visit the same bounded working set. CRC continues its
            // ordinary state across chunks; no independently composed checksums.
            for chunk in self.as_slice().chunks(64 * 1024) {
                sha256.update(chunk);
                nqcrc = byond_dmb::hash::nqcrc(nqcrc, chunk);
            }
            PayloadFingerprint {
                sha256: sha256.finalize().into(),
                nqcrc,
            }
        })
    }
    pub fn sha256(&self) -> [u8; 32] {
        self.fingerprint().sha256
    }
    /// Checksum of the full private payload, never a public recorded resource ID.
    pub(crate) fn nqcrc(&self) -> u32 {
        self.fingerprint().nqcrc
    }
    pub fn ptr_eq(&self, other: &Self) -> bool {
        Arc::ptr_eq(self.arc(), other.arc())
    }
}
impl From<Vec<u8>> for SharedBytes {
    fn from(bytes: Vec<u8>) -> Self {
        Self(Some(Arc::new(SharedBytesOwner {
            bytes, fingerprint: OnceLock::new(), payload: None, control: None,
        })))
    }
}
impl From<&[u8]> for SharedBytes {
    fn from(bytes: &[u8]) -> Self {
        bytes.to_vec().into()
    }
}
/// Compatibility conversion; filesystem capture uses the zero-copy Vec path.
impl From<Arc<[u8]>> for SharedBytes {
    fn from(bytes: Arc<[u8]>) -> Self {
        bytes.as_ref().into()
    }
}
impl Deref for SharedBytes {
    type Target = [u8];
    fn deref(&self) -> &[u8] {
        self.as_slice()
    }
}
impl AsRef<[u8]> for SharedBytes {
    fn as_ref(&self) -> &[u8] {
        self.as_slice()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn vector_allocation_capacity_and_binary_bytes_transfer_without_copy() {
        let mut bytes = Vec::with_capacity(127);
        bytes.extend_from_slice(&[0, 255, 22, 128]);
        let pointer = bytes.as_ptr();
        let payload = SharedBytes::from(bytes);
        assert_eq!(payload.as_ptr(), pointer);
        assert_eq!(payload.capacity(), 127);
        assert_eq!(payload.as_slice(), [0, 255, 22, 128]);
        let alias = payload.clone();
        assert!(payload.ptr_eq(&alias));
        assert_eq!(alias.as_ptr(), pointer);
    }
    #[test]
    fn cloned_aliases_share_the_digest_but_equality_ignores_memo_state() {
        let payload = SharedBytes::from(&b"immutable actual bytes"[..]);
        let alias = payload.clone();
        let independent = SharedBytes::from(payload.as_slice());
        assert!(payload.arc().fingerprint.get().is_none());
        assert!(independent.arc().fingerprint.get().is_none());
        let expected: [u8; 32] = Sha256::digest(payload.as_slice()).into();
        assert_eq!(alias.sha256(), expected);
        assert_eq!(payload.arc().fingerprint.get().unwrap().sha256, expected);
        assert!(independent.arc().fingerprint.get().is_none());
        assert_eq!(payload, independent);
        assert_eq!(payload.sha256(), expected);
        assert_eq!(payload.as_ptr(), alias.as_ptr());
    }
    #[test]
    fn combined_facts_equal_independent_canonical_hashes_across_chunk_boundaries() {
        for length in [0, 1, 65535, 65536, 65537, 131103] {
            let bytes = (0..length)
                .map(|i| (i * 37 + i / 255) as u8)
                .collect::<Vec<_>>();
            let expected_sha: [u8; 32] = Sha256::digest(&bytes).into();
            let expected_crc = byond_dmb::hash::nqcrc(u32::MAX, &bytes);
            let payload = SharedBytes::from(bytes);
            let alias = payload.clone();
            assert_eq!(payload.sha256(), expected_sha);
            assert_eq!(alias.nqcrc(), expected_crc);
            assert!(std::ptr::eq(payload.fingerprint(), alias.fingerprint()));
        }
    }
}
