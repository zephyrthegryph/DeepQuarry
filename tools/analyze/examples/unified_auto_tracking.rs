//! Independent frozen globals/write policies against the shared unique judge.
//! Old parser exists only in this explicitly enabled migration oracle.
pub use dq_analyze::sem::{Sem,ast,body_facts};
#[path="support/globals_original.rs"]mod old_globals;
#[path="support/writes_original.rs"]mod old_writes;
pub mod reads {
 pub use dq_analyze::sem::reads::is_test_code;
 pub fn lvalue_name_of(t:&dreammaker::ast::Spanned<dreammaker::ast::Term>,f:&[dreammaker::ast::Spanned<dreammaker::ast::Follow>])->Option<String>{super::old_writes::lvalue_name_of(t,f)}
}

/// Oracle-only public equivalent. rel() adds a footprint touch, harmless here:
/// these independent runs disable every store and never compare footprints.
fn file_of_public(sem:&dq_analyze::sem::Sem,loc:dreammaker::Location)->Option<&str>{
 if loc.is_builtins(){return None}let rel=sem.rel(loc);(!rel.is_empty()).then_some(rel)
}

fn main(){
 let root=std::path::PathBuf::from(std::env::args().nth(1).expect("fixture root"));
 let engine=dq_analyze::run::Engine::new(dq_analyze::run::registry(),dq_analyze::run::Options{root:std::fs::canonicalize(root).unwrap(),no_cache:true,raw:true,..Default::default()}).unwrap();
 let sem=dq_analyze::sem::sem_for(&engine.tree).expect("independent original model");assert!(engine.tree.files.iter().all(|f|!f.rel.is_empty()));assert!(sem.errors.is_empty(),"{:?}",sem.errors);assert!(dq_analyze::incr::dir().is_none());
 let procs:Vec<dreammaker::objtree::ProcRef>=sem.objtree.iter_types().flat_map(|t|t.iter_self_procs().collect::<Vec<_>>()).filter(|p|!p.is_builtin()&&!matches!(file_of_public(&sem,p.get().location),Some("code/engine/_generated/auto_tracked.dm")|Some("code/engine/_generated/tracked_lists.dm"))).collect();
 let facts=procs.into_iter().map(|p|{let mut writes=old_writes::typed_writes(&sem,p);if let Some(v)=p.name().strip_prefix("set_"){writes.retain(|(_,var)|var!=v);}writes}).collect();
 let outside=old_writes::WriteIndex::from_facts(facts);
 let value=serde_json::json!({"globals":old_globals::GlobalIndex::build(&sem),"writes":old_writes::WriteIndex::build(&sem),"outside_setters":outside});
 let written=value["outside_setters"]["written"].as_array().unwrap();assert!(written.iter().any(|v|v=="changed"));for excluded in ["self_only","other_var","ctor_only","generated_only"]{assert!(!written.iter().any(|v|v==excluded),"{excluded}");}println!("{}",serde_json::to_string(&value).unwrap());
}
