//! The SAME native input-annotation producer, retained across real token demand.
//! It owns only existing ParameterInputSyntax metadata, not another parser/model.
use crate::{ParameterInputSyntax,SettingAdmission,SettingRootLease,Span,TokenKind};
use std::{io,fmt,ops::Deref,sync::Arc,mem::size_of};
#[derive(Clone,Copy,Debug,Eq,PartialEq)]enum State{First,EmptyClose,EmptyDone,AfterIdentifier,Identifier}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum ParameterInputFlow{Consumed,ConsumedIdentifier,Boundary}
#[derive(Debug)]pub enum ParameterInputFailure{Syntax{at:Span,expected:&'static str,receipt:crate::OriginalInputFailure},Operational(io::Error)}
impl From<io::ErrorKind> for ParameterInputFailure{fn from(kind:io::ErrorKind)->Self{Self::Operational(kind.into())}}
impl From<io::Error> for ParameterInputFailure{fn from(error:io::Error)->Self{Self::Operational(error)}}
struct Payload{syntax:ParameterInputSyntax,credit:Option<SettingRootLease>}
pub struct RetainedParameterInput(Option<Arc<Payload>>);
impl Clone for RetainedParameterInput{fn clone(&self)->Self{Self(Some(Arc::clone(self.0.as_ref().expect("live native annotation"))))}}
impl Drop for RetainedParameterInput{fn drop(&mut self){if let Some(owner)=self.0.take(){if let Some(payload)=Arc::into_inner(owner){drop(payload)}}}}
impl Deref for RetainedParameterInput{type Target=ParameterInputSyntax;fn deref(&self)->&Self::Target{&self.0.as_ref().expect("live native annotation").syntax}}
impl fmt::Debug for RetainedParameterInput{fn fmt(&self,f:&mut fmt::Formatter<'_>)->fmt::Result{fmt::Debug::fmt(self.deref(),f)}}
impl PartialEq for RetainedParameterInput{fn eq(&self,other:&Self)->bool{self.deref()==other.deref()}}impl Eq for RetainedParameterInput{}
impl RetainedParameterInput{
 #[cfg(debug_assertions)]
 pub fn retained_bytes_for_trace(&self)->usize{
  self.0.as_ref().and_then(|payload|payload.credit.as_ref()).map_or(0,SettingRootLease::bytes)
 }
 pub fn is_admitted_by(&self,a:&SettingAdmission<'_>)->bool{self.0.as_ref().expect("live input").credit.as_ref().is_some_and(|credit|a.matches_lease_domain(credit))}
 pub fn same_owner(&self,other:&Self)->bool{Arc::ptr_eq(self.0.as_ref().unwrap(),other.0.as_ref().unwrap())}
 pub fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){let p=self.0.as_ref().expect("live input");let fixed=size_of::<Payload>()+2*size_of::<usize>();visit(Arc::as_ptr(p)as usize,fixed,fixed);if let ParameterInputSyntax::Union{identifiers,..}=&p.syntax{let bytes=identifiers.len()*size_of::<Span>();if bytes!=0{visit(identifiers.as_ptr()as usize,bytes,bytes)}}if let Some(credit)=&p.credit{credit.visit_counter_storage(|address,bytes|visit(address,bytes,bytes));}}
}
pub struct ParameterInputCursor<'a,'budget>{state:State,after_in:bool,span:Option<Span>,identifiers:Vec<Span>,failed:bool,a:Option<&'a SettingAdmission<'budget>>,credit:Option<SettingRootLease>}
impl<'a,'budget> ParameterInputCursor<'a,'budget>{
 pub fn new(a:&'a SettingAdmission<'budget>,after_in:bool)->io::Result<Self>{let credit=a.reserve(size_of::<Payload>()+2*size_of::<usize>()).map_err(|e|a.take_operational_error().unwrap_or(e))?;Ok(Self{state:State::First,after_in,span:None,identifiers:Vec::new(),failed:false,a:Some(a),credit:Some(credit)})}
 pub(crate) fn compatibility(after_in:bool)->Self{Self{state:State::First,after_in,span:None,identifiers:Vec::new(),failed:false,a:None,credit:None}}
 fn check(&mut self)->Result<(),ParameterInputFailure>{if self.failed{return Err(io::Error::new(io::ErrorKind::InvalidInput,"failed annotation cursor cannot resume").into())}if let Some(a)=self.a{a.checkpoint().map_err(|e|ParameterInputFailure::Operational(a.take_operational_error().unwrap_or(e)))?}Ok(())}
 fn identifier(&mut self,span:Span)->Result<(),ParameterInputFailure>{
  if self.identifiers.len()==self.identifiers.capacity(){let capacity=self.identifiers.capacity().max(2).checked_mul(2).ok_or(io::ErrorKind::OutOfMemory)?;let bound=capacity.checked_mul(4).ok_or(io::ErrorKind::OutOfMemory)?;
   if let(Some(a),Some(credit))=(self.a,self.credit.as_mut()){let target=bound.checked_mul(size_of::<Span>()).and_then(|bytes|bytes.checked_add(size_of::<Payload>()+2*size_of::<usize>())).ok_or(io::ErrorKind::OutOfMemory)?;if target>credit.bytes(){{let extra=target-credit.bytes();a.grow(credit,extra)}.map_err(|e|a.take_operational_error().unwrap_or(e))?}}
   self.identifiers.try_reserve_exact(capacity-self.identifiers.len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;if self.identifiers.capacity()>bound{return Err(io::ErrorKind::OutOfMemory.into())}
  }self.identifiers.push(span);Ok(())
 }
 fn feed_inner(&mut self,kind:TokenKind,span:Span,text:&str)->Result<ParameterInputFlow,ParameterInputFailure>{
  self.check()?;if matches!(kind,TokenKind::Whitespace|TokenKind::Newline|TokenKind::Comment){return Ok(ParameterInputFlow::Consumed)}
  if span.start>=span.end||self.span.is_some_and(|before|before.end>span.start){return Err(io::Error::new(io::ErrorKind::InvalidInput,"annotation occurrences overlap or reverse").into())}
  let wanted=match self.state{State::First=>crate::OriginalInputExpected::ParenOrIdentifier,State::EmptyClose=>crate::OriginalInputExpected::RightParen,_=>crate::OriginalInputExpected::Identifier};let bad=|expected|ParameterInputFailure::Syntax{at:span,expected,receipt:crate::OriginalInputFailure::new(Some(span),wanted)};
  let identifier=matches!(self.state,State::First|State::Identifier)&&kind==TokenKind::Ident;
  match self.state{
   State::First if kind==TokenKind::Punctuation&&text=="("=>self.state=State::EmptyClose,
   State::First|State::Identifier=>{if kind!=TokenKind::Ident{return Err(bad("identifier"))}self.identifier(span)?;self.state=State::AfterIdentifier;},
   State::EmptyClose=>{if kind!=TokenKind::Punctuation||text!=")"{return Err(bad("')'"))}self.state=State::EmptyDone;},
   State::AfterIdentifier if matches!(kind,TokenKind::Operator|TokenKind::Punctuation)&&text=="|"=>self.state=State::Identifier,
   State::AfterIdentifier|State::EmptyDone=>return Ok(ParameterInputFlow::Boundary),
  }
  self.span=Some(Span::new(self.span.map_or(span.start,|before|before.start),span.end));Ok(if identifier{ParameterInputFlow::ConsumedIdentifier}else{ParameterInputFlow::Consumed})
 }
 pub fn feed(&mut self,kind:TokenKind,span:Span,text:&str)->Result<ParameterInputFlow,ParameterInputFailure>{let result=self.feed_inner(kind,span,text);if result.is_err(){self.failed=true}result}
 pub(crate) fn boundary_error(&self)->&'static str{if self.state==State::EmptyDone{"formal annotation is not an original identifier union"}else{"formal annotation union separator unsupported"}}
 pub(crate) fn completed_empty(&self)->bool{self.state==State::EmptyDone}
 pub fn finish(mut self)->Result<RetainedParameterInput,ParameterInputFailure>{
  self.check()?;let span=self.span.ok_or(ParameterInputFailure::Syntax{at:Span::new(0,0),expected:"identifier or '()'",receipt:crate::OriginalInputFailure::new(None,crate::OriginalInputExpected::ParenOrIdentifier)})?;
  let syntax=match self.state{State::EmptyDone=>ParameterInputSyntax::EmptyParens{span,after_in:self.after_in},State::AfterIdentifier=>ParameterInputSyntax::Union{span,identifiers:std::mem::take(&mut self.identifiers).into_boxed_slice(),after_in:self.after_in},_=>return Err(ParameterInputFailure::Syntax{at:Span::new(span.end,span.end),expected:if self.state==State::EmptyClose{"')'"}else{"identifier"},receipt:crate::OriginalInputFailure::new(None,if self.state==State::EmptyClose{crate::OriginalInputExpected::RightParen}else{crate::OriginalInputExpected::Identifier})})};
  if let(Some(a),Some(credit))=(self.a,self.credit.as_mut()){let rows=match &syntax{ParameterInputSyntax::Union{identifiers,..}=>identifiers.len(),_=>0};let keep=rows.checked_mul(size_of::<Span>()).and_then(|n|n.checked_add(size_of::<Payload>()+2*size_of::<usize>())).ok_or(io::ErrorKind::OutOfMemory)?;let free=credit.bytes().checked_sub(keep).ok_or(io::ErrorKind::InvalidData)?;if free!=0{a.shrink(credit,free).map_err(|e|a.take_operational_error().unwrap_or(e))?}}
  Ok(RetainedParameterInput(Some(Arc::new(Payload{syntax,credit:self.credit.take()}))))
 }
}

#[cfg(test)]mod tests{
 use super::*;use std::sync::atomic::{Ordering};
 #[test]fn same_native_annotation_cursor_keeps_union_or_empty_metadata_once_until_last_alias(){
  for(text,wanted)in[("mob|obj|null, BAD(1)",3usize),("() in BAD(1)",0)]{let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut cursor=ParameterInputCursor::new(&a,false).unwrap();let mut found=None;
   for token in crate::lex(text).tokens{assert_ne!(token.text,"BAD","annotation producer requested a token after its actual boundary");match cursor.feed(token.kind,token.span,&token.text).unwrap(){ParameterInputFlow::Boundary=>{found=Some(token);break},_=>()}}
   assert!(found.is_some());let input=cursor.finish().unwrap();assert!(input.is_admitted_by(&a));let count=match &*input{ParameterInputSyntax::Union{identifiers,..}=>identifiers.len(),ParameterInputSyntax::EmptyParens{..}=>0};assert_eq!(count,wanted);let alias=input.clone();assert!(input.same_owner(&alias));drop(input);assert!(used.load(Ordering::Acquire)>crate::SettingChargeCounter::root_allocation_bytes());drop(alias);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
 }
 #[test]fn same_native_annotation_rejects_malformed_group_before_any_following_union_macro(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut cursor=ParameterInputCursor::new(&a,false).unwrap();let mut refused=false;
  for token in crate::lex("(mob|BAD(1))").tokens{assert_ne!(token.text,"BAD");if let Err(ParameterInputFailure::Syntax{at,expected,..})=cursor.feed(token.kind,token.span,&token.text){assert_eq!(at,Span::new(1,4));assert_eq!(expected,"')'");refused=true;break}}
  assert!(refused);assert!(matches!(cursor.feed(TokenKind::Ident,Span::new(5,8),"BAD"),Err(ParameterInputFailure::Operational(ref error))if error.kind()==io::ErrorKind::InvalidInput));assert!(cursor.finish().is_err());assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn same_native_annotation_quota_and_actual_io_fail_before_growth_and_poison_retries(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,crate::SettingChargeCounter::root_allocation_bytes() + (1),&||Ok(()));assert_eq!(ParameterInputCursor::new(&a,false).err().unwrap().kind(),io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let calls=std::cell::Cell::new(0);let poll=||{let call=calls.get()+1;calls.set(call);if call==2{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}};let a=SettingAdmission::new(&used,1<<20,&poll);let mut cursor=ParameterInputCursor::new(&a,false).unwrap();assert!(matches!(cursor.feed(TokenKind::Ident,Span::new(0,3),"mob"),Err(ParameterInputFailure::Operational(ref error))if error.raw_os_error()==Some(1450)));let count=calls.get();assert!(cursor.feed(TokenKind::Ident,Span::new(4,7),"obj").is_err());assert_eq!(calls.get(),count);drop(cursor);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
}
