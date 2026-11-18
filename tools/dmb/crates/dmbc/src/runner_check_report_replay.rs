//! Optional report-only use of the EXISTING process-wide compound slot.
//! Never a compiled publication, serialized authority or image/names marker.
use std::{error::Error,io,path::{Path,PathBuf}};
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaWork};
use super::{BuildHost,compound_replay::{Entry as SlotEntry,RetainedSlot},full_registry_check::{FullRegistryCheckInputs as Inputs,FullRegistryCheckReport as Report,FullCheckCredit},FullRegistryCheckOptions as Options};
use crate::{request::BuildRequest,selected_report_spool::Verified};

#[derive(Clone,Copy,Eq,PartialEq)]struct Shape{workers:usize,progress:bool,timeout:Option<u16>}
pub(super) struct Candidate{root:PathBuf,cache:PathBuf,shape:Shape,options:Options}
struct Key { candidate:Candidate,selectors:Vec<String>,caller:Option<PathBuf> }
impl Candidate{
 fn matches(&self,request:&BuildRequest,options:Options)->io::Result<bool>{let Some((workspace,cache))=closed_shape(request)?else{return Ok(false)};Ok(self.options==options&&self.shape==shape(request)&&workspace.root==self.root&&cache==self.cache&&request.project.strip_prefix(&self.root).ok()==Some(Path::new("deepquarry.dme")))}
}
fn shape(request:&BuildRequest)->Shape{Shape{workers:request.workers,progress:request.progress_enabled,timeout:request.timeout_seconds}}
fn closed_shape(request:&BuildRequest)->io::Result<Option<(&crate::policy_request::WorkspacePolicyRequest,&Path)>>{
 let roots=crate::policy_request::WorkspaceAuxiliaryQuestion::authored_doc_ui_roots(crate::policy_request::WorkspaceAuxiliaryQuestion::PRIVATE_FULL_REGISTRY).ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"actual full registry has no closed roots"))?;
 if request.no_cache||request.warnings!=crate::diagnostics::WarningPolicy::default(){return Ok(None)}let(workspace,cache)=super::original_exclusions_shape(request,roots)?;
 if workspace.configuration.strip_prefix(&workspace.root).ok()!=Some(Path::new("tools/ci/lint_scopes.toml"))||workspace.recursive_roots.iter().zip(roots).any(|(actual,expected)|actual.strip_prefix(&workspace.root).ok()!=Some(Path::new(expected))){return Err(io::Error::new(io::ErrorKind::InvalidInput,"report replay key differs from actual closed namespace"))}Ok(Some((workspace,cache)))
}
/// Credit outlives both Entry fields AND the Box allocation itself.
pub(crate) struct Loan { entry:Box<Entry>, _credit:SourceArenaCredit, _slot:RetainedSlot }
struct Entry { key:Key, actual:Report }
impl Loan {
 pub(crate) fn require_current(&self,project:&Path)->Result<(),Box<dyn Error>> {self.entry.actual.inputs.require_report_current(project)}
 fn matches(&self,request:&BuildRequest,options:Options,selectors:&[String],caller:Option<&Path>)->io::Result<bool> {
  Ok(self.entry.key.candidate.matches(request,options)? && self.entry.key.selectors==selectors && self.entry.key.caller.as_deref()==caller)
 }
 fn output_current(&self)->Result<bool,Box<dyn Error>> {
  let actual=&self.entry.actual;
  // Only this actual report-purpose owner is eligible. Other variants cannot
  // be promoted or reconstructed as a full model by the cache.
  let Inputs::Model(inputs)=&actual.inputs else{return Ok(false)};
  if !inputs.replay_inputs_current(&actual.project)? {return Ok(false)}
  inputs.require_report_current(&actual.project)?;
  if let Some(file)=&actual.diagnostics {if !file.check_replay()?{return Ok(false)}}
  Ok(actual.report.check_replay()?)
 }
 fn into_report(self)->io::Result<Report> {
  let actual=&self.entry.actual;
  let diagnostics=actual.diagnostics.as_ref().map(|s|s.replay_alias().ok_or_else(backing_lost)).transpose()?;
  let report=actual.report.replay_alias().ok_or_else(backing_lost)?;
  let credit=FullCheckCredit::Replay(actual._credit.control());
  Ok(Report{project:actual.project.clone(),frame:actual.frame,selection:actual.selection,selected:actual.selected,registered:actual.registered,format:actual.format,clean:actual.clean,selftests:actual.selftests,selftest_completion:actual.selftest_completion.as_ref().map(std::sync::Arc::clone),cli:None,diagnostics,report,inputs:Inputs::ReportReplay(self),_credit:credit})
 }
}
fn backing_lost()->io::Error{io::Error::other("actual report replay lost its verified backing")}
fn take_loan(inputs:Inputs)->Option<Loan>{match inputs{Inputs::ReportReplay(actual)=>Some(actual),_=>None}}

impl BuildHost {
 /// A report can be restored only by the sender after actual terminal success.
 /// Dropping/error/cancellation before that point drops the provisional owner.
 pub(crate) fn commit_native_report_replay(&mut self,inputs:Inputs) {
  if let Some(actual)=take_loan(inputs){self.joined_report_replay=Some(SlotEntry::ReportOnly(actual));}
 }
 pub(super) fn take_native_report_replay(&mut self,request:&BuildRequest,options:Options,selectors:&[String],caller:Option<&Path>)->Result<Option<Report>,Box<dyn Error>> {
  if request.no_cache||options.no_cache {return Ok(None)}
  let Some(slot)=self.joined_report_replay.take()else{return Ok(None)};
  match slot {
   SlotEntry::Compiled(actual)=>{self.joined_report_replay=Some(SlotEntry::Compiled(actual));Ok(None)},
   SlotEntry::ReportOnly(actual)=>{
    if !actual.matches(request,options,selectors,caller)?||!actual.output_current()?{return Ok(None)}
    // Alias metadata uses the SAME retained grant, including one path copy.
    Ok(Some(actual.into_report()?))
   }
  }
 }
 /// Carry only the EXISTING path guard's canonical names and Copy settings.
 /// There is NO pre-preparation optional grant or cloned request/selector key.
 /// Mandatory report metadata already pays overlapping root/cache spellings.
 pub(super) fn native_report_replay_candidate(request:&BuildRequest,options:Options,root:PathBuf,cache:PathBuf)->io::Result<Option<Candidate>>{
  let Some((workspace,actual_cache))=closed_shape(request)?else{return Ok(None)};if options.no_cache||workspace.root!=root||actual_cache!=cache||request.project.strip_prefix(&root).ok()!=Some(Path::new("deepquarry.dme")){return Ok(None)}
  Ok(Some(Candidate{root,cache,shape:shape(request),options}))
 }
 /// Own/fund optional key storage ONLY AFTER required preparation and report
 /// rendering succeeded. Pressure cannot steal their mandatory headroom.
 fn native_report_replay_key(&self,candidate:Candidate,selectors:&[String],caller:Option<&Path>)->io::Result<Option<PendingKey>>{
  let bytes=(||{let mut bytes=std::mem::size_of::<Entry>().checked_add(std::mem::size_of::<Loan>())?;
   bytes=bytes.checked_add(candidate.root.capacity())?.checked_add(candidate.cache.capacity())?;
   // One actual project alias is the fixed child of the guarded root.
   bytes=bytes.checked_add(candidate.root.capacity().checked_add(32)?.checked_mul(4)?)?;
   if let Some(path)=caller{bytes=bytes.checked_add(path.as_os_str().len().checked_add(1)?.checked_mul(4)?)?;}
   for name in selectors{bytes=bytes.checked_add(name.len())?.checked_add(std::mem::size_of::<String>())?;}Some(bytes)})();
  let Some(bytes)=bytes.filter(|n|*n<=64*1024)else{return Ok(None)};
  let credit=match self.source_arena_work().reserve(bytes){Ok(actual)=>actual,Err(error)if error.kind()==io::ErrorKind::OutOfMemory=>return Ok(None),Err(actual)=>return Err(actual)};
  Ok(Some(PendingKey{key:Key{candidate,selectors:selectors.to_vec(),caller:caller.map(Path::to_path_buf)},credit}))
 }
 pub(super) fn retain_native_report(&self,mut actual:Report,candidate:Option<Candidate>,selectors:&[String],caller:Option<&Path>)->Result<Report,Box<dyn Error>> {
  let eligible=actual.cli.is_none() && matches!(&actual.inputs,Inputs::Model(_)) && actual.selected==actual.registered && actual.selftest_completion.as_ref().is_some_and(|done|done.passed());
  if eligible && actual.selftests!=actual.selftest_completion.as_ref().map(|done|done.receipt()).transpose()? {return Err(io::Error::new(io::ErrorKind::InvalidData,"actual callback owner and report receipt disagree").into())}
  let Some(candidate)=candidate.filter(|_|eligible)else{return Ok(actual)};
  let total=actual.report.length().checked_add(actual.diagnostics.as_ref().map_or(0,Verified::length));
  if total.is_none_or(|n|n>dq_analyze::selected_exclusions_wire::MAX_STREAM){return Ok(actual)}
  let Some(slot)=RetainedSlot::acquire()else{return Ok(actual)};
  let Some(pending)=self.native_report_replay_key(candidate,selectors,caller)?else{return Ok(actual)};
  let mut denied=false;
  let mut share=|file:Verified|match file.into_replayable(self.source_arena_work()){Ok(actual)=>Ok(actual),Err((original,error))if error.kind()==io::ErrorKind::OutOfMemory=>{denied=true;Ok(original)},Err((_original,actual))=>Err(actual)};
  actual.diagnostics=actual.diagnostics.map(&mut share).transpose()?;actual.report=share(actual.report)?;
  if denied{return Ok(actual)}
  let loan=Loan{entry:Box::new(Entry{key:pending.key,actual}),_credit:pending.credit,_slot:slot};
  // Promotion just established all aliases. An invariant failure still refuses
  // completion and drops the provisional slot; no panic or false delivery.
  Ok(loan.into_report()?)
 }
}
struct PendingKey { key:Key, credit:SourceArenaCredit }

#[cfg(test)]
#[path="../../../../analyze/fixtures/report_configuration.rs"]mod report_configuration;
#[cfg(test)]
mod tests {
 use super::*;
 use crate::{policy_request::{AnalysisContext,PolicyInputRequest,WorkspacePolicyRequest},request::Command};
 const ROOTS:[&str;6]=["code","doc/rewrite","interface","maps","modular_chomp","tgui"];
 fn put(root:&Path,relative:&str,text:&str){let p=root.join(relative);std::fs::create_dir_all(p.parent().unwrap()).unwrap();std::fs::write(p,text).unwrap();}
 fn fixture(label:&str)->(PathBuf,PathBuf,BuildRequest){
  let root=std::fs::canonicalize(crate::test_scratch::dir(label)).unwrap();let cache=std::fs::canonicalize(crate::test_scratch::dir(&format!("{label}-cache"))).unwrap();
  for directory in ROOTS{std::fs::create_dir_all(root.join(directory)).unwrap();}
  std::fs::create_dir_all(root.join(dq_analyze::ui_actions_policy::INTERFACES)).unwrap();
  put(&root,"deepquarry.dme","#include \"code/probe.dm\"\n");put(&root,"code/probe.dm","/proc/probe()\n    return 0\n");put(&root,"tools/ci/lint_scopes.toml",&report_configuration::with_overlay(""));
  let Command::Build(request)=crate::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()else{panic!("actual CLI request")};let mut request=*request;
  request.no_cache=false;request.exact_inputs=true;request.progress_enabled=false;request.workers=1;request.timeout_seconds=Some(300);request.engine_template=None;request.bootstrap_catalog=false;request.cache_root=Some(cache.clone());request.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:ROOTS.map(|p|root.join(p)).to_vec(),configuration:root.join("tools/ci/lint_scopes.toml")}),..Default::default()});(root,cache,request)
 }
 fn run(host:&mut BuildHost,request:BuildRequest,caller:&Path)->(super::super::full_registry_check::SelftestedRegistryCheck,Vec<u8>,Vec<u8>){
  let(mut diagnostics,mut report)=(Vec::new(),Vec::new());let result=host.write_selected_registry_check_with_selftests_from_caller(request,Options{raw:true,..Default::default()},&[],Some(caller.to_path_buf()),&mut diagnostics,&mut report).unwrap();(result,diagnostics,report)
 }
 fn retained(host:&BuildHost)->&Loan{match host.joined_report_replay.as_ref().expect("actual passed fixture report retained after delivery"){SlotEntry::ReportOnly(actual)=>actual,SlotEntry::Compiled(_)=>panic!("report-only completion must not mint compiled ownership")}}
 #[test]fn actual_whole_selftest_report_replay_keeps_same_completion_and_verified_backing_then_invalidates_real_positive_and_negative_facts(){
  let(root,_cache,request)=fixture("selftest-report-replay");let mut host=BuildHost::default();let cold=run(&mut host,request.clone(),&root);
  assert!(matches!(cold.0,super::super::full_registry_check::SelftestedRegistryCheck::Checked{selftests_failed:0,..}));
  let original=retained(&host).entry.actual.report.replay_alias().unwrap();let completion=std::sync::Arc::clone(retained(&host).entry.actual.selftest_completion.as_ref().unwrap());
  let warm=run(&mut host,request.clone(),&root);assert_eq!(cold,warm);assert!(original.same_replay_backing(&retained(&host).entry.actual.report));assert!(std::sync::Arc::ptr_eq(&completion,retained(&host).entry.actual.selftest_completion.as_ref().unwrap()),"callbacks were not rerun");
  // A real positive file changes at identical width and timestamp.
  let path=root.join("code/probe.dm");let stamp=std::fs::metadata(&path).unwrap().modified().unwrap();let text=std::fs::read_to_string(&path).unwrap();let changed=text.replace("return 0","return 1");assert_eq!(text.len(),changed.len());std::fs::write(&path,changed).unwrap();std::fs::File::options().write(true).open(&path).unwrap().set_times(std::fs::FileTimes::new().set_modified(stamp)).unwrap();
  let _=run(&mut host,request.clone(),&root);assert!(!original.same_replay_backing(&retained(&host).entry.actual.report));assert!(!std::sync::Arc::ptr_eq(&completion,retained(&host).entry.actual.selftest_completion.as_ref().unwrap()));
  let before=retained(&host).entry.actual.report.replay_alias().unwrap();
  // Exact caller-CWD negative becomes a real positive, with no fixture paths
  // reused as authority and no policy-affecting ignore added.
  put(&root,".gitignore","# actual caller fact\n");let _=run(&mut host,request.clone(),&root);assert!(!before.same_replay_backing(&retained(&host).entry.actual.report));
  let before=retained(&host).entry.actual.report.replay_alias().unwrap();put(&root,dq_analyze::ui_actions_policy::DISPATCHER,dq_analyze::ui_selftest_policy::DISPATCHER_FIXTURE);let _=run(&mut host,request,&root);assert!(!before.same_replay_backing(&retained(&host).entry.actual.report));
 }
 #[test]fn actual_selftest_semantic_failure_is_not_retained_and_next_real_success_recovers(){
  let(root,_cache,request)=fixture("selftest-report-failure");put(&root,dq_analyze::ui_actions_policy::DISPATCHER,&dq_analyze::ui_selftest_policy::DISPATCHER_FIXTURE.replace("length(raw) > 64","length(raw) > 1"));let mut host=BuildHost::default();let failed=run(&mut host,request.clone(),&root);assert!(matches!(failed.0,super::super::full_registry_check::SelftestedRegistryCheck::Checked{selftests_failed:1,..}));assert!(host.joined_report_replay.is_none());assert!(String::from_utf8(failed.2).unwrap().contains("ui_actions --selftest"));put(&root,dq_analyze::ui_actions_policy::DISPATCHER,dq_analyze::ui_selftest_policy::DISPATCHER_FIXTURE);let recovered=run(&mut host,request,&root);assert!(matches!(recovered.0,super::super::full_registry_check::SelftestedRegistryCheck::Checked{selftests_failed:0,..}));let _=retained(&host);
 }
 #[test]fn actual_warm_report_delivery_first_io_evicts_provisional_owner_and_no_cache_mode_does_not_reuse(){
  struct Broken;impl std::io::Write for Broken{fn write(&mut self,_:&[u8])->io::Result<usize>{Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{Ok(())}}
  let(root,_cache,request)=fixture("selftest-report-io");let mut host=BuildHost::default();let _=run(&mut host,request.clone(),&root);let old=retained(&host).entry.actual.report.replay_alias().unwrap();
  let error=host.write_selected_registry_check_with_selftests_from_caller(request.clone(),Options{raw:true,..Default::default()},&[],Some(root.clone()),&mut std::io::sink(),&mut Broken).unwrap_err();let actual=error.downcast_ref::<io::Error>().unwrap();assert_eq!(actual.raw_os_error(),Some(1450));assert!(host.joined_report_replay.is_none(),"no failed send may retain provisional completion");
  let _=run(&mut host,request.clone(),&root);assert!(!old.same_replay_backing(&retained(&host).entry.actual.report));let mut uncached=request;uncached.no_cache=true;let _=run(&mut host,uncached,&root);assert!(host.joined_report_replay.is_none());
 }
 #[test]fn actual_warm_report_cancelled_during_delivery_does_not_commit_and_next_original_context_recovers(){
  use crate::daemon::control;
  struct CancelOnWrite(control::Cancellation);impl std::io::Write for CancelOnWrite{fn write(&mut self,bytes:&[u8])->io::Result<usize>{self.0.cancel();Ok(bytes.len())}fn flush(&mut self)->io::Result<()>{Ok(())}}
  let(root,_cache,request)=fixture("selftest-report-cancel");let mut host=BuildHost::default();let _=run(&mut host,request.clone(),&root);
  let token=control::Cancellation::default();let binding=control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(300));
  let error=host.write_selected_registry_check_with_selftests_from_caller(request.clone(),Options{raw:true,..Default::default()},&[],Some(root.clone()),&mut std::io::sink(),&mut CancelOnWrite(token)).unwrap_err();assert_eq!(error.downcast_ref::<io::Error>().unwrap().kind(),io::ErrorKind::Interrupted);assert!(host.joined_report_replay.is_none());drop(binding);
  let recovered=run(&mut host,request,&root);assert!(matches!(recovered.0,super::super::full_registry_check::SelftestedRegistryCheck::Checked{selftests_failed:0,..}));let _=retained(&host);
 }
 #[test]fn actual_optional_key_preserves_cancellation_and_declines_only_native_pressure_then_recovers(){
  use dm_preprocess::source_arena_credit::SourceArenaWork;use crate::daemon::control;
  let(root,cache,request)=fixture("selftest-key-pressure");let host=BuildHost::default();let options=Options{raw:true,..Default::default()};let names=vec!["x".repeat(128);256];
  let candidate=||BuildHost::native_report_replay_candidate(&request,options,root.clone(),cache.clone()).unwrap().unwrap();
  let token=control::Cancellation::default();let binding=control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(300));token.cancel();let error=host.native_report_replay_key(candidate(),&names,Some(&root)).err().unwrap();assert_eq!(error.kind(),io::ErrorKind::Interrupted);drop(binding);
  let _binding=control::bind_with_deadline(control::Cancellation::default(),std::time::Instant::now()+std::time::Duration::from_secs(300));
  // Actual current raw_policy::INPUT_BUDGET=256MiB, not the distinct128MiB
  // Original parser census limit. Reserve counts only; no256MiB payload exists.
  let used=host.source_input_admission_bytes().unwrap();let first=host.source_arena_work().reserve(256*1024*1024-used-512*1024).unwrap();let second=host.source_arena_work().reserve(480*1024).unwrap();assert!(host.native_report_replay_key(candidate(),&names,Some(&root)).unwrap().is_none());assert!(host.joined_report_replay.is_none());drop(second);drop(first);
  assert!(host.native_report_replay_key(candidate(),&names,Some(&root)).unwrap().is_some());assert!(host.joined_report_replay.is_none(),"funded key alone cannot publish callback success");
 }

 #[test]fn actual_cli_observations_bypass_whole_report_lookup_and_retention_without_clearing_model_owners(){
  let(root,_cache,request)=fixture("selftest-cli-replay-exclusion");let mut host=BuildHost::default();let cold=run(&mut host,request.clone(),&root);assert!(matches!(cold.0,super::super::full_registry_check::SelftestedRegistryCheck::Checked{selftests_failed:0,..}));let old=retained(&host).entry.actual.report.replay_alias().unwrap();let completion=std::sync::Arc::clone(retained(&host).entry.actual.selftest_completion.as_ref().unwrap());let warm=run(&mut host,request.clone(),&root);assert_eq!(cold,warm);assert!(old.same_replay_backing(&retained(&host).entry.actual.report));
  // A malformed requested mode is refused before discarding an admitted slot.
  let invalid=dq_analyze::native_check_cli_wire::Request{changed:None,timing:true,timing_only:false,allow_usage:true};let(mut diagnostics,mut report,mut usage)=(Vec::new(),Vec::new(),Vec::new());let error=host.write_selected_registry_check_with_cli_observations(request.clone(),Options{raw:true,..Default::default()},&[],true,Some(root.clone()),&invalid,&mut diagnostics,&mut report,&mut usage).unwrap_err();assert_eq!(error.downcast_ref::<io::Error>().unwrap().kind(),io::ErrorKind::InvalidInput);assert!(old.same_replay_backing(&retained(&host).entry.actual.report));assert!(diagnostics.is_empty()&&report.is_empty()&&usage.is_empty());
  let requested=dq_analyze::native_check_cli_wire::Request{changed:None,timing:true,timing_only:false,allow_usage:false};let actual=host.write_selected_registry_check_with_cli_observations(request.clone(),Options{raw:true,..Default::default()},&[],true,Some(root.clone()),&requested,&mut diagnostics,&mut report,&mut usage).unwrap();assert_eq!(actual.selftests.unwrap().failed,0);assert!(String::from_utf8_lossy(&report).contains("-- native CHECK timing"));assert!(usage.is_empty());assert!(host.joined_report_replay.is_none(),"Some CLI observations must neither replay nor retain the whole report slot; actual source/model memo reuse is still allowed");
  let next=run(&mut host,request,&root);assert!(matches!(next.0,super::super::full_registry_check::SelftestedRegistryCheck::Checked{selftests_failed:0,..}));assert!(!old.same_replay_backing(&retained(&host).entry.actual.report));assert!(!std::sync::Arc::ptr_eq(&completion,retained(&host).entry.actual.selftest_completion.as_ref().unwrap()),"a fresh ordinary completion must follow the real observation-mode operation");
 }
}

impl Loan{pub(crate) fn with_report_input_observation<T>(&self,project:&Path,observe:impl FnOnce(&crate::input_snapshot::InputSnapshot)->io::Result<T>)->Result<T,Box<dyn Error>>{self.entry.actual.inputs.with_report_input_observation(project,observe)}}
