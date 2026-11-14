//! Genuine public native host source-bound list-macro cohort; no fake source facts,
//! daemon, legacy fallback, GUI, pins or monolithic library test executable.
#[path="../../../shared/test_scratch.rs"] mod scratch;
#[path="../../../../analyze/fixtures/report_configuration.rs"] mod report_configuration;
use dmbc::{native_fix::{self,Codemod,Request,CommittedFailure},policy_request::{AnalysisContext,PolicyInputRequest,WorkspaceAuxiliaryQuestion,WorkspacePolicyRequest},request::{BuildRequest,Command},runner_host::BuildHost};
use std::{fs,io::{self,Write},path::{Path,PathBuf}};
#[global_allocator]static ALLOC:mimalloc::MiMalloc=mimalloc::MiMalloc;
const ROOTS:[&str;6]=["code","doc/rewrite","interface","maps","modular_chomp","tgui"];
// Exact authored production macros, not empty form stand-ins. This remains
// source/edit-host qualification; the small local list mutator is not a claim
// to reproduce all production generated setter notices/gameplay effects.
fn definitions()->String{
 let setter=include_str!("../../../../../code/defines/engine/capabilities.dm").lines().find(|line|line.starts_with("#define SETTER(")).expect("actual authored setter marker macro");
 let tracked=include_str!("../../../../../code/defines/engine/capabilities.dm").lines().find(|line|line.starts_with("#define TRACKED(")).expect("actual generated declaration macro");
 let unchanged=include_str!("../../../../../code/defines/engine/capabilities.dm").lines().find(|line|line.starts_with("#define TRACKED_UNCHANGED(")).expect("actual generated setter equality macro");
 let list_macro=include_str!("../../../../../code/defines/host/_lists.dm").lines().find(|line|line.starts_with("#define LAZYADD(")).expect("actual authored lazy list mutation macro");
 let siblings=["LAZYREMOVE","LAZYOR","LAZYDISTINCTADD","LAZYSET","LAZYCLEARLIST","LAZYNULL"].into_iter().map(|name|{let prefix=format!("#define {name}(");include_str!("../../../../../code/defines/host/_lists.dm").lines().find(|line|line.starts_with(&prefix)).expect("actual authored list macro").to_string()}).collect::<Vec<_>>().join("\n");
 format!("{setter}\n{tracked}\n{unchanged}\n{list_macro}\n{siblings}\n/obj/box\n    var/list/items\n/obj/box/proc/add_items(value)\n    if(isnull(items))\n        items = list()\n    items += value\n/obj/box/proc/remove_items(value)\n    if(items)\n        items -= value\n        if(!length(items))\n            items = null\n/obj/box/proc/include_items(value)\n    if(!items)\n        items = list()\n    items |= value\n/obj/box/proc/set_items_at(key, value)\n    if(!items)\n        items = list()\n    items[key] = value\n/obj/box/proc/clear_items()\n    if(items)\n        items.Cut()\n        items = null\n")
}
const BEFORE:&str="/obj/box/proc/probe()\r\n    LAZYADD(items, 1) // authored trailing comment\r\n    return 0\r\n";
const AFTER:&str="/obj/box/proc/probe()\r\n    add_items(1) // authored trailing comment\r\n    return 0\r\n";
struct Fixture{root:PathBuf,request:Request}
fn put(root:&Path,relative:&str,bytes:impl AsRef<[u8]>){let path=root.join(relative);fs::create_dir_all(path.parent().unwrap()).unwrap();fs::write(path,bytes).unwrap();}
fn fixture(label:&str,body:&str,apply:bool)->Fixture{
 let root=fs::canonicalize(scratch::dir(label)).unwrap();let cache=fs::canonicalize(scratch::dir(&format!("{label}-cache"))).unwrap();for dir in ROOTS{fs::create_dir_all(root.join(dir)).unwrap();}
 fs::create_dir_all(root.join(dq_analyze::ui_actions_policy::INTERFACES)).unwrap();put(&root,"deepquarry.dme","#include \"code/definitions.dm\"\n#include \"code/_generated/auto_tracked.dm\"\n#include \"code/probe.dm\"\n");put(&root,"code/definitions.dm",definitions());put(&root,"code/_generated/auto_tracked.dm","TRACKED(/obj/box, items)\n");put(&root,"code/probe.dm",body);put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay(""));
 let Command::Build(build)=dmbc::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()else{panic!("actual public request parser")};let mut build:BuildRequest=*build;
 build.no_cache=true;build.exact_inputs=true;build.progress_enabled=false;build.workers=1;build.timeout_seconds=Some(60);build.engine_template=None;build.bootstrap_catalog=false;build.cache_root=Some(cache);
 build.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace_auxiliary:vec![WorkspaceAuxiliaryQuestion::Tracked],workspace:Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:ROOTS.map(|p|root.join(p)).to_vec(),configuration:root.join("tools/ci/lint_scopes.toml")}),..Default::default()});
 Fixture{root,request:Request{build,codemod:Codemod::TrackedListMacros,relative:"code/probe.dm".into(),apply}}
}
#[test]fn actual_native_list_macro_dry_run_then_in_place_apply_reprepares_same_host_and_preserves_crlf(){
 let mut f=fixture("native-list_macro-apply",BEFORE,false);let mut host=BuildHost::default();let(mut diagnostics,mut output)=(Vec::new(),Vec::new());
 native_fix::run(f.request.clone(),&mut host,&mut diagnostics,&mut output).unwrap();let report:serde_json::Value=serde_json::from_slice(&output).unwrap();
 assert_eq!(fs::read(f.root.join("code/probe.dm")).unwrap(),BEFORE.as_bytes());assert_eq!(report["committed"],false);assert_eq!(report["plan"]["edits"].as_array().unwrap().len(),1);assert_eq!(report["plan"]["edits"][0]["text"],"add_items(1)");assert!(report["text"].as_str().unwrap().ends_with("1 rewrite(s) (dry run; --apply writes them), 0 for hand conversion\n"));assert!(report["plan"].get("preimage").is_none());
 f.request.apply=true;output.clear();native_fix::run(f.request.clone(),&mut host,&mut diagnostics,&mut output).unwrap();let report:serde_json::Value=serde_json::from_slice(&output).unwrap();assert_eq!(report["committed"],true);assert_eq!(report["complete"],true);assert!(report["reprepared"].is_object());assert_eq!(fs::read(f.root.join("code/probe.dm")).unwrap(),AFTER.as_bytes());
 f.request.apply=false;output.clear();native_fix::run(f.request,&mut host,&mut diagnostics,&mut output).unwrap();let report:serde_json::Value=serde_json::from_slice(&output).unwrap();assert!(report["plan"]["edits"].as_array().unwrap().is_empty());assert_eq!(report["committed"],false);
}
#[test]fn actual_native_list_macro_mixed_unsupported_form_refuses_without_partial_source_write(){
 let body=BEFORE.replace("    return 0","    items.Add(2)\r\n    return 0");let f=fixture("native-list_macro-unsupported",&body,true);let mut host=BuildHost::default();let(mut diagnostics,mut output)=(Vec::new(),Vec::new());let error=native_fix::run(f.request,&mut host,&mut diagnostics,&mut output).unwrap_err();assert!(error.to_string().contains("other tracked write forms"),"{error}");assert!(output.is_empty());assert_eq!(fs::read(f.root.join("code/probe.dm")).unwrap(),body.as_bytes());
}
struct StopOutput;
impl Write for StopOutput{fn write(&mut self,_:&[u8])->io::Result<usize>{Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{Err(io::Error::from_raw_os_error(1450))}}
#[test]fn actual_native_list_macro_postcommit_output_io_reports_committed_and_keeps_reprepared_source(){
 use std::error::Error;
 let mut f=fixture("native-list_macro-output-failure",BEFORE,true);let mut host=BuildHost::default();let mut diagnostics=Vec::new();let error=native_fix::run(f.request.clone(),&mut host,&mut diagnostics,&mut StopOutput).unwrap_err();let committed=error.downcast_ref::<CommittedFailure>().expect("failure after actual replacement must carry committed=true");assert_eq!(committed.source().unwrap().downcast_ref::<io::Error>().unwrap().raw_os_error(),Some(1450));assert_eq!(fs::read(f.root.join("code/probe.dm")).unwrap(),AFTER.as_bytes());
 f.request.apply=false;let mut output=Vec::new();native_fix::run(f.request,&mut host,&mut diagnostics,&mut output).unwrap();let report:serde_json::Value=serde_json::from_slice(&output).unwrap();assert!(report["plan"]["edits"].as_array().unwrap().is_empty());
}

#[test]fn actual_native_list_macro_all_seven_use_same_captured_host_and_preserve_crlf(){
 let before="/obj/box/proc/probe()\r\n    LAZYADD(items, 1)\r\n    LAZYREMOVE(items, 1)\r\n    LAZYOR(items, 2)\r\n    LAZYDISTINCTADD(items, 3)\r\n    LAZYSET(items, 1, 4)\r\n    LAZYCLEARLIST(items)\r\n    LAZYNULL(items)\r\n    return 0\r\n";
 let after="/obj/box/proc/probe()\r\n    add_items(1)\r\n    remove_items(1)\r\n    include_items(2)\r\n    include_items(3)\r\n    set_items_at(1, 4)\r\n    clear_items()\r\n    set_items(null)\r\n    return 0\r\n";
 let f=fixture("native-list-macro-seven",before,true);let mut host=BuildHost::default();let(mut diagnostics,mut output)=(Vec::new(),Vec::new());native_fix::run(f.request.clone(),&mut host,&mut diagnostics,&mut output).unwrap();let report:serde_json::Value=serde_json::from_slice(&output).unwrap();assert_eq!(report["plan"]["edits"].as_array().unwrap().len(),7);assert_eq!(fs::read(f.root.join("code/probe.dm")).unwrap(),after.as_bytes());
 let mut preview=f.request;preview.apply=false;output.clear();native_fix::run(preview,&mut host,&mut diagnostics,&mut output).unwrap();let report:serde_json::Value=serde_json::from_slice(&output).unwrap();assert!(report["plan"]["edits"].as_array().unwrap().is_empty());
}
struct ChangeDuringPreview{path:PathBuf,bytes:Vec<u8>,time:std::time::SystemTime,changed:bool,output:Vec<u8>}
impl Write for ChangeDuringPreview{
 fn write(&mut self,bytes:&[u8])->io::Result<usize>{if !self.changed{fs::write(&self.path,&self.bytes)?;fs::File::options().write(true).open(&self.path)?.set_times(fs::FileTimes::new().set_modified(self.time))?;self.changed=true;}self.output.extend_from_slice(bytes);Ok(bytes.len())}fn flush(&mut self)->io::Result<()>{Ok(())}
}
#[test]fn actual_native_list_macro_preview_refuses_same_stamp_source_change_and_next_host_request_recovers(){
 let f=fixture("native-list-macro-stale-preview",BEFORE,false);let path=f.root.join("code/probe.dm");let original=fs::read(&path).unwrap();let changed=BEFORE.replace("items, 1","items, 2").into_bytes();assert_eq!(changed.len(),original.len());let time=fs::metadata(&path).unwrap().modified().unwrap();let mut sink=ChangeDuringPreview{path:path.clone(),bytes:changed.clone(),time,changed:false,output:Vec::new()};let mut host=BuildHost::default();let mut diagnostics=Vec::new();let error=native_fix::run(f.request.clone(),&mut host,&mut diagnostics,&mut sink).unwrap_err();assert!(sink.changed);assert!(error.to_string().contains("changed")||error.to_string().contains("input"),"{error}");assert_eq!(fs::read(&path).unwrap(),changed,"external change is not overwritten or rolled back");
 let mut output=Vec::new();native_fix::run(f.request,&mut host,&mut diagnostics,&mut output).unwrap();let report:serde_json::Value=serde_json::from_slice(&output).unwrap();assert_eq!(report["plan"]["edits"][0]["text"],"add_items(2)");
}
#[test]fn actual_native_list_macro_rejects_hardlink_before_mutation_then_same_host_recovers(){
 let f=fixture("native-list-macro-host-hardlink",BEFORE,true);let path=f.root.join("code/probe.dm");let alias=f.root.join("code/alias.dm");fs::hard_link(&path,&alias).unwrap();let mut host=BuildHost::default();let(mut diagnostics,mut output)=(Vec::new(),Vec::new());let error=native_fix::run(f.request.clone(),&mut host,&mut diagnostics,&mut output).unwrap_err();let failed=error.downcast_ref::<native_fix::FailedMutation>().expect("actual in-place refusal includes recovery status");assert!(!failed.may_have_changed);assert!(failed.recovered);assert_eq!(fs::read(&path).unwrap(),BEFORE.as_bytes());assert_eq!(fs::read(&alias).unwrap(),BEFORE.as_bytes());fs::remove_file(&alias).unwrap();native_fix::run(f.request,&mut host,&mut diagnostics,&mut output).unwrap();assert_eq!(fs::read(&path).unwrap(),AFTER.as_bytes());
}

#[test]fn actual_native_list_macro_resource_denial_before_mutation_then_credit_release_recovers_same_host(){
 let f=fixture("native-list-macro-resource",BEFORE,false);let mut host=BuildHost::default();let limit=host.source_arena_work().transformed_source_address_limit().unwrap();let pressure=host.source_arena_work().reserve(limit-512*1024).unwrap();let(mut diagnostics,mut output)=(Vec::new(),Vec::new());let error=native_fix::run(f.request.clone(),&mut host,&mut diagnostics,&mut output).unwrap_err();assert_eq!(error.downcast_ref::<io::Error>().unwrap().kind(),io::ErrorKind::OutOfMemory,"actual FIX resource failure: {error:?}; diagnostics: {}",String::from_utf8_lossy(&diagnostics));assert!(output.is_empty());assert_eq!(fs::read(f.root.join("code/probe.dm")).unwrap(),BEFORE.as_bytes());drop(pressure);native_fix::run(f.request,&mut host,&mut diagnostics,&mut output).unwrap();let report:serde_json::Value=serde_json::from_slice(&output).unwrap();assert_eq!(report["committed"],false);assert_eq!(report["plan"]["edits"].as_array().unwrap().len(),1);
}
