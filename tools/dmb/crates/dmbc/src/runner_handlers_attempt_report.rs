//! Scoped real-attempt report delivery; failed source is never a cached source.
use super::BuildHost;
use crate::{request::{BuildRequest,BuildOutcome,BuildCommand},policy_request::{AnalysisContext,WorkspaceAuxiliaryQuestion as Q}};
use dq_analyze::{captured_sem_handlers::Data,captured_raw_file::Config};
use std::io;
/// Separate the unchanged actual preparation result from later raw-report or
/// callback IO. A report on a failed root does not make compilation successful.
#[derive(Debug)]pub struct HandlersAttemptReport<R>{
 pub preparation:Result<BuildOutcome,Box<dyn std::error::Error>>,
 pub report:Option<io::Result<R>>,
}
struct Sink<R,F>{consume:Option<F>,report:Option<io::Result<R>>}
impl<R,F:FnOnce(&Data,&Config)->io::Result<R>> crate::request_runner::HandlersFailureReportSink for Sink<R,F>{
 fn consume_budget(&mut self,data:&Data,config:&Config,_:&std::sync::Arc<dq_analyze::captured_generator_budget::Budget>){
  let Some(consume)=self.consume.take()else{self.failed(io::Error::new(io::ErrorKind::InvalidInput,"one-shot Handlers callback was repeated"));return};self.report=Some(consume(data,config));
 }
 fn failed(&mut self,error:io::Error){if self.report.as_ref().is_none_or(|r|r.is_ok()){self.report=Some(Err(error))}}
}
impl BuildHost{
 /// Run the SAME real preparation factory. Genuine complete preparation uses
 /// the existing current report child; only its own authenticated failed-root
 /// branch may produce a one-shot raw report. No full source snapshot is installed by that failure.
 /// Structural child facts still require the exact partial owner and operation. The callback is scoped and cannot
 /// return borrowed report/config data or source authority.
 pub fn with_handlers_attempt_report<R>(&mut self,request:BuildRequest,consume:impl FnOnce(&Data,&Config)->io::Result<R>)->io::Result<HandlersAttemptReport<R>>{
  self.with_handlers_attempt_report_to(request,&mut crate::daemon::stderr_writer(),consume)
 }
 pub fn with_handlers_attempt_report_to<R>(&mut self,request:BuildRequest,diagnostics:&mut impl std::io::Write,consume:impl FnOnce(&Data,&Config)->io::Result<R>)->io::Result<HandlersAttemptReport<R>>{
  self.with_handlers_attempt_report_source(request,None,diagnostics,consume)
 }
 /// Embedding clients may lend their actual input provider for this operation. The
 /// real recorder, preflight, parser, counters and freshness checks are unchanged.
 pub fn with_handlers_attempt_report_from_to<R>(&mut self,request:BuildRequest,provider:&(dyn crate::input_snapshot::SnapshotProvider+Sync),diagnostics:&mut impl std::io::Write,consume:impl FnOnce(&Data,&Config)->io::Result<R>)->io::Result<HandlersAttemptReport<R>>{
  self.with_handlers_attempt_report_source(request,Some(provider),diagnostics,consume)
 }
 pub fn with_handlers_attempt_report_from<R>(&mut self,request:BuildRequest,provider:&(dyn crate::input_snapshot::SnapshotProvider+Sync),consume:impl FnOnce(&Data,&Config)->io::Result<R>)->io::Result<HandlersAttemptReport<R>>{
  self.with_handlers_attempt_report_from_to(request,provider,&mut crate::daemon::stderr_writer(),consume)
 }
 fn with_handlers_attempt_report_source<R>(&mut self,request:BuildRequest,provider:Option<&(dyn crate::input_snapshot::SnapshotProvider+Sync)>,diagnostics:&mut impl std::io::Write,consume:impl FnOnce(&Data,&Config)->io::Result<R>)->io::Result<HandlersAttemptReport<R>>{
  let invalid=||io::Error::new(io::ErrorKind::InvalidInput,"Handlers attempt report requires exact Original Analyze workspace purpose");
  if !self.retains_artifacts()||request.command!=BuildCommand::PrepareQuery||!request.project.is_absolute()||!request.defines.is_empty()||request.engine_template.is_some()||request.bootstrap_catalog{return Err(invalid())}
  let intent=request.policy_inputs.as_ref().ok_or_else(invalid)?.clone().admit().map_err(io::Error::other)?;
  if intent.analysis_context()!=Some(AnalysisContext::OriginalAnalyze0290)||intent.workspace_auxiliary()!=[Q::SemHandlers]||!intent.workspace_generators().is_empty()||!intent.files().is_empty()||!intent.search_folders().is_empty(){return Err(invalid())}
  let mut sink=Sink{consume:Some(consume),report:None};let mut output=crate::request_runner::PreparationDiagnosticOutput::captured(diagnostics);let preparation=crate::request_runner::run_build_with_host_and_policy_sinks_from(request.clone(),self,None,Some(&mut sink),&mut output,provider);if let Some(error)=output.take_error(){crate::request_runner::HandlersFailureReportSink::failed(&mut sink,error)}drop(output);
  if let Ok(prepared)=&preparation{
   if sink.report.as_ref().is_some_and(|r|r.is_ok()){return Err(io::Error::new(io::ErrorKind::InvalidData,"failed-attempt report cannot accompany successful preparation"))}
   if sink.report.is_none(){let consume=sink.consume.take().ok_or_else(invalid)?;sink.report=Some(self.with_prepared_handlers_report_to(&request,prepared,diagnostics,consume));}
  }
  Ok(HandlersAttemptReport{preparation,report:sink.report})
 }
}

pub(crate) struct FundedHandlersAttemptReport{
 pub(crate) preparation:Result<BuildOutcome,Box<dyn std::error::Error>>,
 pub(crate) report:Option<io::Result<dq_analyze::policy_finish::admitted::Text>>,
 pub(crate) credit:dm_preprocess::source_arena_credit::SourceArenaCredit,
}
type Budget=dq_analyze::captured_generator_budget::Budget;
type Text=dq_analyze::policy_finish::admitted::Text;

struct OutputSink<'a,F>{sink:Sink<Text,F>,queries:&'a crate::query_db::QueryDb,credit:&'a dm_preprocess::source_arena_credit::SourceArenaControlCredit}
impl<F:FnOnce(&Data,&Config,bool,&dyn dq_analyze::policy_finish::admitted::Work)->io::Result<Text>> crate::request_runner::HandlersFailureReportSink for OutputSink<'_,F>{
 fn consume_budget(&mut self,data:&Data,config:&Config,budget:&std::sync::Arc<Budget>){
  let Some(consume)=self.sink.consume.take()else{self.failed(io::Error::new(io::ErrorKind::InvalidData,"funded handlers callback repeated"));return};
  self.sink.report=Some(self.queries.with_report_output_work_locked(self.credit,budget,|work|consume(data,config,false,work)));
 }
 fn failed(&mut self,error:io::Error){if self.sink.report.as_ref().is_none_or(|r|r.is_ok()){self.sink.report=Some(Err(error))}}
}
impl BuildHost{
 pub(crate) fn with_funded_handlers_attempt_report_to(&mut self,request:BuildRequest,provider:Option<&(dyn crate::input_snapshot::SnapshotProvider+Sync)>,diagnostics:&mut impl std::io::Write,consume:impl FnOnce(&Data,&Config,bool,&dyn dq_analyze::policy_finish::admitted::Work)->io::Result<Text>)->io::Result<FundedHandlersAttemptReport>{
  let invalid=||io::Error::new(io::ErrorKind::InvalidInput,"funded handlers report requires exact Original Analyze purpose");
  if !self.retains_artifacts()||request.command!=BuildCommand::PrepareQuery||!request.project.is_absolute()||!request.defines.is_empty()||request.engine_template.is_some()||request.bootstrap_catalog||request.record_inputs.is_some()||request.replay_inputs.is_some()||request.trace_path.is_some()||request.artifact_directory.is_some()||request.output_store.is_some()||request.source_questions.is_some()||request.diagnostic_declarations{return Err(invalid())}
  let intent=request.policy_inputs.as_ref().ok_or_else(invalid)?.clone().admit().map_err(io::Error::other)?;
  if intent.analysis_context()!=Some(AnalysisContext::OriginalAnalyze0290)||intent.workspace_auxiliary()!=[Q::SemHandlers]||!intent.workspace_generators().is_empty()||!intent.files().is_empty()||!intent.search_folders().is_empty(){return Err(invalid())}
  let credit=self.source_arena_work().reserve(4096)?;let control=credit.control();let queries=std::sync::Arc::clone(self.query_db());
  let mut sink=OutputSink{sink:Sink{consume:Some(consume),report:None},queries:queries.as_ref(),credit:&control};
  let mut output=crate::request_runner::PreparationDiagnosticOutput::captured(diagnostics);
  let preparation=crate::request_runner::run_build_with_host_and_policy_sinks_from(request.clone(),self,None,Some(&mut sink),&mut output,provider);
  if let Some(error)=output.take_error(){crate::request_runner::HandlersFailureReportSink::failed(&mut sink,error)}drop(output);
  if let Ok(prepared)=&preparation{
   if sink.sink.report.as_ref().is_some_and(|r|r.is_ok()){return Err(io::Error::new(io::ErrorKind::InvalidData,"failed handlers report accompanied successful preparation"))}
   if sink.sink.report.is_none(){
    let consume=sink.sink.consume.take().ok_or_else(invalid)?;
    sink.sink.report=Some(self.with_prepared_handlers_report_budget_to(&request,prepared,diagnostics,|data,config,budget|queries.with_report_output_work_locked(&control,budget,|work|consume(data,config,true,work))));
   }
  }
  let report=sink.sink.report.take();drop(sink);drop(control);drop(queries);
  Ok(FundedHandlersAttemptReport{preparation,report,credit})
 }
}
