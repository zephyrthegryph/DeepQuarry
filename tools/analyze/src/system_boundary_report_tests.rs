#[path="system_boundary_report_frozen_original.rs"]mod frozen;
#[path="../../dmb/shared/test_scratch.rs"]mod scratch;
use crate::{lint::{Registry,Cx,Run,Site},tree::Tree,scopes::Scopes};
#[test]fn boundary_observed_ceiling_report_matches_complete_independent_original(){
 let root=scratch::dir("boundary-original-custom-report");let path=root.join("tools/ci/system_boundary_baseline.txt");std::fs::create_dir_all(path.parent().unwrap()).unwrap();
 let mut tree=Tree::from_files(Vec::new());tree.root=root;let mut registry=Registry::default();frozen::register(&mut registry);let lint=registry.find("system_boundary").unwrap();let scope=Scopes::default().for_lint("system_boundary","");let cx=Cx{ fixture:None,tree:&tree,meta:lint.meta(),scope:&scope};
 let site=|rule:&str,key:&str,line:u32|Site{rule:rule.into(),rel:"code/probe.dm".into(),line,msg:format!("code/probe.dm:{line}: exact old message"),key:key.into(),ident:String::new()};
 for sites in [Vec::new(),vec![site("B1","B1:code/probe.dm:SSmachines",1)],(1..=8).map(|line|site("B2","B2:code/probe.dm:/datum/system/probe",line)).collect(),vec![site("B5","B5:cycle:/datum/system/a+/datum/system/b",0),site("B7","B7:/datum/system/unused",0)]]{
  let run=Run{sites,notes:Vec::new()};
  for baseline in ["","B1:code/probe.dm:SSmachines 1\n","B2:code/probe.dm:/datum/system/probe 8\nB7:old:unused 2\n","B1:code/probe.dm:SSmachines 0\nB5:cycle:/datum/system/a+/datum/system/b 1\n"]{
   std::fs::write(&path,baseline).unwrap();let mut expected=String::new();let old_failed=lint.finish(&cx,&run,&mut expected);let observed=crate::baseline::read_ceilings(&path);let mut actual=String::new();let native_failed=crate::system_boundary_report::judge(&run,&observed,&mut actual);assert_eq!((native_failed,actual),(old_failed,expected),"{baseline:?}");
  }
 }
}
