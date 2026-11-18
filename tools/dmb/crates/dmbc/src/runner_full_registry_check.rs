//! Report-only native Analyze requests on the existing retained graph.
//! Ordinary defaults remain unchanged until actual whole qualification.
use super::BuildHost;use std::{error::Error,io::{self,Write}};
pub use dq_analyze::full_registry_check_wire::Options as FullRegistryCheckOptions;
pub(crate) enum FullRegistryCheckInputs{
 ReportReplay(super::check_report_replay::Loan),
 SourceHandlers(crate::request_runner::source_handler_capture::Inputs),
 Model(crate::request_runner::JoinedSelectedInputs),
 SelectedModel(crate::request_runner::checker_capture::Inputs),
 Source(crate::request_runner::native_check_source::NativeSourceCheckInputs),
 Handlers(crate::request_runner::native_check_handlers::Inputs),
}
impl FullRegistryCheckInputs{pub(crate) fn require_report_current(&self,project:&std::path::Path)->Result<(),Box<dyn Error>>{match self{Self::ReportReplay(actual)=>actual.require_current(project),Self::SourceHandlers(inputs)=>inputs.require_report_current(project).map_err(Into::into),Self::Model(inputs)=>inputs.require_report_current(project),Self::SelectedModel(inputs)=>inputs.require_current(project),Self::Source(inputs)=>inputs.require_current(project).map_err(Into::into),Self::Handlers(inputs)=>inputs.require_current(project).map_err(Into::into)}}}

impl FullRegistryCheckInputs{
 pub(crate) fn require_fixture_step(&self,next:&Self,project:&std::path::Path,root:&std::path::Path,transition:&crate::native_author_fix_transaction::Transition,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->io::Result<()>{match(self,next){
 (Self::Source(a),Self::Source(b))=>a.require_fixture_step(b,project,root,transition,work),
 (Self::SelectedModel(a),Self::SelectedModel(b))=>a.require_fixture_step(b,project,root,transition,work),
 (Self::Handlers(a),Self::Handlers(b))=>a.require_fixture_step(b,project,root,transition,work),
 _=>Err(io::Error::new(io::ErrorKind::InvalidInput,"fixture transition changed its actual selected producer role")),}}
 pub(crate) fn require_baseline_step(&self,next:&Self,project:&std::path::Path,transition:&crate::native_author_fix_transaction::Transition,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->io::Result<()>{
  match(self,next){
   (Self::SourceHandlers(a),Self::SourceHandlers(b))=>a.require_baseline_step(b,project,transition,work),
   (Self::Model(a),Self::Model(b))=>a.require_baseline_step(b,project,transition,work),
   (Self::SelectedModel(a),Self::SelectedModel(b))=>a.require_baseline_step(b,project,transition,work),
   (Self::Source(a),Self::Source(b))=>a.require_baseline_step(b,project,transition,work),
   (Self::Handlers(a),Self::Handlers(b))=>a.require_baseline_step(b,project,transition,work),
   _=>Err(io::Error::new(io::ErrorKind::Interrupted,"baseline reprepare changed its actual producer/ledger variant")),
  }
 }
}

pub(crate) enum RegisteredAllocation{
 Owned(dm_preprocess::source_arena_credit::SourceArenaCredit),
 Replay(dm_preprocess::source_arena_credit::SourceArenaControlCredit),
 Baseline{builder:super::baseline_update::Builder,control:dm_preprocess::source_arena_credit::SourceArenaControlCredit},
}
pub(crate) type FullCheckCredit=RegisteredAllocation;
impl From<dm_preprocess::source_arena_credit::SourceArenaCredit> for RegisteredAllocation{fn from(actual:dm_preprocess::source_arena_credit::SourceArenaCredit)->Self{Self::Owned(actual)}}
impl RegisteredAllocation{
 fn report(credit:dm_preprocess::source_arena_credit::SourceArenaCredit)->Self{Self::Owned(credit)}
 fn registered(credit:dm_preprocess::source_arena_credit::SourceArenaCredit,budget:std::sync::Arc<dq_analyze::captured_generator_budget::Budget>,plan:&super::NativeCheckSelection)->Result<Self,Box<dyn Error>>{Ok(match plan.baseline_mode(){Some(mode)=>{let control=credit.control();let builder=super::baseline_update::Builder::new(credit,budget,mode)?;Self::Baseline{builder,control}},None=>Self::report(credit)})}
 pub(super) fn control(&self)->dm_preprocess::source_arena_credit::SourceArenaControlCredit{match self{Self::Owned(actual)=>actual.control(),Self::Replay(actual)=>actual.clone(),Self::Baseline{control,..}=>control.clone()}}
 pub(in crate::runner_host) fn baseline(&mut self)->Option<&mut super::baseline_update::Builder>{match self{Self::Baseline{builder,..}=>Some(builder),_=>None}}
 pub(in crate::runner_host) fn into_baseline(self)->Result<super::baseline_update::Builder,Box<dyn Error>>{match self{Self::Baseline{builder,..}=>Ok(builder),_=>Err(io::Error::new(io::ErrorKind::InvalidInput,"ordinary CHECK allocation is not a baseline plan").into())}}
}
pub(crate) struct FullRegistryCheckReport{
 pub(crate) project:std::path::PathBuf,pub(crate) inputs:FullRegistryCheckInputs,
 pub(crate) frame:dq_analyze::full_registry_check_wire::CheckFrame,
 pub(crate) selection:dq_analyze::full_registry_check_selection_wire::SelectionBinding,
 pub(crate) selected:u64,pub(crate) registered:u64,
 pub(crate) format:FullRegistryCheckOptions,pub(crate) clean:bool,pub(crate) selftests:Option<dq_analyze::full_registry_check_wire::Selftests>,pub(crate) selftest_completion:Option<std::sync::Arc<super::NativeSelftestCompletion>>,pub(crate) cli:Option<super::check_cli_observations::Delivery>,
 pub(crate) diagnostics:Option<crate::selected_report_spool::Verified>,pub(crate) report:crate::selected_report_spool::Verified,
 pub(crate) _credit:RegisteredAllocation,
}
fn finish_cli_outputs(plan:&super::NativeCheckSelection,diagnostics:Option<&crate::selected_report_spool::Verified>,report:crate::selected_report_spool::Verified)->io::Result<(crate::selected_report_spool::Verified,Option<super::check_cli_observations::Delivery>)>{
 let Some(actual)=plan.cli_observations()else{return Ok((report,None))};let report=actual.finish_report(report)?;let cli=actual.finish()?;let total=report.length().checked_add(diagnostics.map_or(0,|stage|stage.length())).and_then(|n|n.checked_add(cli.usage.as_ref().map_or(0,|stage|stage.length())));if total.is_none_or(|n|n>dq_analyze::selected_exclusions_wire::MAX_STREAM){return Err(io::Error::new(io::ErrorKind::OutOfMemory,"CHECK CLI diagnostic/report/usage streams exceed the existing aggregate report bound"))}Ok((report,Some(cli)))
}
pub(super) fn with_full_registry_check_context<T>(command:crate::request::BuildCommand,timeout_seconds:Option<u16>,run:impl FnOnce()->Result<T,Box<dyn Error>>)->Result<T,Box<dyn Error>>{
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
/// Policy completion and actual preceding fixture failures remain distinct.
#[derive(Debug,PartialEq,Eq)]pub enum SelftestedRegistryCheck{Checked{clean:bool,selftests_failed:usize}}
fn native_selftest_receipt(plan:&super::NativeCheckSelection)->io::Result<Option<dq_analyze::full_registry_check_wire::Selftests>>{
 plan.native_selftest_result()?.map(|actual|Ok(dq_analyze::full_registry_check_wire::Selftests{completed:u64::try_from(actual.completed()).map_err(|_|io::Error::from(io::ErrorKind::InvalidData))?,failed:u64::try_from(actual.failed()).map_err(|_|io::Error::from(io::ErrorKind::InvalidData))?})).transpose()
}
impl BuildHost{

 /// Native ordinary fixture callbacks run on the same parent preparation.
 /// Semantic failures still execute all actual selected policies.
 pub fn write_selected_registry_check_with_selftests(&mut self,request:crate::request::BuildRequest,options:FullRegistryCheckOptions,selectors:&[String],diagnostics:&mut impl Write,report:&mut impl Write)->Result<SelftestedRegistryCheck,Box<dyn Error>>{
  with_full_registry_check_context(request.command,request.timeout_seconds,||{
   let _=Self::native_registry_check_paths(&request)?;
   let plan=super::prepare_native_registered_check_selection(selectors,options,self.source_arena_work())?;
   let caller=if plan.names().iter().any(|name|matches!(name.as_str(),"ui_actions"|"check_grep")){Some(std::env::current_dir()?)}else{None};
   drop(plan);
   let completed=self.stage_selected_registry_check_selftest_mode(request,options,selectors,true,caller)?;
   let selftests_failed=usize::try_from(completed.selftests.ok_or_else(||io::Error::other("requested native callbacks omitted their actual terminal receipt"))?.failed).map_err(|_|io::Error::from(io::ErrorKind::InvalidData))?;
   let FullRegistryCheckReport{project,inputs,clean,diagnostics:diagnostics_stage,report:report_stage,_credit,..}=completed;
   inputs.require_report_current(&project)?;if let Some(stage)=diagnostics_stage{stage.publish(diagnostics)?;}report_stage.publish(report)?;inputs.require_report_current(&project)?;crate::daemon::control::checkpoint()?;
   self.commit_native_report_replay(inputs);
   Ok(SelftestedRegistryCheck::Checked{clean,selftests_failed})
  })
 }


 /// Explicit caller-directory DATA is resolved by the ordinary CLI before it
 /// enters the resident host. Its actual bytes/absence are still recorded by
 /// this SAME request, not trusted as facts merely because a path was supplied.
 pub fn write_selected_registry_check_with_selftests_from_caller(&mut self,request:crate::request::BuildRequest,options:FullRegistryCheckOptions,selectors:&[String],caller:Option<std::path::PathBuf>,diagnostics:&mut impl Write,report:&mut impl Write)->Result<SelftestedRegistryCheck,Box<dyn Error>>{
  with_full_registry_check_context(request.command,request.timeout_seconds,||{
   let completed=self.stage_selected_registry_check_selftest_mode(request,options,selectors,true,caller)?;
   let selftests_failed=usize::try_from(completed.selftests.ok_or_else(||io::Error::other("requested native callbacks omitted their actual terminal receipt"))?.failed).map_err(|_|io::Error::from(io::ErrorKind::InvalidData))?;
   let FullRegistryCheckReport{project,inputs,clean,diagnostics:diagnostics_stage,report:report_stage,_credit,..}=completed;
   inputs.require_report_current(&project)?;if let Some(stage)=diagnostics_stage{stage.publish(diagnostics)?;}report_stage.publish(report)?;inputs.require_report_current(&project)?;crate::daemon::control::checkpoint()?;
   self.commit_native_report_replay(inputs);
   Ok(SelftestedRegistryCheck::Checked{clean,selftests_failed})
  })
 }

 fn stage_registered_model_check_report(&mut self,mut request:crate::request::BuildRequest,plan:std::sync::Arc<super::NativeCheckSelection>)->Result<FullRegistryCheckReport,Box<dyn Error>>{self.stage_registered_model_check_report_using_baseline(request,plan,None)}
 fn stage_registered_model_check_report_using_baseline(&mut self,mut request:crate::request::BuildRequest,plan:std::sync::Arc<super::NativeCheckSelection>,generation_domain:Option<&crate::request_runner::runner_freshness::GenerationInputClosure>)->Result<FullRegistryCheckReport,Box<dyn Error>>{
  let(root,cache,project,retained,mut credit)=self.prepare_registered_check_request(&mut request,&plan)?;let mut diagnostics=crate::selected_report_spool::Stage::new(&cache)?;let mut checker_stage=if plan.needs_checker(){Some(crate::selected_report_spool::Stage::new(&cache)?)}else{None};let report=crate::selected_report_spool::Stage::new(&cache)?;
  let cli_started=plan.cli_observations().filter(|actual|actual.request().timing).map(|_|std::time::Instant::now());
  let(prepared,inputs,checker)=if plan.is_baseline_update(){crate::request_runner::native_check_source::prepare_registered_model_baseline(request,self,std::sync::Arc::clone(&plan),&mut diagnostics,checker_stage.as_mut(),generation_domain)?}else{crate::request_runner::native_check_source::prepare_registered_model_check(request,self,std::sync::Arc::clone(&plan),&mut diagnostics,checker_stage.as_mut())?};
  if let Some(started)=cli_started{plan.cli_observations().expect("actual optional timing request").prepared(started.elapsed())?;}
  let(clean,report,frame)={let state=self.query_state.try_lock().map_err(|_|io::Error::new(io::ErrorKind::WouldBlock,"selected model state is borrowed"))?;let snapshot=state.snapshot.as_ref().ok_or_else(||io::Error::other("selected model snapshot absent"))?;snapshot.require_registered_model_inputs(&inputs,&project,&plan)?;inputs.require_current(&project)?;
   let handlers=if plan.needs_handlers(){Some(state.handlers_snapshot.as_ref().ok_or_else(||io::Error::other("selected handler dependency absent"))?)}else{None};let(clean,report)=snapshot.stage_selected_registry_model_check_baseline(&prepared,&retained,&root,report,&plan,checker.as_ref(),handlers,credit.baseline())?;snapshot.require_registered_model_inputs(&inputs,&project,&plan)?;inputs.require_current(&project)?;let frame=crate::daemon::selected_report_wire::Frame::from_prepared(&prepared)?.observation_data().into();(clean,report,frame)};
  let diagnostics=if diagnostics.length()==0{None}else{Some(crate::request_runner::native_check_handlers::check_diagnostic_stage(diagnostics)?)};drop(checker_stage);crate::daemon::control::checkpoint()?;
  let(report,cli)=finish_cli_outputs(&plan,diagnostics.as_ref(),report)?;
  Ok(FullRegistryCheckReport{project,inputs:FullRegistryCheckInputs::SelectedModel(inputs),frame,selection:plan.binding(),selected:u64::try_from(plan.names().len()).map_err(|_|io::Error::from(io::ErrorKind::InvalidData))?,registered:u64::try_from(plan.registered_count()?).map_err(|_|io::Error::from(io::ErrorKind::InvalidData))?,format:plan.format(),clean,diagnostics,report,selftests:native_selftest_receipt(&plan)?,selftest_completion:plan.native_selftest_completion()?,cli,_credit:credit.into()})
 }

 fn prepare_registered_check_request(&self,request:&mut crate::request::BuildRequest,plan:&std::sync::Arc<super::NativeCheckSelection>)->Result<(std::path::PathBuf,std::path::PathBuf,std::path::PathBuf,std::sync::Arc<dq_analyze::captured_generator_budget::Budget>,RegisteredAllocation),Box<dyn Error>>{
  use dq_analyze::captured_generator_budget::Budget;
  let namespace=request.policy_inputs.as_ref().and_then(|input|input.workspace.as_ref()).ok_or_else(super::original_exclusions_invalid)?;let cache_path=request.cache_root.as_deref().ok_or_else(super::original_exclusions_invalid)?;
  let metadata=plan.roots().iter().try_fold(0usize,|total,(directory,_)|total.checked_add(directory.len()).and_then(|n|n.checked_add(namespace.root.as_os_str().len())).and_then(|n|n.checked_add(1))).and_then(|n|n.checked_add(namespace.root.as_os_str().len())).and_then(|n|n.checked_add(cache_path.as_os_str().len())).and_then(|n|n.checked_mul(64)).and_then(|n|n.checked_add(64*1024)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
  let credit=self.source_arena_work().reserve(super::SELECTED_REPORT_RETAINED.checked_add(metadata).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?)?;
  let(root,cache)=match plan.fixture_scope(){Some(scope)=>scope.request_paths(&request)?,None=>Self::native_registry_check_paths(&request)?};
  let workspace=request.policy_inputs.as_mut().and_then(|input|input.workspace.as_mut()).ok_or_else(super::original_exclusions_invalid)?;
  workspace.recursive_roots.clear();
  for(directory,_)in plan.roots(){crate::daemon::control::checkpoint()?;let path=root.join(directory);if !workspace.recursive_roots.contains(&path){workspace.recursive_roots.try_reserve(1).map_err(|_|io::Error::from(io::ErrorKind::OutOfMemory))?;workspace.recursive_roots.push(path)}}
  let project=crate::policy_request::canonical_analysis_project(&request.project,Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;
  let retained=Budget::new(super::SELECTED_REPORT_RETAINED).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;
  let intent=request.policy_inputs.as_mut().ok_or_else(super::original_exclusions_invalid)?;intent.workspace_auxiliary.clear();if !plan.source_only(){for question in plan.questions(){intent.workspace_auxiliary.try_reserve(1).map_err(|_|io::Error::from(io::ErrorKind::OutOfMemory))?;intent.workspace_auxiliary.push(question)}}
  let credit=RegisteredAllocation::registered(credit,std::sync::Arc::clone(&retained),plan)?;
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
 fn stage_source_registry_check_report(&mut self,mut request:crate::request::BuildRequest,plan:std::sync::Arc<super::NativeCheckSelection>)->Result<FullRegistryCheckReport,Box<dyn Error>>{self.stage_source_registry_check_report_using_baseline(request,plan,None)}
 fn stage_source_registry_check_report_using_baseline(&mut self,mut request:crate::request::BuildRequest,plan:std::sync::Arc<super::NativeCheckSelection>,generation_domain:Option<&crate::request_runner::runner_freshness::GenerationInputClosure>)->Result<FullRegistryCheckReport,Box<dyn Error>>{
  use dq_analyze::captured_generator_budget::Budget;
  if !self.retains_artifacts()||!plan.source_only(){return Err(super::original_exclusions_invalid().into())}
  let(root,cache,project,retained,mut credit)=self.prepare_registered_check_request(&mut request,&plan)?;
  let stage=crate::selected_report_spool::Stage::new(&cache)?;
  let cli_started=plan.cli_observations().filter(|actual|actual.request().timing).map(|_|std::time::Instant::now());
  let(prepared,snapshot,inputs)=if plan.is_baseline_update(){crate::request_runner::native_check_source::prepare_registered_source_baseline(request,self,std::sync::Arc::clone(&plan),generation_domain)?}else{crate::request_runner::native_check_source::prepare_registered_source_check(request,self,std::sync::Arc::clone(&plan))?};
  if let Some(started)=cli_started{plan.cli_observations().expect("actual optional timing request").prepared(started.elapsed())?;}
  inputs.require_binding(&snapshot,&plan)?;inputs.require_current(&project)?;
  let(clean,report)=snapshot.stage_selected_registry_source_check_baseline(&prepared,&retained,&root,stage,&plan,credit.baseline())?;
  inputs.require_binding(&snapshot,&plan)?;inputs.require_current(&project)?;crate::daemon::control::checkpoint()?;
  let frame=dq_analyze::full_registry_check_wire::CheckFrame::Source{query_revision:dq_analyze::selected_exclusions_wire::Hex128(snapshot.revision()),source_revision:dq_analyze::selected_exclusions_wire::Hex128(snapshot.source_revision()),policy_revision:dq_analyze::selected_exclusions_wire::Hex128(snapshot.policy_revision())};
  let selected=u64::try_from(plan.names().len()).map_err(|_|io::Error::from(io::ErrorKind::InvalidData))?;let registered=u64::try_from(plan.registered_count()?).map_err(|_|io::Error::from(io::ErrorKind::InvalidData))?;
  let(report,cli)=finish_cli_outputs(&plan,None,report)?;
  Ok(FullRegistryCheckReport{project,inputs:FullRegistryCheckInputs::Source(inputs),frame,selection:plan.binding(),selected,registered,format:plan.format(),clean,diagnostics:None,report,selftests:native_selftest_receipt(&plan)?,selftest_completion:plan.native_selftest_completion()?,cli,_credit:credit.into()})
 }

 pub fn write_full_registry_check(&mut self,request:crate::request::BuildRequest,options:FullRegistryCheckOptions,diagnostics:&mut impl Write,report:&mut impl Write)->Result<bool,Box<dyn Error>>{
  self.write_selected_registry_check(request,options,&[],diagnostics,report)
 }
 /// Partial delivery is not completion: callers buffer/discard on error.
 pub fn write_selected_registry_check(&mut self,request:crate::request::BuildRequest,options:FullRegistryCheckOptions,selectors:&[String],diagnostics:&mut impl Write,report:&mut impl Write)->Result<bool,Box<dyn Error>>{
  with_full_registry_check_context(request.command,request.timeout_seconds,||{
  let plan=super::prepare_native_registered_check_selection(selectors,options,self.source_arena_work())?;
  let completed=if plan.handlers_only()&&!plan.source_handler_union_candidate(){match self.stage_registered_handlers_check_report(request,plan)?{
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
 fn stage_registered_handlers_check_report(&mut self,mut request:crate::request::BuildRequest,plan:std::sync::Arc<super::NativeCheckSelection>)->Result<HandlerCheckStage,Box<dyn Error>>{self.stage_registered_handlers_check_report_using_baseline(request,plan,None)}
 fn stage_registered_handlers_check_report_using_baseline(&mut self,mut request:crate::request::BuildRequest,plan:std::sync::Arc<super::NativeCheckSelection>,generation_domain:Option<&crate::request_runner::runner_freshness::GenerationInputClosure>)->Result<HandlerCheckStage,Box<dyn Error>>{
  if !plan.handlers_only(){return Err(super::original_exclusions_invalid().into())}
  let(root,cache,project,retained,mut credit)=self.prepare_registered_check_request(&mut request,&plan)?;
  // Request copy is DATA under the actual pre-funded request metadata credit;
  // with_prepared_report authenticates it against the real issued owner.
  let report_request=request.clone();let mut diagnostics=crate::selected_report_spool::Stage::new(&cache)?;
  let file=crate::selected_report_spool::Stage::new(&cache)?;
  let cli_started=plan.cli_observations().filter(|actual|actual.request().timing).map(|_|std::time::Instant::now());
  let prepared=if plan.is_baseline_update(){crate::request_runner::native_check_source::prepare_registered_handlers_baseline(request,self,std::sync::Arc::clone(&plan),generation_domain)?}else{crate::request_runner::native_check_source::prepare_registered_handlers_check(request,self,std::sync::Arc::clone(&plan))?};
  if let Some(started)=cli_started{plan.cli_observations().expect("actual optional timing request").prepared(started.elapsed())?;}
  match prepared{
   crate::request_runner::native_check_source::PreparedHandlers::FailedFullOneShot{actual,report}=>if plan.is_baseline_update(){Err(actual)}else{Ok(HandlerCheckStage::FailedFullOneShot{actual,report})},
   crate::request_runner::native_check_source::PreparedHandlers::Current{outcome,inputs}=>{
    inputs.require_current(&project)?;
    let baseline_loan=if plan.is_baseline_update(){Some(inputs.baseline_configuration()?)}else{None};
    let state_owner=self.query_state();let state=state_owner.try_lock().map_err(|error|io::Error::other(error.to_string()))?;
    let snapshot=state.handlers_snapshot.as_ref().ok_or_else(||io::Error::other("prepared Handler owner disappeared"))?;
    inputs.require_binding(snapshot,&plan)?;
    let full=if snapshot.requires_full(){Some(state.snapshot.as_ref().ok_or_else(||io::Error::other("actual Handler full dependency disappeared"))?)}else{None};
    let mut timing=plan.cli_observations().filter(|actual|actual.request().timing).map(|actual|Ok::<_,io::Error>((actual,std::time::Instant::now(),self.query_db.cli_observation_stats()?))).transpose()?;
    let(clean,report)=snapshot.with_prepared_report(&report_request,&outcome,full,&mut diagnostics,|data,config,child|{
     if let Some((actual,started,before))=timing.take(){let after=self.query_db.cli_observation_stats()?;actual.record_timing(super::check_cli_observations::TimingRow{name:"sem/handlers",total:started.elapsed(),files:0,rescanned:0,memo:after.computed==before.computed&&after.green>before.green})?;}
     match credit.baseline(){Some(builder)=>super::query_snapshot::stage_registered_handlers_current_baseline(&root,&plan,file,data,config,child,builder,baseline_loan.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"actual Handler baseline config loan absent"))?),None=>super::query_snapshot::stage_registered_handlers_current(&root,&plan,file,data,config,child)}
    })?;
    if report.length().checked_add(diagnostics.length()).is_none_or(|total|total>dq_analyze::selected_exclusions_wire::MAX_STREAM){return Err(io::Error::new(io::ErrorKind::OutOfMemory,"Handler combined output exceeds existing report bound").into())}
    let(query,partial,full)=inputs.observation()?;drop(state);
    inputs.require_current(&project)?;
    let diagnostics=if diagnostics.length()==0{None}else{Some(crate::request_runner::native_check_handlers::check_diagnostic_stage(diagnostics)?)};
    let frame=dq_analyze::full_registry_check_wire::CheckFrame::Handlers{
     query_revision:dq_analyze::selected_exclusions_wire::Hex128(query),partial_source_revision:partial.map(dq_analyze::selected_exclusions_wire::Hex128),full_source_revision:full.map(dq_analyze::selected_exclusions_wire::Hex128)};
    let selected=u64::try_from(plan.names().len()).map_err(|_|io::Error::from(io::ErrorKind::InvalidData))?;
    let registered=u64::try_from(plan.registered_count()?).map_err(|_|io::Error::from(io::ErrorKind::InvalidData))?;
    let(report,cli)=finish_cli_outputs(&plan,diagnostics.as_ref(),report)?;
    drop(retained);Ok(HandlerCheckStage::Current(FullRegistryCheckReport{project,inputs:FullRegistryCheckInputs::Handlers(inputs),frame,selection:plan.binding(),selected,registered,format:plan.format(),clean,diagnostics,report,selftests:native_selftest_receipt(&plan)?,selftest_completion:plan.native_selftest_completion()?,cli,_credit:credit.into()}))
   }
  }
 }
 pub(crate) fn stage_selected_registry_check_report(&mut self,request:crate::request::BuildRequest,options:FullRegistryCheckOptions,selectors:&[String])->Result<FullRegistryCheckReport,Box<dyn Error>>{self.stage_selected_registry_check_selftest_mode(request,options,selectors,false,None)}
 pub(crate) fn stage_selected_registry_check_selftest_mode(&mut self,request:crate::request::BuildRequest,options:FullRegistryCheckOptions,selectors:&[String],selftests:bool,caller:Option<std::path::PathBuf>)->Result<FullRegistryCheckReport,Box<dyn Error>>{self.stage_selected_registry_check_cli_mode(request,options,selectors,selftests,caller,None)}
 pub(crate) fn stage_selected_registry_check_cli_mode(&mut self,mut request:crate::request::BuildRequest,options:FullRegistryCheckOptions,selectors:&[String],selftests:bool,caller:Option<std::path::PathBuf>,cli:Option<&dq_analyze::native_check_cli_wire::Request>)->Result<FullRegistryCheckReport,Box<dyn Error>>{
  crate::daemon::control::checkpoint()?;
  if crate::daemon::control::current_deadline().is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"report-only CHECK needs its actual bound original deadline").into())}
  if let Some(cli)=cli{cli.qualify(options,selftests)?;}
  request.no_cache|=options.no_cache;
  // Native reports always validate exact content; --rehash requests this existing guarantee.
  request.exact_inputs=true;
  // No new spool/scratch before revalidating the actual retained input owner.
  let(root,cache)=Self::native_registry_check_paths(&request)?;
  if selftests&&cli.is_none(){if let Some(actual)=self.take_native_report_replay(&request,options,selectors,caller.as_deref())?{return Ok(actual)}}
  let candidate=if selftests&&cli.is_none(){Self::native_report_replay_candidate(&request,options,root,cache)?}else{None};
  let mut plan=super::prepare_native_registered_check_selection(selectors,options,self.source_arena_work())?;
  if selftests{std::sync::Arc::get_mut(&mut plan).ok_or_else(||io::Error::other("fresh native callback plan already has an alias"))?.enable_native_selftests(caller,self.source_arena_work())?;}else if caller.is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"unrequested callback caller directory appeared").into())}
  if let Some(cli)=cli{cli.qualify(options,selftests)?;let(_,cache)=Self::native_registry_check_paths(&request)?;std::sync::Arc::get_mut(&mut plan).ok_or_else(||io::Error::other("fresh CHECK CLI plan already aliased"))?.enable_cli_observations(cli,&cache,self.source_arena_work())?;}
  if cli.is_some(){self.discard_joined_report_replay();}
  let actual=self.stage_selected_registry_check_with_plan(request,std::sync::Arc::clone(&plan))?;
  self.retain_native_report(actual,candidate,selectors,plan.selftest_request().and_then(|r|r.caller()))
 }
 pub(super) fn stage_selected_registry_check_with_plan(&mut self,mut request:crate::request::BuildRequest,plan:std::sync::Arc<super::NativeCheckSelection>)->Result<FullRegistryCheckReport,Box<dyn Error>>{
  let options=plan.format();
  request.no_cache|=options.no_cache;request.exact_inputs=true;
  if plan.source_handler_union_candidate(){return self.stage_registered_source_handler_check_report(request,plan)}
  if plan.exclusive_engine_layering(){return self.stage_exclusive_registered_engine_check_report(request,plan)}
  if plan.has_unjoined_handlers(){return Err(io::Error::new(io::ErrorKind::Unsupported,"selected mixed conditional Handler CHECK requires its real joined owner; no semantic-model fallback is issued").into())}
  if plan.handlers_only(){return match self.stage_registered_handlers_check_report(request,plan)?{
   HandlerCheckStage::Current(report)=>Ok(report),HandlerCheckStage::FailedFullOneShot{actual,..}=>Err(actual),
  }}
  if plan.source_only(){return self.stage_source_registry_check_report(request,plan)}
  if plan.names().len()!=plan.registered_count()?{return self.stage_registered_model_check_report(request,plan)}
  // The complete registry uses the existing bounded canonical BODY chunks.
  // This preserves the authenticated whole archive, ordered phases and SCC;
  // it does not allocate an immutable query node for every callable body.
  let project=crate::policy_request::canonical_analysis_project(&request.project,Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;
  let mut effective=options;effective.unused=plan.audit_unused();
  let(inputs,frame,clean,diagnostics,checker,report,credit)=self.stage_full_registry_report_using(request,true,!effective.raw,Some(effective),Some(&plan))?;
  drop(checker);inputs.require_report_current(&project)?;
  let selected=u64::try_from(plan.names().len()).map_err(|_|io::Error::from(io::ErrorKind::InvalidData))?;
  let registered=u64::try_from(plan.registered_count()?).map_err(|_|io::Error::from(io::ErrorKind::InvalidData))?;
  let(report,cli)=finish_cli_outputs(&plan,diagnostics.as_ref(),report)?;
  Ok(FullRegistryCheckReport{project,inputs:FullRegistryCheckInputs::Model(inputs),frame:frame.observation_data().into(),selection:plan.binding(),selected,registered,format:options,clean,diagnostics,report,selftests:native_selftest_receipt(&plan)?,selftest_completion:plan.native_selftest_completion()?,cli,_credit:credit.into()})
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
   let(inputs,frame,clean,diagnostics_stage,checker,report_stage,_credit)=self.stage_full_registry_report_using(request,true,!options.raw,Some(options),None)?;
   frame.require_checker_frame(checker.0)?;
   let original_archive_bodies={
    let state=self.query_state.try_lock().map_err(|_|io::Error::new(io::ErrorKind::WouldBlock,"observed original body roster query state already borrowed"))?;
    state.snapshot.as_ref().ok_or_else(||io::Error::other("observed original body roster snapshot absent"))?.observed_original_archive_bodies(frame.observation_data())?
   };
   let binding=crate::request_runner::runner_freshness::observation::ReportBinding{
    frame:frame.observation_data(),checker_frame:checker.0,options,clean,original_archive_bodies,
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
 fn stage_exclusive_registered_engine_check_report(&mut self,mut request:crate::request::BuildRequest,plan:std::sync::Arc<super::NativeCheckSelection>)->Result<FullRegistryCheckReport,Box<dyn Error>>{self.stage_exclusive_registered_engine_check_report_using_baseline(request,plan,None)}
 fn stage_exclusive_registered_engine_check_report_using_baseline(&mut self,mut request:crate::request::BuildRequest,plan:std::sync::Arc<super::NativeCheckSelection>,generation_domain:Option<&crate::request_runner::runner_freshness::GenerationInputClosure>)->Result<FullRegistryCheckReport,Box<dyn Error>>{
  if !plan.exclusive_engine_layering(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"exclusive selected Engine request required").into())}
  let(root,cache,project,retained,mut credit)=self.prepare_registered_check_request(&mut request,&plan)?;let mut diagnostics=crate::selected_report_spool::Stage::new(&cache)?;let report=crate::selected_report_spool::Stage::new(&cache)?;
  let cli_started=plan.cli_observations().filter(|actual|actual.request().timing).map(|_|std::time::Instant::now());
  let(prepared,actual)=if plan.is_baseline_update(){crate::request_runner::native_check_source::prepare_registered_engine_baseline(request,self,std::sync::Arc::clone(&plan),&mut diagnostics,generation_domain)?}else{crate::request_runner::native_check_source::prepare_registered_engine_check(request,self,std::sync::Arc::clone(&plan),&mut diagnostics)?};
  if let Some(started)=cli_started{plan.cli_observations().expect("actual optional timing request").prepared(started.elapsed())?;}
  let selected=1;let registered=u64::try_from(plan.registered_count()?).map_err(|_|io::Error::from(io::ErrorKind::OutOfMemory))?;
  let(clean,report,frame,inputs)=match actual{
   crate::request_runner::native_check_source::EnginePrepared::Unselected{snapshot,inputs}=>{
    if diagnostics.length()!=0{return Err(io::Error::new(io::ErrorKind::InvalidData,"empty Engine acquired unexpected model diagnostics").into())}inputs.require_binding(&snapshot,&plan)?;inputs.require_current(&project)?;
    let(clean,report)=snapshot.stage_selected_engine_unselected_baseline(&prepared,&retained,&root,report,&plan,credit.baseline())?;inputs.require_binding(&snapshot,&plan)?;inputs.require_current(&project)?;
    let frame=dq_analyze::full_registry_check_wire::CheckFrame::Source{query_revision:dq_analyze::selected_exclusions_wire::Hex128(snapshot.revision()),source_revision:dq_analyze::selected_exclusions_wire::Hex128(snapshot.source_revision()),policy_revision:dq_analyze::selected_exclusions_wire::Hex128(snapshot.policy_revision())};(clean,report,frame,FullRegistryCheckInputs::Source(inputs))
   },
   crate::request_runner::native_check_source::EnginePrepared::Model{inputs}=>{
    let state=self.query_state.try_lock().map_err(|_|io::Error::new(io::ErrorKind::WouldBlock,"actual selected Engine model state borrowed"))?;let snapshot=state.snapshot.as_ref().ok_or_else(||io::Error::other("actual selected Engine model snapshot absent"))?;
    snapshot.require_registered_engine_inputs(&inputs,&project,&plan)?;inputs.require_current(&project)?;let(clean,report)=snapshot.stage_selected_engine_model_baseline(&prepared,&retained,&root,report,&plan,credit.baseline())?;snapshot.require_registered_engine_inputs(&inputs,&project,&plan)?;inputs.require_current(&project)?;
    let frame=crate::daemon::selected_report_wire::Frame::from_prepared(&prepared)?.observation_data().into();(clean,report,frame,FullRegistryCheckInputs::SelectedModel(inputs))
   },
  };
  let diagnostics=if diagnostics.length()==0{None}else{Some(super::query_snapshot::checked_selected_report_stage(diagnostics)?)};crate::daemon::control::checkpoint()?;
  let(report,cli)=finish_cli_outputs(&plan,diagnostics.as_ref(),report)?;
  Ok(FullRegistryCheckReport{project,inputs,frame,selection:plan.binding(),selected,registered,format:plan.format(),clean,diagnostics,report,selftests:native_selftest_receipt(&plan)?,selftest_completion:plan.native_selftest_completion()?,cli,_credit:credit.into()})
 }
}

impl BuildHost{
 fn stage_registered_source_handler_check_report(&mut self,mut request:crate::request::BuildRequest,plan:std::sync::Arc<super::NativeCheckSelection>)->Result<FullRegistryCheckReport,Box<dyn Error>>{self.stage_registered_source_handler_check_report_using_baseline(request,plan,None)}
 fn stage_registered_source_handler_check_report_using_baseline(&mut self,mut request:crate::request::BuildRequest,plan:std::sync::Arc<super::NativeCheckSelection>,generation_domain:Option<&crate::request_runner::runner_freshness::GenerationInputClosure>)->Result<FullRegistryCheckReport,Box<dyn Error>>{
  use dq_analyze::{full_registry_check_wire::CheckFrame,selected_exclusions_wire::Hex128};
  if !plan.source_handler_union_candidate(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual conditional Source/Handler plan required").into())}
  request.exact_inputs=true;request.no_cache|=plan.format().no_cache;
  let(root,cache,project,retained,mut credit)=self.prepare_registered_check_request(&mut request,&plan)?;
  let projection=std::sync::Arc::new(super::derive_source_handler_projection(std::sync::Arc::clone(&plan),self.source_arena_work())?);
  let mut diagnostics=crate::selected_report_spool::Stage::new(&cache)?;let file=crate::selected_report_spool::Stage::new(&cache)?;
  let cli_started=plan.cli_observations().filter(|actual|actual.request().timing).map(|_|std::time::Instant::now());
  let(outcome,actual)=if plan.is_baseline_update(){crate::request_runner::native_check_source::prepare_registered_source_handlers_baseline(request,self,std::sync::Arc::clone(&projection),&mut diagnostics,generation_domain)?}else{crate::request_runner::native_check_source::prepare_registered_source_handlers_check(request,self,std::sync::Arc::clone(&projection),&mut diagnostics)?};
  if let Some(started)=cli_started{plan.cli_observations().expect("actual optional timing request").prepared(started.elapsed())?;}
  actual.inputs.require_report_current(&project)?;
  let(clean,report,pins)={
   let state=self.query_state.try_lock().map_err(|_|io::Error::new(io::ErrorKind::WouldBlock,"conditional Source/Handler state borrowed"))?;
   let raw=state.raw_snapshot.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::NotConnected,"actual conditional Raw snapshot disappeared"))?;
   let handler=state.handlers_snapshot.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::NotConnected,"actual conditional Handler snapshot disappeared"))?;
   let full=if handler.requires_full(){Some(state.snapshot.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::NotConnected,"actual required Handler full snapshot disappeared"))?)}else{None};
   actual.raw.require_same_registered_frame(raw,projection.raw())?;
   actual.inputs.require_binding(raw,handler,full,&projection)?;
   let pins=actual.inputs.pins();
   // Wire/outcome values reject disagreement only; the actual native siblings
   // and moved closure above remain the only producer authority.
   match &outcome{
    crate::request::BuildOutcome::RawQueryPrepared{query_revision,source_revision,policy_revision,retained:true}if full.is_none()=>{
     let parse=|text:&str|u128::from_str_radix(text,16).ok();if parse(query_revision)!=Some(pins.raw_query)||parse(source_revision)!=Some(pins.raw_source)||parse(policy_revision)!=Some(pins.raw_policy){return Err(io::Error::new(io::ErrorKind::InvalidData,"conditional Raw outcome differs from actual sibling").into())}
    },
    crate::request::BuildOutcome::HandlersQueryPrepared{query_revision,partial_source_revision,full_source_revision,retained:true}if full.is_some()=>{
     let parse=|text:&str|u128::from_str_radix(text,16).ok();if parse(query_revision)!=Some(pins.handler_query)||partial_source_revision.as_ref().map(|text|parse(text))!=pins.handler_source.map(Some)||full_source_revision.as_ref().map(|text|parse(text))!=pins.handler_full_source.map(Some){return Err(io::Error::new(io::ErrorKind::InvalidData,"conditional Handler outcome differs from actual full sibling").into())}
    },
    _=>return Err(io::Error::new(io::ErrorKind::InvalidData,"conditional actual preparation outcome was relabeled").into()),
   }
   let(clean,report)=raw.stage_source_handler_registry_check_baseline(&retained,&root,file,&projection,handler,full,credit.baseline())?;
   actual.inputs.require_binding(raw,handler,full,&projection)?;actual.inputs.require_report_current(&project)?;(clean,report,pins)
  };
  if report.length().checked_add(diagnostics.length()).is_none_or(|total|total>dq_analyze::selected_exclusions_wire::MAX_STREAM){return Err(io::Error::new(io::ErrorKind::OutOfMemory,"conditional combined output exceeds existing report bound").into())}
  let diagnostics=if diagnostics.length()==0{None}else{Some(crate::request_runner::native_check_handlers::check_diagnostic_stage(diagnostics)?)};
  let frame=CheckFrame::SourceHandlers{query_revision:Hex128(pins.raw_query),source_revision:Hex128(pins.raw_source),policy_revision:Hex128(pins.raw_policy),handler_query_revision:Hex128(pins.handler_query),partial_source_revision:pins.handler_source.map(Hex128),full_source_revision:pins.handler_full_source.map(Hex128),full_semantic_revision:pins.full_semantic.map(Hex128),full_policy_revision:pins.full_policy.map(Hex128)};
  crate::daemon::control::checkpoint()?;
  let(report,cli)=finish_cli_outputs(&plan,diagnostics.as_ref(),report)?;
  Ok(FullRegistryCheckReport{project,inputs:FullRegistryCheckInputs::SourceHandlers(actual.inputs),frame,selection:plan.binding(),selected:u64::try_from(plan.names().len()).map_err(|_|io::Error::from(io::ErrorKind::InvalidData))?,registered:u64::try_from(plan.registered_count()?).map_err(|_|io::Error::from(io::ErrorKind::InvalidData))?,format:plan.format(),clean,diagnostics,report,selftests:native_selftest_receipt(&plan)?,selftest_completion:plan.native_selftest_completion()?,cli,_credit:credit.into()})
 }
}

impl BuildHost{
 /// Fixture-only caller path on this SAME host and request context. The
 /// ordinary fixture sources are real scratch files supplied by the native
 /// selftest coordinator; all physical/currentness checks remain unchanged.
 pub(crate) fn with_native_derived_fixture_request(&mut self,mut request:crate::request::BuildRequest,visit:&mut dq_analyze::captured_derived_reads::FixtureVisitor<'_>)->Result<(),Box<dyn Error>>{
  if crate::daemon::control::WorkerContext::capture_for_checkpoints().is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native fixture requires its original active selftest context").into())}
  request.exact_inputs=true;request.no_cache=true;
  let options=FullRegistryCheckOptions{raw:true,unused:false,..Default::default()};
  let completed=self.stage_selected_registry_check_report(request,options,&["derived_reads".into()])?;
  completed.inputs.require_report_current(&completed.project)?;
  {let state=self.query_state.try_lock().map_err(|_|io::Error::new(io::ErrorKind::WouldBlock,"native fixture actual model borrowed"))?;let snapshot=state.snapshot.as_ref().ok_or_else(||io::Error::other("native fixture actual selected model absent"))?;snapshot.with_native_derived_fixture(visit)?;}
  completed.inputs.require_report_current(&completed.project)?;crate::daemon::control::checkpoint()?;Ok(())
 }
}

// Operation-local fixture sources only. This is neither a persistent memo nor
// an authored-output writer; every file is create_new under a fresh owned child
// of the request's existing external cache. No game source is mutated.
#[path="fixture_sources_admitted.rs"]mod fixture_sources_admitted;
pub(super) struct NativeFixtureSources{
 root:std::path::PathBuf,parent:std::path::PathBuf,identity:u128,
 files:Vec<(std::path::PathBuf,crate::input_snapshot::Stamp)>,
 directories:Vec<(std::path::PathBuf,u128)>,
 _parent:crate::frozen_inputs::GenerationAncestorGuard,
 _resource:Option<fixture_sources_admitted::Resources>,
}
fn native_fixture_next_id()->u64{use std::sync::atomic::{AtomicU64,Ordering};static NEXT:AtomicU64=AtomicU64::new(0);NEXT.fetch_add(1,Ordering::Relaxed)}
impl NativeFixtureSources{
 pub(super) fn root(&self)->&std::path::Path{&self.root}
 pub(super) fn new(cache:&std::path::Path)->io::Result<Self>{
  let parent=std::fs::canonicalize(cache)?;let guard=crate::frozen_inputs::generation_ancestor_guard(&parent,&parent)?;
  for _ in 0..16{crate::daemon::control::checkpoint()?;let root=parent.join(format!("native-selftest-{}-{}",std::process::id(),native_fixture_next_id()));
   match std::fs::create_dir(&root){Ok(())=>{let identity=crate::frozen_inputs::generation_directory_identity(&root,&parent)?;return Ok(Self{root,parent,identity,files:Vec::new(),directories:Vec::new(),_parent:guard,_resource:None})},Err(actual)if actual.kind()==io::ErrorKind::AlreadyExists=>continue,Err(actual)=>return Err(actual)}
  }Err(io::Error::new(io::ErrorKind::AlreadyExists,"native fixture source namespace exhausted"))
 }
 pub(super) fn current(&self)->io::Result<()>{if self._resource.is_some(){self.current_admitted()}else{self.current_unadmitted()}}
 fn current_unadmitted(&self)->io::Result<()>{if crate::frozen_inputs::generation_directory_identity(&self.root,&self.parent)?!=self.identity{return Err(io::Error::new(io::ErrorKind::InvalidData,"native fixture source directory changed identity"))}Ok(())}
 pub(super) fn put(&mut self,relative:&str,bytes:&[u8])->io::Result<()>{if self._resource.is_some(){self.put_admitted(relative,bytes)}else{self.put_unadmitted(relative,bytes)}}
 fn ensure_parents_unadmitted(&mut self,relative:&str)->io::Result<std::path::PathBuf>{
  use std::path::Component;self.current()?;crate::daemon::control::checkpoint()?;let relative=std::path::Path::new(relative);
  if relative.as_os_str().is_empty()||relative.components().any(|part|!matches!(part,Component::Normal(_))){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native fixture path must be a normal owned relative path"))}
  let mut directory=self.root.clone();let parts:Vec<_>=relative.components().collect();
  for part in &parts[..parts.len()-1]{let _parent=crate::frozen_inputs::generation_ancestor_guard(&directory,&self.root)?;directory.push(part.as_os_str());if let Some((_,identity))=self.directories.iter().find(|(path,_)|*path==directory){if crate::frozen_inputs::generation_directory_identity(&directory,&self.root)?!=*identity{return Err(io::Error::new(io::ErrorKind::InvalidData,"native fixture child directory changed before write"))}continue}std::fs::create_dir(&directory)?;let identity=crate::frozen_inputs::generation_directory_identity(&directory,&self.root)?;self.directories.push((directory.clone(),identity));}
  Ok(directory)
 }
 fn put_unadmitted(&mut self,relative:&str,bytes:&[u8])->io::Result<()>{
  use std::io::Write;let directory=self.ensure_parents_unadmitted(relative)?;
  let _parent=crate::frozen_inputs::generation_ancestor_guard(&directory,&self.root)?;let path=self.root.join(relative);let mut file=std::fs::OpenOptions::new().write(true).create_new(true).open(&path)?;let stamp=crate::input_snapshot::stamp_handle(&file)?;if stamp.file_id.is_none(){return Err(io::Error::new(io::ErrorKind::Unsupported,"native fixture file has no stable identity"))}self.files.push((path,stamp));file.write_all(bytes)?;file.flush()?;drop(file);self.current()
 }
 pub(super) fn remove(&mut self)->io::Result<()>{if self._resource.is_some(){self.remove_admitted()}else{self.remove_unadmitted()}}
 fn remove_unadmitted(&mut self)->io::Result<()>{
  self.current()?;
  while let Some((path,stamp))=self.files.last(){let _parent=crate::frozen_inputs::generation_ancestor_guard(path.parent().unwrap(),&self.root)?;let file=std::fs::File::open(path)?;if crate::input_snapshot::stamp_handle(&file)?.file_id!=stamp.file_id{return Err(io::Error::new(io::ErrorKind::InvalidData,"native fixture file identity changed before cleanup"))}drop(file);std::fs::remove_file(path)?;self.files.pop();}
  while let Some((path,identity))=self.directories.last(){if crate::frozen_inputs::generation_directory_identity(path,&self.root)?!=*identity{return Err(io::Error::new(io::ErrorKind::InvalidData,"native fixture child directory changed before cleanup"))}std::fs::remove_dir(path)?;self.directories.pop();}
  std::fs::remove_dir(&self.root)
 }
}
impl Drop for NativeFixtureSources{fn drop(&mut self){let _=self.remove();}}

fn native_fixture_io(actual:Box<dyn Error>)->io::Error{match actual.downcast::<io::Error>(){Ok(actual)=>*actual,Err(other)=>io::Error::other(other.to_string())}}
pub(super) fn native_fixture_macro<'a>(source:&'a str,prefix:&str)->io::Result<&'a str>{
 source.split_inclusive('\n').find(|line|line.starts_with(prefix)).ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"native fixture's actual production macro definition is missing"))
}
pub(super) struct NativeSelftestWork<'a>{_credit:&'a dm_preprocess::source_arena_credit::SourceArenaCredit,budget:&'a std::sync::Arc<dq_analyze::captured_generator_budget::Budget>}
impl<'a> NativeSelftestWork<'a>{
 pub(super) fn new(credit:&'a dm_preprocess::source_arena_credit::SourceArenaCredit,budget:&'a std::sync::Arc<dq_analyze::captured_generator_budget::Budget>)->io::Result<Self>{
  let bound=budget.used().checked_add(budget.remaining()).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
  if bound>dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES||credit.reserved_bytes()<bound{return Err(io::Error::new(io::ErrorKind::InvalidInput,"native selftest resource loan exceeds its real existing grant/fixture allowance"))}Ok(Self{_credit:credit,budget})
 }
 pub(super) fn budget(&self)->&std::sync::Arc<dq_analyze::captured_generator_budget::Budget>{self.budget}
}
/// The callback's final String retains the SAME actual operation grant.
/// Catalog consumers get only a borrow and must admit their own failure copy
/// while this owner is live; no unowned String escapes the convenience API.
pub(super) struct NativeFixtureMessage{actual:Result<String,String>,_budget:std::sync::Arc<dq_analyze::captured_generator_budget::Budget>,_credit:dm_preprocess::source_arena_credit::SourceArenaControlCredit}
impl NativeFixtureMessage{
 pub(super) fn new(actual:Result<String,String>,work:&NativeSelftestWork<'_>)->io::Result<Self>{
  let capacity=match &actual{Ok(text)|Err(text)=>text.capacity()};let bytes=capacity.checked_add(std::mem::size_of::<Self>()).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
  work.budget.charge(bytes).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;
  Ok(Self{actual,_credit:work._credit.control(),_budget:std::sync::Arc::clone(work.budget)})
 }
 pub(super) fn outcome(&self)->Result<&str,&str>{self.actual.as_ref().map(String::as_str).map_err(String::as_str)}
 /// Private ownership transfer into the checked catalog fold. Its caller
 /// keeps the SAME original physical grant alive until the fold has admitted
 /// this actual String's capacity and dropped the callback window.
 pub(super) fn take_for_catalog(self,work:&NativeSelftestWork<'_>)->io::Result<Result<String,String>>{
  if !std::sync::Arc::ptr_eq(&self._budget,work.budget){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native fixture message belongs to another callback budget"))}
  let Self{actual,_budget,_credit}=self;drop(_budget);drop(_credit);Ok(actual)
 }

}
struct DerivedNativeFixtureBackend<'a>{host:&'a mut BuildHost,cache:&'a std::path::Path,retained:&'a std::sync::Arc<dq_analyze::captured_generator_budget::Budget>}
impl dq_analyze::derived_selftest_policy::Backend for DerivedNativeFixtureBackend<'_>{
 fn inspect(&mut self,texts:&[(&str,String)])->Result<dq_analyze::derived_selftest_policy::Outcome,dq_analyze::derived_selftest_policy::Failure>{
  use dq_analyze::derived_selftest_policy::Failure;
  let run=(||->Result<dq_analyze::derived_selftest_policy::Outcome,Box<dyn Error>>{
   crate::daemon::control::checkpoint()?;
   let source_bytes=texts.iter().try_fold(0usize,|n,(relative,text)|n.checked_add(relative.len()).and_then(|n|n.checked_add(text.len()))).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
   if source_bytes>dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"actual derived fixture sources exceed the existing fixture allowance").into())}
   let metadata=source_bytes.checked_mul(64).and_then(|n|n.checked_add(self.cache.as_os_str().len().checked_mul(128)?)).and_then(|n|n.checked_add(64*1024)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;let _credit=self.host.source_arena_work().reserve(metadata)?;
   let mut scratch=NativeFixtureSources::new(self.cache)?;
   let actual=(||->Result<dq_analyze::derived_selftest_policy::Outcome,Box<dyn Error>>{
    // These are the actual definitions, including real setter bodies. No
    // identity/no-op macro stand-in supplies native declaration or BODY facts.
    let capabilities=include_str!("../../../../../code/defines/engine/capabilities.dm");let markers=include_str!("../../../../../code/defines/engine/declare/markers.dm");let time=include_str!("../../../../../code/defines/engine/time.dm");let byond=include_str!("../../../../../code/__byond_version_compat.dm");
    let mut definitions=String::new();for(source,name)in[(capabilities,"#define TRACKED_UNCHANGED("),(capabilities,"#define SETTER("),(capabilities,"#define TRACKED("),(markers,"#define CAPABILITIES("),(time,"#define SECONDS "),(byond,"#define PROC_REF(")]{definitions.push_str(native_fixture_macro(source,name)?);}
    scratch.put("code/engine/_generated/auto_tracked.dm",definitions.as_bytes())?;scratch.put("code/_generated/reads.dm",b"// native selftest intentionally compares actual generated DATA\n")?;
    let mut manifest=String::from("#include \"code/engine/_generated/auto_tracked.dm\"\n");
    for(relative,text)in texts{
     // Same relation intent through the current genuine macro + raw schema
     // production. Historical REL classification remains an isolated DATA test.
     let native=text.replace("REL(/obj/thing, parent)","CAPABILITIES(/obj/thing)\n\tref_one(nameof(parent))");
     scratch.put(relative,native.as_bytes())?;manifest.push_str(&format!("#include \"{relative}\"\n"));
    }
    manifest.push_str("#include \"code/_generated/reads.dm\"\n");scratch.put("deepquarry.dme",manifest.as_bytes())?;
    scratch.put("tools/ci/lint_scopes.toml",include_bytes!("../../../../ci/lint_scopes.toml"))?;
    let root=std::fs::canonicalize(&scratch.root)?;let cache=std::fs::canonicalize(self.cache)?;
    let crate::request::Command::Build(build)=crate::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()])?else{return Err(io::Error::other("native fixture requires its actual preparation request").into())};let mut request=*build;
    request.cache_root=Some(cache);request.timeout_seconds=Some(300);request.workers=1;request.progress_enabled=false;request.engine_template=None;request.bootstrap_catalog=false;
    use crate::policy_request::{PolicyInputRequest,WorkspacePolicyRequest,WorkspaceAuxiliaryQuestion as Q,AnalysisContext};let directories=Q::authored_doc_ui_roots(Q::PRIVATE_FULL_REGISTRY).ok_or_else(||io::Error::other("actual registry fixture roots absent"))?;
    request.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:directories.iter().map(|directory|root.join(directory)).collect(),configuration:root.join("tools/ci/lint_scopes.toml")}),..Default::default()});
    let mut outcome=None;let mut seen=false;self.host.with_native_derived_fixture_request(request,&mut|fixture|{if seen{return Err("native derived fixture collector repeated its actual callback".into())}seen=true;let actual=fixture.inspect()?;actual.admit_assertion_retention(self.retained).map_err(dq_analyze::captured_reactive_reads::Failure::Operational)?;outcome=Some(actual);Ok(())})?;
    if !seen{return Err(io::Error::new(io::ErrorKind::InvalidData,"native derived fixture collector omitted its actual callback").into())}outcome.ok_or_else(||io::Error::other("native derived fixture outcome absent").into())
   })();
   // The SAME host releases this temporary model before deleting only its
   // authenticated fixture sources. The original first error wins cleanup.
   self.host.clear_regions();let cleanup=scratch.remove();match actual{Err(first)=>Err(first),Ok(value)=>{cleanup?;Ok(value)}}
  })();run.map_err(|actual|Failure::Operational(native_fixture_io(actual)))
 }
}
impl BuildHost{
 pub(crate) fn run_native_derived_fixture_selftest(&mut self,cache:&std::path::Path)->Result<NativeFixtureMessage,Box<dyn Error>>{
  if crate::daemon::control::WorkerContext::capture_for_checkpoints().is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native selftest requires its original active context").into())}
  let _credit=self.source_arena_work().reserve(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES)?;
  let retained=dq_analyze::captured_generator_budget::Budget::new(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;
  self.run_native_derived_fixture_selftest_using(cache,&NativeSelftestWork::new(&_credit,&retained)?)
 }
 /// Caller owns the SAME real operation credit throughout this loan. The
 /// callback catalog uses this entry to avoid a second fixture allowance.
 pub(super) fn run_native_derived_fixture_selftest_using(&mut self,cache:&std::path::Path,work:&NativeSelftestWork<'_>)->Result<NativeFixtureMessage,Box<dyn Error>>{
  if crate::daemon::control::WorkerContext::capture_for_checkpoints().is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native selftest requires its original active context").into())}
  let actual=match dq_analyze::derived_selftest_policy::run(&mut DerivedNativeFixtureBackend{host:self,cache,retained:work.budget},&mut dq_analyze::derived_selftest_policy::NativeAssertions{budget:work.budget,poll:&crate::daemon::control::checkpoint}){Ok(message)=>Ok(message),Err(dq_analyze::derived_selftest_policy::Failure::Assertion(message))=>Err(message),Err(dq_analyze::derived_selftest_policy::Failure::Operational(actual))=>return Err(actual.into())};
  NativeFixtureMessage::new(actual,work).map_err(Into::into)
 }
}

#[cfg(test)]mod native_derived_runtime_selftest_controls{
 use super::*;
 #[test]fn actual_native_derived_callback_uses_same_host_completed_source_and_original_assertions(){
  let cache=crate::test_scratch::dir("native-derived-runtime-callback");let mut host=BuildHost::default();
  let actual=with_full_registry_check_context(crate::request::BuildCommand::PrepareQuery,Some(120),||host.run_native_derived_fixture_selftest(&cache)).unwrap();assert_eq!(actual.outcome().unwrap(),"derived_reads_lint selftest passed");
 }
 #[test]fn actual_native_derived_callback_mismatch_remains_typed_assertion_and_next_run_recovers(){
  struct Changed<'a>(DerivedNativeFixtureBackend<'a>);
  impl dq_analyze::derived_selftest_policy::Backend for Changed<'_>{fn inspect(&mut self,texts:&[(&str,String)])->Result<dq_analyze::derived_selftest_policy::Outcome,dq_analyze::derived_selftest_policy::Failure>{let changed:Vec<_>=texts.iter().map(|(relative,text)|(*relative,text.replace("return energy < max_energy","return max_energy"))).collect();dq_analyze::derived_selftest_policy::Backend::inspect(&mut self.0,&changed)}}
  let cache=crate::test_scratch::dir("native-derived-runtime-mismatch");let mut host=BuildHost::default();
  with_full_registry_check_context(crate::request::BuildCommand::PrepareQuery,Some(120),||{let _credit=host.source_arena_work().reserve(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES)?;let budget=dq_analyze::captured_generator_budget::Budget::new(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;let failure=dq_analyze::derived_selftest_policy::run(&mut Changed(DerivedNativeFixtureBackend{host:&mut host,cache:&cache,retained:&budget}),&mut dq_analyze::derived_selftest_policy::NativeAssertions{budget:&budget,poll:&crate::daemon::control::checkpoint});assert!(matches!(failure,Err(dq_analyze::derived_selftest_policy::Failure::Assertion(ref text))if text.contains("missing declaration")));assert!(host.run_native_derived_fixture_selftest(&cache)?.outcome().is_ok());Ok(())}).unwrap();
 }
}

#[cfg(test)]mod native_derived_retention_controls{
 use super::*;
 #[test]fn actual_native_derived_outcome_transfer_denies_unfunded_escape_then_same_owner_recovers(){
  let cache=crate::test_scratch::dir("native-derived-outcome-transfer");let mut host=BuildHost::default();
  with_full_registry_check_context(crate::request::BuildCommand::PrepareQuery,Some(120),||{
   let credit=host.source_arena_work().reserve(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES)?;
   let fixed=std::mem::size_of::<dq_analyze::captured_generator_budget::Budget>()+2*std::mem::size_of::<usize>();let tight=dq_analyze::captured_generator_budget::Budget::new(fixed).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;
   let result=dq_analyze::derived_selftest_policy::Backend::inspect(&mut DerivedNativeFixtureBackend{host:&mut host,cache:&cache,retained:&tight},&[("code/a.dm","/obj/probe\n    var/glow\n/obj/probe/draw()\n    return glow\n".into())]);assert!(matches!(result,Err(dq_analyze::derived_selftest_policy::Failure::Operational(ref actual))if actual.kind()==io::ErrorKind::OutOfMemory));
   let healthy=dq_analyze::captured_generator_budget::Budget::new(dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;assert!(host.run_native_derived_fixture_selftest_using(&cache,&NativeSelftestWork{_credit:&credit,budget:&healthy})?.outcome().is_ok());Ok(())
  }).unwrap();
 }
}

impl BuildHost{pub(crate) fn with_native_ui_fixture_request(&mut self,mut request:crate::request::BuildRequest,visit:&mut dq_analyze::captured_ui_actions::FixtureVisitor<'_>)->Result<(),Box<dyn Error>>{
 if crate::daemon::control::WorkerContext::capture_for_checkpoints().is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native UI fixture requires its original active selftest context").into())}
 request.exact_inputs=true;request.no_cache=true;
 let plan=super::prepare_native_registered_check_selection(&["ui_actions".into()],FullRegistryCheckOptions{raw:true,unused:false,..Default::default()},self.source_arena_work())?;
 let(_root,_cache,project,_budget,_credit)=self.prepare_registered_check_request(&mut request,&plan)?;
 let(_outcome,snapshot,inputs)=crate::request_runner::native_check_source::prepare_registered_source_check(request,self,std::sync::Arc::clone(&plan))?;
 inputs.require_binding(&snapshot,&plan)?;inputs.require_current(&project)?;
 snapshot.with_registered_ui_fixture(&plan,visit)?;
 inputs.require_binding(&snapshot,&plan)?;inputs.require_current(&project)?;crate::daemon::control::checkpoint()?;Ok(())
}}

impl BuildHost{pub(crate) fn with_native_sys_reactive_fixture_request<T>(&mut self,mut request:crate::request::BuildRequest,visit:impl FnOnce(&dq_analyze::captured_sys_reactive::Data)->io::Result<T>)->Result<T,Box<dyn Error>>{
 if crate::daemon::control::WorkerContext::capture_for_checkpoints().is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"Sys reactive fixture needs its original active selftest context").into())}
 request.exact_inputs=true;request.no_cache=true;
 let completed=self.stage_selected_registry_check_report(request,FullRegistryCheckOptions{raw:true,unused:false,..Default::default()},&["sys/dx_reactive".into()])?;
 completed.inputs.require_report_current(&completed.project)?;
 let result={let state=self.query_state.try_lock().map_err(|_|io::Error::new(io::ErrorKind::WouldBlock,"Sys fixture actual model borrowed"))?;let snapshot=state.snapshot.as_ref().ok_or_else(||io::Error::other("Sys fixture actual model absent"))?;snapshot.with_native_sys_reactive_fixture(visit)?};
 completed.inputs.require_report_current(&completed.project)?;crate::daemon::control::checkpoint()?;Ok(result)
}}

impl BuildHost{
 pub(in crate::runner_host) fn stage_registered_baseline_plan(&mut self,request:crate::request::BuildRequest,plan:std::sync::Arc<super::NativeCheckSelection>,domain:Option<&crate::request_runner::runner_freshness::GenerationInputClosure>)->Result<(FullRegistryCheckInputs,dq_analyze::full_registry_check_wire::CheckFrame,super::baseline_update::Builder),Box<dyn Error>>{
  let mode=plan.baseline_mode().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"baseline coordinator lost its actual selected purpose"))?;
  if plan.format().raw||plan.audit_unused(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"baseline plan cannot borrow raw judgment or whole-unused capture").into())}
  if plan.names().len()==plan.registered_count()?{
   let(inputs,frame,_clean,diagnostics,checker,report,builder)=self.stage_full_registry_baseline_plan(request,domain,mode)?;
   drop((diagnostics,checker,report));
   if builder.observed_count()!=plan.names().len(){return Err(io::Error::new(io::ErrorKind::InvalidData,"full baseline omitted an actual registered producer").into())}
   return Ok((FullRegistryCheckInputs::Model(inputs),frame.observation_data().into(),builder))
  }
  let completed=if plan.source_handler_union_candidate(){self.stage_registered_source_handler_check_report_using_baseline(request,std::sync::Arc::clone(&plan),domain)?}
   else if plan.exclusive_engine_layering(){self.stage_exclusive_registered_engine_check_report_using_baseline(request,std::sync::Arc::clone(&plan),domain)?}
   else if plan.has_unjoined_handlers(){return Err(io::Error::new(io::ErrorKind::Unsupported,"selected baseline requires the actual joined Handler producer; no model fallback").into())}
   else if plan.handlers_only(){match self.stage_registered_handlers_check_report_using_baseline(request,std::sync::Arc::clone(&plan),domain)?{HandlerCheckStage::Current(actual)=>actual,HandlerCheckStage::FailedFullOneShot{actual,..}=>return Err(actual)}}
   else if plan.source_only(){self.stage_source_registry_check_report_using_baseline(request,std::sync::Arc::clone(&plan),domain)?}
   else{self.stage_registered_model_check_report_using_baseline(request,std::sync::Arc::clone(&plan),domain)?};
  let FullRegistryCheckReport{inputs,frame,diagnostics,report,_credit,..}=completed;drop((diagnostics,report));let builder=_credit.into_baseline()?;
  if builder.observed_count()!=plan.names().len(){return Err(io::Error::new(io::ErrorKind::InvalidData,"selected baseline omitted an actual producer callback").into())}
  Ok((inputs,frame,builder))
 }
}

/// Actual policy verdict remains distinct from timing-command process status.
#[derive(Debug,PartialEq,Eq)]pub struct CheckCliOutcome{pub clean:bool,pub selftests:Option<dq_analyze::full_registry_check_wire::Selftests>}
impl BuildHost{
 pub fn write_selected_registry_check_with_cli_observations(&mut self,request:crate::request::BuildRequest,options:FullRegistryCheckOptions,selectors:&[String],selftests:bool,caller:Option<std::path::PathBuf>,cli:&dq_analyze::native_check_cli_wire::Request,diagnostics:&mut impl Write,report:&mut impl Write,usage:&mut impl Write)->Result<CheckCliOutcome,Box<dyn Error>>{
  with_full_registry_check_context(request.command,request.timeout_seconds,||{
   cli.qualify(options,selftests)?;let completed=self.stage_selected_registry_check_cli_mode(request,options,selectors,selftests,caller,Some(cli))?;
   let FullRegistryCheckReport{project,inputs,clean,selftests,diagnostics:diagnostics_stage,report:report_stage,cli:actual,_credit,..}=completed;
   let mut actual=actual.ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"actual CHECK CLI producer omitted its requested output owner"))?;
   if actual.binding!=cli.binding()?||actual.usage_requested!=cli.allow_usage{return Err(io::Error::new(io::ErrorKind::InvalidData,"actual CHECK CLI output owner differs from requested mode").into())}
   inputs.require_report_current(&project)?;
   if let Some(stage)=diagnostics_stage{stage.publish(diagnostics)?;}
   if actual.usage_requested{if let Some(stage)=actual.usage.take(){stage.publish(usage)?;}else{usage.flush()?;}}
   report_stage.publish(report)?;inputs.require_report_current(&project)?;crate::daemon::control::checkpoint()?;
   Ok(CheckCliOutcome{clean,selftests})
  })
 }
}

#[path="runner_parity_scratch.rs"]pub(crate) mod parity_scratch;
impl FullRegistryCheckInputs{
 pub(crate) fn with_report_input_observation<T>(&self,project:&std::path::Path,observe:impl FnOnce(&crate::input_snapshot::InputSnapshot)->io::Result<T>)->Result<T,Box<dyn Error>>{match self{
 Self::ReportReplay(actual)=>actual.with_report_input_observation(project,observe),
 Self::SourceHandlers(actual)=>actual.with_report_input_observation(project,observe),
 Self::Model(actual)=>actual.with_report_input_observation(project,observe),
 Self::SelectedModel(actual)=>actual.with_report_input_observation(project,observe),
 Self::Source(actual)=>actual.with_report_input_observation(project,observe),
 Self::Handlers(actual)=>actual.with_report_input_observation(project,observe),
 }}
}
