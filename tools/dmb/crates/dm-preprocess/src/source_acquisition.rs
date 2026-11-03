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
    /// Native raw acquisition: the SAME decoder and receipt binding without
    /// preparing logical lines, directives, a parser or a semantic graph.
    pub fn from_raw_original_bytes<T:Any+Send+Sync>(bytes:Vec<u8>,receipt:T)->Self{
        let(text,encoding)=decode_original_bytes(bytes);
        Self(Arc::new(Binding{original:Arc::new(Original{source:text.into(),encoding}),receipt:Arc::new(receipt)}))
    }

    /// Actual private constructor layout; resource geometry only, not a source
    /// authorization. Receipt-owned path buffers are supplied by its issuer.
    pub fn raw_constructor_storage_bytes<T>()->std::io::Result<usize>{
        std::mem::size_of::<Binding>().checked_add(std::mem::size_of::<Original>()).and_then(|n|n.checked_add(std::mem::size_of::<T>())).and_then(|n|n.checked_add(6*std::mem::size_of::<usize>())).and_then(|n|SourceText::source_arena_control_bytes().ok().and_then(|m|n.checked_add(m))).ok_or_else(||std::io::ErrorKind::OutOfMemory.into())
    }
    /// SAME raw acquisition constructor after its one admitted decoder emitted
    /// text; private receipt remains the sole native issuer authorization.
    pub fn from_raw_original_decoded<T:Any+Send+Sync>(text:String,encoding:SourceEncoding,receipt:T)->Self{
        Self(Arc::new(Binding{original:Arc::new(Original{source:text.into(),encoding}),receipt:Arc::new(receipt)}))
    }
    /// Issue resource-only weak views over the THREE actual constructor
    /// allocations. Sharing/reissuance preserves real Original addresses and
    /// never causes an aggregate Binding row to double-charge shared objects.
    pub fn visit_weak_resource_objects(&self,mut emit:impl FnMut(WeakAcquisitionObject)){
        emit(WeakAcquisitionObject(WeakObject::Binding(Arc::downgrade(&self.0))));
        emit(WeakAcquisitionObject(WeakObject::Original(Arc::downgrade(&self.0.original))));
        emit(WeakAcquisitionObject(WeakObject::Receipt{owner:Arc::downgrade(&self.0.receipt),bytes:std::mem::size_of_val(self.0.receipt.as_ref())}));
    }
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
    pub fn reissued<T: Any + Send + Sync>(&self, receipt: T) -> Self {
        Self(Arc::new(Binding {
            original: Arc::clone(&self.0.original),
            receipt: Arc::new(receipt),
        }))
    }
}
impl AcquiredSource {
    pub fn from_original_bytes<T: Any + Send + Sync>(bytes: Vec<u8>, receipt: T) -> Self {
        let (text,encoding)=decode_original_bytes(bytes);
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

/// Compare-only ORIGINAL acquisition identity. Warm reissuance preserves it
/// only after the paired prepared-input ledger was validated. A genuinely new
/// read gets another identity even if its decoded storage was interned equal.
/// This weak token is an optimization key, not a source/receipt authority.
#[derive(Clone)]
pub struct OriginalAcquisitionIdentity(std::sync::Weak<Original>);
impl OriginalAcquisitionIdentity {
    pub fn same_live_original(&self, other: &Self) -> bool {
        self.0.strong_count() != 0
            && other.0.strong_count() != 0
            && std::sync::Weak::ptr_eq(&self.0, &other.0)
    }
    pub fn visit_storage(&self, mut visit: impl FnMut(AcquisitionStorage<'_>)) {
        visit(AcquisitionStorage::Object {
            address: self.0.as_ptr() as usize,
            bytes: std::mem::size_of::<Original>(),
        });
    }
}
impl SourceAcquisitionLease {
    pub fn original_identity(&self) -> OriginalAcquisitionIdentity {
        OriginalAcquisitionIdentity(Arc::downgrade(&self.0.original))
    }
}

fn decode_original_bytes(bytes:Vec<u8>)->(String,SourceEncoding){
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
(text,encoding)
}

/// Opaque weak allocation observation. It never returns a lease/Original/model,
/// and a live receipt loan is limited to metadata visitors on this call stack.
#[derive(Clone)]pub struct WeakAcquisitionObject(WeakObject);
#[derive(Clone)]enum WeakObject{Binding(std::sync::Weak<Binding>),Original(std::sync::Weak<Original>),Receipt{owner:std::sync::Weak<dyn Any+Send+Sync>,bytes:usize}}
impl WeakAcquisitionObject{
 pub fn resource_key(&self)->(u8,usize){match &self.0{WeakObject::Binding(w)=>(0,w.as_ptr()as usize),WeakObject::Original(w)=>(1,w.as_ptr()as usize),WeakObject::Receipt{owner,..}=>(2,owner.as_ptr()as*const()as usize)}}
 pub fn is_alive(&self)->bool{match &self.0{WeakObject::Binding(w)=>w.strong_count()!=0,WeakObject::Original(w)=>w.strong_count()!=0,WeakObject::Receipt{owner,..}=>owner.strong_count()!=0}}
 /// Fixed allocation remains reserved by this Weak even when payload is dead.
 pub fn visit_control_storage(&self,visit:impl FnOnce(usize,usize,usize)){
  let(_,ptr)=self.resource_key();let bytes=match &self.0{WeakObject::Binding(_)=>std::mem::size_of::<Binding>(),WeakObject::Original(_)=>std::mem::size_of::<Original>(),WeakObject::Receipt{bytes,..}=>*bytes}+2*std::mem::size_of::<usize>();visit(ptr,if self.is_alive(){bytes}else{0},bytes)
 }
 /// Temporary upgrade, no retained strong owner/content cache. Metadata-only
 /// Object/Receipt facts cannot be used as a source/currentness/EOF proof.
 pub fn visit_live_storage(&self,mut visit:impl FnMut(AcquisitionStorage<'_>))->bool{
  match &self.0{
   WeakObject::Binding(w)=>{let Some(owner)=w.upgrade()else{return false};visit(AcquisitionStorage::Object{address:Arc::as_ptr(&owner)as usize,bytes:std::mem::size_of::<Binding>()});true},
   WeakObject::Original(w)=>{let Some(owner)=w.upgrade()else{return false};visit(AcquisitionStorage::Object{address:Arc::as_ptr(&owner)as usize,bytes:std::mem::size_of::<Original>()});true},
   WeakObject::Receipt{owner,bytes}=>{let Some(owner)=owner.upgrade()else{return false};visit(AcquisitionStorage::Receipt{address:Arc::as_ptr(&owner)as*const()as usize,bytes:*bytes,value:owner.as_ref()});true},
  }
 }
}

#[cfg(test)]mod resource_object_tests{
 use super::*;
 #[test]fn actual_resource_views_dedup_only_shared_original_and_never_reissue_or_resurrect_a_source(){
  let first=SourceAcquisitionLease::from_raw_original_bytes(b"source".to_vec(),1usize);let second=first.reissued(2usize);let mut a=Vec::new();let mut b=Vec::new();first.visit_weak_resource_objects(|w|a.push(w));second.visit_weak_resource_objects(|w|b.push(w));assert_eq!(a.len(),3);assert_eq!(b.len(),3);assert_ne!(a[0].resource_key(),b[0].resource_key());assert_eq!(a[1].resource_key(),b[1].resource_key());assert_ne!(a[2].resource_key(),b[2].resource_key());drop(first);assert!(!a[0].is_alive());assert!(a[1].is_alive());assert!(!a[2].is_alive());drop(second);for w in a.iter().chain(&b){assert!(!w.is_alive());let mut live=false;assert!(!w.visit_live_storage(|_|live=true));assert!(!live);let mut capacity=0;w.visit_control_storage(|_,logical,cap|{assert_eq!(logical,0);capacity=cap});assert!(capacity>0,"real weak control stays reserved until the observation drops");}
 }
}
