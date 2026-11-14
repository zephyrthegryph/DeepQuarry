//! Actual source-only native CHECK input ownership. No semantic snapshot, DME
//! read, cloned recorder ledger, detached path inventory, or compiler grant.
//! Held draft: requires the registered capture/snapshot/preparation hook packet.
use super::runner_freshness;
use crate::{input_snapshot::{InputSnapshot,JoinedReportEpoch,RecordingInputs,SnapshotProvider},runner_host::{BuildHost,NativeCheckSelection},request::{BuildOutcome,BuildRequest}};
use crate::runner_host::query_snapshot::RawWorkspaceSnapshot;
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaWork};
use std::{collections::BTreeSet,error::Error,io,path::{Path,PathBuf},sync::Arc};

/// The only recorder transfer is the same existing joined-epoch ownership
/// transfer. The raw snapshot is an immutable alias of the actual issued frame;
/// its Arc-held payloads are not duplicated or reinterpreted as a model.
#[derive(Clone,Copy)]enum SourcePurpose{Registered,EngineUnselected}
pub(crate) struct NativeSourceCheckInputs{
 purpose:SourcePurpose,
 project:PathBuf,plan:Arc<NativeCheckSelection>,snapshot:RawWorkspaceSnapshot,
 inputs:InputSnapshot,_epoch:JoinedReportEpoch,_credit:SourceArenaCredit,
}
pub(super) struct Pending{
 purpose:SourcePurpose,
 project:PathBuf,plan:Arc<NativeCheckSelection>,snapshot:RawWorkspaceSnapshot,
 epoch:JoinedReportEpoch,_credit:SourceArenaCredit,
}
impl Pending{
 pub(super) fn capture<P:SnapshotProvider>(recording:&RecordingInputs<P>,project:&Path,plan:Arc<NativeCheckSelection>,snapshot:&RawWorkspaceSnapshot,capture:Arc<crate::runner_host::workspace_capture::WorkspaceCapture>,generated:&BTreeSet<PathBuf>,work:&dyn SourceArenaWork)->Result<(Self,runner_freshness::WorkspacePolicyAdmission),Box<dyn Error>>{
  work.checkpoint()?;
  snapshot.require_registered_source_plan(&plan)?;
  if !snapshot.matches_context(project,&Default::default(),Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290)){
   return Err(io::Error::new(io::ErrorKind::InvalidInput,"source CHECK namespace differs from its actual raw frame").into())
  }
  let(admission,epoch)=recording.with_joined_report_snapshot(|inputs|runner_freshness::admit_registered_source_ledger(inputs,generated,capture))?;
  let width=project.as_os_str().len().checked_mul(4).and_then(|n|n.checked_add(4096+std::mem::size_of::<Self>()+std::mem::size_of::<NativeSourceCheckInputs>())).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
  let credit=work.reserve(width)?;
  Ok((Self{purpose:SourcePurpose::Registered,project:project.to_owned(),plan,snapshot:snapshot.clone(),epoch,_credit:credit},admission))
 }
 pub(super) fn capture_engine_unselected<P:SnapshotProvider>(recording:&RecordingInputs<P>,project:&Path,plan:Arc<NativeCheckSelection>,snapshot:&RawWorkspaceSnapshot,generated:&BTreeSet<PathBuf>,work:&dyn SourceArenaWork)->Result<Self,Box<dyn Error>>{
  work.checkpoint()?;snapshot.require_engine_unselected_plan(&plan)?;
  if !snapshot.matches_context(project,&Default::default(),Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290)){return Err(io::Error::new(io::ErrorKind::InvalidInput,"empty Engine actual source namespace differs").into())}
  let((),epoch)=recording.with_joined_report_snapshot(|inputs|runner_freshness::admit_live(inputs,generated))?;
  let bytes=project.as_os_str().len().checked_mul(4).and_then(|n|n.checked_add(4096+std::mem::size_of::<Self>()+std::mem::size_of::<NativeSourceCheckInputs>())).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
  let credit=work.reserve(bytes)?;Ok(Self{purpose:SourcePurpose::EngineUnselected,project:project.to_owned(),plan,snapshot:snapshot.clone(),epoch,_credit:credit})
 }
 pub(super) fn finish<P:SnapshotProvider>(self,recording:RecordingInputs<P>)->io::Result<NativeSourceCheckInputs>{
  let inputs=recording.into_joined_report_snapshot(&self.epoch)?;
  Ok(NativeSourceCheckInputs{purpose:self.purpose,project:self.project,plan:self.plan,snapshot:self.snapshot,inputs,_epoch:self.epoch,_credit:self._credit})
 }
}
fn actual_io(error:Box<dyn Error>)->io::Error{
 match error.downcast::<io::Error>(){Ok(error)=>*error,Err(error)=>io::Error::new(io::ErrorKind::Interrupted,error.to_string())}
}
impl NativeSourceCheckInputs{
 pub(crate) fn require_binding(&self,snapshot:&RawWorkspaceSnapshot,plan:&Arc<NativeCheckSelection>)->io::Result<()>{
  match self.purpose{SourcePurpose::Registered=>self.snapshot.require_same_registered_frame(snapshot,plan),SourcePurpose::EngineUnselected=>{if !Arc::ptr_eq(&self.plan,plan){return Err(io::Error::new(io::ErrorKind::InvalidInput,"empty Engine ledger belongs to another actual selector plan"))}self.snapshot.require_same_engine_unselected_frame(snapshot,plan)}}
 }
 pub(crate) fn require_current(&self,project:&Path)->io::Result<()>{
  crate::daemon::control::checkpoint()?;
  if self.project!=project{return Err(io::Error::new(io::ErrorKind::InvalidInput,"source CHECK ledger belongs to another request namespace"))}
  self.require_purpose()?;
  let current=crate::filesystem_proofs::BulkFileSystemProofs::capture_snapshot(&self.inputs)?;
  let provider=crate::input_snapshot::GeneratedOutputInputs::new(&current,self.inputs.generated_outputs().iter().cloned());
  runner_freshness::admit(&self.inputs,&provider).map_err(actual_io)?;
  if !self.inputs.exact_positive_contents_match(&provider)?{return Err(io::Error::new(io::ErrorKind::Interrupted,"source CHECK input closure changed during operation"))}
  self.require_purpose()
 }
 fn require_purpose(&self)->io::Result<()>{match self.purpose{SourcePurpose::Registered=>self.snapshot.require_registered_source_plan(&self.plan),SourcePurpose::EngineUnselected=>self.snapshot.require_engine_unselected_plan(&self.plan)}}
}

/// Mutable operation-local plumbing through the normal retry loop, never TLS.
/// It is populated only by the actual Source branch AFTER the full recorder has
/// transferred and the exact issued raw snapshot has been admitted to the host.
pub(crate) enum EnginePrepared{Unselected{snapshot:RawWorkspaceSnapshot,inputs:NativeSourceCheckInputs},Model{inputs:super::checker_capture::Inputs}}
pub(super) enum Preparation{
 Engine{plan:Arc<NativeCheckSelection>,prepared:Option<EnginePrepared>},
 Source{plan:Arc<NativeCheckSelection>,prepared:Option<(RawWorkspaceSnapshot,NativeSourceCheckInputs)>},
 Model{plan:Arc<NativeCheckSelection>,prepared:Option<super::checker_capture::Inputs>},
 Handlers{plan:Arc<NativeCheckSelection>,prepared:Option<super::native_check_handlers::Inputs>,failed:Option<super::native_check_handlers::FailedFullOneShot>,failure_staging:super::native_check_handlers::FailureStaging},
}
impl Preparation{
 fn take_engine(&mut self)->Option<EnginePrepared>{match self{Self::Engine{prepared,..}=>prepared.take(),_=>None}}

 pub(super) fn record_engine(&mut self,value:EnginePrepared)->io::Result<()>{match self{Self::Engine{prepared,..}=>{*prepared=Some(value);Ok(())},_=>Err(io::Error::new(io::ErrorKind::InvalidInput,"nonEngine preparation cannot receive Engine frame"))}}

 pub(super) fn engine_plan(&self)->Option<&Arc<NativeCheckSelection>>{match self{Self::Engine{plan,..}=>Some(plan),_=>None}}

 pub(super) fn source_plan(&self)->Option<&Arc<NativeCheckSelection>>{match self{Self::Source{plan,..}=>Some(plan),_=>None}}
 pub(super) fn model_plan(&self)->Option<&Arc<NativeCheckSelection>>{match self{Self::Model{plan,..}=>Some(plan),_=>None}}
 pub(super) fn handlers_plan(&self)->Option<&Arc<NativeCheckSelection>>{match self{Self::Handlers{plan,..}=>Some(plan),_=>None}}
 pub(super) fn begin_attempt(&mut self)->io::Result<()>{match self{Self::Source{prepared,..}=>*prepared=None,Self::Model{prepared,..}=>*prepared=None,Self::Engine{prepared,..}=>*prepared=None,Self::Handlers{prepared,failed,failure_staging,..}=>{*prepared=None;*failed=None;failure_staging.restart()?;}}Ok(())}
 pub(super) fn record_source(&mut self,snapshot:RawWorkspaceSnapshot,inputs:NativeSourceCheckInputs)->io::Result<()>{match self{Self::Source{prepared,..}=>{*prepared=Some((snapshot,inputs));Ok(())},_=>Err(io::Error::new(io::ErrorKind::InvalidInput,"non-raw preparation cannot receive a raw-only frame"))}}
 pub(super) fn record_model(&mut self,inputs:super::checker_capture::Inputs)->io::Result<()>{match self{Self::Model{prepared,..}=>{*prepared=Some(inputs);Ok(())},_=>Err(io::Error::new(io::ErrorKind::InvalidInput,"non-model preparation cannot receive a semantic model ledger"))}}
 pub(super) fn record_handlers(&mut self,inputs:super::native_check_handlers::Inputs)->io::Result<()>{match self{Self::Handlers{prepared,failed,..}=>{if prepared.is_some()||failed.is_some(){return Err(io::Error::new(io::ErrorKind::InvalidData,"Handler recorder transfer repeated or follows failed-full"))}*prepared=Some(inputs);Ok(())},_=>Err(io::Error::new(io::ErrorKind::InvalidInput,"non-handler preparation cannot receive a Handler ledger"))}}
 fn take_source(&mut self)->Option<(RawWorkspaceSnapshot,NativeSourceCheckInputs)>{match self{Self::Source{prepared,..}=>prepared.take(),_=>None}}
 fn take_model(&mut self)->Option<super::checker_capture::Inputs>{match self{Self::Model{prepared,..}=>prepared.take(),_=>None}}
 pub(super) fn handler_failure_staging(&mut self)->Option<&mut super::native_check_handlers::FailureStaging>{match self{Self::Handlers{failure_staging,..}=>Some(failure_staging),_=>None}}
 pub(super) fn record_failed_handlers(&mut self,actual:super::native_check_handlers::FailedFullOneShot)->io::Result<()>{match self{Self::Handlers{prepared,failed,..} if prepared.is_none()&&failed.is_none()=>{*failed=Some(actual);Ok(())},_=>Err(io::Error::new(io::ErrorKind::InvalidData,"failed Handler callback cannot replace a current or repeated outcome"))}}
 fn take_failed_handlers(&mut self)->Option<super::native_check_handlers::FailedFullOneShot>{match self{Self::Handlers{failed,..}=>failed.take(),_=>None}}
 fn take_handlers(&mut self)->Option<super::native_check_handlers::Inputs>{match self{Self::Handlers{prepared,..}=>prepared.take(),_=>None}}
}

pub(crate) fn prepare_registered_source_check(mut request:BuildRequest,host:&mut BuildHost,plan:Arc<NativeCheckSelection>)->Result<(BuildOutcome,RawWorkspaceSnapshot,NativeSourceCheckInputs),Box<dyn Error>>{
 use crate::request::BuildCommand;
 if request.command!=BuildCommand::PrepareQuery||!host.retains_artifacts()||!plan.source_only()
  ||request.record_inputs.is_some()||request.replay_inputs.is_some()||request.no_daemon
  ||request.engine_template.is_some()||request.bootstrap_catalog||request.diagnostic_declarations
  ||request.source_questions.is_some()||!request.defines.is_empty()
  ||request.policy_inputs.as_ref().is_none_or(|input|input.analysis_context!=Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290)||input.workspace.is_none()||!input.workspace_auxiliary.is_empty()||!input.workspace_generators.is_empty()||!input.files.is_empty()||!input.search_folders.is_empty()){return Err(io::Error::new(io::ErrorKind::InvalidInput,"selected source CHECK requires its actual retained source-only preparation").into())}
 request.exact_inputs=true;
 request.no_cache|=plan.format().no_cache;
 let mut preparation=Preparation::Source{plan,prepared:None};
 let mut writer=crate::daemon::stderr_writer();let mut output=super::PreparationDiagnosticOutput::immediate(&mut writer);
 let outcome=super::run_build_with_selected_publication(request,host,None,None,&mut output,None,None,false,Some(&mut preparation))?;
 if !matches!(outcome,BuildOutcome::RawQueryPrepared{..}){return Err(io::Error::new(io::ErrorKind::InvalidData,"source CHECK preparation returned a model/compiler outcome").into())}
 let(snapshot,inputs)=preparation.take_source().ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"source CHECK did not transfer its actual raw snapshot and recorder"))?;
 Ok((outcome,snapshot,inputs))
}

// Source-only ownership definitions. Private metadata controls remain UNRUN;
// actual production report execution is exercised by the narrow public target.
#[cfg(test)]mod registered_source_input_controls{
 use super::*;
 use crate::{policy_request::{AnalysisContext,PolicyInputRequest,WorkspacePolicyRequest},request::{BuildRequest,Command},runner_host::{BuildHost,FullRegistryCheckOptions,prepare_native_check_selection}};
 fn fixture(label:&str,host:&BuildHost)->(PathBuf,BuildRequest,Arc<NativeCheckSelection>){
  let root=crate::test_scratch::dir(label);let cache=crate::test_scratch::dir(&format!("{label}-cache"));
  let root=std::fs::canonicalize(root).unwrap();let cache=std::fs::canonicalize(cache).unwrap();
  let plan=prepare_native_check_selection(&["scheduler".into()],FullRegistryCheckOptions{raw:true,unused:false,..Default::default()},host.source_arena_work()).unwrap();
  let mut roots=Vec::new();for(directory,_)in plan.roots(){let path=root.join(directory);if !roots.contains(&path){std::fs::create_dir_all(&path).unwrap();roots.push(path)}}
  std::fs::create_dir_all(root.join("tools/ci")).unwrap();std::fs::write(root.join("tools/ci/lint_scopes.toml"),"").unwrap();
  // Genuine malformed body: source-only capture must not demand a semantic
  // parse or invent a successful checker/compiler result in order to read it.
  std::fs::write(root.join("code/probe.dm"),"/proc/probe()\n    unexpected [[[\n").unwrap();
  assert!(!root.join("deepquarry.dme").exists());
  let Command::Build(request)=crate::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()else{panic!("real request parser")};let mut request=*request;
  request.no_cache=true;request.exact_inputs=true;request.progress_enabled=false;request.workers=1;request.timeout_seconds=Some(60);request.cache_root=Some(cache);request.engine_template=None;request.bootstrap_catalog=false;
  request.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:roots,configuration:root.join("tools/ci/lint_scopes.toml")}),..Default::default()});
  (root,request,plan)
 }
 #[test]fn actual_source_check_moves_one_real_missing_manifest_ledger_and_refuses_equal_plan_data_or_later_frame(){
  let mut host=BuildHost::default();let(root,request,plan)=fixture("registered-source-owner",&host);
  let before=host.query_db().db().stats(dm_query::Kind(4)).computed;
  let(outcome,first,inputs)=prepare_registered_source_check(request.clone(),&mut host,Arc::clone(&plan)).unwrap();assert!(matches!(outcome,BuildOutcome::RawQueryPrepared{retained:true,..}));
  inputs.require_binding(&first,&plan).unwrap();inputs.require_current(&request.project).unwrap();
  let equal=prepare_native_check_selection(&["scheduler".into()],plan.format(),host.source_arena_work()).unwrap();assert_eq!(equal.binding(),plan.binding());assert!(!Arc::ptr_eq(&equal,&plan));assert_eq!(inputs.require_binding(&first,&equal).unwrap_err().kind(),io::ErrorKind::InvalidInput);
  let(_,second,other)=prepare_registered_source_check(request.clone(),&mut host,Arc::clone(&plan)).unwrap();other.require_binding(&second,&plan).unwrap();assert_eq!(inputs.require_binding(&second,&plan).unwrap_err().kind(),io::ErrorKind::InvalidInput);
  assert_eq!(host.query_db().db().stats(dm_query::Kind(4)).computed,before);assert!(!root.join("deepquarry.dme").exists());
 }
 #[test]fn actual_source_check_current_barrier_detects_changed_real_payload_then_reprepares(){
  let mut host=BuildHost::default();let(root,request,plan)=fixture("registered-source-current",&host);
  let(_,snapshot,inputs)=prepare_registered_source_check(request.clone(),&mut host,Arc::clone(&plan)).unwrap();inputs.require_binding(&snapshot,&plan).unwrap();inputs.require_current(&request.project).unwrap();
  std::fs::write(root.join("code/probe.dm"),"/proc/probe()\n    sleep(1)\n").unwrap();assert!(inputs.require_current(&request.project).is_err());
  let(_,new_snapshot,current)=prepare_registered_source_check(request.clone(),&mut host,Arc::clone(&plan)).unwrap();current.require_binding(&new_snapshot,&plan).unwrap();current.require_current(&request.project).unwrap();assert_eq!(inputs.require_binding(&new_snapshot,&plan).unwrap_err().kind(),io::ErrorKind::InvalidInput);
 }
}
pub(crate) fn prepare_registered_model_check(request:BuildRequest,host:&mut BuildHost,plan:Arc<NativeCheckSelection>,diagnostics:&mut crate::selected_report_spool::Stage,checker:Option<&mut crate::selected_report_spool::Stage>)->Result<(BuildOutcome,super::checker_capture::Inputs,Option<super::PreparedCheckerTranscript>),Box<dyn Error>>{
 if request.command!=crate::request::BuildCommand::PrepareQuery||!host.retains_artifacts()||plan.source_only()||checker.is_some()!=plan.needs_checker(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"selected model CHECK requires its actual report-only demand").into())}
 let mut preparation=Preparation::Model{plan,prepared:None};let mut output=match checker{Some(checker)=>super::PreparationDiagnosticOutput::selected_combined(diagnostics,checker),None=>super::PreparationDiagnosticOutput::selected_report(diagnostics)};
 let result=super::run_build_with_selected_publication(request,host,None,None,&mut output,None,None,false,Some(&mut preparation));let write=output.take_error();let transcript=output.take_checker_frame();let outcome=result?;if let Some(error)=write{return Err(error.into())}
 if !matches!(outcome,BuildOutcome::QueryPrepared{..}){return Err(io::Error::new(io::ErrorKind::InvalidData,"registered model CHECK did not issue its actual model frame").into())}
 let inputs=preparation.take_model().ok_or_else(||io::Error::other("registered model CHECK omitted actual recorder transfer"))?;Ok((outcome,inputs,transcript))
}

/// Actual exclusive Handler preparation: Current and failed-full one-shot
/// outcomes are separate. Neither branch falls back to a semantic model.
pub(crate) enum PreparedHandlers {
 Current{outcome:BuildOutcome,inputs:super::native_check_handlers::Inputs},
 FailedFullOneShot{actual:Box<dyn Error>,report:super::native_check_handlers::FailedFullOneShot},
}
pub(crate) fn prepare_registered_handlers_check(request:BuildRequest,host:&mut BuildHost,
 plan:Arc<NativeCheckSelection>)->Result<PreparedHandlers,Box<dyn Error>>{
 prepare_registered_handlers_check_using(request,host,plan,None)
}
pub(super) fn prepare_registered_handlers_check_using(mut request:BuildRequest,host:&mut BuildHost,
 plan:Arc<NativeCheckSelection>,source_override:Option<&(dyn crate::input_snapshot::SnapshotProvider+Sync)>)->Result<PreparedHandlers,Box<dyn Error>>{
 use crate::policy_request::{AnalysisContext,WorkspaceAuxiliaryQuestion as Q};
 if request.command!=crate::request::BuildCommand::PrepareQuery||!host.retains_artifacts()||!plan.handlers_only()
  ||request.record_inputs.is_some()||request.replay_inputs.is_some()||request.no_daemon
  ||request.engine_template.is_some()||request.bootstrap_catalog||request.diagnostic_declarations
  ||request.source_questions.is_some()||!request.defines.is_empty()
  ||request.policy_inputs.as_ref().is_none_or(|intent|intent.analysis_context!=Some(AnalysisContext::OriginalAnalyze0290)
   ||intent.workspace.is_none()||intent.workspace_auxiliary!=[Q::SemHandlers]
   ||!intent.workspace_generators.is_empty()||!intent.files.is_empty()||!intent.search_folders.is_empty()){
  return Err(io::Error::new(io::ErrorKind::InvalidInput,"conditional Handler CHECK requires its actual exclusive native preparation").into())
 }
 request.exact_inputs=true;request.no_cache|=plan.format().no_cache;
 let cache=request.cache_root.as_deref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"Handler CHECK requires explicit external cache"))?;
 let failure_staging=super::native_check_handlers::FailureStaging::new(Arc::clone(&plan),cache,host.source_arena_work())?;
 let mut preparation=Preparation::Handlers{plan,prepared:None,failed:None,failure_staging};
 // Semantic notices are replayed exactly once by the real current Handler
 // report API. Ordinary preparation tracing remains in its lifecycle stream.
 let mut trace=crate::daemon::stderr_writer();let mut output=super::PreparationDiagnosticOutput::immediate(&mut trace);
 let pending=super::run_build_with_selected_publication(request,host,None,None,&mut output,source_override,None,false,Some(&mut preparation));
 let output_error=output.take_error();let outcome=match pending{
  Ok(outcome)=>outcome,
  Err(actual)=>return match preparation.take_failed_handlers(){Some(report)=>Ok(PreparedHandlers::FailedFullOneShot{actual,report}),None=>Err(actual)},
 };if let Some(actual)=output_error{return Err(actual.into())}
 if !matches!(outcome,BuildOutcome::HandlersQueryPrepared{retained:true,..}){
  return Err(io::Error::new(io::ErrorKind::InvalidData,"Handler CHECK preparation returned another source role").into())
 }
 let inputs=preparation.take_handlers().ok_or_else(||io::Error::other("Handler CHECK did not move its actual recorder ledger"))?;
 Ok(PreparedHandlers::Current{outcome,inputs})
}

/// Exact exclusive selected Engine; actual preflight chooses a real Raw or Model result.
pub(crate) fn prepare_registered_engine_check(mut request:BuildRequest,host:&mut BuildHost,plan:Arc<NativeCheckSelection>,diagnostics:&mut crate::selected_report_spool::Stage)->Result<(BuildOutcome,EnginePrepared),Box<dyn Error>>{
 if request.command!=crate::request::BuildCommand::PrepareQuery||!host.retains_artifacts()||!plan.exclusive_engine_layering()||request.record_inputs.is_some()||request.replay_inputs.is_some()||request.no_daemon||request.engine_template.is_some()||request.bootstrap_catalog||request.diagnostic_declarations||request.source_questions.is_some()||!request.defines.is_empty()||request.policy_inputs.as_ref().is_none_or(|p|p.workspace_auxiliary.as_slice()!=[crate::policy_request::WorkspaceAuxiliaryQuestion::EngineLayering]||p.analysis_context!=Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290)||p.workspace.is_none()||!p.files.is_empty()||!p.search_folders.is_empty()||!p.workspace_generators.is_empty()){return Err(io::Error::new(io::ErrorKind::InvalidInput,"exclusive selected Engine actual purpose required").into())}
 request.exact_inputs=true;request.no_cache|=plan.format().no_cache;
 let mut preparation=Preparation::Engine{plan,prepared:None};let mut output=super::PreparationDiagnosticOutput::selected_report(diagnostics);
 let pending=super::run_build_with_selected_publication(request,host,None,None,&mut output,None,None,false,Some(&mut preparation));let write=output.take_error();let checker=output.take_checker_frame();let outcome=pending?;if let Some(first)=write{return Err(first.into())}if checker.is_some(){return Err(io::Error::new(io::ErrorKind::InvalidData,"exclusive Engine must not run Checker").into())}
 let prepared=preparation.take_engine().ok_or_else(||io::Error::other("actual selected Engine frame/recorder transfer absent"))?;
 if !matches!((&outcome,&prepared),(BuildOutcome::RawQueryPrepared{..},EnginePrepared::Unselected{..})|(BuildOutcome::QueryPrepared{..},EnginePrepared::Model{..})){return Err(io::Error::new(io::ErrorKind::InvalidData,"actual Engine outcome was relabelled").into())}Ok((outcome,prepared))
}

#[cfg(test)]mod selected_engine_owner_controls{
 use super::*;
 fn request(root:&Path,cache:&Path)->BuildRequest{
  let crate::request::Command::Build(request)=crate::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()else{panic!("actual prepare request")};let mut request=*request;request.no_cache=true;request.exact_inputs=true;request.workers=1;request.timeout_seconds=Some(60);request.progress_enabled=false;request.engine_template=None;request.bootstrap_catalog=false;request.cache_root=Some(cache.to_owned());request.policy_inputs=Some(crate::policy_request::PolicyInputRequest{analysis_context:Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290),workspace:Some(crate::policy_request::WorkspacePolicyRequest{root:root.to_owned(),recursive_roots:vec![root.join("code")],configuration:root.join("tools/ci/lint_scopes.toml")}),workspace_auxiliary:vec![crate::policy_request::WorkspaceAuxiliaryQuestion::EngineLayering],..Default::default()});request
 }
 #[test]fn actual_selected_engine_empty_ledger_denies_foreign_equal_selector_and_real_other_frame(){
  let root=crate::test_scratch::dir("selected-engine-owner-root");let cache=crate::test_scratch::dir("selected-engine-owner-cache");std::fs::create_dir_all(root.join("code/engine")).unwrap();std::fs::create_dir_all(root.join("tools/ci")).unwrap();std::fs::write(root.join("code/engine/probe.dm"),"/proc/unselected_bad(\n").unwrap();std::fs::write(root.join("tools/ci/lint_scopes.toml"),"[lint.engine_layering]\nexempt_files=[\"code/engine/probe.dm\"]\n").unwrap();let root=std::fs::canonicalize(root).unwrap();let cache=std::fs::canonicalize(cache).unwrap();
  let _context=crate::daemon::control::bind_with_deadline(crate::daemon::control::Cancellation::default(),std::time::Instant::now()+std::time::Duration::from_secs(30));let mut first=BuildHost::default();let mut second=BuildHost::default();let selectors=vec!["engine_layering".to_owned()];let one=crate::runner_host::prepare_native_check_selection(&selectors,crate::runner_host::FullRegistryCheckOptions::default(),first.source_arena_work()).unwrap();let two=crate::runner_host::prepare_native_check_selection(&selectors,crate::runner_host::FullRegistryCheckOptions::default(),second.source_arena_work()).unwrap();assert!(!Arc::ptr_eq(&one,&two));
  let mut diagnostics=crate::selected_report_spool::Stage::new(&cache).unwrap();let(outcome,a)=prepare_registered_engine_check(request(&root,&cache),&mut first,Arc::clone(&one),&mut diagnostics).unwrap();assert!(matches!(outcome,BuildOutcome::RawQueryPrepared{retained:true,..}));let EnginePrepared::Unselected{snapshot,inputs}=a else{panic!("actual selection is empty")};inputs.require_binding(&snapshot,&one).unwrap();assert_eq!(inputs.require_binding(&snapshot,&two).unwrap_err().kind(),io::ErrorKind::InvalidInput);
  let(_,b)=prepare_registered_engine_check(request(&root,&cache),&mut second,two,&mut diagnostics).unwrap();let EnginePrepared::Unselected{snapshot:other,..}=b else{panic!("actual selection is empty")};assert_eq!(inputs.require_binding(&other,&one).unwrap_err().kind(),io::ErrorKind::InvalidInput);inputs.require_current(&root.join("deepquarry.dme")).unwrap();assert_eq!(diagnostics.length(),0);
 }
}
