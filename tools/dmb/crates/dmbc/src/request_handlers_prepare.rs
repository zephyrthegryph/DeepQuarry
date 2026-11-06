//! Closed sem/handlers source preparation on the SAME host/execution/recorder.
//! Captured source purpose is explicit; no full subject/physical DME/EOF is
//! fabricated for the old partial TU. Findings/report completion is separate.
use super::*;
use crate::{input_snapshot::{RecordingInputs,SnapshotProvider,HandlerPreparedCapture},policy_request::{AdmittedPolicyRequest,AnalysisContext,WorkspaceAuxiliaryQuestion as Q}};
pub(super) fn prepare<P:SnapshotProvider+Sync>(inputs:&RecordingInputs<P>,intent:&AdmittedPolicyRequest,host:&mut crate::runner_host::BuildHost,workers:usize)->Result<Option<Arc<HandlerPreparedCapture>>,Box<dyn std::error::Error>>{
 if intent.analysis_context()!=Some(AnalysisContext::OriginalAnalyze0290){return Ok(None)}
 let selected=match intent.workspace_auxiliary(){[Q::SemHandlers]=>false,[Q::SemHandlersFullAllow]=>true,_=>return Ok(None)};
 if !intent.files().is_empty()||!intent.search_folders().is_empty()||!intent.workspace_generators().is_empty()||intent.workspace().is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"handler preparation requires its exact exclusive workspace request").into())}
 let queries=Arc::clone(host.query_db());
 let subject=if selected{
  use dq_analyze::{captured_allow_annotations::{Operation,full_unused::SelectedTreePlanData},captured_generator_budget::Budget,captured_reactive_reads::Failure,tree::CODE_MAPS_DM};
  let budget=Budget::new(1<<20).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;
  let mut work=Operation{budget:&budget,poll:&crate::daemon::control::checkpoint};
  let plan=SelectedTreePlanData::new([CODE_MAPS_DM],&mut work).map_err(|failure|match failure{
   Failure::Operational(actual)=>actual,
   Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message),
  })?;
  queries.prepare_selected_handlers_preflight(inputs,intent,&plan)?
 }else{queries.prepare_handlers_preflight(inputs,intent)?};
 // Lease the existing host pool using the same controlled worker entry as the
 // normal runner. No private executor/cache/compiler is constructed here.
 let prepared={let(_,execution,_semantic)=host.execution(workers,None)?;execution.run(|executor|inputs.prepare_handlers_structural(subject,executor,&queries))??};
 let capture=inputs.capture_handlers_prepared(prepared,&queries)?;capture.require_bound()?;Ok(Some(capture))
}
