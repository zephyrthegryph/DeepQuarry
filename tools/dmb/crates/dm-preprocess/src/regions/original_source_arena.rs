//! One transformed source allocation, charged to the EXISTING shared source
//! family by the actual host. Does not issue source/EOF/model authority.
use crate::{SourceText,source_text_reservation::ReservedSourceBuffer,source_arena_credit::{SourceArenaCredit,SourceArenaControlCredit,SourceArenaWork}};
use std::{alloc::{alloc,Layout},io,ptr::NonNull};
pub(super) struct OriginalSourceArena<'a>{
 // Drop physical allocation BEFORE payload credit; metadata credit last.
 text:String,reserved:Option<ReservedSourceBuffer>,payload:SourceArenaCredit,control:SourceArenaControlCredit,failed:bool,work:&'a dyn SourceArenaWork,
}
impl<'a>OriginalSourceArena<'a>{
 pub(super) fn new(work:&'a dyn SourceArenaWork)->io::Result<Self>{
  work.checkpoint()?;
  let payload=work.reserve(0)?;
  let control=work.reserve(SourceText::source_arena_control_bytes()?)?.into_control();
  let reserved=work.transformed_source_address_limit().map(ReservedSourceBuffer::new).transpose()?;
  Ok(Self{text:String::new(),reserved,payload,control,failed:false,work})
 }
 pub(super) fn as_str(&self)->&str{
  self.reserved.as_ref().map_or(self.text.as_str(),ReservedSourceBuffer::as_str)
 }
 pub(super) fn append(&mut self,text:&str)->io::Result<dm_syntax::Span>{
  if self.failed{return Err(io::Error::new(io::ErrorKind::InvalidInput,"failed source arena cannot resume"))}let result=self.append_inner(text);if result.is_err(){self.failed=true}result
 }
 fn append_inner(&mut self,text:&str)->io::Result<dm_syntax::Span>{
  self.work.checkpoint()?;
  let start=self.as_str().len();
  let required=start.checked_add(text.len()).ok_or(io::ErrorKind::OutOfMemory)?;
  if let Some(reserved)=&mut self.reserved{
   if required>reserved.capacity(){
    let target=reserved.capacity_for(required)?;
    // This platform operation only backs previously inaccessible addresses.
    // It cannot move the prefix or temporarily duplicate its allocation.
    self.work.grow(&mut self.payload,target-reserved.capacity())?;
    reserved.commit(target)?;
   }
   reserved.push_str(text)?;
   return Ok(dm_syntax::Span::new(start,required));
  }
  if required>self.text.capacity(){
   let preferred=self.text.capacity().checked_add(self.text.capacity()/2).ok_or(io::ErrorKind::OutOfMemory)?.max(4096);let capacity=required.max(preferred);let layout=Layout::array::<u8>(capacity).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;
   // Existing old allocation remains funded. Reserve the exact new allocation
   // before asking the global allocator; unknown Vec growth is not a proof.
   self.work.grow(&mut self.payload,capacity)?;
   // SAFETY: exact Global allocation for u8 matches Vec's global allocator and
   // documented from_raw_parts layout. Null is handled before construction;
   // zero length contains no uninitialized element. Only existing valid UTF8
   // is copied before restoring String. Capacity is known, not guessed.
   let pointer=NonNull::new(unsafe{alloc(layout)}).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
   let bytes=unsafe{Vec::from_raw_parts(pointer.as_ptr(),0,capacity)};let mut next=unsafe{String::from_utf8_unchecked(bytes)};next.push_str(&self.text);std::mem::swap(&mut self.text,&mut next);drop(next);
   // The old physical String is gone before any reservation is refunded. A
   // fallible shrink never masks an earlier allocator failure: allocation
   // failure exits above and holds its funded peak until this owner drops.
   let release=self.payload.reserved_bytes().checked_sub(self.text.capacity()).ok_or(io::ErrorKind::InvalidData)?;if release!=0{self.work.shrink(&mut self.payload,release)?;}
  }
  self.text.push_str(text);Ok(dm_syntax::Span::new(start,required))
 }
 pub(super) fn finish(self)->io::Result<SourceText>{
  if self.failed{return Err(io::Error::new(io::ErrorKind::InvalidInput,"failed source arena cannot be sealed"))}
  self.work.checkpoint()?;
  match self.reserved{
   Some(reserved)=>SourceText::from_reserved_source_arena(reserved,self.payload,self.control),
   None=>SourceText::from_source_arena(self.text,self.payload,self.control),
  }
 }
}

#[cfg(test)]mod tests{
 use super::*;use crate::source_arena_credit::SourceArenaCreditOwner;use std::{any::Any,sync::{Arc,atomic::{AtomicUsize,AtomicBool,Ordering}}};
 #[derive(Default)]struct State{live:AtomicUsize,peak:AtomicUsize,fail:AtomicBool,reserved:AtomicBool,limit:AtomicUsize}
 struct Credit{bytes:AtomicUsize,state:Arc<State>}
 impl Drop for Credit{fn drop(&mut self){self.state.live.fetch_sub(self.bytes.load(Ordering::Acquire),Ordering::AcqRel);}}
 impl SourceArenaCreditOwner for Credit{fn as_any(&self)->&dyn Any{self}fn reserved_bytes(&self)->usize{self.bytes.load(Ordering::Acquire)}fn visit_storage(&self,_:&mut dyn FnMut(usize,usize)){}}
 struct Work(Arc<State>);
 impl Work{fn charge(&self,bytes:usize){let n=self.0.live.fetch_add(bytes,Ordering::AcqRel)+bytes;self.0.peak.fetch_max(n,Ordering::AcqRel);}fn actual<'a>(&self,c:&'a SourceArenaCredit)->io::Result<&'a Credit>{let c=c.owner().as_any().downcast_ref::<Credit>().ok_or(io::ErrorKind::InvalidInput)?;if !Arc::ptr_eq(&c.state,&self.0){return Err(io::ErrorKind::InvalidInput.into())}Ok(c)}}
 impl SourceArenaWork for Work{
  fn transformed_source_address_limit(&self)->Option<usize>{
   self.0.reserved.load(Ordering::Acquire).then_some(4*1024*1024)
  }
  fn checkpoint(&self)->io::Result<()>{if self.0.fail.load(Ordering::Acquire){Err(io::Error::from_raw_os_error(1450))}else{Ok(())}}
  fn reserve(&self,bytes:usize)->io::Result<SourceArenaCredit>{self.checkpoint()?;self.charge(bytes);Ok(SourceArenaCredit::from_resource_owner(Arc::new(Credit{bytes:AtomicUsize::new(bytes),state:self.0.clone()})))}
  fn grow(&self,c:&mut SourceArenaCredit,n:usize)->io::Result<()>{
  self.checkpoint()?;
  let c=self.actual(c)?;
  let limit=self.0.limit.load(Ordering::Acquire);
  if limit!=0 && self.0.live.load(Ordering::Acquire).saturating_add(n)>limit{
   return Err(io::ErrorKind::OutOfMemory.into());
  }
  c.bytes.fetch_add(n,Ordering::AcqRel);
  self.charge(n);
  Ok(())
 }
  fn shrink(&self,c:&mut SourceArenaCredit,n:usize)->io::Result<()>{self.checkpoint()?;let c=self.actual(c)?;let before=c.bytes.load(Ordering::Acquire);let after=before.checked_sub(n).ok_or(io::ErrorKind::InvalidInput)?;c.bytes.store(after,Ordering::Release);self.0.live.fetch_sub(n,Ordering::AcqRel);Ok(())}
 }
 #[test]fn actual_arena_growth_funds_old_new_overlap_then_moves_same_string_and_keeps_last_weak_control(){
  let state=Arc::new(State::default());let work=Work(state.clone());let mut out=OriginalSourceArena::new(&work).unwrap();let metadata=state.live.load(Ordering::Acquire);out.append("first").unwrap();let first_capacity=out.text.capacity();let mut input=String::new();input.extend(std::iter::repeat('x').take(first_capacity+1));out.append(&input).unwrap();let capacity=out.text.capacity();let pointer=out.as_str().as_ptr();assert!(state.peak.load(Ordering::Acquire)>=metadata+first_capacity+capacity);assert_eq!(state.live.load(Ordering::Acquire),metadata+capacity);
  let source=out.finish().unwrap();assert_eq!(source.as_str().as_ptr(),pointer);let alias=source.checked_view(0..5).unwrap();let weak=source.downgrade();drop(source);assert!(state.live.load(Ordering::Acquire)>metadata);drop(alias);assert_eq!(state.live.load(Ordering::Acquire),metadata);drop(weak);assert_eq!(state.live.load(Ordering::Acquire),0);
 }
 #[cfg(all(target_pointer_width="64",any(windows,unix)))]
 #[test]
 fn reserved_arena_funds_only_new_pages_and_seals_the_same_utf8_prefix(){
  let state=Arc::new(State::default());
  state.reserved.store(true,Ordering::Release);
  let work=Work(state.clone());
  let mut arena=OriginalSourceArena::new(&work).unwrap();
  let fixed=state.live.load(Ordering::Acquire);
  let page=arena.reserved.as_ref().unwrap().capacity_for(1).unwrap();
  arena.append("first λ").unwrap();
  let pointer=arena.as_str().as_ptr();
  assert_eq!(state.live.load(Ordering::Acquire),fixed+page);
  // Three pages fit. A replacement with the first page still live would not.
  state.limit.store(fixed+3*page,Ordering::Release);
  let tail="é".repeat(page);
  arena.append(&tail).unwrap();
  assert_eq!(arena.as_str().as_ptr(),pointer);
  assert_eq!(state.live.load(Ordering::Acquire),fixed+3*page);
  assert_eq!(state.peak.load(Ordering::Acquire),fixed+3*page);
  let source=arena.finish().unwrap();
  assert_eq!(source.as_str().as_ptr(),pointer);
  assert_eq!(&source.as_str()[..8],"first λ");
  let alias=source.checked_view(8..source.len()).unwrap();
  assert_eq!(alias.as_str(),tail);
  let weak=source.downgrade();
  drop(source);
  assert_eq!(state.live.load(Ordering::Acquire),fixed+3*page);
  drop(alias);
  assert_eq!(state.live.load(Ordering::Acquire),fixed);
  assert!(weak.upgrade().is_none());
  drop(weak);
  assert_eq!(state.live.load(Ordering::Acquire),0);

  let mut denied=OriginalSourceArena::new(&work).unwrap();
  denied.append("first λ").unwrap();
  state.limit.store(fixed+page,Ordering::Release);
  assert_eq!(denied.append(&tail).unwrap_err().kind(),io::ErrorKind::OutOfMemory);
  assert_eq!(denied.as_str(),"first λ");
  assert_eq!(state.live.load(Ordering::Acquire),fixed+page);
  assert!(denied.finish().is_err());
  assert_eq!(state.live.load(Ordering::Acquire),0);
 }

 #[test]fn arena_first_real_io_permanently_poisoned_before_any_resume_or_false_seal(){
  let state=Arc::new(State::default());let work=Work(state.clone());let mut out=OriginalSourceArena::new(&work).unwrap();out.append("kept").unwrap();state.fail.store(true,Ordering::Release);assert_eq!(out.append("refused").unwrap_err().raw_os_error(),Some(1450));state.fail.store(false,Ordering::Release);assert_eq!(out.as_str(),"kept");assert!(out.append("retry").is_err());assert!(out.finish().is_err());assert_eq!(state.live.load(Ordering::Acquire),0);
  let mut fresh=OriginalSourceArena::new(&work).unwrap();fresh.append("fresh").unwrap();let text=fresh.finish().unwrap();assert_eq!(text.as_str(),"fresh");drop(text);assert_eq!(state.live.load(Ordering::Acquire),0);
 }
 #[test]fn arena_credit_survives_unwind_until_actual_payload_destructor(){
  let state=Arc::new(State::default());let work=Work(state.clone());let result=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||{let mut out=OriginalSourceArena::new(&work).unwrap();out.append("live allocation").unwrap();assert!(state.live.load(Ordering::Acquire)>0);panic!("owner control");}));assert!(result.is_err());assert_eq!(state.live.load(Ordering::Acquire),0);
 }
}
