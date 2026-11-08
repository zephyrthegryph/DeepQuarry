//! Actual same-host analysis purpose, original owners and variant isolation.
use super::*;
use crate::{policy_request::{AnalysisContext,PolicyInputRequest,WorkspacePolicyRequest},request::{BuildRequest,Command,BuildOutcome}};
pub(super) fn fixture(source:&str)->(crate::runner_host::BuildHost,BuildRequest,PathBuf){
 let root=crate::test_scratch::dir("original-analysis-context");std::fs::create_dir(root.join("code")).unwrap();std::fs::create_dir(root.join("maps")).unwrap();std::fs::create_dir_all(root.join("tools/ci")).unwrap();
 std::fs::write(root.join("deepquarry.dme"),b"#ifdef __MAIN__\n/datum/root_main\n#endif\n#if defined(__MAIN__)\n#error MAIN must not be a default object macro\n#endif\n#include \"code/probe.dm\"\n").unwrap();
 std::fs::write(root.join("code/probe.dm"),source).unwrap();std::fs::write(root.join("tools/ci/lint_scopes.toml"),b"").unwrap();
 let args=vec!["prepare-query".to_owned(),root.join("deepquarry.dme").to_string_lossy().into_owned()];let Command::Build(request)=crate::cli::parse(&args).unwrap()else{panic!("actual PrepareQuery parser changed")};let mut request=*request;
 request.no_cache=true;request.exact_inputs=true;request.progress_enabled=false;request.workers=1;request.cache_root=Some(root.join("cache"));
 let mut intent=PolicyInputRequest::default();intent.analysis_context=Some(AnalysisContext::OriginalChecker0290);intent.workspace=Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("maps")],configuration:root.join("tools/ci/lint_scopes.toml")});request.policy_inputs=Some(intent);
 (crate::runner_host::BuildHost::default(),request,root)
}
pub(super) fn run(host:&mut crate::runner_host::BuildHost,request:&BuildRequest){
 let result=crate::request_runner::run_build_with_host(request.clone(),host).unwrap();assert!(matches!(result,BuildOutcome::QueryPrepared{..}));
}
pub(super) fn current<R>(host:&crate::runner_host::BuildHost,consume:impl FnOnce(&SourceSnapshot)->R)->R{
 let state=host.query_state();let guard=state.lock().unwrap();consume(guard.snapshot.as_ref().unwrap())
}
#[test]
fn actual_origin_mapping_alias_holds_parent_past_native_db_drop() {
    let (mut host, mut request, _) = fixture("/proc/origin_parent_test()\n    return 7\n");
    request.policy_inputs.as_mut().unwrap().analysis_context=Some(AnalysisContext::OriginalAnalyze0290);
    let counter=Arc::clone(crate::query_db::body_syntax_counter_for_test(host.query_db()));
    let parent=Arc::clone(counter.shared_reservation().unwrap());
    let baseline=parent.reserved_bytes();
    let syntax_base=counter.allocation_lease_reserved();
    let db=Arc::downgrade(host.query_db());

    run(&mut host,&request);
    // A published archive also owns its BodySyntaxQueries. Escape its actual
    // mapping instead, which retains the same physical pages without the Db.
    let mapping=current(&host,|snapshot|{
        let mapping=snapshot.source_mapping.as_ref().unwrap();
        assert!(Arc::ptr_eq(mapping,snapshot.body_archive.as_ref().unwrap().source_mapping()));
        Arc::clone(mapping)
    });
    let charged_origins=||parent.reserved_bytes()-baseline-(counter.allocation_lease_reserved()-syntax_base);
    assert!(charged_origins()>0,"actual prepare must debit source pages separately from syntax");
    drop(host);
    assert!(db.upgrade().is_none(),"only origin storage, not the native host, escapes");
    assert!(charged_origins()>0,"escaped actual mapping keeps the real source-page debit");
    drop(mapping);
    assert_eq!(counter.allocation_lease_reserved(),syntax_base);
    assert_eq!(parent.reserved_bytes(),baseline);
}

#[test]fn actual_original_analysis_context_has_guarded_declarations_warm_bodies_and_isolated_native_variant(){
 let source="#if DM_BUILD == 1666 && DM_VERSION == 516 && SPACEMAN_DMM\n/datum/original_only\n#else\n/datum/native_only\n#endif\n/proc/probe()\n    return 1\n";
 let(mut host,request,_)=fixture(source);let queries=Arc::clone(host.query_db());run(&mut host,&request);
 let first=current(&host,|first|{assert!(first.tree.lookup_type(dm_ir::SymbolId::of("/datum/original_only")).is_some());assert!(first.tree.lookup_type(dm_ir::SymbolId::of("/datum/native_only")).is_none());assert!(first.diagnostic_declarations.as_ref().unwrap().errors().is_empty());assert!(first.resolved.is_none());assert!(first.replay_proof.is_none());assert!(first.source_answers.is_none());first.require_analysis_context(Some(AnalysisContext::OriginalChecker0290)).unwrap();assert!(first.require_analysis_context(None).is_err());let archive=first.body_archive.as_ref().unwrap();assert!(archive.uses_body_queries(queries.as_ref()));for ordinal in 0..archive.len(){archive.parse_checked(ordinal).unwrap();}Arc::clone(&first.tree)});
 let before=queries.db().stats(dm_query::Kind(4)).computed;run(&mut host,&request);
 current(&host,|warm|{assert!(Arc::ptr_eq(&first,&warm.tree));for ordinal in 0..warm.body_archive.as_ref().unwrap().len(){warm.body_archive.as_ref().unwrap().parse_checked(ordinal).unwrap();}});assert_eq!(queries.db().stats(dm_query::Kind(4)).computed,before);
 let original_state=host.query_state();
 let mut native=request.clone();native.policy_inputs.as_mut().unwrap().analysis_context=None;run(&mut host,&native);
 assert!(!Arc::ptr_eq(&original_state,&host.query_state()));{let stashed=original_state.lock().unwrap();assert_eq!(stashed.last_request_outcome,"analyzed");let original=stashed.snapshot.as_ref().unwrap();assert!(Arc::ptr_eq(&original.tree,&first));original.require_analysis_context(Some(AnalysisContext::OriginalChecker0290)).unwrap();}
 current(&host,|snapshot|{assert!(snapshot.tree.lookup_type(dm_ir::SymbolId::of("/datum/native_only")).is_some());assert!(snapshot.require_analysis_context(Some(AnalysisContext::OriginalChecker0290)).is_err());});assert!(Arc::ptr_eq(host.query_db(),&queries));assert!(host.stashed_variants()>=1);
 run(&mut host,&request);current(&host,|restored|{assert!(restored.tree.lookup_type(dm_ir::SymbolId::of("/datum/original_only")).is_some());assert!(Arc::ptr_eq(&first,&restored.tree));});assert!(host.serves_variant_context(&request.project,&request.defines,Some(AnalysisContext::OriginalChecker0290)));assert!(!host.serves_variant(&request.project,&request.defines));
}
#[test]fn actual_original_analysis_context_zero_errors_remains_diagnostic_without_runtime_abi(){
 let(mut host,request,_)=fixture("/proc/analysis_compare()\n    return 1 <=> 2\n");run(&mut host,&request);current(&host,|snapshot|{assert!(snapshot.diagnostic_declarations.as_ref().unwrap().errors().is_empty());assert!(snapshot.resolved.is_none());assert!(snapshot.native_value_input.is_none());assert!(snapshot.replay_proof.is_none());let archive=snapshot.body_archive.as_ref().unwrap();assert_eq!(archive.len(),1);archive.parse_checked(0).unwrap();});
}
#[test]fn actual_original_analysis_context_rejects_unmatched_options_before_any_project_read(){
 let(mut host,request,root)=fixture("/datum/plain\n");for kind in 0..6{let mut invalid=request.clone();invalid.project=root.join("does-not-exist.dme");match kind{0=>{invalid.defines.insert("CUSTOM".into(),"1".into());},1=>invalid.engine_template=Some(root.join("missing-engine.bin")),2=>invalid.trace_path=Some(root.join("trace")),3=>invalid.record_inputs=Some(root.join("record")),4=>invalid.replay_inputs=Some(root.join("replay")),_=>invalid.artifact_directory=Some(root.join("output"))};let error=crate::request_runner::run_build_with_host(invalid,&mut host).unwrap_err();let actual=error.downcast_ref::<std::io::Error>().expect("typed pre-IO option refusal");assert_eq!(actual.kind(),std::io::ErrorKind::InvalidInput);assert!(host.query_state().lock().unwrap().snapshot.is_none());}assert!(!root.join("output").exists());assert!(!root.join("trace").exists());
}

#[path="../../../../analyze/fixtures/native-analysis-context/observations.rs"]mod observations;
#[test]fn actual_original_analysis_default_context_complete_104_function_dynamic_program_and_guarded_types(){
 let project=std::fs::canonicalize(std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../analyze/fixtures/native-analysis-context/basic/deepquarry.dme")).unwrap();let root=project.parent().unwrap().to_path_buf();let cache=crate::test_scratch::dir("original-analysis-context-observations");
 let args=vec!["prepare-query".to_owned(),project.to_string_lossy().into_owned()];let Command::Build(request)=crate::cli::parse(&args).unwrap()else{panic!("actual PrepareQuery parser changed")};let mut request=*request;request.no_cache=true;request.exact_inputs=true;request.workers=1;request.progress_enabled=false;request.cache_root=Some(cache);
 let mut intent=PolicyInputRequest::default();intent.analysis_context=Some(AnalysisContext::OriginalChecker0290);intent.workspace=Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("maps")],configuration:root.join("tools/ci/lint_scopes.toml")});request.policy_inputs=Some(intent);
 let mut host=crate::runner_host::BuildHost::default();run(&mut host,&request);
 current(&host,|snapshot|{snapshot.require_analysis_context(Some(AnalysisContext::OriginalChecker0290)).unwrap();assert!(snapshot.diagnostic_declarations.as_ref().unwrap().errors().is_empty());let _guard=snapshot.workspace_native_read().unwrap();
  host.semantic.as_ref().unwrap().with_remembered_analysis_source(|view|{
   assert!(Arc::ptr_eq(view.mapping(),snapshot.source_mapping.as_ref().unwrap()));assert!(Arc::ptr_eq(view.archive(),snapshot.body_archive.as_ref().unwrap()));
   let tree=&snapshot.tree;let mut types:Vec<_>=tree.types().iter().map(|node|{let path=tree.symbols().text(node.path).unwrap().to_owned();let ty=tree.lookup_type(node.path).unwrap();let parent=tree.parent(ty).map(|parent|tree.symbols().text(tree.type_node(parent).unwrap().path).unwrap().to_owned());(path,parent)}).collect();types.sort();
   let dm_tree::frontend::FrontendDirectivePlan::OriginalDiagnostic(plan) = view.original_plan() else {
    panic!("expected the actual Original diagnostic plan");
   };
   assert_eq!(plan.final_macros().unwrap().len(),104);assert_eq!(types.iter().filter(|(path,_)|path.starts_with("/datum/context_")).count(),108);
   let result=serde_json::json!({"schema":"analysis-default-context-observations-v1","default_macro_count":plan.final_macros().unwrap().len(),"types":types,"tokens":observations::tokens(view.expanded_text())});println!("NATIVE_ANALYSIS_DEFAULT_CONTEXT={result}");
  }).unwrap().unwrap();
 });
}

#[test]fn actual_original_analysis_workspace_reports_bind_context_and_reject_ordinary_model_questions(){
 use crate::daemon::query::{self,QueryRequest,SourceQuery};
 let(mut host,request,root)=fixture("/proc/probe()\n    return 1\n");std::fs::write(root.join("tools/ci/lint_scopes.toml"),include_bytes!("../../../../ci/lint_scopes.toml")).unwrap();run(&mut host,&request);
 let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();
 let query=QueryRequest{analysis_context:Some(AnalysisContext::OriginalChecker0290),timeout_seconds:Some(60),project:request.project.clone(),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",snapshot.tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:Vec::new(),source_queries:vec![SourceQuery::NativeWorkspaceRawReportPage{root:root.clone(),configuration:root.join("tools/ci/lint_scopes.toml"),lints:vec!["scheduler".into()],cursor:None,limit:128}]};
 let reply=query::evaluate_snapshot(&query,&snapshot.tree,&state).unwrap();assert!(reply.jsonl.contains("source_native_workspace_raw_report"));query::validate_effect_batch_for_test(&query,&reply).unwrap();
 let mut wrong=query.clone();wrong.analysis_context=None;assert_eq!(query::evaluate_snapshot(&wrong,&snapshot.tree,&state).unwrap_err().kind(),std::io::ErrorKind::InvalidInput);
 let mut ordinary=query;ordinary.source_queries=vec![SourceQuery::ResolvedQueries{queries:Vec::new()}];assert!(query::evaluate_snapshot(&ordinary,&snapshot.tree,&state).is_err());
 assert!(snapshot.resolved.is_none());assert!(snapshot.native_value_input.is_none());
}

#[test]fn actual_previous_analysis_census_counts_records_after_publication_retires_and_deduplicates_aliases(){
 let(mut host,request,_)=fixture("/datum/census_analysis\n/proc/probe()\n    return 1\n");run(&mut host,&request);let publication=host.query_state().lock().unwrap().snapshot.take();drop(publication);let semantic=host.semantic.as_ref().unwrap();
 let mut once=crate::heap_census::HeapCensus::new("analysis-once");once.retained_frontend_owners(Some(semantic),None,None);let once=once.finish();assert!(once.owners.iter().any(|row|row.owner=="retained_analysis.owners"&&row.unique_known_capacity_bytes>0));assert!(once.owners.iter().any(|row|row.owner=="retained_analysis.declaration_roster"&&row.unique_known_capacity_bytes>0));
 let mut twice=crate::heap_census::HeapCensus::new("analysis-twice");twice.retained_frontend_owners(Some(semantic),None,None);twice.retained_frontend_owners(Some(semantic),None,None);let twice=twice.finish();assert_eq!(once.unique_known_capacity_bytes,twice.unique_known_capacity_bytes);assert_eq!(once.unique_file_backed_bytes,twice.unique_file_backed_bytes);
}

#[test]fn actual_query_attempt_variant_binding_moves_prior_metadata_and_keeps_failure_on_the_real_target(){
 let old=Arc::new(Mutex::new(QueryState{raw_snapshot:None,handlers_snapshot:None,snapshot:None,last_request_outcome:"published",publication_pair:Some("previous-owned-pair".to_owned())}));let target=Arc::new(Mutex::new(QueryState{raw_snapshot:None,handlers_snapshot:None,snapshot:None,last_request_outcome:"analyzed",publication_pair:None}));let pair=old.lock().unwrap().publication_pair.as_ref().unwrap().as_ptr();
 let mut attempt=QueryAttempt::new(Arc::clone(&old),true);assert!(old.lock().unwrap().publication_pair.is_none());attempt.bind_current_variant(Arc::clone(&target)).unwrap();{let previous=old.lock().unwrap();assert_eq!(previous.last_request_outcome,"published");assert_eq!(previous.publication_pair.as_ref().unwrap().as_ptr(),pair);}assert_eq!(target.lock().unwrap().last_request_outcome,"building");drop(attempt);assert_eq!(target.lock().unwrap().last_request_outcome,"failed");assert_eq!(old.lock().unwrap().last_request_outcome,"published");assert_eq!(old.lock().unwrap().publication_pair.as_deref(),Some("previous-owned-pair"));
}

#[test]fn actual_query_attempt_same_variant_keeps_cached_publication_metadata_on_the_original_state(){
 let state=Arc::new(Mutex::new(QueryState{raw_snapshot:None,handlers_snapshot:None,snapshot:None,last_request_outcome:"published",publication_pair:Some("prior-pair".to_owned())}));let mut attempt=QueryAttempt::new(Arc::clone(&state),true);attempt.bind_current_variant(Arc::clone(&state)).unwrap();assert!(Arc::ptr_eq(&attempt.state,&state));attempt.finish(Some("fresh-cached-pair".to_owned()));drop(attempt);let current=state.lock().unwrap();assert_eq!(current.last_request_outcome,"published");assert_eq!(current.publication_pair.as_deref(),Some("fresh-cached-pair"));assert!(current.snapshot.is_none());
}

#[test]fn actual_original_semantic_selection_issues_only_its_real_archive_child_and_fixed_manifest(){
 use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
 let(mut host,mut request,root)=fixture("/datum/semantic_selected\n/proc/probe()\n    return 1\n");
 request.policy_inputs.as_mut().unwrap().workspace_auxiliary=vec![Q::SemReads];run(&mut host,&request);
 current(&host,|snapshot|{let child=snapshot.workspace_semantic_inputs(Q::SemReads).unwrap();assert!(snapshot.policy_role==SnapshotPolicyRole::WorkspaceSemanticChild);assert!(snapshot.workspace_semantic_inputs(Q::UntrackedInputs).is_err());assert!(snapshot.workspace_generator_inputs(crate::GeneratorName::Reads).is_err());let archive=snapshot.body_archive.as_ref().unwrap();assert!(Arc::ptr_eq(archive,child.policy().archive()));let guard=snapshot.workspace_native_read().unwrap();let workspace=snapshot.native_workspace.as_ref().unwrap();let mut foreign=request.policy_inputs.clone().unwrap();foreign.workspace_auxiliary=vec![Q::Tracked];assert!(WorkspaceSemanticSelection::from_admitted(&foreign.admit().unwrap(),workspace).is_err());workspace.with_semantic_manifest(&guard,Q::SemReads,|bytes|{assert_eq!(bytes.unwrap(),std::fs::read(root.join("deepquarry.dme")).unwrap());Ok(())}).unwrap();assert!(workspace.with_keys_manifest(&guard,|_|Ok(())).is_err());});
 let mut report=request.clone();report.policy_inputs.as_mut().unwrap().workspace_auxiliary.clear();run(&mut host,&report);current(&host,|snapshot|{assert!(snapshot.native_policy_inputs.is_none());assert!(snapshot.workspace_semantic_inputs(Q::SemReads).is_err());});
 let mut native=request;native.policy_inputs.as_mut().unwrap().analysis_context=None;native.project=root.join("unreadable-should-not-be-opened.dme");let error=crate::request_runner::run_build_with_host(native,&mut host).unwrap_err();assert_eq!(error.downcast_ref::<std::io::Error>().unwrap().kind(),std::io::ErrorKind::InvalidInput);
}

#[test]fn actual_original_semantic_fixed_manifest_negative_is_distinct_from_an_alternate_real_project(){
 use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
 let(mut host,mut request,root)=fixture("/datum/alternate_semantic\n");std::fs::rename(root.join("deepquarry.dme"),root.join("main.dme")).unwrap();request.project=root.join("main.dme");request.policy_inputs.as_mut().unwrap().workspace_auxiliary=vec![Q::UntrackedInputs];run(&mut host,&request);
 current(&host,|snapshot|{snapshot.workspace_semantic_inputs(Q::UntrackedInputs).unwrap();let guard=snapshot.workspace_native_read().unwrap();snapshot.native_workspace.as_ref().unwrap().with_semantic_manifest(&guard,Q::UntrackedInputs,|bytes|{assert!(bytes.is_none());Ok(())}).unwrap();});
}

#[test]fn actual_original_all_four_semantic_roles_survive_canonical_capture_and_keep_exact_selection(){
 use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;let(mut host,mut request,_)=fixture("/datum/all_semantic_roles\n");request.policy_inputs.as_mut().unwrap().workspace_auxiliary=vec![Q::TrackedTests,Q::Tracked,Q::UntrackedInputs,Q::SemReads];run(&mut host,&request);current(&host,|snapshot|{for question in[Q::SemReads,Q::UntrackedInputs,Q::Tracked,Q::TrackedTests]{snapshot.workspace_semantic_inputs(question).unwrap();}let selection=snapshot.workspace_semantic_selection.unwrap();assert_eq!(&selection.names[..4],&[Some(Q::SemReads),Some(Q::UntrackedInputs),Some(Q::Tracked),Some(Q::TrackedTests)]);assert!(selection.names[4..].iter().all(Option::is_none),"no unselected semantic question is retained");assert!(snapshot.workspace_generator_selection.is_none());});assert_eq!(host.query_db().db().stats(dm_query::Kind(4)).computed,0);
}

#[test]fn actual_original_semantic_reads_and_untracked_use_same_current_db_and_warm_real_body_inputs(){
 use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;let(mut host,mut request,_)=fixture("/datum/semantic_quiet\n/proc/probe()\n    return 1\n");request.policy_inputs.as_mut().unwrap().workspace_auxiliary=vec![Q::SemReads,Q::UntrackedInputs];run(&mut host,&request);let db=Arc::clone(host.query_db());
 let observe=|snapshot:&SourceSnapshot|{for question in[Q::SemReads,Q::UntrackedInputs]{snapshot.with_original_semantic_policy(question,|data|{assert!(data.sites().is_empty());assert!(data.allow_used().is_empty());Ok(())}).unwrap();}assert!(snapshot.with_original_semantic_policy(Q::Tracked,|_| -> std::io::Result<()> {panic!("wrong-role consumer")}).is_err());};current(&host,observe);let before=db.db().stats(dm_query::Kind(4)).computed;run(&mut host,&request);current(&host,observe);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);assert!(Arc::ptr_eq(&db,host.query_db()));
}

#[test]fn actual_original_semantic_alternate_project_uses_proven_fixed_manifest_absence_without_fabricating_source(){
 use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;let(mut host,mut request,root)=fixture("/datum/semantic_alternate_quiet\n");std::fs::rename(root.join("deepquarry.dme"),root.join("main.dme")).unwrap();request.project=root.join("main.dme");request.policy_inputs.as_mut().unwrap().workspace_auxiliary=vec![Q::SemReads,Q::UntrackedInputs];run(&mut host,&request);current(&host,|snapshot|{for question in[Q::SemReads,Q::UntrackedInputs]{snapshot.with_original_semantic_policy(question,|data|{assert!(data.sites().is_empty());Ok(())}).unwrap();}});assert!(!root.join("deepquarry.dme").exists());
}

#[path="../../../../analyze/fixtures/native-sem-reads/fixture.rs"]mod original_semantic_reads_fixture;
#[path="../../../../analyze/fixtures/native-untracked-inputs/fixture.rs"]mod original_semantic_untracked_fixture;
#[test]fn actual_original_semantic_complete_shared_cases_emit_ordered_sites_and_allow_for_independent_old_comparison(){
 use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;for(family,question,cases)in[("sem/reads",Q::SemReads,original_semantic_reads_fixture::CASES),("untracked_inputs",Q::UntrackedInputs,original_semantic_untracked_fixture::CASES)]{for case in cases{let files=if question==Q::SemReads{original_semantic_reads_fixture::files(case).unwrap()}else{original_semantic_untracked_fixture::files(case).unwrap()};let(mut host,mut request,root)=fixture("");std::fs::remove_file(root.join("code/probe.dm")).unwrap();for(relative,bytes)in files{let path=root.join(relative);std::fs::create_dir_all(path.parent().unwrap()).unwrap();std::fs::write(path,bytes).unwrap();}request.policy_inputs.as_mut().unwrap().workspace_auxiliary=vec![question];run(&mut host,&request);let record=current(&host,|snapshot|snapshot.with_original_semantic_policy(question,|data|Ok(serde_json::json!({"family":family,"case":case,"sites":data.sites(),"allow_used":data.allow_used()}))).unwrap());let before=host.query_db().db().stats(dm_query::Kind(4)).computed;run(&mut host,&request);current(&host,|snapshot|snapshot.with_original_semantic_policy(question,|data|{assert_eq!(serde_json::json!({"family":family,"case":case,"sites":data.sites(),"allow_used":data.allow_used()}),record);Ok(())}).unwrap());assert_eq!(host.query_db().db().stats(dm_query::Kind(4)).computed,before);println!("ORIGINAL_CONTEXT_SEMANTIC_NATIVE={record}");}}
}

#[path="../../../../analyze/fixtures/native-semantic-report/fixture.rs"]mod public_semantic_fixture;
fn public_semantic_case(family:&str,case:&str)->(crate::runner_host::BuildHost,BuildRequest,PathBuf){
 use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;let(mut host,mut request,root)=fixture("");std::fs::remove_file(root.join("code/probe.dm")).unwrap();for(relative,bytes)in public_semantic_fixture::files(family,case).unwrap(){let path=root.join(relative);std::fs::create_dir_all(path.parent().unwrap()).unwrap();std::fs::write(path,bytes).unwrap();}request.policy_inputs.as_mut().unwrap().workspace_auxiliary=vec![if family=="sem/reads"{Q::SemReads}else{Q::UntrackedInputs}];run(&mut host,&request);(host,request,root)
}
#[test]fn actual_public_semantic_hard_reports_deliver_all_ten_cases_and_validate_exact_shape(){
 use crate::daemon::{query::{self,QueryRequest,SourceQuery},analyze::{AnalyzeRequest,finish_captured_for_test}};
 for family in ["sem/reads","untracked_inputs"]{for case in public_semantic_fixture::cases(family).unwrap(){let(mut host,build,root)=public_semantic_case(family,case);let request=AnalyzeRequest{build:build.clone(),lints:vec![family.into()],raw:true,changed:None,scopes_root:None,baseline_mode:None,ci:false};let state=host.query_state();let held=state.lock().unwrap();let snapshot=held.snapshot.as_ref().unwrap();let before=host.query_db().db().stats(dm_query::Kind(4)).computed;let mut cursor=None;let mut pages=Vec::new();
 loop{let q=QueryRequest{analysis_context:Some(AnalysisContext::OriginalChecker0290),timeout_seconds:Some(60),project:build.project.clone(),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",snapshot.tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:Vec::new(),source_queries:vec![SourceQuery::NativeWorkspaceSemanticReportPage{root:root.clone(),configuration:root.join("tools/ci/lint_scopes.toml"),lints:request.lints.clone(),cursor:cursor.clone(),limit:2}]};let reply=query::evaluate_snapshot(&q,&snapshot.tree,&held).unwrap();query::validate_workspace_report_delivery(&reply,&q.source_queries).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();assert_eq!(row["row"],"source_native_workspace_semantic_report");for item in row["items"].as_array().unwrap(){assert!(item.get("source_text").is_none());assert!(matches!(item["kind"].as_str(),Some("hard_site"|"allow")));}cursor=serde_json::from_value(row["next_cursor"].clone()).unwrap();pages.push((reply,q));if cursor.is_none(){break}}
 let(_,bytes)=finish_captured_for_test(&request,&pages,false).unwrap();let report:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert!(report["text"].as_str().unwrap().contains("ratchet lints")||report["text"].as_str().unwrap().contains("Ratchet lints"));let after=host.query_db().db().stats(dm_query::Kind(4)).computed;assert!(after>=before);let warm=query::evaluate_snapshot(&pages[0].1,&snapshot.tree,&held).unwrap();assert_eq!(warm.jsonl,pages[0].0.jsonl);assert_eq!(host.query_db().db().stats(dm_query::Kind(4)).computed,after);
 let mut forged=pages[0].0.clone();let mut row:serde_json::Value=serde_json::from_str(forged.jsonl.trim()).unwrap();row["row"]="source_native_workspace_keys_report".into();forged.jsonl=format!("{row}\n");assert!(query::validate_workspace_report_delivery(&forged,&pages[0].1.source_queries).is_err());drop(held);run(&mut host,&build);
 }}
}
#[test]fn actual_public_complete_scope_preflight_rejects_unselected_missing_lists_before_kind12_scan(){
 use crate::daemon::query::{self,QueryRequest,SourceQuery};
 let(mut host,mut request,root)=fixture("/proc/preflight_probe()\n    return 1\n");use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;request.policy_inputs.as_mut().unwrap().workspace_auxiliary=vec![Q::SemReads];
 // This is a valid selected policy scope but deliberately omits required lists
 // of UNSELECTED registry policies. It must fail before any policy job.
 std::fs::write(root.join("tools/ci/lint_scopes.toml"),"[lint.\"sem/reads\"]\n").unwrap();run(&mut host,&request);
 let state=host.query_state();let held=state.lock().unwrap();let snapshot=held.snapshot.as_ref().unwrap();let before=host.query_db().db().stats(dm_query::Kind(12)).computed;let query=QueryRequest{analysis_context:Some(AnalysisContext::OriginalChecker0290),timeout_seconds:Some(60),project:request.project.clone(),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",snapshot.tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:Vec::new(),source_queries:vec![SourceQuery::NativeWorkspaceSemanticReportPage{root:root.clone(),configuration:root.join("tools/ci/lint_scopes.toml"),lints:vec!["sem/reads".into()],cursor:None,limit:128}]};
 // Run against the same published snapshot using its actual host state.
 for question in [
 crate::daemon::query::SourceQuery::NativeWorkspaceRawReportPage{root:root.clone(),configuration:root.join("tools/ci/lint_scopes.toml"),lints:vec!["scheduler".into()],cursor:None,limit:128},
 crate::daemon::query::SourceQuery::NativeWorkspaceHygieneReportPage{root:root.clone(),configuration:root.join("tools/ci/lint_scopes.toml"),lints:vec!["sys/hygiene".into()],cursor:None,limit:128},
 crate::daemon::query::SourceQuery::NativeWorkspaceSysReportPage{root:root.clone(),configuration:root.join("tools/ci/lint_scopes.toml"),lints:vec!["sys/tables".into()],cursor:None,limit:128},
 crate::daemon::query::SourceQuery::NativeWorkspaceKeysReportPage{root:root.clone(),configuration:root.join("tools/ci/lint_scopes.toml"),lints:vec!["sem/keys".into()],cursor:None,limit:128},
 crate::daemon::query::SourceQuery::NativeWorkspaceCheckGrepReportPage{root:root.clone(),configuration:root.join("tools/ci/lint_scopes.toml"),lints:vec!["check_grep".into()],cursor:None,limit:128},
 crate::daemon::query::SourceQuery::NativeWorkspaceCheckGrepBaselineReportPage{root:root.clone(),configuration:root.join("tools/ci/lint_scopes.toml"),lints:vec!["check_grep".into()],cursor:None,limit:128},
 query.source_queries[0].clone()]{let mut selected=query.clone();selected.source_queries=vec![question];let actual=query::evaluate_snapshot(&selected,&snapshot.tree,&held).unwrap_err();assert_eq!(actual.kind(),std::io::ErrorKind::InvalidInput);assert!(actual.to_string().contains("lint_scopes.toml:")&&actual.to_string().contains("is missing"),"{actual}");assert_eq!(host.query_db().db().stats(dm_query::Kind(12)).computed,before);}
}


#[test]fn actual_public_semantic_rejects_alternate_subject_and_foreign_cursor_preserving_first_writer_io(){
 use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
 let(mut host,request,root)=public_semantic_case("sem/reads","basic");
 current(&host,|snapshot|{
  let names=vec!["sem/reads".to_owned()];let configuration=root.join("tools/ci/lint_scopes.toml");let foreign:crate::query_db::WorkspaceCursor=serde_json::from_value(serde_json::json!({"aggregate_id":"f".repeat(32),"offset":0})).unwrap();let mut out=Vec::new();assert!(snapshot.write_native_workspace_semantic_report_page(&root,&configuration,&names,Some(&foreign),128,&snapshot.tree,&mut out).is_err());assert!(out.is_empty());
  let cancel=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(cancel.clone(),std::time::Instant::now()+std::time::Duration::from_secs(60));struct Fail<'a>(&'a crate::daemon::control::Cancellation);impl std::io::Write for Fail<'_>{fn write(&mut self,_:&[u8])->std::io::Result<usize>{self.0.cancel();Err(std::io::Error::from_raw_os_error(1450))}fn flush(&mut self)->std::io::Result<()>{Ok(())}}
  assert_eq!(snapshot.write_native_workspace_semantic_report_page(&root,&configuration,&names,None,128,&snapshot.tree,&mut Fail(&cancel)).unwrap_err().raw_os_error(),Some(1450));assert_eq!(snapshot.write_native_workspace_semantic_report_page(&root,&configuration,&names,None,128,&snapshot.tree,&mut out).unwrap_err().kind(),std::io::ErrorKind::Interrupted);assert!(out.is_empty());drop(binding);snapshot.write_native_workspace_semantic_report_page(&root,&configuration,&names,None,128,&snapshot.tree,&mut out).unwrap();assert!(!out.is_empty());
 });
 // The private role can truthfully prepare an alternate real project; that
 // does not establish the old public fixed-manifest subject.
 let(mut alternate,mut other,path)=fixture("/datum/alternate_public_subject\n");std::fs::rename(path.join("deepquarry.dme"),path.join("main.dme")).unwrap();other.project=path.join("main.dme");other.policy_inputs.as_mut().unwrap().workspace_auxiliary=vec![Q::SemReads];run(&mut alternate,&other);current(&alternate,|snapshot|{snapshot.workspace_semantic_inputs(Q::SemReads).unwrap();let mut out=Vec::new();assert_eq!(snapshot.write_native_workspace_semantic_report_page(&path,&path.join("tools/ci/lint_scopes.toml"),&["sem/reads".into()],None,128,&snapshot.tree,&mut out).unwrap_err().kind(),std::io::ErrorKind::Unsupported);assert!(out.is_empty());});run(&mut host,&request);
}

#[test]fn actual_public_original_subject_binds_entry_lease_across_windows_prefixes_and_rejects_included_fixed_manifest(){
 use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
 let(mut host,mut request,root)=fixture("/datum/fixed_subject_probe\n");let root=dm_preprocess::regions::filesystem_comparison_key(&root);request.project=root.join("deepquarry.dme");{let intent=request.policy_inputs.as_mut().unwrap();intent.workspace_auxiliary=vec![Q::SemReads];let workspace=intent.workspace.as_mut().unwrap();workspace.root=root.clone();workspace.recursive_roots=vec![root.join("code"),root.join("maps")];workspace.configuration=root.join("tools/ci/lint_scopes.toml");}run(&mut host,&request);let queries=Arc::clone(host.query_db());let before=queries.db().stats(dm_query::Kind(4)).computed;
 current(&host,|snapshot|{let mapping=snapshot.source_mapping.as_ref().unwrap();let(_,entry,path,lease)=mapping.original_root_acquisition_using(&mut||Ok::<(),&'static str>(())).unwrap();assert_eq!(entry.file_name(),Some(std::ffi::OsStr::new("deepquarry.dme")));assert!(lease.source_text().as_str().contains("#include"));assert_eq!(dm_preprocess::regions::relative_filesystem_path(path,&root).as_deref(),Some(std::path::Path::new("deepquarry.dme")));#[cfg(windows)]assert!(path.strip_prefix(&root).is_err(),"actual canonical project has a distinct verbatim drive prefix");snapshot.require_original_fixed_report_subject(&snapshot.tree).unwrap();});assert_eq!(queries.db().stats(dm_query::Kind(4)).computed,before);
 // A genuine alternate main can include the real fixed manifest and acquire
 // its original bytes. That file is still a CHILD, never the actual entry.
 std::fs::write(root.join("main.dme"),"#include \"deepquarry.dme\"\n").unwrap();let mut alternate=request.clone();alternate.project=root.join("main.dme");run(&mut host,&alternate);current(&host,|snapshot|{snapshot.workspace_semantic_inputs(Q::SemReads).unwrap();let mapping=snapshot.source_mapping.as_ref().unwrap();assert!(mapping.source_acquisitions().any(|(path,lease)|path.file_name()==Some(std::ffi::OsStr::new("deepquarry.dme"))&&lease.is_some()));let(_,entry,_,_)=mapping.original_root_acquisition_using(&mut||Ok::<(),&'static str>(())).unwrap();assert_eq!(entry.file_name(),Some(std::ffi::OsStr::new("main.dme")));assert_eq!(snapshot.require_original_fixed_report_subject(&snapshot.tree).unwrap_err().kind(),std::io::ErrorKind::Unsupported);});run(&mut host,&request);current(&host,|snapshot|snapshot.require_original_fixed_report_subject(&snapshot.tree).unwrap());assert_eq!(queries.db().stats(dm_query::Kind(4)).computed,before);
}

#[path="../../../../analyze/fixtures/native-tracked/fixture.rs"]mod original_tracked_fixture;
#[test]fn actual_original_tracked_complete_shared_cases_use_real_schema_named_arguments_and_two_domains(){
 use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;for case in original_tracked_fixture::CASES{let(mut host,mut request,root)=fixture("");std::fs::remove_file(root.join("code/probe.dm")).unwrap();for(relative,bytes)in original_tracked_fixture::files(case).unwrap(){let file=root.join(relative);std::fs::create_dir_all(file.parent().unwrap()).unwrap();std::fs::write(file,bytes).unwrap();}request.policy_inputs.as_mut().unwrap().workspace_auxiliary=vec![Q::Tracked,Q::TrackedTests];run(&mut host,&request);let db=Arc::clone(host.query_db());let records=current(&host,|snapshot|{assert!(snapshot.native_workspace.as_ref().unwrap().semantic_order_question().is_none(),"tracked-only selection must not borrow an unrequested manifest role");let mut records=Vec::new();for tests in[false,true]{snapshot.with_original_tracked_policy(tests,|data|{assert_eq!(data.sites().len(),data.source_text().len());records.push(serde_json::json!({"case":case,"family":data.metadata().name,"sites":data.sites(),"notes":data.notes(),"allow_used":data.allow_used(),"source_text":data.source_text()}));Ok(())}).unwrap();}records});let before=db.db().stats(dm_query::Kind(4)).computed;run(&mut host,&request);current(&host,|snapshot|{for(tests,record)in[false,true].into_iter().zip(&records){snapshot.with_original_tracked_policy(tests,|data|{assert_eq!(serde_json::json!({"case":case,"family":data.metadata().name,"sites":data.sites(),"notes":data.notes(),"allow_used":data.allow_used(),"source_text":data.source_text()}),*record);Ok(())}).unwrap();}});assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);assert!(Arc::ptr_eq(&db,host.query_db()));for record in records{println!("ORIGINAL_CONTEXT_TRACKED_NATIVE={record}");}}
}
#[test]fn actual_original_tracked_exact_selected_role_first_writer_io_and_unwind_keep_same_owner_for_retry(){
 use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;let(mut host,mut request,root)=fixture("#define TRACKED(T,V)
/datum/tracked_current
    var/charge
/datum/tracked_current/proc/write()
    charge = 1
TRACKED(/datum/tracked_current, charge)
");request.policy_inputs.as_mut().unwrap().workspace_auxiliary=vec![Q::Tracked];run(&mut host,&request);let db=Arc::clone(host.query_db());current(&host,|snapshot|{let mut called=false;assert!(snapshot.with_original_tracked_policy(true,|_|{called=true;Ok(())}).is_err());assert!(!called);let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(60));assert_eq!(snapshot.with_original_tracked_policy(false,|_|{token.cancel();Err::<(),_>(std::io::Error::from_raw_os_error(1450))}).unwrap_err().raw_os_error(),Some(1450));drop(binding);let panic=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||snapshot.with_original_tracked_policy(false,|_|->std::io::Result<()>{panic!("actual Original tracked output unwind")})));assert!(panic.is_err());snapshot.with_original_tracked_policy(false,|data|{assert_eq!(data.sites().len(),1);Ok(())}).unwrap();});let before=db.db().stats(dm_query::Kind(4)).computed;run(&mut host,&request);current(&host,|snapshot|snapshot.with_original_tracked_policy(false,|data|{assert_eq!(data.sites().len(),1);Ok(())}).unwrap());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);assert!(root.join("deepquarry.dme").is_file());
}

#[path="../../../../analyze/fixtures/native-decl-workspace/fixture.rs"]mod decl_workspace_fixture;
fn decl_workspace_host(case:&str,extra:usize)->(crate::runner_host::BuildHost,BuildRequest,PathBuf){
 let(mut host,mut request,root)=fixture("/datum/placeholder\n");for(relative,bytes)in decl_workspace_fixture::files(case){let path=root.join(relative);std::fs::create_dir_all(path.parent().unwrap()).unwrap();std::fs::write(path,bytes).unwrap();}for index in 0..extra{std::fs::write(root.join(format!("code/extra_{index:04}.dm")),format!("// actual uncompiled original file {index}\n")).unwrap();}let intent=request.policy_inputs.as_mut().unwrap();intent.analysis_context=Some(AnalysisContext::OriginalAnalyze0290);intent.workspace_auxiliary=vec![crate::policy_request::WorkspaceAuxiliaryQuestion::Decl];run(&mut host,&request);(host,request,root)
}
#[test]fn actual_original_decl_complete_hidden_code_over_130_files_preserves_entire_sites_and_allow_trace(){
 for case in decl_workspace_fixture::CASES{let(host,_request,_root)=decl_workspace_host(case,130);current(&host,|snapshot|snapshot.with_original_decl_policy(|data,_,_|{assert_eq!(data.metadata().name,"decl");assert_eq!(data.sites().len(),data.source_text().len());if *case=="basic"{assert_eq!(data.sites().iter().map(|row|(row.rule.as_str(),row.line)).collect::<Vec<_>>(),[("init_scheduling",6),("destroy_qdel_owned",8),("init_scheduling",14)]);}if *case=="allowed"{assert_eq!(data.allow_used().len(),1);assert_eq!(data.sites().len(),2);}if *case=="exempt"{assert!(data.sites().is_empty());}if *case=="hidden"{assert!(data.sites().iter().any(|row|row.rel=="code/.hidden/probe.dm"));}println!("NATIVE_DECL_WORKSPACE_FULL={}",serde_json::json!({"case":case,"sites":data.sites(),"notes":data.notes(),"allow_used":data.allow_used(),"source_text":data.source_text()}));Ok(())}).unwrap());}
}
#[test]fn actual_original_decl_same_query_owner_warm_output_io_unwind_and_foreign_role_refusal(){
 let(mut host,request,_root)=decl_workspace_host("basic",130);let queries=Arc::clone(host.query_db());let first=current(&host,|snapshot|snapshot.with_original_decl_policy(|data,_,_|Ok(serde_json::json!({"sites":data.sites(),"allow_used":data.allow_used(),"source_text":data.source_text()}))).unwrap());let before=queries.db().stats(dm_query::Kind(4)).computed;
 current(&host,|snapshot|{let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(60));let error=snapshot.with_original_decl_policy(|_,_,_|{token.cancel();Err::<(),_>(std::io::Error::from_raw_os_error(1450))}).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));drop(binding);let unwind=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||snapshot.with_original_decl_policy(|_,_,_|->std::io::Result<()>{panic!("actual complete declaration output unwind")})));assert!(unwind.is_err());let guard=snapshot.workspace_native_read().unwrap();let workspace=snapshot.native_workspace.as_ref().unwrap();let child=snapshot.workspace_semantic_inputs(crate::policy_request::WorkspaceAuxiliaryQuestion::Decl).unwrap();let mut called=false;let error=queries.with_original_workspace_decl_guard_limit(workspace,&guard,child,Some(1),|_,_,_|{called=true;Ok(())}).unwrap_err();assert_eq!(error.kind(),std::io::ErrorKind::OutOfMemory);assert!(!called);snapshot.with_original_decl_policy(|data,_,_|{assert_eq!(data.sites().len(),3);Ok(())}).unwrap();});run(&mut host,&request);current(&host,|snapshot|snapshot.with_original_decl_policy(|data,_,_|{assert_eq!(serde_json::json!({"sites":data.sites(),"allow_used":data.allow_used(),"source_text":data.source_text()}),first);Ok(())}).unwrap());assert_eq!(queries.db().stats(dm_query::Kind(4)).computed,before);
 let mut wrong=request;wrong.policy_inputs.as_mut().unwrap().workspace_auxiliary=vec![crate::policy_request::WorkspaceAuxiliaryQuestion::Tracked];run(&mut host,&wrong);current(&host,|snapshot|{let mut called=false;assert!(snapshot.with_original_decl_policy(|_,_,_|{called=true;Ok(())}).is_err());assert!(!called);});
}

#[path="../../../../analyze/fixtures/native-decl-report/fixture.rs"]mod decl_report_fixture;
#[test]fn actual_original_decl_public_pages_are_complete_pinned_sites_with_real_text_and_exclusive_metadata(){
 use crate::daemon::query::{self,QueryRequest,SourceQuery};let(mut host,mut request,root)=decl_workspace_host("allowed",130);for(relative,bytes)in decl_report_fixture::files("allowed"){let path=root.join(relative);std::fs::create_dir_all(path.parent().unwrap()).unwrap();std::fs::write(path,bytes).unwrap();}run(&mut host,&request);let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let mut query=QueryRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),timeout_seconds:Some(60),project:request.project.clone(),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",snapshot.tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:Vec::new(),source_queries:vec![SourceQuery::NativeWorkspaceSemanticReportPage{root:root.clone(),configuration:root.join("tools/ci/lint_scopes.toml"),lints:vec!["decl".into()],cursor:None,limit:1}]};let mut total=0;let mut aggregate:Option<String>=None;loop{let reply=query::evaluate_snapshot(&query,&snapshot.tree,&state).unwrap();query::validate_effect_batch_for_test(&query,&reply).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();assert_eq!(row["row"],"source_native_workspace_semantic_report");assert_eq!(row["lint_whitelist"],serde_json::json!(["decl"]));assert_eq!(row["full_policy_parity"],false);if let Some(old)=&aggregate{assert_eq!(row["aggregate_id"].as_str(),Some(old.as_str()))}else{aggregate=Some(row["aggregate_id"].as_str().unwrap().to_owned())}for item in row["items"].as_array().unwrap(){assert_ne!(item["kind"],"hard_site");if item["kind"]=="site"{assert!(item["source_text"].is_string());}}total+=row["count"].as_u64().unwrap();if row["next_cursor"].is_null(){assert_eq!(total,row["total_items"].as_u64().unwrap());break}let cursor=serde_json::from_value(row["next_cursor"].clone()).unwrap();if let SourceQuery::NativeWorkspaceSemanticReportPage{cursor:next,..}=&mut query.source_queries[0]{*next=Some(cursor)}}assert_eq!(total,3);let mut wrong=query;wrong.source_queries=vec![SourceQuery::NativeWorkspaceSemanticReportPage{root:root.clone(),configuration:root.join("tools/ci/lint_scopes.toml"),lints:vec!["decl".into(),"sem/reads".into()],cursor:None,limit:1}];assert!(query::evaluate_snapshot(&wrong,&snapshot.tree,&state).is_err());
}

#[path="../../../../analyze/fixtures/native-init-workspace/fixture.rs"]mod init_workspace_fixture;
fn init_workspace_host(case:&str)->(crate::runner_host::BuildHost,BuildRequest,PathBuf){let(mut host,mut request,root)=fixture("/datum/placeholder\n");for(relative,bytes)in init_workspace_fixture::files(case){let path=root.join(relative);std::fs::create_dir_all(path.parent().unwrap()).unwrap();std::fs::write(path,bytes).unwrap();}for index in 0..130{std::fs::write(root.join(format!("code/extra_{index:04}.dm")),format!("// actual original init source {index}\n")).unwrap();}let intent=request.policy_inputs.as_mut().unwrap();intent.analysis_context=Some(AnalysisContext::OriginalAnalyze0290);intent.workspace_auxiliary=vec![crate::policy_request::WorkspaceAuxiliaryQuestion::Init];run(&mut host,&request);(host,request,root)}
#[test]fn actual_original_init_complete_hidden_code_maps_over_130_files_preserves_whole_sites_identities_and_allow(){for case in init_workspace_fixture::CASES{let(host,_,_)=init_workspace_host(case);current(&host,|snapshot|snapshot.with_original_init_policy(|data,_,_|{assert_eq!(data.metadata().name,"init");assert_eq!(data.sites().len(),data.source_text().len());if *case=="basic"{assert!(data.sites().iter().any(|site|site.rule=="world_reads"));assert!(data.sites().iter().any(|site|site.rule=="init_lines"&&!site.ident.is_empty()));assert!(data.sites().iter().any(|site|site.rule=="turf_on_materialize"));assert!(data.sites().iter().any(|site|site.rule=="table_init_overrides"));}if *case=="allowed"{assert!(!data.allow_used().is_empty());}if *case=="exempt"{assert!(data.sites().iter().all(|site|site.rule=="table_init_overrides"));assert!(!data.sites().is_empty(),"table pass includes original exempt sources");}if *case=="table_order"{assert!(!data.sites().iter().any(|site|site.rule=="table_init_overrides"),"actual NTFS files-before-directories makes final deep override FALSE");}if *case=="hidden"{assert!(data.sites().iter().any(|site|site.rel=="maps/.hidden/probe.dm"));assert!(data.allow_used().iter().any(|used|used.rel=="maps/.hidden/probe.dm"));}if *case=="roots"{assert!(!data.sites().iter().any(|site|site.rule=="world_reads"||site.rule=="init_lines"));}println!("NATIVE_INIT_WORKSPACE_FULL={}",serde_json::json!({"case":case,"sites":data.sites(),"notes":data.notes(),"allow_used":data.allow_used(),"source_text":data.source_text()}));Ok(())}).unwrap());}}
#[test]fn actual_original_init_current_owner_quota_io_unwind_then_warm_without_body_demand(){let(mut host,request,_)=init_workspace_host("allowed");let queries=Arc::clone(host.query_db());let first=current(&host,|snapshot|snapshot.with_original_init_policy(|data,_,_|Ok(serde_json::json!({"sites":data.sites(),"allow_used":data.allow_used(),"source_text":data.source_text()}))).unwrap());let before=queries.db().stats(dm_query::Kind(4)).computed;current(&host,|snapshot|{let guard=snapshot.workspace_native_read().unwrap();let workspace=snapshot.native_workspace.as_ref().unwrap();let child=snapshot.workspace_semantic_inputs(crate::policy_request::WorkspaceAuxiliaryQuestion::Init).unwrap();let foreign=crate::query_db::QueryDb::default();let mut called=false;assert!(foreign.with_original_workspace_init_guard(workspace,&guard,child,|_,_,_|{called=true;Ok(())}).is_err());assert!(!called);assert_eq!(queries.with_original_workspace_init_guard_limit(workspace,&guard,child,Some(1),|_,_,_|{called=true;Ok(())}).unwrap_err().kind(),std::io::ErrorKind::OutOfMemory);assert!(!called);let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(60));assert_eq!(snapshot.with_original_init_policy(|_,_,_|{token.cancel();Err::<(),_>(std::io::Error::from_raw_os_error(1450))}).unwrap_err().raw_os_error(),Some(1450));drop(binding);assert!(std::panic::catch_unwind(std::panic::AssertUnwindSafe(||snapshot.with_original_init_policy(|_,_,_|->std::io::Result<()>{panic!("actual init output unwind")}))).is_err());snapshot.with_original_init_policy(|data,_,_|{assert_eq!(serde_json::json!({"sites":data.sites(),"allow_used":data.allow_used(),"source_text":data.source_text()}),first);Ok(())}).unwrap();});run(&mut host,&request);current(&host,|snapshot|snapshot.with_original_init_policy(|data,_,_|{assert_eq!(serde_json::json!({"sites":data.sites(),"allow_used":data.allow_used(),"source_text":data.source_text()}),first);Ok(())}).unwrap());assert_eq!(queries.db().stats(dm_query::Kind(4)).computed,before);}

#[path="../../../../analyze/fixtures/native-init-report/fixture.rs"]mod init_report_fixture;
#[test]fn actual_original_init_public_pages_are_complete_pinned_sites_with_real_text_and_exclusive_metadata(){
 use crate::daemon::query::{self,QueryRequest,SourceQuery};let(mut host,mut request,root)=init_workspace_host("allowed");for(relative,bytes)in init_report_fixture::files("allowed"){let path=root.join(relative);std::fs::create_dir_all(path.parent().unwrap()).unwrap();std::fs::write(path,bytes).unwrap();}run(&mut host,&request);let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let mut query=QueryRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),timeout_seconds:Some(60),project:request.project.clone(),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",snapshot.tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:Vec::new(),source_queries:vec![SourceQuery::NativeWorkspaceSemanticReportPage{root:root.clone(),configuration:root.join("tools/ci/lint_scopes.toml"),lints:vec!["init".into()],cursor:None,limit:1}]};let mut total=0;let mut aggregate:Option<String>=None;loop{let reply=query::evaluate_snapshot(&query,&snapshot.tree,&state).unwrap();query::validate_effect_batch_for_test(&query,&reply).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();assert_eq!(row["row"],"source_native_workspace_semantic_report");assert_eq!(row["lint_whitelist"],serde_json::json!(["init"]));assert_eq!(row["full_policy_parity"],false);if let Some(old)=&aggregate{assert_eq!(row["aggregate_id"].as_str(),Some(old.as_str()))}else{aggregate=Some(row["aggregate_id"].as_str().unwrap().to_owned())}for item in row["items"].as_array().unwrap(){assert_ne!(item["kind"],"hard_site");if item["kind"]=="site"{assert!(item["source_text"].is_string());}}total+=row["count"].as_u64().unwrap();if row["next_cursor"].is_null(){assert_eq!(total,row["total_items"].as_u64().unwrap());break}let cursor=serde_json::from_value(row["next_cursor"].clone()).unwrap();if let SourceQuery::NativeWorkspaceSemanticReportPage{cursor:next,..}=&mut query.source_queries[0]{*next=Some(cursor)}}assert!(total>0);let mut wrong=query;wrong.source_queries=vec![SourceQuery::NativeWorkspaceSemanticReportPage{root:root.clone(),configuration:root.join("tools/ci/lint_scopes.toml"),lints:vec!["init".into(),"sem/reads".into()],cursor:None,limit:1}];assert!(query::evaluate_snapshot(&wrong,&snapshot.tree,&state).is_err());
}

#[path="../../../../analyze/fixtures/native-base-vars-workspace/fixture.rs"]mod base_vars_workspace_fixture;
fn base_vars_workspace_host(case:&str)->(crate::runner_host::BuildHost,BuildRequest,PathBuf){let(mut host,mut request,root)=fixture("/datum/placeholder\n");for(relative,bytes)in base_vars_workspace_fixture::files(case){let path=root.join(relative);std::fs::create_dir_all(path.parent().unwrap()).unwrap();std::fs::write(path,bytes).unwrap();}for index in 0..130{std::fs::write(root.join(format!("code/extra_{index:04}.dm")),format!("// actual full base-vars source {index}\n")).unwrap();}let intent=request.policy_inputs.as_mut().unwrap();intent.analysis_context=Some(AnalysisContext::OriginalAnalyze0290);intent.workspace_auxiliary=vec![crate::policy_request::WorkspaceAuxiliaryQuestion::BaseVars];run(&mut host,&request);(host,request,root)}
#[test]fn actual_original_base_vars_complete_hidden_code_and_noncode_records_preserve_whole_ordered_report(){for case in base_vars_workspace_fixture::CASES{let(host,_,_)=base_vars_workspace_host(case);current(&host,|snapshot|snapshot.with_original_base_vars_policy(|data,_,_|{assert_eq!(data.metadata().name,"base_vars");assert_eq!(data.sites().len(),data.source_text().len());assert_eq!(data.notes().len(),1);assert!(data.sites().iter().any(|site|site.rule=="records_data_only"&&site.rel=="maps/record.dm"),"record methods are original authored non-CODE questions");assert!(data.allow_used().iter().all(|used|used.rel!="maps/record.dm"),"records never ask ALLOW");if *case=="basic"{assert!(data.sites().iter().any(|site|site.rule=="base_var"&&site.ident=="/atom::bv_plain"));assert!(data.sites().iter().any(|site|site.rule=="base_var"&&!site.msg.is_empty()));assert!(data.sites().iter().any(|site|site.rule=="list_init"));}if *case=="allowed"{assert!(!data.sites().iter().any(|site|site.ident=="/atom::bv_plain"));assert!(!data.allow_used().is_empty());}if *case=="homes"||*case=="hidden"{assert!(!data.sites().iter().any(|site|site.ident=="/atom::bv_plain"));}if *case=="hidden"{assert!(data.allow_used().iter().all(|used|!used.rel.contains(".hidden")));}if *case=="hot"{assert!(data.sites().iter().any(|site|site.rule=="hot_home"&&site.rel=="tools/ci/lint_scopes.toml"));}if *case=="record_noncode"{assert!(data.allow_used().iter().any(|used|used.rel=="code/uncompiled.dm"));}println!("NATIVE_BASE_VARS_WORKSPACE_FULL={}",serde_json::json!({"case":case,"sites":data.sites(),"notes":data.notes(),"allow_used":data.allow_used(),"source_text":data.source_text()}));Ok(())}).unwrap());}}
#[test]fn actual_original_base_vars_current_owner_quota_io_unwind_then_warm_without_body_demand(){let(mut host,request,_)=base_vars_workspace_host("allowed");let queries=Arc::clone(host.query_db());let first=current(&host,|snapshot|snapshot.with_original_base_vars_policy(|data,_,_|Ok(serde_json::json!({"sites":data.sites(),"allow_used":data.allow_used(),"source_text":data.source_text()}))).unwrap());let before=queries.db().stats(dm_query::Kind(4)).computed;current(&host,|snapshot|{let guard=snapshot.workspace_native_read().unwrap();let workspace=snapshot.native_workspace.as_ref().unwrap();let child=snapshot.workspace_semantic_inputs(crate::policy_request::WorkspaceAuxiliaryQuestion::BaseVars).unwrap();let foreign=crate::query_db::QueryDb::default();let mut called=false;assert!(foreign.with_original_workspace_base_vars_guard(workspace,&guard,child,|_,_,_|{called=true;Ok(())}).is_err());assert!(!called);assert_eq!(queries.with_original_workspace_base_vars_guard_limit(workspace,&guard,child,Some(1),|_,_,_|{called=true;Ok(())}).unwrap_err().kind(),std::io::ErrorKind::OutOfMemory);assert!(!called);let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(60));assert_eq!(snapshot.with_original_base_vars_policy(|_,_,_|{token.cancel();Err::<(),_>(std::io::Error::from_raw_os_error(1450))}).unwrap_err().raw_os_error(),Some(1450));drop(binding);assert!(std::panic::catch_unwind(std::panic::AssertUnwindSafe(||snapshot.with_original_base_vars_policy(|_,_,_|->std::io::Result<()>{panic!("actual base_vars output unwind")}))).is_err());snapshot.with_original_base_vars_policy(|data,_,_|{assert_eq!(serde_json::json!({"sites":data.sites(),"allow_used":data.allow_used(),"source_text":data.source_text()}),first);Ok(())}).unwrap();});run(&mut host,&request);current(&host,|snapshot|snapshot.with_original_base_vars_policy(|data,_,_|{assert_eq!(serde_json::json!({"sites":data.sites(),"allow_used":data.allow_used(),"source_text":data.source_text()}),first);Ok(())}).unwrap());assert_eq!(queries.db().stats(dm_query::Kind(4)).computed,before);}

#[path="../../../../analyze/fixtures/native-base-vars-report/fixture.rs"]mod base_vars_report_fixture;
#[test]fn actual_original_base_vars_public_pages_are_complete_pinned_sites_with_real_text_and_exclusive_metadata(){
 use crate::daemon::query::{self,QueryRequest,SourceQuery};let(mut host,mut request,root)=base_vars_workspace_host("allowed");for(relative,bytes)in base_vars_report_fixture::files("allowed"){let path=root.join(relative);std::fs::create_dir_all(path.parent().unwrap()).unwrap();std::fs::write(path,bytes).unwrap();}run(&mut host,&request);let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let mut query=QueryRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),timeout_seconds:Some(60),project:request.project.clone(),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",snapshot.tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:Vec::new(),source_queries:vec![SourceQuery::NativeWorkspaceSemanticReportPage{root:root.clone(),configuration:root.join("tools/ci/lint_scopes.toml"),lints:vec!["base_vars".into()],cursor:None,limit:1}]};let mut note_count=0;let mut total=0;let mut aggregate:Option<String>=None;loop{let reply=query::evaluate_snapshot(&query,&snapshot.tree,&state).unwrap();query::validate_effect_batch_for_test(&query,&reply).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();assert_eq!(row["row"],"source_native_workspace_semantic_report");assert_eq!(row["lint_whitelist"],serde_json::json!(["base_vars"]));assert_eq!(row["full_policy_parity"],false);if let Some(old)=&aggregate{assert_eq!(row["aggregate_id"].as_str(),Some(old.as_str()))}else{aggregate=Some(row["aggregate_id"].as_str().unwrap().to_owned())}for item in row["items"].as_array().unwrap(){if item["kind"]=="note"{note_count+=1;assert!(item["text"].as_str().unwrap().starts_with("base_vars: "));}assert_ne!(item["kind"],"hard_site");if item["kind"]=="site"{assert!(item["source_text"].is_string());}}total+=row["count"].as_u64().unwrap();if row["next_cursor"].is_null(){assert_eq!(total,row["total_items"].as_u64().unwrap());break}let cursor=serde_json::from_value(row["next_cursor"].clone()).unwrap();if let SourceQuery::NativeWorkspaceSemanticReportPage{cursor:next,..}=&mut query.source_queries[0]{*next=Some(cursor)}}assert!(total>0);assert_eq!(note_count,1);let mut wrong=query;wrong.source_queries=vec![SourceQuery::NativeWorkspaceSemanticReportPage{root:root.clone(),configuration:root.join("tools/ci/lint_scopes.toml"),lints:vec!["base_vars".into(),"sem/reads".into()],cursor:None,limit:1}];assert!(query::evaluate_snapshot(&wrong,&snapshot.tree,&state).is_err());
}

#[path="../../../../analyze/fixtures/native-requirement-bool-workspace/fixture.rs"]mod requirement_workspace_fixture;
fn requirement_workspace_host(case:&str)->(crate::runner_host::BuildHost,BuildRequest,PathBuf){let(mut host,mut request,root)=fixture("/datum/placeholder\n");for(relative,bytes)in requirement_workspace_fixture::files(case){let path=root.join(relative);std::fs::create_dir_all(path.parent().unwrap()).unwrap();std::fs::write(path,bytes).unwrap();}for index in 0..130{std::fs::write(root.join(format!("code/extra_{index:04}.dm")),format!("// actual full selected requirement source {index}\n")).unwrap();}let intent=request.policy_inputs.as_mut().unwrap();intent.analysis_context=Some(AnalysisContext::OriginalAnalyze0290);intent.workspace_auxiliary=vec![crate::policy_request::WorkspaceAuxiliaryQuestion::RequirementBool];run(&mut host,&request);(host,request,root)}
#[test]fn actual_original_requirement_bool_full_code_over_130_files_keeps_complete_typed_raw_union_and_rule_order(){for case in requirement_workspace_fixture::CASES{let(host,_,_)=requirement_workspace_host(case);current(&host,|snapshot|snapshot.with_original_requirement_bool_policy(|data,_,_|{assert_eq!(data.metadata().name,"requirement_bool");assert_eq!(data.sites().len(),data.source_text().len());assert!(data.notes().is_empty());assert!(data.allow_used().is_empty());if *case=="exempt"{assert!(data.sites().is_empty());}else{assert!(data.sites().iter().any(|site|site.rule=="boolean_callback"));}if *case=="macro"{assert!(data.sites().iter().any(|site|site.rule=="boolean_callback"&&site.line==5),"the actual typed macro call supplements raw lexical evidence");}if *case=="retired"{let first=data.sites().iter().position(|site|site.rule=="legacy_macro").unwrap();assert!(data.sites()[..first].iter().all(|site|site.rule=="boolean_callback"));assert!(data.sites()[first..].iter().all(|site|site.rule=="legacy_macro"));}assert!(data.sites().iter().all(|site|!site.rel.contains(".hidden")));println!("NATIVE_REQUIREMENT_BOOL_FULL={}",serde_json::json!({"case":case,"sites":data.sites(),"notes":data.notes(),"allow_used":data.allow_used(),"source_text":data.source_text()}));Ok(())}).unwrap());}}
#[test]fn actual_original_requirement_bool_current_owner_quota_io_unwind_then_warm_without_body_demand(){let(mut host,request,_)=requirement_workspace_host("basic");let queries=Arc::clone(host.query_db());let first=current(&host,|snapshot|snapshot.with_original_requirement_bool_policy(|data,_,_|Ok(serde_json::json!({"sites":data.sites(),"allow_used":data.allow_used(),"source_text":data.source_text()}))).unwrap());let before=queries.db().stats(dm_query::Kind(4)).computed;current(&host,|snapshot|{let guard=snapshot.workspace_native_read().unwrap();let workspace=snapshot.native_workspace.as_ref().unwrap();let child=snapshot.workspace_semantic_inputs(crate::policy_request::WorkspaceAuxiliaryQuestion::RequirementBool).unwrap();let foreign=crate::query_db::QueryDb::default();let mut called=false;assert!(foreign.with_original_workspace_requirement_bool_guard(workspace,&guard,child,|_,_,_|{called=true;Ok(())}).is_err());assert!(!called);assert_eq!(queries.with_original_workspace_requirement_bool_guard_limit(workspace,&guard,child,Some(1),|_,_,_|{called=true;Ok(())}).unwrap_err().kind(),std::io::ErrorKind::OutOfMemory);assert!(!called);let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(60));assert_eq!(snapshot.with_original_requirement_bool_policy(|_,_,_|{token.cancel();Err::<(),_>(std::io::Error::from_raw_os_error(1450))}).unwrap_err().raw_os_error(),Some(1450));drop(binding);assert!(std::panic::catch_unwind(std::panic::AssertUnwindSafe(||snapshot.with_original_requirement_bool_policy(|_,_,_|->std::io::Result<()>{panic!("actual requirement_bool output unwind")}))).is_err());snapshot.with_original_requirement_bool_policy(|data,_,_|{assert_eq!(serde_json::json!({"sites":data.sites(),"allow_used":data.allow_used(),"source_text":data.source_text()}),first);Ok(())}).unwrap();});run(&mut host,&request);current(&host,|snapshot|snapshot.with_original_requirement_bool_policy(|data,_,_|{assert_eq!(serde_json::json!({"sites":data.sites(),"allow_used":data.allow_used(),"source_text":data.source_text()}),first);Ok(())}).unwrap());assert_eq!(queries.db().stats(dm_query::Kind(4)).computed,before);}

#[path="../../../../analyze/fixtures/native-requirement-bool-report/fixture.rs"]mod requirement_bool_report_fixture;
#[test]fn actual_original_requirement_bool_public_pages_are_complete_pinned_sites_with_real_text_and_exclusive_metadata(){
 use crate::daemon::query::{self,QueryRequest,SourceQuery};let(mut host,mut request,root)=requirement_workspace_host("allowed");for(relative,bytes)in requirement_bool_report_fixture::files("allowed"){let path=root.join(relative);std::fs::create_dir_all(path.parent().unwrap()).unwrap();std::fs::write(path,bytes).unwrap();}run(&mut host,&request);let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let mut query=QueryRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),timeout_seconds:Some(60),project:request.project.clone(),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",snapshot.tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:Vec::new(),source_queries:vec![SourceQuery::NativeWorkspaceSemanticReportPage{root:root.clone(),configuration:root.join("tools/ci/lint_scopes.toml"),lints:vec!["requirement_bool".into()],cursor:None,limit:1}]};let mut total=0;let mut aggregate:Option<String>=None;loop{let reply=query::evaluate_snapshot(&query,&snapshot.tree,&state).unwrap();query::validate_effect_batch_for_test(&query,&reply).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();assert_eq!(row["row"],"source_native_workspace_semantic_report");assert_eq!(row["lint_whitelist"],serde_json::json!(["requirement_bool"]));assert_eq!(row["full_policy_parity"],false);if let Some(old)=&aggregate{assert_eq!(row["aggregate_id"].as_str(),Some(old.as_str()))}else{aggregate=Some(row["aggregate_id"].as_str().unwrap().to_owned())}for item in row["items"].as_array().unwrap(){assert_ne!(item["kind"],"hard_site");if item["kind"]=="site"{assert!(item["source_text"].is_string());}}total+=row["count"].as_u64().unwrap();if row["next_cursor"].is_null(){assert_eq!(total,row["total_items"].as_u64().unwrap());break}let cursor=serde_json::from_value(row["next_cursor"].clone()).unwrap();if let SourceQuery::NativeWorkspaceSemanticReportPage{cursor:next,..}=&mut query.source_queries[0]{*next=Some(cursor)}}assert!(total>0);let mut wrong=query;wrong.source_queries=vec![SourceQuery::NativeWorkspaceSemanticReportPage{root:root.clone(),configuration:root.join("tools/ci/lint_scopes.toml"),lints:vec!["requirement_bool".into(),"sem/reads".into()],cursor:None,limit:1}];assert!(query::evaluate_snapshot(&wrong,&snapshot.tree,&state).is_err());
}

#[path="runner_query_player_link_tests.rs"]mod player_link_complete;

#[path="runner_query_untyped_member_tests.rs"]mod untyped_member_complete;

#[path="runner_query_weak_raw_read_tests.rs"]mod weak_raw_read_complete;

#[path="runner_query_rel_write_undeclared_tests.rs"]mod rel_write_undeclared_complete;

#[path="runner_query_untyped_tests.rs"]mod untyped_complete;

#[path="runner_query_stored_refs_tests.rs"]mod stored_refs_complete;


/// Genuine checker-policy request over the SAME normal Original host pipeline.
/// Workspace capture and explicitly captured named-policy scope are distinct;
/// do not fabricate a revision or mutate a published snapshot to cross roles.
pub(super) fn checker_fixture(source:&str)->(crate::runner_host::BuildHost,BuildRequest,PathBuf){
 let(host,mut request,root)=fixture(source);let intent=request.policy_inputs.as_mut().expect("actual original request intent");
 intent.workspace=None;
 intent.files.push(crate::policy_request::PolicyInputFile{path:root.join("SpacemanDMM.toml"),role:crate::policy_request::PolicyInputRole::Configuration,required:false});
 (host,request,root)
}
#[test]fn current_checker_selected_consumer_preserves_workspace_refusal_and_uses_actual_optional_config_capture(){
 let source="/datum/receiver\n/proc/probe(datum/receiver/argument)\n    return argument.field\n";
 let(mut workspace,request,root)=fixture(source);run(&mut workspace,&request);current(&workspace,|snapshot|{let mut called=0;let actual=snapshot.visit_current_variable_diagnostics(0,&root.join("deepquarry.dme"),None,&snapshot.tree,|_|{called+=1;Ok(())}).unwrap_err();assert!(actual.to_string().contains("named policy needs an explicitly bound captured-policy revision"));assert_eq!(called,0);});
 let(mut checker,request,root)=checker_fixture(source);run(&mut checker,&request);current(&checker,|snapshot|{let capture=snapshot.named_policy_capture(&snapshot.tree).unwrap();assert!(snapshot.policy_revision.is_some());assert_eq!(snapshot.policy_revision,capture.policy_revision());assert!(capture.configuration_bytes(&root.join("SpacemanDMM.toml")).unwrap().is_none(),"actual recorded optional absence, not an invented empty config");let mut called=0;let actual=snapshot.visit_current_variable_diagnostics(0,&root.join("deepquarry.dme"),None,&snapshot.tree,|row|{called+=1;assert_eq!(row.diagnostic.message,"undefined field: \"field\" on /datum/receiver");Ok(())}).unwrap();assert_eq!(actual,dm_analysis::checks_undefined_variable::CurrentUndefinedDisposition::Evaluated);assert_eq!(called,1);});
}

#[path="runner_query_setter_publishes_tests.rs"]mod setter_publishes;

#[path="runner_query_sys_reactive_tests.rs"]mod sys_reactive;

#[path="runner_query_lifeforms_tests.rs"]mod lifeforms;

#[test]
fn actual_semantic_wire_pages_for_lifeforms_and_sys_reactive_pass_client_validation() {
    use crate::daemon::query::{self, QueryRequest, SourceQuery};

    for (name, rule, kind, fixture) in [
        ("lifeforms", "ctor_dead_arg", "hard_site", lifeforms::lifeforms_host as fn() -> (crate::runner_host::BuildHost, BuildRequest, PathBuf)),
        ("sys/dx_reactive", "dx_untracked_read", "site", sys_reactive::sys_host),
    ] {
        let (host, request, root) = fixture();
        let state = host.query_state();
        let state = state.lock().unwrap();
        let snapshot = state.snapshot.as_ref().unwrap();
        let question = QueryRequest {
            analysis_context: Some(AnalysisContext::OriginalAnalyze0290),
            timeout_seconds: Some(60),
            project: request.project,
            defines: Default::default(),
            engine_template: None,
            bootstrap_catalog: false,
            expected_revision: Some(format!("{:032x}", snapshot.tree.identity())),
            expected_source_revision: Some(format!("{:032x}", snapshot.source_revision)),
            expected_policy_revision: Some(format!("{:032x}", snapshot.policy_revision.unwrap())),
            queries: Vec::new(),
            source_queries: vec![SourceQuery::NativeWorkspaceSemanticReportPage {
                configuration: root.join("tools/ci/lint_scopes.toml"),
                root,
                lints: vec![name.into()],
                cursor: None,
                limit: 128,
            }],
        };
        let reply = query::evaluate_snapshot(&question, &snapshot.tree, &state).unwrap();
        query::validate_workspace_report_delivery(&reply, &question.source_queries).unwrap();
        let mut row: serde_json::Value = serde_json::from_str(reply.jsonl.trim_end()).unwrap();
        assert!(row["items"].as_array().unwrap().iter().any(|item|
            item["kind"] == kind && item["site"]["rule"] == rule));
        // Preserve all real findings and pins, changing only the wire purpose.
        row["row"] = "source_native_workspace_sys_report".into();
        row["scope"] = "typed_discovery_complete_sys_family".into();
        row["admission"] = "complete_selected_sys_findings".into();
        let foreign = query::QueryReply { jsonl: format!("{row}\n"), ..reply };
        assert!(query::validate_workspace_report_delivery(&foreign, &question.source_queries).is_err());
    }
}

#[test]
fn original_map_edits_joined_capture_pins_maps_and_reuses_source_tree() {
    use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
    let (mut host, mut request, root) = fixture("/datum/probe\n    var/known\n");
    let intent = request.policy_inputs.as_mut().unwrap();
    intent.analysis_context = Some(AnalysisContext::OriginalAnalyze0290);
    intent.workspace_auxiliary = vec![Q::MapEdits];
    intent.workspace.as_mut().unwrap().recursive_roots = vec![root.join("code")];

    let inspect = |snapshot: &SourceSnapshot, expected: &[(&str, &str, usize)]| {
        let guard = snapshot.workspace_native_read().unwrap();
        let workspace = snapshot.native_workspace.as_ref().unwrap();
        let child = snapshot.workspace_semantic_inputs(Q::MapEdits).unwrap();
        assert!(workspace.matches_source(child.policy().mapping(), snapshot.source_revision));
        let mut rows = Vec::new();
        workspace.for_each_map_edit_file(&guard, |relative, map| {
            assert_eq!(relative, "maps/probe.dmm");
            rows.extend(map.edits().map(|(ty, var, line)| (ty.to_owned(), var.to_owned(), line)));
            Ok(())
        }).unwrap();
        assert_eq!(rows, expected.iter().map(|(ty, var, line)| (ty.to_string(), var.to_string(), *line)).collect::<Vec<_>>());
        (snapshot.source_revision, workspace.policy_revision(), Arc::clone(&snapshot.tree))
    };
    run(&mut host, &request);
    let empty = current(&host, |snapshot| inspect(snapshot, &[]));
    std::fs::write(root.join("maps/probe.dmm"), b"/datum/probe{known = 1; lost = 2}\r\n").unwrap();
    run(&mut host, &request);
    let first = current(&host, |snapshot| inspect(snapshot, &[("/datum/probe", "known", 1), ("/datum/probe", "lost", 1)]));
    assert_eq!(first.0, empty.0);
    assert_ne!(first.1, empty.1);
    assert!(Arc::ptr_eq(&first.2, &empty.2));
    std::fs::write(root.join("maps/probe.dmm"), b"/datum/probe{known = 1; next = 3}\r\n").unwrap();
    run(&mut host, &request);
    let next = current(&host, |snapshot| inspect(snapshot, &[("/datum/probe", "known", 1), ("/datum/probe", "next", 1)]));
    assert_eq!(next.0, first.0);
    assert_ne!(next.1, first.1);
    assert!(Arc::ptr_eq(&next.2, &first.2));
}
