#[path="deadline_policy_frozen_original.rs"] mod frozen;
#[path="../../dmb/shared/test_scratch.rs"] mod scratch;
use crate::{lint::{Cx,Registry,Run,Sink},scopes::Scopes,tree::{Tree,SourceFile},captured_raw_file::{Config,File},captured_raw_policy::Configuration};
const BODY:&str="/obj/machine/process()\n\tif(world.time > expires)\n\t\treturn\n\tif(world.time < expires) // ALLOW(sys_deadline_poll): this annotated fixture tests the existing policy\n\t\treturn\n/obj/other/process()\n\tif(world.time > next_deadline)\n\t\treturn\n";
fn old_registry()->Registry{let mut reg=Registry::default();frozen::register(&mut reg);reg}
#[test]fn deadline_native_file_preserves_original_rows_allow_and_config(){
 let root=std::env::current_dir().unwrap().join("deadline-policy-fixture"); let reg=old_registry();let old=reg.find("deadline_polling").unwrap();
 for config in [None,Some(b"[lint.deadline_polling]\nexempt_files=['code/probe.dm']\n".as_slice())]{
  let interpreted=config.map(|b|Scopes::parse(std::str::from_utf8(b).unwrap()).unwrap()).unwrap_or_default();
  let captured=Config::capture(config.map_or(Configuration::ProvenMissing,Configuration::Captured)).unwrap();
  for rel in ["code/probe.dm","maps/probe.dm","code/.hidden/probe.dm"]{
   let tree=Tree::from_files(vec![SourceFile::from_text(rel,BODY)]);let scope=interpreted.for_lint("deadline_polling","");let cx=Cx{tree:&tree,meta:old.meta(),scope:&scope};let mut expected=Sink::new();
   for f in cx.files(){expected.cur=f.rel.clone();old.scan_file(&cx,f,&mut expected);}
   let actual=File::capture(&root,&root.join(rel),BODY.into()).unwrap().scan(&captured.scope("deadline_polling").unwrap()).unwrap();
   assert_eq!(actual.run.sites,expected.sites,"{rel}");assert_eq!(actual.allow_used,expected.allow_used);assert_eq!(actual.run.notes,expected.notes);
   if rel=="code/probe.dm"&&config.is_none(){assert_eq!(actual.run.sites.len(),2);assert_eq!(actual.allow_used.len(),1);}
  }
 }
}
#[test]fn deadline_observed_custom_report_matches_full_frozen_original_including_stale_and_malformed(){
 let root=scratch::dir("deadline-full-original");let path=root.join("tools/ci/deadline_polling_allowlist.txt");std::fs::create_dir_all(path.parent().unwrap()).unwrap();
 let mut tree=Tree::from_files(vec![SourceFile::from_text("code/probe.dm",BODY)]);tree.root=root;let reg=old_registry();let old=reg.find("deadline_polling").unwrap();let scope=Scopes::default().for_lint("deadline_polling","");let cx=Cx{tree:&tree,meta:old.meta(),scope:&scope};let mut sink=Sink::new();for f in cx.files(){sink.cur=f.rel.clone();old.scan_file(&cx,f,&mut sink);}let run=Run{sites:sink.sites,notes:sink.notes};assert_eq!(run.sites.len(),2);
 for text in ["","code/probe.dm:/obj/machine/process # permitted original\r\n","missing:first # stale one\nmissing:second # stale two\n","missing:first # old\nmissing:second # stale\nmissing:first # replacement\n","code/probe.dm:/obj/machine/process\n"]{
  std::fs::write(&path,text).unwrap();let mut expected=String::new();let bad=old.finish(&cx,&run,&mut expected);let mut actual=String::new();let actual_bad=crate::lints::deadline_polling::judge_observed_allowlist(&run,&path.to_string_lossy(),crate::lints::deadline_polling::parse_allowlist_text(text.into()),&mut actual);assert_eq!((actual_bad,actual),(bad,expected),"{text:?}");
 }
 std::fs::remove_file(&path).unwrap();let mut expected=String::new();let bad=old.finish(&cx,&run,&mut expected);let mut actual=String::new();let actual_bad=crate::lints::deadline_polling::judge_observed_allowlist(&run,&path.to_string_lossy(),Ok(Default::default()),&mut actual);assert_eq!((actual_bad,actual),(bad,expected));
}
