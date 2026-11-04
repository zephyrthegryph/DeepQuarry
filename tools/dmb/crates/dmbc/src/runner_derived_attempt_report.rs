//! Scoped real-attempt report delivery; failed source is never a cached source.
use super::BuildHost;
use crate::{request::{BuildRequest,BuildOutcome,BuildCommand},policy_request::{AnalysisContext,WorkspaceAuxiliaryQuestion as Q}};
use dq_analyze::{captured_derived_reads::DerivedReadData,captured_raw_file::Config};
use std::io;
/// Separate the unchanged actual preparation result from later raw-report or
/// callback IO. A report on a failed root does not make compilation successful.
#[derive(Debug)]pub struct DerivedAttemptReport<R>{
 pub preparation:Result<BuildOutcome,Box<dyn std::error::Error>>,
 pub report:Option<io::Result<R>>,
}
struct Sink<R,F>{consume:Option<F>,report:Option<io::Result<R>>}
impl<R,F:FnOnce(&DerivedReadData,&Config)->io::Result<R>> crate::request_runner::DerivedFailureReportSink for Sink<R,F>{
 fn consume(&mut self,data:&DerivedReadData,config:&Config){
  let Some(consume)=self.consume.take()else{self.failed(io::Error::new(io::ErrorKind::InvalidInput,"one-shot Derived callback was repeated"));return};self.report=Some(consume(data,config));
 }
 fn failed(&mut self,error:io::Error){if self.report.as_ref().is_none_or(|r|r.is_ok()){self.report=Some(Err(error))}}
}
impl BuildHost{
 /// Run the SAME real preparation factory. Genuine complete preparation uses
 /// the existing current report child; only its own authenticated failed-root
 /// branch may produce a one-shot raw report. Nothing is installed in a warm
 /// source/result cache by that failure. The callback is scoped and cannot
 /// return borrowed report/config data or source authority.
 pub fn with_derived_attempt_report<R>(&mut self,request:BuildRequest,consume:impl FnOnce(&DerivedReadData,&Config)->io::Result<R>)->io::Result<DerivedAttemptReport<R>>{
  self.with_derived_attempt_report_to(request,&mut crate::daemon::stderr_writer(),consume)
 }
 pub fn with_derived_attempt_report_to<R>(&mut self,request:BuildRequest,diagnostics:&mut impl std::io::Write,consume:impl FnOnce(&DerivedReadData,&Config)->io::Result<R>)->io::Result<DerivedAttemptReport<R>>{
  self.with_derived_attempt_report_source(request,None,diagnostics,consume)
 }
 /// Embedding clients may lend their actual input provider for this operation. The
 /// real recorder, preflight, parser, counters and freshness checks are unchanged.
 pub fn with_derived_attempt_report_from_to<R>(&mut self,request:BuildRequest,provider:&(dyn crate::input_snapshot::SnapshotProvider+Sync),diagnostics:&mut impl std::io::Write,consume:impl FnOnce(&DerivedReadData,&Config)->io::Result<R>)->io::Result<DerivedAttemptReport<R>>{
  self.with_derived_attempt_report_source(request,Some(provider),diagnostics,consume)
 }
 pub fn with_derived_attempt_report_from<R>(&mut self,request:BuildRequest,provider:&(dyn crate::input_snapshot::SnapshotProvider+Sync),consume:impl FnOnce(&DerivedReadData,&Config)->io::Result<R>)->io::Result<DerivedAttemptReport<R>>{
  self.with_derived_attempt_report_from_to(request,provider,&mut crate::daemon::stderr_writer(),consume)
 }
 fn with_derived_attempt_report_source<R>(&mut self,request:BuildRequest,provider:Option<&(dyn crate::input_snapshot::SnapshotProvider+Sync)>,diagnostics:&mut impl std::io::Write,consume:impl FnOnce(&DerivedReadData,&Config)->io::Result<R>)->io::Result<DerivedAttemptReport<R>>{
  let invalid=||io::Error::new(io::ErrorKind::InvalidInput,"Derived attempt report requires exact Original Analyze workspace purpose");
  if !self.retains_artifacts()||request.command!=BuildCommand::PrepareQuery||!request.project.is_absolute()||!request.defines.is_empty()||request.engine_template.is_some()||request.bootstrap_catalog{return Err(invalid())}
  let intent=request.policy_inputs.as_ref().ok_or_else(invalid)?.clone().admit().map_err(io::Error::other)?;
  if intent.analysis_context()!=Some(AnalysisContext::OriginalAnalyze0290)||intent.workspace_auxiliary()!=[Q::DerivedReads]||!intent.workspace_generators().is_empty()||!intent.files().is_empty()||!intent.search_folders().is_empty(){return Err(invalid())}
  let mut sink=Sink{consume:Some(consume),report:None};let mut output=crate::request_runner::PreparationDiagnosticOutput::captured(diagnostics);let preparation=crate::request_runner::run_build_with_host_and_derived_sink_from(request.clone(),self,Some(&mut sink),&mut output,provider);if let Some(error)=output.take_error(){crate::request_runner::DerivedFailureReportSink::failed(&mut sink,error)}drop(output);
  if let Ok(prepared)=&preparation{
   if sink.report.as_ref().is_some_and(|r|r.is_ok()){return Err(io::Error::new(io::ErrorKind::InvalidData,"failed-attempt report cannot accompany successful preparation"))}
   if sink.report.is_none(){let consume=sink.consume.take().ok_or_else(invalid)?;sink.report=Some(self.with_prepared_derived_report_to(&request,prepared,diagnostics,consume));}
  }
  Ok(DerivedAttemptReport{preparation,report:sink.report})
 }
}
