//! Operation-specific native codemod/fixture coordinator. WORKING only.
//! No legacy Engine/Sem/model parser or untracked filesystem reader fallback.
use super::*;
use std::{error::Error,io,path::Path,sync::Arc};
use dm_preprocess::source_arena_credit::SourceArenaCredit;

/// SAME actual moved recorder and diagnostic owner stay live through delivery.
/// The operation completes independently of actual Complete/PrimaryPrefix DATA.
pub(crate) struct SemanticPrepared{
 pub(crate) outcome:BuildOutcome,
 pub(crate) inputs:schema_capture::Inputs,
 pub(crate) frontend:Arc<dm_tree::frontend::DiagnosticFrontend>,
 _metadata:SourceArenaCredit,
}
impl SemanticPrepared{
 pub(crate) fn with_model<T>(&self,root:&Path,host:&crate::runner_host::BuildHost,consume:impl FnOnce(&crate::runner_host::query_snapshot::SourceSnapshot)->Result<T,Box<dyn Error>>)->Result<T,Box<dyn Error>>{
  self.inputs.require_current()?;
  let view=self.frontend.source_view().map_err(io::Error::other)?;
  self.inputs.require_binding(view.mapping(),view.tree().identity(),view.source_revision())?;
  let mut pending=None;let mut consume=Some(consume);
  let entered=self.inputs.with_context(||{
   let state=host.query_state();let state=state.try_lock().map_err(|e|match e{std::sync::TryLockError::WouldBlock=>io::Error::new(io::ErrorKind::WouldBlock,"utility current model already borrowed"),std::sync::TryLockError::Poisoned(_)=>io::Error::other("utility current model poisoned")})?;
   let snapshot=state.snapshot.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::NotFound,"utility current model absent"))?;
   if !snapshot.matches_tree(view.tree())||snapshot.source_revision!=view.source_revision()||!snapshot.matches_original_utility_root(root){return Err(io::Error::new(io::ErrorKind::Interrupted,"utility current model changed after preparation"))}
   let run=consume.take().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"utility model consumer repeated"))?;
   pending=Some(run(snapshot));if pending.as_ref().is_some_and(Result::is_err){Err(io::ErrorKind::Other.into())}else{Ok(())}
  });
  let value=match pending{Some(Err(first))=>return Err(first),Some(Ok(value))=>{entered?;value},None=>{entered?;return Err(io::Error::other("utility model context was not visited").into())}};
  self.inputs.require_current()?;Ok(value)
 }
}
/// The admitted request is produced by the backend's existing original-request
/// factory. Raw root, physical project and interpreted fixture config remain
/// separate purposes; this entry deliberately captures NO rules configuration.
pub(crate) fn prepare_semantic_only(request:BuildRequest,root:&Path,host:&mut crate::runner_host::BuildHost,physical:&mut dyn utility_capture::Capture)->Result<SemanticPrepared,Box<dyn Error>>{
 use crate::policy_request::{AnalysisContext,WorkspaceAuxiliaryQuestion as Q};
 if !root.is_absolute()||request.command!=BuildCommand::PrepareQuery||!request.exact_inputs||!request.no_cache||request.no_daemon||!host.retains_artifacts()||!request.defines.is_empty()||request.engine_template.is_some()||request.bootstrap_catalog||request.record_inputs.is_some()||request.replay_inputs.is_some()||request.artifact_directory.is_some()||request.output_store.is_some()||request.trace_path.is_some()||request.source_questions.is_some()||request.diagnostic_declarations||request.policy_inputs.as_ref().is_none_or(|p|p.analysis_context!=Some(AnalysisContext::OriginalAnalyze0290)||p.workspace.as_ref().is_none_or(|w|w.root!=root)||p.workspace_auxiliary!=[Q::SemReads]||!p.workspace_generators.is_empty()||!p.files.is_empty()||!p.search_folders.is_empty()){
  return Err(io::Error::new(io::ErrorKind::InvalidInput,"native codemod requires its actual config-free Original utility request").into())
 }
 let canonical=|p:&Path|crate::policy_request::canonical_analysis_project(p,Some(AnalysisContext::OriginalAnalyze0290));
 if canonical(&request.project)?!=canonical(&root.join("deepquarry.dme"))?{return Err(io::Error::new(io::ErrorKind::InvalidInput,"native codemod project differs from actual caller namespace").into())}
 let cache=request.cache_root.as_deref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"native utility external cache absent"))?;
 let actual_cache=std::fs::canonicalize(cache)?;let actual_root=std::fs::canonicalize(root)?;
 if !actual_cache.is_dir()||actual_cache.starts_with(&actual_root){return Err(io::Error::new(io::ErrorKind::InvalidInput,"utility cache must be existing and outside actual source root").into())}
 let metadata=host.source_arena_work().reserve(cache.as_os_str().len().checked_mul(4).and_then(|n|n.checked_add(16384)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?)?;
 let mut native_text=std::io::sink();let mut inputs=None;let mut frontend=None;let mut output=PreparationDiagnosticOutput::captured(&mut native_text);
 output.retain_native_semantic_only_utility_inputs(&mut inputs,&mut frontend)?;output.retain_utility_physical(physical)?;
 let pending=run_build_with_host_and_derived_sink(request,host,None,&mut output);let first=output.take_error();
 if pending.is_err()||first.is_some(){output.abort_utility_capture();}drop(output);
 if let Some(actual)=first{return Err(actual.into())}let outcome=pending?;
 let inputs=inputs.ok_or_else(||io::Error::other("semantic-only utility omitted actual recorder closure"))?;
 let frontend=frontend.ok_or_else(||io::Error::other("semantic-only utility omitted actual original outcome"))?;
 if frontend.original_analysis_completeness().is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"semantic-only utility has no actual complete/prefix producer").into())}
 let view=frontend.source_view().map_err(io::Error::other)?;inputs.require_binding(view.mapping(),view.tree().identity(),view.source_revision())?;inputs.require_current()?;
 Ok(SemanticPrepared{outcome,inputs,frontend,_metadata:metadata})
}
