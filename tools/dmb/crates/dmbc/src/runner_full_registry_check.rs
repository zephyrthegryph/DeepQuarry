//! Read-only full-registry Analyze demand on the existing native preparation.
//! It produces no strict compile, output pair, DMB or RSC. Ordinary defaults
//! remain unchanged; the real native Checker transcript is a semantic child,
//! not an extra Analyze finding/verdict or public Checker output.
use super::BuildHost;
use std::{error::Error,io::{self,Write}};
pub use dq_analyze::full_registry_check_wire::Options as FullRegistryCheckOptions;
pub(crate) struct FullRegistryCheckReport{
 pub(crate) project:std::path::PathBuf,
 pub(crate) inputs:crate::request_runner::JoinedSelectedInputs,
 pub(crate) frame:crate::daemon::selected_report_wire::Frame,
 pub(crate) format:FullRegistryCheckOptions,pub(crate) clean:bool,
 pub(crate) diagnostics:Option<crate::selected_report_spool::Verified>,
 pub(crate) report:crate::selected_report_spool::Verified,
 pub(crate) _credit:dm_preprocess::source_arena_credit::SourceArenaCredit,
}
impl BuildHost{
 /// Caller must buffer/discard partial delivery on an error. Source evidence
 /// is revalidated on both sides; no failed attempt claims report completion.
 pub fn write_full_registry_check(&mut self,request:crate::request::BuildRequest,options:FullRegistryCheckOptions,
  diagnostics:&mut impl Write,report:&mut impl Write)->Result<bool,Box<dyn Error>>{
  use crate::daemon::{control,prepare_deadline};
  let requested=prepare_deadline::capture(request.command,request.timeout_seconds,std::time::Instant::now())?
   .ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"full registry check requires its original explicit deadline"))?;
  let _binding=if control::WorkerContext::capture_for_checkpoints().is_none(){
   if control::current_deadline().is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"full registry check cannot begin during publication").into())}
   Some(control::bind_with_deadline(control::Cancellation::default(),requested))
  }else{if control::current_deadline().is_none_or(|deadline|deadline>requested){return Err(io::Error::new(io::ErrorKind::InvalidInput,"full registry check cannot extend an inherited request").into())}None};
  control::checkpoint()?;
  let completed=self.stage_full_registry_check_report(request,options)?;
  let FullRegistryCheckReport{project,inputs,clean,diagnostics:diagnostics_stage,report:report_stage,_credit,..}=completed;
  inputs.require_report_current(&project)?;
  if let Some(stage)=diagnostics_stage{stage.publish(diagnostics)?;}
  report_stage.publish(report)?;
  inputs.require_report_current(&project)?;control::checkpoint()?;Ok(clean)
 }
 pub(crate) fn stage_full_registry_check_report(&mut self,request:crate::request::BuildRequest,options:FullRegistryCheckOptions)->Result<FullRegistryCheckReport,Box<dyn Error>>{
  crate::daemon::control::checkpoint()?;
  if crate::daemon::control::current_deadline().is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"report-only demand needs its actual bound original request deadline").into())}
  let project=crate::policy_request::canonical_analysis_project(&request.project,Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;
  let(inputs,frame,clean,diagnostics,checker,report,credit)=self.stage_full_registry_report_using(request,false,!options.raw,Some(options))?;
  drop(checker);inputs.require_report_current(&project)?;
  Ok(FullRegistryCheckReport{project,inputs,frame,format:options,clean,diagnostics,report,_credit:credit})
 }

}
