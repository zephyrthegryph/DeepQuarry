//! Acquisition authority is separate from both lexical interning and retention.
use crate::{
    regions::prepared_source::{shared_prepared, shared_prepared_bytes, PreparedSource},
    SourceText,
};
use std::{any::Any, sync::Arc};

/// Selects when ordinary lexical products are first needed. Both modes
/// preserve the same decoded-byte interning and acquisition authority.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SourcePreparationDemand {
    Lexical,
    Bytes,
}

impl SourcePreparationDemand {
    pub fn prepare(self, text: SourceText) -> Arc<PreparedSource> {
        match self {
            Self::Lexical => shared_prepared(text),
            Self::Bytes => shared_prepared_bytes(text),
        }
    }
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SourceEncoding {
    Utf8,
    Utf8Bom,
    IncompatibleOriginal,
    SyntheticUtf8,
}
use crate::source_arena_credit::SourceArenaControlCredit;
use std::sync::Weak;

/// Every concrete strong handle, including temporary upgrades, releases the
/// implicit Weak before dropping its payload's final control-credit alias.
struct AcquisitionOwner<T>(Option<Arc<T>>);
impl<T> AcquisitionOwner<T> {
    fn new(value: T) -> Self { Self(Some(Arc::new(value))) }
    fn arc(&self) -> &Arc<T> { self.0.as_ref().expect("live acquisition owner") }
    fn downgrade(&self, credit: &Option<SourceArenaControlCredit>) -> AcquisitionWeak<T> {
        AcquisitionWeak { weak: Arc::downgrade(self.arc()), credit: credit.clone() }
    }
}
impl<T> Clone for AcquisitionOwner<T> {
    fn clone(&self) -> Self { Self(Some(self.arc().clone())) }
}
impl<T> std::ops::Deref for AcquisitionOwner<T> {
    type Target = T;
    fn deref(&self) -> &T { self.arc().as_ref() }
}
impl<T> Drop for AcquisitionOwner<T> {
    fn drop(&mut self) {
        if let Some(owner) = self.0.take() {
            drop(Arc::into_inner(owner));
        }
    }
}
struct AcquisitionWeak<T> {
    weak: Weak<T>,
    // Release the actual Weak before this alias can refund its Arc layout.
    credit: Option<SourceArenaControlCredit>,
}
impl<T> Clone for AcquisitionWeak<T> {
    fn clone(&self) -> Self { Self { weak: self.weak.clone(), credit: self.credit.clone() } }
}
impl<T> AcquisitionWeak<T> {
    fn as_ptr(&self) -> *const T { self.weak.as_ptr() }
    fn strong_count(&self) -> usize { self.weak.strong_count() }
    fn same(&self, other: &Self) -> bool { Weak::ptr_eq(&self.weak, &other.weak) }
    fn upgrade(&self) -> Option<AcquisitionOwner<T>> {
        self.weak.upgrade().map(|owner| AcquisitionOwner(Some(owner)))
    }
}

struct Original {
    source: SourceText,
    encoding: SourceEncoding,
    control: Option<SourceArenaControlCredit>,
}
struct Binding {
    original: AcquisitionOwner<Original>,
    receipt: Arc<dyn Any + Send + Sync>,
    // The erased receipt Arc drops before its control reservation.
    receipt_credit: Option<crate::source_arena_credit::SourceArenaControlCredit>,
    control: Option<SourceArenaControlCredit>,
}
/// Lightweight exact acquisition binding: no lexical PreparedSource owner.
#[derive(Clone)]
pub struct SourceAcquisitionLease(AcquisitionOwner<Binding>);
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
        Self(AcquisitionOwner::new(Binding{original:AcquisitionOwner::new(Original{source:text.into(),encoding,control:None}),receipt:Arc::new(receipt),receipt_credit:None,control:None}))
    }

    /// Actual private constructor layout; resource geometry only, not a source
    /// authorization. Receipt-owned path buffers are supplied by its issuer.
    pub fn raw_constructor_storage_bytes<T>() -> std::io::Result<usize> {
        std::mem::size_of::<Binding>().checked_add(std::mem::size_of::<Original>())
            .and_then(|n| n.checked_add(4 * std::mem::size_of::<usize>()))
            .and_then(|n| n.checked_add(Self::receipt_allocation_bytes::<T>().ok()?))
            .and_then(|n| n.checked_add(SourceText::source_arena_control_bytes().ok()?))
            .ok_or_else(|| std::io::ErrorKind::OutOfMemory.into())
    }

    fn receipt_allocation_bytes<T>() -> std::io::Result<usize> {
        use std::alloc::Layout;
        Layout::new::<[usize; 2]>().extend(Layout::new::<T>())
            .map(|(layout, _)| layout.pad_to_align().size())
            .map_err(|_| std::io::ErrorKind::OutOfMemory.into())
    }
    /// SAME raw acquisition constructor after its one admitted decoder emitted
    /// text; private receipt remains the sole native issuer authorization.
    pub fn from_raw_original_decoded<T:Any+Send+Sync>(text:String,encoding:SourceEncoding,receipt:T)->Self{
        Self::from_raw_original_decoded_with_candidate(text,encoding,receipt,None)
    }
    /// Optional DATA-only reuse after an actual admitted read. Equal bytes
    /// can share storage, while every call allocates a fresh original binding
    /// and keeps the caller's newly issued private receipt. Never grants a
    /// prepared lexical owner, a read receipt, or exceptional raw bytes.
    #[doc(hidden)]
    pub fn from_raw_original_decoded_with_candidate<T:Any+Send+Sync>(
        text:String,encoding:SourceEncoding,receipt:T,candidate:Option<&SourceText>,
    )->Self{
        let source=match candidate{
            Some(prior) if encoding==SourceEncoding::Utf8&&prior.can_reuse_for_exact_raw_utf8(&text)=>prior.clone(),
            _=>text.into(),
        };
        Self(AcquisitionOwner::new(Binding{original:AcquisitionOwner::new(Original{source,encoding,control:None}),receipt:Arc::new(receipt),receipt_credit:None,control:None}))
    }
    /// Construct a fresh backing after the existing decoded-byte reuse check.
    /// The funding loan grants storage only. This constructor owns the actual String.
    #[doc(hidden)]
    pub fn from_raw_original_decoded_with_funding<T: Any + Send + Sync>(
        text: String, encoding: SourceEncoding, receipt: T, candidate: Option<&SourceText>,
        fund_text: &crate::source_arena_credit::OriginalReadTextFunding<'_>,
    ) -> std::io::Result<Self> {
        let source = match candidate {
            Some(prior) if encoding == SourceEncoding::Utf8 && prior.can_reuse_for_exact_raw_utf8(&text) => prior.clone(),
            _ => match fund_text.split(text.capacity())? {
                Some((payload, control)) => SourceText::from_source_arena(text, payload, control)?,
                None => text.into(),
            },
        };
        // Settle both fixed layouts before donating the still-local receipt's
        // paths. After receipt donation no further constructor can refuse.
        let (binding_control, original_control) = fund_text.split_acquisition_controls([
            std::mem::size_of::<Binding>() + 2 * std::mem::size_of::<usize>(),
            std::mem::size_of::<Original>() + 2 * std::mem::size_of::<usize>(),
        ])?.map_or((None,None), |(binding, original)| (Some(binding), Some(original)));
        let receipt_credit = fund_text.split_receipt(&receipt)?;
        Ok(Self(AcquisitionOwner::new(Binding {
            original: AcquisitionOwner::new(Original { source, encoding, control: original_control }),
            receipt: Arc::new(receipt),
            receipt_credit,
            control: binding_control,
        })))
    }
    /// Issue resource-only weak views over the THREE actual constructor
    /// allocations. Sharing/reissuance preserves real Original addresses and
    /// never causes an aggregate Binding row to double-charge shared objects.
    pub fn visit_weak_resource_objects(&self,mut emit:impl FnMut(WeakAcquisitionObject)){
        emit(WeakAcquisitionObject(WeakObject::Binding(self.0.downgrade(&self.0.control))));
        emit(WeakAcquisitionObject(WeakObject::Original(self.0.original.downgrade(&self.0.original.control))));
        emit(WeakAcquisitionObject(WeakObject::Receipt{owner:Arc::downgrade(&self.0.receipt),bytes:std::mem::size_of_val(self.0.receipt.as_ref()),credit:self.0.receipt_credit.clone()}));
    }
    pub fn visit_storage(&self, mut visit: impl FnMut(AcquisitionStorage<'_>)) {
        visit(AcquisitionStorage::Object {
            address: Arc::as_ptr(self.0.arc()) as usize,
            bytes: std::mem::size_of::<Binding>(),
        });
        visit(AcquisitionStorage::Object {
            address: Arc::as_ptr(self.0.original.arc()) as usize,
            bytes: std::mem::size_of::<Original>(),
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
    /// Fix this actual adopted input's fingerprint allocation footprint. All
    /// range digests remain exact, while new cache storage cannot grow.
    pub fn seal_input_fingerprint_storage(&self) {
        self.source_text().freeze_span_fingerprint_growth();
    }
    pub fn encoding(&self) -> SourceEncoding {
        self.0.original.encoding
    }
    pub fn receipt<T: Any>(&self) -> Option<&T> {
        self.0.receipt.downcast_ref()
    }
    pub fn same_binding(&self, other: &Self) -> bool {
        Arc::ptr_eq(self.0.arc(), other.0.arc())
    }
    pub fn same_original_acquisition(&self, other: &Self) -> bool {
        Arc::ptr_eq(self.0.original.arc(), other.0.original.arc())
    }
    pub fn reissued<T: Any + Send + Sync>(&self, receipt: T) -> Self {
        Self(AcquisitionOwner::new(Binding {
            original: self.0.original.clone(),
            receipt: Arc::new(receipt),
            receipt_credit: None,
            control: None,
        }))
    }
}
impl AcquiredSource {
    pub fn from_original_bytes<T: Any + Send + Sync>(bytes: Vec<u8>, receipt: T) -> Self {
        Self::from_original_bytes_with_candidate_using(
            bytes, None, receipt, SourcePreparationDemand::Lexical,
        )
    }
    /// Reuse a full decoded text allocation only after the actual UTF-8 bytes
    /// have been acquired and compared. Issue a fresh acquisition in either case.
    pub fn from_original_bytes_with_candidate<T: Any + Send + Sync>(
        bytes: Vec<u8>, candidate: Option<&SourceText>, receipt: T,
    ) -> Self {
        Self::from_original_bytes_with_candidate_using(
            bytes, candidate, receipt, SourcePreparationDemand::Lexical,
        )
    }

    pub fn from_original_bytes_with_candidate_using<T: Any + Send + Sync>(
        bytes: Vec<u8>, candidate: Option<&SourceText>, receipt: T,
        demand: SourcePreparationDemand,
    ) -> Self {
        if let Some(text) = candidate.filter(|text| {
            !bytes.starts_with(b"\xef\xbb\xbf") && text.as_str().as_bytes() == bytes.as_slice()
        }) {
            drop(bytes);
            text.freeze_span_fingerprint_growth();
            return Self::issue(demand.prepare(text.clone()), SourceEncoding::Utf8, receipt);
        }
        let (text, encoding) = decode_original_bytes(bytes);
        Self::issue(demand.prepare(text.into()), encoding, receipt)
    }

    pub fn from_original_slice<T: Any + Send + Sync>(bytes: &[u8], receipt: T) -> Self {
        Self::from_original_slice_using(bytes, receipt, SourcePreparationDemand::Lexical)
    }

    pub fn from_original_slice_using<T: Any + Send + Sync>(
        bytes: &[u8], receipt: T, demand: SourcePreparationDemand,
    ) -> Self {
        Self::issue(
            demand.prepare(crate::decode_source_bytes(bytes).into()),
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
        let original = AcquisitionOwner::new(Original {
            source: prepared.original().clone(),
            encoding,
            control: None,
        });
        Self {
            prepared,
            lease: SourceAcquisitionLease(AcquisitionOwner::new(Binding {
                original,
                receipt: Arc::new(receipt),
            receipt_credit: None,
            control: None,
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
pub struct SourceAcquisitionIdentity(AcquisitionWeak<Binding>);
impl std::fmt::Debug for SourceAcquisitionIdentity {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SourceAcquisitionIdentity")
            .finish_non_exhaustive()
    }
}
impl SourceAcquisitionIdentity {
    pub fn matches(&self, lease: &SourceAcquisitionLease) -> bool {
        // The weak token keeps this allocation address reserved, and the
        // lease keeps its own Binding live. Neither handle is dereferenced.
        std::ptr::eq(self.0.as_ptr(), Arc::as_ptr(lease.0.arc()))
    }
    /// Storage/lifetime observation only, never source or locator authority.
    pub fn is_alive(&self) -> bool {
        self.0.strong_count() != 0
    }
    pub(crate) fn same_identity(&self, other: &Self) -> bool {
        self.0.same(&other.0)
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
        SourceAcquisitionIdentity(self.0.downgrade(&self.0.control))
    }
}

/// Compare-only ORIGINAL acquisition identity. Warm reissuance preserves it
/// only after the paired prepared-input ledger was validated. A genuinely new
/// read gets another identity even if its decoded storage was interned equal.
/// This weak token is an optimization key, not a source/receipt authority.
#[derive(Clone)]
pub struct OriginalAcquisitionIdentity(AcquisitionWeak<Original>);
impl OriginalAcquisitionIdentity {
    pub fn same_live_original(&self, other: &Self) -> bool {
        self.0.strong_count() != 0
            && other.0.strong_count() != 0
            && self.0.same(&other.0)
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
        OriginalAcquisitionIdentity(self.0.original.downgrade(&self.0.original.control))
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
#[derive(Clone)]enum WeakObject{Binding(AcquisitionWeak<Binding>),Original(AcquisitionWeak<Original>),Receipt{owner:std::sync::Weak<dyn Any+Send+Sync>,bytes:usize,credit:Option<crate::source_arena_credit::SourceArenaControlCredit>}}
impl WeakAcquisitionObject{
 pub fn control_credit(&self) -> Option<&SourceArenaControlCredit> {
     match &self.0 {
         WeakObject::Binding(owner) => owner.credit.as_ref(),
         WeakObject::Original(owner) => owner.credit.as_ref(),
         WeakObject::Receipt { credit, .. } => credit.as_ref(),
     }
 }

 /// Resource loan accompanying the erased receipt weak control. The Weak
 /// field precedes this credit so its allocation can free before refund.
 pub fn receipt_control_credit(&self) -> Option<&crate::source_arena_credit::SourceArenaControlCredit> {
     match &self.0 {
         WeakObject::Receipt { credit, .. } => credit.as_ref(),
         _ => None,
     }
 }

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
   WeakObject::Binding(w)=>{let Some(owner)=w.upgrade()else{return false};visit(AcquisitionStorage::Object{address:Arc::as_ptr(owner.arc())as usize,bytes:std::mem::size_of::<Binding>()});true},
   WeakObject::Original(w)=>{let Some(owner)=w.upgrade()else{return false};visit(AcquisitionStorage::Object{address:Arc::as_ptr(owner.arc())as usize,bytes:std::mem::size_of::<Original>()});true},
   WeakObject::Receipt{owner,bytes,..}=>{let Some(owner)=owner.upgrade()else{return false};visit(AcquisitionStorage::Receipt{address:Arc::as_ptr(&owner)as*const()as usize,bytes:*bytes,value:owner.as_ref()});true},
  }
 }
}

#[cfg(test)]mod resource_object_tests{
 use super::*;
 #[test]fn actual_resource_views_dedup_only_shared_original_and_never_reissue_or_resurrect_a_source(){
  let first=SourceAcquisitionLease::from_raw_original_bytes(b"source".to_vec(),1usize);let second=first.reissued(2usize);let mut a=Vec::new();let mut b=Vec::new();first.visit_weak_resource_objects(|w|a.push(w));second.visit_weak_resource_objects(|w|b.push(w));assert_eq!(a.len(),3);assert_eq!(b.len(),3);assert_ne!(a[0].resource_key(),b[0].resource_key());assert_eq!(a[1].resource_key(),b[1].resource_key());assert_ne!(a[2].resource_key(),b[2].resource_key());drop(first);assert!(!a[0].is_alive());assert!(a[1].is_alive());assert!(!a[2].is_alive());drop(second);for w in a.iter().chain(&b){assert!(!w.is_alive());let mut live=false;assert!(!w.visit_live_storage(|_|live=true));assert!(!live);let mut capacity=0;w.visit_control_storage(|_,logical,cap|{assert_eq!(logical,0);capacity=cap});assert!(capacity>0,"real weak control stays reserved until the observation drops");}
 }
}
