//! Moved actual recorder closure for one read-only schema proposal run.
//! Not a source certificate reconstructed from filenames, hashes or CLI DATA.
use super::runner_freshness;
use crate::input_snapshot::{InputSnapshot,JoinedReportEpoch,RecordingInputs,SnapshotProvider};
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaWork};
use dm_tree::frontend::{DiagnosticSourceView,SourceExportMapping};
use std::{collections::BTreeSet,error::Error,io,path::{Path,PathBuf},sync::{Arc,Weak}};
pub(super) struct Pending{project:PathBuf,mapping:Weak<SourceExportMapping>,semantic:u128,source:u128,epoch:JoinedReportEpoch,context:crate::daemon::control::WorkerContext,_credit:SourceArenaCredit}
pub(crate) struct Inputs{project:PathBuf,mapping:Weak<SourceExportMapping>,semantic:u128,source:u128,inputs:InputSnapshot,_epoch:JoinedReportEpoch,context:crate::daemon::control::WorkerContext,_credit:SourceArenaCredit}
impl Pending{
 pub(super) fn capture<P:SnapshotProvider>(recording:&RecordingInputs<P>,project:&Path,frontend:&DiagnosticSourceView<'_>,generated:&BTreeSet<PathBuf>,work:&dyn SourceArenaWork)->Result<Self,Box<dyn Error>>{
  if frontend.original_analysis_completeness().is_none()||frontend.mapping().initial_environment()!=dm_preprocess::InitialEnvironment::OriginalChecker0290||!frontend.receipt().authenticates(frontend.tree()){
   return Err(io::Error::new(io::ErrorKind::InvalidInput,"schema proposal needs its actual Original checker preparation").into())
  }
  frontend.require_original_analysis_seed().map_err(|message|io::Error::new(io::ErrorKind::InvalidInput,message))?;
  let((),epoch)=recording.with_joined_report_snapshot(|snapshot|{runner_freshness::admit_live(snapshot,generated)?;Ok(())})?;
  let context=crate::daemon::control::WorkerContext::capture_for_checkpoints().ok_or_else(||io::Error::new(io::ErrorKind::NotConnected,"schema report needs its original active request checkpoint context"))?;
  let credit=work.reserve(project.as_os_str().len().checked_mul(4).and_then(|n|n.checked_add(4096)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?)?;
  Ok(Self{project:project.to_owned(),mapping:Arc::downgrade(frontend.mapping()),semantic:frontend.tree().identity(),source:frontend.source_revision(),epoch,context,_credit:credit})
 }
 pub(super) fn finish<P:SnapshotProvider>(self,recording:RecordingInputs<P>)->io::Result<Inputs>{
  let inputs=recording.into_joined_report_snapshot(&self.epoch)?;
  Ok(Inputs{project:self.project,mapping:self.mapping,semantic:self.semantic,source:self.source,inputs,_epoch:self.epoch,context:self.context,_credit:self._credit})
 }
}
impl Inputs{
 pub(crate) fn with_context<T>(&self,run:impl FnOnce()->io::Result<T>)->io::Result<T>{self.context.with_checkpoint_context(run)}
 pub(crate) fn require_binding(&self,mapping:&Arc<SourceExportMapping>,semantic:u128,source:u128)->io::Result<()>{
  if self.mapping.upgrade().is_none_or(|actual|!Arc::ptr_eq(&actual,mapping))||self.semantic!=semantic||self.source!=source{
   return Err(io::Error::new(io::ErrorKind::InvalidInput,"schema proposal ledger differs from current actual source owner/frame"))
  }Ok(())
 }
 pub(crate) fn require_current(&self)->Result<(),Box<dyn Error>>{
  let current=crate::filesystem_proofs::BulkFileSystemProofs::capture_snapshot(&self.inputs)?;
  let provider=crate::input_snapshot::GeneratedOutputInputs::new(&current,self.inputs.generated_outputs().iter().cloned());
  runner_freshness::admit(&self.inputs,&provider)?;
  if !self.inputs.exact_positive_contents_match(&provider)?{return Err(io::Error::new(io::ErrorKind::Interrupted,"schema proposal input closure changed during operation").into())}Ok(())
 }
}

// Resource-only bounded spool drain, never a source/completion issuer. Actual
// stage callers fund its initialized8KiB scratch and retain the original context.
pub(crate) fn drain(reader:&mut dyn std::io::Read)->io::Result<u64>{let mut block=[0u8;8192];let mut total=0u64;loop{crate::daemon::control::checkpoint()?;let n=reader.read(&mut block)?;if n==0{return Ok(total)}total=total.checked_add(n as u64).ok_or(io::ErrorKind::OutOfMemory)?;}}
#[cfg(test)]mod drain_controls{use super::*;
 struct ReadStop{reads:usize}impl std::io::Read for ReadStop{fn read(&mut self,_:&mut[u8])->io::Result<usize>{self.reads+=1;Err(io::Error::from_raw_os_error(1450))}}
 #[test]fn schema_spool_drain_preserves_first_read_io_and_expired_original_context(){let mut failed=ReadStop{reads:0};assert_eq!(drain(&mut failed).unwrap_err().raw_os_error(),Some(1450));assert_eq!(failed.reads,1);let _binding=crate::daemon::control::bind_with_deadline(crate::daemon::control::Cancellation::default(),std::time::Instant::now());let mut untouched=ReadStop{reads:0};assert_eq!(drain(&mut untouched).unwrap_err().kind(),io::ErrorKind::Interrupted);assert_eq!(untouched.reads,0);}
}

impl Inputs{
 pub(crate)fn require_closure_report_step(&self,next:&Self,root:&Path,transition:&crate::native_author_fix_transaction::Transition,work:&dyn SourceArenaWork)->io::Result<()>{if self.project!=next.project||!self.inputs.same_closure_report_step(&next.inputs,root,transition,work)?{return Err(io::Error::new(io::ErrorKind::Interrupted,"closure write changed another captured input or namespace"))}Ok(())}
}

impl Inputs{
 /// Called only on two actual source-bound prepared attempts. Repreparation
 /// may mint a new mapping owner; exact source/configuration facts must remain
 /// unchanged, while ONLY the writer's one directory step may advance.
 pub(crate)fn require_codemod_directory_step(&self,next:&Self,transition:&crate::native_author_fix_transaction::DirectoryTransition,work:&dyn SourceArenaWork)->io::Result<()>{
  work.checkpoint()?;
  if self.project!=next.project||!self.inputs.same_directory_step(&next.inputs,transition,work)?{return Err(io::Error::new(io::ErrorKind::Interrupted,"codemod directory creation changed another captured input or namespace"))}Ok(())
 }
}

impl Inputs{
 pub(crate)fn require_codemod_authored_step(&self,next:&Self,transition:&crate::native_author_fix_transaction::Transition,work:&dyn SourceArenaWork)->io::Result<()>{if self.project!=next.project||!self.inputs.same_codemod_authored_step(&next.inputs,transition,work)?{return Err(io::Error::new(io::ErrorKind::Interrupted,"codemod authored write changed another captured input"))}Ok(())}
 pub(crate)fn require_codemod_output_step(&self,next:&Self,target:&crate::runner_host::codemod_targets::CapturedCodemodTarget<'_>,transition:&crate::native_author_fix_transaction::Transition,work:&dyn SourceArenaWork)->io::Result<()>{if self.project!=next.project||!self.inputs.same_codemod_output_step(&next.inputs,target,transition,work)?{return Err(io::Error::new(io::ErrorKind::Interrupted,"codemod output changed another captured input or namespace"))}Ok(())}
 pub(crate)fn require_codemod_removal_step(&self,next:&Self,target:&crate::runner_host::codemod_targets::CapturedCodemodTarget<'_>,removal:&crate::native_author_fix_transaction::Removal,work:&dyn SourceArenaWork)->io::Result<()>{if self.project!=next.project||!self.inputs.same_codemod_removal_step(&next.inputs,target,removal,work)?{return Err(io::Error::new(io::ErrorKind::Interrupted,"codemod removal changed another captured input or namespace"))}Ok(())}
}
