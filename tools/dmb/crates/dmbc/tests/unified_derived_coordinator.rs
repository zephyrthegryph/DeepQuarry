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

fn coordinator_request(build:BuildRequest)->dmbc::daemon::analyze::AnalyzeRequest{dmbc::daemon::analyze::AnalyzeRequest{build,lints:vec!["derived_reads".into()],raw:true,changed:None,scopes_root:None,baseline_mode:None,ci:false}}
#[test]fn actual_resident_derived_coordinator_current_report_has_real_pins_six_rules_allow_and_stale_hook(){let root=fixture("resident-derived-current");let req=coordinator_request(request(&root));let mut host=BuildHost::default();let mut diagnostics=Vec::new();let(clean,bytes)=dmbc::daemon::analyze::with_derived_host_to(&mut host,req.clone(),&mut diagnostics).unwrap();let data:dmbc::daemon::analyze::DerivedReport=serde_json::from_slice(&bytes).unwrap();assert!(!clean);assert!(data.complete&&!data.full_policy_parity&&!data.baseline);assert!(matches!(data.preparation,dmbc::daemon::analyze::DerivedPreparation::Current{ref semantic_revision,ref source_revision,ref policy_revision}if !semantic_revision.is_empty()&&!source_revision.is_empty()&&!policy_revision.is_empty()));assert!(!data.allow_usage.is_empty());assert!(data.text.contains("derived_reads: code/_generated/reads.dm is stale"));for rule in ["undeclared_read","declared_untracked","hop_not_relation","reaction_read_untracked","untracked_ui_read","exact_on_state_changed"]{assert!(data.text.contains(rule),"{rule}: {}",data.text)}let warm=dmbc::daemon::analyze::with_derived_host_to(&mut host,req,&mut diagnostics).unwrap();let warm:dmbc::daemon::analyze::DerivedReport=serde_json::from_slice(&warm.1).unwrap();assert_eq!(warm.text,data.text);assert_eq!(warm.allow_usage,data.allow_usage);}
#[test]fn actual_resident_derived_coordinator_refuses_mixed_roles_and_baseline_before_preparation(){let root=fixture("resident-derived-role");let mut req=coordinator_request(request(&root));let mut host=BuildHost::default();for names in [vec!["derived_reads".into(),"scheduler".into()],vec!["scheduler".into(),"derived_reads".into()]]{req.lints=names;assert!(dmbc::daemon::analyze::with_derived_host_to(&mut host,req.clone(),&mut Vec::new()).is_err())}req.lints=vec!["derived_reads".into()];req.baseline_mode=Some(dmbc::daemon::analyze::BaselineMode::Update);assert!(dmbc::daemon::analyze::with_derived_host_to(&mut host,req,&mut Vec::new()).is_err());assert!(host.declaration_retention_stats().is_none());assert!(!root.join("tools/ci/derived_reads_baseline.txt").exists());}
#[test]fn actual_resident_derived_coordinator_keeps_first_diagnostic_io_and_does_not_emit_clean_report(){use std::io;struct Failed(usize);impl io::Write for Failed{fn write(&mut self,_:&[u8])->io::Result<usize>{self.0+=1;Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{Ok(())}}let root=fixture("resident-derived-io");put(&root,"deepquarry.dme","#warn genuine cold preparation notice\n#include \"code/probe.dm\"\n");let mut host=BuildHost::default();let mut failed=Failed(0);let actual=dmbc::daemon::analyze::with_derived_host_to(&mut host,coordinator_request(request(&root)),&mut failed).unwrap_err();assert_eq!(failed.0,1);let mut cursor:Option<&(dyn std::error::Error+'static)>=Some(actual.as_ref());let mut code=None;while let Some(error)=cursor{if let Some(error)=error.downcast_ref::<io::Error>(){code=error.raw_os_error();if code.is_some(){break}}cursor=error.source()}assert_eq!(code,Some(1450));}

#[test]fn actual_resident_derived_coordinator_modified_raw_file_invalidates_current_report(){let root=fixture("resident-derived-changed-raw");let req=coordinator_request(request(&root));let mut host=BuildHost::default();let first=dmbc::daemon::analyze::with_derived_host_to(&mut host,req.clone(),&mut Vec::new()).unwrap();let first:dmbc::daemon::analyze::DerivedReport=serde_json::from_slice(&first.1).unwrap();put(&root,"code/probe.dm",format!("{}\n/obj/new_embedding\n    var/no_track\n/obj/new_embedding/ui_data()\n    return no_track\n/obj/new_embedding/mutate()\n    no_track = 7\n",SEED));let next=dmbc::daemon::analyze::with_derived_host_to(&mut host,req,&mut Vec::new()).unwrap();let next:dmbc::daemon::analyze::DerivedReport=serde_json::from_slice(&next.1).unwrap();assert_ne!(first.text,next.text);match(first.preparation,next.preparation){(dmbc::daemon::analyze::DerivedPreparation::Current{source_revision:a,..},dmbc::daemon::analyze::DerivedPreparation::Current{source_revision:b,..})=>assert_ne!(a,b),_=>panic!("both actual complete prepares must have real current revisions")}}
