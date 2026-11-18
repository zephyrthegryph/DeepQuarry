//! Actual utility route controls. Reuse existing codemod/fixture source corpus;
//! no fake model, second parser or synthetic successful completion is created.
use super::*;
use crate::runner_host::BuildHost;
use dq_analyze::native_codemod_fixture_wire::Question;
use std::{io::Write,path::PathBuf};
fn request(label:&str,question:Question)->(Request,PathBuf){
 let root=std::fs::canonicalize(crate::test_scratch::dir(label)).unwrap();let cache=std::fs::canonicalize(crate::test_scratch::dir(&format!("{label}-cache"))).unwrap();
 std::fs::create_dir_all(root.join("code")).unwrap();std::fs::create_dir_all(root.join("tools/ci")).unwrap();std::fs::write(root.join("tools/ci/lint_scopes.toml"),b"").unwrap();
 let binding=Binding{schema:dq_analyze::native_codemod_fixture_wire::Schema::V2,root:root.clone(),question};let build=build_for_binding(&binding,&cache).unwrap();let request=Request{build,binding};request.qualify().unwrap();(request,root)
}
fn context()->crate::daemon::control::Binding{crate::daemon::control::bind_with_deadline(crate::daemon::control::Cancellation::default(),std::time::Instant::now()+std::time::Duration::from_secs(120))}
fn first_os(error:&(dyn std::error::Error+'static))->Option<i32>{let mut cursor=Some(error);while let Some(error)=cursor{if let Some(code)=error.downcast_ref::<io::Error>().and_then(io::Error::raw_os_error){return Some(code)}cursor=error.source();}None}

#[test]fn utility_actual_metadata_list_publishes_clean_empty_stderr(){
 let(request,root)=request("utility-real-metadata-empty",Question::CodemodList);let _scope=context();let mut host=BuildHost::default();let report=host.stage_native_codemod_fixture(request.build,request.binding).unwrap();let(mut out,mut err)=(Vec::new(),Vec::new());assert_eq!(report.publish(&mut out,&mut err).unwrap(),0);assert!(err.is_empty());let out=String::from_utf8(out).unwrap();for name in ["own_set","own_add","om_after"]{assert!(out.contains(name),"actual registry list includes {name}");}assert!(!root.join("deepquarry.dme").exists(),"metadata cannot create/prepare a project");
}
#[test]fn utility_cancelled_metadata_report_cannot_revive_in_fresh_request_context(){
 let(request,_)=request("utility-real-metadata-cancel",Question::CodemodList);let token=crate::daemon::control::Cancellation::default();let scope=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(120));let mut host=BuildHost::default();let report=host.stage_native_codemod_fixture(request.build,request.binding).unwrap();drop(scope);token.cancel();
 let _fresh=context();let(mut out,mut err)=(Vec::new(),Vec::new());let error=report.publish(&mut out,&mut err).err().unwrap();assert!(error.downcast_ref::<io::Error>().is_some_and(|e|e.kind()==io::ErrorKind::Interrupted));assert!(out.is_empty()&&err.is_empty());
}
#[test]fn utility_actual_codemod_apply_output_failure_preserves_verified_source_mutation(){
 let question=Question::Codemod{name:"own_set".into(),apply:true,revert:false,write_residue:false,sites:false,paths:Vec::new()};let(request,root)=request("utility-real-codemod-output-fault",question);
 let stubs=include_str!("../../../../../analyze/codemods/own_set/fixtures/_stubs.dm").replace("\r\n","\n");let before=include_str!("../../../../../analyze/codemods/own_set/fixtures/basic.in.dm").replace("\r\n","\n");let after=include_str!("../../../../../analyze/codemods/own_set/fixtures/basic.out.dm").replace("\r\n","\n");
 std::fs::write(root.join("code/stubs.dm"),stubs).unwrap();std::fs::write(root.join("code/probe.dm"),&before).unwrap();std::fs::write(root.join("deepquarry.dme"),b"#include \"code/stubs.dm\"\n#include \"code/probe.dm\"\n").unwrap();
 let _scope=context();let mut host=BuildHost::default();let report=host.stage_native_codemod_fixture(request.build,request.binding).unwrap();assert_eq!(std::fs::read_to_string(root.join("code/probe.dm")).unwrap(),after,"actual existing codemod kernel converted the real corpus input");assert!(root.join("data/codemod/own_set/revert.json").is_file(),"actual missing parent chain + revert record committed");
 struct Denied{writes:usize}impl Write for Denied{fn write(&mut self,_:&[u8])->io::Result<usize>{self.writes+=1;Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{Err(io::Error::from_raw_os_error(1450))}}
 let mut out=Denied{writes:0};let mut err=Vec::new();let error=report.publish(&mut out,&mut err).err().unwrap();assert!(out.writes>0);assert_eq!(first_os(error.as_ref()),Some(1450));assert!(error.to_string().contains("committed mutations"));assert_eq!(std::fs::read_to_string(root.join("code/probe.dm")).unwrap(),after,"output IO cannot roll back truthful already-committed code");
}
#[test]fn utility_actual_fixture_uses_real_root_binding_and_selected_fixture_producer(){
 let(request,real)=request("utility-real-fixture-route",Question::Fixture{lint:"scheduler".into(),bless:false});let fixture=real.join("tools/analyze/fixtures/scheduler");std::fs::create_dir_all(fixture.join("code/modules/sched")).unwrap();
 std::fs::write(fixture.join("code/modules/sched/rules.dm"),include_str!("../../../../../analyze/fixtures/scheduler/code/modules/sched/rules.dm")).unwrap();
 assert_eq!(request.build.policy_inputs.as_ref().unwrap().workspace.as_ref().unwrap().root,real,"endpoint admits real repo, not a manually substituted fixture request");
 let _scope=context();let mut host=BuildHost::default();let report=host.stage_native_codemod_fixture(request.build,request.binding).unwrap();let(mut out,mut err)=(Vec::new(),Vec::new());assert_eq!(report.publish(&mut out,&mut err).unwrap(),0);assert!(String::from_utf8(out).unwrap().contains("findings\n"));assert!(!fixture.join("deepquarry.dme").exists(),"fixture uses native actual source closure without creating synthetic DME");
}
#[test]fn utility_request_qualifier_rejects_wrong_root_model_outputs_and_wire_unknown_fields(){
 let(actual,_)=request("utility-real-qualifier",Question::CodemodList);actual.qualify().unwrap();
 for case in 0..8{let mut build=actual.build.clone();match case{0=>build.project=build.project.with_file_name("foreign.dme"),1=>build.no_cache=false,2=>build.exact_inputs=false,3=>build.command=BuildCommand::Compile,4=>build.defines.insert("FOREIGN".into(),"1".into()).map(|_|()).unwrap_or(()),5=>build.policy_inputs.as_mut().unwrap().workspace.as_mut().unwrap().root.push("foreign"),6=>build.artifact_directory=build.cache_root.clone(),7=>build.source_questions=Some(Vec::new()),_=>unreachable!()};let request=Request{build,binding:actual.binding.clone()};assert!(request.qualify().is_err(),"tampered utility case {case} cannot obtain preparation authority");}
 let mut data=serde_json::to_value(&actual).unwrap();data.as_object_mut().unwrap().insert("forged_completed".into(),serde_json::Value::Bool(true));assert!(serde_json::from_value::<Request>(data).is_err());
}

#[test]fn utility_v2_long_request_applies_actual_codemod_and_sends_fixed_header_without_truncation(){
 let mut paths=vec!["code/".into()];paths.extend((0..200).map(|n|format!("code/not_selected_{n}/")));let question=Question::Codemod{name:"own_set".into(),apply:true,revert:false,write_residue:false,sites:false,paths};let(request,root)=request("utility-v2-long-request",question);assert!(request.binding.fingerprint().unwrap().bytes>dq_analyze::selected_exclusions_wire::MAX_HEADER as u64);
 let stubs=include_str!("../../../../../analyze/codemods/own_set/fixtures/_stubs.dm").replace("\r\n","\n");let before=include_str!("../../../../../analyze/codemods/own_set/fixtures/basic.in.dm").replace("\r\n","\n");let after=include_str!("../../../../../analyze/codemods/own_set/fixtures/basic.out.dm").replace("\r\n","\n");std::fs::write(root.join("code/stubs.dm"),stubs).unwrap();std::fs::write(root.join("code/probe.dm"),&before).unwrap();std::fs::write(root.join("deepquarry.dme"),b"#include \"code/stubs.dm\"\n#include \"code/probe.dm\"\n").unwrap();
 let _scope=context();let mut host=BuildHost::default();let report=host.stage_native_codemod_fixture(request.build,request.binding).unwrap();let mut wire=Vec::new();crate::daemon::selected_report_wire::send_native_codemod_fixture(&mut wire,report,host.source_arena_work()).unwrap();assert_eq!(std::fs::read_to_string(root.join("code/probe.dm")).unwrap(),after);assert!(wire.windows(b"native-codemod-fixture-v2".len()).any(|part|part==b"native-codemod-fixture-v2"));assert!(!wire.windows(b"native-codemod-fixture-v1".len()).any(|part|part==b"native-codemod-fixture-v1"));
}
#[test]fn utility_v2_cancelled_preflight_never_reaches_actual_codemod_writer(){
 let question=Question::Codemod{name:"own_set".into(),apply:true,revert:false,write_residue:false,sites:false,paths:vec!["code/".into()]};let(request,root)=request("utility-v2-preflight-cancel",question);std::fs::write(root.join("code/probe.dm"),b"preserve exact bytes\n").unwrap();let token=crate::daemon::control::Cancellation::default();let _scope=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(120));token.cancel();let mut host=BuildHost::default();let first=host.stage_native_codemod_fixture(request.build,request.binding).err().unwrap();assert!(first.downcast_ref::<io::Error>().is_some_and(|error|error.kind()==io::ErrorKind::Interrupted));assert_eq!(std::fs::read(root.join("code/probe.dm")).unwrap(),b"preserve exact bytes\n");assert!(!root.join("data/codemod").exists());
}

#[path="native_utility_lifecycle_controls.rs"]
mod lifecycle_controls;

#[test]fn utility_actual_semantic_child_keeps_full_subject_without_reissuing_workspace_intent(){
 use crate::policy_request::{AnalysisContext,PolicyInputRequest};
 // The outer Analyze constructor still requires a genuine workspace intent.
 assert!(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),..Default::default()}.admit().is_err());
 let question=Question::Codemod{name:"own_set".into(),apply:false,revert:false,write_residue:false,sites:false,paths:Vec::new()};let(request,real)=request("utility-real-semantic-child-intent",question);request.qualify().unwrap();assert_eq!(request.build.policy_inputs.as_ref().unwrap().workspace.as_ref().unwrap().root,real);
 let stubs=include_str!("../../../../../analyze/codemods/own_set/fixtures/_stubs.dm").replace("\r\n","\n");let before=include_str!("../../../../../analyze/codemods/own_set/fixtures/basic.in.dm").replace("\r\n","\n");std::fs::write(real.join("code/stubs.dm"),stubs).unwrap();std::fs::write(real.join("code/probe.dm"),&before).unwrap();std::fs::write(real.join("deepquarry.dme"),b"#include \"code/stubs.dm\"\n#include \"code/probe.dm\"\n").unwrap();
 let _scope=context();let mut host=BuildHost::default();let report=host.stage_native_codemod_fixture(request.build,request.binding).unwrap();
 report.into_delivery(|binding,_request,frame,_exit,committed,_out,_err,current|{
  current().unwrap();assert_eq!(binding.root,real);assert_eq!(committed,0);assert!(matches!(frame,Some(dq_analyze::native_codemod_fixture_wire::SourceFrame::Semantic{completeness:dq_analyze::native_codemod_fixture_wire::OriginalCompleteness::Complete,..})),"actual Original semantic producer supplies completion, not empty child intent");Ok(())
 }).unwrap();assert_eq!(std::fs::read_to_string(real.join("code/probe.dm")).unwrap(),before);assert!(!real.join("data/codemod/own_set/revert.json").exists());
}
