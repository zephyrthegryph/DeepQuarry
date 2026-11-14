//! Moved actual recorder closure for one standalone nonpublishing Checker run.
//! Not a source certificate reconstructed from filenames, hashes or CLI DATA.
use super::runner_freshness;
use crate::input_snapshot::{InputSnapshot,JoinedReportEpoch,RecordingInputs,SnapshotProvider};
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaWork};
use dm_tree::frontend::{DiagnosticSourceView,DiagnosticPreparationPurpose,SourceExportMapping};
use std::{collections::BTreeSet,error::Error,io,path::{Path,PathBuf},sync::{Arc,Weak}};
enum ReportPurpose{Checker,RegisteredModel(Arc<crate::runner_host::NativeCheckSelection>),RegisteredEngineModel(Arc<crate::runner_host::NativeCheckSelection>)}
pub(super) struct Pending{purpose:ReportPurpose,project:PathBuf,mapping:Weak<SourceExportMapping>,semantic:u128,source:u128,epoch:JoinedReportEpoch,_credit:SourceArenaCredit}
pub(crate) struct Inputs{purpose:ReportPurpose,project:PathBuf,mapping:Weak<SourceExportMapping>,semantic:u128,source:u128,inputs:InputSnapshot,_epoch:JoinedReportEpoch,_credit:SourceArenaCredit}
impl Pending{
 pub(super) fn capture<P:SnapshotProvider>(recording:&RecordingInputs<P>,project:&Path,frontend:&DiagnosticSourceView<'_>,generated:&BTreeSet<PathBuf>,work:&dyn SourceArenaWork)->Result<Self,Box<dyn Error>>{
  if frontend.preparation_purpose()!=DiagnosticPreparationPurpose::OriginalSharedComplete||frontend.mapping().initial_environment()!=dm_preprocess::InitialEnvironment::OriginalChecker0290||!frontend.receipt().authenticates(frontend.tree()){
   return Err(io::Error::new(io::ErrorKind::InvalidInput,"standalone Checker needs its actual Original checker preparation").into())
  }
  Self::capture_actual(recording,project,frontend,generated,work,ReportPurpose::Checker)
 }
 // report_project binds the caller operation only. The actual source entry
 // remains authenticated by the subject/mapping/receipt checks below.
 pub(super) fn capture_registered_model<P:SnapshotProvider>(recording:&RecordingInputs<P>,report_project:&Path,frontend:&DiagnosticSourceView<'_>,generated:&BTreeSet<PathBuf>,work:&dyn SourceArenaWork,capture:&Arc<crate::runner_host::workspace_capture::WorkspaceCapture>,plan:&Arc<crate::runner_host::NativeCheckSelection>)->Result<Self,Box<dyn Error>>{
  if plan.source_only()||frontend.mapping().initial_environment()!=dm_preprocess::InitialEnvironment::OriginalChecker0290||frontend.preparation_purpose()!=DiagnosticPreparationPurpose::OriginalSharedComplete||!frontend.receipt().authenticates(frontend.tree()){return Err(io::Error::new(io::ErrorKind::InvalidInput,"selected model ledger requires actual complete Original declaration source").into())}
  capture.require_registered_plan(plan)?;let subject=recording.original_analysis_subject().ok_or_else(||io::Error::other("selected model actual analysis subject absent"))?;subject.require_bound_mapping(frontend.mapping())?;capture.require_analysis_subject(subject)?;
  Self::capture_actual(recording,report_project,frontend,generated,work,ReportPurpose::RegisteredModel(Arc::clone(plan)))
 }
 pub(super) fn capture_registered_engine_model<P:SnapshotProvider>(recording:&RecordingInputs<P>,project:&Path,frontend:&DiagnosticSourceView<'_>,generated:&BTreeSet<PathBuf>,work:&dyn SourceArenaWork,capture:&Arc<crate::runner_host::workspace_capture::WorkspaceCapture>,plan:&Arc<crate::runner_host::NativeCheckSelection>)->Result<Self,Box<dyn Error>>{
  if !plan.exclusive_engine_layering()||frontend.mapping().initial_environment()!=dm_preprocess::InitialEnvironment::OriginalChecker0290||frontend.preparation_purpose()!=DiagnosticPreparationPurpose::OriginalSharedComplete||!frontend.receipt().authenticates(frontend.tree()){return Err(io::Error::new(io::ErrorKind::InvalidInput,"selected Engine model requires actual complete Original producer").into())}
  let subject=recording.original_analysis_subject().ok_or_else(||io::Error::other("actual nonempty Engine subject absent"))?;let preflight=subject.engine_preflight()?;
  if preflight.question()!=crate::policy_request::WorkspaceAuxiliaryQuestion::EngineLayering{return Err(io::Error::new(io::ErrorKind::InvalidInput,"selected Engine model cannot borrow another producer purpose").into())}subject.require_bound_mapping(frontend.mapping())?;capture.require_engine_preflight(preflight)?;capture.require_analysis_subject(subject)?;
  Self::capture_actual(recording,project,frontend,generated,work,ReportPurpose::RegisteredEngineModel(Arc::clone(plan)))
 }
 fn capture_actual<P:SnapshotProvider>(recording:&RecordingInputs<P>,project:&Path,frontend:&DiagnosticSourceView<'_>,generated:&BTreeSet<PathBuf>,work:&dyn SourceArenaWork,purpose:ReportPurpose)->Result<Self,Box<dyn Error>>{
  frontend.require_original_analysis_seed().map_err(|message|io::Error::new(io::ErrorKind::InvalidInput,message))?;
  let((),epoch)=recording.with_joined_report_snapshot(|snapshot|{runner_freshness::admit_live(snapshot,generated)?;Ok(())})?;
  let credit=work.reserve(project.as_os_str().len().checked_mul(4).and_then(|n|n.checked_add(4096)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?)?;
  Ok(Self{purpose,project:project.to_owned(),mapping:Arc::downgrade(frontend.mapping()),semantic:frontend.tree().identity(),source:frontend.source_revision(),epoch,_credit:credit})
 }
 pub(super) fn finish<P:SnapshotProvider>(self,recording:RecordingInputs<P>)->io::Result<Inputs>{
  let inputs=recording.into_joined_report_snapshot(&self.epoch)?;
  Ok(Inputs{purpose:self.purpose,project:self.project,mapping:self.mapping,semantic:self.semantic,source:self.source,inputs,_epoch:self.epoch,_credit:self._credit})
 }
}
impl Inputs{
 pub(crate) fn require_binding(&self,project:&Path,mapping:&Arc<SourceExportMapping>,semantic:u128,source:u128)->io::Result<()>{
  if !matches!(&self.purpose,ReportPurpose::Checker){return Err(io::Error::new(io::ErrorKind::InvalidInput,"model ledger cannot grant standalone Checker source"))}
  if self.project!=project||self.mapping.upgrade().is_none_or(|actual|!Arc::ptr_eq(&actual,mapping))||self.semantic!=semantic||self.source!=source{
   return Err(io::Error::new(io::ErrorKind::InvalidInput,"Checker ledger differs from current actual source owner/frame"))
  }Ok(())
 }
 pub(crate) fn require_registered_model_binding(&self,project:&Path,mapping:&Arc<SourceExportMapping>,semantic:u128,source:u128,plan:&Arc<crate::runner_host::NativeCheckSelection>)->io::Result<()>{
  if !matches!(&self.purpose,ReportPurpose::RegisteredModel(actual)if Arc::ptr_eq(actual,plan))||self.project!=project||self.mapping.upgrade().is_none_or(|actual|!Arc::ptr_eq(&actual,mapping))||self.semantic!=semantic||self.source!=source{return Err(io::Error::new(io::ErrorKind::InvalidInput,"selected model ledger differs from actual plan/source/frame"))}Ok(())
 }
 pub(crate) fn require_registered_engine_binding(&self,project:&Path,mapping:&Arc<SourceExportMapping>,semantic:u128,source:u128,plan:&Arc<crate::runner_host::NativeCheckSelection>)->io::Result<()>{
  if !plan.exclusive_engine_layering()||!matches!(&self.purpose,ReportPurpose::RegisteredEngineModel(actual)if Arc::ptr_eq(actual,plan))||self.project!=project||self.mapping.upgrade().is_none_or(|actual|!Arc::ptr_eq(&actual,mapping))||self.semantic!=semantic||self.source!=source{return Err(io::Error::new(io::ErrorKind::InvalidInput,"selected Engine model ledger differs from exact actual plan/source frame"))}Ok(())
 }
 pub(crate) fn require_current(&self,project:&Path)->Result<(),Box<dyn Error>>{
  if self.project!=project{return Err(io::Error::new(io::ErrorKind::InvalidInput,"Checker ledger belongs to another project").into())}
  let current=crate::filesystem_proofs::BulkFileSystemProofs::capture_snapshot(&self.inputs)?;
  let provider=crate::input_snapshot::GeneratedOutputInputs::new(&current,self.inputs.generated_outputs().iter().cloned());
  runner_freshness::admit(&self.inputs,&provider)?;
  if !self.inputs.exact_positive_contents_match(&provider)?{return Err(io::Error::new(io::ErrorKind::Interrupted,"standalone Checker input closure changed during operation").into())}Ok(())
 }
}
