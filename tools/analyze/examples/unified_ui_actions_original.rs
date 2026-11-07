//! Independent frozen entire Original UI producer and original nested dx helpers.
pub use dq_analyze::{allow,lint,incr,tree,pat,pat_match,util,parity,scopes,raw_type_vars_policy,captured_raw_file,captured_raw_policy,captured_generator_budget,captured_reactive_reads,captured_raw_tree_pages,captured_ui_actions,reactive_raw_policy_pages,ui_actions_policy};
pub use dq_analyze::original_policy_descriptors as allow_registry_fields;
#[path="../fixtures/original_policies/doc_snippets_dx.rs"]pub mod old_dx;
pub mod dm{pub use dq_analyze::dm::*;pub use crate::old_dx as dx;}
#[path="../fixtures/original_policies/ui_actions_source_scanner.rs"]mod old;
#[path="../fixtures/native-ui-actions-workspace/fixture.rs"]mod fixture;
#[path="../fixtures/native-ui-actions-workspace/direct.rs"]mod direct;
#[path="../../dmb/shared/test_scratch.rs"]mod scratch;
fn record(out:&dq_analyze::policy_finish::Outcome)->serde_json::Value{serde_json::json!({"sites":out.run.sites,"notes":out.run.notes,"allow_used":out.allow_used,"failed":out.failed,"text":out.text,"internal_error":out.internal_error})}
struct Text<'a>(&'a captured_raw_tree_pages::Data);impl dq_analyze::baseline::SiteText for Text<'_>{fn site_text(&self,relative:&str,line:usize)->String{self.0.sites().iter().position(|s|s.rel==relative&&s.line as usize==line).map(|n|self.0.source_text()[n].clone()).unwrap_or_default()}}
fn error(f:captured_reactive_reads::Failure)->Box<dyn std::error::Error>{match f{captured_reactive_reads::Failure::Operational(e)=>Box::new(e),captured_reactive_reads::Failure::Unsupported(s)=>s.into()}}
// The historical oracle really executes at its original path. Only the
// known repository move is projected onto its reported coordinates/text.
const HISTORICAL_DISPATCHER: &str = "code/datums/capabilities/ui_actions.dm";
fn current_dispatcher_path(value: &str) -> &str {
    if value == HISTORICAL_DISPATCHER { ui_actions_policy::DISPATCHER } else { value }
}
fn historical_dispatcher_path(value: &str) -> &str {
    if value == ui_actions_policy::DISPATCHER { HISTORICAL_DISPATCHER } else { value }
}
fn main()->Result<(),Box<dyn std::error::Error>>{
{use sha1::Digest as _;assert_eq!(format!("{:x}",sha1::Sha1::digest(include_bytes!("../fixtures/original_policies/ui_actions_source_scanner.rs"))),"3ee8c2ad6eb03c331404690b46dee332073ea91c");}
{use sha1::Digest as _;assert_eq!(format!("{:x}",sha1::Sha1::digest(include_bytes!("../fixtures/original_policies/doc_snippets_dx.rs"))),"96bbe29394ea1fabcccae2f89b91e71bc7ea1101");}
 for case in fixture::CASES{let root=scratch::dir(&format!("ui-actions-original-{case}"));let files=fixture::files(case);for(rel,text)in &files{let path=root.join(rel);std::fs::create_dir_all(path.parent().unwrap())?;std::fs::write(path,text)?;}
  let historical_root = scratch::dir(&format!("ui-actions-historical-{case}"));
  for (rel, text) in &files {
      let path = historical_root.join(historical_dispatcher_path(rel));
      std::fs::create_dir_all(path.parent().unwrap())?;
      std::fs::write(path, text)?;
  }
  let options=dq_analyze::run::Options{root:root.clone(),lints:vec!["ui_actions".into()],raw:true,no_cache:true,..Default::default()};let mut registry=lint::Registry::default();old::register(&mut registry);let original=dq_analyze::run::Engine::new(registry,dq_analyze::run::Options{root:historical_root,..options.clone()})?;let mut expected=original.run_one(original.reg.lints[0].as_ref());assert!(expected.internal_error.is_none(),"{case}: {:?}",expected.internal_error);
  if *case=="basic"{assert!(expected.run.sites.iter().any(|s|s.rule=="ui_unsent_param"));assert!(expected.run.sites.iter().any(|s|s.rule=="ui_unvalidated_param"));assert!(expected.run.sites.iter().any(|s|s.rule=="problem"));}if *case=="clean"||*case=="missing"{assert!(expected.run.sites.is_empty());}if *case=="malformed"{assert_eq!(expected.run.sites.len(),1);assert_eq!(expected.run.notes.len(),1);}if *case=="allow"{assert!(!expected.allow_used.is_empty());}assert!(!expected.run.sites.iter().any(|s|s.rel.starts_with("maps/")||s.rel.contains(".hidden")||s.rel.ends_with(".d.ts")));
  for site in &mut expected.run.sites {
      site.rel = current_dispatcher_path(&site.rel).to_owned();
      site.msg = site.msg.replace(HISTORICAL_DISPATCHER, ui_actions_policy::DISPATCHER);
  }
  for note in &mut expected.run.notes {
      *note = note.replace(HISTORICAL_DISPATCHER, ui_actions_policy::DISPATCHER);
  }
  for used in &mut expected.allow_used {
      used.rel = current_dispatcher_path(&used.rel).to_owned();
  }
  expected.text = expected.text.replace(HISTORICAL_DISPATCHER, ui_actions_policy::DISPATCHER);
  let mut shared_registry=lint::Registry::default();dq_analyze::lints::ui_actions::register(&mut shared_registry);let shared=dq_analyze::run::Engine::new(shared_registry,options)?;let shared=shared.run_one(shared.reg.lints[0].as_ref());assert_eq!(record(&shared),record(&expected),"entire independent original/delegated UI {case}");
  let data=direct::run(&root,&files,64*1024*1024,None,&||Ok(())).map_err(error)?;assert_eq!(data.sites(),expected.run.sites.as_slice(),"entire sites {case}");assert_eq!(data.notes(),expected.run.notes.as_slice(),"entire ordered notes {case}");assert_eq!(data.allow_used(),expected.allow_used.as_slice(),"entire ordered ALLOW {case}");for(s,t)in data.sites().iter().zip(data.source_text()){assert_eq!(*t,original.tree.site_text(historical_dispatcher_path(&s.rel),s.line as usize),"actual original source text {case}");}
  let cfg=files.iter().find(|r|r.0=="tools/ci/lint_scopes.toml").unwrap();let config=captured_raw_file::Config::capture(captured_raw_policy::Configuration::Captured(cfg.1.as_bytes()))?;let empty=Default::default();let scope=config.borrowed_report_scope("ui_actions",ui_actions_policy::metadata().group).unwrap_or(&empty);let actual=dq_analyze::policy_finish::finish_report(ui_actions_policy::metadata(),scope,&Text(&data),lint::Run{sites:data.sites().to_vec(),notes:data.notes().to_vec()},data.allow_used().to_vec(),Default::default(),&root,&None,true,|_,_,_|panic!("UI is not Custom"),|_,_|false);assert_eq!(record(&actual),record(&expected),"entire independent old/native UI outcome {case}");println!("ORIGINAL_UI_ACTIONS_FULL={}",serde_json::json!({"case":case,"record":{"sites":expected.run.sites,"source_text":data.source_text(),"notes":expected.run.notes,"allow_used":expected.allow_used}}));
 }Ok(())
}
