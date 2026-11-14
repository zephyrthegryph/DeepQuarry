//! One read-only schema operation on the caller's retained host. Never a writer.
use super::*;
struct Prepared{outcome:crate::request::BuildOutcome,inputs:crate::request_runner::schema_capture::Inputs,diagnostics:Option<crate::selected_report_spool::Verified>,_credit:dm_preprocess::source_arena_credit::SourceArenaCredit}
pub(crate) struct SchemaReport{pub(crate) root:PathBuf,pub(crate) inputs:crate::request_runner::schema_capture::Inputs,pub(crate) frame:dq_analyze::selected_exclusions_wire::Frame,pub(crate) count:usize,pub(crate) diagnostics:Option<crate::selected_report_spool::Verified>,pub(crate) report:crate::selected_report_spool::Verified,pub(crate) _credit:dm_preprocess::source_arena_credit::SourceArenaCredit,pub(crate) _prepare_credit:dm_preprocess::source_arena_credit::SourceArenaCredit}
impl BuildHost{
 fn prepare_schema_inner(&mut self,request:crate::request::BuildRequest)->Result<Prepared,Box<dyn std::error::Error>>{let(outcome,inputs,diagnostics,credit)=crate::request_runner::prepare_schema_proposals(request,self)?;Ok(Prepared{outcome,inputs,diagnostics,_credit:credit})}
 fn schema_prepared<T>(&self,prepared:&Prepared,diagnostics:&mut impl std::io::Write,consume:impl FnOnce(&dq_analyze::captured_untyped_pages::schema_proposals::Data,&dq_analyze::captured_raw_file::Config,&Arc<dq_analyze::captured_generator_budget::Budget>)->std::io::Result<T>)->std::io::Result<T>{
  crate::daemon::control::checkpoint()?;
  let state=self.query_state.try_lock().map_err(|error|match error{std::sync::TryLockError::WouldBlock=>std::io::Error::new(std::io::ErrorKind::WouldBlock,"schema query state is already borrowed"),std::sync::TryLockError::Poisoned(_)=>std::io::Error::other("schema query state poisoned")})?;
  let snapshot=state.snapshot.as_ref().ok_or_else(||std::io::Error::new(std::io::ErrorKind::NotFound,"schema proposal has no actual semantic source"))?;snapshot.require_schema_capture_binding(&prepared.inputs)?;
  prepared.inputs.with_context(||{
   let current=||prepared.inputs.require_current().map_err(|error|match error.downcast::<std::io::Error>(){Ok(actual)=>*actual,Err(other)=>std::io::Error::other(other.to_string())});
   current()?;let pending=snapshot.with_original_schema_proposals_report_to(diagnostics,consume);if pending.is_err(){return pending}current()?;pending
  })
 }
 /// One genuine original request binds preparation, computation and delivery.
 /// Warm reuse is the host's normal graph reuse; no split token can reopen TLS.
 pub fn with_schema_proposals_to<T>(&mut self,request:crate::request::BuildRequest,diagnostics:&mut impl std::io::Write,consume:impl FnOnce(&dq_analyze::captured_untyped_pages::schema_proposals::Data,&dq_analyze::captured_raw_file::Config,&Arc<dq_analyze::captured_generator_budget::Budget>)->std::io::Result<T>)->Result<T,Box<dyn std::error::Error>>{
  use crate::daemon::{control,prepare_deadline};
  let requested=prepare_deadline::capture(request.command,request.timeout_seconds,std::time::Instant::now())?.ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidInput,"schema report requires original explicit deadline"))?;
  let _binding=if control::WorkerContext::capture_for_checkpoints().is_none(){if control::current_deadline().is_some(){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"schema cannot begin under publication masking").into())}Some(control::bind_with_deadline(control::Cancellation::default(),requested))}else{if control::current_deadline().is_none_or(|deadline|deadline>requested){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"schema cannot extend inherited request deadline").into())}None};
  control::checkpoint()?;let mut prepared=self.prepare_schema_inner(request)?;prepared.inputs.require_current()?;if let Some(stage)=prepared.diagnostics.take(){stage.publish(diagnostics)?;}self.schema_prepared(&prepared,diagnostics,consume).map_err(Into::into)
 }
 pub fn write_schema_proposals_to(&mut self,request:crate::request::BuildRequest,diagnostics:&mut impl std::io::Write,output:&mut impl std::io::Write)->Result<usize,Box<dyn std::error::Error>>{
  self.with_schema_proposals_to(request,diagnostics,|data,_,budget|{data.write_text(&||{budget.require().map_err(|m|std::io::Error::new(std::io::ErrorKind::OutOfMemory,m))?;crate::daemon::control::checkpoint()},output)?;Ok(data.rows().len())})
 }
 pub(crate) fn stage_schema_proposals(&mut self,request:crate::request::BuildRequest)->Result<SchemaReport,Box<dyn std::error::Error>>{
  crate::daemon::control::checkpoint()?;if crate::daemon::control::current_deadline().is_none()||crate::daemon::control::WorkerContext::capture_for_checkpoints().is_none(){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"schema staging requires its active original request").into())}
  let workspace=request.policy_inputs.as_ref().and_then(|p|p.workspace.as_ref()).ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidInput,"schema actual workspace absent"))?;
  let cache=request.cache_root.as_ref().ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidInput,"schema requires explicit cache root"))?;
  let credit=self.source_arena_work().reserve(workspace.root.as_os_str().len().checked_add(cache.as_os_str().len()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(8192)).ok_or_else(||std::io::Error::from(std::io::ErrorKind::OutOfMemory))?)?;
  let root=workspace.root.clone();let mut report=crate::selected_report_spool::Stage::new(cache)?;
  let mut prepared=self.prepare_schema_inner(request)?;
  let count=self.schema_prepared(&prepared,&mut std::io::sink(),|data,_,budget|{data.write_text(&||{budget.require().map_err(|m|std::io::Error::new(std::io::ErrorKind::OutOfMemory,m))?;crate::daemon::control::checkpoint()},&mut report)?;Ok(data.rows().len())})?;
  let frame=crate::daemon::selected_report_wire::Frame::from_prepared(&prepared.outcome)?.observation_data();
  let diagnostics=prepared.diagnostics.take();
  let report=report.seal()?.validate(crate::request_runner::schema_capture::drain)?.0;prepared.inputs.require_current()?;
  Ok(SchemaReport{root,inputs:prepared.inputs,frame,count,diagnostics,report,_credit:credit,_prepare_credit:prepared._credit})
 }
}
