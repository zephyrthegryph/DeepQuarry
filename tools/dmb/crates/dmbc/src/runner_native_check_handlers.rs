//! Conditional sem/handlers CHECK ownership, distinct from source/model frames.
//! Held draft: not installed, built, or qualified. One real recorder is moved.
use super::runner_freshness;
use crate::{input_snapshot::{InputSnapshot,JoinedReportEpoch,RecordingInputs,SnapshotProvider},
 runner_host::{NativeCheckSelection,query_snapshot::HandlerWorkspaceSnapshot}};
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaWork};
use std::{collections::BTreeSet,error::Error,io,path::{Path,PathBuf},sync::Arc};
fn invalid(message:&'static str)->io::Error{io::Error::new(io::ErrorKind::InvalidInput,message)}
pub(crate) struct Inputs{
 project:PathBuf,plan:Arc<NativeCheckSelection>,snapshot:HandlerWorkspaceSnapshot,
 inputs:InputSnapshot,_epoch:JoinedReportEpoch,_credit:SourceArenaCredit,
}
pub(super) struct Pending{
 project:PathBuf,plan:Arc<NativeCheckSelection>,snapshot:HandlerWorkspaceSnapshot,
 epoch:JoinedReportEpoch,_credit:SourceArenaCredit,
}
impl Pending{
 pub(super) fn capture<P:SnapshotProvider>(recording:&RecordingInputs<P>,project:&Path,
  plan:Arc<NativeCheckSelection>,snapshot:&HandlerWorkspaceSnapshot,
  generated:&BTreeSet<PathBuf>,work:&dyn SourceArenaWork)->Result<Self,Box<dyn Error>>{
  work.checkpoint()?;snapshot.require_current()?;
  if !plan.handlers_only()||!snapshot.matches_context(project,&Default::default(),Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290)){
   return Err(invalid("conditional Handler CHECK needs its actual exclusive plan and current namespace").into())
  }
  // This is the already admitted CURRENT handler branch. Failed-full and
  // preparation-only prefixes never construct this private snapshot owner.
  let((),epoch)=recording.with_joined_report_snapshot(|inputs|{
   runner_freshness::admit_live(inputs,generated)?;
   if !snapshot.capture().is_recorded_in(inputs){return Err(invalid("Handler report omits its actual recorded partial source").into())}
   snapshot.require_current()?;Ok(())
  })?;
  let bytes=project.as_os_str().len().checked_mul(4)
   .and_then(|n|n.checked_add(4096+std::mem::size_of::<Self>()+std::mem::size_of::<Inputs>()))
   .ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
  let credit=work.reserve(bytes)?;
  Ok(Self{project:project.to_owned(),plan,snapshot:snapshot.clone(),epoch,_credit:credit})
 }
 pub(super) fn finish<P:SnapshotProvider>(self,recording:RecordingInputs<P>)->io::Result<Inputs>{
  let inputs=recording.into_joined_report_snapshot(&self.epoch)?;
  Ok(Inputs{project:self.project,plan:self.plan,snapshot:self.snapshot,inputs,_epoch:self.epoch,_credit:self._credit})
 }
}
impl Inputs{
 /// Observation DATA only: never semantic/policy revision pins. The containing
 /// Handler report still needs the same current actual owner and moved ledger.
 pub(crate) fn observation(&self)->io::Result<(u128,Option<u128>,Option<u128>)>{
  self.snapshot.require_current()?;
  Ok((self.snapshot.revision(),self.snapshot.source_revision()?,self.snapshot.full_source_revision()?))
 }

 pub(crate) fn require_binding(&self,current:&HandlerWorkspaceSnapshot,plan:&Arc<NativeCheckSelection>)->io::Result<()>{
  if !Arc::ptr_eq(plan,&self.plan){return Err(invalid("Handler report plan belongs to another actual operation"))}
  self.snapshot.require_same_snapshot(current)
 }
 pub(crate) fn require_current(&self,project:&Path)->io::Result<()>{
  crate::daemon::control::checkpoint()?;
  if project!=self.project||!self.plan.handlers_only(){return Err(invalid("Handler report ledger belongs to another request purpose"))}
  self.snapshot.require_current()?;
  let current=crate::filesystem_proofs::BulkFileSystemProofs::capture_snapshot(&self.inputs)?;
  let provider=crate::input_snapshot::GeneratedOutputInputs::new(&current,self.inputs.generated_outputs().iter().cloned());
  runner_freshness::admit(&self.inputs,&provider).map_err(|error|match error.downcast::<io::Error>(){
   Ok(actual)=>*actual,Err(other)=>io::Error::new(io::ErrorKind::Interrupted,other.to_string())})?;
  if !self.inputs.exact_positive_contents_match(&provider)?{return Err(io::Error::new(io::ErrorKind::Interrupted,"Handler report input closure changed during operation"))}
  self.snapshot.require_current()
 }
}

/// Called only after QueryAttempt issued its genuine Current Handler owner.
/// The mutex alias is released before the caller finishes that attempt.
pub(super) fn capture_current<P:SnapshotProvider>(recording:&RecordingInputs<P>,project:&Path,
 plan:Arc<NativeCheckSelection>,query_state:&std::sync::Mutex<crate::runner_host::query_snapshot::QueryState>,
 generated:&BTreeSet<PathBuf>,work:&dyn SourceArenaWork)->Result<Pending,Box<dyn Error>>{
 let state=query_state.try_lock().map_err(|error|match error{
  std::sync::TryLockError::WouldBlock=>io::Error::new(io::ErrorKind::WouldBlock,"current Handler source is already borrowed"),
  std::sync::TryLockError::Poisoned(_)=>io::Error::other("current Handler source state poisoned")})?;
 let snapshot=state.handlers_snapshot.as_ref().ok_or_else(||invalid("actual Handler preparation omitted its admitted source owner"))?;
 Pending::capture(recording,project,plan,snapshot,generated,work)
}

/// Evidence of ONE actual failed-root report callback. This is deliberately not
/// Inputs: no require_current(), successful frame or retained-query outcome.
/// The original preparation error travels separately and remains primary.
pub(crate) struct FailedFullOneShot {
 diagnostics:Option<crate::selected_report_spool::Verified>,report:crate::selected_report_spool::Verified,clean:bool,
 capture:Arc<crate::input_snapshot::HandlerPreparedCapture>,
 proof:Arc<runner_freshness::HandlerPolicyAdmission>,queries:Arc<crate::query_db::QueryDb>,
 inputs:InputSnapshot,_epoch:JoinedReportEpoch,_credit:SourceArenaCredit,
}
impl FailedFullOneShot {
 pub(crate) fn write_once(self,mut diagnostics:&mut dyn io::Write,mut output:&mut dyn io::Write)->io::Result<()> {
  // These owner checks distinguish the real failed callback from Current. No
  // freshness, EOF or full-model claim is made for the captured failure prefix.
  if self.proof.is_current()||self.proof.failed_root().is_none()
   ||!Arc::ptr_eq(&self.capture,self.proof.capture())||!self.capture.uses_queries(&self.queries){
   return Err(invalid("one-shot Handler output lost its actual failed-full owner"))
  }
  if let Some(stage)=self.diagnostics{stage.publish(&mut diagnostics)?;}self.report.publish(&mut output)
 }
 pub(crate) fn clean_data(&self)->bool{self.clean}
}
/// Precreated operation-local disk stage. Each actual retry must restart it;
/// callbacks borrow the real child budget and never reserve through QueryDb
/// while that producer holds its raw-family gate.
pub(super) struct FailureStaging {
 plan:Arc<NativeCheckSelection>,file:Option<crate::selected_report_spool::Stage>,diagnostics:Option<crate::selected_report_spool::Stage>,
 cache:PathBuf,_credit:SourceArenaCredit,
}
impl FailureStaging {
 pub(super) fn new(plan:Arc<NativeCheckSelection>,cache:&Path,work:&dyn SourceArenaWork)->io::Result<Self>{
  if !plan.handlers_only(){return Err(invalid("failure staging requires exclusive real sem/handlers selection"))}
  let bytes=cache.as_os_str().len().checked_mul(4).and_then(|n|n.checked_add(4096+std::mem::size_of::<Self>())).ok_or(io::ErrorKind::OutOfMemory)?;
  let credit=work.reserve(bytes)?;let file=crate::selected_report_spool::Stage::new(cache)?;
  Ok(Self{plan,file:Some(file),diagnostics:Some(crate::selected_report_spool::Stage::new(cache)?),cache:cache.to_owned(),_credit:credit})
 }
 pub(super) fn restart(&mut self)->io::Result<()>{
  match self.file.as_mut(){Some(file)=>file.restart_attempt()?,None=>self.file=Some(crate::selected_report_spool::Stage::new(&self.cache)?)}
  match self.diagnostics.as_mut(){Some(file)=>file.restart_attempt()?,None=>self.diagnostics=Some(crate::selected_report_spool::Stage::new(&self.cache)?)}Ok(())
 }
}
pub(super) fn capture_failed<P:SnapshotProvider>(
 staging:&mut FailureStaging,recording:&RecordingInputs<P>,
 capture:Arc<crate::input_snapshot::HandlerPreparedCapture>,proof:Arc<runner_freshness::HandlerPolicyAdmission>,
 queries:Arc<crate::query_db::QueryDb>,work:&dyn SourceArenaWork,
)->io::Result<FailedPending>{
 if proof.is_current()||!Arc::ptr_eq(&capture,proof.capture())||!capture.uses_queries(&queries){return Err(invalid("failed Handler stage has another actual admission owner"))}
 let failed=proof.failed_root().ok_or_else(||invalid("failed Handler stage lacks actual failed root"))?;
 capture.require_failed_full_prefix(recording,&queries,failed)?;
 let file=staging.file.take().ok_or_else(||invalid("failed Handler callback stage was already consumed"))?;
 // A genuine QueryDb producer proves the failed-prefix again AFTER this callback.
 let mut diagnostics=staging.diagnostics.take().ok_or_else(||invalid("failed Handler diagnostic stage was already consumed"))?;
 let(diagnostics,clean,report)=queries.with_handlers_failed_full_report(recording,&capture,&proof,|data,config,child|{
  // The retained partial producer is the only semantic notice owner here;
  // the independently requested full root failed before issuing a frontend.
  if let Some(frontend)=capture.prepared().frontend(){let partial=frontend.handlers_structural_source().map_err(io::Error::other)?;
   if let Some(notices)=partial.view().original_preprocess_notices(){crate::diagnostics::write_original_preprocess_notices(&mut diagnostics,&notices)?;}}
  let diagnostics=if diagnostics.length()==0{None}else{Some(check_diagnostic_stage(diagnostics)?)};
  let(clean,report)=crate::runner_host::query_snapshot::stage_registered_handlers_failed_full(capture.root(),&staging.plan,file,data,config,child)?;
  Ok((diagnostics,clean,report))
 })?;
 let total=report.length().checked_add(diagnostics.as_ref().map_or(0,|part|part.length())).ok_or(io::ErrorKind::OutOfMemory)?;
 if total>dq_analyze::selected_exclusions_wire::MAX_STREAM{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"failed Handler combined output exceeds existing report bound"))}
 failed.require_recording(recording,&queries)?;capture.require_failed_full_prefix(recording,&queries,failed)?;
 // Do not call require_recording from inside this mutex loan: that would try
 // to acquire the SAME snapshot mutex again. The epoch transfer is real.
 let((),epoch)=recording.with_joined_report_snapshot(|_|Ok::<(),Box<dyn Error>>(()))
  .map_err(|error|match error.downcast::<io::Error>(){Ok(actual)=>*actual,Err(other)=>io::Error::other(other.to_string())})?;
 failed.require_recording(recording,&queries)?;capture.require_failed_full_prefix(recording,&queries,failed)?;
 let credit=work.reserve(std::mem::size_of::<FailedPending>()+std::mem::size_of::<FailedFullOneShot>()+4096)?;
 Ok(FailedPending{diagnostics,report,clean,capture,proof,queries,epoch,_credit:credit})
}
pub(super) struct FailedPending {
 diagnostics:Option<crate::selected_report_spool::Verified>,report:crate::selected_report_spool::Verified,clean:bool,
 capture:Arc<crate::input_snapshot::HandlerPreparedCapture>,proof:Arc<runner_freshness::HandlerPolicyAdmission>,
 queries:Arc<crate::query_db::QueryDb>,epoch:JoinedReportEpoch,_credit:SourceArenaCredit,
}
impl FailedPending {
 pub(super) fn finish<P:SnapshotProvider>(self,recording:RecordingInputs<P>)->io::Result<FailedFullOneShot>{
  let inputs=recording.into_joined_report_snapshot(&self.epoch)?;
  Ok(FailedFullOneShot{diagnostics:self.diagnostics,report:self.report,clean:self.clean,capture:self.capture,proof:self.proof,queries:self.queries,inputs,_epoch:self.epoch,_credit:self._credit})
 }
}

pub(crate) fn check_diagnostic_stage(file:crate::selected_report_spool::Stage)->io::Result<crate::selected_report_spool::Verified>{
 let length=file.length();let(stage,count)=file.seal()?.validate(|input|{
  let mut block=[0u8;8192];let mut total=0u64;loop{crate::daemon::control::checkpoint()?;let n=input.read(&mut block)?;if n==0{return Ok(total)}total=total.checked_add(n as u64).ok_or(io::ErrorKind::OutOfMemory)?;}
 })?;
 if count!=length||stage.length()!=length{return Err(invalid("Handler diagnostics omitted sealed bytes"))}Ok(stage)
}

#[cfg(test)]#[path="runner_native_check_handlers_tests.rs"]mod tests;
