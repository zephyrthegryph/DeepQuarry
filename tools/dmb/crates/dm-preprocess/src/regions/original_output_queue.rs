//! The actual undrained Original output queue, shared by ordinary iteration
//! and conditional expansion. No token-history surrogate or parser/source grant.
use crate::macro_expansion::{OriginalMacroRows as Rows,OriginalMacroToken as Token,OriginalMacroValue as Value};
use dm_syntax::SettingAdmission;
use std::io;
pub(super) struct OriginalOutputQueue<'s>{rows:Rows<Option<Token<'s>>>,head:usize,failed:bool}
impl<'s>OriginalOutputQueue<'s>{
 pub(super) fn new(a:&SettingAdmission<'_>)->io::Result<Self>{Ok(Self{rows:Rows::new(a)?,head:0,failed:false})}
 pub(super) fn len(&self)->usize{self.rows.len()-self.head}
 pub(super) fn is_empty(&self)->bool{self.len()==0}
 pub(super) fn push(&mut self,token:Token<'s>,a:&SettingAdmission<'_>)->io::Result<()>{
  if self.failed{return Err(io::Error::new(io::ErrorKind::InvalidInput,"failed actual output queue cannot resume"))}
  // Reclaim consumed slots in place. Only live values move, never clone or
  // serialize. Rotation is allocation-free; retained capacity remains funded.
  if self.head!=0 && (self.head>=self.len() || self.rows.len()==self.rows.capacity()){
   let live=self.len();self.rows.as_mut_slice().rotate_left(self.head);self.rows.truncate(live);self.head=0;
  }
  let result=self.rows.push(Some(token),a);if result.is_err(){self.failed=true}result
 }
 pub(super) fn pop(&mut self)->io::Result<Option<Token<'s>>>{
  if self.failed{return Err(io::Error::new(io::ErrorKind::InvalidInput,"failed actual output queue cannot be drained as successful output"))}
  if self.is_empty(){return Ok(None)}let token=self.rows.as_mut_slice()[self.head].take().ok_or(io::ErrorKind::InvalidData)?;self.head+=1;
  if self.head==self.rows.len(){self.rows.truncate(0);self.head=0;}Ok(Some(token))
 }
 /// The old condition parser drains all unconsumed values after its result.
 pub(super) fn discard_values(&mut self){self.rows.truncate(0);self.head=0;}
 /// This observes exactly the SAME live output queue which the caller drains.
 /// Dynamic macros have already expanded before Cursor asks this question.
 pub(super) fn preserves_defined_operand(&self)->bool{
  if self.failed||self.len()<2{return false}let live=&self.rows.as_slice()[self.head..];
  matches!((&live[live.len()-2],&live[live.len()-1]),
   (Some(Token{value:Value::Ident{spelling,..},..}),Some(Token{value:Value::Punct("("),..}))if spelling.get()=="defined")
 }
 pub(super) fn visit_allocation(&self,visit:impl FnMut(usize,usize)){self.rows.visit_allocation(visit)}
}
#[cfg(test)]mod tests{
 use super::*;use crate::macro_expansion::{OriginalMacroTextValue as Text,OriginalMacroOrigin as Origin};
 use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 fn token(value:Value<'static>)->Token<'static>{Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,raw_spelling:None,origin:Origin{physical:dm_syntax::Span::default(),line:0,byte_column:None,occurrence:0,invocation:false},value}}
 fn ident(name:&'static str)->Token<'static>{token(Value::Ident{spelling:Text::Borrowed(name),whitespace:false})}
 #[test]fn defined_guard_uses_only_actual_undrained_queue_and_compaction_keeps_exact_token_order(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut q=OriginalOutputQueue::new(&a).unwrap();
  q.push(ident("before"),&a).unwrap();q.push(ident("defined"),&a).unwrap();q.push(token(Value::Punct("(")),&a).unwrap();assert!(q.preserves_defined_operand());
  assert!(matches!(q.pop().unwrap(),Some(Token{value:Value::Ident{spelling,..},..})if spelling.get()=="before"));assert!(q.preserves_defined_operand());
  assert!(matches!(q.pop().unwrap(),Some(Token{value:Value::Ident{spelling,..},..})if spelling.get()=="defined"));assert!(!q.preserves_defined_operand());
  q.push(ident("after"),&a).unwrap();assert!(matches!(q.pop().unwrap(),Some(Token{value:Value::Punct("("),..})));assert!(matches!(q.pop().unwrap(),Some(Token{value:Value::Ident{spelling,..},..})if spelling.get()=="after"));assert!(q.pop().unwrap().is_none());
  for _ in 0..64{q.push(ident("defined"),&a).unwrap();q.push(token(Value::Punct("(")),&a).unwrap();assert!(q.preserves_defined_operand());q.pop().unwrap();assert!(!q.preserves_defined_operand());q.pop().unwrap();}
  assert!(q.rows.capacity()<=4);drop(q);assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn queue_retains_first_real_io_and_cannot_be_resumed_after_failed_append(){
  let used=Arc::new(AtomicUsize::new(0));let fail=std::cell::Cell::new(false);let checkpoint=||if fail.get(){Err(io::Error::from_raw_os_error(1450))}else{Ok(())};let a=SettingAdmission::new(&used,1<<20,&checkpoint);let mut q=OriginalOutputQueue::new(&a).unwrap();
  q.push(ident("defined"),&a).unwrap();fail.set(true);assert_eq!(q.push(token(Value::Punct("(")),&a).unwrap_err().raw_os_error(),Some(1450));fail.set(false);assert!(q.push(ident("retry"),&a).is_err());assert!(q.pop().is_err());assert!(!q.preserves_defined_operand());drop(q);assert_eq!(used.load(Ordering::Acquire),0);
 }
}
