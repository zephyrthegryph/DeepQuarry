//! Shared recorder-owned raw preflight read for Derived and handlers.
//! This never creates native PreparedSource or bypasses later physical traversal.
use super::*;
use dq_analyze::{captured_generator_budget::Budget,captured_reactive_reads::Failure,captured_raw_file::RawPolicyViews};
use std::sync::Arc;
fn quota(b:&Budget,message:impl Into<String>)->Failure{b.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message.into()))}
fn pay(b:&Budget,n:Option<usize>)->Result<(),Failure>{let n=n.ok_or_else(||quota(b,"raw policy preflight allocation overflow"))?;b.charge(n).map_err(|m|quota(b,m))}
/// Resource-only settlement; never authorizes a source or changes the read.
/// The real QueryDb implementation publishes actual backing BEFORE quota denial.
pub(crate) trait RecordedPolicySourceLender {
 /// Resource-only synchronous callback. Unimplemented lenders refuse rather
 /// than issuing detached work or silently accepting an unvisited marker.
 fn with_held_source_work(&mut self,_queries:&crate::query_db::QueryDb,_visit:&mut dyn FnMut(&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->io::Result<()>)->io::Result<()>{Err(io::Error::new(io::ErrorKind::NotConnected,"this source lender has no actual held-gate resource loan"))}

 fn prepare_source(&mut self)->io::Result<()>;
 fn acquired(&mut self,lease:&dm_preprocess::SourceAcquisitionLease)->io::Result<()>;
 /// Raw text borrowed only until the prepaid physical file scope drops.
 /// Exceptional original bytes may still escape into RecordingInputs.
 fn acquired_preflight_file(&mut self,lease:&dm_preprocess::SourceAcquisitionLease)->io::Result<()>{self.acquired(lease)}
 fn prepare_directory_metadata(&mut self,issuer:&Arc<()>,bytes:usize)->io::Result<()>;
 fn directory_window_started(&mut self,issuer:&Arc<()>,upper:usize)->io::Result<()>;
 fn directory_metadata_settled(&mut self,issuer:&Arc<()>,actual:usize)->io::Result<()>;
}
#[cfg(test)]struct TestLender<'a>(&'a Budget);
#[cfg(test)]impl RecordedPolicySourceLender for TestLender<'_>{
 fn prepare_directory_metadata(&mut self,_:&Arc<()>,bytes:usize)->io::Result<()>{self.0.charge(bytes+256).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))}
 fn directory_window_started(&mut self,_:&Arc<()>,_:usize)->io::Result<()>{Ok(())}
 fn directory_metadata_settled(&mut self,_:&Arc<()>,_:usize)->io::Result<()>{Ok(())}
 fn prepare_source(&mut self)->io::Result<()>{self.0.charge(3*256).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))}
 fn acquired(&mut self,lease:&dm_preprocess::SourceAcquisitionLease)->io::Result<()>{let original=super::recorded_source_original(lease)?;if let super::RecordedSourceOriginal::Bytes(bytes)=original{self.0.charge(bytes.capacity()+std::mem::size_of::<dm_resources::SharedBytesOwner>()+2*std::mem::size_of::<usize>()).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?}Ok(())}
}
#[derive(Clone,Copy)]
enum PolicyFileDemand{General,Code,Marker}
impl<P:SnapshotProvider> RecordingInputs<P>{
 #[cfg(test)]pub(crate) fn with_recorded_policy_file(&self,root:&Path,path:&Path,budget:&Arc<Budget>,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{self.with_recorded_policy_file_using(root,path,budget,&mut TestLender(budget),visit)}
 /// Borrow the original policy view of ONE actual admitted recorded read.
 /// The canonical FileInput-backed raw receipt proves this read only. It is
 /// not the productive raw driver's exact path/open receipt or a source grant.
 pub(crate) fn with_recorded_policy_file_using(&self,root:&Path,path:&Path,budget:&Arc<Budget>,lender:&mut dyn RecordedPolicySourceLender,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{
  self.with_recorded_policy_file_demand(root,path,budget,lender,PolicyFileDemand::General,visit)
 }
 pub(crate) fn with_recorded_policy_file_code_using(&self,root:&Path,path:&Path,budget:&Arc<Budget>,lender:&mut dyn RecordedPolicySourceLender,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{
  self.with_recorded_policy_file_demand(root,path,budget,lender,PolicyFileDemand::Code,visit)
 }
 pub(crate) fn with_recorded_policy_file_marker_using(&self,root:&Path,path:&Path,budget:&Arc<Budget>,lender:&mut dyn RecordedPolicySourceLender,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{
  self.with_recorded_policy_file_demand(root,path,budget,lender,PolicyFileDemand::Marker,visit)
 }
 fn with_recorded_policy_file_demand(&self,root:&Path,path:&Path,budget:&Arc<Budget>,lender:&mut dyn RecordedPolicySourceLender,demand:PolicyFileDemand,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{
  if self.initial_environment!=dm_preprocess::InitialEnvironment::OriginalChecker0290{return Err(Failure::Operational(invalid("raw preflight requires actual Original recorder context")))}
  crate::daemon::control::checkpoint()?;budget.require().map_err(|m|quota(budget,m))?;
  // Real recorder path/fact/search-folder nodes are acquired by the same read;
  // the operation funds that ownership before those copies can be published.
  let metadata=path.as_os_str().len().checked_mul(32).and_then(|n|n.checked_add(8192));
  let known={
   let current=self.snapshot.lock().map_err(|_|invalid("input mutex poisoned"))?;
   path.parent().is_some_and(|parent|current.folders.contains_key(parent))&&current.files.contains_key(path)
  };
  if !known{pay(budget,metadata)?;}
  let prepare=|scratch:&Budget|{
   // Receipt construction and validation still use transient path/fact copies.
   if known{pay(scratch,metadata)?;}
   crate::daemon::control::checkpoint()?;scratch.require().map_err(|m|quota(scratch,m))?;
   lender.prepare_source()?;let limit=budget.remaining();
   let mut admit=|bytes|scratch.charge(bytes).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m));
   let bytes=if known{self.reread_policy_payload_admitted(path,limit,&mut admit)}else{self.read_policy_vec_admitted(path,limit,&mut admit)}?
    .ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::NotFound,"selected raw preflight file disappeared before its actual read")))?;
   let lease=self.finish_raw_source_read_admitted(path,bytes,&mut|plan|{
    let needed=plan.constructor_bytes().checked_add(plan.decoded_bytes()).ok_or(io::ErrorKind::OutOfMemory)?;scratch.charge(needed).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;
    Ok(())
   },&mut|actual|lender.acquired_preflight_file(actual))?;
   if !self.validate_recorded_source_lease(path,&lease){return Err(Failure::Operational(invalid("raw preflight actual issuer/path/file facts differ")))}
   let original=super::recorded_source_original(&lease)?;let raw=match &original{super::RecordedSourceOriginal::Utf8(text)=>text.as_bytes(),super::RecordedSourceOriginal::Bytes(bytes)=>bytes.as_slice()};
   let transform=if matches!(&original,super::RecordedSourceOriginal::Utf8(text)if !text.as_bytes().contains(&b'\r')){Some(0)}else{dq_analyze::captured_raw_file::analyze_raw_len(raw).map_err(|m|quota(scratch,m))?.checked_mul(4).and_then(|n|n.checked_add(8192))};pay(scratch,transform)?;
   // Clone a genuine UTF8 view or do only the existing Analyze lossiness/newline
   // projection. No tokenization, parser, schema inference or blanket BOM strip.
   Ok(super::normalize_recorded_policy_original(&original))
  };
  match demand{
   PolicyFileDemand::Code=>dq_analyze::captured_raw_file::with_original_policy_file_code_prepared(root,path,budget,prepare,visit),
   PolicyFileDemand::Marker=>dq_analyze::captured_raw_file::with_original_policy_file_marker_prepared(root,path,budget,prepare,visit),
   PolicyFileDemand::General=>dq_analyze::captured_raw_file::with_original_policy_file_prepared(root,path,0,budget,prepare,visit),
  }
 }
}
#[cfg(test)]mod tests{
 use super::*;
 #[test]fn preflight_raw_loan_retains_real_bom_crlf_and_never_prepares_native_source(){let root=crate::test_scratch::dir("preflight-recorded-raw-view");std::fs::create_dir_all(root.join("code")).unwrap();let path=root.join("code/a.dm");std::fs::write(&path,b"\xef\xbb\xbf/obj/probe\r\n").unwrap();let inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);let budget=Budget::new(8*1024*1024).unwrap();let mut called=0;inputs.with_recorded_policy_file(&root,&path,&budget,&mut|relative,views|{called+=1;assert_eq!(relative,"code/a.dm");assert_eq!(views.raw()?,"\u{feff}/obj/probe\n");Ok(true)}).unwrap();assert_eq!(called,1);assert!(inputs.source_acquisitions.lock().unwrap().is_empty(),"raw preflight must not construct ordinary native PreparedSource");assert!(inputs.recorded_file_fact(&path).is_ok());}
 #[test]fn preflight_raw_loan_preserves_first_callback_io_after_cancel_and_next_fresh_scope(){let root=crate::test_scratch::dir("preflight-recorded-raw-io");std::fs::create_dir_all(root.join("code")).unwrap();let path=root.join("code/a.dm");std::fs::write(&path,"/obj/probe\n").unwrap();let inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(60));let budget=Budget::new(8*1024*1024).unwrap();let actual=inputs.with_recorded_policy_file(&root,&path,&budget,&mut|_,_|{token.cancel();Err(Failure::Operational(io::Error::from_raw_os_error(1450)))});assert!(matches!(actual,Err(Failure::Operational(ref actual))if actual.raw_os_error()==Some(1450)));drop(binding);let fresh=Budget::new(8*1024*1024).unwrap();assert!(inputs.with_recorded_policy_file(&root,&path,&fresh,&mut|_,_|Ok(true)).unwrap());let tiny=Budget::new(256).unwrap();let mut entered=false;assert!(matches!(inputs.with_recorded_policy_file(&root,&path,&tiny,&mut|_,_|{entered=true;Ok(true)}),Err(Failure::Operational(ref actual))if actual.kind()==io::ErrorKind::OutOfMemory));assert!(!entered);}
 #[test]
 fn repeated_real_policy_read_refunds_metadata_without_bypassing_current_bytes(){
  let root=crate::test_scratch::dir("preflight-recorded-raw-repeat");
  std::fs::create_dir_all(root.join("code")).unwrap();
  let path=canonical_path(&root.join("code/a.dm"));
  std::fs::write(&path,"/obj/probe\n").unwrap();
  let inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
  let budget=Budget::new(8*1024*1024).unwrap();
  assert!(inputs.with_recorded_policy_file(&root,&path,&budget,&mut|_,_|Ok(true)).unwrap());
  let after_first=budget.used();
  let fixed=std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>();
  for _ in 0..8{
   assert!(inputs.with_recorded_policy_file(&root,&path,&budget,&mut|_,views|{assert_eq!(views.raw()?,"/obj/probe\n");Ok(true)}).unwrap());
  }
  assert_eq!(budget.used(),after_first+8*(fixed+3*256));
  std::fs::write(&path,"/obj/fresh\n").unwrap();
  let fresh=Budget::new(8*1024*1024).unwrap();
  assert!(matches!(inputs.with_recorded_policy_file(&root,&path,&fresh,&mut|_,_|panic!("a changed source must be refused before lending bytes")),Err(Failure::Operational(error))if error.to_string().contains("input changed during repeated capture")));
 }

}
