//! Operation-local request metadata for actual conditional Source + Handler work.
//! No source/completion authority is established by an admitted request.
use std::{io,sync::Arc,path::Path};
use crate::{policy_request::{AnalysisContext,PolicyInputRequest,WorkspacePolicyRequest,AdmittedPolicyRequest,WorkspaceAuxiliaryQuestion as Q},runner_host::query_snapshot::SourceHandlerProjection};
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaWork};
pub(super) struct ChildIntents{
 projection:Arc<SourceHandlerProjection>,raw:AdmittedPolicyRequest,handlers:AdmittedPolicyRequest,
 _credit:SourceArenaCredit,
}
impl ChildIntents{
 pub(super) fn derive(projection:Arc<SourceHandlerProjection>,root:&Path,configuration:&Path,work:&dyn SourceArenaWork)->io::Result<Self>{
  work.checkpoint()?;projection.require_parent(projection.parent())?;
  if !root.is_absolute()||configuration.strip_prefix(root).ok()!=Some(Path::new("tools/ci/lint_scopes.toml")){return Err(io::Error::new(io::ErrorKind::InvalidInput,"conditional child intents require the same actual registered workspace namespace"))}
  // Fund both original and normalized requests, path vectors and allocation
  // peaks before any caller-width path clone or independent child admission.
  let bytes=projection.raw().roots().iter().try_fold(0usize,|n,(directory,_)|n.checked_add(root.as_os_str().len()).and_then(|n|n.checked_add(directory.len()+1)))
   .and_then(|n|n.checked_add(root.as_os_str().len().checked_mul(4)?)).and_then(|n|n.checked_add(configuration.as_os_str().len().checked_mul(4)?))
   .and_then(|n|n.checked_mul(64)).and_then(|n|n.checked_add(65536+std::mem::size_of::<Self>())).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
  let credit=work.reserve(bytes)?;let mut roots=Vec::new();
  for(directory,_)in projection.raw().roots(){work.checkpoint()?;let path=root.join(directory);if !roots.contains(&path){roots.try_reserve(1).map_err(|_|io::Error::from(io::ErrorKind::OutOfMemory))?;roots.push(path)}}
  let raw_request=PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:root.to_owned(),recursive_roots:roots,configuration:configuration.to_owned()}),..Default::default()};
  let raw=raw_request.admit()?;
  // The legacy structural selector is exclusively visible CODE. The parent's
  // extra raw roots and full-unused domain do not change Handler selection.
  let handler_request=PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:root.to_owned(),recursive_roots:vec![root.join("code")],configuration:configuration.to_owned()}),workspace_auxiliary:vec![Q::SemHandlers],..Default::default()};
  let handlers=handler_request.admit()?;work.checkpoint()?;Ok(Self{projection,raw,handlers,_credit:credit})
 }
 pub(super) fn projection(&self)->&Arc<SourceHandlerProjection>{&self.projection}
 pub(super) fn raw(&self)->&AdmittedPolicyRequest{&self.raw}
 pub(super) fn handlers(&self)->&AdmittedPolicyRequest{&self.handlers}
 pub(super) fn clone_required_full_intent<P:crate::input_snapshot::SnapshotProvider>(&self,capture:&crate::input_snapshot::HandlerPreparedCapture,recording:&crate::input_snapshot::RecordingInputs<P>)->io::Result<AdmittedPolicyRequest>{
  capture.require_bound()?;capture.prepared().subject().require_current(recording)?;if self.handlers.workspace().is_none_or(|workspace|workspace.root!=capture.root())||!capture.prepared().subject().requires_full_model()||capture.prepared().subject().is_selected_full(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"conditional full intent has no actual exclusive Handler requirement"))}
  // The retained metadata credit includes original/normalized clone peaks.
  Ok(self.handlers.clone())
 }

 pub(super) fn require_raw_intent(&self,actual:&AdmittedPolicyRequest)->io::Result<()>{
  self.projection.require_parent(self.projection.parent())?;
  if actual!=&self.raw{return Err(io::Error::new(io::ErrorKind::InvalidInput,"conditional operation borrowed a different admitted raw child intent"))}Ok(())
 }
}
