//! Actual live preparation ledger for a source-bound authored fix. No Checker,
//! generated-output, replay or filesystem permission can be issued from DATA.
use super::runner_freshness;
use crate::{input_snapshot::{InputSnapshot,JoinedReportEpoch,RecordingInputs,SnapshotProvider,Stamp},
 runner_host::workspace_capture::WorkspaceCapture};
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaWork};
use std::{collections::BTreeSet,error::Error,io,path::{Path,PathBuf},sync::{Arc,Weak}};
pub(crate) struct Pending {
 project:PathBuf,capture:Weak<WorkspaceCapture>,epoch:JoinedReportEpoch,_credit:SourceArenaCredit,
}
pub(crate) struct Inputs {
 project:PathBuf,capture:Weak<WorkspaceCapture>,inputs:InputSnapshot,
 _epoch:JoinedReportEpoch,_credit:SourceArenaCredit,
}
impl Pending {
 pub(super) fn capture<P:SnapshotProvider>(recording:&RecordingInputs<P>,project:&Path,
  workspace:&Arc<WorkspaceCapture>,generated:&BTreeSet<PathBuf>,work:&dyn SourceArenaWork)->Result<Self,Box<dyn Error>> {
  let((),epoch)=recording.with_joined_report_snapshot(|inputs|{
   if !workspace.is_recorded_in(inputs){return Err(io::Error::other("authored fix closure omits its actual workspace capture").into())}
   runner_freshness::admit_live(inputs,generated)?;Ok(())
  })?;
  let bytes=project.as_os_str().len().checked_mul(4).and_then(|n|n.checked_add(4096))
   .ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
  let credit=work.reserve(bytes)?;
  Ok(Self{project:project.to_owned(),capture:Arc::downgrade(workspace),epoch,_credit:credit})
 }
 pub(super) fn finish<P:SnapshotProvider>(self,recording:RecordingInputs<P>)->io::Result<Inputs>{
  let inputs=recording.into_joined_report_snapshot(&self.epoch)?;
  Ok(Inputs{project:self.project,capture:self.capture,inputs,_epoch:self.epoch,_credit:self._credit})
 }
}
impl Inputs {
 pub(crate) fn require_workspace(&self,capture:&Arc<WorkspaceCapture>)->io::Result<()> {
  if self.capture.upgrade().is_none_or(|actual|!Arc::ptr_eq(&actual,capture))||!capture.is_recorded_in(&self.inputs){
   return Err(io::Error::new(io::ErrorKind::InvalidInput,"fix ledger and native source belong to different capture issuers"))
  }Ok(())
 }
 pub(crate) fn require_current(&self)->Result<(),Box<dyn Error>>{
  let current=crate::filesystem_proofs::BulkFileSystemProofs::capture_snapshot(&self.inputs)?;
  let provider=crate::input_snapshot::GeneratedOutputInputs::new(&current,self.inputs.generated_outputs().iter().cloned());
  runner_freshness::admit(&self.inputs,&provider)?;
  if !self.inputs.exact_positive_contents_match(&provider)?{
   return Err(io::Error::new(io::ErrorKind::Interrupted,"authored fix captured inputs changed before application").into())
  }Ok(())
 }
 pub(crate) fn recorded_stamp(&self,relative:&str)->io::Result<Stamp>{
  let root=self.project.parent().ok_or_else(||io::Error::other("captured fix manifest has no root"))?;
  let target=dm_preprocess::regions::canonical_path(&root.join(relative));
  self.inputs.authored_recorded_preimage(&target).map(|(stamp,_)|stamp)
 }
 pub(crate) fn target_stamp(&self,relative:&str,preimage:&[u8])->io::Result<Stamp>{
  let root=self.project.parent().ok_or_else(||io::Error::other("captured fix manifest has no root"))?;
  let target=dm_preprocess::regions::canonical_path(&root.join(relative));
  self.inputs.authored_preimage_stamp(&target,preimage)
 }
}

impl Inputs{
 pub(crate) fn require_authored_step(&self,next:&Self,transition:Option<&crate::native_author_fix_transaction::Transition>,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->io::Result<()>{
  work.checkpoint()?;if self.project!=next.project||!self.inputs.same_authored_step(&next.inputs,transition,work)?{return Err(io::Error::new(io::ErrorKind::Interrupted,"native authored batch source/configuration/namespace changed beyond its exact successful write"))}Ok(())
 }
}
