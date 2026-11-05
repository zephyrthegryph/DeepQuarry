//! Shared report preparation and page delivery through one actual Original host.
use super::*;
use crate::{policy_request::{AnalysisContext,PolicyInputRequest,WorkspacePolicyRequest,WorkspaceAuxiliaryQuestion as Q},request::Command,runner_host::BuildHost};

#[path = "../../../../../analyze/fixtures/native-sem-reads/fixture.rs"]
mod source;
#[path = "../../../../../analyze/fixtures/report_configuration.rs"]
mod report_config;

const QUESTIONS:[Q;3]=[Q::SemReads,Q::UntrackedInputs,Q::SetterPublishes];

fn fixture()->(PathBuf,AnalyzeRequest){
    let root=crate::test_scratch::dir("semantic-report-cohort");
    for (relative,bytes) in source::files("allowed").unwrap(){
        let path=root.join(relative);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path,bytes).unwrap();
    }
    std::fs::create_dir(root.join("maps")).unwrap();
    let configuration=root.join("tools/ci/lint_scopes.toml");
    std::fs::create_dir_all(configuration.parent().unwrap()).unwrap();
    std::fs::write(&configuration,report_config::with_overlay(
        "[lint.auto_tracked.lists]\ninclude=[\"/datum/setter_probe::charge\"]\n")).unwrap();
    std::fs::write(root.join("code/setter.dm"),"/datum/setter_probe\n    var/charge\nSETTER(/datum/setter_probe, charge)\n/datum/setter_probe/proc/set_charge(value)\n    charge=value\n").unwrap();
    let project=root.join("deepquarry.dme");
    use std::io::Write;
    writeln!(std::fs::OpenOptions::new().append(true).open(&project).unwrap(),"#include \"code/setter.dm\"").unwrap();
    let Command::Build(build)=crate::cli::parse(&["prepare-query".into(),project.to_string_lossy().into_owned()]).unwrap()else{panic!("actual PrepareQuery parser")};
    let mut build=*build;
    build.no_cache=true;build.exact_inputs=true;build.workers=1;build.timeout_seconds=Some(60);
    build.engine_template=None;build.bootstrap_catalog=false;build.progress_enabled=false;build.cache_root=Some(root.join("cache"));
    build.policy_inputs=Some(PolicyInputRequest{
        analysis_context:Some(AnalysisContext::OriginalAnalyze0290),
        workspace:Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("maps")],configuration}),
        workspace_auxiliary:QUESTIONS.to_vec(),..Default::default()
    });
    (root,AnalyzeRequest{build,lints:vec!["setter_publishes".into(),"sem/reads".into(),"untracked_inputs".into()],raw:true,changed:None,scopes_root:None,baseline_mode:None,ci:false})
}

#[test]
fn actual_semantic_read_cohort_admits_only_exact_workspace_questions(){
    let(_,request)=fixture();
    request.validate(false).unwrap();
    let mut wrong=request.clone();wrong.lints[1]="scheduler".into();assert!(wrong.validate(false).is_err());
    let mut wrong=request.clone();wrong.lints[1]="untracked_inputs".into();assert!(wrong.validate(false).is_err());
    let mut wrong=request.clone();wrong.build.policy_inputs.as_mut().unwrap().workspace_auxiliary.pop();assert!(wrong.validate(false).is_err());
    let mut wrong=request.clone();wrong.build.policy_inputs.as_mut().unwrap().workspace_auxiliary.push(Q::DerivedReads);assert!(wrong.validate(false).is_err());
    let mut wrong=request.clone();wrong.build.policy_inputs.as_mut().unwrap().workspace_auxiliary.push(Q::SemHandlers);assert!(wrong.validate(false).is_err());
    let mut wrong=request.clone();wrong.build.policy_inputs.as_mut().unwrap().analysis_context=Some(AnalysisContext::OriginalChecker0290);assert!(wrong.validate(false).is_err());
    let mut wrong=request.clone();wrong.raw=false;wrong.baseline_mode=Some(BaselineMode::Update);assert!(wrong.validate(true).is_err());
}

#[test]
fn actual_semantic_read_cohort_uses_one_preparation_and_reuses_all_native_pages(){
    let(root,request)=fixture();
    request.validate(false).unwrap();
    let mut host=BuildHost::default();
    let outcome=crate::request_runner::run_build_with_host(request.build.clone(),&mut host).unwrap();
    let BuildOutcome::QueryPrepared{semantic_revision,source_revision,policy_revision:Some(policy_revision),retained:true}=outcome
        else{panic!("one real prepared workspace must own the entire cohort")};
    let pins=(semantic_revision,source_revision,policy_revision);
    let state=host.query_state();
    let held=state.lock().unwrap();
    let snapshot=held.snapshot.as_ref().unwrap();
    let mut delivery=Delivery::new(pins.clone());
    let mut policies=Vec::new();
    let before=host.query_db().db().stats(dm_query::Kind(4)).computed;
    collect_report_pages(&request,&mut delivery,false,|query|{
        let [SourceQuery::NativeWorkspaceSemanticReportPage{lints,..}]=query.source_queries.as_slice()
            else{panic!("cohort must issue its actual semantic page")};
        assert_eq!(lints.len(),1);
        if policies.last()!=lints.first(){policies.push(lints[0].clone())}
        Ok(super::super::query::evaluate_snapshot(&query,snapshot.prepared_query_tree().expect("retained semantic query tree"),&held)?)
    }).unwrap();
    assert_eq!(policies,request.lints);
    for name in &request.lints{
        assert!(!delivery.lints[name].run.sites.is_empty(),"{name} must contribute a real diagnostic");
    }
    let (clean,bytes,allows)=complete(&request,&mut delivery,false).unwrap();
    assert!(!clean);
    assert!(!allows.is_empty(),"the real sem/reads ALLOW witness belongs to the complete delivery");
    assert!(!root.join("deepquarry.dmb").exists());
    let after=host.query_db().db().stats(dm_query::Kind(4)).computed;
    assert!(after>before,"the cold cohort must actually ask for body syntax");
    let policy_count=host.query_db().db().stats(dm_query::Kind(12)).computed;
    let mut warm=Delivery::new(pins.clone());
    collect_report_pages(&request,&mut warm,false,|query|{
        Ok(super::super::query::evaluate_snapshot(&query,snapshot.prepared_query_tree().expect("retained semantic query tree"),&held)?)
    }).unwrap();
    assert_eq!(complete(&request,&mut warm,false).unwrap().1,bytes);
    assert_eq!(host.query_db().db().stats(dm_query::Kind(4)).computed,after);
    assert_eq!(host.query_db().db().stats(dm_query::Kind(12)).computed,policy_count);
    let mut failed=Delivery::new(pins);
    let fail=collect_report_pages(&request,&mut failed,false,|query|{
        let [SourceQuery::NativeWorkspaceSemanticReportPage{lints,..}]=query.source_queries.as_slice()else{panic!("unexpected query")};
        let mut reply=super::super::query::evaluate_snapshot(&query,snapshot.prepared_query_tree().expect("retained semantic query tree"),&held)?;
        if lints.as_slice()==["sem/reads"]{reply.source_revision=Some("0".repeat(32));}
        Ok(reply)
    }).unwrap_err();
    assert!(fail.to_string().contains("pins changed"));
    assert!(complete(&request,&mut failed,false).is_err(),"a completed first policy cannot certify the entire report");
}
