//! Bounded neutral fixture source views, under the caller's existing owner.
//! These DATA files cannot issue source acquisition, Original or Root grants.
use crate::{derived_selftest_policy::Failure,key_policy_control::{self as kc,Control},tree::SourceFile};
pub(crate) fn source<C:Control<Error=Failure>>(relative:&str,text:&str,c:&mut C)->Result<SourceFile,Failure>{
 if !C::CHECKED{return Ok(SourceFile::from_text(relative,text))}
 // Same four split envelopes as the approved CheckGrep native fixture: raw,
 // code, clean and marker views plus bounded-constructor/overlap metadata.
 let room=kc::split_bound(text.len()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(std::mem::size_of::<SourceFile>())).ok_or_else(||c.overflow())?;
 kc::reserve(c,||room.checked_add(text.len().checked_mul(4)?)?.checked_add(relative.len().checked_mul(8)?)?.checked_add(128))?;
 SourceFile::from_shared_budgeted(relative,std::path::PathBuf::from(relative),text.to_owned().into(),room).map_err(|message|{let _=c.allocation_failed();Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message))})
}
/// Loan only; the SourceFiles and caller's real grant outlive this control.
/// A lazy captured-view OOM must precede any later cancellation/IO poll.
pub(crate) struct Views<'a,C>{pub inner:&'a mut C,pub files:&'a[SourceFile]}
impl<C:Control<Error=Failure>> Views<'_,C>{fn require(&mut self)->Result<(),Failure>{
 if !C::CHECKED{return Ok(())}
 for file in self.files{if let Some(message)=file.captured_budget_error(){let _=self.inner.allocation_failed();return Err(Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message)))}}
 Ok(())
}}
impl<C:Control<Error=Failure>> Control for Views<'_,C>{type Error=Failure;const CHECKED:bool=C::CHECKED;
 fn checkpoint(&mut self)->Result<(),Failure>{self.require()?;self.inner.checkpoint()}
 fn reserve(&mut self,bytes:usize)->Result<(),Failure>{self.require()?;self.inner.reserve(bytes)}
 fn temporary(&mut self,slot:usize,bytes:usize)->Result<(),Failure>{self.require()?;self.inner.temporary(slot,bytes)}
 fn overflow(&mut self)->Failure{self.inner.overflow()}fn allocation_failed(&mut self)->Failure{self.inner.allocation_failed()}
}

#[cfg(all(test,feature="native-policy"))]mod controls{
 use super::*;use crate::{captured_generator_budget::Budget,derived_selftest_policy::NativeAssertions};
 #[test]fn captured_fixture_child_oom_precedes_later_original_io_and_fresh_source_recovers(){
  let budget=Budget::new(crate::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();budget.charge(1<<20).unwrap();let text="x".repeat(4096);
  let file=SourceFile::from_shared_budgeted("code/a.dm",std::path::PathBuf::from("code/a.dm"),text.clone().into(),8192).unwrap();let _=file.clean();assert!(file.captured_budget_error().is_some(),"real lazy view must fail its existing 8KiB child ledger");
  let polls=std::cell::Cell::new(0);let later=||{polls.set(polls.get()+1);Err(std::io::Error::from_raw_os_error(1450))};let mut control=NativeAssertions{budget:&budget,poll:&later};let mut views=Views{inner:&mut control,files:std::slice::from_ref(&file)};
  assert!(matches!(views.checkpoint(),Err(Failure::Operational(actual))if actual.kind()==std::io::ErrorKind::OutOfMemory));assert_eq!(polls.get(),0);drop(views);drop(control);drop(file);
  let fresh=Budget::new(crate::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();let mut control=NativeAssertions{budget:&fresh,poll:&||Ok(())};let file=source("code/a.dm",&text,&mut control).unwrap();let _=file.clean();let mut views=Views{inner:&mut control,files:std::slice::from_ref(&file)};views.checkpoint().unwrap();
 }
}
