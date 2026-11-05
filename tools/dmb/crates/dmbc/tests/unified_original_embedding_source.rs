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
use actual_provider::source;
use std::io;
fn coordinator_request(build:BuildRequest)->dmbc::daemon::analyze::AnalyzeRequest{dmbc::daemon::analyze::AnalyzeRequest{build,lints:vec!["derived_reads".into()],raw:true,changed:None,scopes_root:None,baseline_mode:None,ci:false}}
#[test]fn embedding_same_actual_factory_second_open_failure_reports_once_without_source_snapshot(){let root=fixture("embedding-actual-second-open");let request=request(&root);let provider=source(true);let mut host=BuildHost::default();let mut called=0;let attempt=host.with_derived_attempt_report_from_to(request,&provider,&mut Vec::new(),|data,_|{called+=1;assert!(!data.sites().is_empty());assert!(data.generated_is_stale());Ok(data.sites().len())}).unwrap();assert_eq!(called,1);assert_eq!(provider.second_reads(),1);assert_eq!(attempt.preparation.unwrap_err().downcast_ref::<io::Error>().map(io::Error::kind),Some(io::ErrorKind::NotFound));assert!(attempt.report.unwrap().unwrap()>0);assert!(host.declaration_retention_stats().is_none_or(|stats|stats.current_keys==0));}
#[test]fn embedding_actual_coordinator_failed_root_dto_has_no_fabricated_revisions(){let root=fixture("embedding-coordinator-real-failure");let provider=source(true);let mut host=BuildHost::default();let(clean,bytes)=dmbc::daemon::analyze::with_derived_host_from_to(&mut host,coordinator_request(request(&root)),&provider,&mut Vec::new()).unwrap();assert!(!clean);let data:dmbc::daemon::analyze::DerivedReport=serde_json::from_slice(&bytes).unwrap();assert!(matches!(data.preparation,dmbc::daemon::analyze::DerivedPreparation::FailedRootOneShot{..}));let wire:serde_json::Value=serde_json::from_slice(&bytes).unwrap();for field in ["semantic_revision","source_revision","policy_revision"]{assert!(wire["preparation"].get(field).is_none());}assert!(data.text.contains("derived_reads: code/_generated/reads.dm is stale"));assert!(!root.join("deepquarry.dme").exists());}
#[test]fn embedding_actual_factory_does_not_reuse_default_provider_cache_and_preserves_later_callback_io(){let root=fixture("embedding-after-default-host");let mut host=BuildHost::default();let req=request(&root);let BuildOutcome::QueryPrepared{semantic_revision:old_semantic,source_revision:old_source,..}=run(&mut host,&req)else{unreachable!()};put(&root,"code/probe.dm",format!("{}\n/obj/new_embedding\n    var/no_track\n/obj/new_embedding/ui_data()\n    return list(no_track)\n/obj/new_embedding/mutate()\n    no_track = 7\n",SEED));let provider=source(false);let current=host.with_derived_attempt_report_from_to(req.clone(),&provider,&mut Vec::new(),|data,_|Ok(data.sites().iter().zip(data.source_text()).any(|(site,line)|site.rule=="untracked_ui_read"&&line.contains("return list(no_track)")))).unwrap();let BuildOutcome::QueryPrepared{semantic_revision,source_revision,..}=current.preparation.unwrap()else{panic!("expected current embedded source")};assert_ne!(semantic_revision,old_semantic);assert_ne!(source_revision,old_source);assert!(provider.second_reads()>0);assert!(current.report.unwrap().unwrap(),"borrowed active source must run its own changed declaration");let provider=source(true);let failed=host.with_derived_attempt_report_from_to(req,&provider,&mut Vec::new(),|_,_|Err::<(),_>(io::Error::from_raw_os_error(1450))).unwrap();assert_eq!(failed.preparation.unwrap_err().downcast_ref::<io::Error>().map(io::Error::kind),Some(io::ErrorKind::NotFound));assert_eq!(failed.report.unwrap().unwrap_err().raw_os_error(),Some(1450));}
