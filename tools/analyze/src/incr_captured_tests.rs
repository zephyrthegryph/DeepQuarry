use super::*;
use std::sync::atomic::{AtomicUsize,Ordering};
#[path="../../dmb/shared/test_scratch.rs"]mod test_scratch;
static CONFIG_TEST:std::sync::Mutex<()>=std::sync::Mutex::new(());
fn captured(rel:&str)->SourceFile{SourceFile::from_shared_text(rel,std::env::current_dir().unwrap().join(rel),"/datum/probe\n".into())}
fn use_at(name:&str)->crate::lint::AllowUse{crate::lint::AllowUse{rel:"code/probe.dm".into(),line:1,name:name.into(),code:String::new()}}
#[test]
fn captured_incr_bypasses_config_disk_and_empty_shards_with_same_file_and_allow_order(){
 let _serial=CONFIG_TEST.lock().unwrap();
 let root=test_scratch::dir("captured-incr-no-disk");let trap=root.join("cache-is-a-file");std::fs::write(&trap,b"unchanged no-disk trap").unwrap();
 configure(trap.clone(),"actual configured cache trap".into(),true);
 let a=captured("code/a.dm");let b=captured("code/b.dm");let files=[&b,&a];let caller=std::thread::current().id();
 let saved=crate::dm::sys::take_recorded();crate::dm::sys::replay_recorded(vec![use_at("before")]);
 let before=captured::config_reads();let calls=AtomicUsize::new(0);
 let rows=sharded_keyed("captured-outer",7,&files,|file|{
   assert_eq!(std::thread::current().id(),caller,"captured callbacks stay serial on caller");calls.fetch_add(1,Ordering::Relaxed);
   crate::dm::sys::replay_recorded(vec![use_at(&file.rel)]);
   let nested:Vec<usize>=facts("captured-empty",&[],|_|panic!("empty selection callback"));assert!(nested.is_empty());
   let one:usize=cached("captured-single",0,||17);assert_eq!(one,17);file.rel.clone()
 });
 assert_eq!(rows,vec!["code/b.dm","code/a.dm"]);assert_eq!(calls.load(Ordering::Relaxed),2);
 assert_eq!(captured::config_reads(),before,"no old global configuration consulted");
 assert_eq!(std::fs::read(&trap).unwrap(),b"unchanged no-disk trap");
 let mut expected=vec![use_at("before")];
 let mut grouped:Vec<_>=files.iter().map(|f|(sharded::shard_for_test(&f.rel),f.rel.as_str())).collect();grouped.sort_by_key(|p|p.0);
 expected.extend(grouped.into_iter().map(|(_,rel)|use_at(rel)));assert_eq!(crate::dm::sys::take_recorded(),expected);crate::dm::sys::restore_recorded(saved);
 configure(root.join("ordinary-control"),"ordinary".into(),true);let normal=SourceFile::from_text("code/ordinary.dm","/datum/x\n");let calls=AtomicUsize::new(0);
 let first:Vec<usize>=keyed("ordinary-control",1,&[&normal],|_|{calls.fetch_add(1,Ordering::Relaxed);29});
 let next:Vec<usize>=keyed("ordinary-control",1,&[&normal],|_|{calls.fetch_add(1,Ordering::Relaxed);31});
 assert_eq!(first,next);assert_eq!(calls.load(Ordering::Relaxed),1,"legacy disk hit unchanged");
 assert!(root.join("ordinary-control").read_dir().unwrap().next().is_some());configure(PathBuf::new(),String::new(),false);
}
#[test]
fn captured_incr_scope_empty_mixed_atomic_refusal_and_nested_panic_restore(){
 let a=captured("code/captured.dm");let ordinary=SourceFile::from_text("code/ordinary.dm","unused");let count=AtomicUsize::new(0);
 let saved=crate::dm::sys::take_recorded();crate::dm::sys::replay_recorded(vec![use_at("before")]);
 {let scope=captured_compute_scope();let before=captured::config_reads();
  let empty:Vec<usize>=sharded_facts("empty",&[],|_|panic!("empty callback"));assert!(empty.is_empty());assert_eq!(captured::config_reads(),before);
  let refused=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||keyed("mixed",0,&[&a,&ordinary],|_|{count.fetch_add(1,Ordering::Relaxed);1usize})));
  assert!(refused.is_err());assert_eq!(count.load(Ordering::Relaxed),0);assert!(scope.require().is_err());
 }
 {let scope=captured_compute_scope();
  let failed=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||{
    let _:Vec<usize>=facts("panic",&[&a],|_|{crate::dm::sys::replay_recorded(vec![use_at("failed")]);panic!("actual nested callback panic")});
  }));assert!(failed.is_err());assert!(scope.require().is_err());
 }
 assert_eq!(crate::dm::sys::take_recorded(),vec![use_at("before")]);crate::dm::sys::restore_recorded(saved);
 let scope=captured_compute_scope();assert!(scope.require().is_ok());let rows:Vec<usize>=facts("recovered",&[&a],|_|3);assert_eq!(rows,vec![3]);assert!(scope.require().is_ok());
}
#[test]
fn captured_incr_nested_single_panic_and_configuration_mutation_cannot_be_swallowed(){
 for mutation in [false,true]{let scope=captured_compute_scope();
  let failure=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||cached("nested",1,||{
   if mutation{configure(PathBuf::new(),"forbidden".into(),false);}else{panic!("actual single callback panic");}1usize
  })));
  assert!(failure.is_err());assert!(scope.require().is_err());
 }
 assert!(!captured::active());let scope=captured_compute_scope();assert!(scope.require().is_ok());
}
