//! One actual final-token projection with retained producer state, independent
//! of parser scheduling. No source/model or EOF grant follows these DATA.
use super::original_native_projection::{project_native_token_using,Adjacency,OriginalNativeProjection,needs_separator};
use crate::{SourceProvider,macro_expansion::{OriginalMacroToken as Token,OriginalMacroValue as Value}};
use dm_syntax::{SettingAdmission,SettingRootLease,Span,SpanToken};use std::{io,sync::{Arc,Mutex}};
#[derive(Clone,Copy)]struct CursorState{last:Option<Adjacency>,offset:usize,line:usize,failed:bool}
struct Payload{state:Mutex<CursorState>,credit:SettingRootLease}
/// The identity IS the actual retained output cursor allocation and its state.
/// No nonce/hash/Weak or counter detached from the producing operation exists.
pub(super) struct OriginalOutputIdentity(Option<Arc<Payload>>);
impl Clone for OriginalOutputIdentity{fn clone(&self)->Self{Self(Some(Arc::clone(self.0.as_ref().expect("live actual output cursor"))))}}
impl Drop for OriginalOutputIdentity{fn drop(&mut self){if let Some(owner)=self.0.take(){if let Some(payload)=Arc::into_inner(owner){drop(payload)}}}}
impl OriginalOutputIdentity{
 /// Exact live cursor/control allocations only. The retained lease's size
 /// is a resource reservation and is deliberately never reported as storage.
 pub(super) fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){
  let owner=self.0.as_ref().expect("live actual output cursor");let bytes=std::mem::size_of::<Payload>()+2*std::mem::size_of::<usize>();visit(Arc::as_ptr(owner)as usize,bytes,bytes);
  owner.credit.visit_counter_storage(|pointer,n|{let bytes=n+2*std::mem::size_of::<usize>();visit(pointer,bytes,bytes)});
 }
 pub(super) fn same(&self,other:&Self)->bool{Arc::ptr_eq(self.0.as_ref().unwrap(),other.0.as_ref().unwrap())}
 pub(super) fn admitted_by(&self,a:&SettingAdmission<'_>)->bool{a.matches_lease_domain(&self.0.as_ref().unwrap().credit)}
}
pub(super) struct OriginalOutputCursor{owner:OriginalOutputIdentity}
/// Fields are private to this issuing module. The receiver may only adopt the
/// SAME issued chunk; no caller can supply arbitrary padding, line or identity.
pub(super) struct OriginalPreparedOutputToken{
 token:dm_syntax::Token,literal:Option<dm_syntax::OriginalLiteralData>,actual:Option<Token<'static>>,
 leading:bool,trailing:bool,cover:Span,line:usize,owner:OriginalOutputIdentity,
 // Last: the physical token text above dies before its actual spelling credit.
 credit:SettingRootLease,
}
#[derive(Clone)]pub(super) struct OriginalDeliveryFrontier{owner:OriginalOutputIdentity,end:usize}
impl OriginalDeliveryFrontier{
 pub(super) fn belongs_to(&self,owner:&OriginalOutputIdentity)->bool{self.owner.same(owner)}
 pub(super) fn end(&self)->usize{self.end}
 pub(super) fn owner(&self)->&OriginalOutputIdentity{&self.owner}
}
/// Issued only after the driver reaches ActualEnd. This aliases the existing
/// funded output cursor and carries no token or declaration-completeness claim.
#[derive(Clone)]
pub(super) struct OriginalProducedEnd(OriginalDeliveryFrontier);
impl OriginalProducedEnd {
    pub(super) fn validate(&self, delivered: &OriginalDeliveryFrontier, a: &SettingAdmission<'_>) -> io::Result<()> {
        a.checkpoint().map_err(|error| a.take_operational_error().unwrap_or(error))?;
        if !self.0.owner.admitted_by(a) || !self.0.owner.same(&delivered.owner) || self.0.end != delivered.end {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "logical end does not close the actual delivered frontier"));
        }
        Ok(())
    }
    pub(super) fn end(&self) -> usize { self.0.end }
}
/// Borrowed actual production record; top metadata uses this SAME line/state.
pub(super) struct OriginalProducedSpan<'a>{token:&'a OriginalPreparedOutputToken}
impl OriginalProducedSpan<'_>{
 pub(super) fn is_default_semicolon(&self)->bool{self.token.actual.is_none()&&self.token.token.kind==dm_syntax::TokenKind::Punctuation&&self.token.token.text==";"&&self.token.literal.is_none()}
 pub(super) fn output_line(&self)->usize{self.token.line}
 pub(super) fn actual(&self)->io::Result<&Token<'static>>{self.token.actual()}
 pub(super) fn owner(&self)->&OriginalOutputIdentity{&self.token.owner}
 pub(super) fn token(&self)->SpanToken{SpanToken{kind:self.token.token.kind,span:self.token.token.span}}
 pub(super) fn cover(&self)->Span{self.token.cover}
}
impl OriginalOutputCursor{
 pub(super) fn new(a:&SettingAdmission<'_>)->io::Result<Self>{a.checkpoint()?;let credit=a.reserve(std::mem::size_of::<Payload>()+2*std::mem::size_of::<usize>())?;Ok(Self{owner:OriginalOutputIdentity(Some(Arc::new(Payload{state:Mutex::new(CursorState{last:None,offset:0,line:1,failed:false}),credit})))})}
 pub(super) fn identity(&self)->OriginalOutputIdentity{self.owner.clone()}
 pub(super) fn initial_delivery(&self)->io::Result<OriginalDeliveryFrontier>{let state=*self.owner.0.as_ref().unwrap().state.lock().map_err(|_|io::ErrorKind::Other)?;if state.offset!=0||state.failed{return Err(io::ErrorKind::InvalidInput.into())}Ok(OriginalDeliveryFrontier{owner:self.owner.clone(),end:0})}
 pub(super) fn seal_actual_end(&self, a: &SettingAdmission<'_>) -> io::Result<OriginalProducedEnd> {
    a.checkpoint().map_err(|error| a.take_operational_error().unwrap_or(error))?;
    let state = self.owner.0.as_ref().expect("actual output owner").state.lock().map_err(|_| io::ErrorKind::Other)?;
    if state.failed || !self.owner.admitted_by(a) { return Err(io::ErrorKind::InvalidInput.into()); }
    Ok(OriginalProducedEnd(OriginalDeliveryFrontier { owner: self.owner.clone(), end: state.offset }))
 }
 pub(super) fn prepare(&mut self,actual:Token<'static>,provider:&dyn SourceProvider,a:&SettingAdmission<'_>)->io::Result<OriginalPreparedOutputToken>{
  let result=self.prepare_inner(actual,provider,a);if result.is_err(){if let Ok(mut state)=self.owner.0.as_ref().unwrap().state.lock(){state.failed=true}}result
 }
 fn prepare_inner(&mut self,actual:Token<'static>,provider:&dyn SourceProvider,a:&SettingAdmission<'_>)->io::Result<OriginalPreparedOutputToken>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;if !self.owner.admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}let trailing=matches!(&actual.value,Value::Punct("{"|"}"|";"));let projection=project_native_token_using(&actual,provider,a)?;self.prepare_projection(Some(actual),projection,trailing,a)}
 /// Only the actual logical default-delimiter branch calls this. No fake
 /// macro Origin/frame/acquisition is supplied for its nonphysical location.
 pub(super) fn prepare_default_semicolon(&mut self,a:&SettingAdmission<'_>)->io::Result<OriginalPreparedOutputToken>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;if !self.owner.admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}let mut spelling=crate::macro_expansion::OriginalMacroText::new(a)?;spelling.push_str(";",a)?;let projection=OriginalNativeProjection{kind:dm_syntax::TokenKind::Punctuation,spelling,literal:None,adjacency:Adjacency::Punct};let result=self.prepare_projection(None,projection,true,a);if result.is_err(){if let Ok(mut state)=self.owner.0.as_ref().unwrap().state.lock(){state.failed=true}}result}
 fn prepare_projection(&mut self,actual:Option<Token<'static>>,projection:OriginalNativeProjection,trailing:bool,a:&SettingAdmission<'_>)->io::Result<OriginalPreparedOutputToken>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;if !self.owner.admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}
  let state=*self.owner.0.as_ref().unwrap().state.lock().map_err(|_|io::ErrorKind::Other)?;if state.failed{return Err(io::ErrorKind::InvalidInput.into())}
  let OriginalNativeProjection{kind,spelling,literal,adjacency}=projection;
  let leading=needs_separator(state.last,adjacency);
  let start=state.offset.checked_add(usize::from(leading)).ok_or(io::ErrorKind::OutOfMemory)?;let end=start.checked_add(spelling.as_str().len()).ok_or(io::ErrorKind::OutOfMemory)?;
  let frontier=end.checked_add(usize::from(trailing)).ok_or(io::ErrorKind::OutOfMemory)?;
  let mut line=state.line;for(at,byte)in spelling.as_str().bytes().enumerate(){if at%1024==0{a.checkpoint()?;}if byte==b'\n'{line=line.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;}}line=line.checked_add(usize::from(trailing)).ok_or(io::ErrorKind::OutOfMemory)?;
  a.checkpoint()?;let(text,credit)=spelling.into_parts();
  *self.owner.0.as_ref().unwrap().state.lock().map_err(|_|io::ErrorKind::Other)?=CursorState{last:Some(if trailing{Adjacency::Whitespace}else{adjacency}),offset:frontier,line,failed:false};
  Ok(OriginalPreparedOutputToken{token:dm_syntax::Token{kind,span:Span::new(start,end),text},literal,actual,leading,trailing,cover:Span::new(start,frontier),line:state.line,owner:self.owner.clone(),credit})
 }
}
impl OriginalPreparedOutputToken{
 pub(super) fn produced(&self)->OriginalProducedSpan<'_>{OriginalProducedSpan{token:self}}
 pub(super) fn actual(&self)->io::Result<&Token<'static>>{self.actual.as_ref().ok_or_else(||io::ErrorKind::InvalidData.into())}
 pub(super) fn token(&self)->SpanToken{self.produced().token()}
 pub(super) fn cover(&self)->Span{self.cover}
 pub(super) fn adopt(self,arena:&mut super::original_source_arena::OriginalSourceArena<'_>,primary:&mut dm_syntax::OriginalPrimaryDemand<'_,'_,'_>,owner:&OriginalOutputIdentity,a:&SettingAdmission<'_>)->io::Result<(super::original_final_output::OriginalEmittedToken,OriginalDeliveryFrontier)>{
  a.checkpoint()?;if !self.owner.same(owner)||!self.owner.admitted_by(a)||!a.matches_lease_domain(&self.credit)||self.credit.bytes()<self.token.text.capacity()||self.token.span.start.checked_sub(usize::from(self.leading))!=Some(arena.as_str().len()){return Err(io::Error::new(io::ErrorKind::InvalidInput,"prepared output does not continue this SAME actual receiver"))}
  if self.leading{arena.append(" ")?;}let span=arena.append(&self.token.text)?;if span!=self.token.span{return Err(io::ErrorKind::InvalidData.into())}let native=SpanToken{kind:self.token.kind,span};if self.actual.as_ref().is_some_and(|token|matches!(&token.value,Value::Punct(":"))){if self.token.text!=":"||self.literal.is_some(){return Err(io::ErrorKind::InvalidData.into())}primary.token_with_original_colon(native,self.actual.as_ref().unwrap().punctuation_close)?;}else if let Some(data)=self.literal{primary.token_with_original_literal(native,data)?;}else{primary.token(native)?;}
  if self.trailing{arena.append("\n")?;}if arena.as_str().len()!=self.cover.end{return Err(io::ErrorKind::InvalidData.into())}
  let delivery=OriginalDeliveryFrontier{owner:self.owner.clone(),end:self.cover.end};
  Ok((super::original_final_output::OriginalEmittedToken{token:self.token,credit:self.credit,punctuation_close:self.actual.as_ref().is_some_and(|t|t.punctuation_close),original:self.actual},delivery))
 }
}
