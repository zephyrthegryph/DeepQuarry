//! Real native pipeline controls for the opt-in standalone text core, not oracle parity.
#[path="../../../shared/test_scratch.rs"]mod scratch;
use dmbc::{native_checker::{self,Request},runner_host::BuildHost};
use std::{fs,io::{self,Write},path::PathBuf};
#[global_allocator]static ALLOC:mimalloc::MiMalloc=mimalloc::MiMalloc;
fn fixture(name:&str,source:&str,configuration:&str)->(Request,PathBuf){
 let root=scratch::dir(name);let cache=scratch::dir(&format!("{name}-cache"));let project=root.join("project.dme");fs::write(&project,source).unwrap();fs::write(root.join("SpacemanDMM.toml"),configuration).unwrap();
 (Request{project:project.clone(),configuration:None,cache_root:cache,workers:1,timeout_seconds:60},project)
}
#[test]fn actual_standalone_checker_clean_full_scope_and_pinned_text_summary(){
 let(request,_)=fixture("native-checker-cli-clean","/proc/probe()\n    return 1\n","");let mut host=BuildHost::default();let(mut out,mut err)=(Vec::new(),Vec::new());
 let result=native_checker::run(request,&mut host,&mut out,&mut err).unwrap();assert_eq!(result.exit_code,0);assert_eq!(result.emitted,0);assert_eq!(result.visited_bodies,1);assert!(!result.full_checker_parity);assert!(err.is_empty());
 let out=String::from_utf8(out).unwrap();for marker in ["Analyzing variables...","Gathering proc settings...","Analyzing proc bodies...","Analyzing proc override validity...","Analyzing proc call tree..."]{assert_eq!(out.matches(marker).count(),1)}assert!(out.ends_with("Found 0 diagnostics\n"));
}
#[test]fn actual_standalone_checker_visible_error_is_complete_nonzero_not_operational_failure(){
 let(request,_)=fixture("native-checker-cli-error","/proc/probe()\n    return missing_value\n","");let mut host=BuildHost::default();let(mut out,mut err)=(Vec::new(),Vec::new());let result=native_checker::run(request,&mut host,&mut out,&mut err).unwrap();
 assert_eq!(result.exit_code,1);assert_eq!(result.emitted,1);let err=String::from_utf8(err).unwrap();assert!(err.contains(", line 2, column "));assert!(err.contains("error: undefined var: \"missing_value\"\n\n"));assert!(String::from_utf8(out).unwrap().ends_with("Found 1 diagnostics\n"));
}
#[test]fn actual_standalone_checker_typed_preprocess_notice_obeys_same_captured_policy(){
 let source="#define A 1\n#define A 2\n/proc/probe()\n    return A\n";
 let(request,_)=fixture("native-checker-cli-preprocess",source,"");let mut host=BuildHost::default();let(mut out,mut err)=(Vec::new(),Vec::new());let result=native_checker::run(request,&mut host,&mut out,&mut err).unwrap();assert_eq!(result.exit_code,1);assert_eq!(result.emitted,1);assert!(String::from_utf8(err).unwrap().contains("warning: macro redefined: A"));
 let(request,_)=fixture("native-checker-cli-preprocess-disabled",source,"[diagnostics]\nmacro_redefined = \"disabled\"\n");out.clear();let mut err=Vec::new();let result=native_checker::run(request,&mut host,&mut out,&mut err).unwrap();assert_eq!(result.exit_code,0);assert!(err.is_empty());
}
struct FailedOutput;
impl Write for FailedOutput{fn write(&mut self,_:&[u8])->io::Result<usize>{Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{panic!("no flush after actual first write error")}}
#[test]fn actual_standalone_checker_first_output_io_is_preserved_and_same_host_recovers(){
 let(request,_)=fixture("native-checker-cli-output-io","/proc/probe()\n    return missing_value\n","");let mut host=BuildHost::default();let mut out=Vec::new();let error=native_checker::run(request.clone(),&mut host,&mut out,&mut FailedOutput).unwrap_err();assert_eq!(error.downcast_ref::<io::Error>().unwrap().raw_os_error(),Some(1450));assert!(!String::from_utf8(out).unwrap().contains("Found "));
 let(mut out,mut err)=(Vec::new(),Vec::new());assert_eq!(native_checker::run(request,&mut host,&mut out,&mut err).unwrap().exit_code,1);
}
struct Restore{path:PathBuf,bytes:Vec<u8>,modified:std::time::SystemTime}
impl Drop for Restore{fn drop(&mut self){fs::write(&self.path,&self.bytes).unwrap();fs::OpenOptions::new().write(true).open(&self.path).unwrap().set_times(fs::FileTimes::new().set_modified(self.modified)).unwrap();}}
struct ChangeSource{path:PathBuf,modified:std::time::SystemTime,changed:bool,bytes:Vec<u8>}
impl Write for ChangeSource{fn write(&mut self,bytes:&[u8])->io::Result<usize>{self.bytes.extend_from_slice(bytes);if !self.changed{self.changed=true;let old=fs::read(&self.path)?;let new=String::from_utf8(old).unwrap().replace("missing_value","missing_other");fs::write(&self.path,new)?;fs::OpenOptions::new().write(true).open(&self.path)?.set_times(fs::FileTimes::new().set_modified(self.modified))?;}Ok(bytes.len())}fn flush(&mut self)->io::Result<()>{Ok(())}}
#[test]fn actual_standalone_checker_same_size_mtime_restored_change_during_output_refuses_success(){
 let(request,path)=fixture("native-checker-cli-output-stale","/proc/probe()\n    return missing_value\n","");let restore=Restore{path:path.clone(),bytes:fs::read(&path).unwrap(),modified:fs::metadata(&path).unwrap().modified().unwrap()};let mut host=BuildHost::default();let mut out=Vec::new();let mut sink=ChangeSource{path,modified:restore.modified,changed:false,bytes:Vec::new()};
 let error=native_checker::run(request,&mut host,&mut out,&mut sink).unwrap_err();assert!(sink.changed);assert!(error.to_string().contains("changed")||error.to_string().contains("stale"),"{error}");assert!(!String::from_utf8(out).unwrap().contains("Found "));drop(restore);
}

// Authored fixtures for eventual native + independently pinned execution.
// These tests are native expected-contract controls; their existence does NOT
// claim that the pinned executable has been run or parity established.
fn causal_order(text:&str,markers:&[&str]){
 let mut previous=0usize;
 for marker in markers{let next=text[previous..].find(marker).map(|n|previous+n).unwrap_or_else(||panic!("missing actual registration {marker:?} in {text:?}"));previous=next+marker.len();}
}
#[test]
fn actual_standalone_checker_causal_formals_includes_macros_and_numeric_lookahead(){
 for(name,source,child,expected)in[
  ("native-causal-formal","#warn EARLY\n/proc/probe(static/value)\n    return value\n#warn LATE\n",None,vec!["#warn EARLY","'static/' has no effect here","#warn LATE"]),
  ("native-causal-include","#warn EARLY\n#include \"child.dm\"\n#warn LATE\n",Some("/proc/probe(static/value)\n    return value\n"),vec!["#warn EARLY","'static/' has no effect here","#warn LATE"]),
  ("native-causal-macro","#define ARG static/value\n#warn EARLY\n/proc/probe(ARG)\n    return value\n#warn LATE\n",None,vec!["#warn EARLY","'static/' has no effect here","#warn LATE"]),
  ("native-causal-default","#warn EARLY\n/proc/probe(static/value=2147483649)\n    return value\n#warn LATE\n",None,vec!["#warn EARLY","'static/' has no effect here","precision loss of integer constant:","#warn LATE"]),
 ]{
  let(request,project)=fixture(name,source,"");
  if let Some(child)=child{fs::write(project.parent().unwrap().join("child.dm"),child).unwrap();}
  let mut host=BuildHost::default();let(mut out,mut err)=(Vec::new(),Vec::new());
  let result=native_checker::run(request,&mut host,&mut out,&mut err).unwrap();
  assert_eq!(result.exit_code,1);assert!(!result.full_checker_parity);
  causal_order(&String::from_utf8(err).unwrap(),&expected);
  assert!(String::from_utf8(out).unwrap().contains("Found "));
 }
}
#[test]
fn actual_standalone_checker_duplicate_registration_follows_body_and_trailing_pp_at_actual_eof(){
 let source="/datum/x/proc/probe()\n    return 0\n/datum/x/proc/probe()\n    #warn BODY\n    return 1\n#warn TAIL\n";
 let(request,_)=fixture("native-causal-duplicate-eof",source,"");let mut host=BuildHost::default();let(mut out,mut err)=(Vec::new(),Vec::new());
 let result=native_checker::run(request,&mut host,&mut out,&mut err).unwrap();assert_eq!(result.exit_code,1);assert!(!result.full_checker_parity);
 causal_order(&String::from_utf8(err).unwrap(),&["#warn BODY","#warn TAIL","duplicate definition of proc/probe"]);
 assert!(String::from_utf8(out).unwrap().contains("Found "));
}

#[test]
fn actual_standalone_checker_dynamic_dispatch_receipts_drive_real_body_queries(){
 let source="/proc/dynamic_value(proc_ref, list/call_args)\n    return call(proc_ref)(arglist(call_args || list()))\n/proc/dynamic_effect(E, proc_ref, list/call_args)\n    call(E, proc_ref)(arglist(call_args || list()))\n    return 0\n";
 let(request,_)=fixture("native-checker-cli-dynamic-dispatch",source,"");let mut host=BuildHost::default();let(mut out,mut err)=(Vec::new(),Vec::new());
 let result=native_checker::run(request,&mut host,&mut out,&mut err).unwrap();
 assert_eq!(result.exit_code,0,"{}",String::from_utf8_lossy(&err));assert_eq!(result.visited_bodies,2);assert_eq!(result.emitted,0);assert!(err.is_empty());assert!(!result.full_checker_parity);
 assert!(String::from_utf8(out).unwrap().ends_with("Found 0 diagnostics\n"));
}

#[test]
fn actual_standalone_checker_builtin_call_result_field_read_uses_real_current_body(){
 // get_step is the actual fixed builtin, not a synthetic content helper/stub.
 // Its target is a genuine typed atom; x/y are the actual builtin coordinate
 // fields. This tests the new call-result follower through the public core.
 let source="/proc/read_call_member(atom/source)\n    return get_step(source,1).x + get_step(source,1).y\n";
 let(request,_)=fixture("native-call-member-builtin",source,"");let mut host=BuildHost::default();let(mut out,mut err)=(Vec::new(),Vec::new());
 let result=native_checker::run(request,&mut host,&mut out,&mut err).unwrap();
 assert_eq!(result.exit_code,0);assert_eq!(result.emitted,0);assert_eq!(result.visited_bodies,1);assert!(!result.full_checker_parity);assert!(err.is_empty(),"{}",String::from_utf8_lossy(&err));assert!(String::from_utf8(out).unwrap().ends_with("Found 0 diagnostics\n"));
}


#[test]
fn actual_standalone_checker_indexed_arithmetic_update_uses_real_current_body(){
 let source="/proc/update_index(list/values)\n    values[1] -= values[1] >> 8\n    return 0\n";
 let(request,_)=fixture("native-indexed-arithmetic",source,"");let mut host=BuildHost::default();let(mut out,mut err)=(Vec::new(),Vec::new());
 let result=native_checker::run(request,&mut host,&mut out,&mut err).unwrap();assert_eq!(result.exit_code,0,"{}",String::from_utf8_lossy(&err));assert_eq!(result.emitted,0);assert_eq!(result.visited_bodies,1);assert!(!result.full_checker_parity);assert!(err.is_empty());assert!(String::from_utf8(out).unwrap().ends_with("Found 0 diagnostics\n"));
}

#[test]
fn actual_standalone_checker_static_new_statement_reuses_existing_constructor_proof(){
 let source="/proc/create_object()\n    new/obj()\n    return 0\n";
 let(request,_)=fixture("native-static-new-statement",source,"");let mut host=BuildHost::default();let(mut out,mut err)=(Vec::new(),Vec::new());
 let result=native_checker::run(request,&mut host,&mut out,&mut err).unwrap();assert_eq!(result.exit_code,0,"{}",String::from_utf8_lossy(&err));assert_eq!(result.emitted,0);assert_eq!(result.visited_bodies,1);assert!(!result.full_checker_parity);assert!(err.is_empty());assert!(String::from_utf8(out).unwrap().ends_with("Found 0 diagnostics\n"));
}

#[path="../../../shared/test_native_transport.rs"]mod native_transport;
fn checker_transport_payload<'a>(bytes:&'a[u8],project:&std::path::Path)->(dq_analyze::native_checker_wire::Terminal,&'a[u8],&'a[u8]){
 let end=bytes.iter().position(|b|*b==b'\n').expect("actual bounded terminal");let terminal:dq_analyze::native_checker_wire::Terminal=serde_json::from_slice(&bytes[..end]).unwrap();terminal.require(project).unwrap();let payload=&bytes[end+1..];let diagnostic=usize::try_from(terminal.diagnostics.as_ref().map_or(0,|s|s.length)).unwrap();assert_eq!(diagnostic+usize::try_from(terminal.output.length).unwrap(),payload.len());let(diagnostics,output)=payload.split_at(diagnostic);assert!(terminal.diagnostics.as_ref().is_none_or(|seal|seal.hash.0==xxhash_rust::xxh3::xxh3_128(diagnostics)));assert_eq!(terminal.output.hash.0,xxhash_rust::xxh3::xxh3_128(output));(terminal,diagnostics,output)
}
fn checker_transport_pid(root:&std::path::Path)->u64{let mut rows=Vec::new();for entry in fs::read_dir(root.join("daemon/live")).unwrap(){let path=entry.unwrap().path();if path.extension()==Some(std::ffi::OsStr::new("json")){let value:serde_json::Value=serde_json::from_slice(&fs::read(path).unwrap()).unwrap();rows.push(value["pid"].as_u64().expect("actual live daemon PID"));}}assert_eq!(rows.len(),1,"only the existing private test namespace daemon");rows[0]}
#[test]
#[ignore="private native IPC; run exact outside Cargo under dm_compile machine slot"]
fn actual_resident_checker_reuses_one_daemon_and_seals_semantic_output_without_trace_contamination(){
 use std::{ffi::OsStr,time::Duration};let root=scratch::dir("resident-checker-source");let project=root.join("project.dme");fs::write(&project,"/proc/probe()\n    return 1\n").unwrap();fs::write(root.join("SpacemanDMM.toml"),"").unwrap();let canonical_project=fs::canonicalize(&project).unwrap();
 let transport_root=scratch::dir("resident-checker-transport");let transport=native_transport::LibraryTransport{root:&transport_root,namespace:format!("resident-checker-{}",std::process::id())};let arguments=[OsStr::new("checker-text"),OsStr::new("-e"),project.as_os_str()];
 let first=transport.run_program_with_trace(std::path::Path::new(env!("CARGO_BIN_EXE_dmbc")),&arguments,Duration::from_secs(90),true).unwrap();assert_eq!(first.status.code(),Some(0),"{}",String::from_utf8_lossy(&first.stderr));assert!(first.stderr.is_empty(),"operational logs must remain lifecycle output: {}",String::from_utf8_lossy(&first.stderr));let(first_terminal,diagnostic,output)=checker_transport_payload(&first.stdout,&canonical_project);assert_eq!(first_terminal.emitted,0);assert_eq!(first_terminal.visited_bodies,1);assert!(diagnostic.is_empty());assert!(output.ends_with(b"Found 0 diagnostics\n"));assert!(String::from_utf8_lossy(output).contains(&format!("Parsing {}...",project.display())),"display spelling stays authored while canonical identity is real");let pid=checker_transport_pid(&transport_root);
 fs::write(&project,"/proc/probe()\n    return missing_value\n").unwrap();let second=transport.run_program(std::path::Path::new(env!("CARGO_BIN_EXE_dmbc")),&arguments,Duration::from_secs(90)).unwrap();assert_eq!(second.status.code(),Some(1),"{}",String::from_utf8_lossy(&second.stderr));assert!(second.stderr.is_empty());let(second_terminal,diagnostic,output)=checker_transport_payload(&second.stdout,&canonical_project);assert_eq!(second_terminal.emitted,1);assert!(String::from_utf8_lossy(diagnostic).contains("undefined var: \"missing_value\""));assert!(output.ends_with(b"Found 1 diagnostics\n"));assert_ne!(first_terminal.frame.source_revision,second_terminal.frame.source_revision);assert_eq!(checker_transport_pid(&transport_root),pid,"same real resident process handles changed source");
 let json_arguments=[OsStr::new("checker-text"),OsStr::new("-e"),project.as_os_str(),OsStr::new("--json")];let json=transport.run_program(std::path::Path::new(env!("CARGO_BIN_EXE_dmbc")),&json_arguments,Duration::from_secs(90)).unwrap();assert_eq!(json.status.code(),Some(1));assert!(json.stderr.is_empty());let(json_terminal,diagnostic,output)=checker_transport_payload(&json.stdout,&canonical_project);assert!(json_terminal.json);assert_eq!(json_terminal.emitted,1);assert!(output.ends_with(b"Found 1 diagnostics\n{\"error\":1,\"hint\":0,\"info\":0,\"warning\":0}"));assert_eq!(checker_transport_pid(&transport_root),pid,"same actual daemon serves JSON without another parser host");
 if cfg!(debug_assertions){let lifecycle=fs::read_to_string(transport_root.join("daemon/lifecycle.log")).unwrap();assert!(lifecycle.contains("ORIGINAL_ADAPTER_CREDIT stage=before_adapt"),"existing original tracing must remain observable");assert!(!String::from_utf8_lossy(output).contains("ORIGINAL_ADAPTER_CREDIT"));assert!(!String::from_utf8_lossy(diagnostic).contains("ORIGINAL_ADAPTER_CREDIT"));}
 for entry in fs::read_dir(&root).unwrap(){let path=entry.unwrap().path();assert!(!matches!(path.extension().and_then(|s|s.to_str()),Some("dmb"|"rsc")),"Checker must not publish executable products")}
}

#[test]fn actual_standalone_checker_json_counts_hidden_preprocess_hint_and_visible_body_error(){
 let(request,_)=fixture("native-checker-json-registered","#define A 1\n#define A 2\n/proc/probe()\n    return missing_value\n","[diagnostics]\nmacro_redefined = \"hint\"\n");
 let mut host=BuildHost::default();let(mut out,mut err)=(Vec::new(),Vec::new());let result=native_checker::run_with_json(request,true,&mut host,&mut out,&mut err).unwrap();assert!(result.json);assert_eq!(result.exit_code,1);assert_eq!(result.emitted,1);assert_eq!(result.visited_bodies,1);
 let text=String::from_utf8(out).unwrap();assert!(text.ends_with("Found 1 diagnostics\n{\"error\":1,\"hint\":1,\"info\":0,\"warning\":0}"),"{text}");let err=String::from_utf8(err).unwrap();assert!(err.contains("undefined var: \"missing_value\""));assert!(!err.contains("macro redefined"),"hidden hint remains a genuine registered count without semantic text");assert!(!result.full_checker_parity);
}

#[test]
fn actual_standalone_checker_variadic_formal_keeps_issued_original_header(){
 let(request,_)=fixture("native-checker-cli-variadic-formal","/proc/probe(...)\n    return\n","");let mut host=BuildHost::default();let(mut out,mut err)=(Vec::new(),Vec::new());
 let result=native_checker::run(request,&mut host,&mut out,&mut err).unwrap();
 assert_eq!(result.exit_code,0,"{}",String::from_utf8_lossy(&err));assert_eq!(result.visited_bodies,1);assert_eq!(result.emitted,0);assert!(!result.full_checker_parity);assert!(err.is_empty());
 assert!(String::from_utf8(out).unwrap().ends_with("Found 0 diagnostics\n"));
}

#[test]
fn actual_standalone_checker_bare_postfix_read_values_keep_real_effects_and_full_bodies(){
 for(name,source)in[
  ("postfix-return","/proc/probe(safety)\n    return safety--\n"),
  ("postfix-negated","/proc/probe(safety)\n    return !safety--\n"),
  ("postfix-write-key","/proc/probe(list/path, index, value)\n    path[index--] = value\n    return index\n"),
  ("postfix-interpolation","/proc/probe(i)\n    return \"[i++]\"\n"),
 ]{
  let(request,_)=fixture(name,source,"");let mut host=BuildHost::default();let(mut out,mut err)=(Vec::new(),Vec::new());
  let result=native_checker::run(request,&mut host,&mut out,&mut err).unwrap();
  assert_eq!(result.exit_code,0,"{name}: {}",String::from_utf8_lossy(&err));assert_eq!(result.emitted,0,"{name}");
  assert_eq!(result.visited_bodies,1,"{name}");assert!(!result.full_checker_parity);
  assert!(String::from_utf8(out).unwrap().ends_with("Found 0 diagnostics\n"));assert!(err.is_empty());
 }
}

#[test]fn actual_standalone_checker_absolute_static_new_without_arguments_keeps_real_target(){
 let source="/datum/seed_pile\n/proc/probe()\n    var/datum/seed_pile/P = new /datum/seed_pile\n    return P\n";
 let(request,_)=fixture("absolute-static-new-absent",source,"");let mut host=BuildHost::default();let(mut out,mut err)=(Vec::new(),Vec::new());
 let result=native_checker::run(request,&mut host,&mut out,&mut err).unwrap();assert_eq!(result.exit_code,0,"{}",String::from_utf8_lossy(&err));assert_eq!(result.emitted,0);assert_eq!(result.visited_bodies,1);assert!(!result.full_checker_parity);assert!(err.is_empty());
 assert!(String::from_utf8(out).unwrap().ends_with("Found 0 diagnostics\n"));
}

#[test]fn actual_standalone_checker_bare_loop_controls_use_real_owned_layout_terminators(){
 for(name,source)in[
  ("owned-break-followed","/proc/probe(value)\n    while(value)\n        break\n    return 0\n"),
  ("owned-continue-followed","/proc/probe(value)\n    while(value)\n        continue\n    return 0\n"),
  ("owned-break-end","/proc/probe(value)\n    while(value)\n        break\n"),
 ]{
  let(request,_)=fixture(name,source,"");let mut host=BuildHost::default();let(mut out,mut err)=(Vec::new(),Vec::new());
  let result=native_checker::run(request,&mut host,&mut out,&mut err).unwrap();assert_eq!(result.exit_code,0,"{name}: {}",String::from_utf8_lossy(&err));assert_eq!(result.emitted,0);assert_eq!(result.visited_bodies,1);assert!(!result.full_checker_parity);assert!(err.is_empty());assert!(String::from_utf8(out).unwrap().ends_with("Found 0 diagnostics\n"));
 }
}

#[test]fn actual_standalone_checker_member_safe_index_uses_real_member_then_safe_key(){
 let source="/datum/holder\n    var/list/factors\n/proc/probe(datum/holder/other_trait, id)\n    return !isnull(other_trait.factors?[id])\n";
 let(request,_)=fixture("member-safe-index-read",source,"");let mut host=BuildHost::default();let(mut out,mut err)=(Vec::new(),Vec::new());let result=native_checker::run(request,&mut host,&mut out,&mut err).unwrap();
 assert_eq!(result.exit_code,0,"{}",String::from_utf8_lossy(&err));assert_eq!(result.emitted,0);assert_eq!(result.visited_bodies,1);assert!(!result.full_checker_parity);assert!(err.is_empty());assert!(String::from_utf8(out).unwrap().ends_with("Found 0 diagnostics\n"));
}

#[test]#[ignore="actual resident IPC; parent runs bounded focused target"]
fn actual_resident_checker_resolves_each_caller_cwd_and_autodetect_without_using_daemon_cwd(){
 use std::{ffi::OsStr,path::Path,time::Duration};let first=fs::canonicalize(scratch::dir("checker-caller-first")).unwrap();let second=fs::canonicalize(scratch::dir("checker-caller-second")).unwrap();
 fs::write(first.join("project.dme"),"/proc/probe()\n    return 1\n").unwrap();fs::write(second.join("project.dme"),"/proc/probe()\n    return missing_value\n").unwrap();fs::write(second.join("tgstation.dme"),"not the preferred environment\n").unwrap();fs::write(second.join("cfg.toml"),"").unwrap();
 let transport_root=fs::canonicalize(scratch::dir("checker-caller-transport")).unwrap();let transport=native_transport::LibraryTransport{root:&transport_root,namespace:format!("checker-callers-{}",std::process::id())};let program=Path::new(env!("CARGO_BIN_EXE_dmbc"));
 let args=[OsStr::new("checker-text"),OsStr::new("-e"),OsStr::new("./project.dme")];let a=transport.run_program_in(program,&args,Duration::from_secs(90),&first).unwrap();assert_eq!(a.status.code(),Some(0),"{}",String::from_utf8_lossy(&a.stderr));assert!(a.stderr.is_empty());let(_,d,o)=checker_transport_payload(&a.stdout,&fs::canonicalize(first.join("project.dme")).unwrap());assert!(d.is_empty());assert!(String::from_utf8_lossy(o).contains("Parsing ./project.dme..."));let pid=checker_transport_pid(&transport_root);
 let args=[OsStr::new("checker-text"),OsStr::new("-c"),OsStr::new("cfg.toml")];let b=transport.run_program_in(program,&args,Duration::from_secs(90),&second).unwrap();assert_eq!(b.status.code(),Some(1),"{}",String::from_utf8_lossy(&b.stderr));assert!(b.stderr.is_empty());let(t,d,o)=checker_transport_payload(&b.stdout,&fs::canonicalize(second.join("project.dme")).unwrap());assert_eq!(t.emitted,1);assert!(String::from_utf8_lossy(d).contains("undefined var: \"missing_value\""));assert!(String::from_utf8_lossy(o).contains("Parsing project.dme..."));assert_eq!(checker_transport_pid(&transport_root),pid,"physical project follows second caller while existing daemon remains the same process");
 let unknown=[OsStr::new("checker-text"),OsStr::new("-e"),OsStr::new("absent.dme"),OsStr::new("--unknown")];let c=transport.run_program_in(program,&unknown,Duration::from_secs(10),&second).unwrap();assert_eq!(c.status.code(),Some(0));assert!(c.stdout.is_empty(),"early argument action is not a completed Checker terminal");assert_eq!(String::from_utf8(c.stderr).unwrap().trim(),"unknown argument: --unknown");
}
