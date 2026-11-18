use super::*;
use crate::captured_allow_annotations::Operation;
use crate::{captured_raw_file::{File,RawPolicyViews},captured_raw_policy::Configuration,allow_registry_metadata::complete_registry_allow_names};
use std::sync::Arc;
struct Pages{files:Vec<File>,stop:bool,fail:bool}
impl RawPolicyPages for Pages{
 fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{
  for file in &self.files{if !file.with_policy_views(visit)?{return Ok(false)}if self.fail{return Err(Failure::Operational(io::Error::from_raw_os_error(1450)))}}
  Ok(!self.stop)
 }
}
fn frame()->FrameData{FrameData{owner:FrameOwner::Semantic(11),source:22,configuration:33}}
fn selected()->FullSelectionData{FullSelectionData{names:vec!["scheduler".into(),"allow_annotations".into()]}}
fn op<'a>(b:&'a Budget)->Operation<'a>{Operation{budget:b,poll:&||Ok(())}}
#[test]fn zero_usage_producers_still_complete_and_foreign_duplicate_missing_or_failed_folds_never_finish(){
 let budget=Budget::new(8*1024*1024).unwrap();let mut c=op(&budget);let selection=selected();let mut join=UsageJoinData::new(&selection,frame());join.record_fold("scheduler",frame(),&[],&mut c).unwrap();assert!(join.finish_data(&mut c).is_err());join.record_fold("allow_annotations",frame(),&[],&mut c).unwrap();assert!(join.finish_data(&mut c).unwrap().used.is_empty());
 for (name,other) in [("scheduler",FrameData{configuration:34,..frame()}),("foreign_policy",frame())]{let mut next=UsageJoinData::new(&selection,frame());assert!(next.record_fold(name,other,&[],&mut c).is_err());assert!(next.record_fold("scheduler",frame(),&[],&mut c).is_err());assert!(next.finish_data(&mut c).is_err());}
 let mut duplicate=UsageJoinData::new(&selection,frame());duplicate.record_fold("scheduler",frame(),&[],&mut c).unwrap();assert!(duplicate.record_fold("scheduler",frame(),&[],&mut c).is_err());assert!(duplicate.finish_data(&mut c).is_err());
}
#[cfg(feature="native-policy")]
#[test]fn actual_registration_selection_preserves_empty_and_exclusions_only_name_group_rules(){
 let budget=Budget::new(16*1024*1024).unwrap();let mut c=op(&budget);let all=registered_full_selection(&[],&mut c).unwrap();assert!(all.names().iter().any(|name|name=="allow_annotations"));assert!(all.names().iter().any(|name|name=="init"));let excluded=registered_full_selection(&["-init".into(),"-sys".into()],&mut c).unwrap();assert!(!excluded.names().iter().any(|name|name=="init"||name.starts_with("sys/")));assert!(registered_full_selection(&["scheduler".into()],&mut c).is_err());
 #[cfg(feature="legacy-sem")]{let registry=crate::run::registry();let actual:Vec<_>=crate::run::selected(&registry,&[]).iter().map(|lint|lint.meta().name.to_owned()).collect();assert_eq!(all.names(),actual);let actual:Vec<_>=crate::run::selected(&registry,&["-init".into(),"-sys".into()]).iter().map(|lint|lint.meta().name.to_owned()).collect();assert_eq!(excluded.names(),actual);}
}
#[test]fn actual_fold_allow_usage_and_unexempt_code_maps_annotations_feed_same_unused_judge(){
 let root=std::env::current_dir().unwrap().join("allow-unused-whole-data");let budget=Budget::new(16*1024*1024).unwrap();let config=Config::capture(Configuration::Captured(b"[lint.allow_annotations]\nexempt=[\"code/exempt.dm\"]\n")).unwrap();let mut control=op(&budget);let registry=complete_registry_allow_names(&mut control).unwrap();
 let rows=[("maps/probe.dm","// ALLOW(scheduler): world.Export() is a blocking external call\n"),("code/exempt.dm","// ALLOW(scheduler): world.Export() is a blocking external call\n"),("code/used.dm","/proc/x()\n    sleep(1) // ALLOW(scheduler): world.Export() is a blocking external call\n"),("code/other.dm","// ALLOW(init): this native initializer deliberately retains instance state\n// ALLOW(check_grep): these source tokens intentionally test actual checks\n// ALLOW(doc_snippets): these source tokens intentionally test actual checks\n")];
 let mut files=Vec::new();let mut usage=Vec::new();for(relative,text)in rows{let file=File::capture(&root,&root.join(relative),text.to_owned().into()).unwrap();if relative=="code/used.dm"{let data=file.scan(&config.scope("scheduler").unwrap()).unwrap();assert!(data.run.sites.is_empty());assert_eq!(data.allow_used.len(),1);usage=data.allow_used;}files.push(file);}
 let pages=Pages{files,stop:false,fail:false};let selection=selected();let mut join=UsageJoinData::new(&selection,frame());join.record_fold("scheduler",frame(),&usage,&mut control).unwrap();join.record_fold("allow_annotations",frame(),&[],&mut control).unwrap();let usage=join.finish_data(&mut control).unwrap();
 super::super::with_names(&registry,&config,&mut control,|known,_|{let actual=collect_unused_data(known,&usage,&pages,&[],&|_|String::new(),&budget,&||Ok(()))?;assert_eq!(actual.len(),3);assert!(actual[0].starts_with("code/exempt.dm:1: ALLOW(scheduler) is unused"),"unused phase must ignore validation exemptions");assert!(actual[1].starts_with("maps/probe.dm:1: ALLOW(scheduler) is unused"));assert!(actual[2].starts_with("ALLOW(init): 1 annotation, but no lint run used any"));Ok(())}).unwrap();
}
#[test]fn stopped_eof_first_1450_quota_and_fresh_recovery_do_not_publish_partial_unused_success(){
 let root=std::env::current_dir().unwrap().join("allow-unused-controls");let config=Config::capture(Configuration::ProvenMissing).unwrap();let budget=Budget::new(16*1024*1024).unwrap();let mut c=op(&budget);let registry=complete_registry_allow_names(&mut c).unwrap();let selection=selected();let mut join=UsageJoinData::new(&selection,frame());join.record_fold("scheduler",frame(),&[],&mut c).unwrap();join.record_fold("allow_annotations",frame(),&[],&mut c).unwrap();let usage=join.finish_data(&mut c).unwrap();let mut pages=Pages{files:vec![File::capture(&root,&root.join("code/probe.dm"),"// ALLOW(scheduler): world.Export() is a blocking external call\n".to_owned().into()).unwrap()],stop:true,fail:false};
 super::super::with_names(&registry,&config,&mut c,|known,_|{assert!(matches!(collect_unused_data(known,&usage,&pages,&[],&|_|String::new(),&budget,&||Ok(())),Err(Failure::Unsupported(ref message))if message.contains("EOF")));pages.stop=false;pages.fail=true;assert!(matches!(collect_unused_data(known,&usage,&pages,&[],&|_|String::new(),&budget,&||Ok(())),Err(Failure::Operational(ref error))if error.raw_os_error()==Some(1450)));pages.fail=false;let denied=Budget::new(std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>()).unwrap();assert!(matches!(collect_unused_data(known,&usage,&pages,&[],&|_|String::new(),&denied,&||Ok(())),Err(Failure::Operational(ref error))if error.kind()==io::ErrorKind::OutOfMemory));assert_eq!(collect_unused_data(known,&usage,&pages,&[],&|_|String::new(),&budget,&||Ok(())).unwrap().len(),1);Ok(())}).unwrap();
 let io_budget=Budget::new(1<<20).unwrap();let mut c=Operation{budget:&io_budget,poll:&||Err(io::Error::from_raw_os_error(1450))};let mut denied_join=UsageJoinData::new(&selection,frame());assert!(matches!(denied_join.record_fold("scheduler",frame(),&[],&mut c),Err(Failure::Operational(ref error))if error.raw_os_error()==Some(1450)));let fresh=Budget::new(1<<20).unwrap();assert!(denied_join.finish_data(&mut op(&fresh)).is_err());
}
#[cfg(feature="legacy-sem")]
#[path="allow_annotations_original.rs"]mod immutable_original;
#[cfg(feature="legacy-sem")]
#[test]fn independent_original_unused_whole_output_matches_140_files_digest_collision_malformed_maps_quiet_and_aliases(){
 use crate::tree::{Tree,SourceFile};let root=std::env::current_dir().unwrap().join("allow-unused-original");let budget=Budget::new(32*1024*1024).unwrap();let config=Config::capture(Configuration::ProvenMissing).unwrap();let registry=complete_registry_allow_names(&mut op(&budget)).unwrap();let mut source=vec![("maps/map.dm".to_owned(),"// ALLOW(scheduler): world.Export() is a blocking external call\n".to_owned()),("code/a_malformed.dm".to_owned(),"// ALLOW(@): malformed marker still participates in digest search\n".to_owned())];for n in 0..140{source.push((format!("code/file_{n:03}.dm"),if n==0{"// ALLOW(scheduler): world.Export() is a blocking external call\n// ALLOW(init): deliberately retains the actual per-instance state\n".into()}else if n==139{"// ALLOW(check_grep): preserve the actual source fixture tokens here\n// ALLOW(doc_snippets): preserve the actual source fixture tokens here\n".into()}else{"/datum/probe\n".into()}));}source.sort_by(|a,b|a.0.cmp(&b.0));let tree=Tree::from_files(source.iter().map(|(rel,text)|SourceFile::from_text(rel,text)).collect());let mut pages=Pages{files:source.iter().rev().map(|(rel,text)|File::capture(&root,&root.join(rel),text.to_owned().into()).unwrap()).collect(),stop:false,fail:false};let selection=selected();let usage=vec![AllowUse{name:"scheduler".into(),rel:"maps/map.dm".into(),line:1,code:String::new()}];let mut join=UsageJoinData::new(&selection,frame());let mut c=op(&budget);join.record_fold("scheduler",frame(),&usage,&mut c).unwrap();join.record_fold("allow_annotations",frame(),&[],&mut c).unwrap();let usage_data=join.finish_data(&mut c).unwrap();let extras=vec![("scheduler".to_owned(),"collision".to_owned(),1),("missing".to_owned(),"absent".to_owned(),1)];let digest=|relative:&str|if relative=="code/a_malformed.dm"||relative=="code/file_000.dm"{"collision".to_owned()}else{relative.to_owned()};
 super::super::with_names(&registry,&config,&mut c,|known,_|{immutable_original::set_known(known.names.clone());for extras in [&[][..],extras.as_slice()]{let actual=collect_unused_data(known,&usage_data,&pages,extras,&digest,&budget,&||Ok(()))?;let old=immutable_original::unused(&tree,&usage,extras,&digest);assert_eq!(actual,old);assert!(actual.iter().any(|line|line.starts_with("ALLOW(init)")));}pages.stop=true;assert!(collect_unused_data(known,&usage_data,&pages,&[],&digest,&budget,&||Ok(())).is_err());Ok(())}).unwrap();
}

#[cfg(feature="legacy-sem")]
#[path="../../dmb/shared/test_scratch.rs"]mod full_plan_scratch;
#[cfg(feature="legacy-sem")]
#[test]fn selected_tree_plan_matches_actual_original_engine_loading_and_does_not_widen_excluded_maps(){
 let root=full_plan_scratch::dir("allow-selected-original-plan");for(relative,text)in[("code/probe.dm","/proc/p()\n    return\n"),("maps/probe.dm","// ALLOW(scheduler): preserve actual mapping behavior here\n"),("code/.hidden/probe.dm","// hidden is not CODE_MAPS_DM\n")]{let path=root.join(relative);std::fs::create_dir_all(path.parent().unwrap()).unwrap();std::fs::write(path,text).unwrap();}
 for keep in [vec!["scheduler"],vec!["scheduler","allow_annotations"]]{let registry=crate::run::registry();let exclusions=registry.lints.iter().filter(|lint|!keep.contains(&lint.meta().name)).map(|lint|format!("-{}",lint.meta().name)).collect::<Vec<_>>();let engine=crate::run::Engine::new(registry,crate::run::Options{root:root.clone(),lints:exclusions,no_cache:true,raw:true,..Default::default()}).unwrap();let selected=crate::run::selected(&engine.reg,&engine.opts.lints);let budget=Budget::new(16<<20).unwrap();let plan=SelectedTreePlanData::new(selected.iter().map(|lint|lint.meta().select),&mut op(&budget)).unwrap();let expected=engine.tree.select(&crate::tree::CODE_MAPS_DM).into_iter().map(|file|file.rel.as_str()).collect::<Vec<_>>();let actual=["code/probe.dm","maps/probe.dm","code/.hidden/probe.dm"].into_iter().filter(|relative|plan.matches_path(relative)).collect::<Vec<_>>();assert_eq!(actual,expected);assert_eq!(plan.matches_path("maps/probe.dm"),keep.contains(&"allow_annotations"));}
}

#[test]fn actual_duplicate_producer_roots_allocate_and_admit_only_one_native_plan_entry(){
 let unique_budget=Budget::new(16*1024).unwrap();let unique_before=unique_budget.used();let unique=SelectedTreePlanData::new([crate::tree::CODE_MAPS_DM],&mut op(&unique_budget)).unwrap();let unique_charge=unique_budget.used()-unique_before;
 let repeated_budget=Budget::new(16*1024).unwrap();let repeated_before=repeated_budget.used();let repeated=SelectedTreePlanData::new(std::iter::repeat_n(crate::tree::CODE_MAPS_DM,4096),&mut op(&repeated_budget)).unwrap();
 assert_eq!(repeated.plan.entries,unique.plan.entries);assert_eq!(repeated.roots(),unique.roots());assert_eq!(repeated_budget.used()-repeated_before,unique_charge,"duplicate roots cannot allocate dead temporary Strings or consume another node grant");assert!(!repeated_budget.denied());
 for path in["code/probe.dm","maps/probe.dm","code/.hidden/probe.dm","doc/probe.md"]{assert_eq!(repeated.matches_path(path),unique.matches_path(path));assert_eq!(repeated.matches_loaded_dm(path),unique.matches_loaded_dm(path));}
}
#[test]fn normalized_duplicate_plan_keys_preserve_actual_plan_and_root_order(){
 let rows=[crate::tree::Select{roots:&[("code/","dm"),("code",".dm"),("maps//","..dm"),("maps","dm"),("doc/",".md")],hidden:false},crate::tree::CODE_MAPS_DM];
 let mut original=crate::tree::Plan::default();for select in rows{for &(dir,extension)in select.roots{original.add(dir,extension);}}
 let budget=Budget::new(16*1024).unwrap();let actual=SelectedTreePlanData::new(rows,&mut op(&budget)).unwrap();assert_eq!(actual.plan.entries,original.entries);assert_eq!(actual.roots(),["code","maps"]);
}
#[test]fn duplicate_plan_checkpoint_preserves_actual_first_io_without_partial_result(){
 struct Stop{polls:usize,fail:usize}impl Control for Stop{type Error=Failure;const CHECKED:bool=true;
  fn checkpoint(&mut self)->Result<(),Failure>{self.polls+=1;if self.polls==self.fail{Err(Failure::Operational(io::Error::from_raw_os_error(1450)))}else{Ok(())}}
  fn reserve(&mut self,_:usize)->Result<(),Failure>{Ok(())}fn overflow(&mut self)->Failure{Failure::Operational(io::ErrorKind::OutOfMemory.into())}fn allocation_failed(&mut self)->Failure{self.overflow()}
 }
 for fail in 1..=12{let mut actual=Stop{polls:0,fail};let result=SelectedTreePlanData::new(std::iter::repeat_n(crate::tree::CODE_MAPS_DM,4),&mut actual);let Err(Failure::Operational(error))=result else{panic!("actual duplicate traversal checkpoint must refuse before returning Plan DATA")};assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(actual.polls,fail);}
}

#[cfg(feature="native-policy")]
#[test]
fn actual_registered_empty_producers_complete_in_selection_index_order_without_duplicate_names(){
 let budget=Budget::new(1<<20).unwrap();let mut c=op(&budget);
 let selection=registered_full_selection(&[],&mut c).unwrap();assert!(selection.names().len()>32);
 let names=selection.names().to_vec();let before=budget.used();
 let mut join=UsageJoinData::new(&selection,frame());assert!(join.completed.is_empty());assert_eq!(join.completed.capacity(),0);
 // A real producer may finish out of registration order; its exact slot alone completes.
 for (position,name)in names.iter().rev().enumerate(){
  join.record_fold(name,frame(),&[],&mut c).unwrap();
  assert_eq!(join.completed.iter().filter(|done|**done).count(),position+1);
  if position+1<names.len(){assert!(join.finish_data(&mut c).is_err());}
 }
 assert_eq!(join.completed.len(),selection.names().len());assert!(join.finish_data(&mut c).unwrap().used.is_empty());
 let completion_charge=budget.used()-before;
 assert!(completion_charge>=join.completed.capacity()*std::mem::size_of::<bool>());
 assert!(completion_charge<4096,"actual completion flags replace per-producer BTree nodes and name copies: {completion_charge}");
 assert_eq!(selection.names(),names,"exact original registration order and names are immutable");
 assert!(join.record_fold(&names[0],frame(),&[],&mut c).is_err());assert!(join.finish_data(&mut c).is_err());
}
#[test]
fn completion_flag_growth_first_1450_poison_and_fresh_recovery_keep_actual_rows_private(){
 struct FirstAllocation{left:usize}
 impl Control for FirstAllocation{
  type Error=Failure;const CHECKED:bool=true;
  fn checkpoint(&mut self)->Result<(),Failure>{Ok(())}
  fn reserve(&mut self,_:usize)->Result<(),Failure>{if self.left==0{return Err(Failure::Operational(io::Error::from_raw_os_error(1450)))}self.left-=1;Ok(())}
  fn overflow(&mut self)->Failure{Failure::Operational(io::ErrorKind::OutOfMemory.into())}
  fn allocation_failed(&mut self)->Failure{Failure::Operational(io::ErrorKind::OutOfMemory.into())}
 }
 let selection=selected();let mut denied=UsageJoinData::new(&selection,frame());
 let first=denied.record_fold("scheduler",frame(),&[],&mut FirstAllocation{left:0}).unwrap_err();
 assert!(matches!(first,Failure::Operational(ref error)if error.raw_os_error()==Some(1450)));
 assert_eq!(denied.completed.len(),0);assert_eq!(denied.completed.capacity(),0);
 let wider=FullSelectionData{names:["scheduler","allow_annotations","init","decl","tracked","base_vars"].into_iter().map(str::to_owned).collect()};let mut partial=UsageJoinData::new(&wider,frame());let actual=partial.record_fold("scheduler",frame(),&[],&mut FirstAllocation{left:1}).unwrap_err();assert!(matches!(actual,Failure::Operational(ref error)if error.raw_os_error()==Some(1450)));assert_eq!(partial.completed.len(),4);assert!(partial.completed.iter().all(|done|!*done));
 let budget=Budget::new(1<<20).unwrap();let mut c=op(&budget);assert!(partial.finish_data(&mut c).is_err());assert!(denied.finish_data(&mut c).is_err());assert!(denied.record_fold("allow_annotations",frame(),&[],&mut c).is_err());
 let mut fresh=UsageJoinData::new(&selection,frame());fresh.record_fold("allow_annotations",frame(),&[],&mut c).unwrap();assert!(fresh.finish_data(&mut c).is_err());fresh.record_fold("scheduler",frame(),&[],&mut c).unwrap();assert!(fresh.finish_data(&mut c).unwrap().used.is_empty());
}
