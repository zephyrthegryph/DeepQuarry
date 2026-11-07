//! Compact retained DATA for an already issued physical definition. Wide
//! rows keep the original typed tokens when any exact proof is unavailable.
use super::{OriginalDefinitionName,original_poll,retain_product_rows,visit_product_rows};
use crate::macro_expansion::{empty_exact,OriginalMacroOrigin as Origin,OriginalMacroRows as Rows,OriginalMacroTextValue as Text,OriginalMacroToken as Token,OriginalMacroValue as Value};
use dm_syntax::{OriginalStringMode,SettingAdmission,SettingRootLease,Span};
use dm_syntax::original_scalar_transport::{
    original_punctuation_storage_index, original_punctuation_storage_value,
};
use std::{io,mem::size_of};

const WHITESPACE:u8=1;
const CLOSE_COLON:u8=2;
const INVOCATION:u8=4;

#[derive(Clone, Copy)]
#[repr(u8)]
enum PhysicalValue { Ident, Int, Float, Punct }

pub(super) struct PhysicalToken {
    start: u32, end: u32, line: u32, column: u32,
    payload: u32, value: PhysicalValue, flags: u8,
}
impl PhysicalToken{
 fn encode(token:&Token<'static>,name:&OriginalDefinitionName)->Option<Self>{
  let frame=name.lexical_frame()?;
  let origin=token.origin;
  if !token.lexical_frame.as_ref().is_some_and(|token_frame|token_frame.same_frame(frame))
   ||origin.occurrence!=name.origin().occurrence||token.lexical_span!=Some(origin.physical)
   ||token.raw_spelling.is_some()||token.string_mode!=OriginalStringMode::Unknown{return None}
  let column=match origin.byte_column{None=>0,Some(column)=>u32::try_from(column).ok().filter(|n|*n!=0)?};
  let mut flags=0;
  if token.punctuation_close{flags|=CLOSE_COLON;}
  if origin.invocation{flags|=INVOCATION;}
  let (value, payload)=match &token.value{
   Value::Ident{spelling:Text::Source(actual),whitespace}=>{
    if !frame.acquisition().source_text().matches_retained_subview(origin.physical.range(),actual){return None}
    if *whitespace{flags|=WHITESPACE;}
    (PhysicalValue::Ident, 0)
   }
   Value::Int(value)=>(PhysicalValue::Int,*value as u32),
   Value::Float(value)=>(PhysicalValue::Float,value.to_bits()),
   Value::Punct(text)=>(PhysicalValue::Punct,u32::from(original_punctuation_storage_index(text)?)),
   _=>return None,
  };
  Some(Self{start:u32::try_from(origin.physical.start).ok()?,end:u32::try_from(origin.physical.end).ok()?,line:u32::try_from(origin.line).ok()?,column,payload,value,flags})
 }
 fn span(&self)->Span{Span::new(self.start as usize,self.end as usize)}
 fn decode(&self,name:&OriginalDefinitionName)->io::Result<Token<'static>>{
  let frame=name.lexical_frame().ok_or(io::ErrorKind::InvalidData)?;
  let span=self.span();
  let value=match self.value{
   PhysicalValue::Ident=>Value::Ident{spelling:Text::Source(frame.acquisition().source_text().checked_view(span.range()).ok_or(io::ErrorKind::InvalidData)?),whitespace:self.flags&WHITESPACE!=0},
   PhysicalValue::Int=>Value::Int(self.payload as i32),
   PhysicalValue::Float=>Value::Float(f32::from_bits(self.payload)),
   PhysicalValue::Punct=>{
    let index=u8::try_from(self.payload).map_err(|_|io::ErrorKind::InvalidData)?;
    Value::Punct(original_punctuation_storage_value(index).ok_or(io::ErrorKind::InvalidData)?)
   }
  };
  let origin=Origin{physical:span,line:self.line as usize,byte_column:(self.column!=0).then_some(self.column as usize),occurrence:name.origin().occurrence,invocation:self.flags&INVOCATION!=0};
  Ok(Token{string_mode:OriginalStringMode::Unknown,punctuation_close:self.flags&CLOSE_COLON!=0,lexical_frame:Some(frame.clone()),lexical_span:Some(span),value,raw_spelling:None,origin})
 }
}

pub(super) enum Replacement{Exact(Vec<Token<'static>>),Physical(Vec<PhysicalToken>)}
impl Replacement{
 pub(super) fn capture(rows:Rows<Token<'static>>,name:Option<&OriginalDefinitionName>,credit:&mut SettingRootLease,a:&SettingAdmission<'_>)->io::Result<Self>{
  let Some(name)=name.filter(|name|name.lexical_frame().is_some())else{return retain_product_rows(rows,credit,a).map(Self::Exact)};
  if rows.len()==0||!rows.is_admitted_by(a)||size_of::<PhysicalToken>()>=size_of::<Token<'static>>(){return retain_product_rows(rows,credit,a).map(Self::Exact)}
  // Prove eligibility for the entire roster before reserving any overlap.
  for token in rows.as_slice(){original_poll(a)?;if PhysicalToken::encode(token,name).is_none(){return retain_product_rows(rows,credit,a).map(Self::Exact)}}
  let bytes=rows.len().checked_mul(size_of::<PhysicalToken>()).ok_or(io::ErrorKind::OutOfMemory)?;
  // Keep the actual original rows funded through the compact allocation.
  a.grow(credit,bytes).map_err(|error|a.take_operational_error().unwrap_or(error))?;
  let mut packed=empty_exact(rows.len(),a)?;
  for token in rows.as_slice(){
   original_poll(a)?;
   packed.push(PhysicalToken::encode(token,name).ok_or(io::ErrorKind::InvalidData)?);
  }
  drop(rows);
  Ok(Self::Physical(packed))
 }
 pub(super) fn len(&self)->usize{match self{Self::Exact(rows)=>rows.len(),Self::Physical(packed)=>packed.len()}}
 pub(super) fn visit_allocation(&self,mut visit:impl FnMut(usize,usize)){
  match self{Self::Exact(rows)=>visit_product_rows(rows,&mut visit),Self::Physical(packed)=>visit_product_rows(packed,&mut visit)}
 }
 pub(super) fn wide(&self)->&[Token<'static>]{match self{Self::Exact(rows)=>rows.as_slice(),Self::Physical(_)=>&[]}}
 #[cfg(test)]
 pub(super) fn is_compact(&self)->bool{matches!(self,Self::Physical(_))}
 pub(super) fn duplicate_using(&self,name:Option<&OriginalDefinitionName>,a:&SettingAdmission<'_>)->io::Result<Rows<Token<'static>>>{
  let mut result=Rows::with_capacity(self.len(),a)?;
  match self{
   Self::Exact(rows)=>for token in rows.as_slice(){original_poll(a)?;result.push(token.duplicate(a)?,a)?;},
   Self::Physical(packed)=>{
    let name=name.ok_or(io::ErrorKind::InvalidData)?;
    for token in packed{original_poll(a)?;original_poll(a)?;result.push(token.decode(name)?,a)?;}
   }
  }
  Ok(result)
 }
}

#[cfg(test)]
mod punctuation_storage_tests {
    use super::*;
    use std::sync::{atomic::{Ordering}};

    #[test]
    fn original_replacement_copy_reserves_only_its_complete_output_buffer() {
        let used = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let admission = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let count = 73;
        let mut rows = Rows::with_capacity(count, &admission).unwrap();
        for ordinal in 0..count {
            let span = Span::new(ordinal, ordinal + 1);
            rows.push(Token {
                value: Value::Punct("+"),
                punctuation_close: false,
                origin: Origin { physical: span, line: 1, byte_column: Some(ordinal + 1),
                    occurrence: 0, invocation: false },
                lexical_frame: None,
                lexical_span: None,
                raw_spelling: None,
                string_mode: OriginalStringMode::Unknown,
            }, &admission).unwrap();
        }
        let mut credit = admission.reserve(0).unwrap();
        let replacement = Replacement::capture(rows, None, &mut credit, &admission).unwrap();
        let original_charge = used.load(Ordering::Acquire);
        let output_bytes = count * size_of::<Token<'static>>();
        let tight = SettingAdmission::new(&used, original_charge + output_bytes, &|| Ok(()));
        let duplicate = replacement.duplicate_using(None, &tight).unwrap();
        assert_eq!(duplicate.capacity(), count);
        assert_eq!(used.load(Ordering::Acquire), original_charge + output_bytes);
        for (original, copy) in replacement.wide().iter().zip(duplicate.as_slice()) {
            assert!(matches!(copy.value, Value::Punct("+")));
            assert_eq!(copy.origin, original.origin);
        }
        drop((duplicate, replacement, credit));
        assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
    }

    #[test]
    fn physical_punctuation_reserves_exact_compact_width_and_preserves_wide_fallback() {
        assert_eq!(size_of::<PhysicalToken>(), 24);
        #[cfg(target_pointer_width = "64")]
        {
            #[allow(dead_code)]
            enum PriorValue { Ident, Int(i32), Float(u32), Punct(&'static str) }
            #[allow(dead_code)]
            struct PriorToken { start:u32,end:u32,line:u32,column:u32,value:PriorValue,flags:u8 }
            assert!(size_of::<PhysicalToken>() < size_of::<PriorToken>());
        }
        let used = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let healthy = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let lease = crate::SourceAcquisitionLease::from_raw_original_bytes(b"NAME : :::".to_vec(), 19u64);
        let frame = crate::regions::OriginalLexicalFrameIdentity::issue(lease.clone(), &healthy).unwrap();
        let name_span = Span::new(0, 4);
        let span = Span::new(5, 6);
        let origin = Origin { physical: span, line: 1, byte_column: Some(6), occurrence: 3, invocation: false };
        let mut name_credit = healthy.reserve(0).unwrap();
        let name = OriginalDefinitionName::capture(super::super::WideDefinitionName {
            origin: Origin { physical: name_span, byte_column: Some(1), ..origin },
            spelling: Text::Source(lease.source_text().checked_view(name_span.range()).unwrap()),
            lexical_frame: Some(frame.clone()),
        }, Some(name_span), &mut name_credit, &healthy).unwrap();
        assert!(name.uses_physical_storage());
        assert_eq!(name_credit.bytes(), 0);
        let make = |spelling: &'static str| {
            let mut rows = Rows::new(&healthy).unwrap();
            rows.push_definition_row(Token {
                value: Value::Punct(spelling), punctuation_close: true, origin,
                lexical_frame: Some(frame.clone()), lexical_span: Some(span),
                raw_spelling: None, string_mode: OriginalStringMode::Unknown,
            }, &healthy).unwrap();
            rows
        };
        let base = used.load(Ordering::Acquire);
        let mut credit = healthy.reserve(0).unwrap();
        let rows = make(":");
        let short = SettingAdmission::new(&used, used.load(Ordering::Acquire) + size_of::<PhysicalToken>() - 1, &|| Ok(()));
        let error = Replacement::capture(rows, Some(&name), &mut credit, &short).err().unwrap();
        assert_eq!(error.kind(), io::ErrorKind::OutOfMemory);
        assert_eq!(used.load(Ordering::Acquire), base);
        assert_eq!(credit.bytes(), 0);
        let rows = make(":");
        let exact = SettingAdmission::new(&used, used.load(Ordering::Acquire) + size_of::<PhysicalToken>(), &|| Ok(()));
        let compact = Replacement::capture(rows, Some(&name), &mut credit, &exact).unwrap();
        assert!(compact.is_compact());
        assert_eq!(credit.bytes(), size_of::<PhysicalToken>());
        assert_eq!(used.load(Ordering::Acquire), base + size_of::<PhysicalToken>());
        let decoded = compact.duplicate_using(Some(&name), &healthy).unwrap();
        let token = &decoded.as_slice()[0];
        assert!(matches!(token.value, Value::Punct(":")));
        assert!(token.punctuation_close);
        assert_eq!(token.origin, origin);
        assert_eq!(token.lexical_span, Some(span));
        assert!(token.lexical_frame.as_ref().unwrap().same_frame(&frame));
        drop((decoded, compact, credit));
        assert_eq!(used.load(Ordering::Acquire), base);

        let mut credit = healthy.reserve(0).unwrap();
        let mut rows = make(":");
        let mut unknown = make(":::").pop().unwrap();
        unknown.origin.physical = Span::new(7, 10);
        unknown.origin.byte_column = Some(8);
        unknown.lexical_span = Some(unknown.origin.physical);
        rows.push_definition_row(unknown, &healthy).unwrap();
        let original = rows.as_slice().as_ptr();
        let wide = Replacement::capture(rows, Some(&name), &mut credit, &healthy).unwrap();
        assert!(!wide.is_compact(), "one unrecognized punctuation keeps the entire exact roster");
        assert_eq!(wide.wide().as_ptr(), original);
        assert!(matches!(wide.wide()[0].value, Value::Punct(":")));
        assert!(matches!(wide.wide()[1].value, Value::Punct(":::")));
        drop((wide, credit, name, frame, lease));
        assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
    }
}
