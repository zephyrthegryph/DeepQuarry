//! Actual source-only acquisition/current owner; no parser/model success prerequisite.
use super::*;
use crate::{policy_request::{AnalysisContext,PolicyInputRequest,WorkspacePolicyRequest,WorkspaceAuxiliaryQuestion as Q},request::{BuildOutcome,BuildRequest,Command},input_snapshot::{RecordingInputs,SnapshotProvider,FileSystemInputs,Stamp,FolderListing,CapturedInputRead,PolicyDirectoryListing}};
use std::{sync::atomic::{AtomicUsize,Ordering},io,path::Path};
fn fixture(label:&str,manifest:usize)->(crate::runner_host::BuildHost,BuildRequest,PathBuf){
 let root=crate::test_scratch::dir(label);for folder in ["code","doc/rewrite","tools/ci","cache"]{std::fs::create_dir_all(root.join(folder)).unwrap();}std::fs::write(root.join("code/a.dm"),"/proc/known()\n    return\n").unwrap();std::fs::write(root.join("doc/rewrite/a.md"),"```dm\nknown()\nmissing_doc()\n```\n").unwrap();std::fs::write(root.join("tools/ci/lint_scopes.toml"),"").unwrap();match manifest{0=>std::fs::write(root.join("deepquarry.dme"),"#include \"missing_compiled_input.dm\"\n").unwrap(),1=>(),2=>std::fs::create_dir(root.join("deepquarry.dme")).unwrap(),_=>panic!("fixture manifest")}
 let args=vec!["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()];let Command::Build(request)=crate::cli::parse(&args).unwrap()else{panic!("real PrepareQuery")};let mut request=*request;request.no_cache=true;request.exact_inputs=true;request.progress_enabled=false;request.workers=1;request.engine_template=None;request.bootstrap_catalog=false;request.cache_root=Some(root.join("cache"));let mut intent=PolicyInputRequest::default();intent.analysis_context=Some(AnalysisContext::OriginalAnalyze0290);intent.workspace=Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("doc/rewrite")],configuration:root.join("tools/ci/lint_scopes.toml")});intent.workspace_auxiliary=vec![Q::DocSnippets];request.policy_inputs=Some(intent);(crate::runner_host::BuildHost::default(),request,root)
}
fn query(request:&BuildRequest,raw:&RawWorkspaceSnapshot)->crate::daemon::query::QueryRequest{let w=request.policy_inputs.as_ref().unwrap().workspace.as_ref().unwrap();crate::daemon::query::QueryRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),timeout_seconds:None,project:request.project.clone(),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",raw.revision())),expected_source_revision:Some(format!("{:032x}",raw.source_revision())),expected_policy_revision:Some(format!("{:032x}",raw.policy_revision())),queries:Vec::new(),source_queries:vec![crate::daemon::query::SourceQuery::NativeWorkspaceRawTreeReportPage{root:w.root.clone(),configuration:w.configuration.clone(),lints:vec!["doc_snippets".into()],cursor:None,limit:128}]}}
#[test]fn raw_doc_actual_prepare_and_report_ignore_bad_absent_or_non_file_dme_without_frontend(){
 for manifest in 0..3{let(mut host,request,_)=fixture("raw-doc-no-frontend",manifest);let db=Arc::clone(host.query_db());let bodies=db.db().stats(dm_query::Kind(4)).computed;let outcome=crate::request_runner::run_build_with_host(request.clone(),&mut host).unwrap();assert!(matches!(outcome,BuildOutcome::RawQueryPrepared{retained:true,..}));assert!(host.query_tree().is_none(),"source-only preparation must not invent a semantic tree");let state=host.query_state();let state=state.lock().unwrap();assert!(state.snapshot.is_none());let raw=state.raw_snapshot.as_ref().unwrap();assert!(Arc::ptr_eq(&raw.queries,&db));let request=query(&request,raw);let first=crate::daemon::query::evaluate_raw_snapshot(&request,raw,&state).unwrap();let warm=crate::daemon::query::evaluate_raw_snapshot(&request,raw,&state).unwrap();assert_eq!(first.jsonl,warm.jsonl);assert_eq!(first.snapshot_outcome,"raw_source_prepared");assert!(first.publication_pair.is_none());let row:serde_json::Value=serde_json::from_str(first.jsonl.trim()).unwrap();assert_eq!(row["scope"],"typed_discovery_complete_raw_tree");assert!(row["items"].as_array().unwrap().iter().any(|item|item["kind"]=="site"&&item["site"]["rule"]=="doc_unknown_name"));assert_eq!(db.db().stats(dm_query::Kind(4)).computed,bodies);}
}
#[test]fn raw_doc_current_frame_rejects_foreign_role_configuration_and_each_revision_and_invalidates(){
 let(mut host,request,root)=fixture("raw-doc-currentness",0);crate::request_runner::run_build_with_host(request.clone(),&mut host).unwrap();let old_request={let state=host.query_state();let state=state.lock().unwrap();let raw=state.raw_snapshot.as_ref().unwrap();let valid=query(&request,raw);for field in 0..9{let mut wrong=valid.clone();match field{0=>wrong.expected_revision=Some("0".repeat(32)),1=>wrong.expected_source_revision=Some("0".repeat(32)),2=>wrong.expected_policy_revision=Some("0".repeat(32)),3=>{let crate::daemon::query::SourceQuery::NativeWorkspaceRawTreeReportPage{configuration,..}=&mut wrong.source_queries[0]else{unreachable!()};*configuration=root.join("other.toml");},5=>wrong.engine_template=Some(root.join("alien-engine.dmb")),6=>wrong.bootstrap_catalog=true,7=>wrong.analysis_context=Some(AnalysisContext::OriginalChecker0290),8=>wrong.project=root.join("foreign.dme"),4=>{let crate::daemon::query::SourceQuery::NativeWorkspaceRawTreeReportPage{lints,..}=&mut wrong.source_queries[0]else{unreachable!()};*lints=vec!["ownership".into()];},_=>unreachable!()}assert!(crate::daemon::query::evaluate_raw_snapshot(&wrong,raw,&state).is_err());}let foreign=Arc::new(crate::query_db::QueryDb::default());assert!(workspace_native_guard::NativeReadGuard::raw_owned(&raw.capture,&raw.source,&foreign).is_err());let scope=workspace_native_guard::NativeReadGuard::raw_owned(&raw.capture,&raw.source,&raw.queries).unwrap();assert!(scope.query_receipt(&mut |_|Ok(())).is_err(),"raw source cannot acquire semantic graph authority");valid};
 std::fs::write(root.join("doc/rewrite/a.md"),"```dm\nnew_missing_doc()\n```\n").unwrap();crate::request_runner::run_build_with_host(request.clone(),&mut host).unwrap();let state=host.query_state();let state=state.lock().unwrap();let raw=state.raw_snapshot.as_ref().unwrap();assert!(crate::daemon::query::evaluate_raw_snapshot(&old_request,raw,&state).is_err());let current=query(&request,raw);assert_ne!(current.expected_source_revision,old_request.expected_source_revision);crate::daemon::query::evaluate_raw_snapshot(&current,raw,&state).unwrap();
}
struct Physical{manifest_attempts:AtomicUsize,fail:Option<PathBuf>}
impl Physical{fn check(&self,path:&Path)->io::Result<()>{if path.file_name().is_some_and(|name|name=="deepquarry.dme"){self.manifest_attempts.fetch_add(1,Ordering::SeqCst);return Err(io::Error::new(io::ErrorKind::PermissionDenied,"actual DME read is forbidden for this raw-only fixture"))}if self.fail.as_deref()==Some(path){return Err(io::Error::from_raw_os_error(1450))}Ok(())}}
impl SnapshotProvider for Physical{fn stamp(&self,path:&Path)->io::Result<Stamp>{self.check(path)?;FileSystemInputs.stamp(path)}fn read(&self,path:&Path)->io::Result<(Stamp,Vec<u8>)>{self.check(path)?;FileSystemInputs.read(path)}fn list(&self,path:&Path)->io::Result<FolderListing>{FileSystemInputs.list(path)}fn read_policy_bounded(&self,path:&Path,limit:usize)->io::Result<Option<CapturedInputRead>>{self.check(path)?;FileSystemInputs.read_policy_bounded(path,limit)}fn policy_directory(&self,path:&Path,follow:bool,limit:usize)->io::Result<Option<PolicyDirectoryListing>>{FileSystemInputs.policy_directory(path,follow,limit)}}
#[test]fn raw_doc_real_acquisition_never_reads_unreadable_dme_and_does_not_swallow_required_io(){
 let(_,request,root)=fixture("raw-doc-required-io",0);let intent=request.policy_inputs.clone().unwrap().admit().unwrap();let db=Arc::new(crate::query_db::QueryDb::default());let provider=Physical{manifest_attempts:AtomicUsize::new(0),fail:None};let input=RecordingInputs::new(&provider,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);let(capture,owner)=crate::runner_host::workspace_capture::capture_raw_only(&input,&intent,&db).unwrap();assert_eq!(provider.manifest_attempts.load(Ordering::SeqCst),0);let scope=workspace_native_guard::NativeReadGuard::raw_owned(&capture,&owner,&db).unwrap();assert!(capture.covers_raw_tree_policy(dq_analyze::captured_raw_tree_pages::Policy::DocSnippets,&mut |_|Ok(())).unwrap());let called=std::cell::Cell::new(false);let denied=db.with_workspace_raw_tree_limit(&capture,&scope,dq_analyze::captured_raw_tree_pages::Policy::DocSnippets,std::mem::size_of::<dq_analyze::captured_generator_budget::Budget>()+2*std::mem::size_of::<usize>(),|_,_,_|{called.set(true);Ok(())});assert!(matches!(denied,Err(dq_analyze::captured_reactive_reads::Failure::Operational(e))if e.kind()==io::ErrorKind::OutOfMemory));assert!(!called.get());db.with_workspace_raw_tree(&capture,&scope,dq_analyze::captured_raw_tree_pages::Policy::DocSnippets,|data,_,_|{assert!(!data.sites().is_empty());Ok(())}).unwrap();
 let failing=Physical{manifest_attempts:AtomicUsize::new(0),fail:Some(root.join("doc/rewrite/a.md"))};let input=RecordingInputs::new(&failing,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);let error=crate::runner_host::workspace_capture::capture_raw_only(&input,&intent,&db).err().unwrap();assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(failing.manifest_attempts.load(Ordering::SeqCst),0);
 let mut wrong=request.policy_inputs.unwrap();wrong.workspace_auxiliary.clear();let wrong=wrong.admit().unwrap();assert!(crate::runner_host::workspace_capture::capture_raw_only(&input,&wrong,&db).is_err());
}
#[test]fn raw_source_doc_and_ownership_are_distinct_closed_discovery_and_querydb_roles(){
 let(_,request,root)=fixture("raw-source-two-roles",0);let db=Arc::new(crate::query_db::QueryDb::default());let input=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);let doc=request.policy_inputs.clone().unwrap().admit().unwrap();let(doc_capture,doc_owner)=crate::runner_host::workspace_capture::capture_raw_only(&input,&doc,&db).unwrap();assert!(!doc_capture.covers_code_dm(&mut |_|Ok(())).unwrap());
 let mut ownership=request.policy_inputs.unwrap();ownership.workspace_auxiliary=vec![Q::Ownership];ownership.workspace.as_mut().unwrap().recursive_roots=vec![root.join("code")];let ownership=ownership.admit().unwrap();let(code_capture,code_owner)=crate::runner_host::workspace_capture::capture_raw_only(&input,&ownership,&db).unwrap();assert!(code_capture.covers_code_dm(&mut |_|Ok(())).unwrap());assert!(!code_capture.covers_raw_tree_policy(dq_analyze::captured_raw_tree_pages::Policy::DocSnippets,&mut |_|Ok(())).unwrap());assert!(workspace_native_guard::NativeReadGuard::raw_owned(&code_capture,&doc_owner,&db).is_err());assert!(workspace_native_guard::NativeReadGuard::raw_owned(&doc_capture,&code_owner,&db).is_err());let wrong_env=RecordingInputs::new(FileSystemInputs,0);assert!(crate::runner_host::workspace_capture::capture_raw_only(&wrong_env,&doc,&db).is_err());assert!(!Q::Ownership.is_semantic());
}

#[test]fn raw_doc_large_actual_source_is_input_funded_and_warm_reissue_preserves_the_same_owner(){
 let(mut host,request,root)=fixture("raw-doc-real-large-source",0);
 let mut large=String::from("/proc/large_known(var/list/args = list(1, list(2, 3)))\n    return\n");
 let target=1_550_277usize;let line="// representative generated rows do not request a semantic model\n";
 while large.len()+line.len()<=target{large.push_str(line)}large.extend(std::iter::repeat(' ').take(target-large.len()));
 assert_eq!(large.len(),target);std::fs::write(root.join("code/large.dm"),large).unwrap();std::fs::write(root.join("doc/rewrite/a.md"),"```dm\nlarge_known()\nmissing_doc()\n```\n").unwrap();
 let db=Arc::clone(host.query_db());let before=db.db().stats(dm_query::Kind(4)).computed;
 crate::request_runner::run_build_with_host(request.clone(),&mut host).unwrap();
 let(old_capture,old_owner,old_lease)={let state=host.query_state();let state=state.lock().unwrap();let raw=state.raw_snapshot.as_ref().unwrap();assert!(raw.capture.retained_charge().unwrap()<target,"actual source payload must not be disguised as 64MiB extra metadata");let lease=raw.capture.raw_input_files().find(|lease|lease.source_text().len()==target).unwrap().clone();let scope=workspace_native_guard::NativeReadGuard::raw_owned(&raw.capture,&raw.source,&raw.queries).unwrap();let(page,_)=raw.capture.code_page(&scope,0,128,65_536).unwrap();let file=page.iter().find(|file|file.path==root.join("code/large.dm")).unwrap();assert_eq!(file.text.as_ref().unwrap().len(),target);assert_eq!(file.charge,0,"only actual already-funded SourceText owners receive input credit");let answer=crate::daemon::query::evaluate_raw_snapshot(&query(&request,raw),raw,&state).unwrap();let page:serde_json::Value=serde_json::from_str(answer.jsonl.trim()).unwrap();assert!(page["items"].as_array().unwrap().iter().filter(|item|item["kind"]=="site").all(|item|!item.to_string().contains("large_known")),"known header cannot become a refusal");(Arc::clone(&raw.capture),Arc::clone(&raw.source),lease)};
 crate::request_runner::run_build_with_host(request.clone(),&mut host).unwrap();
 {let state=host.query_state();let state=state.lock().unwrap();let raw=state.raw_snapshot.as_ref().unwrap();let current=raw.capture.raw_input_files().find(|lease|lease.source_text().len()==target).unwrap();assert!(current.source_text().same_view(old_lease.source_text()),"new actual bounded read may reissue the exact same immutable input owner");assert!(!current.same_binding(&old_lease),"each current acquisition still has a new private read receipt");assert!(current.same_original_acquisition(&old_lease));assert!(old_capture.matches_raw_source(&old_owner,old_owner.revision()));assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);}
 // A real byte change requires a new backing, even with the old frame/lease held.
 let mut changed=std::fs::read(root.join("code/large.dm")).unwrap();changed[0]=b' ';std::fs::write(root.join("code/large.dm"),changed).unwrap();crate::request_runner::run_build_with_host(request,&mut host).unwrap();let state=host.query_state();let state=state.lock().unwrap();let raw=state.raw_snapshot.as_ref().unwrap();let current=raw.capture.raw_input_files().find(|lease|lease.source_text().len()==target).unwrap();assert!(!current.source_text().same_view(old_lease.source_text()));assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);
}
#[test]fn raw_actual_exceptional_acquisition_keeps_original_bytes_and_fails_before_decode_on_quota_or_io(){
 let root=crate::test_scratch::dir("raw-actual-codec-original");let path=root.join("exceptional.dm");let bytes=[0xef,0xbb,0xbf,b'/',b'/',0x80,b'\r',b'\n'];std::fs::write(&path,bytes).unwrap();
 let first=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);let called=std::cell::Cell::new(0);let old=first.read_raw_source(&path,4096,None,|capacity,exceptional,needs_decode|{assert!(needs_decode);called.set(called.get()+1);assert!(capacity>=bytes.len());assert!(exceptional);Ok(())}).unwrap().unwrap();assert_eq!(called.get(),1);assert_eq!(old.source_text().as_str(),dm_preprocess::decode_source_bytes(&bytes));match crate::input_snapshot::recorded_source_original(&old).unwrap(){crate::input_snapshot::RecordedSourceOriginal::Bytes(raw)=>assert_eq!(raw.as_slice(),bytes),_=>panic!("exceptional actual byte receipt")}
 let second=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);let new=second.read_raw_source(&path,4096,Some(&old),|_,_,needs_decode|{assert!(!needs_decode);Ok(())}).unwrap().unwrap();assert!(new.same_original_acquisition(&old));assert!(!new.same_binding(&old));assert!(new.source_text().same_view(old.source_text()));assert!(!second.validate_source_lease(&path,&new),"raw reissue never grants a prepared compiler input");assert!(!first.validate_source_lease(&path,&new));
 for error in [std::io::Error::from(std::io::ErrorKind::OutOfMemory),std::io::Error::from_raw_os_error(1450)]{let kind=error.kind();let os=error.raw_os_error();let input=RecordingInputs::new(FileSystemInputs,0);let observed=input.read_raw_source(&path,4096,None,|_,_,_|Err(error)).err().unwrap();assert_eq!(observed.kind(),kind);assert_eq!(observed.raw_os_error(),os);}
}

#[path="runner_query_raw_source_demand_tests.rs"]mod source_demand;

const UI_RAW_DISPATCHER_INPUT: &str = r#"
/proc/ui_action_key(raw)
	if(!istext(raw) || !length(raw) || length(raw) > 64 || !GLOB.ui_action_raw_regex.Find(raw))
		return null
	var/out = GLOB.ui_action_camel_regex.Replace(raw, "$1_$2")
	out = replacetext(lowertext(out), "-", "_")
	return out
GLOBAL_DATUM_INIT(ui_action_raw_regex, /regex, regex(@"^[A-Za-z0-9_-]+$"))
GLOBAL_DATUM_INIT(ui_action_camel_regex, /regex, regex(@"([a-z0-9])([A-Z])", "g"))
GLOBAL_LIST_INIT(ui_reserved_arg_names, list("user", "src", "usr", "ui", "state", "holder"))
"#;

fn ui_raw_fixture(label:&str)->(crate::runner_host::BuildHost,BuildRequest,PathBuf){
 let(host,mut request,root)=fixture(label,0);
 std::fs::create_dir_all(root.join("tgui/packages/tgui/interfaces")).unwrap();
 std::fs::create_dir_all(root.join("code/datums/capabilities")).unwrap();
 std::fs::write(root.join("tgui/packages/tgui/interfaces/Probe.tsx"),"act('go')\n").unwrap();
 let intent=request.policy_inputs.as_mut().unwrap();intent.workspace_auxiliary=vec![Q::UiActions];
 intent.workspace.as_mut().unwrap().recursive_roots=vec![root.join("code"),root.join("tgui/packages/tgui/interfaces")];
 (host,request,root)
}
#[test]fn raw_ui_actual_dispatcher_missing_or_bad_does_not_open_other_payload_or_manifest(){
 for bad in[false,true]{for refused in["code/a.dm","tgui/packages/tgui/interfaces/Probe.tsx"]{
  let(_,request,root)=ui_raw_fixture("raw-ui-dispatcher-early-stop");
  if bad{std::fs::write(root.join("code/datums/capabilities/ui_actions.dm"),"// missing normalization contract\n").unwrap();}
  let intent=request.policy_inputs.unwrap().admit().unwrap();
  let provider=Physical{manifest_attempts:AtomicUsize::new(0),fail:Some(root.join(refused))};
  let inputs=RecordingInputs::new(&provider,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
  let db=Arc::new(crate::query_db::QueryDb::default());
  let(capture,owner)=crate::runner_host::workspace_capture::capture_raw_only(&inputs,&intent,&db).unwrap();
  assert!(!capture.prepared_ui_dispatcher().unwrap().needs_sources());
  assert_eq!(capture.ui_dispatcher_index().unwrap().is_some(),bad);
  assert_eq!(capture.raw_input_files().count(),usize::from(bad));
  assert_eq!(provider.manifest_attempts.load(Ordering::SeqCst),0);
  assert_eq!(owner.purpose().name(),"ui_actions");
 }}
}
#[test]fn raw_ui_valid_dispatcher_keeps_required_io_and_same_querydb_recovery(){
 let(_,request,root)=ui_raw_fixture("raw-ui-dispatcher-required-io");
 std::fs::write(root.join("code/datums/capabilities/ui_actions.dm"),UI_RAW_DISPATCHER_INPUT).unwrap();
 let intent=request.policy_inputs.unwrap().admit().unwrap();let db=Arc::new(crate::query_db::QueryDb::default());
 for refused in["code/a.dm","tgui/packages/tgui/interfaces/Probe.tsx"]{
  let provider=Physical{manifest_attempts:AtomicUsize::new(0),fail:Some(root.join(refused))};
  let inputs=RecordingInputs::new(&provider,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
  let actual=crate::runner_host::workspace_capture::capture_raw_only(&inputs,&intent,&db).err().expect("actual required source must fail");
  assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(provider.manifest_attempts.load(Ordering::SeqCst),0);
 }
 let inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
 let(capture,owner)=crate::runner_host::workspace_capture::capture_raw_only(&inputs,&intent,&db).unwrap();
 assert!(capture.prepared_ui_dispatcher().unwrap().needs_sources());assert!(capture.ui_dispatcher_index().unwrap().is_some());
 assert_eq!(capture.raw_input_files().count(),3);assert!(owner.uses_queries(&db));
}
#[test]fn raw_ui_actual_prepare_ignores_broken_dme_without_semantic_tree(){
 for bad in[false,true]{
  let(mut host,request,root)=ui_raw_fixture("raw-ui-prepare-without-model");
  if bad{std::fs::write(root.join("code/datums/capabilities/ui_actions.dm"),"// invalid dispatcher\n").unwrap();}
  let db=Arc::clone(host.query_db());let before=db.db().stats(dm_query::Kind(4)).computed;
  let outcome=crate::request_runner::run_build_with_host(request,&mut host).unwrap();
  assert!(matches!(outcome,BuildOutcome::RawQueryPrepared{retained:true,..}));assert!(host.query_tree().is_none());
  assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);
 }
}
#[test]fn raw_ui_discovery_and_identity_cannot_grant_other_policy_roles(){
 let(_,request,_)=ui_raw_fixture("raw-ui-closed-role");let mut wrong=request.policy_inputs.clone().unwrap();
 let intent=request.policy_inputs.unwrap().admit().unwrap();let db=Arc::new(crate::query_db::QueryDb::default());
 let inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
 let(capture,owner)=crate::runner_host::workspace_capture::capture_raw_only(&inputs,&intent,&db).unwrap();
 assert!(!capture.covers_code_dm(&mut|_|Ok(())).unwrap());
 assert!(!capture.covers_raw_tree_policy(dq_analyze::captured_raw_tree_pages::Policy::DocSnippets,&mut|_|Ok(())).unwrap());
 assert!(!capture.covers_raw_tree_policy(dq_analyze::captured_raw_tree_pages::Policy::Ownership,&mut|_|Ok(())).unwrap());
 assert!(workspace_native_guard::NativeReadGuard::raw_owned(&capture,&owner,&db).is_ok());
 let other=Arc::new(crate::query_db::QueryDb::default());assert!(workspace_native_guard::NativeReadGuard::raw_owned(&capture,&owner,&other).is_err());
 wrong.workspace_auxiliary=vec![Q::DocSnippets];let wrong=wrong.admit().unwrap();
 let state=Arc::new(Mutex::new(QueryState::default()));let mut attempt=QueryAttempt::new(Arc::clone(&state),true);
 let(_,admission)=crate::request_runner::runner_freshness::admit_workspace_captured(&inputs,None,&crate::frozen_inputs::Inputs::Live,&Default::default(),Arc::clone(&capture)).unwrap();
 assert!(attempt.admit_raw_source(&wrong,capture,owner,db,admission).is_err());assert!(state.lock().unwrap().raw_snapshot.is_none(),"foreign producer purpose cannot publish a source frame");
}

#[test]fn raw_ui_ignored_payloads_stay_unread_but_exempt_fixed_dispatcher_is_required(){
 let(_,request,root)=ui_raw_fixture("raw-ui-ignored-payloads");
 std::fs::write(root.join("code/datums/capabilities/ui_actions.dm"),UI_RAW_DISPATCHER_INPUT).unwrap();
 std::fs::write(root.join("tgui/packages/tgui/interfaces/definitions.d.ts"),"declare const ignored: unknown;\n").unwrap();
 std::fs::write(root.join("tools/ci/lint_scopes.toml"),"[lint.ui_actions]\nexempt_prefixes = [\"code/a.dm\", \"tgui/packages/tgui/interfaces/Probe.tsx\", \"code/datums/capabilities/ui_actions.dm\"]\n").unwrap();
 let intent=request.policy_inputs.unwrap().admit().unwrap();let db=Arc::new(crate::query_db::QueryDb::default());
 for refused in["code/a.dm","tgui/packages/tgui/interfaces/Probe.tsx","tgui/packages/tgui/interfaces/definitions.d.ts"]{
  let provider=Physical{manifest_attempts:AtomicUsize::new(0),fail:Some(root.join(refused))};
  let inputs=RecordingInputs::new(&provider,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
  let(capture,_)=crate::runner_host::workspace_capture::capture_raw_only(&inputs,&intent,&db).unwrap();
  assert!(capture.prepared_ui_dispatcher().unwrap().needs_sources());assert_eq!(capture.raw_input_files().count(),1);
  assert!(capture.productive_ui_configuration().unwrap().unwrap().policy_path_exempt("ui_actions",dq_analyze::ui_actions_policy::metadata().group,"code/a.dm"));
  assert!(capture.productive_doc_configuration().unwrap().is_none());assert_eq!(provider.manifest_attempts.load(Ordering::SeqCst),0);
 }
 let provider=Physical{manifest_attempts:AtomicUsize::new(0),fail:Some(root.join("code/datums/capabilities/ui_actions.dm"))};
 let inputs=RecordingInputs::new(&provider,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
 let error=crate::runner_host::workspace_capture::capture_raw_only(&inputs,&intent,&db).err().expect("fixed dispatcher remains required despite source exemption");
 assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(provider.manifest_attempts.load(Ordering::SeqCst),0);
}
