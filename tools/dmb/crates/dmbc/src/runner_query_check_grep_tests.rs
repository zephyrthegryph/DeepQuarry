//! Actual filesystem/discovery/acquisition and SAME QueryDb complete policy tests.
use super::*;
use dq_analyze::captured_reactive_reads::Failure;
#[path="../../dm-analysis/examples/support/reference_hierarchy.rs"]mod reference_hierarchy;
fn check_fixture(label:&str,count:usize)->PathBuf{
 let root=fixture(label,count);
 for folder in ["maps","tgui/hidden/.child","html/changelogs","config/example","code/__defines/verdigris"]{std::fs::create_dir_all(root.join(folder)).unwrap();}
 std::fs::write(root.join("code/0000.dm"),"#define TRACKED(T,V)\nTRACKED(/datum/probe,slot_flags)\n/datum/probe\n    var/slot_flags\n    var/datum/holder\n    proc/set_slot_flags(value)\n        slot_flags=value\n    proc/check(datum/probe/borrowed)\n        set_slot_flags(slot_flags & ~1)\n        borrowed.holder\n        return 0\n").unwrap();
 std::fs::write(root.join("maps/probe.dmm"),"// TGM map declaration source\n").unwrap();
 std::fs::write(root.join("tgui/probe.jsx"),"observed name only; contents must not be opened").unwrap();std::fs::write(root.join("tgui/hidden/.child/omit.jsx"),"hidden name is excluded").unwrap();
 std::fs::write(root.join("html/changelogs/example.yml"),"actual deliberately modified changelog example\n").unwrap();
 std::fs::write(root.join("config/example/config.txt"),"GAME_VERSION 515\n").unwrap();
 std::fs::write(root.join("dependencies.sh"),"export MACRO_COUNT=0\n").unwrap();
 std::fs::write(root.join("code/__defines/verdigris/_bindings_types.dm"),"var/tmp/init_check_seed\n/proc/get_check_query_probe()\n").unwrap();
 std::fs::write(root.join("code/__defines/verdigris/_bindings.dm"),"#define CHECK_NATIVE_BINDING 1\n").unwrap();
 std::fs::copy(root.join("p.dme"),root.join("deepquarry.dme")).unwrap();
 root
}
fn check_frontend<P:SnapshotProvider>(root:&Path,inputs:&RecordingInputs<P>,db:&Arc<crate::query_db::QueryDb>)->ColdFrontend{
 let seed=reference_hierarchy::seed();let executor=dm_exec::BuildExecutor::new(1).unwrap();
 dm_tree::frontend::build_with_executor(&root.join("deepquarry.dme"),inputs,&Default::default(),dm_tree::frontend::FrontendConfig{workers:1,engine:Some(&seed),observer:None},None,&executor).unwrap().with_body_queries(db.clone())
}
fn selected<P:SnapshotProvider>(root:&Path,front:&ColdFrontend,inputs:&RecordingInputs<P>)->Arc<workspace_capture::WorkspaceCapture>{
 let discovery=Arc::new(workspace_discovery::discover_check_grep(inputs,DiscoveryContract{root:root.into(),recursive_roots:vec![root.join("code"),root.join("maps"),root.join("tgui")]}).unwrap());
 workspace_capture::capture_with_auxiliary(front,inputs,discovery,&root.join("missing.toml"),&[crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrep]).unwrap()
}
fn report(snapshot:&SourceSnapshot)->Result<(String,usize,usize),Failure>{snapshot.with_native_check_grep(&snapshot.tree,|output,budget|{budget.charge(output.report.len().checked_mul(4).and_then(|n|n.checked_add(128)).unwrap()).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;Ok((output.report.clone(),output.run.sites.len(),output.allow_used.len()))})}
#[test]fn actual_check_grep_complete_pages_semantic_loans_fixed_negatives_jsx_and_warm_same_db_no_io(){
 let root=check_fixture("check-grep-actual-130",130);let db=Arc::new(crate::query_db::QueryDb::default());let physical=Physical{reads:Mutex::new(BTreeMap::new()),fail_policy:Mutex::new(None)};let inputs=RecordingInputs::new(&physical,4_000_000_000);let front=check_frontend(&root,&inputs,&db);let capture=selected(&root,&front,&inputs);let snapshot=snapshot(&front,&db,&inputs,&capture);let before=physical.reads();
 let cold=report(&snapshot).unwrap();assert!(cold.1>0);assert!(cold.0.contains("probe.jsx"));assert!(!cold.0.contains("omit.jsx"));let bodies=db.db().stats(dm_query::Kind(4)).computed;assert!(bodies>0,"actual lexical exceptions demand original query-backed body syntax");
 assert_eq!(report(&snapshot).unwrap(),cold);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,bodies);assert_eq!(physical.reads(),before);
 assert_eq!(physical.reads.lock().unwrap().get(&root.join("tgui/probe.jsx")).copied().unwrap_or(0),0,"JSX observation is typed filename-only");
 std::fs::write(root.join(".gitignore"),"/code/0001.dm\n").unwrap();std::fs::write(root.join("html/changelogs/example.yml"),"changed after actual admission\n").unwrap();
 assert_eq!(report(&snapshot).unwrap(),cold,"report is from actual original recorded observations, without a late fixed-file reread");assert_eq!(physical.reads(),before);
 assert!(!capture.facts().validate(&FileSystemInputs,true,u128::MAX/2).unwrap().0.unchanged(),"actual negative/fixed closure changes force fresh preparation");
}
#[test]fn actual_check_grep_refuses_unselected_partial_foreign_archive_and_preserves_callback_1450_cancel(){
 let root=check_fixture("check-grep-actual-domains",2);let db=Arc::new(crate::query_db::QueryDb::default());let inputs=RecordingInputs::new(FileSystemInputs,4_000_000_000);let front=check_frontend(&root,&inputs,&db);let capture=selected(&root,&front,&inputs);let snap=snapshot(&front,&db,&inputs,&capture);let mut entered=0;
 let foreign=crate::query_db::QueryDb::default();assert!(foreign.with_workspace_check_grep(&capture,&snap.workspace_native_read().unwrap(),snap.body_archive.as_deref().unwrap(),snap.semantic_sources.as_deref().unwrap(),|_,_|{entered+=1;Ok(())}).is_err());assert_eq!(entered,0);
 let result=snap.with_native_check_grep(&snap.tree,|_,_|Err::<(),_>(Failure::Operational(io::Error::from_raw_os_error(1450))));assert!(matches!(result,Err(Failure::Operational(ref error))if error.raw_os_error()==Some(1450)));
 let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert!(matches!(report(&snap),Err(Failure::Operational(ref error))if error.kind()==io::ErrorKind::Interrupted));drop(binding);assert!(report(&snap).is_ok());
 // New recorder and matching frontend preserve genuine discovery contracts.
 let other=RecordingInputs::new(FileSystemInputs,4_000_000_000);let front2=check_frontend(&root,&other,&db);let subset=discover(&root,&other);assert!(workspace_capture::capture_with_auxiliary(&front2,&other,subset,&root.join("missing.toml"),&[crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrep]).is_err());
 let ordinary=workspace_capture::capture(&front2,&other,discover(&root,&other),&root.join("missing.toml")).unwrap();let raw=snapshot(&front2,&db,&other,&ordinary);assert!(report(&raw).is_err());
}
#[test]fn actual_check_grep_fixed_source_failure_is_original_io_before_any_report_and_fresh_recorder_recovers(){
 let root=check_fixture("check-grep-fixed-io",2);let db=Arc::new(crate::query_db::QueryDb::default());let physical=Physical{reads:Mutex::new(BTreeMap::new()),fail_policy:Mutex::new(None)};let inputs=RecordingInputs::new(&physical,4_000_000_000);let front=check_frontend(&root,&inputs,&db);*physical.fail_policy.lock().unwrap()=Some(root.join(".gitignore"));let discovery=Arc::new(workspace_discovery::discover_check_grep(&inputs,DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("maps"),root.join("tgui")]}).unwrap());let actual=workspace_capture::capture_with_auxiliary(&front,&inputs,discovery,&root.join("missing.toml"),&[crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrep]).err().unwrap();assert_eq!(actual.raw_os_error(),Some(1450));
 *physical.fail_policy.lock().unwrap()=None;let fresh=RecordingInputs::new(&physical,4_000_000_000);let front=check_frontend(&root,&fresh,&db);let capture=selected(&root,&front,&fresh);let snapshot=snapshot(&front,&db,&fresh,&capture);assert!(report(&snapshot).is_ok());
}

#[path="../../../../analyze/fixtures/native-check-grep/fixture.rs"]mod whole_fixture;
#[test]fn actual_check_grep_whole_original_fixture_projection(){
 for case in ["basic","configured","lossy"]{
  let root=crate::test_scratch::dir(&format!("check-grep-whole-{case}"));
  for(relative,bytes)in whole_fixture::files(case).unwrap(){let path=root.join(relative);std::fs::create_dir_all(path.parent().unwrap()).unwrap();std::fs::write(path,whole_fixture::source_bytes(case,relative,bytes)).unwrap();}
  let db=Arc::new(crate::query_db::QueryDb::default());let physical=Physical{reads:Mutex::new(BTreeMap::new()),fail_policy:Mutex::new(None)};let inputs=RecordingInputs::new(&physical,4_000_000_000);let front=check_frontend(&root,&inputs,&db);
  let discovery=Arc::new(workspace_discovery::discover_check_grep(&inputs,DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("maps"),root.join("tgui")]}).unwrap());
  let capture=workspace_capture::capture_with_auxiliary(&front,&inputs,discovery,&root.join("tools/ci/lint_scopes.toml"),&[crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrep]).unwrap();let snapshot=snapshot(&front,&db,&inputs,&capture);let before=physical.reads();
  let first=snapshot.with_native_check_grep(&snapshot.tree,|output,budget|{
   assert!(output.report.contains("maps\\fixture_test.dmm"),"message-empty root DME sites retain their actual original line text");
   if case=="lossy"{for rule in ["r10_bindings_init_seeds_referenced_outside_a_var_edit","r10_bindings_no_member_var_caching_of_a_binding_read","thermal_constants_generated_not_redefined_h1"]{assert!(output.run.sites.iter().any(|site|site.rel=="code/raw.dm"&&site.rule==rule),"lossy uncompiled original text must preserve dynamic rule {rule}");}}
   let width=output.run.sites.iter().try_fold(output.report.len(),|n,site|n.checked_add(site.rule.len())?.checked_add(site.rel.len())?.checked_add(site.msg.len())?.checked_add(site.key.len())?.checked_add(site.ident.len()));
   budget.charge(width.and_then(|n|n.checked_mul(16)).and_then(|n|n.checked_add(output.run.sites.len().checked_mul(2048)?)).and_then(|n|n.checked_add(8192)).unwrap()).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
   Ok(serde_json::json!({"case":case,"report":output.report,"failed":output.failed,"sites":output.run.sites,"notes":output.run.notes,"allow_used":output.allow_used}))
  }).unwrap();assert!(first["report"].as_str().unwrap().len()>100);assert_eq!(physical.reads(),before);
  println!("NATIVE_CHECK_GREP_FULL={first}");let warm=report(&snapshot).unwrap();assert_eq!(warm.0,first["report"].as_str().unwrap());assert_eq!(warm.1,first["sites"].as_array().unwrap().len());assert_eq!(physical.reads(),before);
 }
}

#[test]fn actual_check_grep_tiny_same_counter_and_body_1450_publish_no_report_then_fresh_operation_recovers(){
 let root=check_fixture("check-grep-real-quota-body-io",2);let db=Arc::new(crate::query_db::QueryDb::default());let physical=Physical{reads:Mutex::new(BTreeMap::new()),fail_policy:Mutex::new(None)};let inputs=RecordingInputs::new(&physical,4_000_000_000);let front=check_frontend(&root,&inputs,&db);let capture=selected(&root,&front,&inputs);let snapshot=snapshot(&front,&db,&inputs,&capture);let before=physical.reads();let mut entered=0;
 let denied=db.with_workspace_check_grep_limit(&capture,&snapshot.workspace_native_read().unwrap(),snapshot.body_archive.as_deref().unwrap(),snapshot.semantic_sources.as_deref().unwrap(),128,|_,_|{entered+=1;Ok(())});assert!(matches!(denied,Err(Failure::Operational(ref error))if error.kind()==io::ErrorKind::OutOfMemory));assert_eq!(entered,0);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,0);
 let fault=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));let io_error=snapshot.with_native_check_grep(&snapshot.tree,|_,_|{entered+=1;Ok(())});assert!(matches!(io_error,Err(Failure::Operational(ref error))if error.raw_os_error()==Some(1450)));assert_eq!(entered,0);drop(fault);
 let good=report(&snapshot).unwrap();assert!(good.1>0);assert_eq!(report(&snapshot).unwrap(),good);assert_eq!(physical.reads(),before);
}
#[test]fn actual_check_grep_discovery_uses_exact_mixed_roots_hidden_sources_shallow_dmes_and_typed_jsx_names(){
 let root=check_fixture("check-grep-typed-domain",1);for directory in ["code/.hidden","doc","tgui/packages/tgui/interfaces","tgui/elsewhere"]{std::fs::create_dir_all(root.join(directory)).unwrap();}
 for(relative,bytes)in[("code/probe.ts","const value = 1;"),("code/.hidden/probe.tsx","hidden exact selected source"),("tgui/packages/tgui/interfaces/a.tsx","exact interface source"),("tgui/elsewhere/skip.ts","outside selected interface"),("tgui/elsewhere/skip.dm","outside selected interface DM"),("other.dme","// actual shallow manifest"),(".hidden.dme","// hidden root manifest"),("doc/nested.dme","// nested manifest"),("code/nested.dme","// nested manifest")]{std::fs::write(root.join(relative),bytes).unwrap();}
 let db=Arc::new(crate::query_db::QueryDb::default());let physical=Physical{reads:Mutex::new(BTreeMap::new()),fail_policy:Mutex::new(None)};let inputs=RecordingInputs::new(&physical,4_000_000_000);let front=check_frontend(&root,&inputs,&db);let capture=selected(&root,&front,&inputs);let snapshot=snapshot(&front,&db,&inputs,&capture);let guard=snapshot.workspace_native_read().unwrap();let(dmes,jsx)=capture.check_grep_names(&guard).unwrap();assert!(dmes.iter().any(|path|path==&root.join("other.dme")));assert!(!dmes.iter().any(|path|path==&root.join(".hidden.dme")||path==&root.join("code/nested.dme")||path==&root.join("doc/nested.dme")));assert_eq!(jsx.len(),1);assert_eq!(jsx[0],root.join("tgui/probe.jsx"));
 let paths=(0..capture.file_count()).map(|index|capture.path(index).unwrap()).collect::<Vec<_>>();assert!(paths.contains(&root.join("code/probe.ts").as_path()));assert!(paths.contains(&root.join("code/.hidden/probe.tsx").as_path()));assert!(paths.contains(&root.join("tgui/packages/tgui/interfaces/a.tsx").as_path()));assert!(!paths.contains(&root.join("tgui/elsewhere/skip.ts").as_path()));assert!(!paths.contains(&root.join("tgui/elsewhere/skip.dm").as_path()));assert!(!paths.contains(&root.join("tgui/probe.jsx").as_path()));
 let before=physical.reads();assert!(report(&snapshot).is_ok());assert_eq!(physical.reads(),before);
}

#[test]fn actual_check_grep_compiled_nontext_map_uses_recorded_raw_bytes_and_preserves_first_io(){
 let root=check_fixture("check-grep-real-compiled-map",1);let map=root.join("maps/probe.dmm");let map_bytes=b"// actual typed map raw bytes\r\n// non-UTF8 map comment \xff\r\n";std::fs::write(&map,map_bytes).unwrap();let manifest=root.join("deepquarry.dme");let mut source=std::fs::read_to_string(&manifest).unwrap();source.push_str("#include \"maps/probe.dmm\"\n");std::fs::write(&manifest,source).unwrap();
 let db=Arc::new(crate::query_db::QueryDb::default());let physical=Physical{reads:Mutex::new(BTreeMap::new()),fail_policy:Mutex::new(None)};let failed=RecordingInputs::new(&physical,4_000_000_000);let first=check_frontend(&root,&failed,&db);let occurrence=first.plan.occurrences.iter().position(|row|row.path.as_path()==map.as_path()&&row.non_text_kind()==Some(dm_preprocess::regions::NonTextKind::Map)).expect("actual native planner must issue a NonText map occurrence");assert!(first.source_export_mapping().unwrap().source_acquisition(occurrence).is_none(),"NonText metadata is not a text acquisition");
 let discovery=Arc::new(workspace_discovery::discover_check_grep(&failed,DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("maps"),root.join("tgui")]}).unwrap());*physical.fail_policy.lock().unwrap()=Some(map.clone());let error=workspace_capture::capture_with_auxiliary(&first,&failed,discovery,&root.join("missing.toml"),&[crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrep]).err().expect("actual map candidate IO must prevent capture publication");assert_eq!(error.raw_os_error(),Some(1450));*physical.fail_policy.lock().unwrap()=None;drop(first);drop(failed);
 let inputs=RecordingInputs::new(&physical,4_000_000_001);let front=check_frontend(&root,&inputs,&db);let capture=selected(&root,&front,&inputs);let snapshot=snapshot(&front,&db,&inputs,&capture);let guard=snapshot.workspace_native_read().unwrap();let index=(0..capture.file_count()).find(|index|capture.path(*index).unwrap()==map.as_path()).unwrap();match capture.original(index,&guard).unwrap(){crate::input_snapshot::RecordedSourceOriginal::Bytes(bytes)=>assert_eq!(bytes.as_slice(),map_bytes),crate::input_snapshot::RecordedSourceOriginal::Utf8(_)=>panic!("a typed map must not be promoted to a native text lease")};let before=physical.reads();let first=report(&snapshot).unwrap();std::fs::write(&map,b"changed after actual capture").unwrap();assert_eq!(report(&snapshot).unwrap(),first);assert_eq!(physical.reads(),before,"queries borrow actual recorded map bytes without reopening the filesystem");
}
