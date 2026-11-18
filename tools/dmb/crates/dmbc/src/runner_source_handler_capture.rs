//! One actual moved ledger for a real no-Model Raw + structural Handler pair.
//! Developing private operation owner; not source authority reconstructed from DATA.
use super::runner_freshness;
use crate::{input_snapshot::{InputSnapshot,JoinedReportEpoch,RecordingInputs,SnapshotProvider,HandlerPreparedCapture},runner_host::query_snapshot::{RawWorkspaceSnapshot,HandlerWorkspaceSnapshot,SourceHandlerProjection,SourceHandlerPins,SourceSnapshot}};
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaWork};
use std::{collections::{BTreeMap,BTreeSet},error::Error,io,path::{Path,PathBuf},sync::Arc};
pub(super) struct Pending{project:PathBuf,projection:Arc<SourceHandlerProjection>,raw:RawWorkspaceSnapshot,handler:Arc<HandlerPreparedCapture>,proof:Arc<runner_freshness::HandlerPolicyAdmission>,pins:SourceHandlerPins,full_mapping:Option<std::sync::Weak<dm_tree::frontend::SourceExportMapping>>,epoch:JoinedReportEpoch,_credit:SourceArenaCredit}
pub(crate) struct Inputs{project:PathBuf,projection:Arc<SourceHandlerProjection>,raw:RawWorkspaceSnapshot,handler:Arc<HandlerPreparedCapture>,proof:Arc<runner_freshness::HandlerPolicyAdmission>,pins:SourceHandlerPins,full_mapping:Option<std::sync::Weak<dm_tree::frontend::SourceExportMapping>>,inputs:InputSnapshot,_epoch:JoinedReportEpoch,_credit:SourceArenaCredit}
impl Pending{
 pub(super) fn capture<P:SnapshotProvider>(recording:&RecordingInputs<P>,project:&Path,projection:Arc<SourceHandlerProjection>,raw:&RawWorkspaceSnapshot,handler:&HandlerWorkspaceSnapshot,full:Option<&SourceSnapshot>,generated:&BTreeSet<PathBuf>,work:&dyn SourceArenaWork)->Result<Self,Box<dyn Error>>{
  work.checkpoint()?;projection.require_parent(projection.parent())?;let pins=raw.require_source_handler_sibling(handler,projection.raw(),full)?;let full_mapping=full.map(|actual|actual.source_handler_mapping(handler).map(Arc::downgrade)).transpose()?;
  if !raw.matches_context(project,&BTreeMap::new(),Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))||!handler.matches_context(project,&BTreeMap::new(),Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290)){return Err(io::Error::new(io::ErrorKind::InvalidInput,"combined source/Handler actual namespace differs").into())}
  let bytes=project.as_os_str().len().checked_mul(4).and_then(|n|n.checked_add(4096+std::mem::size_of::<Self>()+std::mem::size_of::<Inputs>())).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;let credit=work.reserve(bytes)?;
  // This method takes the real snapshot mutex itself, so it must be outside
  // the epoch callback below. Both native owners already belong to this run.
  handler.capture().prepared().subject().require_current(recording)?;
  let((),epoch)=recording.with_joined_report_snapshot(|inputs|{runner_freshness::admit_live(inputs,generated)?;raw.require_recorded_source_handler_prefix(inputs,projection.raw())?;Ok(())})?;
  Ok(Self{project:project.to_owned(),projection,raw:raw.clone(),handler:Arc::clone(handler.capture()),proof:Arc::clone(handler.admission()),pins,full_mapping,epoch,_credit:credit})
 }
 pub(super) fn finish<P:SnapshotProvider>(self,recording:RecordingInputs<P>)->io::Result<Inputs>{let inputs=recording.into_joined_report_snapshot(&self.epoch)?;Ok(Inputs{project:self.project,projection:self.projection,raw:self.raw,handler:self.handler,proof:self.proof,pins:self.pins,full_mapping:self.full_mapping,inputs,_epoch:self.epoch,_credit:self._credit})}
}
fn actual_io(error:Box<dyn Error>)->io::Error{match error.downcast::<io::Error>(){Ok(actual)=>*actual,Err(other)=>io::Error::new(io::ErrorKind::Interrupted,other.to_string())}}
impl Inputs{
 pub(crate) fn require_baseline_step(&self,next:&Self,project:&Path,transition:&crate::native_author_fix_transaction::Transition,work:&dyn SourceArenaWork)->io::Result<()>{
  work.checkpoint()?;
  let a=self.projection.parent();let b=next.projection.parent();
  if self.project!=project||next.project!=project||!a.is_baseline_update()||!b.is_baseline_update()||!Arc::ptr_eq(a,b){return Err(io::Error::new(io::ErrorKind::InvalidInput,"Source/Handler baseline step differs from actual parent plan/namespace"))}
  if !self.inputs.same_baseline_step(&next.inputs,transition,work)?{return Err(io::Error::new(io::ErrorKind::Interrupted,"Source/Handler input closure changed beyond its actual baseline write"))}Ok(())
 }
 pub(crate) fn pins(&self)->SourceHandlerPins{self.pins}
 pub(crate) fn require_binding(&self,raw:&RawWorkspaceSnapshot,handler:&HandlerWorkspaceSnapshot,full:Option<&SourceSnapshot>,projection:&Arc<SourceHandlerProjection>)->io::Result<()>{
  if !Arc::ptr_eq(projection,&self.projection)||!Arc::ptr_eq(handler.capture(),&self.handler)||!Arc::ptr_eq(handler.admission(),&self.proof){return Err(io::Error::new(io::ErrorKind::InvalidInput,"combined source report belongs to another actual owner"))}
  self.projection.require_parent(projection.parent())?;self.raw.require_same_registered_frame(raw,projection.raw())?;let same_full=match(&self.full_mapping,full){(None,None)=>true,(Some(bound),Some(actual))=>{let current=actual.source_handler_mapping(handler)?;bound.upgrade().is_some_and(|bound|Arc::ptr_eq(&bound,current))},_=>false};if !same_full{return Err(io::Error::new(io::ErrorKind::InvalidInput,"conditional report full mapping differs from its actual admitted sibling"))}if raw.require_source_handler_sibling(handler,projection.raw(),full)?!=self.pins{return Err(io::Error::new(io::ErrorKind::InvalidInput,"combined source report actual frame changed"))}Ok(())
 }
 pub(crate) fn require_report_current(&self,project:&Path)->io::Result<()>{
  crate::daemon::control::checkpoint()?;if self.project!=project||!self.proof.is_current()||!Arc::ptr_eq(&self.handler,self.proof.capture()){return Err(io::Error::new(io::ErrorKind::InvalidInput,"combined source report lost its exact actual purpose/owner"))}self.handler.require_bound()?;if self.full_mapping.as_ref().is_some_and(|mapping|mapping.upgrade().is_none()){return Err(io::Error::new(io::ErrorKind::InvalidInput,"conditional full source owner is no longer retained"))}self.projection.require_parent(self.projection.parent())?;self.raw.require_recorded_source_handler_prefix(&self.inputs,self.projection.raw())?;
  let current=crate::filesystem_proofs::BulkFileSystemProofs::capture_snapshot(&self.inputs)?;let provider=crate::input_snapshot::GeneratedOutputInputs::new(&current,self.inputs.generated_outputs().iter().cloned());runner_freshness::admit(&self.inputs,&provider).map_err(actual_io)?;if !self.inputs.exact_positive_contents_match(&provider)?{return Err(io::Error::new(io::ErrorKind::Interrupted,"combined source/Handler input closure changed during operation"))}self.handler.require_bound()?;self.raw.require_recorded_source_handler_prefix(&self.inputs,self.projection.raw())?;crate::daemon::control::checkpoint()
 }
}

/// Called only after the same current QueryAttempt admitted its actual full
/// Handler child and retained its independent Raw sibling. The same state loan
/// supplies both current owners; only one original recorder epoch is minted.
pub(super) fn capture_current<P:SnapshotProvider>(recording:&RecordingInputs<P>,project:&Path,
 projection:Arc<SourceHandlerProjection>,query_state:&std::sync::Mutex<crate::runner_host::query_snapshot::QueryState>,
 generated:&BTreeSet<PathBuf>,work:&dyn SourceArenaWork,
)->Result<Pending,Box<dyn Error>>{
 let state=query_state.lock().map_err(|_|io::Error::other("conditional query state poisoned"))?;
 let raw=state.raw_snapshot.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::NotConnected,"conditional actual Raw sibling absent"))?;
 let handlers=state.handlers_snapshot.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::NotConnected,"conditional actual Handler sibling absent"))?;
 let full=handlers.requires_full().then_some(state.snapshot.as_ref()).flatten();
 Pending::capture(recording,project,projection,raw,handlers,full,generated,work)
}

impl Inputs{pub(crate) fn native_selftest_epoch(&self)->&crate::input_snapshot::JoinedReportEpoch{&self._epoch}}

impl Inputs{
 pub(crate) fn with_report_input_observation<T>(&self,project:&std::path::Path,observe:impl FnOnce(&crate::input_snapshot::InputSnapshot)->std::io::Result<T>)->Result<T,Box<dyn std::error::Error>>{
  self.require_report_current(project)?;let result=observe(&self.inputs)?;self.require_report_current(project)?;Ok(result)
 }
}
