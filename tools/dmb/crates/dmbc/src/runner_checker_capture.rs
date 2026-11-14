//! Moved actual recorder closure for one standalone nonpublishing Checker run.
//! Not a source certificate reconstructed from filenames, hashes or CLI DATA.
use super::runner_freshness;
use crate::input_snapshot::{InputSnapshot,JoinedReportEpoch,RecordingInputs,SnapshotProvider};
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaWork};
use dm_tree::frontend::{DiagnosticSourceView,DiagnosticPreparationPurpose,SourceExportMapping};
use std::{collections::BTreeSet,error::Error,io,path::{Path,PathBuf},sync::{Arc,Weak}};
pub(super) struct Pending{project:PathBuf,mapping:Weak<SourceExportMapping>,semantic:u128,source:u128,epoch:JoinedReportEpoch,_credit:SourceArenaCredit}
pub(crate) struct Inputs{project:PathBuf,mapping:Weak<SourceExportMapping>,semantic:u128,source:u128,inputs:InputSnapshot,_epoch:JoinedReportEpoch,_credit:SourceArenaCredit}
impl Pending{
 pub(super) fn capture<P:SnapshotProvider>(recording:&RecordingInputs<P>,project:&Path,frontend:&DiagnosticSourceView<'_>,generated:&BTreeSet<PathBuf>,work:&dyn SourceArenaWork)->Result<Self,Box<dyn Error>>{
  if frontend.preparation_purpose()!=DiagnosticPreparationPurpose::OriginalSharedComplete||frontend.mapping().initial_environment()!=dm_preprocess::InitialEnvironment::OriginalChecker0290||!frontend.receipt().authenticates(frontend.tree()){
   return Err(io::Error::new(io::ErrorKind::InvalidInput,"standalone Checker needs its actual Original checker preparation").into())
  }
  frontend.require_original_analysis_seed().map_err(|message|io::Error::new(io::ErrorKind::InvalidInput,message))?;
  let((),epoch)=recording.with_joined_report_snapshot(|snapshot|{runner_freshness::admit_live(snapshot,generated)?;Ok(())})?;
  let credit=work.reserve(project.as_os_str().len().checked_mul(4).and_then(|n|n.checked_add(4096)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?)?;
  Ok(Self{project:project.to_owned(),mapping:Arc::downgrade(frontend.mapping()),semantic:frontend.tree().identity(),source:frontend.source_revision(),epoch,_credit:credit})
 }
 pub(super) fn finish<P:SnapshotProvider>(self,recording:RecordingInputs<P>)->io::Result<Inputs>{
  let inputs=recording.into_joined_report_snapshot(&self.epoch)?;
  Ok(Inputs{project:self.project,mapping:self.mapping,semantic:self.semantic,source:self.source,inputs,_epoch:self.epoch,_credit:self._credit})
 }
}
impl Inputs{
 pub(crate) fn require_binding(&self,project:&Path,mapping:&Arc<SourceExportMapping>,semantic:u128,source:u128)->io::Result<()>{
  if self.project!=project||self.mapping.upgrade().is_none_or(|actual|!Arc::ptr_eq(&actual,mapping))||self.semantic!=semantic||self.source!=source{
   return Err(io::Error::new(io::ErrorKind::InvalidInput,"Checker ledger differs from current actual source owner/frame"))
  }Ok(())
 }
 pub(crate) fn require_current(&self,project:&Path)->Result<(),Box<dyn Error>>{
  if self.project!=project{return Err(io::Error::new(io::ErrorKind::InvalidInput,"Checker ledger belongs to another project").into())}
  let current=crate::filesystem_proofs::BulkFileSystemProofs::capture_snapshot(&self.inputs)?;
  let provider=crate::input_snapshot::GeneratedOutputInputs::new(&current,self.inputs.generated_outputs().iter().cloned());
  runner_freshness::admit(&self.inputs,&provider)?;
  if !self.inputs.exact_positive_contents_match(&provider)?{return Err(io::Error::new(io::ErrorKind::Interrupted,"standalone Checker input closure changed during operation").into())}Ok(())
 }
}
