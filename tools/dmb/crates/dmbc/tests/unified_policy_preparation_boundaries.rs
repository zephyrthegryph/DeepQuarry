//! Small public boundary target. Preparation tests run in process; the explicit
//! transport test uses a private daemon. No game world or alternate parser.
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

/// Opt-in transport control. Use the binary Cargo actually built and retire
/// only this private namespace after the run. Files prevent pipe backpressure
/// while the caller polls the bounded child.
struct LibraryTransport<'a>{root:&'a Path,namespace:String}
impl LibraryTransport<'_>{
 fn run(&self,args:&[&std::ffi::OsStr],timeout:std::time::Duration)->std::io::Result<std::process::Output>{
  self.run_program(Path::new(env!("CARGO_BIN_EXE_dmbc")),args,timeout)
 }
 fn run_program(&self,program:&Path,args:&[&std::ffi::OsStr],timeout:std::time::Duration)->std::io::Result<std::process::Output>{
  use std::{fs::File,io,process::{Command,Stdio},time::Instant};
  let stdout=self.root.join("transport.stdout");let stderr=self.root.join("transport.stderr");
  let mut command=Command::new(program);
  command.args(args).stdin(Stdio::null()).stdout(File::create(&stdout)?).stderr(File::create(&stderr)?)
   .env("DMB_DAEMON_NAMESPACE",&self.namespace).env("DMB_DAEMON_DIR",self.root.join("daemon"))
   .env("DMB_DAEMON_AUTOSTART","1").env("DMB_FORWARDED","1")
   .env("DMB_DAEMON_IDLE_EXIT_SECS","120").env("RAYON_NUM_THREADS","1")
   .env_remove("DMB_UNIFIED_ANALYSIS").env_remove("DQ_ALLOW_USAGE");
  #[cfg(windows)]{use std::os::windows::process::CommandExt;command.creation_flags(0x0800_0000|0x0000_4000);}
  let mut child=command.spawn()?;
  let start=Instant::now();
  let status=loop{
   match child.try_wait(){
    Ok(Some(status))=>break status,
    Ok(None)if start.elapsed()<timeout=>std::thread::sleep(std::time::Duration::from_millis(20)),
    result=>{let _=child.kill();let _=child.wait();return Err(result.err().unwrap_or_else(||io::Error::new(io::ErrorKind::TimedOut,"owned library transport child exceeded its watchdog")));}
   }
  };
  Ok(std::process::Output{status,stdout:std::fs::read(stdout)?,stderr:std::fs::read(stderr)?})
 }
}
impl Drop for LibraryTransport<'_>{
 fn drop(&mut self){
  let _=self.run(&[std::ffi::OsStr::new("--daemon-retire")],std::time::Duration::from_secs(20));
 }
}

#[test]
#[ignore = "private dmbc transport; run outside Cargo with the dm_compile machine slot"]
fn public_library_transport_matches_the_exact_raw_fingerprint_and_finishes_empty_without_a_manifest(){
 use dmbc::daemon::analyze::AnalyzeRequest;
 use std::{ffi::OsStr,time::{Duration,SystemTime,UNIX_EPOCH}};
 let root=test_scratch::dir("public-library-transport");
 let daemon=LibraryTransport{root:&root,namespace:format!("library-boundary-{}-{}",std::process::id(),SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis())};
 let rel="code/library/probe.dm";
 put(&root,rel,b"/proc/library_probe()\n    downstream_helper()   // fingerprint from current raw source\n");
 put(&root,"code/content/probe.dm",b"/proc/downstream_helper()\n    return\n");
 put(&root,"deepquarry.dme",format!("#include \"{rel}\"\n#include \"code/content/probe.dm\"\n"));
 put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay(""));
 let mut analyze=AnalyzeRequest{build:request(&root,Q::LibraryLayering),lints:vec!["library_layering".into()],raw:false,changed:None,scopes_root:None,baseline_mode:None,ci:false};
 let request_path=root.join("library-request.json");
 let check=|request:&AnalyzeRequest,code:i32|{
  std::fs::write(&request_path,serde_json::to_vec(request).unwrap()).unwrap();
  let output=daemon.run(&[OsStr::new("analyze-check"),request_path.as_os_str(),OsStr::new("--jsonl")],Duration::from_secs(120)).unwrap();
  assert_eq!(output.status.code(),Some(code),"stdout={}\nstderr={}",String::from_utf8_lossy(&output.stdout),String::from_utf8_lossy(&output.stderr));
  let report:serde_json::Value=serde_json::from_slice(&output.stdout).unwrap();
  assert_eq!(report["lints"],serde_json::json!(["library_layering"]));
  assert_eq!(report["complete"],true);
  assert_eq!(report["full_policy_parity"],false);
  assert_eq!(report["clean"],code==0);
  report
 };
 let report=check(&analyze,1);
 assert!(report["text"].as_str().unwrap().contains("downstream_helper() // fingerprint from current raw source"));
 put(&root,"tools/ci/library_layering_baseline.txt",format!("external_dependency\t{rel}\tdownstream_helper() // fingerprint from current raw source\n"));
 let covered=check(&analyze,0);
 assert_eq!(covered["source_revision"],report["source_revision"],"the authored fixture baseline covers the actual same source");
 let manifest=root.join("deepquarry.dme");
 analyze.raw=true;
 let authored_raw=check(&analyze,1);
 std::fs::remove_file(&manifest).unwrap();
 let absent=check(&analyze,1);
 assert_eq!(absent["text"],authored_raw["text"],"the missing-root route must resolve the same live library-to-content call from captured CODE");
 assert_eq!(check(&analyze,1),absent,"warm replay must preserve the exact synthetic report");
 assert!(!manifest.exists(),"the private root must not materialize a fixed manifest");
 assert!(!root.join("__dmb_original_analysis_subject__").exists(),"the private root must not create a synthetic namespace on disk");
 for bytes in [b"// no authored marker\n".as_slice(),b"\xFF#include \"code/library/probe.dm\"\n".as_slice()] {
  std::fs::write(&manifest,bytes).unwrap();
  assert_eq!(check(&analyze,1)["text"],authored_raw["text"],"readable non-marker or non-UTF-8 manifests use the legacy synthetic recipe");
  assert_eq!(std::fs::read(&manifest).unwrap(),bytes);
 }
 std::fs::remove_file(&manifest).unwrap();
 std::fs::create_dir(&manifest).unwrap();
 let invalid=daemon.run(&[OsStr::new("analyze-check"),request_path.as_os_str(),OsStr::new("--jsonl")],Duration::from_secs(120)).unwrap();
 assert!(!invalid.status.success());
 let stderr=String::from_utf8_lossy(&invalid.stderr);
 assert!(stderr.contains("candidate is not a regular file"),"{stderr}");
 assert!(serde_json::from_slice::<serde_json::Value>(&invalid.stdout).map_or(true,|report|report["complete"]!=true),"operational nonfile refusal must not publish the previous synthetic report");
 std::fs::remove_dir(&manifest).unwrap();
 put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay("[lint.library_layering]\nexempt_files=[\"code/library/probe.dm\"]\n"));
 analyze.raw=true;
 let empty=check(&analyze,0);
 assert_ne!(empty["policy_revision"],covered["policy_revision"],"the no-model role has distinct current evidence");
 assert!(!empty["text"].as_str().unwrap().contains("downstream_helper()"));
 assert!(!root.join("deepquarry.dmb").exists());
}

#[test]
fn notice_publisher_prepares_only_complete_code_without_a_model_or_manifest_read() {
 let root=test_scratch::dir("public-notice-publisher-no-model");
 put(&root,"code/probe.dm",b"// captured CODE_DM input\n");
 put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay(""));
 let request=request(&root,Q::NoticePublisher);
 let mut host=BuildHost::default();
 let missing=prepare_raw(&mut host,&request);
 put(&root,"deepquarry.dme",b"#include \"unreadable_or_missing.dm\"\n");
 let malformed=prepare_raw(&mut host,&request);
 assert_eq!(missing.source,malformed.source,"a hostile authored manifest cannot become a raw input");
 assert_eq!(missing.policy,malformed.policy);
 std::fs::remove_file(&request.project).unwrap();
 std::fs::create_dir(&request.project).unwrap();
 let directory=prepare_raw(&mut host,&request);
 assert_eq!(missing.source,directory.source);
 assert_eq!(missing.policy,directory.policy);
 put(&root,"code/probe.dm",b"// changed actual CODE_DM input\n");
 let changed=prepare_raw(&mut host,&request);
 assert_ne!(directory.source,changed.source);
 assert!(!root.join("deepquarry.dmb").exists());

 let mut mixed=request.clone();
 mixed.policy_inputs.as_mut().unwrap().workspace_auxiliary.push(Q::Ownership);
 assert!(dmbc::request_runner::run_build_with_host(mixed,&mut host).is_err());
 let mut wrong_root=request;
 wrong_root.policy_inputs.as_mut().unwrap().workspace.as_mut().unwrap().recursive_roots=vec![root.join("code/probe.dm")];
 assert!(dmbc::request_runner::run_build_with_host(wrong_root,&mut host).is_err());
}

#[test]
#[ignore = "private dmbc transport; run outside Cargo with the dm_compile machine slot"]
fn public_notice_publisher_emits_message_only_findings_from_the_actual_raw_tree() {
 use dmbc::daemon::analyze::AnalyzeRequest;
 use std::{ffi::OsStr,time::{Duration,SystemTime,UNIX_EPOCH}};
 let root=test_scratch::dir("public-notice-publisher");
 let daemon=LibraryTransport{root:&root,namespace:format!("notice-publisher-{}-{}",std::process::id(),SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis())};
 std::fs::create_dir(root.join("deepquarry.dme")).unwrap();
 put(&root,"code/probe.dm",concat!(
     "/datum/probe/proc/subscriber()\n",
     "    on_notice(/datum/notice/witness_missing)\n",
     "    on_notice(/datum/notice/child_published)\n",
     "    publish(/datum/notice/child_published/subtype)\n",
     "/datum/after\n",
 ));
 put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay(""));
 let build=request(&root,Q::NoticePublisher);
 let analyze=AnalyzeRequest{build,lints:vec!["notice_publisher".into()],raw:false,changed:None,scopes_root:None,baseline_mode:None,ci:true};
 let path=root.join("notice-request.json");
 std::fs::write(&path,serde_json::to_vec(&analyze).unwrap()).unwrap();
 let output=daemon.run(&[OsStr::new("analyze-check"),path.as_os_str(),OsStr::new("--jsonl")],Duration::from_secs(90)).unwrap();
 assert_eq!(output.status.code(),Some(1),"stdout={}\nstderr={}",String::from_utf8_lossy(&output.stdout),String::from_utf8_lossy(&output.stderr));
 let report:serde_json::Value=serde_json::from_slice(&output.stdout).unwrap();
 assert_eq!(report["lints"],serde_json::json!(["notice_publisher"]));
 assert_eq!(report["complete"],true);
 assert_eq!(report["full_policy_parity"],false);
 assert_eq!(report["clean"],false);
 let message=report["text"].as_str().unwrap();
 assert!(message.contains("a subscriber waits for /datum/notice/witness_missing, which nothing publishes"),"{message}");
 assert!(!message.contains("a subscriber waits for /datum/notice/child_published"),"{message}");
}

#[test]
#[ignore = "private dmbc transport; run outside Cargo with the dm_compile machine slot"]
fn public_silicon_entry_preserves_raw_and_hidden_actor_findings_under_one_original_subject() {
 use dmbc::daemon::analyze::AnalyzeRequest;
 use std::{ffi::OsStr,time::{Duration,SystemTime,UNIX_EPOCH}};
 let root=test_scratch::dir("public-silicon-entry");
 let daemon=LibraryTransport{root:&root,namespace:format!("silicon-entry-{}-{}",std::process::id(),SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis())};
 put(&root,"deepquarry.dme","#include \"code/main.dm\"\n#include \"code/.actor.dm\"\n");
 put(&root,"code/main.dm",concat!("/datum/act\n    var/actor\n/datum/act/op\n/mob/living/silicon/ai\n/obj/machinery\n    var/is_ai_remote_interface=1\n"));
 put(&root,"code/.actor.dm",concat!("#define isAI(A) istype(A, /mob/living/silicon/ai)\n/obj/machinery/proc/use(datum/act/op/A)\n    return isAI(A.actor)\n/obj/machinery/proc/covered(datum/act/op/A)\n    return isAI(A.actor) // ALLOW(silicon_entry): this tests the recorded annotation consumption\n"));
 put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay(""));
 let build=request(&root,Q::SiliconEntry);
 let analyze=AnalyzeRequest{build,lints:vec!["silicon_entry".into()],raw:false,changed:None,scopes_root:None,baseline_mode:None,ci:true};
 let path=root.join("silicon-entry-request.json");
 std::fs::write(&path,serde_json::to_vec(&analyze).unwrap()).unwrap();
 let output=daemon.run(&[OsStr::new("analyze-check"),path.as_os_str(),OsStr::new("--jsonl")],Duration::from_secs(90)).unwrap();
 assert_eq!(output.status.code(),Some(1),"stdout={}\nstderr={}",String::from_utf8_lossy(&output.stdout),String::from_utf8_lossy(&output.stderr));
 let report:serde_json::Value=serde_json::from_slice(&output.stdout).unwrap();
 assert_eq!(report["lints"],serde_json::json!(["silicon_entry"]));
 assert_eq!(report["complete"],true);
 assert_eq!(report["full_policy_parity"],false);
 assert_eq!(report["clean"],false);
 let message=report["text"].as_str().unwrap();
 assert!(message.contains("code/main.dm:6")&&message.contains("is_ai_remote_interface"),"{message}");
 assert!(message.contains("code/.actor.dm:3")&&message.contains("op handler /obj/machinery/proc/use"),"{message}");
 assert!(!message.contains("proc/covered"),"{message}");
 assert!(!root.join("deepquarry.dmb").exists());
 let mut denied=analyze;
 denied.build.policy_inputs.as_mut().unwrap().workspace_auxiliary=vec![Q::UntypedMember];
 std::fs::write(&path,serde_json::to_vec(&denied).unwrap()).unwrap();
 let output=daemon.run(&[OsStr::new("analyze-check"),path.as_os_str(),OsStr::new("--jsonl")],Duration::from_secs(90)).unwrap();
 assert!(!output.status.success());
 assert!(String::from_utf8_lossy(&output.stderr).contains("exactly its admitted fixed auxiliary questions"));
}

#[test]
#[ignore = "private dmbc transport; run outside Cargo with the dm_compile machine slot"]
fn public_handlers_report_uses_the_structural_source_and_only_demanded_full_source() {
 use dmbc::daemon::analyze::AnalyzeRequest;
 use std::{ffi::OsStr,time::{Duration,SystemTime,UNIX_EPOCH}};
 let root=test_scratch::dir("public-handlers-transport");
 let daemon=LibraryTransport{root:&root,namespace:format!("handlers-{}-{}",std::process::id(),SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis())};
 put(&root,"code/context.dm","/datum/act\n/proc/leak(datum/act/A)\n    return list(A)\n");
 put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay(""));
 let manifest=root.join("deepquarry.dme");std::fs::create_dir(&manifest).unwrap();
 let build=request(&root,Q::SemHandlers);
 let analyze=AnalyzeRequest{build,lints:vec!["sem/handlers".into()],raw:true,changed:None,scopes_root:None,baseline_mode:None,ci:false};
 let path=root.join("handler-request.json");
 std::fs::write(&path,serde_json::to_vec(&analyze).unwrap()).unwrap();
 let check=||{
  let output=daemon.run(&[OsStr::new("analyze-check"),path.as_os_str(),OsStr::new("--jsonl")],Duration::from_secs(90)).unwrap();
  assert_eq!(output.status.code(),Some(1),"stdout={}\nstderr={}",String::from_utf8_lossy(&output.stdout),String::from_utf8_lossy(&output.stderr));
  let report:serde_json::Value=serde_json::from_slice(&output.stdout).unwrap();
  assert_eq!(report["schema"],"native-analyze-handlers-report-v1");assert_eq!(report["complete"],true);assert_eq!(report["full_policy_parity"],false);
  assert_eq!(report["preparation"]["kind"],"current");assert!(report["preparation"]["partial_source_revision"].is_string());
  report
 };
 let structural=check();
 assert!(structural["preparation"]["full_source_revision"].is_null());
 assert!(structural["text"].as_str().unwrap().contains("code/context.dm:3"));
 std::fs::remove_dir(&manifest).unwrap();
 put(&root,"code/engine/present/protocols.dm","/datum/look\n/atom/proc/draw(datum/look/look)\n    return\n");
 put(&root,"code/output.dm","/obj/bad/draw(extra,datum/look/look)\n    return\n");
 put(&root,"deepquarry.dme","#include \"code/context.dm\"\n#include \"code/engine/present/protocols.dm\"\n#include \"code/output.dm\"\n");
 let whole=check();assert!(whole["preparation"]["full_source_revision"].is_string());
 let text=whole["text"].as_str().unwrap();assert!(text.contains("code/context.dm:3")&&text.contains("code/output.dm:1"));
 assert!(!root.join("deepquarry.dmb").exists());
}

#[test]
#[ignore = "private dmbc transport; run outside Cargo with the dm_compile machine slot"]
fn public_combined_checker_analyze_transport_shares_source_and_keeps_ordinary_v1() {
    use dq_analyze::{
        captured_allow_annotations::{full_unused, Operation},
        captured_generator_budget::Budget,
        selected_exclusions_wire::{CombinedTerminal, Hex128, Roster, Seal, Terminal},
    };
    use std::{ffi::OsStr, time::{Duration, SystemTime, UNIX_EPOCH}};
    let root = test_scratch::dir("public-combined-selected");
    let transport = test_scratch::dir("public-combined-selected-transport");
    let cache = test_scratch::dir("public-combined-selected-cache");
    let daemon = LibraryTransport {
        root: &transport,
        namespace: format!("combined-report-{}-{}", std::process::id(), SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis()),
    };
    let manifest = "#warn combined_transport_warning\n#include \"code/probe.dm\"\n";
    put(&root, "deepquarry.dme", manifest);
    put(&root, "tools/ci/lint_scopes.toml", report_configuration::with_overlay(
        "[lint.auto_tracked.lists]\ninclude=[\"/datum/charge_probe::charge\"]\n",
    ));
    put(&root, "code/probe.dm", concat!(
        "#define CAPABILITIES(...)\n",
        "#define PROC_REF(P) #P\n",
        "/datum/act\n/datum/act/eval\n",
        "/datum/receiver\n",
        "/proc/check_field(datum/receiver/argument)\n    return argument.field\n",
        "/obj/probe\n",
        "/obj/probe/proc/dynamic(datum/act/eval/A)\n    return vars[\"probe\"]\n",
        "CAPABILITIES(/obj/probe,when(PROC_REF(dynamic)))\n",
        "#define SETTER(T,V)\n",
        "/datum/charge_probe\n    var/charge\n",
        "SETTER(/datum/charge_probe, charge)\n",
        "/datum/charge_probe/proc/set_charge(value)\n    charge = value\n",
    ));
    let mut build = request(&root, Q::DocSnippets);
    build.cache_root = Some(cache);
    let intent = build.policy_inputs.as_mut().unwrap();
    intent.workspace_auxiliary.clear();
    intent.workspace.as_mut().unwrap().recursive_roots = vec![root.join("code"), root.join("maps")];
    let budget = Budget::new(1 << 20).unwrap();
    let mut work = Operation { budget: &budget, poll: &|| Ok(()) };
    let all = full_unused::registered_full_selection(&[], &mut work).unwrap();
    let request_path = transport.join("combined.json");
    let set_roster = |roster: Roster| {
        let exclusions: Vec<_> = all.names().iter().filter(|name| !roster.names().contains(&name.as_str()))
            .map(|name| format!("-{name}")).collect();
        let json = serde_json::json!({"build":build,"exclusions":exclusions});
        std::fs::write(&request_path, serde_json::to_vec(&json).unwrap()).unwrap();
    };
    let run = |command: &str| daemon.run(
        &[OsStr::new(command), request_path.as_os_str(), OsStr::new("--report-batch")],
        Duration::from_secs(120),
    ).unwrap();
    let seal = |bytes: &[u8]| Seal {
        length: bytes.len() as u64, hash: Hex128(xxhash_rust::xxh3::xxh3_128(bytes)),
    };
    let split = |stdout: &[u8]| stdout.iter().position(|byte| *byte == b'\n').expect("bounded terminal line");
    for roster in [Roster::WithSemanticReads, Roster::WithReactivePolicies] {
        set_roster(roster);
        let actual = run("checker-analyze-selected");
        assert_eq!(actual.status.code(), Some(1), "stderr={}", String::from_utf8_lossy(&actual.stderr));
        let header_end = split(&actual.stdout);
        let header: CombinedTerminal = serde_json::from_slice(&actual.stdout[..header_end]).unwrap();
        header.require().unwrap();
        assert_eq!(header.roster, roster);
        let (checker, analyze) = actual.stdout[header_end + 1..].split_at(header.checker.length as usize);
        assert_eq!(header.checker, seal(checker));
        assert_eq!(header.report, seal(analyze));
        assert_eq!(header.diagnostics, Some(seal(&actual.stderr)));
        assert_eq!(String::from_utf8_lossy(&actual.stderr).matches("combined_transport_warning").count(), 1);
        let checker: serde_json::Value = serde_json::from_slice(checker).unwrap();
        let wire_frame = serde_json::to_value(header.frame).unwrap();
        assert_eq!(checker["semantic_revision"], wire_frame["semantic_revision"]);
        assert_eq!(checker["source_revision"], wire_frame["source_revision"]);
        assert_eq!(checker["policy_revision"], serde_json::to_value(header.checker_policy_revision).unwrap());
        assert_eq!(checker["full_checker_parity"], false);
        assert!(checker["diagnostics"].as_array().unwrap().iter().any(|row| row["family"] == "undefined_variable"));
        let analyze_text = std::str::from_utf8(analyze).unwrap();
        assert!(analyze_text.contains("[reads/dynamic_read]"), "{analyze_text}");
        assert!(analyze_text.contains("[untracked_inputs/stat_input_untracked]"), "{analyze_text}");
        assert_eq!(analyze_text.contains("[setter_publishes/no_publish]"), roster == Roster::WithReactivePolicies, "{analyze_text}");

        let ordinary = run("analyze-exclusions");
        assert_eq!(ordinary.status.code(), Some(1));
        let ordinary_end = split(&ordinary.stdout);
        let ordinary_header: Terminal = serde_json::from_slice(&ordinary.stdout[..ordinary_end]).unwrap();
        ordinary_header.require(roster).unwrap();
        assert_eq!(ordinary_header.frame, header.frame);
        assert_eq!(&ordinary.stdout[ordinary_end + 1..], analyze);
        assert_eq!(ordinary.stderr, actual.stderr);
    }

    // Hold the Analyze roster fixed and exercise Checker-only status changes.
    // The manifest's raw preprocessing warning remains a separate transcript.
    let roster = Roster::WithSemanticReads;
    set_roster(roster);
    let checker_only = |source: &str, expected: Option<(&str, &str)>| {
        put(&root, "code/probe.dm", source);
        let ordinary = run("analyze-exclusions");
        assert_eq!(ordinary.status.code(), Some(0), "{}", String::from_utf8_lossy(&ordinary.stderr));
        let ordinary_end = split(&ordinary.stdout);
        let ordinary_header: Terminal = serde_json::from_slice(&ordinary.stdout[..ordinary_end]).unwrap();
        ordinary_header.require(roster).unwrap();
        assert!(ordinary_header.clean);

        let combined = run("checker-analyze-selected");
        assert_eq!(combined.status.code(), Some(i32::from(expected.is_some())), "{}", String::from_utf8_lossy(&combined.stderr));
        let header_end = split(&combined.stdout);
        let header: CombinedTerminal = serde_json::from_slice(&combined.stdout[..header_end]).unwrap();
        header.require().unwrap();
        assert_eq!(header.roster, roster);
        assert_eq!(header.clean, expected.is_none());
        let (checker, analyze) = combined.stdout[header_end + 1..].split_at(header.checker.length as usize);
        assert_eq!(analyze, &ordinary.stdout[ordinary_end + 1..]);
        assert_eq!(combined.stderr, ordinary.stderr);
        let report: serde_json::Value = serde_json::from_slice(checker).unwrap();
        let rows = report["diagnostics"].as_array().unwrap();
        assert_eq!(rows.len(), usize::from(expected.is_some()), "{report}");
        if let Some((family, level)) = expected {
            assert_eq!(rows[0]["family"], family);
            assert_eq!(rows[0]["severity"], level);
        }
    };
    checker_only(
        "/datum/receiver\n/proc/check_field(datum/receiver/argument)\n    return argument.field\n",
        Some(("undefined_variable", "error")),
    );
    checker_only("/proc/check_field()\n    return 1\n", None);

    let warning = "/proc/check_setting()\n    set SpacemanDMM_not_known=1\n    return 1\n";
    checker_only(warning, Some(("unknown_linter_setting", "warning")));
    put(&root, "SpacemanDMM.toml", "[diagnostics]\nunknown_linter_setting=\"off\"\n");
    checker_only(warning, None);

    put(&root, "deepquarry.dme", format!("{manifest}/proc/fatal(var/A=)\n"));
    let rejected = run("checker-analyze-selected");
    assert_eq!(rejected.status.code(), Some(2));
    assert!(rejected.stdout.is_empty());
    assert!(!String::from_utf8_lossy(&rejected.stderr).contains("combined_transport_warning"));
    assert!(!root.join("deepquarry.dmb").exists());
}

#[test]
#[ignore = "private dmbc transport; run outside Cargo with the dm_compile machine slot"]
fn public_map_edits_transport_pins_regular_maps_and_refuses_other_geometry() {
    use dmbc::daemon::analyze::AnalyzeRequest;
    use std::{ffi::OsStr, time::{Duration, SystemTime, UNIX_EPOCH}};
    let root = test_scratch::dir("public-map-edits");
    let transport = test_scratch::dir("public-map-edits-transport");
    let daemon = LibraryTransport {
        root: &transport,
        namespace: format!("map-edits-{}-{}", std::process::id(), SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis()),
    };
    put(&root, "deepquarry.dme", "#include \"code/probe.dm\"\n");
    put(&root, "code/probe.dm", "/obj/base\n    var/known\n/obj/base/child\n");
    put(&root, "tools/ci/lint_scopes.toml", report_configuration::with_overlay(""));
    let mut request = AnalyzeRequest { build: request(&root, Q::MapEdits), lints: vec!["map_edits".into()],
        raw: false, changed: None, scopes_root: None, baseline_mode: None, ci: false };
    let input = transport.join("map-edits-request.json");
    let run = |request: &AnalyzeRequest, expected: i32| {
        std::fs::write(&input, serde_json::to_vec(request).unwrap()).unwrap();
        let output = daemon.run(&[OsStr::new("analyze-check"), input.as_os_str(), OsStr::new("--jsonl")], Duration::from_secs(120)).unwrap();
        assert_eq!(output.status.code(), Some(expected), "stdout={}\nstderr={}", String::from_utf8_lossy(&output.stdout), String::from_utf8_lossy(&output.stderr));
        if let Some(client) = std::env::var_os("DQ_MAP_EDITS_NATIVE_ANALYZE") {
            let client = PathBuf::from(client);
            assert!(client.is_absolute(), "use an actual analyze-native executable");
            let thin = daemon.run_program(
                &client,
                &[
                    OsStr::new("native-check"),
                    OsStr::new("--dmbc"),
                    OsStr::new(env!("CARGO_BIN_EXE_dmbc")),
                    input.as_os_str(),
                ],
                Duration::from_secs(120),
            ).expect("run actual standalone Analyze thin client");
            assert_eq!(thin.status.code(), Some(expected), "{}", String::from_utf8_lossy(&thin.stderr));
            assert_eq!(thin.stdout, output.stdout, "the client delivers only the verified named report bytes");
        }
        if expected == 2 {
            assert!(output.stdout.is_empty(), "partial result before capture refusal");
            return serde_json::Value::Null;
        }
        let row: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
        assert_eq!(row["complete"], true);
        assert_eq!(row["lints"], serde_json::json!(["map_edits"]));
        assert_eq!(row["clean"], expected == 0);
        if let Some(oracle) = std::env::var_os("DQ_MAP_EDITS_LEGACY_ANALYZE") {
            let oracle = PathBuf::from(oracle);
            assert!(oracle.is_absolute(), "use an independent pre-port legacy Analyze binary");
            let mut legacy = std::process::Command::new(oracle);
            legacy.args(["check", "--lint", "map_edits", "--no-cache", "--root"]).arg(&root);
            legacy.env_remove("DQ_ANALYZE_NATIVE").env_remove("DQ_ALLOW_USAGE");
            #[cfg(windows)]
            {
                use std::os::windows::process::CommandExt;
                legacy.creation_flags(0x08000000 | 0x00004000);
            }
            let legacy = legacy.output().expect("run independent pre-port MapEdits scanner");
            assert_eq!(legacy.status.code(), Some(expected), "{}", String::from_utf8_lossy(&legacy.stderr));
            assert_eq!(row["text"].as_str().unwrap().as_bytes(), legacy.stdout.as_slice());
        }
        row
    };
    let empty = run(&request, 0);
    put(&root, "maps/.hidden/edit.dmm", b"/obj/base/child{known = 1; name = \"built-in\"; lost = 2}\r\n/obj/absent{stray = \"\xff\"}\r\n");
    put(&root, "maps/palettes/ignored.dmm", b"/obj/absent{should_not_read = 3}\n");
    let actual = run(&request, 1);
    let text = actual["text"].as_str().unwrap();
    assert!(text.contains("maps/.hidden/edit.dmm:1: [map_edits/unknown_var] /obj/base/child.lost"), "{text}");
    assert!(text.contains("maps/.hidden/edit.dmm:2: [map_edits/unknown_type] /obj/absent"), "{text}");
    assert_eq!(text.matches("[map_edits/unknown_").count(), 2, "{text}");
    assert_eq!(actual["source_revision"], empty["source_revision"]);
    assert_ne!(actual["policy_revision"], empty["policy_revision"]);
    put(&root, "maps/.hidden/edit.dmm", b"/obj/base/child{known = 3}\n");
    let repaired = run(&request, 0);
    assert_eq!(repaired["source_revision"], actual["source_revision"]);
    assert_ne!(repaired["policy_revision"], actual["policy_revision"]);
    #[cfg(unix)]
    {
        std::os::unix::fs::symlink(".hidden/edit.dmm", root.join("maps/alias.dmm")).unwrap();
        run(&request, 2);
    }
    request.build.policy_inputs.as_mut().unwrap().workspace.as_mut().unwrap().recursive_roots.push(root.join("maps"));
    run(&request, 2);
    assert!(!root.join("deepquarry.dmb").exists());
}

#[test]
#[ignore = "private dmbc transport; run outside Cargo with the dm_compile machine slot"]
fn public_allow_annotations_preserves_explicit_validation_scope_and_zero_usage() {
    use dmbc::{daemon::analyze::AnalyzeRequest, policy_request::PolicyInputRequest};
    use std::{ffi::OsStr, time::{Duration, SystemTime, UNIX_EPOCH}};

    let root = test_scratch::dir("public-allow-annotations");
    let transport = test_scratch::dir("public-allow-annotations-transport");
    let daemon = LibraryTransport {
        root: &transport,
        namespace: format!("allow-annotations-{}-{}", std::process::id(), SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis()),
    };
    put(&root, "deepquarry.dme", "#include \"code/probe.dm\"\n");
    put(&root, "code/probe.dm", "/proc/fixture()\n    return\n// ALLOW(fixture_custom): this valid unused annotation is outside explicit validation\n");
    put(&root, "maps/visible.dm", "// ALLOW(keys): this name comes from the actual shared lint registry\n// ALLOW(unregistered_fixture_name): report this invalid original annotation\n");
    put(&root, "maps/.hidden/invisible.dm", "// ALLOW():\n");
    put(&root, "code/annotation_exempt/ignored.dm", "// ALLOW():\n");
    put(&root, "elsewhere/outside.dm", "// ALLOW():\n");
    let config = report_configuration::with_overlay(
        "[lint.allow_annotations]\nexempt_prefixes=[\"code/annotation_exempt/\"]\n",
    ).replacen("\nknown = [", "\nknown = [\"fixture_custom\", ", 1);
    put(&root, "tools/ci/lint_scopes.toml", config);
    let mut build = request(&root, Q::MapEdits);
    let PolicyInputRequest { workspace, workspace_auxiliary, .. } = build.policy_inputs.as_mut().unwrap();
    let workspace = workspace.as_mut().unwrap();
    workspace.recursive_roots.push(root.join("maps"));
    workspace_auxiliary.clear();
    let request = AnalyzeRequest {
        build, lints: vec!["allow_annotations".into()], raw: false, changed: None,
        scopes_root: None, baseline_mode: None, ci: false,
    };

    let input = transport.join("allow-annotations-request.json");
    let run = |request: &AnalyzeRequest, expected: i32| {
        std::fs::write(&input, serde_json::to_vec(request).unwrap()).unwrap();
        let direct = daemon.run(&[OsStr::new("analyze-check"), input.as_os_str(), OsStr::new("--jsonl")], Duration::from_secs(120)).unwrap();
        assert_eq!(direct.status.code(), Some(expected), "stdout={}\nstderr={}", String::from_utf8_lossy(&direct.stdout), String::from_utf8_lossy(&direct.stderr));
        if let Some(client) = std::env::var_os("DQ_ALLOW_ANNOTATIONS_NATIVE_ANALYZE") {
            let client = PathBuf::from(client);
            assert!(client.is_absolute(), "use an actual analyze-native executable");
            let thin = daemon.run_program(
                &client,
                &[OsStr::new("native-check"), OsStr::new("--dmbc"), OsStr::new(env!("CARGO_BIN_EXE_dmbc")), input.as_os_str()],
                Duration::from_secs(120),
            ).unwrap();
            assert_eq!(thin.status.code(), Some(expected), "{}", String::from_utf8_lossy(&thin.stderr));
            assert_eq!(thin.stdout, direct.stdout);
        }
        if expected == 2 {
            assert!(direct.stdout.is_empty());
            return serde_json::Value::Null;
        }
        let row: serde_json::Value = serde_json::from_slice(&direct.stdout).unwrap();
        assert_eq!(row["complete"], true);
        assert_eq!(row["lints"], serde_json::json!(["allow_annotations"]));
        assert_eq!(row["clean"], expected == 0);
        assert_eq!(row["allow_usage"], serde_json::json!([]));
        let text = row["text"].as_str().unwrap();
        assert!(!text.contains("allow annotations:") && !text.contains(" is unused:"));
        if let Some(oracle) = std::env::var_os("DQ_ALLOW_ANNOTATIONS_LEGACY_ANALYZE") {
            let oracle = PathBuf::from(oracle);
            assert!(oracle.is_absolute(), "use the independently built legacy oracle");
            let mut legacy = std::process::Command::new(oracle);
            legacy.args(["check", "--lint", "allow_annotations", "--no-selftest", "--no-cache", "--unused", "--root"]).arg(&root);
            legacy.env_remove("DQ_ANALYZE_NATIVE").env_remove("DQ_ALLOW_USAGE");
            #[cfg(windows)]
            {
                use std::os::windows::process::CommandExt;
                legacy.creation_flags(0x0800_0000 | 0x0000_4000);
            }
            let legacy = legacy.output().unwrap();
            assert_eq!(legacy.status.code(), Some(expected), "{}", String::from_utf8_lossy(&legacy.stderr));
            assert_eq!(legacy.stdout.as_slice(), text.as_bytes());
        }
        row
    };
    let findings = run(&request, 1);
    let text = findings["text"].as_str().unwrap();
    assert!(text.contains("maps/visible.dm:2:") && text.contains("unregistered_fixture_name"), "{text}");
    for excluded in ["invisible.dm", "ignored.dm", "outside.dm"] {
        assert!(!text.contains(excluded), "{text}");
    }
    put(&root, "maps/visible.dm", "// ALLOW(keys): this name comes from the actual shared lint registry\n");
    let clean = run(&request, 0);
    assert_eq!(findings["source_revision"], clean["source_revision"]);
    assert_ne!(findings["policy_revision"], clean["policy_revision"]);

    let mut mixed = request.clone();
    mixed.lints.push("scheduler".into());
    run(&mixed, 2);
    let mut partial = request;
    partial.build.policy_inputs.as_mut().unwrap().workspace.as_mut().unwrap().recursive_roots.pop();
    run(&partial, 2);
    assert!(!root.join("deepquarry.dmb").exists());
}
