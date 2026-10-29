//! Acquisition authority is separate from both lexical interning and retention.
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
    source: SourceText,
    encoding: SourceEncoding,
}
struct Binding {
    original: Arc<Original>,
    receipt: Arc<dyn Any + Send + Sync>,
}
/// Lightweight exact acquisition binding: no lexical PreparedSource owner.
#[derive(Clone)]
pub struct SourceAcquisitionLease(Arc<Binding>);
impl std::fmt::Debug for SourceAcquisitionLease {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SourceAcquisitionLease")
            .field("encoding", &self.encoding())
            .finish_non_exhaustive()
    }
}
/// Primary-read/prepared-cache pair. Only these native producers retain lexical
/// preparation; archives keep lease(), so lightweight pages cannot pin it.
#[derive(Clone)]
pub struct AcquiredSource {
    prepared: Arc<PreparedSource>,
    lease: SourceAcquisitionLease,
}
impl std::fmt::Debug for AcquiredSource {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("AcquiredSource")
            .field("encoding", &self.encoding())
            .finish_non_exhaustive()
    }
}
/// Storage exposure only, never source/acquisition authority.
pub enum AcquisitionStorage<'a> {
    Object {
        address: usize,
        bytes: usize,
    },
    Receipt {
        address: usize,
        bytes: usize,
        value: &'a (dyn Any + Send + Sync),
    },
    Source(&'a SourceText),
}
impl SourceAcquisitionLease {
    pub fn visit_storage(&self, mut visit: impl FnMut(AcquisitionStorage<'_>)) {
        visit(AcquisitionStorage::Object {
            address: Arc::as_ptr(&self.0) as usize,
            bytes: std::mem::size_of_val(self.0.as_ref()),
        });
        visit(AcquisitionStorage::Object {
            address: Arc::as_ptr(&self.0.original) as usize,
            bytes: std::mem::size_of_val(self.0.original.as_ref()),
        });
        visit(AcquisitionStorage::Receipt {
            address: Arc::as_ptr(&self.0.receipt) as *const () as usize,
            bytes: std::mem::size_of_val(self.0.receipt.as_ref()),
            value: self.0.receipt.as_ref(),
        });
        visit(AcquisitionStorage::Source(&self.0.original.source));
    }

    pub fn source_text(&self) -> &SourceText {
        &self.0.original.source
    }
    pub fn encoding(&self) -> SourceEncoding {
        self.0.original.encoding
    }
    pub fn receipt<T: Any>(&self) -> Option<&T> {
        self.0.receipt.downcast_ref()
    }
    pub fn same_binding(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.0, &other.0)
    }
    pub fn same_original_acquisition(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.0.original, &other.0.original)
    }
    fn reissued<T: Any + Send + Sync>(&self, receipt: T) -> Self {
        Self(Arc::new(Binding {
            original: Arc::clone(&self.0.original),
            receipt: Arc::new(receipt),
        }))
    }
}
impl AcquiredSource {
    pub fn from_original_bytes<T: Any + Send + Sync>(bytes: Vec<u8>, receipt: T) -> Self {
        let encoding = classify(&bytes);
        let text = match String::from_utf8(bytes) {
            Ok(mut text) => {
                if text.starts_with('\u{feff}') {
                    text.drain(..3);
                }
                text
            }
            Err(e) => crate::decode_source_bytes(&e.into_bytes()),
        };
        Self::issue(shared_prepared(text.into()), encoding, receipt)
    }
    pub fn from_original_slice<T: Any + Send + Sync>(bytes: &[u8], receipt: T) -> Self {
        Self::issue(
            shared_prepared(crate::decode_source_bytes(bytes).into()),
            classify(bytes),
            receipt,
        )
    }
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
        let original = Arc::new(Original {
            source: prepared.original().clone(),
            encoding,
        });
        Self {
            prepared,
            lease: SourceAcquisitionLease(Arc::new(Binding {
                original,
                receipt: Arc::new(receipt),
            })),
        }
    }
    pub fn prepared(&self) -> &Arc<PreparedSource> {
        &self.prepared
    }
    pub fn lease(&self) -> &SourceAcquisitionLease {
        &self.lease
    }
    pub fn encoding(&self) -> SourceEncoding {
        self.lease.encoding()
    }
    pub fn receipt<T: Any>(&self) -> Option<&T> {
        self.lease.receipt()
    }
    pub fn reissued<T: Any + Send + Sync>(&self, receipt: T) -> Self {
        Self {
            prepared: Arc::clone(&self.prepared),
            lease: self.lease.reissued(receipt),
        }
    }
    pub fn same_binding(&self, other: &Self) -> bool {
        self.lease.same_binding(&other.lease)
    }
    pub fn same_original_acquisition(&self, other: &Self) -> bool {
        self.lease.same_original_acquisition(&other.lease)
    }
}
fn classify(bytes: &[u8]) -> SourceEncoding {
    if std::str::from_utf8(bytes).is_err() {
        SourceEncoding::IncompatibleOriginal
    } else if bytes.starts_with(b"\xef\xbb\xbf") {
        SourceEncoding::Utf8Bom
    } else {
        SourceEncoding::Utf8
    }
}
#[cfg(test)]
#[path = "source_acquisition_tests.rs"]
mod tests;

/// Compare-only weak issuance identity. This does not retain original source,
/// receipts or PreparedSource; it is never serialized, hashed or dereferenced.
#[derive(Clone)]
pub struct SourceAcquisitionIdentity(std::sync::Weak<Binding>);
impl std::fmt::Debug for SourceAcquisitionIdentity {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SourceAcquisitionIdentity")
            .finish_non_exhaustive()
    }
}
impl SourceAcquisitionIdentity {
    pub fn matches(&self, lease: &SourceAcquisitionLease) -> bool {
        std::sync::Weak::ptr_eq(&self.0, &Arc::downgrade(&lease.0))
    }
    /// Storage/lifetime observation only, never source or locator authority.
    pub fn is_alive(&self) -> bool {
        self.0.strong_count() != 0
    }
    pub(crate) fn same_identity(&self, other: &Self) -> bool {
        std::sync::Weak::ptr_eq(&self.0, &other.0)
    }
    pub fn visit_storage(&self, mut visit: impl FnMut(AcquisitionStorage<'_>)) {
        // Weak keeps the Binding allocation reserved, even after its payload
        // has dropped. Do not upgrade/resurrect it or visit dropped members.
        visit(AcquisitionStorage::Object {
            address: self.0.as_ptr() as usize,
            bytes: std::mem::size_of::<Binding>(),
        });
    }
}
impl SourceAcquisitionLease {
    pub fn identity(&self) -> SourceAcquisitionIdentity {
        SourceAcquisitionIdentity(Arc::downgrade(&self.0))
    }
}
