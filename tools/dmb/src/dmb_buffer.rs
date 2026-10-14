//! Shared append storage for the single canonical record writer.
use std::ops::{Deref, DerefMut};
pub(in super::super) enum Buffer<'a> {
    Owned(Vec<u8>),
    Bounded {
        bytes: &'a mut [u8],
        written: usize,
        overflow: bool,
    },
}
impl<'a> Buffer<'a> {
    pub(in super::super) fn owned() -> Self {
        Self::Owned(Vec::new())
    }
    pub(in super::super) fn bounded(bytes: &'a mut [u8]) -> Self {
        Self::Bounded {
            bytes,
            written: 0,
            overflow: false,
        }
    }
    pub(in super::super) fn reserve(&mut self, additional: usize) {
        if let Self::Owned(bytes) = self {
            bytes.reserve(additional);
        }
    }
    pub(in super::super) fn extend_from_slice(&mut self, value: &[u8]) {
        match self {
            Self::Owned(bytes) => bytes.extend_from_slice(value),
            Self::Bounded {
                bytes,
                written,
                overflow,
            } => {
                let Some(end) = written
                    .checked_add(value.len())
                    .filter(|&end| end <= bytes.len())
                else {
                    *overflow = true;
                    return;
                };
                if *overflow {
                    return;
                }
                bytes[*written..end].copy_from_slice(value);
                *written = end;
            }
        }
    }
    pub(in super::super) fn push(&mut self, value: u8) {
        self.extend_from_slice(&[value]);
    }
    pub(in super::super) fn overflowed(&self) -> bool {
        matches!(self, Self::Bounded { overflow: true, .. })
    }
    pub(in super::super) fn into_owned(self) -> Vec<u8> {
        match self {
            Self::Owned(bytes) => bytes,
            Self::Bounded { .. } => unreachable!("only root owned writer becomes encoded output"),
        }
    }
    pub(in super::super) fn append_space(&mut self, size: usize) -> std::io::Result<&mut [u8]> {
        match self {
            Self::Owned(bytes) => {
                let start = bytes.len();
                let end = start
                    .checked_add(size)
                    .ok_or_else(|| std::io::Error::other("serialization size overflow"))?;
                bytes.resize(end, 0);
                Ok(&mut bytes[start..])
            }
            Self::Bounded { .. } => Err(std::io::Error::other(
                "root serialization storage is not owned",
            )),
        }
    }
}
impl Deref for Buffer<'_> {
    type Target = [u8];
    fn deref(&self) -> &[u8] {
        match self {
            Self::Owned(bytes) => bytes,
            Self::Bounded { bytes, written, .. } => &bytes[..*written],
        }
    }
}
impl DerefMut for Buffer<'_> {
    fn deref_mut(&mut self) -> &mut [u8] {
        match self {
            Self::Owned(bytes) => bytes,
            Self::Bounded { bytes, written, .. } => &mut bytes[..*written],
        }
    }
}
