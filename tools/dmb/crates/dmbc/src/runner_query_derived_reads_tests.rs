//! Real cold host/QueryDb controls. These require the conditional request route.
use super::*;
use crate::{policy_request::{AnalysisContext,PolicyInputRequest,WorkspacePolicyRequest,WorkspaceAuxiliaryQuestion as Q},request::{BuildOutcome,BuildRequest,Command}};
pub(super) const SEED:&str=r#"#define TRACKED(T,V)
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
fn request(case:&str)->(crate::runner_host::BuildHost,BuildRequest,PathBuf){
 let root=crate::test_scratch::dir(&format!("derived-actual-host-{case}"));std::fs::create_dir_all(root.join("code/engine/_generated")).unwrap();std::fs::create_dir_all(root.join("code/_generated")).unwrap();std::fs::create_dir_all(root.join("tools/ci")).unwrap();
 for(path,text)in[("code/probe.dm",SEED),("code/engine/_generated/auto_tracked.dm",""),("code/_generated/reads.dm","// deliberately stale actual file\n"),("deepquarry.dme","#include \"code/probe.dm\"\n#include \"code/engine/_generated/auto_tracked.dm\"\n#include \"code/_generated/reads.dm\"\n"),("tools/ci/lint_scopes.toml","")]{std::fs::write(root.join(path),text).unwrap();}
 let Command::Build(request)=crate::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()else{panic!("actual PrepareQuery")};let mut request=*request;request.no_cache=true;request.exact_inputs=true;request.progress_enabled=false;request.workers=1;request.cache_root=Some(root.join("cache"));
 request.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:vec![root.join("code")],configuration:root.join("tools/ci/lint_scopes.toml")}),workspace_auxiliary:vec![Q::DerivedReads],..Default::default()});(crate::runner_host::BuildHost::default(),request,root)
}
#[test]fn actual_derived_cold_preflight_and_same_current_query_child_produce_all_six_rules_then_reuse(){
 let(mut host,request,_root)=request("whole");let queries=Arc::clone(host.query_db());assert!(matches!(crate::request_runner::run_build_with_host(request,&mut host).unwrap(),BuildOutcome::QueryPrepared{..}));
 let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().expect("real native SourceSnapshot");let first=snapshot.with_original_derived_policy_report(|data,_,_|{let rules=data.sites().iter().map(|site|site.rule.as_str()).collect::<std::collections::BTreeSet<_>>();assert_eq!(rules.len(),6,"actual full whole-judge rules, not a registered empty producer");assert!(!data.allow_used().is_empty());assert!(data.generated_is_stale());Ok(data.sites().iter().map(|site|(site.rule.clone(),site.rel.clone(),site.line)).collect::<Vec<_>>())}).unwrap();
 let before=queries.db().stats(dm_query::Kind(4)).computed;let child=queries.db().stats(dm_query::Kind(12)).computed;
 let again=snapshot.with_original_derived_policy_report(|data,_,_|Ok(data.sites().iter().map(|site|(site.rule.clone(),site.rel.clone(),site.line)).collect::<Vec<_>>())).unwrap();assert_eq!(again,first);assert_eq!(queries.db().stats(dm_query::Kind(4)).computed,before,"same raw whole policy report cannot request a second set of BODY syntax");assert_eq!(queries.db().stats(dm_query::Kind(12)).computed,child,"genuine current child cache hit");
}
#[test]fn actual_derived_invalid_configuration_precedes_even_missing_manifest_on_cold_host(){
 let(mut host,request,root)=request("ordering");std::fs::write(root.join("tools/ci/lint_scopes.toml"),"[not valid TOML").unwrap();std::fs::remove_file(root.join("deepquarry.dme")).unwrap();let actual=crate::request_runner::run_build_with_host(request,&mut host).unwrap_err();let message=actual.to_string();assert!(message.contains("TOML")||message.contains("toml"),"first actual config failure must survive before missing manifest: {message}");assert!(host.query_tree().is_none());
}
