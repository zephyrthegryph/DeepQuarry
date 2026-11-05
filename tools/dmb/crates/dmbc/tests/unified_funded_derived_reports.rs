//! Real in-process selected report through the genuine current host/Kind12.
//! No daemon, GUI, source constructor, test-only authority or legacy fallback.
#[path="../../../shared/test_scratch.rs"]mod scratch;
#[path="../../../../analyze/fixtures/report_configuration.rs"]mod report_configuration;
use dmbc::{policy_request::{AnalysisContext,PolicyInputRequest,WorkspacePolicyRequest,WorkspaceAuxiliaryQuestion as Q},request::{BuildRequest,BuildOutcome,Command},runner_host::BuildHost};
use std::path::{Path,PathBuf};
fn put(root:&Path,relative:&str,bytes:impl AsRef<[u8]>){let path=root.join(relative);std::fs::create_dir_all(path.parent().unwrap()).unwrap();std::fs::write(path,bytes).unwrap();}
fn fixture(label:&str)->PathBuf{let root=scratch::dir(label);put(&root,"deepquarry.dme","#include \"code/probe.dm\"\n");put(&root,"code/probe.dm",SEED);put(&root,"code/_generated/reads.dm","// actual stale raw generated state\n");put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay(""));root}
fn request(root:&Path)->BuildRequest{let Command::Build(request)=dmbc::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()else{panic!("actual public PrepareQuery")};let mut request=*request;request.no_cache=true;request.exact_inputs=true;request.progress_enabled=false;request.workers=1;request.timeout_seconds=Some(60);request.engine_template=None;request.bootstrap_catalog=false;request.cache_root=Some(root.join("cache"));request.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:root.to_owned(),recursive_roots:vec![root.join("code")],configuration:root.join("tools/ci/lint_scopes.toml")}),workspace_auxiliary:vec![Q::DerivedReads],..Default::default()});request}

const SEED:&str=r#"#define TRACKED(T,V)
#define PUBLISHED_BY(T,V,K)
/datum/foreign
    var/far
/obj/probe
    var/value
    var/missing
    var/mutable
    var/link
/obj/probe/derived()
    return list(drawn_from(nameof(value), rel(nameof(link), nameof(/datum/foreign::far))))
/obj/probe/draw()
    return missing
/obj/probe/on_state_changed()
    return
/obj/probe/ui_data()
    return list(mutable, value)
/obj/probe/mutate()
    mutable = 7
/obj/probe/child/draw()
    // ALLOW(derived_reads): intentional fixture read kept by the original policy
    return missing
/mob/probe
    var/custom_health
/mob/probe/life_hud()
    return custom_health
"#;

fn run(host:&mut BuildHost,request:&BuildRequest)->BuildOutcome{let actual=dmbc::request_runner::run_build_with_host(request.clone(),host).unwrap();assert!(matches!(actual,BuildOutcome::QueryPrepared{retained:true,..}));actual}
fn report(host:&BuildHost,request:&BuildRequest,prepared:&BuildOutcome)->(String,Vec<(String,String,u32)>,usize,bool){host.with_prepared_derived_report(request,prepared,|data,configuration|{
 let empty=dq_analyze::scopes::LintScope::default();let scope=configuration.borrowed_report_scope(data.metadata().name,data.metadata().group).unwrap_or(&empty);let root=request.policy_inputs.as_ref().unwrap().workspace.as_ref().unwrap().root.as_path();
 let finished=dq_analyze::policy_finish::finish_report(data.metadata(),scope,data,dq_analyze::lint::Run{sites:data.sites().to_vec(),notes:Vec::new()},data.allow_used().to_vec(),dq_analyze::policy_finish::Timing::default(),root,&None,true,|_,_,_|false,|_,text|{if let Some(message)=data.post_judge_message(){text.push_str(message);true}else{false}});
 assert!(finished.internal_error.is_none());Ok((finished.text,data.sites().iter().map(|site|(site.rule.clone(),site.rel.clone(),site.line)).collect(),data.allow_used().len(),data.generated_is_stale()))
}).unwrap()}

#[path="support/actual_original_provider.rs"]mod actual_provider;
use std::io;
#[test]fn actual_funded_report_quota_inside_held_gate_then_same_host_reprepare_recovers(){let root=fixture("funded-report-real-quota");let req=request(&root);let provider=actual_provider::source(false);let mut host=BuildHost::default();let mut called=false;let first=host.with_funded_derived_attempt_report_to(req.clone(),Some(&provider),&mut Vec::new(),|data,_,work|{called=true;assert!(!data.sites().is_empty());work.reserve(usize::MAX)?;Ok(())}).unwrap();assert!(called&&first.preparation().is_ok());assert_eq!(first.report().unwrap().as_ref().unwrap_err().kind(),io::ErrorKind::OutOfMemory);drop(first);let next=host.with_funded_derived_attempt_report_to(req,Some(&provider),&mut Vec::new(),|data,_,work|{work.reserve(64)?;assert!(!data.sites().is_empty());Ok(vec![3u8;32])}).unwrap();assert!(next.preparation().is_ok());assert_eq!(next.report().unwrap().as_ref().unwrap(),&vec![3u8;32]);assert!(provider.second_reads()>=2,"recovery must perform genuine new preparation; no denied budget reset");}
#[test]fn actual_funded_callback_first_io_does_not_deadlock_and_same_host_reprepares(){let root=fixture("funded-report-real-io");let req=request(&root);let provider=actual_provider::source(false);let mut host=BuildHost::default();let first=host.with_funded_derived_attempt_report_to(req.clone(),Some(&provider),&mut Vec::new(),|_,_,work|{work.reserve(64)?;Err::<(),_>(io::Error::from_raw_os_error(1450))}).unwrap();assert!(first.preparation().is_ok());assert_eq!(first.report().unwrap().as_ref().unwrap_err().raw_os_error(),Some(1450));drop(first);let next=host.with_funded_derived_attempt_report_to(req,Some(&provider),&mut Vec::new(),|data,_,work|{work.reserve(16)?;Ok(data.sites().len())}).unwrap();assert!(next.preparation().is_ok());assert!(*next.report().unwrap().as_ref().unwrap()>0);}
#[test]fn actual_funded_payload_keeps_native_credit_until_payload_owner_drops(){let root=fixture("funded-report-live-credit");let req=request(&root);let provider=actual_provider::source(false);let mut host=BuildHost::default();let output=host.with_funded_derived_attempt_report_to(req,Some(&provider),&mut Vec::new(),|_,_,work|{work.reserve(65_536)?;Ok(vec![7u8;65_536])}).unwrap();assert!(output.preparation().is_ok());assert_eq!(output.report().unwrap().as_ref().unwrap().len(),65_536);let during=host.source_input_admission_bytes().unwrap();drop(output);let after=host.source_input_admission_bytes().unwrap();assert!(during>=after+65_536,"real native admission must retire only after its actual byte payload owner");}
#[test]fn actual_failed_root_funded_callback_keeps_source_first_over_quota_and_later_io(){for quota in [true,false]{let root=fixture("funded-report-source-first");let req=request(&root);let provider=actual_provider::source(true);let mut host=BuildHost::default();let actual=host.with_funded_derived_attempt_report_to(req,Some(&provider),&mut Vec::new(),|data,_,work|{assert!(!data.sites().is_empty());if quota{work.reserve(usize::MAX)?;}Err::<(),_>(io::Error::from_raw_os_error(1450))}).unwrap();assert_eq!(actual.preparation().as_ref().unwrap_err().downcast_ref::<io::Error>().map(io::Error::kind),Some(io::ErrorKind::NotFound));let report=actual.report().unwrap().as_ref().unwrap_err();if quota{assert_eq!(report.kind(),io::ErrorKind::OutOfMemory)}else{assert_eq!(report.raw_os_error(),Some(1450))}}}
