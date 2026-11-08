//! The actual undrained Original output queue, shared by ordinary iteration
//! and conditional expansion. No token-history surrogate or parser/source grant.
use crate::macro_expansion::{OriginalMacroRows as Rows,OriginalMacroToken as Token,OriginalMacroValue as Value};
use dm_syntax::SettingAdmission;
use super::{original_output_trace::OriginalOutputTrace,macro_trace_view::OriginalMacroAuthor};
use std::sync::Arc;
use std::io;
struct Entry<'s>{token:Token<'s>,trace:OriginalOutputTrace}
pub(super) struct OriginalOutputQueue<'s>{rows:Rows<Option<Entry<'s>>>,head:usize,failed:bool,trace:OriginalOutputTrace}
impl<'s>OriginalOutputQueue<'s>{
 pub(super) fn new(a:&SettingAdmission<'_>)->io::Result<Self>{Ok(Self{rows:Rows::new(a)?,head:0,failed:false,trace:OriginalOutputTrace::default()})}
 pub(super) fn len(&self)->usize{self.rows.len()-self.head}
 pub(super) fn is_empty(&self)->bool{self.len()==0}
 pub(super) fn push(&mut self,token:Token<'s>,a:&SettingAdmission<'_>)->io::Result<()>{
  if self.failed{return Err(io::Error::new(io::ErrorKind::InvalidInput,"failed actual output queue cannot resume"))}
  // Reclaim consumed slots in place. Only live values move, never clone or
  // serialize. Rotation is allocation-free; retained capacity remains funded.
  if self.head!=0 && (self.head>=self.len() || self.rows.len()==self.rows.capacity()){
   let live=self.len();self.rows.as_mut_slice().rotate_left(self.head);self.rows.truncate(live);self.head=0;
  }
  let result=self.rows.push(Some(Entry{token,trace:self.trace.clone()}),a);if result.is_err(){self.failed=true}result
 }
 /// Produce the same one-row drain without writing a temporary queue row.
 /// The real push would keep this capacity after its immediate drain.
 pub(super) fn direct_using(&mut self,token:Token<'s>,a:&SettingAdmission<'_>)->io::Result<(Token<'s>,OriginalOutputTrace)>{
  if self.failed{return Err(io::Error::new(io::ErrorKind::InvalidInput,"failed actual output queue cannot resume"))}
  if self.head!=0||self.rows.len()!=0{return Err(io::ErrorKind::InvalidInput.into())}
  if let Err(error)=self.rows.ensure(1,a){self.failed=true;return Err(error)}
  Ok((token,self.trace.clone()))
 }
 pub(super) fn pop(&mut self)->io::Result<Option<Token<'s>>>{self.pop_with_trace().map(|actual|actual.map(|(token,_)|token))}
 pub(super) fn pop_with_trace(&mut self)->io::Result<Option<(Token<'s>,OriginalOutputTrace)>>{
  if self.failed{return Err(io::Error::new(io::ErrorKind::InvalidInput,"failed actual output queue cannot be drained as successful output"))}
  if self.is_empty(){return Ok(None)}let token=self.rows.as_mut_slice()[self.head].take().ok_or(io::ErrorKind::InvalidData)?;self.head+=1;
  if self.head==self.rows.len(){self.rows.truncate(0);self.head=0;}Ok(Some((token.token,token.trace)))
 }
 pub(super) fn trace_pushed_using(&mut self,name:&str,origin:crate::macro_expansion::OriginalMacroOrigin,depth:usize,definition:Option<crate::macro_expansion::OriginalMacroOrigin>,projected:Option<&Arc<OriginalMacroAuthor>>,a:&SettingAdmission<'_>)->io::Result<()>{
  if self.failed{return Err(io::ErrorKind::InvalidInput.into())}let result=(||{self.rows.ensure(0,a)?;self.trace=self.trace.pushed_with_definition_using(name,origin,depth,definition,projected,a)?;Ok(())})();if result.is_err(){self.failed=true}result
 }
 pub(super) fn trace_popped_using(&mut self,depth:usize,a:&SettingAdmission<'_>)->io::Result<()>{
  if self.failed{return Err(io::ErrorKind::InvalidInput.into())}let result=(||{self.rows.ensure(0,a)?;self.trace=self.trace.popped_using(depth,a)?;Ok(())})();if result.is_err(){self.failed=true}result
 }
 /// The old condition parser drains all unconsumed values after its result.
 pub(super) fn discard_values(&mut self){self.rows.truncate(0);self.head=0;}
 /// This observes exactly the SAME live output queue which the caller drains.
 /// Dynamic macros have already expanded before Cursor asks this question.
 pub(super) fn preserves_defined_operand(&self)->bool{
  if self.failed||self.len()<2{return false}let live=&self.rows.as_slice()[self.head..];
  matches!((&live[live.len()-2],&live[live.len()-1]),
   (Some(Entry{token:Token{value:Value::Ident{spelling,..},..},..}),Some(Entry{token:Token{value:Value::Punct("("),..},..}))if spelling.get()=="defined")
 }
 pub(super) fn visit_allocation(&self,visit:impl FnMut(usize,usize)){self.rows.visit_allocation(visit)}
}
#[cfg(test)]mod tests{
 use super::*;use crate::macro_expansion::{OriginalMacroTextValue as Text,OriginalMacroOrigin as Origin};
 use std::sync::{Arc, atomic::{Ordering}};
 fn token(value:Value<'static>)->Token<'static>{Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,raw_spelling:None,origin:Origin{physical:dm_syntax::Span::default(),line:0,byte_column:None,occurrence:0,invocation:false},value}}
 fn ident(name:&'static str)->Token<'static>{token(Value::Ident{spelling:Text::Borrowed(name),whitespace:false})}
 #[test]fn defined_guard_uses_only_actual_undrained_queue_and_compaction_keeps_exact_token_order(){
  let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut q=OriginalOutputQueue::new(&a).unwrap();
  q.push(ident("before"),&a).unwrap();q.push(ident("defined"),&a).unwrap();q.push(token(Value::Punct("(")),&a).unwrap();assert!(q.preserves_defined_operand());
  assert!(matches!(q.pop().unwrap(),Some(Token{value:Value::Ident{spelling,..},..})if spelling.get()=="before"));assert!(q.preserves_defined_operand());
  assert!(matches!(q.pop().unwrap(),Some(Token{value:Value::Ident{spelling,..},..})if spelling.get()=="defined"));assert!(!q.preserves_defined_operand());
  q.push(ident("after"),&a).unwrap();assert!(matches!(q.pop().unwrap(),Some(Token{value:Value::Punct("("),..})));assert!(matches!(q.pop().unwrap(),Some(Token{value:Value::Ident{spelling,..},..})if spelling.get()=="after"));assert!(q.pop().unwrap().is_none());
  for _ in 0..64{q.push(ident("defined"),&a).unwrap();q.push(token(Value::Punct("(")),&a).unwrap();assert!(q.preserves_defined_operand());q.pop().unwrap();assert!(!q.preserves_defined_operand());q.pop().unwrap();}
  assert!(q.rows.capacity()<=4);drop(q);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]
 fn direct_single_row_preserves_push_capacity_and_first_checkpoint_error() {
  fn run(direct: bool, fault: Option<usize>) -> (Option<i32>, usize, usize) {
   let used = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
   let observed = std::cell::Cell::new(0usize);
   let enabled = std::cell::Cell::new(false);
   let checkpoint = || {
    if enabled.get() {
     observed.set(observed.get() + 1);
     if fault == Some(observed.get()) { return Err(io::Error::from_raw_os_error(1450)); }
    }
    Ok(())
   };
   let a = SettingAdmission::new(&used, 1 << 20, &checkpoint);
   let mut queue = OriginalOutputQueue::new(&a).unwrap();
   let origin=Origin{physical:dm_syntax::Span::new(0,1),line:1,byte_column:Some(1),occurrence:0,invocation:true};
   queue.trace_pushed_using("LIVE",origin,1,None,None,&a).unwrap();
   enabled.set(true);
   let row: io::Result<_> = (|| {
    if direct {
     let row = queue.direct_using(ident("issued"), &a)?;
     // This is the outer pump's post-push checkpoint.
     a.checkpoint().map_err(|error|a.take_operational_error().unwrap_or(error))?;
     Ok(row)
    } else {
     queue.push(ident("issued"), &a)?;
     a.checkpoint().map_err(|error|a.take_operational_error().unwrap_or(error))?;
     Ok(queue.pop_with_trace()?.unwrap())
    }
   })();
   enabled.set(false);
   let kind = match row {
    Ok((token,trace)) => {
     assert!(matches!(token.value,Value::Ident{spelling,..}if spelling.get()=="issued"));
     let mut seen = 0;
     trace.visit_inner_to_outer_using(&a, |frame| { assert_eq!(frame.name,"LIVE"); seen+=1; Ok(()) }).unwrap();
     assert_eq!(seen,1);
     assert!(queue.is_empty());
     None
    }
    Err(error) => error.raw_os_error(),
   };
   (kind, observed.get(), queue.rows.capacity())
  }
  let old = run(false, None);
  assert_eq!(old, run(true, None));
  for checkpoint in 1..=old.1 {
   let queued = run(false, Some(checkpoint));
   assert_eq!(queued.0,Some(1450));
   assert_eq!(queued,run(true,Some(checkpoint)));
  }
 }

 #[test]fn queue_retains_first_real_io_and_cannot_be_resumed_after_failed_append(){
  let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let fail=std::cell::Cell::new(false);let checkpoint=||if fail.get(){Err(io::Error::from_raw_os_error(1450))}else{Ok(())};let a=SettingAdmission::new(&used,1<<20,&checkpoint);let mut q=OriginalOutputQueue::new(&a).unwrap();
  q.push(ident("defined"),&a).unwrap();fail.set(true);assert_eq!(q.push(token(Value::Punct("(")),&a).unwrap_err().raw_os_error(),Some(1450));fail.set(false);assert!(q.push(ident("retry"),&a).is_err());assert!(q.pop().is_err());assert!(!q.preserves_defined_operand());drop(q);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]fn actual_delayed_queue_drain_retains_each_tokens_lineage_after_all_live_frames_pop(){
  let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,4<<20,&||Ok(()));let mut q=OriginalOutputQueue::new(&a).unwrap();let origin=Origin{physical:dm_syntax::Span::new(0,1),line:1,byte_column:Some(1),occurrence:0,invocation:true};q.trace_pushed_using("OUTER",origin,1,None,None,&a).unwrap();q.push(ident("first"),&a).unwrap();q.trace_pushed_using("INNER",origin,2,Some(origin),None,&a).unwrap();q.push(ident("second"),&a).unwrap();q.trace_popped_using(1,&a).unwrap();q.trace_popped_using(0,&a).unwrap();assert_eq!(q.trace.depth(),0);
  let(first,outer)=q.pop_with_trace().unwrap().unwrap();let(second,inner)=q.pop_with_trace().unwrap().unwrap();assert!(matches!(first.value,Value::Ident{spelling,..}if spelling.get()=="first"));assert!(matches!(second.value,Value::Ident{spelling,..}if spelling.get()=="second"));let mut names=Vec::new();outer.visit_inner_to_outer_using(&a,|row|{names.push(row.name.to_owned());Ok(())}).unwrap();assert_eq!(names,["OUTER"]);names.clear();inner.visit_inner_to_outer_using(&a,|row|{names.push(row.name.to_owned());Ok(())}).unwrap();assert_eq!(names,["INNER","OUTER"]);drop((q,outer));assert!(used.load(Ordering::Acquire)>dm_syntax::SettingChargeCounter::root_allocation_bytes(),"delayed snapshot owns its actual lineage storage");drop(inner);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }

}
