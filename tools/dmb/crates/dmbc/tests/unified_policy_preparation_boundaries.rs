//! Small IN-PROCESS public boundary target. No Cargo subprocess, daemon, game
//! world, GUI, alternative parser, invented model or private visibility changes.
//! Preparation/pin assertions are not claims that private report/cache tests ran.
#[path="../../../shared/test_scratch.rs"]mod test_scratch;
#[path="../../../../analyze/fixtures/report_configuration.rs"]mod report_configuration;
#[path="../../../../analyze/fixtures/native-ui-actions-workspace/fixture.rs"]mod ui_fixture;
use dmbc::{policy_request::{AnalysisContext,PolicyInputRequest,WorkspacePolicyRequest,WorkspaceAuxiliaryQuestion as Q},request::{BuildRequest,BuildOutcome,Command},runner_host::BuildHost};
use std::path::{Path,PathBuf};
fn put(root:&Path,relative:&str,bytes:impl AsRef<[u8]>){let path=root.join(relative);std::fs::create_dir_all(path.parent().unwrap()).unwrap();std::fs::write(path,bytes).unwrap();}
fn request(root:&Path,question:Q)->BuildRequest{
 let Command::Build(request)=dmbc::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()else{panic!("actual public PrepareQuery")};let mut request=*request;
 request.no_cache=true;request.exact_inputs=true;request.progress_enabled=false;request.workers=1;request.engine_template=None;request.bootstrap_catalog=false;request.cache_root=Some(root.join("cache"));request.timeout_seconds=Some(60);
 // run_build_with_host is the public local retained-host entry, not daemon IPC.
 // no_daemon stays false because that option means one-shot/nonretaining owner.
 let recursive_roots=match question{Q::DocSnippets=>vec![root.join("code"),root.join("doc/rewrite")],Q::UiActions=>vec![root.join("code"),root.join("tgui/packages/tgui/interfaces")],_=>vec![root.join("code")]};
 request.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:root.to_owned(),recursive_roots,configuration:root.join("tools/ci/lint_scopes.toml")}),workspace_auxiliary:vec![question],..Default::default()});request
}
#[derive(Debug,Eq,PartialEq)]struct RawPins{query:String,source:String,policy:String}
fn prepare_raw(host:&mut BuildHost,request:&BuildRequest)->RawPins{
 let had_declarations=host.declaration_retention_stats().is_some();let had_prepared=host.prepared_source_retention_census().is_some();let had_symbolic=host.symbolic_retention_stats().is_some();
 let outcome=dmbc::request_runner::run_build_with_host(request.clone(),host).unwrap();
 let BuildOutcome::RawQueryPrepared{query_revision,source_revision,policy_revision,retained:true}=outcome else{panic!("actual raw-only request produced {outcome:?}")};
 for value in [&query_revision,&source_revision,&policy_revision]{assert_eq!(value.len(),32);assert!(value.bytes().all(|byte|byte.is_ascii_hexdigit()));}
 // A previous semantic attempt may legitimately leave a reusable empty/cache
 // owner in the host. Assert that THIS raw request creates none of these,
 // while its RawQueryPrepared variant independently refuses a semantic result.
 if !had_declarations{assert!(host.declaration_retention_stats().is_none(),"raw preparation initialized a semantic declaration owner");}if !had_prepared{assert!(host.prepared_source_retention_census().is_none(),"raw preparation created a logical/prepared-source parser product");}if !had_symbolic{assert!(host.symbolic_retention_stats().is_none(),"raw preparation secretly lowered executable code");}
 RawPins{query:query_revision,source:source_revision,policy:policy_revision}
}
fn doc_root(label:&str)->PathBuf{
 let root=test_scratch::dir(label);put(&root,"code/a.dm",b"/proc/known()\n    return\n");put(&root,"doc/rewrite/a.md",b"```dm\nknown()\nmissing_doc()\n```\n");put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay(""));root
}
#[test]fn raw_doc_prepare_ignores_malformed_absent_and_directory_dme_without_a_frontend_or_publication(){
 for case in 0..3{let root=doc_root("public-raw-doc-no-model");match case{0=>put(&root,"deepquarry.dme",b"#include \"missing_compiled_file.dm\"\n"),1=>(),2=>std::fs::create_dir(root.join("deepquarry.dme")).unwrap(),_=>unreachable!()};let request=request(&root,Q::DocSnippets);let mut host=BuildHost::default();prepare_raw(&mut host,&request);assert!(!root.join("deepquarry.dmb").exists());assert!(!root.join("deepquarry.rsc").exists());}
}
#[test]fn raw_doc_public_source_and_configuration_pins_change_on_actual_edits_and_recover_after_configuration_failure(){
 let root=doc_root("public-raw-doc-pins");let request=request(&root,Q::DocSnippets);let mut host=BuildHost::default();let first=prepare_raw(&mut host,&request);let warm=prepare_raw(&mut host,&request);assert_eq!(warm.source,first.source);assert_eq!(warm.policy,first.policy);
 put(&root,"doc/rewrite/a.md",b"```dm\nchanged_missing_doc()\n```\n");let edited=prepare_raw(&mut host,&request);assert_ne!(edited.source,first.source);
 put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay("[lint.doc_snippets]\nexempt_files=[\"code/a.dm\"]\n"));let configured=prepare_raw(&mut host,&request);assert_ne!(configured.policy,edited.policy);
 // Original Scopes::load deliberately uses defaults for unreadable paths,
 // including a directory. Malformed readable TOML is the genuine fatal case.
 let config=root.join("tools/ci/lint_scopes.toml");std::fs::remove_file(&config).unwrap();std::fs::create_dir(&config).unwrap();let defaults=prepare_raw(&mut host,&request);assert_ne!(defaults.policy,configured.policy,"directory defaults must not reuse the old captured configuration");std::fs::remove_dir(&config).unwrap();put(&root,"tools/ci/lint_scopes.toml",b"[lint.doc_snippets");assert!(dmbc::request_runner::run_build_with_host(request.clone(),&mut host).is_err(),"malformed actual configuration must not publish an empty clean preparation");put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay(""));prepare_raw(&mut host,&request);
}
#[test]fn actual_exceptional_raw_bytes_change_the_public_source_revision_even_when_lossy_display_would_match(){
 let root=doc_root("public-exceptional-raw-pins");let request=request(&root,Q::DocSnippets);let mut host=BuildHost::default();put(&root,"code/a.dm",b"\xef\xbb\xbf/proc/known()\n    return\n// \x80\n");let first=prepare_raw(&mut host,&request);put(&root,"code/a.dm",b"\xef\xbb\xbf/proc/known()\n    return\n// \x91\n");let changed=prepare_raw(&mut host,&request);assert_ne!(changed.source,first.source,"actual original bytes, not decoded text equivalence, bind current source preparation");prepare_raw(&mut host,&request);
}
#[test]fn actual_doc_and_ownership_preparations_keep_distinct_purpose_pins_without_semantic_fabrication(){
 let root=doc_root("public-closed-raw-roles");for n in 0..140{put(&root,&format!("code/source_{n:03}.dm"),b"// actual whole-discovery raw input\n");}put(&root,"deepquarry.dme",b"malformed compiler manifest must never become this raw role\n");let mut host=BuildHost::default();let doc=request(&root,Q::DocSnippets);let ownership=request(&root,Q::Ownership);let a=prepare_raw(&mut host,&doc);let b=prepare_raw(&mut host,&ownership);assert_ne!(a.policy,b.policy,"closed roles are not interchangeable receipts");let again=prepare_raw(&mut host,&doc);assert_eq!(again.policy,a.policy);assert_eq!(again.source,a.source);
 let mut mixed=doc.clone();mixed.policy_inputs.as_mut().unwrap().workspace_auxiliary.push(Q::Ownership);let mixed=dmbc::request_runner::run_build_with_host(mixed,&mut host).unwrap();assert!(matches!(mixed,BuildOutcome::QueryPrepared{retained:true,..}),"a mixed request may prepare the actual graph, but cannot borrow either closed raw-only issuer: {mixed:?}");prepare_raw(&mut host,&doc);
}
#[test]fn ui_actual_public_prepare_remains_raw_and_reissues_after_helper_dispatcher_and_config_changes(){
 let root=test_scratch::dir("public-ui-raw-preparation");for(relative,text)in ui_fixture::files("basic"){put(&root,relative,text);}let request=request(&root,Q::UiActions);let mut host=BuildHost::default();let first=prepare_raw(&mut host,&request);
 put(&root,"code/helper.dm",b"/proc/helper(value)\n    return ui_text(value)\n");let added=prepare_raw(&mut host,&request);assert_ne!(added.source,first.source);std::fs::remove_file(root.join("code/helper.dm")).unwrap();let removed=prepare_raw(&mut host,&request);assert_ne!(removed.source,added.source);
 put(&root,"tools/ci/lint_scopes.toml",ui_fixture::configuration("[lint.ui_actions]\nexempt_files=[\"code/helper.dm\"]\n"));let config=prepare_raw(&mut host,&request);assert_ne!(config.policy,removed.policy);
 put(&root,"code/datums/capabilities/ui_actions.dm",b"invalid actual dispatcher\n");let bad=prepare_raw(&mut host,&request);assert_ne!(bad.source,config.source);put(&root,"code/datums/capabilities/ui_actions.dm",ui_fixture::DISPATCHER);prepare_raw(&mut host,&request);
 // This is actual issuer/preparation coverage. It does not call private C1/C2
 // reporting or claim helper dependency/Kind12/TTL regressions passed.
}
#[test]fn engine_no_selected_metadata_owner_cannot_be_reused_as_clean_when_selection_starts_requiring_a_model(){
 let root=doc_root("public-engine-conditional-owner");put(&root,"code/engine/probe.dm",b"/proc/entry()\n    ordinary_helper()\n");std::fs::create_dir(root.join("deepquarry.dme")).unwrap();put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay("[lint.engine_layering]\nexempt_files=[\"code/engine/probe.dm\"]\n"));let request=request(&root,Q::EngineLayering);let mut host=BuildHost::default();prepare_raw(&mut host,&request);
 put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay("[lint.engine_layering]\nexempt_files=[]\n"));assert!(dmbc::request_runner::run_build_with_host(request.clone(),&mut host).is_err(),"new selected engine code needs the actual manifest/model; old clean raw owner must not survive its unreadable DME");
 put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay("[lint.engine_layering]\nexempt_files=[\"code/engine/probe.dm\"]\n"));prepare_raw(&mut host,&request);
}
fn checker_request(root:&Path)->BuildRequest{
 let mut request=request(root,Q::DocSnippets);request.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalChecker0290),..Default::default()});request
}
#[test]fn actual_public_original_parameter_error_stays_source_exit_two_instead_of_native_fallback(){
 let root=test_scratch::dir("public-original-fatal-parameter");put(&root,"deepquarry.dme",include_bytes!("../../../fixtures/unified_checks/fatal_parameter_outcome_exact_bad_parameter/project.dme"));let mut host=BuildHost::default();let error=dmbc::request_runner::run_build_with_host(checker_request(&root),&mut host).unwrap_err();let failure=dmbc::request_failure::RequestFailure::from_error(error.as_ref());assert_eq!(failure.kind,dmbc::request_failure::FailureKind::Source,"actual public failure: {failure:?}");assert_eq!(failure.kind.exit_code(),2);assert!(failure.message.contains("got ')', expected one of: operator, literal, variable, proc call"),"{}",failure.message);assert!(!failure.message.contains("native unsupported"));
}
#[test]fn actual_public_original_class_comma_keeps_primary_source_refusal_and_recovers_on_fresh_valid_input(){
 let root=test_scratch::dir("public-original-fatal-class-comma");put(&root,"deepquarry.dme",include_bytes!("../../../fixtures/unified_checks/fatal_declaration_class_comma/project.dme"));let request=checker_request(&root);let mut host=BuildHost::default();let error=dmbc::request_runner::run_build_with_host(request.clone(),&mut host).unwrap_err();let failure=dmbc::request_failure::RequestFailure::from_error(error.as_ref());assert_eq!(failure.kind,dmbc::request_failure::FailureKind::Source,"actual public failure: {failure:?}");assert_eq!(failure.kind.exit_code(),2);assert!(failure.message.contains("got ','"),"{}",failure.message);put(&root,"deepquarry.dme",b"/datum/valid\n    var/value = 1\n");assert!(matches!(dmbc::request_runner::run_build_with_host(request,&mut host).unwrap(),BuildOutcome::QueryPrepared{retained:true,..}));
}
