//! Immutable complete old rule comparison over every CODE source, no semantic model.
#[path="../fixtures/original_policies/op_order.rs"]mod original;
#[path="../fixtures/native-op-order/fixture.rs"]mod fixture;
#[path="../../dmb/shared/test_scratch.rs"]mod scratch;

use crate::{captured_generator_budget::Budget,reactive_raw_policy_pages::RawPolicyPages,captured_reactive_reads::Failure};
struct Pages<'a>{tree:&'a crate::tree::Tree,budget:&'a std::sync::Arc<Budget>,stop:bool}
impl RawPolicyPages for Pages<'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,crate::captured_raw_file::RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{if self.stop{return Ok(false)}for file in self.tree.select(&crate::tree::CODE_DM){if !crate::captured_raw_file::with_original_policy_file(&self.tree.root,&self.tree.root.join(&file.rel),file.raw().text.clone(),0,self.budget,visit)?{return Ok(false)}}Ok(true)}}
struct Text<'a>(&'a crate::captured_op_order::Data);
impl crate::baseline::SiteText for Text<'_>{fn site_text(&self,rel:&str,line:usize)->String{let index=self.0.sites().iter().position(|s|s.rel==rel&&s.line as usize==line).expect("every emitted site must retain actual same-loan source text");self.0.source_text()[index].clone()}}
#[test]fn original_op_order_entire_rule_retains_all_files_composition_allow_and_ceilings(){
 for(case,body,positive)in fixture::CASES{
  let root=scratch::dir(&format!("op-order-whole-{case}"));
  for(path,text)in fixture::files(case,body){let target=root.join(path);std::fs::create_dir_all(target.parent().unwrap()).unwrap();std::fs::write(target,text).unwrap();}
  let options=||crate::run::Options{root:root.clone(),lints:vec!["op_order".into()],no_cache:true,raw:true,..Default::default()};
  let mut old_registry=crate::lint::Registry::default();original::register(&mut old_registry);
  let old=crate::run::Engine::new(old_registry,options()).unwrap();let expected=old.run_one(old.reg.lints[0].as_ref());
  assert!(expected.internal_error.is_none(),"actual original {case}");assert_eq!(!expected.run.sites.is_empty(),*positive,"actual old fixture trap {case}");

  let configuration=std::fs::read(root.join("tools/ci/lint_scopes.toml")).unwrap();let config=crate::captured_raw_file::Config::capture(crate::captured_raw_policy::Configuration::Captured(&configuration)).unwrap();let order=crate::sem::decls::dme_include_order(&root);let budget=Budget::new(64*1024*1024).unwrap();let pages=Pages{tree:&old.tree,budget:&budget,stop:false};
  let native=crate::captured_op_order::collect(&pages,&order,&config,&budget,&||Ok(())).unwrap();assert_eq!(native.sites(),expected.run.sites.as_slice(),"entire actual raw fold sites {case}");assert_eq!(native.allow_used(),expected.allow_used.as_slice(),"entire actual raw fold ALLOW {case}");assert_eq!(native.sites().len(),native.source_text().len());
  let empty=crate::scopes::LintScope::default();let scope=config.borrowed_report_scope("op_order","").unwrap_or(&empty);let report=crate::policy_finish::finish_report(&crate::op_order_policy::META,scope,&Text(&native),crate::lint::Run{sites:native.sites().to_vec(),notes:Vec::new()},native.allow_used().to_vec(),Default::default(),&root,&None,true,|_,_,_|panic!("op_order has the exact existing ceilings finish"),|_,_|false);assert_eq!(report.text,expected.text,"entire native ceilings text {case}");assert_eq!(report.failed,expected.failed);
  let stopped=Pages{tree:&old.tree,budget:&budget,stop:true};assert!(crate::captured_op_order::collect(&stopped,&order,&config,&budget,&||Ok(())).is_err());let first=crate::captured_op_order::collect(&pages,&order,&config,&budget,&||Err(std::io::Error::from_raw_os_error(1450))).err().unwrap();assert!(matches!(first,Failure::Operational(e)if e.raw_os_error()==Some(1450)));assert!(Budget::new(0).is_err());let denied=Budget::new(std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>()).unwrap();assert!(matches!(crate::captured_op_order::collect(&pages,&order,&config,&denied,&||Ok(())),Err(Failure::Operational(e))if e.kind()==std::io::ErrorKind::OutOfMemory));
  let mut new_registry=crate::lint::Registry::default();crate::lints::op_order::register(&mut new_registry);
  let new=crate::run::Engine::new(new_registry,options()).unwrap();let actual=new.run_one(new.reg.lints[0].as_ref());
  assert!(actual.internal_error.is_none());assert_eq!(actual.run.sites,expected.run.sites,"entire sites {case}");assert_eq!(actual.allow_used,expected.allow_used,"entire ALLOW trace {case}");assert_eq!(actual.run.notes,expected.run.notes);assert_eq!(actual.text,expected.text,"whole ceilings report {case}");assert_eq!(actual.failed,expected.failed);
  if matches!(*case,"relative_allow"|"clash_allow"){assert!(!expected.allow_used.is_empty(),"genuine annotation usage must not disappear");}
 }
}
