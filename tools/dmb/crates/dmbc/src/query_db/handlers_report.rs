//! Whole Handler report over authentic partial and independently demanded full
//! source children. One family gate and one root Budget fund all three phases.
use super::*;
use crate::runner_host::{workspace_capture::WorkspaceCapture,query_snapshot::workspace_native_guard::NativeReadGuard};
use super::workspace::{SelectedHandlerFiles,WorkspaceCodeReader};
use dq_analyze::{captured_allow_annotations::full_unused::SelectedTreePlanData,captured_generator_budget::Budget,captured_reactive_reads::Failure,captured_sem_handlers::{Builder,Data}};
use crate::{input_snapshot::HandlerPreparedCapture,request_runner::runner_freshness::HandlerPolicyAdmission};
#[path="handlers_original_file.rs"]mod original_file;
fn actual(error:Failure)->io::Error{match error{Failure::Operational(error)=>error,Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)}}
fn checkpoint(b:&Budget)->Result<(),Failure>{crate::daemon::control::checkpoint()?;b.require().map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))}
struct Funding{budget:Arc<Budget>,done:bool}impl Drop for Funding{fn drop(&mut self){if !self.done{self.budget.keep_failed_scratch()}}}
fn with_handler_report_file(
 subject:&crate::input_snapshot::HandlerStructuralSubject,mapping:&dm_tree::frontend::SourceExportMapping,
 budget:&Arc<Budget>,selected:Option<&SelectedHandlerFiles<'_,'_,'_>>,relative:&str,
 visit:&mut dyn FnMut(Option<dq_analyze::captured_raw_file::RawPolicyViews<'_>>)->Result<(),Failure>,
)->Result<(),Failure>{
 match selected{
  Some(files)=>files.with_file(relative,visit),
  None=>original_file::with_actual_file(subject,mapping,relative,budget,visit),
 }
}
fn require_current(queries:&QueryDb,capture:&Arc<HandlerPreparedCapture>,proof:&Arc<HandlerPolicyAdmission>)->Result<(),Failure>{capture.require_bound()?;if !Arc::ptr_eq(capture,proof.capture())||!capture.uses_queries(queries){return Err("whole handlers report current source/admission/query owner differs".into())}Ok(())}
impl QueryDb{
 fn collect_handler_partitions<T>(self:&Arc<Self>,capture:&Arc<HandlerPreparedCapture>,proof:&Arc<HandlerPolicyAdmission>,budget:&Arc<Budget>,full:Option<(&Arc<WorkspaceCapture>,&NativeReadGuard<'_>,&Arc<CapturedPolicyInputs>,&WorkspaceCodeReader<'_,'_>,Option<&SelectedTreePlanData>)>,consume:impl FnOnce(&Data,&Config,&Arc<Budget>)->io::Result<T>)->Result<T,Failure>{
  require_current(self,capture,proof)?;checkpoint(budget)?;
  let mut funding=Funding{budget:Budget::scoped_temporaries(budget).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?,done:false};
  let poll=||crate::daemon::control::checkpoint();let mut builder=Builder::new(&funding.budget,&poll)?;let subject=capture.prepared().subject();
  let selected=full.and_then(|(_,_,child,reader,plan)|plan.map(|plan|reader.handler_report_files(child.policy(),plan))).transpose()?;
  if let Some(staged)=capture.take_staged_rows()?{
   let files=selected.as_ref().ok_or("detached handler structural rows require full selected ALLOW files")?;
   staged.replay(self,capture.issuance(),capture.partial_revision()?,budget,|rule,relative,line,message|{
    builder.push(rule,relative,line,message,&mut|relative,visit|files.with_file(relative,visit)).map_err(actual)
   })?;
  }else{
   self.with_handlers_structural_budget_locked(capture,proof,budget,|data,_|{
    for row in data.rows(){let mapping=capture.structural_inputs()?.mapping();builder.push(row.rule,&row.relative,row.line,&row.message,&mut|relative,visit|with_handler_report_file(subject,mapping,budget,selected.as_ref(),relative,visit)).map_err(actual)?;}Ok(())
   })?;
  }
  if let Some((workspace,guard,full_capture,reader,selected_tree))=full.filter(|_|subject.requires_full_model()){
   self.with_handler_declarations_reader_locked(workspace,guard,full_capture,reader,selected_tree.is_some(),|data,_|{
    for row in data.sites(){builder.push(&row.rule,&row.rel,row.line,&row.msg,&mut|relative,visit|with_handler_report_file(subject,full_capture.policy().mapping(),budget,selected.as_ref(),relative,visit)).map_err(actual)?;}Ok(())
   })?;
  }
  let data=builder.finish()?;require_current(self,capture,proof)?;checkpoint(budget)?;
  let pending=consume(&data,subject.config(),budget);if pending.is_err(){return pending.map_err(Failure::Operational)}
  require_current(self,capture,proof)?;checkpoint(budget)?;drop(data);funding.done=true;pending.map_err(Failure::Operational)
 }
 /// Structural-only completion. This cannot invent a requested/full-unavailable
 /// source, semantic completeness, full-CODE closure, or ALLOW-unused union.
 pub(crate) fn with_handlers_structural_report<T>(self:&Arc<Self>,capture:&Arc<HandlerPreparedCapture>,proof:&Arc<HandlerPolicyAdmission>,consume:impl FnOnce(&Data,&Config,&Arc<Budget>)->io::Result<T>)->io::Result<T>{
  let produced=(||{require_current(self,capture,proof)?;if !proof.is_current(){return Err("failed handler proof cannot publish a current structural report".into())}if capture.prepared().subject().requires_full_model(){return Err("handler full partition is requested but not genuinely issued".into())}
   let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());self.raw_prune_locked(Instant::now());self.begin_result_admission_locked()?;
   let source=self.raw_source_input_charge_locked()?;let input=self.workspace_input_base_headroom_locked(source)?;let available=input.min(RESULT_BUDGET.saturating_sub(self.raw_policy.charge.load(Ordering::Acquire)));
   let root=Budget::new(available).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;self.collect_handler_partitions(capture,proof,&root,None,consume)
  })();produced.map_err(actual)
 }
 /// Real independently admitted full model; same current reader/budget owns
 /// partial structural and full declared/output child evaluation.
 pub(crate) fn with_handlers_full_report<T>(self:&Arc<Self>,capture:&Arc<HandlerPreparedCapture>,proof:&Arc<HandlerPolicyAdmission>,workspace:&Arc<WorkspaceCapture>,guard:&NativeReadGuard<'_>,full_capture:&Arc<CapturedPolicyInputs>,selected_tree:Option<&SelectedTreePlanData>,consume:impl FnOnce(&Data,&Config,&Arc<Budget>)->io::Result<T>)->io::Result<T>{
  let produced=(||{require_current(self,capture,proof)?;if !proof.is_current(){return Err("failed handler proof cannot publish a current full report".into())}let joined=crate::policy_request::WorkspaceAuxiliaryQuestion::is_private_handlers_domain(workspace.auxiliary());
   if !capture.prepared().subject().requires_full_model()&&!(joined&&selected_tree.is_some()){
    return Err("handler full partition was not requested".into());
   }if workspace.root()!=capture.root(){return Err("handler partial and full workspace roots differ".into())}
   if selected_tree.is_some()!=capture.prepared().subject().is_selected_full(){return Err("handler full report does not match the actual partial source purpose".into())}
   let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());self.raw_prune_locked(Instant::now());self.begin_result_admission_locked()?;
   self.with_workspace_code_pages_limit_locked(workspace,guard,None,|reader|self.collect_handler_partitions(capture,proof,reader.budget(),Some((workspace,guard,full_capture,reader,selected_tree)),consume))
  })();produced.map_err(actual)
 }
}

impl QueryDb{
 /// One-shot structural report after this SAME attempt's independently
 /// requested full root genuinely failed to open. This issues no cached source,
 /// full model, EOF or generic unavailable role and never accepts ErrorKind.
 pub(crate) fn with_handlers_failed_full_report<P:crate::input_snapshot::SnapshotProvider,T>(self:&Arc<Self>,inputs:&crate::input_snapshot::RecordingInputs<P>,capture:&Arc<HandlerPreparedCapture>,proof:&Arc<HandlerPolicyAdmission>,consume:impl FnOnce(&Data,&Config,&Arc<Budget>)->io::Result<T>)->io::Result<T>{
  let produced=(||{require_current(self,capture,proof)?;let failed=proof.failed_root().ok_or("handler failed report has no actual failed-full disposition")?;capture.require_failed_full_prefix(inputs,self,failed)?;
   let full=inputs.original_analysis_subject().ok_or("failed handler full report has no actual requested subject")?;
   if !capture.prepared().subject().requires_full_model()||failed.root()!=full.project()||!full.matches_workspace_root(capture.root()){return Err("failed handler full report has another actual root or unrequested partition".into())}
   capture.require_failed_full_prefix(inputs,self,failed)?;
   let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());self.raw_prune_locked(Instant::now());self.begin_result_admission_locked()?;
   let source=self.raw_source_input_charge_locked()?;let input=self.workspace_input_base_headroom_locked(source)?;let available=input.min(RESULT_BUDGET.saturating_sub(self.raw_policy.charge.load(Ordering::Acquire)));
   let budget=Budget::new(available).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;
   let answer=self.collect_handler_partitions(capture,proof,&budget,None,consume);if matches!(&answer,Err(Failure::Operational(_))){return answer}failed.require_recording(inputs,self)?;capture.require_failed_full_prefix(inputs,self,failed)?;answer
  })();produced.map_err(actual)
 }
}
