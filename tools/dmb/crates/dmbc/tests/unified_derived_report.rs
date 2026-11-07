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
#[test]fn actual_public_cold_and_warm_current_derived_reports_execute_six_rule_producer_allow_ledger_and_stale_hook(){let root=fixture("public-derived-whole-report");let request=request(&root);let mut host=BuildHost::default();let prepared=run(&mut host,&request);let cold=report(&host,&request,&prepared);let rules=cold.1.iter().map(|row|row.0.as_str()).collect::<std::collections::BTreeSet<_>>();assert_eq!(rules.len(),6,"all six actual whole-judge rules must run");assert!(cold.2>0);assert!(cold.3);assert!(cold.0.contains("derived_reads: code/_generated/reads.dm is stale"));assert_eq!(report(&host,&request,&prepared),cold,"warm genuine current report cannot become an empty clean response");}
#[test]
fn selected_derived_reads_preserves_the_exclusive_six_rules_staleness_and_allow_ledger() {
    use dq_analyze::{captured_allow_annotations::{full_unused, Operation}, captured_generator_budget::Budget, selected_exclusions_wire::Roster};
    let root = fixture("public-selected-derived-reads");
    put(&root, "deepquarry.dme", "#warn derived_selected_notice\n#include \"code/probe.dm\"\n");
    put(&root, "maps/unused.dm", "// ALLOW(scheduler): this fixture intentionally has no scheduler call\n/datum/map_policy_input\n");
    let exclusive = request(&root);
    let mut exclusive_host = BuildHost::default();
    let prepared = run(&mut exclusive_host, &exclusive);
    let expected = report(&exclusive_host, &exclusive, &prepared);
    assert_eq!(expected.1.iter().map(|row| &row.0).collect::<std::collections::BTreeSet<_>>().len(), 6);
    assert!(expected.2 > 0 && expected.3);

    let mut selected = exclusive.clone();
    selected.cache_root = Some(scratch::dir("public-selected-derived-cache"));
    let intent = selected.policy_inputs.as_mut().unwrap();
    intent.workspace_auxiliary.clear();
    intent.workspace.as_mut().unwrap().recursive_roots = vec![root.join("code"), root.join("maps")];
    let budget = Budget::new(1 << 20).unwrap();
    let mut operation = Operation { budget: &budget, poll: &|| Ok(()) };
    let registry = full_unused::registered_full_selection(&[], &mut operation).unwrap();
    let exclusions: Vec<_> = registry.names().iter().filter(|name| !Roster::WithDerivedReads.names().contains(&name.as_str()))
        .map(|name| format!("-{name}")).collect();
    let mut host = BuildHost::default();
    let mut diagnostics = Vec::new();
    let mut output = Vec::new();
    assert!(!host.write_original_exclusions_report(selected.clone(), &exclusions, &mut diagnostics, &mut output).unwrap());
    let text = std::str::from_utf8(&output).unwrap();
    assert!(text.contains(expected.0.as_str()), "selected Derived section differs from exclusive:\n{text}\nexpected:\n{}", expected.0);
    assert!(text.contains("ALLOW(scheduler): 1 annotation"), "selected parent must capture the map-only annotation: {text}");
    assert!(text.contains("allow annotations: 1 unused"), "only the map annotation should be unused: {text}");
    assert_eq!(String::from_utf8_lossy(&diagnostics).matches("derived_selected_notice").count(), 1);
    let mut warm = Vec::new();
    assert!(!host.write_original_exclusions_report(selected.clone(), &exclusions, &mut Vec::new(), &mut warm).unwrap());
    assert_eq!(warm, output);

    let unsupported: Vec<_> = exclusions.iter().filter(|name| name.as_str() != "-cooldown").cloned().collect();
    let mut rejected = Vec::new();
    let mut rejected_diagnostics = Vec::new();
    let error = host.write_original_exclusions_report(selected, &unsupported, &mut rejected_diagnostics, &mut rejected).unwrap_err();
    assert_eq!(error.downcast_ref::<std::io::Error>().map(std::io::Error::kind), Some(std::io::ErrorKind::Unsupported));
    assert!(rejected.is_empty() && rejected_diagnostics.is_empty());
}

#[test]fn actual_public_derived_report_rejects_foreign_host_stale_revision_and_wrong_request_role_before_callback(){let root=fixture("public-derived-report-same-owner");let request=request(&root);let mut host=BuildHost::default();let first=run(&mut host,&request);report(&host,&request,&first);let other_root=fixture("public-derived-report-foreign");let mut other=BuildHost::default();let other_request=self::request(&other_root);let _=run(&mut other,&other_request);let mut entered=false;assert!(other.with_prepared_derived_report(&request,&first,|_,_|{entered=true;Ok(())}).is_err());assert!(!entered);
 let mut wrong=request.clone();wrong.policy_inputs.as_mut().unwrap().workspace_auxiliary=vec![Q::SemReads];assert!(host.with_prepared_derived_report(&wrong,&first,|_,_|{entered=true;Ok(())}).is_err());assert!(!entered);
 put(&root,"code/extra.dm","/datum/new_raw_source\n    var/value\n");let current=run(&mut host,&request);assert!(host.with_prepared_derived_report(&request,&first,|_,_|{entered=true;Ok(())}).is_err());assert!(!entered);report(&host,&request,&current);
}
#[test]fn actual_public_derived_report_preserves_first_consumer_io_then_same_current_source_recovers(){let root=fixture("public-derived-report-consumer-io");let request=request(&root);let mut host=BuildHost::default();let prepared=run(&mut host,&request);let actual=host.with_prepared_derived_report(&request,&prepared,|_,_|Err::<(),_>(std::io::Error::from_raw_os_error(1450))).unwrap_err();assert_eq!(actual.raw_os_error(),Some(1450));report(&host,&request,&prepared);}

fn synthetic_first_marker_report(non_utf8:bool){let root=fixture("public-derived-authentic-synthetic-root");let request=request(&root);if non_utf8{put(&root,"deepquarry.dme",b"\xff#include \"code/probe.dm\"\n")}else{std::fs::remove_file(root.join("deepquarry.dme")).unwrap()}let mut host=BuildHost::default();let prepared=run(&mut host,&request);let cold=report(&host,&request,&prepared);let rules=cold.1.iter().map(|s|s.0.as_str()).collect::<std::collections::BTreeSet<_>>();assert_eq!(rules.len(),6,"authentic synthetic entry must still issue complete nonvacuous whole policy data, not None/empty bypass");assert!(cold.2>0);assert!(cold.3);assert_eq!(report(&host,&request,&prepared),cold);let current=run(&mut host,&request);assert_eq!(report(&host,&request,&current),cold,"second genuine preparation must preserve old synthetic root recipe and actual CODE");if non_utf8{assert_eq!(std::fs::read(&request.project).unwrap()[0],0xff)}else{assert!(!request.project.exists(),"private synthetic header must not install a physical DME or conceal first-marker absence")}}
#[test]fn actual_whole_derived_host_missing_initial_marker_uses_authentic_synthetic_entry(){synthetic_first_marker_report(false)}
#[test]fn actual_whole_derived_host_non_utf8_initial_marker_uses_authentic_synthetic_entry(){synthetic_first_marker_report(true)}
