//! Immutable captured bytes whose original vector allocation transfers intact.
use std::{ops::Deref, sync::Arc};

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SharedBytes(Arc<Vec<u8>>);
impl SharedBytes {
    pub fn as_slice(&self) -> &[u8] {
        self.0.as_slice()
    }
    pub fn capacity(&self) -> usize {
        self.0.capacity()
    }
    pub fn shared_vec(&self) -> &Arc<Vec<u8>> {
        &self.0
    }
    pub fn ptr_eq(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.0, &other.0)
    }
}
impl From<Vec<u8>> for SharedBytes {
    fn from(bytes: Vec<u8>) -> Self {
        Self(Arc::new(bytes))
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
}
