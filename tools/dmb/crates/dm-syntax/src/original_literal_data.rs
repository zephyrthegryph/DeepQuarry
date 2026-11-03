//! Source-free Original scalar/static VALUE owner. No source/model/body cache.
use crate::{OriginalTokenValue, SettingAdmission, SettingRootLease};
use std::{fmt, io, mem::size_of, ops::Deref, sync::Arc};

/// Actual producer-issued lexical form, distinct from the neutral String value.
/// Unknown is deliberately unissued; spelling and value never reconstruct it.
#[repr(u8)]
#[derive(Clone,Copy,Debug,Default,Eq,PartialEq,Hash)]
pub enum OriginalStringMode{#[default]Unknown=0,Normal=1,Raw=2,Generated=3}
struct Payload {
    string_mode:OriginalStringMode,
    raw: String,
    value: OriginalTokenValue<String>,
    // LAST: both physical strings die before the original counter is credited.
    credit: SettingRootLease,
}
/// No public Arc/Weak escape: final Arc::into_inner deallocates its control
/// before dropping payload buffers and then its SAME resource-only credit.
pub struct OriginalLiteralData(Option<Arc<Payload>>);
impl Clone for OriginalLiteralData {
    fn clone(&self)->Self { Self(Some(Arc::clone(self.0.as_ref().expect("live literal DATA")))) }
}
impl Drop for OriginalLiteralData {
    fn drop(&mut self) {
        if let Some(owner)=self.0.take() {
            if let Some(payload)=Arc::into_inner(owner) { drop(payload); }
        }
    }
}
impl fmt::Debug for OriginalLiteralData {
    fn fmt(&self,f:&mut fmt::Formatter<'_>)->fmt::Result {
        f.debug_struct("OriginalLiteralData").field("raw",&self.raw()).field("kind",&self.kind()).finish()
    }
}
impl Deref for OriginalLiteralData {
    type Target=str;
    fn deref(&self)->&str { self.raw() }
}
fn fail(a:&SettingAdmission<'_>,e:io::Error)->io::Error {
    let kind=e.kind(); a.record_operational_error(e); kind.into()
}
fn bytes(a:&SettingAdmission<'_>,n:Option<usize>)->io::Result<usize> {
    n.ok_or_else(||fail(a,io::Error::new(io::ErrorKind::OutOfMemory,"Original literal DATA size overflow")))
}
fn copy_value_text(s:&str,a:&SettingAdmission<'_>,credit:&mut SettingRootLease)->io::Result<String> {
    // Exact same Global Layout -> Vec -> String storage discipline as the
    // existing native source arena. No guessed String capacity or after-the-
    // allocation credit top-up. The old raw owner remains paid during copy.
    a.checkpoint()?;
    if s.is_empty(){return Ok(String::new())}
    let layout=std::alloc::Layout::array::<u8>(s.len()).map_err(|e|fail(a,io::Error::new(io::ErrorKind::OutOfMemory,e)))?;
    a.grow(credit,s.len())?;
    // SAFETY: exact Global u8 layout matches Vec::from_raw_parts; null is
    // handled before owner construction and len0 reads no uninitialized bytes.
    // push_str copies validated UTF8 and never grows this exact capacity.
    let pointer=std::ptr::NonNull::new(unsafe{std::alloc::alloc(layout)}).ok_or_else(||fail(a,io::ErrorKind::OutOfMemory.into()))?;
    let bytes=unsafe{Vec::from_raw_parts(pointer.as_ptr(),0,s.len())};
    let mut text=unsafe{String::from_utf8_unchecked(bytes)};
    text.push_str(s);
    a.checkpoint()?;
    Ok(text)
}

impl OriginalLiteralData {
    fn payload(&self)->&Payload { self.0.as_deref().expect("live literal DATA") }
    /// Adopt a genuine caller-owned grammar spelling, explicitly paying its
    /// actual capacity here. A naked String is NEVER treated as prepaid. Typed
    /// values are actual issued lexer/macro values, not parsed from this raw.
    pub fn from_value_using(raw:String,value:OriginalTokenValue<&str>,a:&SettingAdmission<'_>)->io::Result<Self> {
        Self::from_value_with_mode_using(raw,value,OriginalStringMode::Unknown,a)
    }
    pub fn from_value_with_mode_using(raw:String,value:OriginalTokenValue<&str>,mode:OriginalStringMode,a:&SettingAdmission<'_>)->io::Result<Self>{
        a.checkpoint()?;
        let credit=a.reserve(raw.capacity())?;
        Self::from_admitted_raw_with_mode_using(raw,credit,value,mode,a)
    }
    /// Resource-only move from the SAME actual admitted raw spelling owner.
    /// Physical String and original reservation move together; no copy, credit
    /// minting, source identity or foreign-domain adoption follows this API.
    pub fn from_admitted_raw_using(raw:String,credit:SettingRootLease,value:OriginalTokenValue<&str>,a:&SettingAdmission<'_>)->io::Result<Self>{
        Self::from_admitted_raw_with_mode_using(raw,credit,value,OriginalStringMode::Unknown,a)
    }
    pub fn from_admitted_raw_with_mode_using(raw:String,credit:SettingRootLease,value:OriginalTokenValue<&str>,mode:OriginalStringMode,a:&SettingAdmission<'_>)->io::Result<Self>{
        // Failure cleanup also owns raw BEFORE credit. Validation never lets
        // an unsupported/foreign producer leak or refund a live raw buffer.
        let mut pending=Payload{string_mode:mode,raw,value:OriginalTokenValue::Int(0),credit};
        a.checkpoint()?;
        if !a.matches_lease_domain(&pending.credit)||pending.credit.bytes()<pending.raw.capacity(){
            return Err(fail(a,io::Error::new(io::ErrorKind::InvalidInput,"Original raw literal storage lacks its actual SAME-domain capacity credit")));
        }
        if !matches!(&value,OriginalTokenValue::Int(_)|OriginalTokenValue::Float(_)|OriginalTokenValue::String(_)|OriginalTokenValue::Resource(_)) {
            return Err(fail(a,io::Error::new(io::ErrorKind::Unsupported,"Original literal DATA does not yet issue interpolation/template or nonliteral values")));
        }
        if mode!=OriginalStringMode::Unknown&&!matches!(&value,OriginalTokenValue::String(_)){
            return Err(fail(a,io::Error::new(io::ErrorKind::InvalidInput,"Original lexical string mode attached to non-String literal DATA")));
        }
        let fixed=bytes(a,size_of::<Payload>().checked_add(2*size_of::<usize>()))?;
        a.grow(&mut pending.credit,fixed)?;
        pending.value=match value {
            OriginalTokenValue::Int(n)=>OriginalTokenValue::Int(n),
            OriginalTokenValue::Float(n)=>OriginalTokenValue::Float(n),
            OriginalTokenValue::String(s)=>OriginalTokenValue::String(copy_value_text(s,a,&mut pending.credit)?),
            OriginalTokenValue::Resource(s)=>OriginalTokenValue::Resource(copy_value_text(s,a,&mut pending.credit)?),
            _=>unreachable!("closed scalar/static gate"),
        };
        a.checkpoint()?;
        Ok(Self(Some(Arc::new(pending))))
    }
    pub fn string_mode(&self)->OriginalStringMode{self.payload().string_mode}
    pub fn raw(&self)->&str { &self.payload().raw }
    pub fn raw_storage(&self)->&String { &self.payload().raw }
    pub fn value(&self)->OriginalTokenValue<&str> { self.payload().value.map_text(String::as_str) }
    pub fn same_owner(&self,other:&Self)->bool { Arc::ptr_eq(self.0.as_ref().unwrap(),other.0.as_ref().unwrap()) }
    pub fn kind(&self)->&'static str { match &self.payload().value {OriginalTokenValue::Int(_)=>"Int",OriginalTokenValue::Float(_)=>"Float",OriginalTokenValue::String(_)=>"String",OriginalTokenValue::Resource(_)=>"Resource",_=>unreachable!("closed scalar/static owner")} }
    /// Exact known live allocations only, not reservations, parser caches or
    /// source authority. Caller performs address dedup across all aliases.
    pub fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)) {
        let p=self.payload();let fixed=size_of::<Payload>()+2*size_of::<usize>();
        visit(Arc::as_ptr(self.0.as_ref().unwrap())as usize,fixed,fixed);
        visit(p.raw.as_ptr()as usize,p.raw.len(),p.raw.capacity());
        match &p.value {OriginalTokenValue::String(s)|OriginalTokenValue::Resource(s)=>visit(s.as_ptr()as usize,s.len(),s.capacity()),_=>()}
        p.credit.visit_counter_storage(|ptr,n|{let bytes=n+2*size_of::<usize>();visit(ptr,bytes,bytes)});
    }
}
impl PartialEq for OriginalLiteralData {
    fn eq(&self,other:&Self)->bool {
        if self.raw()!=other.raw()||self.string_mode()!=other.string_mode(){return false}
        match(self.value(),other.value()) {
            (OriginalTokenValue::Int(a),OriginalTokenValue::Int(b))=>a==b,
            (OriginalTokenValue::Float(a),OriginalTokenValue::Float(b))=>a.to_bits()==b.to_bits(),
            (OriginalTokenValue::String(a),OriginalTokenValue::String(b))|(OriginalTokenValue::Resource(a),OriginalTokenValue::Resource(b))=>a==b,
            _=>false,
        }
    }
}
impl Eq for OriginalLiteralData {}

#[cfg(test)]mod tests {
 use super::*; use std::sync::atomic::{AtomicUsize,Ordering};
 #[test]fn exact_values_and_float_bits_are_data_not_raw_reparse(){
  let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=SettingAdmission::new(&counter,1<<20,&poll);
  let values=[OriginalTokenValue::Int(0),OriginalTokenValue::Float(-0.0),OriginalTokenValue::Float(f32::from_bits(0x7fc00111)),OriginalTokenValue::String("[not interpolation]"),OriginalTokenValue::Resource("a\\b")];
  for value in values {let data=OriginalLiteralData::from_value_using("same spelling".into(),value,&a).unwrap();let copy=data.clone();assert_eq!(data,copy);assert!(data.same_owner(&copy));let mut capacity=0;data.visit_storage(|_,_,n|capacity+=n);assert!(capacity>data.raw().len());}
  let positive=OriginalLiteralData::from_value_using("0".into(),OriginalTokenValue::Float(0.0),&a).unwrap();let negative=OriginalLiteralData::from_value_using("0".into(),OriginalTokenValue::Float(-0.0),&a).unwrap();assert_ne!(positive,negative);drop((positive,negative));assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn actual_alias_lifetime_keeps_credit_until_last_data_and_ast_drop(){
  let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=SettingAdmission::new(&counter,1<<20,&poll);
  let data=OriginalLiteralData::from_value_using("\"raw\"".into(),OriginalTokenValue::String("[static]"),&a).unwrap();let charged=counter.load(Ordering::Acquire);let literal=crate::LiteralText::from_original_data(&data,40,&a).unwrap();assert!(literal.original_data().unwrap().same_owner(&data));drop(data);assert_eq!(counter.load(Ordering::Acquire),charged);assert_eq!(literal.syntax_parts().unwrap(),None);drop(literal);assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn actual_quota_and_first_1450_leave_no_retained_data_and_fresh_admission_recovers(){
  let counter=Arc::new(AtomicUsize::new(0));let no=||Ok(());let small=SettingAdmission::new(&counter,0,&no);assert!(OriginalLiteralData::from_value_using("x".into(),OriginalTokenValue::String("value"),&small).is_err());assert_eq!(counter.load(Ordering::Acquire),0);
  let calls=std::cell::Cell::new(0);let stop=||{calls.set(calls.get()+1);if calls.get()==4{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}};let a=SettingAdmission::new(&counter,1<<20,&stop);assert!(OriginalLiteralData::from_value_using("raw".into(),OriginalTokenValue::String("value"),&a).is_err());assert_eq!(a.take_operational_error().unwrap().raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),0);
  let fresh=SettingAdmission::new(&counter,1<<20,&no);drop(OriginalLiteralData::from_value_using("x".into(),OriginalTokenValue::Int(1),&fresh).unwrap());assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn interpolation_is_typed_unissued_not_static_or_an_empty_tree(){let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=SettingAdmission::new(&counter,1<<20,&poll);let error=OriginalLiteralData::from_value_using("\"[x]a\"".into(),OriginalTokenValue::InterpBegin(""),&a).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::Unsupported);assert_eq!(counter.load(Ordering::Acquire),0);}
}

#[cfg(test)]mod admitted_raw_tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 #[test]fn raw_spelling_moves_same_allocation_and_credit_without_a_second_capacity_charge(){
  let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=SettingAdmission::new(&counter,1<<20,&poll);let mut raw=String::with_capacity(4096);raw.push_str("\"[static]\"");let ptr=raw.as_ptr();let capacity=raw.capacity();let credit=a.reserve(capacity).unwrap();let data=OriginalLiteralData::from_admitted_raw_using(raw,credit,OriginalTokenValue::Int(3),&a).unwrap();assert_eq!(data.raw_storage().as_ptr(),ptr);assert_eq!(counter.load(Ordering::Acquire),capacity+size_of::<Payload>()+2*size_of::<usize>());drop(data);assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn foreign_or_short_admitted_raw_credit_is_rejected_without_moving_domains_or_leaking_raw(){
  let own=Arc::new(AtomicUsize::new(0));let other=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=SettingAdmission::new(&own,1<<20,&poll);let foreign=SettingAdmission::new(&other,1<<20,&poll);let raw=String::from("raw");let credit=foreign.reserve(raw.capacity()).unwrap();assert!(OriginalLiteralData::from_admitted_raw_using(raw,credit,OriginalTokenValue::Int(1),&a).is_err());assert_eq!(own.load(Ordering::Acquire),0);assert_eq!(other.load(Ordering::Acquire),0);let fresh=SettingAdmission::new(&own,1<<20,&poll);let raw=String::from("raw");let short=fresh.reserve(raw.capacity()-1).unwrap();assert!(OriginalLiteralData::from_admitted_raw_using(raw,short,OriginalTokenValue::Int(1),&fresh).is_err());assert_eq!(own.load(Ordering::Acquire),0);
 }
}

#[cfg(test)]mod string_mode_tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 #[test]fn actual_modes_are_distinct_immutable_facts_without_spelling_inference_or_ast_cache(){let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let raw="\"same\\n[static]\"";let mut values=Vec::new();for mode in [OriginalStringMode::Unknown,OriginalStringMode::Normal,OriginalStringMode::Raw,OriginalStringMode::Generated]{let data=OriginalLiteralData::from_value_with_mode_using(raw.into(),OriginalTokenValue::String("same\\n[static]"),mode,&a).unwrap();assert_eq!(data.string_mode(),mode);let text=crate::LiteralText::from_original_data(&data,70,&a).unwrap();assert_eq!(text.original_string_mode(),Some(mode));assert_eq!(text.rebind_original_using(90,&a).unwrap().original_string_mode(),Some(mode));assert!(text.syntax_parts().unwrap().is_none());for old in &values{assert_ne!(&data,old);}values.push(data);}drop(values);assert_eq!(used.load(Ordering::Acquire),0);}
 #[test]fn existing_ctor_does_not_guess_mode_and_admitted_raw_keeps_pointer_credit_and_real_mode(){let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let old=OriginalLiteralData::from_value_using("@{raw}".into(),OriginalTokenValue::String("raw"),&a).unwrap();assert_eq!(old.string_mode(),OriginalStringMode::Unknown);drop(old);let raw=String::from("raw grammar");let ptr=raw.as_ptr();let credit=a.reserve(raw.capacity()).unwrap();let data=OriginalLiteralData::from_admitted_raw_with_mode_using(raw,credit,OriginalTokenValue::String("typed"),OriginalStringMode::Raw,&a).unwrap();assert_eq!(data.raw_storage().as_ptr(),ptr);assert_eq!(data.string_mode(),OriginalStringMode::Raw);drop(data);assert_eq!(used.load(Ordering::Acquire),0);}
}
