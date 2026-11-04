//! Whole old sem=None control through an actual failed second physical reader.
//! No native source/model/absence constructor is available here.
use super::*;
#[path="../examples/support/deps_original/reaction_producer.rs"]mod original;
#[path="../../dmb/shared/test_scratch.rs"]mod scratch;
struct Pages<'a>{tree:&'a crate::tree::Tree,config:Option<&'a crate::captured_raw_file::Config>,fail:std::cell::Cell<bool>,stop:bool}
impl crate::reactive_raw_policy_pages::RawPolicyPages for Pages<'_>{
 fn for_each(&self,visit:&mut dyn FnMut(&str,crate::captured_raw_file::RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{
  if self.fail.get(){return Err(Failure::Operational(io::Error::from_raw_os_error(1450)))}
  for file in self.tree.select(&crate::tree::CODE_DM){if self.config.is_some_and(|c|c.policy_path_exempt("derived_reads",metadata().group,&file.rel)){continue}if !visit(&file.rel,crate::captured_raw_file::RawPolicyViews::from_source(file))?{return Ok(false)}}Ok(!self.stop)
 }
}
fn run(stale:bool,bom:bool){
 let root=scratch::dir("derived-authentic-unavailable-raw");std::fs::create_dir_all(root.join("code/_generated")).unwrap();std::fs::create_dir_all(root.join("tools/ci")).unwrap();
 let seed="/obj/probe\n    var/value\n    var/missing\n    var/link\n/obj/probe/derived()\n    return list(drawn_from(nameof(value), rel(nameof(link), nameof(/datum/far::v))))\n/obj/probe/draw()\n    return missing\n/obj/probe/ui_data()\n    return list(value)\n/obj/probe/on_state_changed()\n    return\n/mob/probe\n    var/custom_health\n/mob/probe/life_hud()\n    return custom_health\n/obj/probe/child/draw()\n    // ALLOW(derived_reads): intentional oracle raw read retained for parity\n    return missing\n";
 // Preserve the original BOM/CRLF file verbatim. The frozen raw header
 // matcher does not recognize CRLF procedure headers; an independent LF
 // witness makes refusal and ALLOW assertions nonvacuous without changing it.
 if bom{std::fs::write(root.join("code/witness.dm"),"/obj/unavailable_witness\n    var/observed\n/obj/unavailable_witness/ui_data()\n    return list(observed)\n/obj/unavailable_witness/child/ui_data()\n    // ALLOW(derived_reads): intentional LF witness for actual unavailable semantics\n    return list(observed)\n").unwrap();}
 let seed=if bom{format!("\u{feff}{}",seed.replace("\n","\r\n"))}else{seed.into()};std::fs::write(root.join("code/probe.dm"),seed).unwrap();std::fs::write(root.join("deepquarry.dme"),"#include \"code/probe.dm\"\n#include \"code/_generated/reads.dm\"\n").unwrap();std::fs::write(root.join("tools/ci/lint_scopes.toml"),"").unwrap();std::fs::write(root.join("code/_generated/reads.dm"),"// actual stale raw output\n").unwrap();
 let mut registry=crate::lint::Registry::default();original::register(&mut registry);let engine=crate::run::Engine::new(registry,crate::run::Options{root:root.clone(),raw:true,lints:vec!["derived_reads".into()],..Default::default()}).unwrap();
 if !stale{let want=original::generated_for(&engine.tree,&engine.tree.select(&crate::tree::CODE_DM));std::fs::write(root.join("code/_generated/reads.dm"),want).unwrap();}
 drop(engine);let mut registry=crate::lint::Registry::default();original::register(&mut registry);let engine=crate::run::Engine::new(registry,crate::run::Options{root:root.clone(),raw:true,lints:vec!["derived_reads".into()],..Default::default()}).unwrap();
 let failure=crate::sem::delete_after_real_marker_for_derived_oracle(&engine.tree).unwrap();assert!(failure.contains("deepquarry.dme"));assert!(crate::sem::sem_for(&engine.tree).is_none());
 let old=engine.run_one(engine.reg.find("derived_reads").unwrap());assert!(old.internal_error.is_none(),"{:?}",old.internal_error);
 let config=crate::captured_raw_file::Config::capture(crate::captured_raw_policy::Configuration::ProvenMissing).unwrap();let all=Pages{tree:&engine.tree,config:None,fail:false.into(),stop:false};let selected=Pages{tree:&engine.tree,config:Some(&config),fail:false.into(),stop:false};let poll=||Ok(());let budget=Budget::new(128*1024*1024).unwrap();let preflight=prepare_selected_pages(&selected,&budget,&poll).unwrap();let tests=crate::sem::gen::test_only_types(&engine.tree);let native=derived_reads_data_without_semantic_from_preflight_pages(preflight,&selected,&all,&tests,&budget,&poll).unwrap();
 assert_eq!(native.sites(),old.run.sites);assert_eq!(native.allow_used(),old.allow_used);assert_eq!(native.generated_is_stale(),old.text.contains("code/_generated/reads.dm is stale"));assert!(native.sites().iter().any(|s|s.rule=="untracked_ui_read"),"unavailable semantics must not invent a never-written exemption");
 if bom{assert!(!native.allow_used().is_empty(),"LF witness must exercise actual ALLOW accounting while the CRLF source remains unchanged");}
 let scope=engine.scopes.for_lint(metadata().name,metadata().group);let report=crate::policy_finish::finish_report(metadata(),&scope,&native,crate::lint::Run{sites:native.sites().to_vec(),notes:Vec::new()},native.allow_used().to_vec(),crate::policy_finish::Timing::default(),&root,&None,true,|_,_,_|false,|_,text|{if let Some(message)=native.post_judge_message(){text.push_str(message);true}else{false}});assert_eq!(report.text,old.text);assert_eq!(report.failed,old.failed);assert!(report.internal_error.is_none());
 let fresh=Budget::new(128*1024*1024).unwrap();let preflight=prepare_selected_pages(&selected,&fresh,&poll).unwrap();all.fail.set(true);assert!(matches!(derived_reads_data_without_semantic_from_preflight_pages(preflight,&selected,&all,&tests,&fresh,&poll),Err(Failure::Operational(ref e))if e.raw_os_error()==Some(1450)));all.fail.set(false);
 let fresh=Budget::new(128*1024*1024).unwrap();let preflight=prepare_selected_pages(&selected,&fresh,&poll).unwrap();let tiny=Budget::new(256).unwrap();assert!(matches!(derived_reads_data_without_semantic_from_preflight_pages(preflight,&selected,&all,&tests,&tiny,&poll),Err(Failure::Operational(ref e))if e.kind()==io::ErrorKind::OutOfMemory));
 let fresh=Budget::new(128*1024*1024).unwrap();let preflight=prepare_selected_pages(&selected,&fresh,&poll).unwrap();let stopped=Pages{tree:&engine.tree,config:None,fail:false.into(),stop:true};assert!(derived_reads_data_without_semantic_from_preflight_pages(preflight,&selected,&stopped,&tests,&fresh,&poll).is_err());
 let fresh=Budget::new(128*1024*1024).unwrap();let preflight=prepare_selected_pages(&selected,&fresh,&poll).unwrap();assert_eq!(derived_reads_data_without_semantic_from_preflight_pages(preflight,&selected,&all,&tests,&fresh,&poll).unwrap().sites(),native.sites());
}
#[test]fn actual_failed_second_reader_raw_judge_matches_immutable_old_report(){run(true,false)}
#[test]fn actual_failed_second_reader_raw_judge_keeps_bom_crlf_and_allow_usage(){run(true,true)}
#[test]fn actual_failed_second_reader_raw_judge_preserves_generator_success(){run(false,false)}
