//! Actual same-host analysis purpose, original owners and variant isolation.
use super::*;
use crate::{policy_request::{AnalysisContext,PolicyInputRequest,WorkspacePolicyRequest},request::{BuildRequest,Command,BuildOutcome}};
fn fixture(source:&str)->(crate::runner_host::BuildHost,BuildRequest,PathBuf){
 let root=crate::test_scratch::dir("original-analysis-context");std::fs::create_dir(root.join("code")).unwrap();std::fs::create_dir(root.join("maps")).unwrap();std::fs::create_dir_all(root.join("tools/ci")).unwrap();
 std::fs::write(root.join("deepquarry.dme"),b"#ifdef __MAIN__\n/datum/root_main\n#endif\n#if defined(__MAIN__)\n#error MAIN must not be a default object macro\n#endif\n#include \"code/probe.dm\"\n").unwrap();
 std::fs::write(root.join("code/probe.dm"),source).unwrap();std::fs::write(root.join("tools/ci/lint_scopes.toml"),b"").unwrap();
 let args=vec!["prepare-query".to_owned(),root.join("deepquarry.dme").to_string_lossy().into_owned()];let Command::Build(request)=crate::cli::parse(&args).unwrap()else{panic!("actual PrepareQuery parser changed")};let mut request=*request;
 request.no_cache=true;request.exact_inputs=true;request.progress_enabled=false;request.workers=1;request.cache_root=Some(root.join("cache"));
 let mut intent=PolicyInputRequest::default();intent.analysis_context=Some(AnalysisContext::OriginalChecker0290);intent.workspace=Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("maps")],configuration:root.join("tools/ci/lint_scopes.toml")});request.policy_inputs=Some(intent);
 (crate::runner_host::BuildHost::default(),request,root)
}
fn run(host:&mut crate::runner_host::BuildHost,request:&BuildRequest){
 let result=crate::request_runner::run_build_with_host(request.clone(),host).unwrap();assert!(matches!(result,BuildOutcome::QueryPrepared{..}));
}
fn current<R>(host:&crate::runner_host::BuildHost,consume:impl FnOnce(&SourceSnapshot)->R)->R{
 let state=host.query_state();let guard=state.lock().unwrap();consume(guard.snapshot.as_ref().unwrap())
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
   assert_eq!(view.original_plan().final_macros.len(),104);assert_eq!(types.iter().filter(|(path,_)|path.starts_with("/datum/context_")).count(),108);
   let result=serde_json::json!({"schema":"analysis-default-context-observations-v1","default_macro_count":view.original_plan().final_macros.len(),"types":types,"tokens":observations::tokens(view.expanded_text())});println!("NATIVE_ANALYSIS_DEFAULT_CONTEXT={result}");
  }).unwrap().unwrap();
 });
}

#[test]fn actual_original_analysis_workspace_reports_bind_context_and_reject_ordinary_model_questions(){
 use crate::daemon::query::{self,QueryRequest,SourceQuery};
 let(mut host,request,root)=fixture("/proc/probe()\n    return 1\n");run(&mut host,&request);
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
 let old=Arc::new(Mutex::new(QueryState{snapshot:None,last_request_outcome:"published",publication_pair:Some("previous-owned-pair".to_owned())}));let target=Arc::new(Mutex::new(QueryState{snapshot:None,last_request_outcome:"analyzed",publication_pair:None}));let pair=old.lock().unwrap().publication_pair.as_ref().unwrap().as_ptr();
 let mut attempt=QueryAttempt::new(Arc::clone(&old),true);assert!(old.lock().unwrap().publication_pair.is_none());attempt.bind_current_variant(Arc::clone(&target)).unwrap();{let previous=old.lock().unwrap();assert_eq!(previous.last_request_outcome,"published");assert_eq!(previous.publication_pair.as_ref().unwrap().as_ptr(),pair);}assert_eq!(target.lock().unwrap().last_request_outcome,"building");drop(attempt);assert_eq!(target.lock().unwrap().last_request_outcome,"failed");assert_eq!(old.lock().unwrap().last_request_outcome,"published");assert_eq!(old.lock().unwrap().publication_pair.as_deref(),Some("previous-owned-pair"));
}

#[test]fn actual_query_attempt_same_variant_keeps_cached_publication_metadata_on_the_original_state(){
 let state=Arc::new(Mutex::new(QueryState{snapshot:None,last_request_outcome:"published",publication_pair:Some("prior-pair".to_owned())}));let mut attempt=QueryAttempt::new(Arc::clone(&state),true);attempt.bind_current_variant(Arc::clone(&state)).unwrap();assert!(Arc::ptr_eq(&attempt.state,&state));attempt.finish(Some("fresh-cached-pair".to_owned()));drop(attempt);let current=state.lock().unwrap();assert_eq!(current.last_request_outcome,"published");assert_eq!(current.publication_pair.as_deref(),Some("fresh-cached-pair"));assert!(current.snapshot.is_none());
}
