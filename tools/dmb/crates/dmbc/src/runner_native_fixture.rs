//! Ordinary sem fixture over one exact retained registered producer.
use super::{BuildHost,FullRegistryCheckOptions,full_registry_check::FullRegistryCheckInputs};
use std::{io::{self,Write},path::Path,sync::Arc};
use crate::{request::BuildRequest,selected_report_spool::{Stage,Verified}};
use dm_preprocess::source_arena_credit::SourceArenaCredit;
type BoxError=Box<dyn std::error::Error>;
fn invalid(s:&'static str)->io::Error{io::Error::new(io::ErrorKind::InvalidInput,s)}
pub(crate) struct NativeFixtureReport{
 pub(crate) binding:dq_analyze::native_codemod_fixture_wire::Binding,
 pub(crate) frame:dq_analyze::full_registry_check_wire::CheckFrame,
 pub(crate) committed:usize,pub(crate) comparison_accepted:bool,pub(crate) project:std::path::PathBuf,pub(crate) inputs:FullRegistryCheckInputs,
 pub(crate) stdout:Verified,pub(crate) stderr:Verified,transition:Option<crate::native_author_fix_transaction::Transition>,pub(crate) _credit:SourceArenaCredit,
}
impl NativeFixtureReport{
 fn mutation_failure(&self,primary:BoxError)->BoxError{match &self.transition{Some(actual)=>crate::native_fix::CommittedFailure::from_verified_transition(primary,actual),None=>primary}}

 pub(crate) fn require_current(&self)->Result<(),BoxError>{self.inputs.require_report_current(&self.project)}
 pub(crate) fn publish(self,out:&mut impl Write)->Result<(),BoxError>{if let Err(primary)=self.require_current(){return Err(self.mutation_failure(primary))}let NativeFixtureReport{inputs,project,stdout,stderr,transition,..}=self;let pending=(||->Result<(),BoxError>{stderr.publish(&mut io::sink())?;stdout.publish(out)?;inputs.require_report_current(&project)?;Ok(())})();pending.map_err(|primary|match &transition{Some(t)=>crate::native_fix::CommittedFailure::from_verified_transition(primary,t),None=>primary})}
}
impl BuildHost{
 pub(crate) fn stage_native_fixture(&mut self,request:BuildRequest,real_root:&Path,lint:&str,bless:bool)->Result<NativeFixtureReport,BoxError>{super::full_registry_check::with_full_registry_check_context(request.command,request.timeout_seconds,||self.stage_native_fixture_using(request,real_root,lint,bless,&mut|_|Ok(())))}
 pub(crate) fn stage_native_fixture_using(&mut self,mut request:BuildRequest,real_root:&Path,lint:&str,bless:bool,hook:&mut impl FnMut(crate::native_author_fix_transaction::Event)->io::Result<()>)->Result<NativeFixtureReport,BoxError>{
  self.stage_native_fixture_mode(request,real_root,lint,bless,super::fixture_scope::FixtureConfigMode::Repository,hook,&mut|_,_,_,_,_,_,_|Ok(true))
 }
 /// Parity receives raw and normalized previews before ANY expected.txt write.
 /// The gate may refuse; refusal leaves authored output untouched.
 pub(crate) fn stage_native_parity_fixture(&mut self,request:BuildRequest,real_root:&Path,lint:&str,bless:bool,gate:&mut dyn FnMut(&Verified,&Verified,&super::fixture_scope::CapturedFixtureTarget,&FullRegistryCheckInputs,&Path,&Path,&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->Result<bool,BoxError>)->Result<NativeFixtureReport,BoxError>{
  super::full_registry_check::with_full_registry_check_context(request.command,request.timeout_seconds,||self.stage_native_fixture_mode(request,real_root,lint,bless,super::fixture_scope::FixtureConfigMode::FixtureIfPresent,&mut|_|Ok(()),gate))
 }
 fn stage_native_fixture_mode(&mut self,mut request:BuildRequest,real_root:&Path,lint:&str,bless:bool,mode:super::fixture_scope::FixtureConfigMode,hook:&mut impl FnMut(crate::native_author_fix_transaction::Event)->io::Result<()>,gate:&mut dyn FnMut(&Verified,&Verified,&super::fixture_scope::CapturedFixtureTarget,&FullRegistryCheckInputs,&Path,&Path,&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->Result<bool,BoxError>)->Result<NativeFixtureReport,BoxError>{
  if !self.retains_artifacts(){return Err(invalid("fixture needs the existing retained native host").into())}
  let mut count=Count{n:0};serde_json::to_writer(&mut count,&request).map_err(io::Error::other)?;
  let credit=self.source_arena_work().reserve(count.n.checked_mul(8).and_then(|n|n.checked_add(real_root.as_os_str().len().checked_mul(16)?)).and_then(|n|n.checked_add(lint.len().checked_mul(8)?)).and_then(|n|n.checked_add(32768)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?)?;
  let selector_credit=self.source_arena_work().reserve(lint.len().checked_mul(4).and_then(|n|n.checked_add(4096)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?)?;
  let options=FullRegistryCheckOptions{raw:true,unused:false,no_cache:true,..Default::default()};
  let mut plan=super::prepare_native_registered_check_selection(&[lint.to_owned()],options,self.source_arena_work())?;
  if plan.names().len()!=1||plan.names()[0]!=lint{return Err(invalid("fixture needs one exact canonical registered lint name").into())}
  drop(selector_credit);
  let cache=request.cache_root.as_ref().ok_or_else(||invalid("fixture external cache absent"))?;
  let scope=super::fixture_scope::FixtureScope::issue_mode(real_root,lint,bless,mode,cache,self.source_arena_work())?;
  // The fixture constructor selects the exact old sem-fixture override; no
  // ordinary registered request obtains this configuration permission.
  let workspace=request.policy_inputs.as_mut().and_then(|p|p.workspace.as_mut()).ok_or_else(||invalid("fixture actual workspace absent"))?;
  if workspace.root!=real_root||workspace.configuration!=real_root.join("tools/ci/lint_scopes.toml")||request.project!=real_root.join("deepquarry.dme")||workspace.recursive_roots.iter().any(|p|!p.starts_with(real_root))||request.warnings!=crate::diagnostics::WarningPolicy::default(){return Err(invalid("fixture caller differs from its authenticated real-root request").into())}
  // Request paths are DATA, paid by credit above. The selected producer still
  // discovers/opens/reads the actual fixture through its SAME recorder and
  // proves its own synthetic/real root. Real repository configuration is kept.
  workspace.root=scope.root().to_path_buf();workspace.recursive_roots.clear();workspace.recursive_roots.try_reserve_exact(1).map_err(|_|io::Error::from(io::ErrorKind::OutOfMemory))?;workspace.recursive_roots.push(scope.root().join("code"));
  workspace.configuration=scope.configuration().to_path_buf();request.project=scope.root().join("deepquarry.dme");
  let(recovery,recovery_credit)=super::native_codemod::request_copy(&request,self.source_arena_work())?;let cache=cache.clone();let root=scope.root().to_path_buf();
  Arc::get_mut(&mut plan).ok_or_else(||invalid("fresh fixture selection already aliased"))?.install_fixture(scope)?;
  let actual=self.stage_selected_registry_check_with_plan(request,Arc::clone(&plan))?;actual.inputs.require_report_current(&actual.project)?;
  let(target,expected)=plan.fixture_scope().ok_or_else(||invalid("fixture scope disappeared"))?.finish_outputs()?;
  let super::full_registry_check::FullRegistryCheckReport{project,inputs,frame,report:mut stdout,_credit:old_credit,diagnostics,..}=actual;
  let stderr=match diagnostics{Some(actual)=>actual,None=>Stage::new(&cache)?.seal_allow_empty()?.validate(|r|io::copy(r,&mut io::sink()))?.0};drop(old_credit);
  let binding=dq_analyze::native_codemod_fixture_wire::Binding{schema:dq_analyze::native_codemod_fixture_wire::Schema::V2,root:real_root.to_path_buf(),question:dq_analyze::native_codemod_fixture_wire::Question::Fixture{lint:lint.to_owned(),bless}};
  let mut comparison_accepted=true;
  let expected=match expected{
   Some(expected)=>{
    stdout=stdout.into_replayable(self.source_arena_work()).map_err(|(_,error)|error)?;
    let expected=expected.into_replayable(self.source_arena_work()).map_err(|(_,error)|error)?;
    inputs.require_report_current(&project)?;
    comparison_accepted=gate(&stdout,&expected,target.as_ref().ok_or_else(||invalid("fixture preview lacks captured fixed target"))?,&inputs,&project,plan.fixture_scope().ok_or_else(||invalid("fixture scope disappeared"))?.configuration(),self.source_arena_work())?;
    inputs.require_report_current(&project)?;Some(expected)
   },None=>None,
  };
  if let Some(target)=target.filter(|_|bless&&comparison_accepted){let expected=expected.ok_or_else(||invalid("fixture physical write lacks normalized preview"))?;
   inputs.require_report_current(&project)?;let expected_length=expected.length();let expected_hash=expected.hash();
   let desired=super::native_sem_utility::ReportBytes::capture(expected,self.source_arena_work())?;
   self.clear_regions();
   let attempted=crate::native_author_fix_transaction::commit_fixture_using(&target,&desired.bytes,self.source_arena_work(),&mut||inputs.require_report_current(&project),hook);
   // EVERY physical attempt, including partial failure, is followed by actual
   // preparation. Prior plan/scope identity is retained; facts are not reused.
   let recovered=self.stage_selected_registry_check_with_plan(recovery,Arc::clone(&plan));drop(recovery_credit);
   let transition=match attempted{Ok(committed)=>committed.into_parts().1,Err(actual)=>{let(ok,recovery)=match recovered{Ok(value)=>{drop(value);(true,None)},Err(error)=>{self.clear_regions();(false,Some(error))}};return Err(crate::native_fix::FailedMutation::from_attempt(actual.primary,actual.may_have_changed,ok,recovery))}};
   let next=match recovered{Ok(next)=>next,Err(first)=>{self.clear_regions();return Err(crate::native_fix::CommittedFailure::from_verified_transition(first,&transition))}};
   let finalized=(||->Result<_,BoxError>{
   inputs.require_fixture_step(&next.inputs,&project,&root,&transition,self.source_arena_work())?;next.inputs.require_report_current(&next.project)?;
   let(_,next_expected)=plan.fixture_scope().ok_or_else(||invalid("fixture recovery scope disappeared"))?.finish_expected()?.ok_or_else(||invalid("fixture recovery omitted expected DATA"))?;
   if next_expected.length()!=expected_length||next_expected.hash()!=expected_hash{return Err(invalid("fixture normalized findings changed across its expected-only write").into())}
   drop(next_expected);drop(desired);drop(target);drop(inputs);
   let mut output=Stage::new(&cache)?;stdout.publish(&mut output)?;writeln!(output,"wrote {}",root.join("expected.txt").display())?;
   let length=output.length();let(stdout,copied)=output.seal()?.validate(|r|io::copy(r,&mut io::sink()))?;if copied!=length{return Err(invalid("fixture output sealed extent differs").into())}
   next.inputs.require_report_current(&next.project)?;Ok((next,stdout))
   })();
   let(next,stdout)=match finalized{Ok(value)=>value,Err(primary)=>return Err(crate::native_fix::CommittedFailure::from_verified_transition(primary,&transition))};
   let result=NativeFixtureReport{comparison_accepted,binding,project:next.project,inputs:next.inputs,frame:next.frame,stdout,stderr,transition:Some(transition),committed:1,_credit:credit};Ok(result)
  }else{let result=NativeFixtureReport{comparison_accepted,binding,project,inputs,frame,stdout,stderr,transition:None,committed:0,_credit:credit};result.require_current()?;Ok(result)}
 }
}
struct Count{n:usize}impl Write for Count{fn write(&mut self,b:&[u8])->io::Result<usize>{self.n=self.n.checked_add(b.len()).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;Ok(b.len())}fn flush(&mut self)->io::Result<()>{Ok(())}}
#[cfg(test)]mod fixture_controls{
 use super::*;
 use crate::policy_request::{PolicyInputRequest,WorkspacePolicyRequest,AnalysisContext};
 fn fixture(lint:&str,label:&str)->(BuildHost,BuildRequest,std::path::PathBuf,std::path::PathBuf){
  let real=std::fs::canonicalize(crate::test_scratch::dir(label)).unwrap();let cache=std::fs::canonicalize(crate::test_scratch::dir(&format!("{label}-cache"))).unwrap();
  let root=real.join("tools/analyze/fixtures").join(lint.replace('/',"__"));std::fs::create_dir_all(root.join("code")).unwrap();std::fs::create_dir_all(real.join("tools/ci")).unwrap();std::fs::write(real.join("tools/ci/lint_scopes.toml"),b"").unwrap();
  std::fs::write(root.join("code/probe.dm"),b"/datum/fixture_probe\n    var/x = 1\n/proc/fixture_probe()\n    sleep(1)\n").unwrap();
  let crate::request::Command::Build(request)=crate::cli::parse(&["prepare-query".into(),real.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()else{panic!("ordinary prepare-query contract changed")};let mut request=*request;
  request.cache_root=Some(cache);request.workers=1;request.progress_enabled=false;request.timeout_seconds=Some(60);request.exact_inputs=true;request.no_cache=true;
  request.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:real.clone(),recursive_roots:vec![real.join("code")],configuration:real.join("tools/ci/lint_scopes.toml")}),..Default::default()});
  (BuildHost::default(),request,real,root)
 }
 #[test]fn actual_sem_fixture_missing_dme_uses_same_native_model_and_repo_config_over_fixture_config(){
  let(mut host,request,real,root)=fixture("decl","native-sem-fixture-model");std::fs::create_dir_all(root.join("tools/ci")).unwrap();std::fs::write(root.join("tools/ci/lint_scopes.toml"),b"this is not valid TOML [").unwrap();
  let report=host.stage_native_fixture(request,&real,"decl",false).unwrap();assert_eq!(report.committed,0);let mut out=Vec::new();report.publish(&mut out).unwrap();assert!(String::from_utf8(out).unwrap().ends_with("findings\n"));assert!(!root.join("deepquarry.dme").exists());assert!(!root.join("__dmb_original_analysis_subject__").exists());
  let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();assert!(snapshot.diagnostic_tree().expect("actual authenticated fixture tree").lookup_type(dm_ir::SymbolId::of("/datum/fixture_probe")).is_some());
 }
 #[test]fn actual_sem_fixture_positive_and_absent_expected_use_same_writer_and_exact_three_column_bytes(){
  for existing in [false,true]{let(mut host,request,real,root)=fixture("scheduler",if existing{"native-fixture-rewrite"}else{"native-fixture-create"});if existing{std::fs::write(root.join("expected.txt"),b"old\n").unwrap();}
   let report=host.stage_native_fixture(request,&real,"scheduler",true).unwrap();assert_eq!(report.committed,1);let mut out=Vec::new();report.publish(&mut out).unwrap();let out=String::from_utf8(out).unwrap();assert!(out.contains("findings\n"));assert!(out.contains("wrote "));
   let expected=std::fs::read_to_string(root.join("expected.txt")).unwrap();assert!(!expected.is_empty(),"real sleep must yield actual scheduler findings");assert!(expected.lines().all(|row|row.split('\t').count()==3));assert!(!expected.contains("old"));
  }
 }
 #[test]fn parity_fixture_own_configuration_is_recorded_and_does_not_change_sem_fixture_override(){
  let(mut host,request,real,root)=fixture("scheduler","native-parity-own-config");std::fs::create_dir_all(root.join("tools/ci")).unwrap();std::fs::write(root.join("tools/ci/lint_scopes.toml"),b"# actual fixture config\n").unwrap();
  let report=host.stage_native_parity_fixture(request,&real,"scheduler",false,&mut|raw,expected,_target,inputs,project,configuration,work|{assert_eq!(configuration,root.join("tools/ci/lint_scopes.toml"));assert!(raw.length()>0);assert!(expected.length()>0);inputs.require_report_current(project)?;work.checkpoint()?;Ok(true)}).unwrap();
  std::fs::remove_file(root.join("tools/ci/lint_scopes.toml")).unwrap();assert!(report.require_current().is_err(),"positive own-config path must remain in SAME selected ledger");
 }
 #[test]fn parity_fixture_fallback_records_absence_before_selected_proof(){
  let(mut host,request,real,root)=fixture("scheduler","native-parity-absent-config");
  let report=host.stage_native_parity_fixture(request,&real,"scheduler",false,&mut|_,_,_,_,_,configuration,_|{assert_eq!(configuration,real.join("tools/ci/lint_scopes.toml"));Ok(true)}).unwrap();
  std::fs::create_dir_all(root.join("tools/ci")).unwrap();std::fs::write(root.join("tools/ci/lint_scopes.toml"),b"# appeared\n").unwrap();assert!(report.require_current().is_err(),"fallback must be invalidated when fixture config appears");
 }
 #[test]fn parity_fixture_comparison_failure_cannot_bless_authored_expected(){
  let(mut host,request,real,root)=fixture("scheduler","native-parity-rejected-preview");std::fs::write(root.join("expected.txt"),b"preserve old expected\n").unwrap();let mut gated=false;
  let report=host.stage_native_parity_fixture(request,&real,"scheduler",true,&mut|raw,expected,_,_,_,_,_|{gated=true;assert!(raw.length()>0&&expected.length()>0);Ok(false)});
  assert!(gated);let report=report.unwrap();assert!(!report.comparison_accepted);assert_eq!(report.committed,0);assert_eq!(std::fs::read(root.join("expected.txt")).unwrap(),b"preserve old expected\n");
 }
 #[test]fn actual_sem_fixture_currentness_includes_real_root_config(){let(mut host,request,real,_root)=fixture("scheduler","native-fixture-config-current");let report=host.stage_native_fixture(request,&real,"scheduler",false).unwrap();std::fs::write(real.join("tools/ci/lint_scopes.toml"),b"# changed after actual native producer\n").unwrap();assert!(report.require_current().is_err());}
 #[test]fn actual_sem_fixture_partial_writer_error_keeps_first_1450_and_reprepares(){let(mut host,request,real,root)=fixture("scheduler","native-fixture-partial-error");std::fs::write(root.join("expected.txt"),b"old\n").unwrap();let mut seen=0;let result=super::super::full_registry_check::with_full_registry_check_context(request.command,request.timeout_seconds,||host.stage_native_fixture_using(request,&real,"scheduler",true,&mut|event|{if matches!(event,crate::native_author_fix_transaction::Event::AfterTruncate){seen+=1;return Err(io::Error::from_raw_os_error(1450))}Ok(())}));assert_eq!(seen,1);let error=match result{Err(error)=>error,Ok(_)=>panic!("actual truncate/write fault must fail fixture")};let mut cursor:Option<&(dyn std::error::Error+'static)>=Some(error.as_ref());let mut actual=false;while let Some(error)=cursor{if error.downcast_ref::<io::Error>().is_some_and(|e|e.raw_os_error()==Some(1450)){actual=true;break}cursor=error.source();}assert!(actual,"actual first operational error must survive recovery");assert!(host.query_state().lock().unwrap().raw_snapshot.is_some(),"failure must leave a genuine newly prepared raw state");}
 #[test]fn actual_sem_fixture_refuses_other_source_mutation_during_bless(){let(mut host,request,real,root)=fixture("scheduler","native-fixture-other-change");let mut once=false;let result=super::super::full_registry_check::with_full_registry_check_context(request.command,request.timeout_seconds,||host.stage_native_fixture_using(request,&real,"scheduler",true,&mut|event|{if !once&&matches!(event,crate::native_author_fix_transaction::Event::BeforeWrite){once=true;std::fs::write(root.join("code/probe.dm"),b"/datum/unrelated_changed_input\n")?;}Ok(())}));assert!(once);assert!(result.is_err(),"only expected.txt may differ in the post-write closure");}
 #[test]fn actual_fixture_partial_configuration_does_not_weaken_ordinary_registered_check(){
  let(mut host,mut request,real,_root)=fixture("scheduler","fixture-partial-config-vs-check");std::fs::create_dir_all(real.join("code")).unwrap();std::fs::write(real.join("code/ordinary.dm"),b"/proc/ordinary_probe()\n    sleep(1)\n").unwrap();std::fs::write(real.join("deepquarry.dme"),b"#include \"code/ordinary.dm\"\n").unwrap();
  use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;request.policy_inputs.as_mut().unwrap().workspace.as_mut().unwrap().recursive_roots=Q::authored_doc_ui_roots(Q::PRIVATE_FULL_REGISTRY).unwrap().iter().map(|path|real.join(path)).collect();
  let error=super::super::full_registry_check::with_full_registry_check_context(request.command,request.timeout_seconds,||host.stage_selected_registry_check_report(request.clone(),FullRegistryCheckOptions{raw:true,unused:false,no_cache:true,..Default::default()},&["scheduler".into()])).err().expect("ordinary CHECK must reject missing unrelated registered lists");assert!(error.to_string().contains("is missing"),"{error}");
  let report=host.stage_native_fixture(request,&real,"scheduler",false).unwrap();let mut out=Vec::new();report.publish(&mut out).unwrap();assert!(String::from_utf8(out).unwrap().ends_with("findings\n"));
 }
 #[test]fn actual_fixture_still_refuses_malformed_selected_repository_configuration(){let(mut host,request,real,root)=fixture("scheduler","fixture-malformed-selected-config");std::fs::write(real.join("tools/ci/lint_scopes.toml"),b"[broken TOML").unwrap();assert!(host.stage_native_fixture(request,&real,"scheduler",true).is_err());assert!(!root.join("expected.txt").exists(),"configuration parse refusal cannot bless");}
}
/// Same API shape as native_codemod::run; this completion retains its real
/// selected producer ledger, rather than pretending every fixture is a model.
pub(crate) struct Completed{
 pub(crate) exit:i32,pub(crate) committed:usize,pub(crate) frame:dq_analyze::native_codemod_fixture_wire::SourceFrame,
 project:std::path::PathBuf,inputs:FullRegistryCheckInputs,transition:Option<crate::native_author_fix_transaction::Transition>,_credit:SourceArenaCredit,
}
impl Completed{pub(crate)fn require_current(&self)->Result<(),BoxError>{self.inputs.require_report_current(&self.project)}pub(crate)fn mutation_failure(&self,primary:BoxError)->BoxError{match &self.transition{Some(t)=>crate::native_fix::CommittedFailure::from_verified_transition(primary,t),None=>primary}}}
pub(crate)fn run(request:&BuildRequest,binding:&dq_analyze::native_codemod_fixture_wire::Binding,host:&mut BuildHost,mut stdout:&mut dyn Write,mut stderr:&mut dyn Write)->Result<Completed,BoxError>{
 use dq_analyze::native_codemod_fixture_wire::{Question,SourceFrame};binding.validate()?;
 let Question::Fixture{lint,bless}=&binding.question else{return Err(invalid("native fixture coordinator received another question").into())};
 let(owned_request,copy_credit)=super::native_codemod::request_copy(request,host.source_arena_work())?;
 let report=host.stage_native_fixture(owned_request,&binding.root,lint,*bless)?;drop(copy_credit);if let Err(primary)=report.require_current(){return Err(report.mutation_failure(primary))}
 finish_report(report,stdout,stderr)
}
/// Consume the SAME retained fixture report into its compact input completion
/// after publishing outputs. Parity uses this after its compare-before-write
/// gate, without rescanning or retaining duplicate report spools.
pub(crate) fn finish_report(report:NativeFixtureReport,mut stdout:&mut dyn Write,mut stderr:&mut dyn Write)->Result<Completed,BoxError>{
 if let Err(primary)=report.require_current(){return Err(report.mutation_failure(primary))}
 let NativeFixtureReport{committed,frame,project,inputs,stdout:out,stderr:err,transition,_credit,..}=report;
 let pending=(||->Result<(),BoxError>{err.publish(&mut stderr)?;out.publish(&mut stdout)?;inputs.require_report_current(&project)?;Ok(())})();
 if let Err(primary)=pending{return Err(match &transition{Some(t)=>crate::native_fix::CommittedFailure::from_verified_transition(primary,t),None=>primary})}
 Ok(Completed{exit:0,committed,frame:dq_analyze::native_codemod_fixture_wire::SourceFrame::Selected(frame),project,inputs,transition,_credit})
}
