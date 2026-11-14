//! Actual owner/failed-root controls. Definitions only until parent executes.
use super::*;
#[path="../../../shared/test_scratch.rs"]mod scratch;
#[path="../../../../analyze/fixtures/report_configuration.rs"]mod report_configuration;
#[path="runner_native_check_handlers_test_provider.rs"]mod actual_provider;
use crate::{policy_request::{AnalysisContext,PolicyInputRequest,WorkspacePolicyRequest,WorkspaceAuxiliaryQuestion as Q},request::{BuildRequest,BuildOutcome,Command},runner_host::{BuildHost,FullRegistryCheckOptions}};
fn put(root:&Path,relative:&str,bytes:impl AsRef<[u8]>){let path=root.join(relative);std::fs::create_dir_all(path.parent().unwrap()).unwrap();std::fs::write(path,bytes).unwrap();}
fn fixture(full:bool)->(PathBuf,BuildRequest){
 let root=std::fs::canonicalize(scratch::dir("registered-handlers-owner")).unwrap();let cache=scratch::dir("registered-handlers-owner-cache");
 put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay(""));
 // Same authored fixture as the existing actual public Handler report controls.
 put(&root,"code/__defines/context.dm","#define CAPABILITIES(...)\n#define PROC_REF(P) #P\n/datum/act\n/datum/act/eval\n/obj/probe\n");
 put(&root,"code/structural.dm","/proc/leak(datum/act/A)\n    return list(A)\n");
 let mut manifest="#include \"code/__defines/context.dm\"\n#include \"code/structural.dm\"\n".to_owned();
 if full{put(&root,"code/handler.dm","/obj/probe/proc/handler(datum/act/eval/A)\n    return 2\nCAPABILITIES(/obj/probe,when(PROC_REF(handler)))\n");manifest.push_str("#include \"code/handler.dm\"\n");}
 put(&root,"deepquarry.dme",manifest);
 let Command::Build(request)=crate::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()else{panic!("actual preparation parser")};let mut request=*request;
 request.no_cache=true;request.exact_inputs=true;request.progress_enabled=false;request.workers=1;request.timeout_seconds=Some(60);request.engine_template=None;request.bootstrap_catalog=false;request.cache_root=Some(cache);
 request.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:vec![root.join("code")],configuration:root.join("tools/ci/lint_scopes.toml")}),workspace_auxiliary:vec![Q::SemHandlers],..Default::default()});(root,request)
}
fn actual_plan(host:&BuildHost)->Arc<NativeCheckSelection>{crate::runner_host::prepare_native_check_selection(&["sem/handlers".into()],FullRegistryCheckOptions::default(),host.source_arena_work()).unwrap()}
fn bound()->crate::daemon::control::Binding{crate::daemon::control::bind_with_deadline(crate::daemon::control::Cancellation::default(),std::time::Instant::now()+std::time::Duration::from_secs(60))}
#[test]fn registered_handler_current_partial_is_real_owner_without_full_model_or_baseline(){
 let _binding=bound();let(root,request)=fixture(false);std::fs::remove_file(&request.project).unwrap();std::fs::create_dir(&request.project).unwrap();
 let mut host=BuildHost::default();let plan=actual_plan(&host);assert!(plan.handlers_only());assert_eq!(plan.questions().collect::<Vec<_>>(),[Q::SemHandlers]);assert!(plan.baselines().next().is_none());
 let super::super::native_check_source::PreparedHandlers::Current{outcome,inputs}=super::super::native_check_source::prepare_registered_handlers_check(request.clone(),&mut host,Arc::clone(&plan)).unwrap()else{panic!("actual unrequested physical DME cannot force full")};
 assert!(matches!(outcome,BuildOutcome::HandlersQueryPrepared{full_source_revision:None,retained:true,..}));inputs.require_current(&request.project).unwrap();
 let foreign=actual_plan(&host);let alias=inputs.snapshot.clone();assert!(inputs.require_binding(&alias,&foreign).is_err());assert!(inputs.require_binding(&alias,&plan).is_ok());
 assert!(host.symbolic_retention_stats().is_none_or(|stats|stats.records==0&&stats.successful_admissions==0));assert!(request.project.is_dir());assert!(!root.join("deepquarry.dmb").exists());
}
#[test]fn registered_handler_current_ledger_rejects_changed_configuration_and_recovers(){
 let _binding=bound();let(root,request)=fixture(false);let mut host=BuildHost::default();let plan=actual_plan(&host);
 let super::super::native_check_source::PreparedHandlers::Current{inputs,..}=super::super::native_check_source::prepare_registered_handlers_check(request.clone(),&mut host,plan).unwrap()else{panic!("current")};
 let path=root.join("tools/ci/lint_scopes.toml");let old=std::fs::read(&path).unwrap();let stamp=std::fs::metadata(&path).unwrap().modified().unwrap();let mut changed=old.clone();let at=changed.iter().position(|b|*b==b'\n').unwrap();changed[at]=b' ';std::fs::write(&path,&changed).unwrap();std::fs::OpenOptions::new().write(true).open(&path).unwrap().set_times(std::fs::FileTimes::new().set_modified(stamp)).unwrap();
 let failed=inputs.require_current(&request.project);std::fs::write(&path,old).unwrap();assert!(failed.is_err(),"same-size restored-mtime changes cannot inherit current");
 let recovery_plan=actual_plan(&host);assert!(matches!(super::super::native_check_source::prepare_registered_handlers_check(request,&mut host,recovery_plan).unwrap(),super::super::native_check_source::PreparedHandlers::Current{..}));
}
#[test]fn registered_handler_failed_full_is_actual_one_shot_never_current_and_source_error_stays_first(){
 let _binding=bound();let(_root,request)=fixture(true);let mut host=BuildHost::default();let provider=actual_provider::source(true);let plan=actual_plan(&host);
 let super::super::native_check_source::PreparedHandlers::FailedFullOneShot{actual,report}=super::super::native_check_source::prepare_registered_handlers_check_using(request.clone(),&mut host,plan,Some(&provider)).unwrap()else{panic!("real second-reader failure must not issue Current")};
 assert_eq!(actual.downcast_ref::<io::Error>().map(io::Error::kind),Some(io::ErrorKind::NotFound));assert!(!report.clean_data());
 let(mut diagnostics,mut text)=(Vec::new(),Vec::new());report.write_once(&mut diagnostics,&mut text).unwrap();let text=String::from_utf8(text).unwrap();assert!(text.contains("structural results only")&&text.contains("code/structural.dm"));assert!(!text.contains("Ratchet lints passed")&&!text.contains("Ratchet lints failed")&&!text.contains("code/handler.dm"));
 let fake=BuildOutcome::HandlersQueryPrepared{query_revision:"0".into(),partial_source_revision:None,full_source_revision:None,retained:true};let mut called=false;assert!(host.with_prepared_handlers_report(&request,&fake,|_,_|{called=true;Ok(())}).is_err());assert!(!called);assert!(provider.second_reads()>=2);
}
#[test]fn registered_handler_failed_callback_output_io_cannot_replace_earlier_source_error(){
 struct Fail;impl io::Write for Fail{fn write(&mut self,_:&[u8])->io::Result<usize>{Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{panic!("no flush after failure")}}
 let _binding=bound();let(_root,request)=fixture(true);let mut host=BuildHost::default();let provider=actual_provider::source(true);let plan=actual_plan(&host);
 let super::super::native_check_source::PreparedHandlers::FailedFullOneShot{actual,report}=super::super::native_check_source::prepare_registered_handlers_check_using(request,&mut host,plan,Some(&provider)).unwrap()else{panic!("actual failed full")};
 assert_eq!(report.write_once(&mut Vec::new(),&mut Fail).unwrap_err().raw_os_error(),Some(1450));
 assert_eq!(actual.downcast_ref::<io::Error>().map(io::Error::kind),Some(io::ErrorKind::NotFound));
}
