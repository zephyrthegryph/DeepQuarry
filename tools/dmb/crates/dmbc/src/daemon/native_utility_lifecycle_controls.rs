//! End-to-end utility lifecycle over the real retained backend and existing
//! codemod corpus. Uses the parent route's actual request/context/scratch owner.
use super::*;
use std::{error::Error,path::Path};

fn question(name:&str,apply:bool,revert:bool,write_residue:bool)->Question{
 Question::Codemod{name:name.into(),apply,revert,write_residue,sites:true,paths:Vec::new()}
}
fn execute(host:&mut BuildHost,base:&Request,question:Question)->Result<(i32,Vec<u8>,Vec<u8>),Box<dyn Error>>{
 let binding=Binding{schema:base.binding.schema,root:base.binding.root.clone(),question};
 let build=build_for_binding(&binding,base.build.cache_root.as_deref().expect("actual request cache"))?;
 let request=Request{build,binding};request.qualify()?;
 let report=host.stage_native_codemod_fixture(request.build,request.binding)?;
 let(mut stdout,mut stderr)=(Vec::new(),Vec::new());let exit=report.publish(&mut stdout,&mut stderr)?;
 Ok((exit,stdout,stderr))
}
fn install(root:&Path,stubs:&str,before:&str){
 std::fs::write(root.join("code/stubs.dm"),stubs.replace("\r\n","\n")).unwrap();
 std::fs::write(root.join("code/probe.dm"),before.replace("\r\n","\n")).unwrap();
 std::fs::write(root.join("deepquarry.dme"),b"#include \"code/stubs.dm\"\n#include \"code/probe.dm\"\n").unwrap();
}

#[test]
fn utility_actual_residue_keys_apply_and_revert_complete_one_real_lifecycle(){
 let(base,root)=request("utility-real-codemod-lifecycle",question("om_after",false,false,false));
 let before=include_str!("../../../../../analyze/codemods/om_after/fixtures/after_slot_residue.in.dm").replace("\r\n","\n");
 let after=include_str!("../../../../../analyze/codemods/om_after/fixtures/after_slot_residue.out.dm").replace("\r\n","\n");
 install(&root,include_str!("../../../../../analyze/codemods/om_after/fixtures/_stubs.dm"),&before);
 let _scope=context();let mut host=BuildHost::default();let undo=root.join("data/codemod/om_after");let reports=root.join("tools/analyze/codemods/om_after");
 let(exit,_,errors)=execute(&mut host,&base,question("om_after",false,false,false)).unwrap();
 assert_eq!(exit,1);assert!(String::from_utf8(errors).unwrap().contains("no committed residue.json"));
 assert_eq!(std::fs::read_to_string(root.join("code/probe.dm")).unwrap(),before);assert!(!undo.exists()&&!reports.exists(),"check must not manufacture undo or report directories");
 let(exit,_,errors)=execute(&mut host,&base,question("om_after",false,false,true)).unwrap();assert_eq!(exit,0);assert!(errors.is_empty());
 let residue_before=std::fs::read(reports.join("residue.json")).unwrap();let keys_before=std::fs::read(reports.join("keys.json")).unwrap();
 let residue:serde_json::Value=serde_json::from_slice(&residue_before).unwrap();let keys:serde_json::Value=serde_json::from_slice(&keys_before).unwrap();
 assert_eq!(residue["codemod"],"om_after");assert_eq!(residue["residue"],6);assert_eq!(residue["sites"].as_array().unwrap().len(),6);
 let mut actual:Vec<_>=residue["sites"].as_array().unwrap().iter().map(|site|site["reason"].as_str().unwrap()).collect();actual.sort_unstable();
 let mut expected:Vec<_>=include_str!("../../../../../analyze/codemods/om_after/fixtures/after_slot_residue.residue").lines().collect();expected.sort_unstable();assert_eq!(actual,expected,"actual captured corpus refusals are preserved");
 assert_eq!(keys["preserved"],1);assert_eq!(keys["unresolved"],0);assert_eq!(keys["keys"].as_array().unwrap().len(),1);assert_eq!(keys["keys"][0]["key"],"\"fine\"");
 assert!(!undo.join("revert.json").exists());assert_eq!(std::fs::read_to_string(root.join("code/probe.dm")).unwrap(),before,"residue generation is read-only on authored code");
 assert_eq!(execute(&mut host,&base,question("om_after",false,false,false)).unwrap().0,0,"actual committed residue enables check without rewriting the tree");
 assert_eq!(execute(&mut host,&base,question("om_after",true,false,false)).unwrap().0,0);
 assert_eq!(std::fs::read_to_string(root.join("code/probe.dm")).unwrap(),after);
 let record=std::fs::read(undo.join("revert.json")).unwrap();let parsed:serde_json::Value=serde_json::from_slice(&record).unwrap();
 assert_eq!(parsed["codemod"],"om_after");assert_eq!(parsed["files"].as_array().unwrap().len(),1);assert_eq!(parsed["files"][0]["file"],"code/probe.dm");assert!(!parsed["files"][0]["inverse"].as_array().unwrap().is_empty());
 assert_eq!(execute(&mut host,&base,question("om_after",false,false,true)).unwrap().0,0);
 assert_eq!(std::fs::read(undo.join("revert.json")).unwrap(),record,"residue refresh cannot overwrite an active undo record");
 assert_eq!(std::fs::read(reports.join("keys.json")).unwrap(),keys_before,"legacy leaves the last keys report when no new key uses remain");
 let residue_after=std::fs::read(reports.join("residue.json")).unwrap();let parsed_after:serde_json::Value=serde_json::from_slice(&residue_after).unwrap();assert_eq!(parsed_after["sites"],residue["sites"]);
 let(exit,output,errors)=execute(&mut host,&base,question("om_after",false,true,false)).unwrap();assert_eq!(exit,0);assert!(errors.is_empty());assert!(String::from_utf8(output).unwrap().contains("reverted 1 files"));
 assert_eq!(std::fs::read_to_string(root.join("code/probe.dm")).unwrap(),before,"actual authenticated inverse restores exact original bytes");assert!(!undo.join("revert.json").exists(),"successful revert removes only its authenticated record");
 assert_eq!(std::fs::read(reports.join("residue.json")).unwrap(),residue_after);assert_eq!(std::fs::read(reports.join("keys.json")).unwrap(),keys_before);
 assert_eq!(execute(&mut host,&base,question("om_after",false,false,false)).unwrap().0,0,"same retained host remains current after the removal transition");
}

#[test]
fn utility_actual_revert_hash_refusal_preserves_edited_code_and_live_record(){
 let(base,root)=request("utility-real-codemod-revert-hash",question("own_set",true,false,false));
 let before=include_str!("../../../../../analyze/codemods/own_set/fixtures/basic.in.dm").replace("\r\n","\n");let after=include_str!("../../../../../analyze/codemods/own_set/fixtures/basic.out.dm").replace("\r\n","\n");
 install(&root,include_str!("../../../../../analyze/codemods/own_set/fixtures/_stubs.dm"),&before);
 let _scope=context();let mut host=BuildHost::default();assert_eq!(execute(&mut host,&base,question("own_set",true,false,false)).unwrap().0,0);
 let record_path=root.join("data/codemod/own_set/revert.json");let record=std::fs::read(&record_path).unwrap();let changed=format!("{after}\n// actual edit after codemod apply\n");std::fs::write(root.join("code/probe.dm"),&changed).unwrap();
 let error=execute(&mut host,&base,question("own_set",false,true,false)).unwrap_err();assert!(error.to_string().contains("changed since the codemod wrote it"),"actual pre-write hash refusal: {error}");
 assert_eq!(std::fs::read_to_string(root.join("code/probe.dm")).unwrap(),changed,"refused revert cannot partially replace authored bytes");assert_eq!(std::fs::read(record_path).unwrap(),record,"failed inverse validation cannot remove its active undo record");
}
