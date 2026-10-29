//! An acquisition lease is NOT the interned lexical source's identity.
use crate::{
    regions::prepared_source::{shared_prepared, PreparedSource},
    SourceText,
};
use std::{any::Any, sync::Arc};
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SourceEncoding {
    Utf8,
    Utf8Bom,
    IncompatibleOriginal,
    SyntheticUtf8,
}
struct Original {
    prepared: Arc<PreparedSource>,
    encoding: SourceEncoding,
}
struct Binding {
    original: Arc<Original>,
    receipt: Arc<dyn Any + Send + Sync>,
}
#[derive(Clone)]
pub struct AcquiredSource(Arc<Binding>);
impl std::fmt::Debug for AcquiredSource {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("AcquiredSource")
            .field("encoding", &self.encoding())
            .finish_non_exhaustive()
    }
}
impl AcquiredSource {
    /// Provider boundary: classify ORIGINAL bytes and create the paired text in
    /// one transaction. No existing text/hash can be supplied as evidence.
    pub fn from_original_bytes<T: Any + Send + Sync>(bytes: Vec<u8>, receipt: T) -> Self {
        let encoding = if std::str::from_utf8(&bytes).is_err() {
            SourceEncoding::IncompatibleOriginal
        } else if bytes.starts_with(b"\xef\xbb\xbf") {
            SourceEncoding::Utf8Bom
        } else {
            SourceEncoding::Utf8
        };
        let text = match String::from_utf8(bytes) {
            Ok(mut text) => {
                if text.starts_with('\u{feff}') {
                    text.drain(..3);
                }
                text
            }
            Err(error) => crate::decode_source_bytes(&error.into_bytes()),
        };
        Self::issue(shared_prepared(SourceText::from(text)), encoding, receipt)
    }
    /// Exceptional acquisition already owns its original byte allocation elsewhere.
    pub fn from_original_slice<T: Any + Send + Sync>(bytes: &[u8], receipt: T) -> Self {
        let encoding = if std::str::from_utf8(bytes).is_err() {
            SourceEncoding::IncompatibleOriginal
        } else if bytes.starts_with(b"\xef\xbb\xbf") {
            SourceEncoding::Utf8Bom
        } else {
            SourceEncoding::Utf8
        };
        Self::issue(
            shared_prepared(SourceText::from(crate::decode_source_bytes(bytes))),
            encoding,
            receipt,
        )
    }
    /// Explicit in-memory provider contract, never the default for read(String).
    pub fn synthetic_utf8<T: Any + Send + Sync>(text: SourceText, receipt: T) -> Self {
        Self::issue(
            shared_prepared(text),
            SourceEncoding::SyntheticUtf8,
            receipt,
        )
    }
    fn issue<T: Any + Send + Sync>(
        prepared: Arc<PreparedSource>,
        encoding: SourceEncoding,
        receipt: T,
    ) -> Self {
        Self(Arc::new(Binding {
            original: Arc::new(Original { prepared, encoding }),
            receipt: Arc::new(receipt),
        }))
    }
    pub fn prepared(&self) -> &Arc<PreparedSource> {
        &self.0.original.prepared
    }
    pub fn encoding(&self) -> SourceEncoding {
        self.0.original.encoding
    }
    pub fn receipt<T: Any>(&self) -> Option<&T> {
        self.0.receipt.downcast_ref()
    }
    /// Only the provider may refresh its opaque receipt AFTER validating reuse.
    /// Original acquisition/classification is retained, never inferred anew.
    pub fn reissued<T: Any + Send + Sync>(&self, receipt: T) -> Self {
        Self(Arc::new(Binding {
            original: Arc::clone(&self.0.original),
            receipt: Arc::new(receipt),
        }))
    }
    pub fn same_binding(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.0, &other.0)
    }
    pub fn same_original_acquisition(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.0.original, &other.0.original)
    }
}
#[cfg(test)]
#[path = "source_acquisition_tests.rs"]
mod tests;
