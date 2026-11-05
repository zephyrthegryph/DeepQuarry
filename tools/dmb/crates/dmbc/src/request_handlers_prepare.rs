//! Closed sem/handlers source preparation on the SAME host/execution/recorder.
//! Captured source purpose is explicit; no full subject/physical DME/EOF is
//! fabricated for the old partial TU. Findings/report completion is separate.
use super::*;
use crate::{input_snapshot::{RecordingInputs,SnapshotProvider,HandlerPreparedCapture},policy_request::{AdmittedPolicyRequest,AnalysisContext,WorkspaceAuxiliaryQuestion as Q}};
pub(super) fn prepare<P:SnapshotProvider+Sync>(inputs:&RecordingInputs<P>,intent:&AdmittedPolicyRequest,host:&mut crate::runner_host::BuildHost,workers:usize)->Result<Option<Arc<HandlerPreparedCapture>>,Box<dyn std::error::Error>>{
 if intent.analysis_context()!=Some(AnalysisContext::OriginalAnalyze0290)||intent.workspace_auxiliary()!=[Q::SemHandlers]{return Ok(None)}
 if !intent.files().is_empty()||!intent.search_folders().is_empty()||!intent.workspace_generators().is_empty()||intent.workspace().is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"handler preparation requires its exact exclusive workspace request").into())}
 let queries=Arc::clone(host.query_db());let subject=queries.prepare_handlers_preflight(inputs,intent)?;
 // Lease the existing host pool using the same controlled worker entry as the
 // normal runner. No private executor/cache/compiler is constructed here.
 let prepared={let(_,execution,_semantic)=host.execution(workers,None)?;execution.run(|executor|inputs.prepare_handlers_structural(subject,executor,&queries))??};
 let capture=inputs.capture_handlers_prepared(prepared,&queries)?;capture.require_bound()?;Ok(Some(capture))
}
