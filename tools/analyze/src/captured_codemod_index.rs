//! Original lexical ownership index for a native codemod operation.
//! Same funded event producer and same Index replay; no memo/disk cache/model.
//! Depends on the scoped native-pattern Control hooks in frozen regex339.
//! The ownership matcher-chain port and SAME lender issuer are still OPEN;
//! supplying a provider alone is not a full regex heap-closure claim.
use std::io;
use crate::key_policy_control::Control as _;
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaWork};
use crate::{tree::SourceFile,dm::ownership_index::Index,key_policy_control as kc,captured_reactive_reads::Failure,raw_ownership_policy::{self as original,IdxEv}};
fn oom()->Failure{Failure::Operational(io::ErrorKind::OutOfMemory.into())}
struct Control<'a>{work:&'a dyn SourceArenaWork,patterns:&'a dyn crate::native_pattern::Provider,peaks:[usize;8],credit:SourceArenaCredit}
impl<'a>Control<'a>{fn new(work:&'a dyn SourceArenaWork,patterns:&'a dyn crate::native_pattern::Provider)->Result<Self,Failure>{Ok(Self{work,patterns,peaks:[0;8],credit:work.reserve(0).map_err(Failure::Operational)?})}}
impl kc::Control for Control<'_>{
 type Error=Failure;const CHECKED:bool=true;
 fn native_patterns(&self)->Option<&dyn crate::native_pattern::Provider>{Some(self.patterns)}
 fn native_pattern_failed(&mut self,actual:io::Error)->Failure{Failure::Operational(actual)}
 fn checkpoint(&mut self)->Result<(),Failure>{self.work.checkpoint().map_err(Failure::Operational)}
 fn reserve(&mut self,n:usize)->Result<(),Failure>{self.work.grow(&mut self.credit,n).map_err(Failure::Operational)}
 fn temporary(&mut self,slot:usize,n:usize)->Result<(),Failure>{let previous=*self.peaks.get(slot).ok_or_else(oom)?;if n>previous{self.reserve(n-previous)?;self.peaks[slot]=n;}Ok(())}
 fn overflow(&mut self)->Failure{oom()}fn allocation_failed(&mut self)->Failure{oom()}
}
/// Payload first, SAME existing raw-family allocation credit LAST. A borrowed
/// index is lexical DATA only; its zero legacy memo keys issue no native grant.
pub(crate) struct CapturedIndex{actual:Index,_credit:SourceArenaCredit}
impl CapturedIndex{
 pub(crate) fn actual(&self)->&Index{&self.actual}
 pub(crate) fn collect(files:&[&SourceFile],work:&dyn SourceArenaWork,patterns:&dyn crate::native_pattern::Provider)->Result<Self,Failure>{let mut builder=Builder::new(work,patterns)?;for file in files{builder.file(file)?;}builder.finish()}

}

pub(crate) struct Builder<'a>{actual:Index,previous:Option<String>,retained:Control<'a>,scratch:Control<'a>}
impl<'a>Builder<'a>{
 pub(crate) fn new(work:&'a dyn SourceArenaWork,patterns:&'a dyn crate::native_pattern::Provider)->Result<Self,Failure>{
  let mut retained=Control::new(work,patterns)?;let mut scratch=Control::new(work,patterns)?;
  let mut actual=Index::default();
  // Exactly Index::new's original registry order, through existing checked
  // string and row admission rather than an independent fixed scratch bank.
  for name in original::FLYWEIGHT_TYPES{let name=kc::own(&mut retained,name)?;actual.apply_owned_using(IdxEv::Registry(name),&mut retained)?;}
  Ok(Self{actual,previous:None,retained,scratch})
 }
 pub(crate) fn file(&mut self,file:&SourceFile)->Result<(),Failure>{
  let Self{actual,previous,retained,scratch}=self;
   if !file.is_captured_input(){return Err(Failure::Unsupported("native codemod index requires captured file views".into()))}
   if let Some(first)=file.captured_budget_error(){return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,first)))}
   retained.checkpoint()?;
   if previous.as_deref().is_some_and(|old:&str|old>=file.rel.as_str()){return Err(Failure::Unsupported("native codemod index files must have actual unique path order".into()))}
   *previous=Some(kc::own(retained,&file.rel)?);let raw=file.raw();let code=file.code();
   if let Some(first)=file.captured_budget_error(){return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,first)))}
   original::try_visit_file_events_funded(&file.rel,raw,code,scratch,|event|{
    // The producer's scratch already funds these allocated strings. Transfer
    // their exact retained capacities before its next reusable scratch slot.
    let bytes=match &event{
     IdxEv::Member{owner,vtype,name,..}=>owner.capacity().checked_add(vtype.capacity()).and_then(|n|n.checked_add(name.capacity())),
     IdxEv::Decl{owner,name,macro_name,opts,rel,..}=>[owner,name,macro_name,opts,rel].iter().try_fold(0usize,|n,s|n.checked_add(s.capacity())),
     IdxEv::Registry(name)=>Some(name.capacity()),
     IdxEv::Global{name,vtype,..}=>name.capacity().checked_add(vtype.capacity()),
    }.ok_or_else(oom)?;
    retained.reserve(bytes)?;actual.apply_owned_using(event,retained)
   })?;
   if let Some(first)=file.captured_budget_error(){return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,first)))}  Ok(())
 }
 pub(crate) fn finish(self)->Result<CapturedIndex,Failure>{let Self{actual,previous,mut retained,scratch}=self;retained.checkpoint()?;drop(previous);drop(scratch);Ok(CapturedIndex{actual,_credit:retained.credit})}
}
