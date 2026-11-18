//! Optional borrowed admission for native compiler regex operations.
//! Original constructors and algorithms do not install a hook.
//! A refusal is an opaque transport marker; the caller retains the actual IO.
use alloc::{string::String,vec::Vec};
use core::fmt;

/// Opaque refusal; the real resource owner retains its original failure.
#[derive(Clone,Copy,Debug,Eq,PartialEq)]
pub struct Refused;
impl fmt::Display for Refused{fn fmt(&self,f:&mut fmt::Formatter<'_>)->fmt::Result{f.write_str("native regex allocation admission refused")}}
/// The real caller owns the budget, original deadline and first-error latch.
/// This trait owns no counter or cache and cannot invent an allocation grant.
pub trait Admission:Send+Sync{
 /// Uses the same caller-owned admission and preserves its original failure.
 fn checkpoint(&self)->Result<(),Refused>;
 /// Uses the same caller-owned admission and preserves its original failure.
 fn reserve(&self,bytes:usize)->Result<(),Refused>;
 /// Uses the same caller-owned admission and preserves its original failure.
 fn overflow(&self)->Refused;
 /// Uses the same caller-owned admission and preserves its original failure.
 fn allocation_failed(&self)->Refused;
 /// Optional same-owner successful compiler-phase settlement. The default
 /// keeps all reservations conservatively; it grants no refund authority.
 fn begin_retained_phase(&self)->Result<Option<u64>,Refused>{Ok(None)}
 /// Settle only a token issued by this actual owner, after scratch teardown.
 fn settle_retained_phase(&self,_serial:u64,_retained:usize)->Result<(),Refused>{Err(self.allocation_failed())}
 /// Same active token, after an earlier successful compiler phase has retired
 /// all owners except this exact retained product. The token remains active.
 fn checkpoint_retained_phase(&self,_serial:u64,_retained:usize)->Result<(),Refused>{Err(self.allocation_failed())}
 /// Optional next named checkpoint after parsed HIR. Default keeps every
 /// byte conservatively for older resource owners; it authorizes no refund.
 fn checkpoint_retained_builder_phase(&self,_serial:u64,_retained:usize)->Result<(),Refused>{Ok(())}


 /// A failed phase retires its token but never refunds an escaping failure.
 fn abandon_retained_phase(&self,_serial:u64){}
 /// One composite producer may contain sequential ordinary compiler phases.
 /// Default owners keep conservative accounting and issue no new token.
 fn begin_retained_composite_phase(&self)->Result<Option<u64>,Refused>{Ok(None)}
 /// Settle after all child phases and composite temporary owners retired.
 fn settle_retained_composite_phase(&self,_serial:u64,_retained:usize)->Result<(),Refused>{Err(self.allocation_failed())}
 /// Failure abandons conservatively, never releasing potentially live data.
 fn abandon_retained_composite_phase(&self,_serial:u64){}


}
/// Shared borrow of the caller's actual allocation lender.
pub type Shared<'a>=alloc::sync::Arc<dyn Admission+'a>;
/// Optional admission used only by the explicitly checked native ports.
#[derive(Clone,Default)]
pub struct Hook<'a>(pub Option<Shared<'a>>);
impl fmt::Debug for Hook<'_>{fn fmt(&self,f:&mut fmt::Formatter<'_>)->fmt::Result{f.debug_tuple("NativeAdmission").field(&self.0.is_some()).finish()}}
/// Non-cloneable loan from one exact Hook owner. No scalar can forge this
/// wrapper; successful settlement consumes it. Drop only abandons the token.
pub struct RetainedPhase<'a>{owner:Hook<'a>,serial:Option<u64>,checkpointed:bool,builder_checkpointed:bool}
impl<'a> RetainedPhase<'a>{
 /// Retire only physically dead earlier-stage temporaries, keeping this SAME
 /// opaque phase's original baseline and active identity for final settlement.
 pub fn checkpoint(&mut self,hook:&Hook<'a>,retained:usize)->Result<(),Refused>{
  let same=match(&self.owner.0,&hook.0){(Some(a),Some(b))=>alloc::sync::Arc::ptr_eq(a,b),(None,None)=>true,_=>false};
  if !same||self.checkpointed{return Err(hook.allocation_failed())}
  if let Some(serial)=self.serial{self.owner.0.as_ref().ok_or_else(||hook.allocation_failed())?.checkpoint_retained_phase(serial,retained)?;}
  self.checkpointed=true;Ok(())
 }
 /// Freeze exactly once after parsed HIR and physical compiler-memo teardown.
 /// The caller keeps actual HIR plus complete frozen-builder ownership funded.
 pub fn checkpoint_builder(&mut self,hook:&Hook<'a>,retained:usize)->Result<(),Refused>{
  let same=match(&self.owner.0,&hook.0){(Some(a),Some(b))=>alloc::sync::Arc::ptr_eq(a,b),(None,None)=>true,_=>false};
  if !same||!self.checkpointed||self.builder_checkpointed{return Err(hook.allocation_failed())}
  if let Some(serial)=self.serial{self.owner.0.as_ref().ok_or_else(||hook.allocation_failed())?.checkpoint_retained_builder_phase(serial,retained)?;}
  self.builder_checkpointed=true;Ok(())
 }
 /// Called only after the compiler closure and its temporary owners dropped.
 pub fn settle(mut self,hook:&Hook<'a>,retained:usize)->Result<(),Refused>{
  let same=match(&self.owner.0,&hook.0){(Some(a),Some(b))=>alloc::sync::Arc::ptr_eq(a,b),(None,None)=>true,_=>false};
  if !same{return Err(hook.allocation_failed())}
  if let Some(serial)=self.serial{self.owner.0.as_ref().ok_or_else(||hook.allocation_failed())?.settle_retained_phase(serial,retained)?;self.serial=None;}
  Ok(())
 }
}
impl Drop for RetainedPhase<'_>{fn drop(&mut self){if let(Some(owner),Some(serial))=(&self.owner.0,self.serial){owner.abandon_retained_phase(serial)}}}
/// Non-cloneable SAME-owner composite coordinate, not a second budget.
/// It can enclose ordinary sequential phases but cannot settle a live child.
pub struct RetainedCompositePhase<'a>{owner:Hook<'a>,serial:Option<u64>}
impl<'a> RetainedCompositePhase<'a>{
 /// Caller has physically retired all temporary owners except this product.
 pub fn settle(mut self,hook:&Hook<'a>,retained:usize)->Result<(),Refused>{
  let same=match(&self.owner.0,&hook.0){(Some(a),Some(b))=>alloc::sync::Arc::ptr_eq(a,b),(None,None)=>true,_=>false};
  if !same{return Err(hook.allocation_failed())}
  if let Some(serial)=self.serial{self.owner.0.as_ref().ok_or_else(||hook.allocation_failed())?.settle_retained_composite_phase(serial,retained)?;self.serial=None;}Ok(())
 }
}
impl Drop for RetainedCompositePhase<'_>{fn drop(&mut self){if let(Some(owner),Some(serial))=(&self.owner.0,self.serial){owner.abandon_retained_composite_phase(serial)}}}
impl<'a> Hook<'a>{
 /// Begin one composite producer on this same lender, without a new allowance.
 pub fn retained_composite_phase(&self)->Result<RetainedCompositePhase<'a>,Refused>{
  self.checkpoint()?;let serial=match &self.0{Some(owner)=>owner.begin_retained_composite_phase()?,None=>None};Ok(RetainedCompositePhase{owner:self.clone(),serial})
 }

 /// Start a same-owner retained compiler phase; this allocates no new owner.
 pub fn retained_phase(&self)->Result<RetainedPhase<'a>,Refused>{
  self.checkpoint()?;let serial=match &self.0{Some(owner)=>owner.begin_retained_phase()?,None=>None};
  Ok(RetainedPhase{owner:self.clone(),serial,checkpointed:false,builder_checkpointed:false})
 }

 /// Uses the same caller-owned admission and preserves its original failure.
 pub fn active(&self)->bool{self.0.is_some()}
 /// Refuse a checked native entry without an actual borrowed lender.
 pub fn require_active(&self)->Result<(),Refused>{if self.active(){Ok(())}else{Err(self.allocation_failed())}}
 /// Uses the same caller-owned admission and preserves its original failure.
 pub fn overflow(&self)->Refused{self.0.as_ref().map_or(Refused,|a|a.overflow())}
 /// Uses the same caller-owned admission and preserves its original failure.
 pub fn allocation_failed(&self)->Refused{self.0.as_ref().map_or(Refused,|a|a.allocation_failed())}
 /// Uses the same caller-owned admission and preserves its original failure.
 pub fn checkpoint(&self)->Result<(),Refused>{if let Some(a)=&self.0{a.checkpoint()}else{Ok(())}}
 /// Uses the same caller-owned admission and preserves its original failure.
 pub fn reserve(&self,bytes:impl FnOnce()->Option<usize>)->Result<(),Refused>{
  let Some(a)=&self.0 else{return Ok(())};a.checkpoint()?;a.reserve(bytes().ok_or_else(||a.overflow())?)
 }
 /// Fund the full new backing while the old backing remains live. The caller
 /// publishes a row only after this returns. No posthoc memory estimate.
 /// Uses the same caller-owned admission and preserves its original failure.
 pub fn room<T>(&self,rows:&mut Vec<T>,additional:usize)->Result<(),Refused>{
  let Some(a)=&self.0 else{return Ok(())};a.checkpoint()?;
  let need=rows.len().checked_add(additional).ok_or_else(||a.overflow())?;
  if need<=rows.capacity(){return Ok(())}
  let next=need.max(rows.capacity().checked_mul(2).ok_or_else(||a.overflow())?).max(4);
  a.reserve(next.checked_mul(core::mem::size_of::<T>()).and_then(|n|n.checked_add(64)).ok_or_else(||a.overflow())?)?;
  rows.try_reserve_exact(next-rows.len()).map_err(|_|a.allocation_failed())?;
  if rows.capacity()>next{return Err(a.allocation_failed())}Ok(())
 }
 /// Uses the same caller-owned admission and preserves its original failure.
 pub fn push<T>(&self,rows:&mut Vec<T>,value:T)->Result<(),Refused>{self.room(rows,1)?;rows.push(value);Ok(())}
 /// Uses the same caller-owned admission and preserves its original failure.
 pub fn resize<T:Clone>(&self,rows:&mut Vec<T>,length:usize,value:T)->Result<(),Refused>{
  self.room(rows,length.saturating_sub(rows.len()))?;rows.resize(length,value);Ok(())
 }
 /// Uses the same caller-owned admission and preserves its original failure.
 pub fn string_room(&self,text:&mut String,additional:usize)->Result<(),Refused>{
  let Some(a)=&self.0 else{return Ok(())};a.checkpoint()?;
  let need=text.len().checked_add(additional).ok_or_else(||a.overflow())?;
  if need>text.capacity(){let next=need.max(text.capacity().checked_mul(2).ok_or_else(||a.overflow())?).max(64);
   a.reserve(next.checked_add(64).ok_or_else(||a.overflow())?)?;
   text.try_reserve_exact(next-text.len()).map_err(|_|a.allocation_failed())?;
   if text.capacity()>next{return Err(a.allocation_failed())}
  }
  Ok(())
 }
 /// Admit actual String backing before appending borrowed text.
 pub fn append(&self,text:&mut String,value:&str)->Result<(),Refused>{
  self.string_room(text,value.len())?;text.push_str(value);Ok(())
 }
 /// Uses the same caller-owned admission and preserves its original failure.
 pub fn text(&self,value:&str)->Result<String,Refused>{let mut text=String::new();self.append(&mut text,value)?;Ok(text)}
 /// Format into the same controlled String rather than allocating a temporary
 /// format! buffer before the caller's real admission can observe it.
 /// Uses the same caller-owned admission and preserves its original failure.
 pub fn format(&self,args:fmt::Arguments<'_>)->Result<String,Refused>{
  struct Output<'h,'a>{hook:&'h Hook<'a>,text:String,first:Option<Refused>}
  impl fmt::Write for Output<'_,'_>{
   fn write_str(&mut self,value:&str)->fmt::Result{
    if self.first.is_some(){return Err(fmt::Error)}
    if let Err(actual)=self.hook.append(&mut self.text,value){self.first=Some(actual);return Err(fmt::Error)}Ok(())
   }
  }
  let mut output=Output{hook:self,text:String::new(),first:None};
  let result=fmt::write(&mut output,args);
  if let Some(first)=output.first{return Err(first)}
  if result.is_err(){return Err(self.allocation_failed())}Ok(output.text)
 }
}
#[cfg(test)]mod tests{
 use super::*;use core::sync::atomic::{AtomicUsize,Ordering};
 struct Probe{left:AtomicUsize,polls:AtomicUsize,fail:usize}
 impl Admission for Probe{
  /// Uses the same caller-owned admission and preserves its original failure.
  fn checkpoint(&self)->Result<(),Refused>{if self.polls.fetch_add(1,Ordering::SeqCst)+1==self.fail{Err(Refused)}else{Ok(())}}
  /// Uses the same caller-owned admission and preserves its original failure.
  fn reserve(&self,n:usize)->Result<(),Refused>{self.left.fetch_update(Ordering::SeqCst,Ordering::SeqCst,|v|v.checked_sub(n)).map(|_|()).map_err(|_|Refused)}
  /// Uses the same caller-owned admission and preserves its original failure.
  fn overflow(&self)->Refused{Refused}fn allocation_failed(&self)->Refused{Refused}
 }
 #[test]fn actual_denial_precedes_backing_growth_and_legacy_does_not_poll(){
  let h=Hook(Some(alloc::sync::Arc::new(Probe{left:AtomicUsize::new(1),polls:AtomicUsize::new(0),fail:usize::MAX})));let mut rows=Vec::<u64>::new();assert_eq!(h.push(&mut rows,1),Err(Refused));assert_eq!(rows.capacity(),0);
  let mut legacy=Vec::new();Hook::default().push(&mut legacy,7).unwrap();assert_eq!(legacy,[7]);
 }
}
