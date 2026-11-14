//! Actual same-recorder Source/Handler preparation before a conditional model.
//! This helper executes real existing producers; ChildIntents is only metadata.
use std::{error::Error,io,path::{Path,PathBuf},collections::BTreeSet,sync::Arc};
use crate::{input_snapshot::{RecordingInputs,SnapshotProvider,HandlerPreparedCapture},runner_host::{BuildHost,query_snapshot::{RawWorkspaceSnapshot,HandlerWorkspaceSnapshot}},query_db::QueryDb};
use super::{runner_freshness,source_handler_intent::ChildIntents};

pub(super) struct StructuralPair{
 pub(super) raw:RawWorkspaceSnapshot,pub(super) handlers:HandlerWorkspaceSnapshot,
 pub(super) admission:runner_freshness::WorkspacePolicyAdmission,
}
pub(super) struct RequiredFull{
 pub(super) raw:RawWorkspaceSnapshot,pub(super) capture:Arc<HandlerPreparedCapture>,
 pub(super) admission:runner_freshness::WorkspacePolicyAdmission,
}
pub(super) enum ActualPreparation{Structural(StructuralPair),RequiresFull(RequiredFull)}

/// No caller boolean decides whether a full model is needed. The SAME genuine
/// structural producer's prepared subject makes that existing native decision.
pub(super) fn prepare<P:SnapshotProvider+Sync,C:crate::frozen_inputs::CapturedCurrentProvider>(
 inputs:&RecordingInputs<P>,current:&C,handler_current:&crate::frozen_inputs::Inputs,generated:&BTreeSet<PathBuf>,
 intents:&ChildIntents,host:&mut BuildHost,workers:usize,
)->Result<ActualPreparation,Box<dyn Error>>{
 crate::daemon::control::checkpoint()?;intents.projection().require_parent(intents.projection().parent())?;
 let handlers=super::handlers_prepare::prepare(inputs,intents.handlers(),host,workers,None,false)?
  .ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"conditional operation omitted its actual exclusive Handler producer"))?;
 let queries=Arc::clone(host.query_db());
 let(capture,source)=crate::runner_host::workspace_capture::capture_registered_source_check(inputs,intents.raw(),&queries,Arc::clone(intents.projection().raw()))?;
 let raw=RawWorkspaceSnapshot::issued_registered(intents.raw(),Arc::clone(&capture),source,Arc::clone(&queries),intents.projection().raw())?;
 let admission=runner_freshness::admit_workspace_captured_using(inputs,None,current,generated,capture,queries.as_ref())?.1;
 handlers.require_bound()?;if !handlers.uses_queries(queries.as_ref()){return Err(io::Error::new(io::ErrorKind::InvalidInput,"conditional Handler producer belongs to another actual query owner").into())}handlers.prepared().subject().require_current(inputs)?;
 #[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){crate::daemon_eprintln!("native selected Source/Handler: actual raw={:032x} Handler requires_full={}",raw.revision(),handlers.prepared().subject().requires_full_model());}

 if handlers.prepared().subject().requires_full_model(){
  // The actual raw producer remains independent. It supplies no model, full
  // Handler revision or declaration availability. Continue this SAME runner's
  // existing full preparation with the actual Handler requirement below.
  return Ok(ActualPreparation::RequiresFull(RequiredFull{raw,capture:handlers,admission}))
 }
 let proof=runner_freshness::admit_handlers_captured_using(inputs,None,handler_current,generated,Arc::clone(&handlers),queries.as_ref())?.1.into_shared()?;
 let handlers=HandlerWorkspaceSnapshot::issued(intents.handlers(),handlers,proof,queries)?;
 raw.require_structural_handler_sibling(&handlers,intents.projection().raw())?;
 crate::daemon::control::checkpoint()?;Ok(ActualPreparation::Structural(StructuralPair{raw,handlers,admission}))
}

impl StructuralPair{
 /// Both producers and ordinary provider finish must succeed before the caller
 /// can mint the one moved closure or atomically retain these actual siblings.
 pub(super) fn capture<P:SnapshotProvider>(&self,recording:&RecordingInputs<P>,project:&Path,
  intents:&Arc<ChildIntents>,generated:&BTreeSet<PathBuf>,queries:&QueryDb,
 )->Result<super::source_handler_capture::Pending,Box<dyn Error>>{
  self.raw.require_structural_handler_sibling(&self.handlers,intents.projection().raw())?;
  super::source_handler_capture::Pending::capture(recording,project,Arc::clone(intents.projection()),&self.raw,&self.handlers,None,generated,queries)
 }
}
