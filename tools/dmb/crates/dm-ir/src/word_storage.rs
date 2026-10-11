//! Source-neutral word access without alignment or host-endian assumptions.
use std::{fmt, ops::Range, sync::Arc};

/// Physical backing descriptor for deduplicated retention accounting, never
/// identity/freshness authority. Control blocks and private indices are unknown.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ByteOwnerStorage {
    pub address: usize,
    pub bytes: usize,
    pub memory_mapped: bool,
}
/// An immutable byte lifetime owner. Implementations must return the same bytes
/// for their entire lifetime. A mapping owner must uphold its existing immutable
/// file contract. This API supplies storage only, not semantic/source admission.
pub trait ImmutableByteOwner: Send + Sync {
    fn bytes(&self) -> &[u8];
    fn storage(&self) -> ByteOwnerStorage;
}
impl ImmutableByteOwner for Vec<u8> {
    fn bytes(&self) -> &[u8] {
        self
    }
    fn storage(&self) -> ByteOwnerStorage {
        ByteOwnerStorage {
            address: self.as_ptr() as usize,
            bytes: self.capacity(),
            memory_mapped: false,
        }
    }
}
#[derive(Clone)]
pub enum WordStorage {
    Owned(Vec<u32>),
    /// Fields stay private behind SharedWords, so callers cannot bypass range
    /// and word-count validation by directly constructing this variant.
    Shared(SharedWords),
}
#[derive(Clone)]
pub struct SharedWords {
    owner: Arc<dyn ImmutableByteOwner>,
    range: Range<usize>,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum WordStorageError {
    InvalidRange,
    PartialWord,
    WordCountOverflow,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum WordStorageView {
    Owned {
        address: usize,
        length_bytes: usize,
        capacity_bytes: usize,
    },
    Shared {
        backing: ByteOwnerStorage,
        offset: usize,
        length_bytes: usize,
    },
}
impl Default for WordStorage {
    fn default() -> Self {
        Self::Owned(Vec::new())
    }
}
impl WordStorage {
    pub fn shared(
        owner: Arc<dyn ImmutableByteOwner>,
        range: Range<usize>,
    ) -> Result<Self, WordStorageError> {
        if range.start > range.end || range.end > owner.bytes().len() {
            return Err(WordStorageError::InvalidRange);
        }
        let count = range.end - range.start;
        if count % 4 != 0 {
            return Err(WordStorageError::PartialWord);
        }
        u32::try_from(count / 4).map_err(|_| WordStorageError::WordCountOverflow)?;
        Ok(Self::Shared(SharedWords { owner, range }))
    }
    pub fn len(&self) -> usize {
        match self {
            Self::Owned(words) => words.len(),
            Self::Shared(words) => (words.range.end - words.range.start) / 4,
        }
    }
    pub fn owned_slice(&self) -> Option<&[u32]> {
        match self {
            Self::Owned(words) => Some(words),
            Self::Shared(_) => None,
        }
    }
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
    pub fn word_at(&self, index: usize) -> Option<u32> {
        match self {
            Self::Owned(words) => words.get(index).copied(),
            Self::Shared(words) => {
                if index >= self.len() {
                    return None;
                }
                let at = words.range.start.checked_add(index.checked_mul(4)?)?;
                let bytes = words.owner.bytes().get(at..at.checked_add(4)?)?;
                Some(u32::from_le_bytes(bytes.try_into().ok()?))
            }
        }
    }
    pub fn iter(&self) -> WordIter<'_> {
        WordIter {
            storage: self,
            indices: 0..self.len(),
        }
    }
    /// Final output construction can deliberately materialize words; ordinary
    /// inspection/canonical hashing should iterate rather than allocate a copy.
    pub fn to_vec(&self) -> Vec<u32> {
        self.iter().collect()
    }
    pub fn storage(&self) -> WordStorageView {
        match self {
            Self::Owned(words) => WordStorageView::Owned {
                address: words.as_ptr() as usize,
                length_bytes: words.len().saturating_mul(4),
                capacity_bytes: words.capacity().saturating_mul(4),
            },
            Self::Shared(words) => WordStorageView::Shared {
                backing: words.owner.storage(),
                offset: words.range.start,
                length_bytes: words.range.end - words.range.start,
            },
        }
    }
}
impl PartialEq for WordStorage {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (Self::Shared(a), Self::Shared(b))
                if Arc::ptr_eq(&a.owner, &b.owner) && a.range == b.range =>
            {
                true
            }
            _ => self.len() == other.len() && self.iter().eq(other.iter()),
        }
    }
}
impl Eq for WordStorage {}
impl fmt::Debug for WordStorage {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("WordStorage")
            .field("length", &self.len())
            .field("storage", &self.storage())
            .finish()
    }
}
pub struct WordIter<'a> {
    storage: &'a WordStorage,
    indices: Range<usize>,
}
impl Iterator for WordIter<'_> {
    type Item = u32;
    fn next(&mut self) -> Option<u32> {
        self.indices.next().map(|at| {
            self.storage
                .word_at(at)
                .expect("validated immutable word range")
        })
    }
    fn size_hint(&self) -> (usize, Option<usize>) {
        self.indices.size_hint()
    }
}
impl DoubleEndedIterator for WordIter<'_> {
    fn next_back(&mut self) -> Option<u32> {
        self.indices.next_back().map(|at| {
            self.storage
                .word_at(at)
                .expect("validated immutable word range")
        })
    }
}
impl ExactSizeIterator for WordIter<'_> {}
impl std::iter::FusedIterator for WordIter<'_> {}
#[cfg(test)]
#[path = "word_storage_tests.rs"]
mod tests;
