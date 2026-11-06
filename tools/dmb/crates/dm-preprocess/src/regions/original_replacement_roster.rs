//! Compact retained DATA for an already issued physical definition. Wide
//! rows keep the original typed tokens when any exact proof is unavailable.
use super::{OriginalDefinitionName,original_poll,retain_product_rows,visit_product_rows};
use crate::macro_expansion::{empty_exact,OriginalMacroOrigin as Origin,OriginalMacroRows as Rows,OriginalMacroTextValue as Text,OriginalMacroToken as Token,OriginalMacroValue as Value};
use dm_syntax::{OriginalStringMode,SettingAdmission,SettingRootLease,Span};
use std::{io,mem::size_of};

const WHITESPACE:u8=1;
const CLOSE_COLON:u8=2;
const INVOCATION:u8=4;

#[derive(Clone,Copy)]
enum PhysicalValue{Ident,Int(i32),Float(u32),Punct(&'static str)}
pub(super) struct PhysicalToken{start:u32,end:u32,line:u32,column:u32,value:PhysicalValue,flags:u8}
impl PhysicalToken{
 fn encode(token:&Token<'static>,name:&OriginalDefinitionName)->Option<Self>{
  let frame=name.lexical_frame.as_ref()?;
  let origin=token.origin;
  if !token.lexical_frame.as_ref().is_some_and(|token_frame|token_frame.same_frame(frame))
   ||origin.occurrence!=name.origin.occurrence||token.lexical_span!=Some(origin.physical)
   ||token.raw_spelling.is_some()||token.string_mode!=OriginalStringMode::Unknown{return None}
  let column=match origin.byte_column{None=>0,Some(column)=>u32::try_from(column).ok().filter(|n|*n!=0)?};
  let mut flags=0;
  if token.punctuation_close{flags|=CLOSE_COLON;}
  if origin.invocation{flags|=INVOCATION;}
  let value=match &token.value{
   Value::Ident{spelling:Text::Source(actual),whitespace}=>{
    if !frame.acquisition().source_text().matches_retained_subview(origin.physical.range(),actual){return None}
    if *whitespace{flags|=WHITESPACE;}
    PhysicalValue::Ident
   }
   Value::Int(value)=>PhysicalValue::Int(*value),
   Value::Float(value)=>PhysicalValue::Float(value.to_bits()),
   Value::Punct(text)=>PhysicalValue::Punct(*text),
   _=>return None,
  };
  Some(Self{start:u32::try_from(origin.physical.start).ok()?,end:u32::try_from(origin.physical.end).ok()?,line:u32::try_from(origin.line).ok()?,column,value,flags})
 }
 fn span(&self)->Span{Span::new(self.start as usize,self.end as usize)}
 fn decode(&self,name:&OriginalDefinitionName)->io::Result<Token<'static>>{
  let frame=name.lexical_frame.as_ref().ok_or(io::ErrorKind::InvalidData)?;
  let span=self.span();
  let value=match self.value{
   PhysicalValue::Ident=>Value::Ident{spelling:Text::Source(frame.acquisition().source_text().checked_view(span.range()).ok_or(io::ErrorKind::InvalidData)?),whitespace:self.flags&WHITESPACE!=0},
   PhysicalValue::Int(value)=>Value::Int(value),
   PhysicalValue::Float(value)=>Value::Float(f32::from_bits(value)),
   PhysicalValue::Punct(value)=>Value::Punct(value),
  };
  let origin=Origin{physical:span,line:self.line as usize,byte_column:(self.column!=0).then_some(self.column as usize),occurrence:name.origin.occurrence,invocation:self.flags&INVOCATION!=0};
  Ok(Token{string_mode:OriginalStringMode::Unknown,punctuation_close:self.flags&CLOSE_COLON!=0,lexical_frame:Some(frame.clone()),lexical_span:Some(span),value,raw_spelling:None,origin})
 }
}

pub(super) enum Replacement{Exact(Vec<Token<'static>>),Physical(Vec<PhysicalToken>)}
impl Replacement{
 pub(super) fn capture(rows:Rows<Token<'static>>,name:Option<&OriginalDefinitionName>,credit:&mut SettingRootLease,a:&SettingAdmission<'_>)->io::Result<Self>{
  let Some(name)=name.filter(|name|name.lexical_frame.is_some())else{return retain_product_rows(rows,credit,a).map(Self::Exact)};
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
  let mut result=Rows::new(a)?;
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
