//! Independent original whole decision result against the shared policy core.
pub use dq_analyze::sem;
#[path="support/auto_decision_original/projected.rs"]mod original;

/// Oracle-only public equivalent. rel() adds a footprint touch, harmless here:
/// these independent runs disable every store and never compare footprints.
fn file_of_public(sem:&dq_analyze::sem::Sem,loc:dreammaker::Location)->Option<&str>{
 if loc.is_builtins(){return None}let rel=sem.rel(loc);(!rel.is_empty()).then_some(rel)
}

fn verify_oracle_transport(){
 let old=include_str!("support/auto_decision_original/producer.rs");let projected=include_str!("support/auto_decision_original/projected.rs");
 let expected=old.replace("sem.file_of(loc)","crate::file_of_public(sem,loc)").replace("sem.file_of(v.location)","crate::file_of_public(sem,v.location)");assert_eq!(expected,projected,"only private file lookup transport may differ from the frozen producer");
}
fn main(){verify_oracle_transport();
 let root=std::path::PathBuf::from(std::env::args().nth(1).expect("fixture root"));
 let engine=dq_analyze::run::Engine::new(dq_analyze::run::registry(),dq_analyze::run::Options{root:std::fs::canonicalize(root).unwrap(),no_cache:true,raw:true,..Default::default()}).unwrap();let sem=dq_analyze::sem::sem_for(&engine.tree).unwrap();assert!(engine.tree.files.iter().all(|f|!f.rel.is_empty()));assert!(sem.errors.is_empty(),"{:?}",sem.errors);assert!(dq_analyze::incr::dir().is_none());
 let mut candidates=std::collections::BTreeSet::new();for ty in sem.objtree.iter_types(){let owner=if ty.get().path.is_empty(){"/"}else{&ty.get().path};for(name,v)in &ty.get().vars{if v.declaration.is_some(){candidates.insert((owner.to_owned(),name.clone()));}}}
 for(owner,var)in [("/datum/auto_case","value"),("/datum/auto_case","missing_candidate"),("/missing_type","x")]{candidates.insert((owner.into(),var.into()));}
 let exclude=vec!["other_var".into(),"/datum/auto_case::excluded_x".into()];
 let old=original::decide(&engine.tree,&sem,&candidates,&exclude);let shared=dq_analyze::gens::auto_tracked::decide(&engine.tree,&sem,&candidates,&exclude);
 let old=serde_json::json!({"tracked":old.tracked.iter().map(|a|(&a.ty,&a.var,a.list)).collect::<Vec<_>>(),"blocked":old.blocked});let shared=serde_json::json!({"tracked":shared.tracked.iter().map(|a|(&a.ty,&a.var,a.list)).collect::<Vec<_>>(),"blocked":shared.blocked});assert_eq!(old,shared,"whole original ordered decision and refusal-text result");assert!(!old["tracked"].as_array().unwrap().is_empty());assert!(!old["blocked"].as_array().unwrap().is_empty());println!("{}",serde_json::to_string(&old).unwrap());
}
