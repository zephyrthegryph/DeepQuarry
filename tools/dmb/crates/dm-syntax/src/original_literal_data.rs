//! Source-free Original scalar/static VALUE owner. No source/model/body cache.
use crate::{OriginalTokenValue, SettingAdmission, SettingRootLease};
use std::{fmt, io, mem::size_of, ops::Deref, sync::Arc};

/// Actual producer-issued lexical form, distinct from the neutral String value.
/// Unknown is deliberately unissued; spelling and value never reconstruct it.
#[repr(u8)]
#[derive(Clone,Copy,Debug,Default,Eq,PartialEq,Hash)]
pub enum OriginalStringMode{#[default]Unknown=0,Normal=1,Raw=2,Generated=3}
#[repr(u8)]
#[derive(Clone, Copy)]
enum LiteralKind { Int, Float, String, Resource, InterpBegin, InterpPart, InterpEnd }

struct Payload {
    kind: LiteralKind,
    scalar_bits: u32,
    string_mode:OriginalStringMode,
    // A nonzero end means the issued typed text exactly equals these raw
    // UTF-8 bytes. Empty text already needs no allocation; [0, 0] is owned.
    value_in_raw: [u8; 2],
    raw: String,
    text: Box<str>,
    // LAST: both physical strings die before the original counter is credited.
    credit: SettingRootLease,
}
/// No public Arc/Weak escape: final Arc::into_inner deallocates its control
/// before dropping payload buffers and then its SAME resource-only credit.
// A unique backing needs ordinal 0. The private producer pool can reuse
// a backing but mints a different nonzero ordinal for each occurrence.
pub struct OriginalLiteralData(Option<Arc<Payload>>, usize);
impl Clone for OriginalLiteralData {
    fn clone(&self)->Self { Self(Some(Arc::clone(self.0.as_ref().expect("live literal DATA"))),self.1) }
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
fn copy_value_text(s:&str,a:&SettingAdmission<'_>,credit:&mut SettingRootLease)->io::Result<Box<str>> {
    a.checkpoint()?;
    if s.is_empty(){return Ok(Box::default())}
    let layout=std::alloc::Layout::array::<u8>(s.len()).map_err(|e|fail(a,io::Error::new(io::ErrorKind::OutOfMemory,e)))?;
    a.grow(credit,s.len())?;
    let pointer=std::ptr::NonNull::new(unsafe{std::alloc::alloc(layout)}).ok_or_else(||fail(a,io::ErrorKind::OutOfMemory.into()))?;
    // SAFETY: Global owns exactly s.len() bytes. Copying the entire &str
    // initializes the allocation with valid UTF-8 before Box takes ownership.
    // Box<str> drops with the same length-derived Global layout.
    let text = unsafe {
        std::ptr::copy_nonoverlapping(s.as_ptr(), pointer.as_ptr(), s.len());
        let raw = std::ptr::slice_from_raw_parts_mut(pointer.as_ptr(), s.len());
        Box::from_raw(raw as *mut str)
    };
    a.checkpoint()?;
    Ok(text)
}

fn store_static_value(s: &str, pending: &mut Payload, a: &SettingAdmission<'_>) -> io::Result<Box<str>> {
    // Bounded byte comparison only. The caller has already issued the VALUE
    // and the lossless spelling independently; no quote/escape rule is used.
    if !s.is_empty() && pending.raw.len() <= usize::from(u8::MAX) && s.len() <= pending.raw.len() {
        a.checkpoint()?;
        if let Some(start) = pending.raw.find(s) {
            let end = start + s.len(); // find proves this nonempty UTF-8 range is inside raw
            pending.value_in_raw = [start as u8, end as u8];
            return Ok(Box::default());
        }
    }
    copy_value_text(s, a, &mut pending.credit)
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
        let mut pending=Payload{kind:LiteralKind::Int,scalar_bits:0,string_mode:mode,value_in_raw:[0,0],raw,text:Box::default(),credit};
        a.checkpoint()?;
        if !a.matches_lease_domain(&pending.credit)||pending.credit.bytes()<pending.raw.capacity(){
            return Err(fail(a,io::Error::new(io::ErrorKind::InvalidInput,"Original raw literal storage lacks its actual SAME-domain capacity credit")));
        }
        if !matches!(&value,OriginalTokenValue::Int(_)|OriginalTokenValue::Float(_)|OriginalTokenValue::String(_)|OriginalTokenValue::Resource(_)|OriginalTokenValue::InterpBegin(_)|OriginalTokenValue::InterpPart(_)|OriginalTokenValue::InterpEnd(_)) {
            return Err(fail(a,io::Error::new(io::ErrorKind::Unsupported,"Original literal DATA requires an actual scalar/static or interpolation-part value")));
        }
        if mode!=OriginalStringMode::Unknown&&!matches!(&value,OriginalTokenValue::String(_)|OriginalTokenValue::InterpBegin(_)|OriginalTokenValue::InterpPart(_)|OriginalTokenValue::InterpEnd(_)){
            return Err(fail(a,io::Error::new(io::ErrorKind::InvalidInput,"Original lexical string mode attached to non-String literal DATA")));
        }
        let fixed=bytes(a,size_of::<Payload>().checked_add(2*size_of::<usize>()))?;
        a.grow(&mut pending.credit,fixed)?;
        pending.kind = match value {
            OriginalTokenValue::Int(n) => {
                pending.scalar_bits = n as u32;
                LiteralKind::Int
            }
            OriginalTokenValue::Float(n) => {
                pending.scalar_bits = n.to_bits();
                LiteralKind::Float
            }
            OriginalTokenValue::String(s) => {
                pending.text = store_static_value(s, &mut pending, a)?;
                LiteralKind::String
            }
            OriginalTokenValue::Resource(s) => {
                pending.text = store_static_value(s, &mut pending, a)?;
                LiteralKind::Resource
            }
            OriginalTokenValue::InterpBegin(s) => {
                pending.text = copy_value_text(s, a, &mut pending.credit)?;
                LiteralKind::InterpBegin
            }
            OriginalTokenValue::InterpPart(s) => {
                pending.text = copy_value_text(s, a, &mut pending.credit)?;
                LiteralKind::InterpPart
            }
            OriginalTokenValue::InterpEnd(s) => {
                pending.text = copy_value_text(s, a, &mut pending.credit)?;
                LiteralKind::InterpEnd
            }
            _ => unreachable!("closed scalar/static/template-part gate"),
        };
        a.checkpoint()?;
        Ok(Self(Some(Arc::new(pending)),0))
    }
    pub fn string_mode(&self)->OriginalStringMode{self.payload().string_mode}
    pub fn raw(&self)->&str { &self.payload().raw }
    pub fn raw_storage(&self)->&String { &self.payload().raw }
    pub fn value(&self)->OriginalTokenValue<&str> {
        let payload = self.payload();
        let [start, end] = payload.value_in_raw;
        let text: &str = if end != 0 {
            &payload.raw[usize::from(start)..usize::from(end)]
        } else {
            &payload.text
        };
        match payload.kind {
            LiteralKind::Int => OriginalTokenValue::Int(payload.scalar_bits as i32),
            LiteralKind::Float => OriginalTokenValue::Float(f32::from_bits(payload.scalar_bits)),
            LiteralKind::String => OriginalTokenValue::String(text),
            LiteralKind::Resource => OriginalTokenValue::Resource(text),
            LiteralKind::InterpBegin => OriginalTokenValue::InterpBegin(text),
            LiteralKind::InterpPart => OriginalTokenValue::InterpPart(text),
            LiteralKind::InterpEnd => OriginalTokenValue::InterpEnd(text),
        }
    }
    /// Issued literal occurrence identity, independent of storage reuse.
    pub fn same_owner(&self,other:&Self)->bool {
        self.1 == other.1 && Arc::ptr_eq(self.0.as_ref().unwrap(),other.0.as_ref().unwrap())
    }
    pub fn kind(&self)->&'static str {
        match self.payload().kind {
            LiteralKind::Int => "Int",
            LiteralKind::Float => "Float",
            LiteralKind::String => "String",
            LiteralKind::Resource => "Resource",
            LiteralKind::InterpBegin => "InterpBegin",
            LiteralKind::InterpPart => "InterpPart",
            LiteralKind::InterpEnd => "InterpEnd",
        }
    }
    // The Arc reference itself is already in the primary row allocation.
    // Do not count shared admission-counter Arcs in this payload family.
    #[cfg(debug_assertions)]
    pub(crate) fn trace_payload(&self)->(bool,usize){
        let owner=self.0.as_ref().expect("live literal DATA");
        (Arc::strong_count(owner)==1,owner.credit.bytes())
    }
    /// Exact known live allocations only, not reservations, parser caches or
    /// source authority. Caller performs address dedup across all aliases.
    pub fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)) {
        let p=self.payload();let fixed=size_of::<Payload>()+2*size_of::<usize>();
        visit(Arc::as_ptr(self.0.as_ref().unwrap())as usize,fixed,fixed);
        visit(p.raw.as_ptr()as usize,p.raw.len(),p.raw.capacity());
        if !p.text.is_empty() {
            visit(p.text.as_ptr() as usize, p.text.len(), p.text.len());
        }
        p.credit.visit_counter_storage(|ptr,n|{let bytes=n+2*size_of::<usize>();visit(ptr,bytes,bytes)});
    }
}
const NUMERIC_SLOTS:usize=16;
const SHORT_NUMERIC_BYTES:usize=16;
#[derive(Clone,Copy,PartialEq,Eq)]
enum NumericKey { Int(i32), Float(u32) }
impl NumericKey {
    fn from_value(value:&OriginalTokenValue<&str>)->Option<Self> {
        match value {
            OriginalTokenValue::Int(value)=>Some(Self::Int(*value)),
            OriginalTokenValue::Float(value)=>Some(Self::Float(value.to_bits())),
            _=>None,
        }
    }
    fn slot(self, raw:&str)->usize {
        // Slot selection is only a reuse hint. Full spelling and typed bits
        // are checked on every hit; a collision simply replaces one entry.
        let mut hash=match self {
            Self::Int(value)=>value as u32,
            Self::Float(bits)=>bits ^ 0xa9b4_e9e1,
        };
        for byte in raw.bytes() {
            hash=hash.wrapping_mul(16_777_619) ^ u32::from(byte);
        }
        (hash as usize) % NUMERIC_SLOTS
    }
}

const STATIC_SLOTS: usize = 128;
const STATIC_WAYS: usize = 4;
const STATIC_SETS: usize = STATIC_SLOTS / STATIC_WAYS;
const SHORT_STATIC_BYTES: usize = 128;

#[derive(Clone, Copy, PartialEq, Eq)]
enum StaticKey<'a> { String(&'a str), Resource(&'a str) }
impl<'a> StaticKey<'a> {
    fn from_value(value: &OriginalTokenValue<&'a str>, mode: OriginalStringMode) -> Option<Self> {
        match value {
            OriginalTokenValue::String(text) => Some(Self::String(*text)),
            OriginalTokenValue::Resource(text) if mode == OriginalStringMode::Unknown => Some(Self::Resource(*text)),
            _ => None,
        }
    }
    fn text(self) -> &'a str {
        match self { Self::String(text) | Self::Resource(text) => text }
    }
    fn slot(self, raw: &str, mode: OriginalStringMode) -> usize {
        // Collisions only select eviction. The hit path also compares the full
        // raw spelling, issued lexical mode and exact typed text and variant.
        let tag = match self { Self::String(_) => 0x8cf5_3331u32, Self::Resource(_) => 0x7a40_6b91 };
        let mut hash = tag ^ u32::from(mode as u8);
        for byte in raw.bytes().chain(self.text().bytes()) {
            hash = hash.wrapping_mul(16_777_619) ^ u32::from(byte);
        }
        (hash as usize) % STATIC_SLOTS
    }
}

/// Bounded producer-local reuse of short immutable VALUE storage. Numeric
/// slots keep their original geometry. The separate static bank is inline in
/// the output cursor and cannot issue spans, raw frames or parser authority.
pub struct OriginalLiteralPool {
    numeric: [Option<OriginalLiteralData>; NUMERIC_SLOTS],
    static_text: [[Option<OriginalLiteralData>; STATIC_WAYS]; STATIC_SETS],
    issued: usize,
    domain: SettingRootLease,
}
impl OriginalLiteralPool {
    pub fn new(a:&SettingAdmission<'_>)->io::Result<Self> {
        Ok(Self {
            numeric: std::array::from_fn(|_| None),
            static_text: std::array::from_fn(|_| std::array::from_fn(|_| None)),
            issued: 0,
            domain: a.reserve(0)?,
        })
    }

    pub fn issue_using(&mut self,raw:String,credit:SettingRootLease,value:OriginalTokenValue<&str>,mode:OriginalStringMode,a:&SettingAdmission<'_>)->io::Result<OriginalLiteralData> {
        // Actual borrowed raw bytes have already been copied by the caller
        // in its existing source IO order. Even a cache hit must authenticate
        // and drop that actual allocation before releasing its own credit.
        struct Pending { raw:String, credit:SettingRootLease }
        let pending=Pending{raw,credit};
        a.checkpoint()?;
        if !a.matches_lease_domain(&self.domain)||!a.matches_lease_domain(&pending.credit)||pending.credit.bytes()<pending.raw.capacity(){
            return Err(fail(a,io::Error::new(io::ErrorKind::InvalidInput,"literal reuse requires the actual SAME-domain raw literal allocation")));
        }
        let Some(ordinal) = self.issued.checked_add(1) else {
            return OriginalLiteralData::from_admitted_raw_with_mode_using(pending.raw,pending.credit,value,mode,a);
        };
        let numeric = NumericKey::from_value(&value)
            .filter(|_| mode == OriginalStringMode::Unknown && pending.raw.len() <= SHORT_NUMERIC_BYTES);
        let static_key = StaticKey::from_value(&value, mode)
            .filter(|key| pending.raw.len() <= SHORT_STATIC_BYTES && key.text().len() <= SHORT_STATIC_BYTES);
        let candidates: &mut [Option<OriginalLiteralData>] = if let Some(key) = numeric {
            std::slice::from_mut(&mut self.numeric[key.slot(&pending.raw)])
        } else if let Some(key) = static_key {
            // Same fixed bank size. A spelling collision can displace only
            // the least recently used value after the whole set fills.
            &mut self.static_text[key.slot(&pending.raw, mode) / STATIC_WAYS]
        } else {
            return OriginalLiteralData::from_admitted_raw_with_mode_using(pending.raw,pending.credit,value,mode,a);
        };
        let matching = candidates.iter().position(|candidate| {
            candidate.as_ref().is_some_and(|cached| {
                if cached.raw() != pending.raw || cached.string_mode() != mode {
                    return false;
                }
                let current = cached.value();
                if let Some(key) = numeric {
                    return NumericKey::from_value(&current) == Some(key);
                }
                StaticKey::from_value(&current, mode) == static_key
            })
        });
        if let Some(index) = matching {
            // Only this pool sees this backing. One serial covers both banks,
            // preserving each occurrence even after eviction and reinsertion.
            let mut occurrence = candidates[index].as_ref().expect("matched occupied slot").clone();
            occurrence.1 = ordinal;
            drop(pending);
            a.checkpoint()?;
            candidates[..=index].rotate_right(1);
            self.issued = ordinal;
            return Ok(occurrence);
        }
        let mut occurrence=OriginalLiteralData::from_admitted_raw_with_mode_using(pending.raw,pending.credit,value,mode,a)?;
        occurrence.1=ordinal;
        candidates.rotate_right(1);
        candidates[0] = Some(occurrence.clone());
        self.issued=ordinal;
        Ok(occurrence)
    }
}

impl PartialEq for OriginalLiteralData {
    fn eq(&self,other:&Self)->bool {
        if self.raw()!=other.raw()||self.string_mode()!=other.string_mode(){return false}
        match(self.value(),other.value()) {
            (OriginalTokenValue::Int(a),OriginalTokenValue::Int(b))=>a==b,
            (OriginalTokenValue::Float(a),OriginalTokenValue::Float(b))=>a.to_bits()==b.to_bits(),
            (OriginalTokenValue::String(a),OriginalTokenValue::String(b))|(OriginalTokenValue::Resource(a),OriginalTokenValue::Resource(b))|(OriginalTokenValue::InterpBegin(a),OriginalTokenValue::InterpBegin(b))|(OriginalTokenValue::InterpPart(a),OriginalTokenValue::InterpPart(b))|(OriginalTokenValue::InterpEnd(a),OriginalTokenValue::InterpEnd(b))=>a==b,
            _=>false,
        }
    }
}
impl Eq for OriginalLiteralData {}

#[cfg(test)]mod tests {
 use super::*; use std::sync::atomic::{AtomicUsize,Ordering};
 #[test]
 fn compact_literal_payload_preserves_typed_bits_text_and_exact_admitted_storage() {
    #[cfg(target_pointer_width = "64")]
    {
        #[allow(dead_code)]
        struct PreviousShape {
            string_mode: OriginalStringMode,
            value_in_raw: [u8; 2],
            raw: String,
            value: OriginalTokenValue<String>,
            credit: SettingRootLease,
        }
        assert_eq!(size_of::<Payload>(), 64);
        assert_eq!(size_of::<PreviousShape>() - size_of::<Payload>(), 16);
    }
    let counter = Arc::new(AtomicUsize::new(0));
    let healthy = SettingAdmission::new(&counter, 1 << 20, &|| Ok(()));
    let raw = String::from("raw spelling");
    let fixed = size_of::<Payload>() + 2 * size_of::<usize>();
    let total = fixed + raw.capacity() + "typed é".len();
    let tight = SettingAdmission::new(&counter, total - 1, &|| Ok(()));
    assert_eq!(
        OriginalLiteralData::from_value_using(raw.clone(), OriginalTokenValue::InterpPart("typed é"), &tight).unwrap_err().kind(),
        io::ErrorKind::OutOfMemory,
    );
    assert_eq!(counter.load(Ordering::Acquire), 0);
    let part = OriginalLiteralData::from_value_using(raw, OriginalTokenValue::InterpPart("typed é"), &healthy).unwrap();
    assert!(matches!(part.value(), OriginalTokenValue::InterpPart("typed é")));
    assert_eq!(counter.load(Ordering::Acquire), total);
    let mut visited = false;
    let typed = part.payload().text.as_ptr() as usize;
    part.visit_storage(|ptr, used, capacity| {
        if ptr == typed {
            visited = true;
            assert_eq!(used, "typed é".len());
            assert_eq!(capacity, used);
        }
    });
    assert!(visited);
    let alias = part.clone();
    drop(part);
    assert_eq!(counter.load(Ordering::Acquire), total);
    drop(alias);
    assert_eq!(counter.load(Ordering::Acquire), 0);

    let n = OriginalLiteralData::from_value_using("raw".into(), OriginalTokenValue::Int(i32::MIN), &healthy).unwrap();
    let f = OriginalLiteralData::from_value_using("raw".into(), OriginalTokenValue::Float(f32::from_bits(0xffc00001)), &healthy).unwrap();
    assert!(matches!(n.value(), OriginalTokenValue::Int(i32::MIN)));
    assert!(matches!(f.value(), OriginalTokenValue::Float(value) if value.to_bits() == 0xffc00001));
    drop((n, f));
    assert_eq!(counter.load(Ordering::Acquire), 0);
 }

 #[test]
 fn short_static_value_can_borrow_exact_utf8_bytes_from_its_own_raw_owner() {
  let used = Arc::new(AtomicUsize::new(0));
  let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
  let raw = r#""é\n""#;
  let same = OriginalLiteralData::from_value_with_mode_using(raw.into(), OriginalTokenValue::String(r"é\n"), OriginalStringMode::Raw, &a).unwrap();
  let OriginalTokenValue::String(value) = same.value() else { panic!("same issued String variant") };
  assert_eq!(value, r"é\n");
  assert_eq!(value.as_ptr(), same.raw()[1..].as_ptr());
  let fixed = size_of::<Payload>() + 2 * size_of::<usize>();
  assert_eq!(used.load(Ordering::Acquire), fixed + same.raw_storage().capacity());
  assert_eq!(same.string_mode(), OriginalStringMode::Raw);
  let alias = same.clone();
  drop(same);
  assert!(matches!(alias.value(), OriginalTokenValue::String(r"é\n")));
  drop(alias);
  assert_eq!(used.load(Ordering::Acquire), 0);

  let changed = OriginalLiteralData::from_value_using(raw.into(), OriginalTokenValue::String("é\n"), &a).unwrap();
  let OriginalTokenValue::String(value) = changed.value() else { panic!("same issued String variant") };
  assert_eq!(value, "é\n");
  assert_eq!(used.load(Ordering::Acquire), fixed + changed.raw_storage().capacity() + value.len());
  let resource = OriginalLiteralData::from_value_using("'icons/a.dmi'".into(), OriginalTokenValue::Resource("icons/a.dmi"), &a).unwrap();
  let OriginalTokenValue::Resource(value) = resource.value() else { panic!("same issued Resource variant") };
  assert_eq!(value.as_ptr(), resource.raw()[1..].as_ptr());
  drop((resource, changed));
  assert_eq!(used.load(Ordering::Acquire), 0);

  let long = format!("'{}'", "x".repeat(256));
  let wide = OriginalLiteralData::from_value_using(long.clone(), OriginalTokenValue::Resource(&long[1..long.len()-1]), &a).unwrap();
  let OriginalTokenValue::Resource(value) = wide.value() else { panic!("same issued Resource variant") };
  assert_ne!(value.as_ptr(), wide.raw()[1..].as_ptr(), "wide spans keep the full-width owned path");
  assert_eq!(value.len(), 256);
  drop(wide);
  assert_eq!(used.load(Ordering::Acquire), 0);
 }
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
 #[test]fn interpolation_part_is_actual_typed_data_not_static_or_reconstructed(){let counter=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&counter,1<<20,&||Ok(()));for value in[OriginalTokenValue::InterpBegin("[not a child]"),OriginalTokenValue::InterpPart("middle"),OriginalTokenValue::InterpEnd("last")]{let data=OriginalLiteralData::from_value_with_mode_using("unrelated raw spelling".into(),value,OriginalStringMode::Normal,&a).unwrap();let alias=data.clone();assert!(matches!(data.value(),OriginalTokenValue::InterpBegin("[not a child]")|OriginalTokenValue::InterpPart("middle")|OriginalTokenValue::InterpEnd("last")));assert!(data.same_owner(&alias));drop(data);assert!(counter.load(Ordering::Acquire)>0);drop(alias);assert_eq!(counter.load(Ordering::Acquire),0);}}
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


#[cfg(test)]
mod numeric_reuse_tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    fn issue(pool:&mut OriginalLiteralPool, raw:&str, value:OriginalTokenValue<&str>, a:&SettingAdmission<'_>)->io::Result<OriginalLiteralData>{
        let raw=raw.to_owned();
        let credit=a.reserve(raw.capacity())?;
        pool.issue_using(raw,credit,value,OriginalStringMode::Unknown,a)
    }

    #[test]
    fn repeated_numeric_occurrences_share_payload_and_keep_their_own_identity(){
        let used=Arc::new(AtomicUsize::new(0));
        let a=SettingAdmission::new(&used,1<<20,&||Ok(()));
        let mut pool=OriginalLiteralPool::new(&a).unwrap();
        let first=issue(&mut pool,"7",OriginalTokenValue::Int(7),&a).unwrap();
        let first_bytes=used.load(Ordering::Acquire);
        let many:Vec<_>=(0..256).map(|_|issue(&mut pool,"7",OriginalTokenValue::Int(7),&a).unwrap()).collect();
        assert_eq!(used.load(Ordering::Acquire),first_bytes,"hits retain only the original payload");
        for next in &many {
            assert_eq!(next,&first);
            assert_eq!(next.raw_storage().as_ptr(),first.raw_storage().as_ptr());
            assert!(!next.same_owner(&first));
            assert!(next.same_owner(&next.clone()));
        }
        assert!(!many[0].same_owner(&many[1]));
        assert!(256*first_bytes>256*std::mem::size_of::<usize>(),"payload reuse also repays the occurrence word");
        drop(pool);
        drop(first);
        assert_eq!(used.load(Ordering::Acquire),first_bytes);
        drop(many);
        assert_eq!(used.load(Ordering::Acquire),0);
    }

    #[test]
    fn numeric_reuse_keeps_raw_spelling_float_bits_and_pool_domains_exact(){
        let used=Arc::new(AtomicUsize::new(0));
        let a=SettingAdmission::new(&used,1<<20,&||Ok(()));
        let mut pool=OriginalLiteralPool::new(&a).unwrap();
        let zero=issue(&mut pool,"0",OriginalTokenValue::Int(0),&a).unwrap();
        let hex=issue(&mut pool,"0x0",OriginalTokenValue::Int(0),&a).unwrap();
        let positive=issue(&mut pool,"0",OriginalTokenValue::Float(0.0),&a).unwrap();
        let negative=issue(&mut pool,"0",OriginalTokenValue::Float(-0.0),&a).unwrap();
        assert_ne!(zero,hex);
        assert_ne!(zero,positive);
        assert_ne!(positive,negative);
        assert_eq!(hex.raw(),"0x0");
        let mut foreign=OriginalLiteralPool::new(&a).unwrap();
        let other=issue(&mut foreign,"0",OriginalTokenValue::Int(0),&a).unwrap();
        assert_eq!(zero,other);
        assert!(!zero.same_owner(&other));
        assert_ne!(zero.raw_storage().as_ptr(),other.raw_storage().as_ptr());
        let first=issue(&mut pool,"7",OriginalTokenValue::Int(7),&a).unwrap();
        let raw="7".to_owned();
        let credit=a.reserve(raw.capacity()).unwrap();
        let fault=||Err(io::Error::from_raw_os_error(1450));
        let failed=SettingAdmission::new(&used,1<<20,&fault);
        assert!(pool.issue_using(raw,credit,OriginalTokenValue::Int(7),OriginalStringMode::Unknown,&failed).is_err());
        assert_eq!(failed.take_operational_error().unwrap().raw_os_error(),Some(1450));
        let next=issue(&mut pool,"7",OriginalTokenValue::Int(7),&a).unwrap();
        assert_eq!(next.raw_storage().as_ptr(),first.raw_storage().as_ptr());
        assert!(!next.same_owner(&first));
        drop((next,first,zero,hex,positive,negative,other,foreign,pool));
        assert_eq!(used.load(Ordering::Acquire),0);
    }
}

#[cfg(test)]
mod static_reuse_tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    fn issue(pool: &mut OriginalLiteralPool, raw: &str, value: OriginalTokenValue<&str>,
        mode: OriginalStringMode, a: &SettingAdmission<'_>) -> OriginalLiteralData {
        let raw = raw.to_owned();
        let credit = a.reserve(raw.capacity()).unwrap();
        pool.issue_using(raw, credit, value, mode, a).unwrap()
    }

    #[test]
    fn short_static_values_share_only_exact_raw_typed_value_mode_and_producer() {
        use OriginalStringMode::{Generated, Normal, Raw, Unknown};
        use OriginalTokenValue::{InterpBegin, Resource, String};
        let used = Arc::new(AtomicUsize::new(0));
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut pool = OriginalLiteralPool::new(&a).unwrap();
        let first = issue(&mut pool, r#""[static]""#, String("[static]"), Generated, &a);
        let paid = used.load(Ordering::Acquire);
        let aliases: Vec<_> = (0..64).map(|_| issue(&mut pool, r#""[static]""#, String("[static]"), Generated, &a)).collect();
        assert_eq!(used.load(Ordering::Acquire), paid);
        for next in &aliases {
            assert_eq!(first, *next);
            assert_eq!(first.raw().as_ptr(), next.raw().as_ptr());
            assert!(!first.same_owner(next));
            assert!(next.same_owner(&next.clone()));
        }
        assert!(!aliases[0].same_owner(&aliases[1]));

        let normal = issue(&mut pool, "same", String("typed"), Normal, &a);
        let raw = issue(&mut pool, "same", String("typed"), Raw, &a);
        let other_spelling = issue(&mut pool, "other", String("typed"), Normal, &a);
        let other_value = issue(&mut pool, "same", String("different"), Normal, &a);
        let resource = issue(&mut pool, "same", Resource("typed"), Unknown, &a);
        let resource_repeat = issue(&mut pool, "same", Resource("typed"), Unknown, &a);
        let unknown = issue(&mut pool, "same", String("typed"), Unknown, &a);
        for other in [&raw, &other_spelling, &other_value, &resource, &unknown] {
            assert_ne!(&normal, other);
            assert_ne!(normal.raw().as_ptr(), other.raw().as_ptr());
        }
        assert_ne!(resource, unknown);
        assert_eq!(resource.raw().as_ptr(), resource_repeat.raw().as_ptr());
        assert!(!resource.same_owner(&resource_repeat));
        let mut other = OriginalLiteralPool::new(&a).unwrap();
        let foreign = issue(&mut other, r#""[static]""#, String("[static]"), Generated, &a);
        assert_eq!(first, foreign);
        assert_ne!(first.raw().as_ptr(), foreign.raw().as_ptr());
        assert!(!first.same_owner(&foreign));

        let begin = issue(&mut pool, "fragment", InterpBegin("fragment"), Normal, &a);
        let begin_again = issue(&mut pool, "fragment", InterpBegin("fragment"), Normal, &a);
        assert_eq!(begin, begin_again);
        assert_ne!(begin.raw().as_ptr(), begin_again.raw().as_ptr());
        let long = "x".repeat(SHORT_STATIC_BYTES + 1);
        let wide = issue(&mut pool, &long, String("short"), Normal, &a);
        let wide_again = issue(&mut pool, &long, String("short"), Normal, &a);
        assert_ne!(wide.raw().as_ptr(), wide_again.raw().as_ptr());
        drop((first, aliases, normal, raw, other_spelling, other_value, resource, resource_repeat,
            unknown, foreign, begin, begin_again, wide, wide_again, other, pool));
        assert_eq!(used.load(Ordering::Acquire), 0);
    }

    #[test]
    fn static_pool_keeps_colliding_values_in_the_same_funded_bank() {
        let used = Arc::new(AtomicUsize::new(0));
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut pool = OriginalLiteralPool::new(&a).unwrap();
        assert_eq!(size_of_val(&pool.static_text), size_of::<[Option<OriginalLiteralData>; STATIC_SLOTS]>());

        let mode = OriginalStringMode::Normal;
        let slot = StaticKey::String("anchor").slot("anchor", mode);
        let mut spellings = vec!["anchor".to_owned()];
        spellings.extend((0..4096).map(|n| format!("collision-{n}"))
            .filter(|s| StaticKey::String(s).slot(s, mode) == slot).take(STATIC_WAYS));
        assert_eq!(spellings.len(), STATIC_WAYS + 1);
        let add = |pool: &mut OriginalLiteralPool, name: &str| {
            issue(pool, name, OriginalTokenValue::String(name), mode, &a)
        };

        let issued: Vec<_> = spellings[..STATIC_WAYS].iter().map(|s| add(&mut pool, s)).collect();
        let paid = used.load(Ordering::Acquire);
        let recent = add(&mut pool, &spellings[0]);
        assert_eq!(recent.raw().as_ptr(), issued[0].raw().as_ptr());
        assert!(!recent.same_owner(&issued[0]));
        assert_eq!(used.load(Ordering::Acquire), paid);

        let extra = add(&mut pool, &spellings[STATIC_WAYS]);
        let still_recent = add(&mut pool, &spellings[0]);
        let evicted = add(&mut pool, &spellings[1]);
        assert_eq!(still_recent.raw().as_ptr(), recent.raw().as_ptr());
        assert_ne!(evicted.raw().as_ptr(), issued[1].raw().as_ptr());
        assert_eq!(evicted, issued[1]);
        drop((issued, recent, extra, still_recent, evicted, pool));
        assert_eq!(used.load(Ordering::Acquire), 0);
    }

}
