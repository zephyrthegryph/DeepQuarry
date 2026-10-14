//! Immutable captured bytes whose original vector allocation transfers intact.
use sha2::{Digest, Sha256};
use std::{
    ops::Deref,
    sync::{Arc, OnceLock},
};

/// One immutable payload owner; memoized facts cannot outlive or detach from its bytes.
#[derive(Debug)]
pub struct SharedBytesOwner {
    bytes: Vec<u8>,
    fingerprint: OnceLock<PayloadFingerprint>,
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

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SharedBytes(Arc<SharedBytesOwner>);
impl SharedBytes {
    pub fn as_slice(&self) -> &[u8] {
        self.0.bytes.as_slice()
    }
    pub fn capacity(&self) -> usize {
        self.0.bytes.capacity()
    }
    pub fn shared_owner(&self) -> &Arc<SharedBytesOwner> {
        &self.0
    }
    /// Initialize both canonical facts once, on the capture worker that first hashes bytes.
    fn fingerprint(&self) -> &PayloadFingerprint {
        self.0.fingerprint.get_or_init(|| {
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
        Arc::ptr_eq(&self.0, &other.0)
    }
}
impl From<Vec<u8>> for SharedBytes {
    fn from(bytes: Vec<u8>) -> Self {
        Self(Arc::new(SharedBytesOwner {
            bytes,
            fingerprint: OnceLock::new(),
        }))
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
        assert!(payload.0.fingerprint.get().is_none());
        assert!(independent.0.fingerprint.get().is_none());
        let expected: [u8; 32] = Sha256::digest(payload.as_slice()).into();
        assert_eq!(alias.sha256(), expected);
        assert_eq!(payload.0.fingerprint.get().unwrap().sha256, expected);
        assert!(independent.0.fingerprint.get().is_none());
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
