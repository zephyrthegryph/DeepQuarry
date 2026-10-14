//! Owned authenticated read: the digest is inseparable from its immutable payload.
use super::Stamp;

#[derive(Debug)]
pub struct CapturedInputRead {
    stamp: Stamp,
    bytes: Vec<u8>,
    content: u128,
}
impl CapturedInputRead {
    /// Safe provider boundary: derive the content identity from the actual owned bytes.
    /// Stamp/length admission remains with the caller so existing error order is preserved.
    pub fn new(stamp: Stamp, bytes: Vec<u8>) -> Self {
        let content = xxhash_rust::xxh3::xxh3_128(&bytes);
        Self::from_verified(stamp, bytes, content)
    }
    /// Only crate-owned read boundaries may reuse a digest they have just verified.
    pub(crate) fn from_verified(stamp: Stamp, bytes: Vec<u8>, content: u128) -> Self {
        Self {
            stamp,
            bytes,
            content,
        }
    }
    pub fn stamp(&self) -> &Stamp {
        &self.stamp
    }
    pub fn bytes(&self) -> &[u8] {
        &self.bytes
    }
    pub fn content(&self) -> u128 {
        self.content
    }
    /// Consuming extraction ends the certificate lifetime before mutable bytes escape.
    pub fn into_parts(self) -> (Stamp, Vec<u8>, u128) {
        (self.stamp, self.bytes, self.content)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn safe_constructor_hashes_actual_allocation_and_mutation_ends_certificate() {
        let mut bytes = Vec::with_capacity(91);
        bytes.extend_from_slice(b"actual");
        let pointer = bytes.as_ptr();
        let stamp = Stamp {
            size: 6,
            modified_ns: 1,
            file_id: Some(7),
        };
        let read = CapturedInputRead::new(stamp.clone(), bytes);
        assert_eq!(read.bytes().as_ptr(), pointer);
        assert_eq!(read.content(), xxhash_rust::xxh3::xxh3_128(b"actual"));
        let (_, mut bytes, old_digest) = read.into_parts();
        bytes[0] ^= 1;
        let replacement = CapturedInputRead::new(stamp, bytes);
        assert_ne!(replacement.content(), old_digest);
        assert_eq!(
            replacement.content(),
            xxhash_rust::xxh3::xxh3_128(replacement.bytes())
        );
    }
}
