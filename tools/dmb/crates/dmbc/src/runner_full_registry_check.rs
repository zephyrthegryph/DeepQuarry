//! Report-only native Analyze requests on the existing retained graph.
//! Ordinary defaults remain unchanged until actual whole qualification.
use super::BuildHost;use std::{error::Error,io::{self,Write}};
pub use dq_analyze::full_registry_check_wire::Options as FullRegistryCheckOptions;
pub(crate) enum FullRegistryCheckInputs{
 Model(crate::request_runner::JoinedSelectedInputs),
 SelectedModel(crate::request_runner::checker_capture::Inputs),
 Source(crate::request_runner::native_check_source::NativeSourceCheckInputs),
 Handlers(crate::request_runner::native_check_handlers::Inputs),
}
impl FullRegistryCheckInputs{pub(crate) fn require_report_current(&self,project:&std::path::Path)->Result<(),Box<dyn Error>>{match self{Self::Model(inputs)=>inputs.require_report_current(project),Self::SelectedModel(inputs)=>inputs.require_current(project),Self::Source(inputs)=>inputs.require_current(project).map_err(Into::into),Self::Handlers(inputs)=>inputs.require_current(project).map_err(Into::into)}}}
pub(crate) struct FullRegistryCheckReport{
 pub(crate) project:std::path::PathBuf,pub(crate) inputs:FullRegistryCheckInputs,
 pub(crate) frame:dq_analyze::full_registry_check_wire::CheckFrame,
 pub(crate) selection:dq_analyze::full_registry_check_selection_wire::SelectionBinding,
 pub(crate) selected:u64,pub(crate) registered:u64,
 pub(crate) format:FullRegistryCheckOptions,pub(crate) clean:bool,
 pub(crate) diagnostics:Option<crate::selected_report_spool::Verified>,pub(crate) report:crate::selected_report_spool::Verified,
 pub(crate) _credit:dm_preprocess::source_arena_credit::SourceArenaCredit,
}
fn with_full_registry_check_context<T>(command:crate::request::BuildCommand,timeout_seconds:Option<u16>,run:impl FnOnce()->Result<T,Box<dyn Error>>)->Result<T,Box<dyn Error>>{
  use crate::daemon::{control,prepare_deadline};
  let requested=prepare_deadline::capture(command,timeout_seconds,std::time::Instant::now())?
   .ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"full registry check requires its original explicit deadline"))?;
  let _binding=if control::WorkerContext::capture_for_checkpoints().is_none(){
   if control::current_deadline().is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"full registry check cannot begin during publication").into())}
   Some(control::bind_with_deadline(control::Cancellation::default(),requested))
  }else{if control::current_deadline().is_none_or(|deadline|deadline>requested){return Err(io::Error::new(io::ErrorKind::InvalidInput,"full registry check cannot extend an inherited request").into())}None};
  control::checkpoint()?;
  run()
}
impl BuildHost{
 fn stage_registered_model_check_report(&mut self,mut request:crate::request::BuildRequest,plan:std::sync::Arc<super::NativeCheckSelection>)->Result<FullRegistryCheckReport,Box<dyn Error>>{
  let(root,cache,project,retained,credit)=self.prepare_registered_check_request(&mut request,&plan)?;let mut diagnostics=crate::selected_report_spool::Stage::new(&cache)?;let mut checker_stage=if plan.needs_checker(){Some(crate::selected_report_spool::Stage::new(&cache)?)}else{None};let report=crate::selected_report_spool::Stage::new(&cache)?;
  let(prepared,inputs,checker)=crate::request_runner::native_check_source::prepare_registered_model_check(request,self,std::sync::Arc::clone(&plan),&mut diagnostics,checker_stage.as_mut())?;
  let(clean,report,frame)={let state=self.query_state.try_lock().map_err(|_|io::Error::new(io::ErrorKind::WouldBlock,"selected model state is borrowed"))?;let snapshot=state.snapshot.as_ref().ok_or_else(||io::Error::other("selected model snapshot absent"))?;snapshot.require_registered_model_inputs(&inputs,&project,&plan)?;inputs.require_current(&project)?;
   let handlers=if plan.needs_handlers(){Some(state.handlers_snapshot.as_ref().ok_or_else(||io::Error::other("selected handler dependency absent"))?)}else{None};let(clean,report)=snapshot.stage_selected_registry_model_check(&prepared,&retained,&root,report,&plan,checker.as_ref(),handlers)?;snapshot.require_registered_model_inputs(&inputs,&project,&plan)?;inputs.require_current(&project)?;let frame=crate::daemon::selected_report_wire::Frame::from_prepared(&prepared)?.observation_data().into();(clean,report,frame)};
  let diagnostics=if diagnostics.length()==0{None}else{Some(crate::request_runner::native_check_handlers::check_diagnostic_stage(diagnostics)?)};drop(checker_stage);crate::daemon::control::checkpoint()?;
  Ok(FullRegistryCheckReport{project,inputs:FullRegistryCheckInputs::SelectedModel(inputs),frame,selection:plan.binding(),selected:u64::try_from(plan.names().len()).map_err(|_|io::Error::from(io::ErrorKind::InvalidData))?,registered:u64::try_from(plan.registered_count()?).map_err(|_|io::Error::from(io::ErrorKind::InvalidData))?,format:plan.format(),clean,diagnostics,report,_credit:credit})
 }

 fn prepare_registered_check_request(&self,request:&mut crate::request::BuildRequest,plan:&std::sync::Arc<super::NativeCheckSelection>)->Result<(std::path::PathBuf,std::path::PathBuf,std::path::PathBuf,std::sync::Arc<dq_analyze::captured_generator_budget::Budget>,dm_preprocess::source_arena_credit::SourceArenaCredit),Box<dyn Error>>{
  use dq_analyze::captured_generator_budget::Budget;
  let namespace=request.policy_inputs.as_ref().and_then(|input|input.workspace.as_ref()).ok_or_else(super::original_exclusions_invalid)?;let cache_path=request.cache_root.as_deref().ok_or_else(super::original_exclusions_invalid)?;
  let metadata=plan.roots().iter().try_fold(0usize,|total,(directory,_)|total.checked_add(directory.len()).and_then(|n|n.checked_add(namespace.root.as_os_str().len())).and_then(|n|n.checked_add(1))).and_then(|n|n.checked_add(namespace.root.as_os_str().len())).and_then(|n|n.checked_add(cache_path.as_os_str().len())).and_then(|n|n.checked_mul(64)).and_then(|n|n.checked_add(64*1024)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
  let credit=self.source_arena_work().reserve(super::SELECTED_REPORT_RETAINED.checked_add(metadata).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?)?;
  let(root,cache)=Self::native_registry_check_paths(&request)?;
  let workspace=request.policy_inputs.as_mut().and_then(|input|input.workspace.as_mut()).ok_or_else(super::original_exclusions_invalid)?;
  workspace.recursive_roots.clear();
  for(directory,_)in plan.roots(){crate::daemon::control::checkpoint()?;let path=root.join(directory);if !workspace.recursive_roots.contains(&path){workspace.recursive_roots.try_reserve(1).map_err(|_|io::Error::from(io::ErrorKind::OutOfMemory))?;workspace.recursive_roots.push(path)}}
  let project=crate::policy_request::canonical_analysis_project(&request.project,Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;
  let retained=Budget::new(super::SELECTED_REPORT_RETAINED).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;
  let intent=request.policy_inputs.as_mut().ok_or_else(super::original_exclusions_invalid)?;intent.workspace_auxiliary.clear();if !plan.source_only(){for question in plan.questions(){intent.workspace_auxiliary.try_reserve(1).map_err(|_|io::Error::from(io::ErrorKind::OutOfMemory))?;intent.workspace_auxiliary.push(question)}}
  Ok((root,cache,project,retained,credit))
 }

 /// Wire preflight validates only the declared neutral namespace, without
 /// opening unselected source roots. The actual selected acquisition repeats
 /// admission against registry-derived roots under native storage credit.
 pub(crate) fn native_registry_check_paths(request:&crate::request::BuildRequest)->io::Result<(std::path::PathBuf,std::path::PathBuf)>{
  use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
  let roots=Q::authored_doc_ui_roots(Q::PRIVATE_FULL_REGISTRY).ok_or_else(super::original_exclusions_invalid)?;
  let(workspace,cache)=super::original_exclusions_shape(request,roots)?;if request.warnings!=crate::diagnostics::WarningPolicy::default(){return Err(super::original_exclusions_invalid())}
  if workspace.recursive_roots.iter().zip(roots).any(|(actual,expected)|*actual!=workspace.root.join(expected))||workspace.configuration!=workspace.root.join("tools/ci/lint_scopes.toml"){return Err(super::original_exclusions_invalid())}
  let root=std::fs::canonicalize(&workspace.root)?;let physical_cache=std::fs::canonicalize(cache)?;
  if root!=workspace.root||!physical_cache.is_dir()||physical_cache.starts_with(&root)||dm_preprocess::regions::canonical_path(&request.project)!=root.join("deepquarry.dme"){return Err(super::original_exclusions_invalid())}
  Ok((root,physical_cache))
 }
 fn stage_source_registry_check_report(&mut self,mut request:crate::request::BuildRequest,plan:std::sync::Arc<super::NativeCheckSelection>)->Result<FullRegistryCheckReport,Box<dyn Error>>{
  use dq_analyze::captured_generator_budget::Budget;
  if !self.retains_artifacts()||!plan.source_only(){return Err(super::original_exclusions_invalid().into())}
  let(root,cache,project,retained,credit)=self.prepare_registered_check_request(&mut request,&plan)?;
  let stage=crate::selected_report_spool::Stage::new(&cache)?;
  let(prepared,snapshot,inputs)=crate::request_runner::native_check_source::prepare_registered_source_check(request,self,std::sync::Arc::clone(&plan))?;
  inputs.require_binding(&snapshot,&plan)?;inputs.require_current(&project)?;
  let(clean,report)=snapshot.stage_selected_registry_source_check(&prepared,&retained,&root,stage,&plan)?;
  inputs.require_binding(&snapshot,&plan)?;inputs.require_current(&project)?;crate::daemon::control::checkpoint()?;
  let frame=dq_analyze::full_registry_check_wire::CheckFrame::Source{query_revision:dq_analyze::selected_exclusions_wire::Hex128(snapshot.revision()),source_revision:dq_analyze::selected_exclusions_wire::Hex128(snapshot.source_revision()),policy_revision:dq_analyze::selected_exclusions_wire::Hex128(snapshot.policy_revision())};
  let selected=u64::try_from(plan.names().len()).map_err(|_|io::Error::from(io::ErrorKind::InvalidData))?;let registered=u64::try_from(plan.registered_count()?).map_err(|_|io::Error::from(io::ErrorKind::InvalidData))?;
  Ok(FullRegistryCheckReport{project,inputs:FullRegistryCheckInputs::Source(inputs),frame,selection:plan.binding(),selected,registered,format:plan.format(),clean,diagnostics:None,report,_credit:credit})
 }

 pub fn write_full_registry_check(&mut self,request:crate::request::BuildRequest,options:FullRegistryCheckOptions,diagnostics:&mut impl Write,report:&mut impl Write)->Result<bool,Box<dyn Error>>{
  self.write_selected_registry_check(request,options,&[],diagnostics,report)
 }
 /// Partial delivery is not completion: callers buffer/discard on error.
 pub fn write_selected_registry_check(&mut self,request:crate::request::BuildRequest,options:FullRegistryCheckOptions,selectors:&[String],diagnostics:&mut impl Write,report:&mut impl Write)->Result<bool,Box<dyn Error>>{
  with_full_registry_check_context(request.command,request.timeout_seconds,||{
  let plan=super::prepare_native_check_selection(selectors,options,self.source_arena_work())?;
  let completed=if plan.handlers_only(){match self.stage_registered_handlers_check_report(request,plan)?{
   HandlerCheckStage::Current(report)=>report,
   HandlerCheckStage::FailedFullOneShot{actual,report:failed}=>{let _=failed.write_once(diagnostics,report);return Err(actual)},
  }}else{self.stage_selected_registry_check_with_plan(request,plan)?};
  let FullRegistryCheckReport{project,inputs,clean,diagnostics:diagnostics_stage,report:report_stage,_credit,..}=completed;
  inputs.require_report_current(&project)?;if let Some(stage)=diagnostics_stage{stage.publish(diagnostics)?;}report_stage.publish(report)?;inputs.require_report_current(&project)?;crate::daemon::control::checkpoint()?;Ok(clean)
  })
 }
 pub(crate) fn stage_full_registry_check_report(&mut self,request:crate::request::BuildRequest,options:FullRegistryCheckOptions)->Result<FullRegistryCheckReport,Box<dyn Error>>{
  self.stage_selected_registry_check_report(request,options,&[])
 }
 fn stage_registered_handlers_check_report(&mut self,mut request:crate::request::BuildRequest,plan:std::sync::Arc<super::NativeCheckSelection>)->Result<HandlerCheckStage,Box<dyn Error>>{
  if !plan.handlers_only(){return Err(super::original_exclusions_invalid().into())}
  let(root,cache,project,retained,credit)=self.prepare_registered_check_request(&mut request,&plan)?;
  // Request copy is DATA under the actual pre-funded request metadata credit;
  // with_prepared_report authenticates it against the real issued owner.
  let report_request=request.clone();let mut diagnostics=crate::selected_report_spool::Stage::new(&cache)?;
  let file=crate::selected_report_spool::Stage::new(&cache)?;
  match crate::request_runner::native_check_source::prepare_registered_handlers_check(request,self,std::sync::Arc::clone(&plan))?{
   crate::request_runner::native_check_source::PreparedHandlers::FailedFullOneShot{actual,report}=>Ok(HandlerCheckStage::FailedFullOneShot{actual,report}),
   crate::request_runner::native_check_source::PreparedHandlers::Current{outcome,inputs}=>{
    inputs.require_current(&project)?;
    let state_owner=self.query_state();let state=state_owner.try_lock().map_err(|error|io::Error::other(error.to_string()))?;
    let snapshot=state.handlers_snapshot.as_ref().ok_or_else(||io::Error::other("prepared Handler owner disappeared"))?;
    inputs.require_binding(snapshot,&plan)?;
    let full=if snapshot.requires_full(){Some(state.snapshot.as_ref().ok_or_else(||io::Error::other("actual Handler full dependency disappeared"))?)}else{None};
    let(clean,report)=snapshot.with_prepared_report(&report_request,&outcome,full,&mut diagnostics,|data,config,child|{
     super::query_snapshot::stage_registered_handlers_current(&root,&plan,file,data,config,child)
    })?;
    if report.length().checked_add(diagnostics.length()).is_none_or(|total|total>dq_analyze::selected_exclusions_wire::MAX_STREAM){return Err(io::Error::new(io::ErrorKind::OutOfMemory,"Handler combined output exceeds existing report bound").into())}
    let(query,partial,full)=inputs.observation()?;drop(state);
    inputs.require_current(&project)?;
    let diagnostics=if diagnostics.length()==0{None}else{Some(crate::request_runner::native_check_handlers::check_diagnostic_stage(diagnostics)?)};
    let frame=dq_analyze::full_registry_check_wire::CheckFrame::Handlers{
     query_revision:dq_analyze::selected_exclusions_wire::Hex128(query),partial_source_revision:partial.map(dq_analyze::selected_exclusions_wire::Hex128),full_source_revision:full.map(dq_analyze::selected_exclusions_wire::Hex128)};
    let selected=u64::try_from(plan.names().len()).map_err(|_|io::Error::from(io::ErrorKind::InvalidData))?;
    let registered=u64::try_from(plan.registered_count()?).map_err(|_|io::Error::from(io::ErrorKind::InvalidData))?;
    drop(retained);Ok(HandlerCheckStage::Current(FullRegistryCheckReport{project,inputs:FullRegistryCheckInputs::Handlers(inputs),frame,selection:plan.binding(),selected,registered,format:plan.format(),clean,diagnostics,report,_credit:credit}))
   }
  }
 }
 pub(crate) fn stage_selected_registry_check_report(&mut self,mut request:crate::request::BuildRequest,options:FullRegistryCheckOptions,selectors:&[String])->Result<FullRegistryCheckReport,Box<dyn Error>>{
  crate::daemon::control::checkpoint()?;
  if crate::daemon::control::current_deadline().is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"report-only CHECK needs its actual bound original deadline").into())}
  request.no_cache|=options.no_cache;
  // Native reports always validate exact content; --rehash requests this existing guarantee.
  request.exact_inputs=true;
  let plan=super::prepare_native_check_selection(selectors,options,self.source_arena_work())?;
  self.stage_selected_registry_check_with_plan(request,plan)
 }
 fn stage_selected_registry_check_with_plan(&mut self,mut request:crate::request::BuildRequest,plan:std::sync::Arc<super::NativeCheckSelection>)->Result<FullRegistryCheckReport,Box<dyn Error>>{
  let options=plan.format();
  request.no_cache|=options.no_cache;request.exact_inputs=true;
  if plan.exclusive_engine_layering(){return self.stage_exclusive_registered_engine_check_report(request,plan)}
  if plan.has_unjoined_handlers(){return Err(io::Error::new(io::ErrorKind::Unsupported,"selected mixed conditional Handler CHECK requires its real joined owner; no semantic-model fallback is issued").into())}
  if plan.handlers_only(){return match self.stage_registered_handlers_check_report(request,plan)?{
   HandlerCheckStage::Current(report)=>Ok(report),HandlerCheckStage::FailedFullOneShot{actual,..}=>Err(actual),
  }}
  if plan.source_only(){return self.stage_source_registry_check_report(request,plan)}
  if plan.names().len()!=plan.registered_count()?{return self.stage_registered_model_check_report(request,plan)}
  let project=crate::policy_request::canonical_analysis_project(&request.project,Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;
  let mut effective=options;effective.unused=plan.audit_unused();
  let(inputs,frame,clean,diagnostics,checker,report,credit)=self.stage_full_registry_report_using(request,false,!effective.raw,Some(effective))?;
  drop(checker);inputs.require_report_current(&project)?;
  let selected=u64::try_from(plan.names().len()).map_err(|_|io::Error::from(io::ErrorKind::InvalidData))?;
  let registered=u64::try_from(plan.registered_count()?).map_err(|_|io::Error::from(io::ErrorKind::InvalidData))?;
  Ok(FullRegistryCheckReport{project,inputs:FullRegistryCheckInputs::Model(inputs),frame:frame.observation_data().into(),selection:plan.binding(),selected,registered,format:options,clean,diagnostics,report,_credit:credit})
 }
 /// Opt-in whole-registry observation over one actual moved preparation ledger.
 /// Ordinary report and strict compiled observation APIs remain separate.
 pub fn write_full_registry_check_with_input_observation<F>(&mut self,request:crate::request::BuildRequest,options:FullRegistryCheckOptions,
  observe:F,diagnostics:&mut impl Write,report:&mut impl Write)->Result<bool,Box<dyn Error>>
 where F:for<'a>FnOnce(crate::request_runner::runner_freshness::observation::ReportObservation<'a>)->io::Result<()>{
  with_full_registry_check_context(request.command,request.timeout_seconds,||{
   if request.policy_inputs.as_ref().and_then(|p|p.analysis_context)!=Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290){return Err(io::Error::new(io::ErrorKind::InvalidInput,"observed report requires actual Original Analyze preparation").into())}
   let cache=request.cache_root.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"observed report needs actual external cache"))?;
   let bytes=cache.as_os_str().len().checked_add(request.project.as_os_str().len()).and_then(|n|n.checked_mul(32)).and_then(|n|n.checked_add(65536+std::mem::size_of::<F>())).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
   let _metadata=self.source_arena_work().reserve(bytes)?;
   let cache=cache.clone();let project=crate::policy_request::canonical_analysis_project(&request.project,Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;
   let(inputs,frame,clean,diagnostics_stage,checker,report_stage,_credit)=self.stage_full_registry_report_using(request,false,!options.raw,Some(options))?;
   frame.require_checker_frame(checker.0)?;
   let binding=crate::request_runner::runner_freshness::observation::ReportBinding{
    frame:frame.observation_data(),checker_frame:checker.0,options,clean,
    diagnostics:diagnostics_stage.as_ref().map(|s|dq_analyze::selected_exclusions_wire::Seal{length:s.length(),hash:dq_analyze::selected_exclusions_wire::Hex128(s.hash())}),
    checker:dq_analyze::selected_exclusions_wire::Seal{length:checker.1.length(),hash:dq_analyze::selected_exclusions_wire::Hex128(checker.1.hash())},
    report:dq_analyze::selected_exclusions_wire::Seal{length:report_stage.length(),hash:dq_analyze::selected_exclusions_wire::Hex128(report_stage.hash())}};
   inputs.with_report_input_observation(&project,|actual|crate::request_runner::runner_freshness::observation::observe_report_inputs(&project,&cache,actual,binding,checker.1,self.source_arena_work(),observe))?;
   if let Some(stage)=diagnostics_stage{stage.publish(diagnostics)?;}report_stage.publish(report)?;
   inputs.require_report_current(&project)?;crate::daemon::control::checkpoint()?;Ok(clean)
  })
 }

}

/// A failed source open never reaches FullRegistryCheckReport or a successful
/// wire terminal. Its one-shot rows and the SAME original error remain separate.
enum HandlerCheckStage{
 Current(FullRegistryCheckReport),
 FailedFullOneShot{actual:Box<dyn Error>,report:crate::request_runner::native_check_handlers::FailedFullOneShot},
}

impl BuildHost{
 fn stage_exclusive_registered_engine_check_report(&mut self,mut request:crate::request::BuildRequest,plan:std::sync::Arc<super::NativeCheckSelection>)->Result<FullRegistryCheckReport,Box<dyn Error>>{
  if !plan.exclusive_engine_layering(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"exclusive selected Engine request required").into())}
  let(root,cache,project,retained,credit)=self.prepare_registered_check_request(&mut request,&plan)?;let mut diagnostics=crate::selected_report_spool::Stage::new(&cache)?;let report=crate::selected_report_spool::Stage::new(&cache)?;
  let(prepared,actual)=crate::request_runner::native_check_source::prepare_registered_engine_check(request,self,std::sync::Arc::clone(&plan),&mut diagnostics)?;
  let selected=1;let registered=u64::try_from(plan.registered_count()?).map_err(|_|io::Error::from(io::ErrorKind::OutOfMemory))?;
  let(clean,report,frame,inputs)=match actual{
   crate::request_runner::native_check_source::EnginePrepared::Unselected{snapshot,inputs}=>{
    if diagnostics.length()!=0{return Err(io::Error::new(io::ErrorKind::InvalidData,"empty Engine acquired unexpected model diagnostics").into())}inputs.require_binding(&snapshot,&plan)?;inputs.require_current(&project)?;
    let(clean,report)=snapshot.stage_selected_engine_unselected(&prepared,&retained,&root,report,&plan)?;inputs.require_binding(&snapshot,&plan)?;inputs.require_current(&project)?;
    let frame=dq_analyze::full_registry_check_wire::CheckFrame::Source{query_revision:dq_analyze::selected_exclusions_wire::Hex128(snapshot.revision()),source_revision:dq_analyze::selected_exclusions_wire::Hex128(snapshot.source_revision()),policy_revision:dq_analyze::selected_exclusions_wire::Hex128(snapshot.policy_revision())};(clean,report,frame,FullRegistryCheckInputs::Source(inputs))
   },
   crate::request_runner::native_check_source::EnginePrepared::Model{inputs}=>{
    let state=self.query_state.try_lock().map_err(|_|io::Error::new(io::ErrorKind::WouldBlock,"actual selected Engine model state borrowed"))?;let snapshot=state.snapshot.as_ref().ok_or_else(||io::Error::other("actual selected Engine model snapshot absent"))?;
    snapshot.require_registered_engine_inputs(&inputs,&project,&plan)?;inputs.require_current(&project)?;let(clean,report)=snapshot.stage_selected_engine_model(&prepared,&retained,&root,report,&plan)?;snapshot.require_registered_engine_inputs(&inputs,&project,&plan)?;inputs.require_current(&project)?;
    let frame=crate::daemon::selected_report_wire::Frame::from_prepared(&prepared)?.observation_data().into();(clean,report,frame,FullRegistryCheckInputs::SelectedModel(inputs))
   },
  };
  let diagnostics=if diagnostics.length()==0{None}else{Some(super::query_snapshot::checked_selected_report_stage(diagnostics)?)};crate::daemon::control::checkpoint()?;
  Ok(FullRegistryCheckReport{project,inputs,frame,selection:plan.binding(),selected,registered,format:plan.format(),clean,diagnostics,report,_credit:credit})
 }
}
