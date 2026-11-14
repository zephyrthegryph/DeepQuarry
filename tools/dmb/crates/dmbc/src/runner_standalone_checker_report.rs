//! Actual resident Checker staging on the SAME retained host and source ledger.
use super::*;use std::{error::Error,io,path::PathBuf};
pub(crate) struct StandaloneCheckerReport{pub(crate)project:PathBuf,pub(crate)outcome:crate::native_checker::Outcome,pub(crate)inputs:crate::request_runner::checker_capture::Inputs,pub(crate)diagnostics:Option<crate::selected_report_spool::Verified>,pub(crate)output:crate::selected_report_spool::Verified,pub(crate)_credit:dm_preprocess::source_arena_credit::SourceArenaCredit}
impl BuildHost{
 pub(crate) fn stage_standalone_checker(&mut self,build:crate::request::BuildRequest,display:PathBuf,configuration:Option<PathBuf>,json:bool)->Result<StandaloneCheckerReport,Box<dyn Error>>{
  if !self.retains_artifacts(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"Checker requires the existing retained host").into())}
  crate::daemon::control::checkpoint()?;
  let cache=build.cache_root.as_ref().ok_or_else(||io::Error::other("Checker stage cache absent"))?;
  let width=cache.as_os_str().len().checked_add(build.project.as_os_str().len()).and_then(|n|n.checked_add(display.as_os_str().len())).and_then(|n|n.checked_add(configuration.as_ref().map_or(0,|p|p.as_os_str().len()))).and_then(|n|n.checked_mul(32)).and_then(|n|n.checked_add(65536+std::mem::size_of::<StandaloneCheckerReport>())).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
  let credit=self.source_arena_work().reserve(width)?;crate::native_checker::require_prepared_shape(&build,&display,configuration.as_deref())?;
  let project=build.project.clone();let mut diagnostics=crate::selected_report_spool::Stage::new(cache)?;let mut output=crate::selected_report_spool::Stage::new(cache)?;
  let(outcome,inputs)=crate::native_checker::run_prepared_with_json(build,&display,configuration.as_deref(),json,self,&mut output,&mut diagnostics)?;
  inputs.require_current(&project)?;let diagnostics=if diagnostics.length()==0{None}else{Some(super::query_snapshot::checked_selected_report_stage(diagnostics)?)};let output=super::query_snapshot::checked_selected_report_stage(output)?;inputs.require_current(&project)?;crate::daemon::control::checkpoint()?;
  Ok(StandaloneCheckerReport{project,outcome,inputs,diagnostics,output,_credit:credit})
 }
}
