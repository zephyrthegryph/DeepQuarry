//! Exact structural content with optional, lazy compatibility byte encoding.
use dm_ir::SymbolicCode;
use std::sync::{Arc, OnceLock};

#[derive(Clone, Debug)]
pub enum EntryContent {
    Bytes(Arc<[u8]>),
    Symbolic(Arc<SymbolicContent>),
}

#[derive(Debug)]
pub struct SymbolicContent {
    prefix: Arc<[u8]>,
    code: Arc<SymbolicCode>,
    suffix: Arc<[u8]>,
    canonical: OnceLock<Arc<[u8]>>,
}

impl SymbolicContent {
    /// Borrow retained allocations without invoking canonical encoding.
    pub fn parts(&self) -> (&Arc<[u8]>, &Arc<SymbolicCode>, &Arc<[u8]>) {
        (&self.prefix, &self.code, &self.suffix)
    }
    pub fn materialized_bytes(&self) -> Option<&Arc<[u8]>> {
        self.canonical.get()
    }
    pub fn byte_len(&self) -> usize {
        self.prefix
            .len()
            .checked_add(self.code.canonical_len())
            .and_then(|length| length.checked_add(self.suffix.len()))
            .expect("symbolic entry canonical length overflow")
    }
    fn bytes(&self) -> &[u8] {
        self.canonical.get_or_init(|| {
            let mut bytes = Vec::with_capacity(self.byte_len());
            bytes.extend_from_slice(&self.prefix);
            bytes.extend(self.code.canonical_bytes());
            bytes.extend_from_slice(&self.suffix);
            bytes.into()
        })
    }
}

impl EntryContent {
    /// Prefix includes any producer-authored length framing. This inserts no
    /// new framing: canonical bytes are precisely prefix + code + suffix.
    pub fn symbolic(prefix: Arc<[u8]>, code: Arc<SymbolicCode>, suffix: Arc<[u8]>) -> Self {
        Self::Symbolic(Arc::new(SymbolicContent {
            prefix,
            code,
            suffix,
            canonical: OnceLock::new(),
        }))
    }
    pub fn byte_len(&self) -> usize {
        match self {
            Self::Bytes(bytes) => bytes.len(),
            Self::Symbolic(content) => content.byte_len(),
        }
    }
    pub fn materialized_bytes(&self) -> Option<&Arc<[u8]>> {
        match self {
            Self::Bytes(bytes) => Some(bytes),
            Self::Symbolic(content) => content.materialized_bytes(),
        }
    }
    /// Share existing canonical storage; only symbolic compatibility consumers
    /// trigger its one-time encoding.
    pub fn shared_bytes(&self) -> Arc<[u8]> {
        match self {
            Self::Bytes(bytes) => Arc::clone(bytes),
            Self::Symbolic(content) => {
                let _ = content.bytes();
                Arc::clone(
                    content
                        .materialized_bytes()
                        .expect("canonical bytes initialized"),
                )
            }
        }
    }
}
impl From<Arc<[u8]>> for EntryContent {
    fn from(bytes: Arc<[u8]>) -> Self {
        Self::Bytes(bytes)
    }
}
impl From<Vec<u8>> for EntryContent {
    fn from(bytes: Vec<u8>) -> Self {
        Self::Bytes(bytes.into())
    }
}
impl From<&[u8]> for EntryContent {
    fn from(bytes: &[u8]) -> Self {
        Self::Bytes(bytes.into())
    }
}
impl AsRef<[u8]> for EntryContent {
    fn as_ref(&self) -> &[u8] {
        match self {
            Self::Bytes(bytes) => bytes,
            Self::Symbolic(content) => content.bytes(),
        }
    }
}
impl PartialEq for EntryContent {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (Self::Bytes(left), Self::Bytes(right)) => left == right,
            (Self::Symbolic(left), Self::Symbolic(right)) => {
                let structural_equal = left.prefix == right.prefix
                    && left.code == right.code
                    && left.suffix == right.suffix;
                // Public envelopes may segment the same byte stream differently.
                // Preserve canonical equality (including mixed Bytes comparisons)
                // without encoding the ordinary structurally-identical case.
                structural_equal
                    || (left.byte_len() == right.byte_len() && left.bytes() == right.bytes())
            }
            _ => self.as_ref() == other.as_ref(),
        }
    }
}
impl Eq for EntryContent {}

#[cfg(test)]
mod tests;
