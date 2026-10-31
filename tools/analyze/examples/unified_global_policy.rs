//! Independent frozen globals/write policies against the shared unique judge.
//! Old parser exists only in this explicitly enabled migration oracle.
pub use dq_analyze::sem::{Sem,ast,body_facts};
#[path="support/globals_original.rs"]mod old_globals;
#[path="support/writes_original.rs"]mod old_writes;
pub mod reads {
 pub use dq_analyze::sem::reads::is_test_code;
 pub fn lvalue_name_of(t:&dreammaker::ast::Spanned<dreammaker::ast::Term>,f:&[dreammaker::ast::Spanned<dreammaker::ast::Follow>])->Option<String>{super::old_writes::lvalue_name_of(t,f)}
}
fn canonical(v:&mut serde_json::Value){match v{serde_json::Value::Array(values)=>{for v in values.iter_mut(){canonical(v)}values.sort_by_key(|v|v.to_string());},serde_json::Value::Object(fields)=>{for v in fields.values_mut(){canonical(v)}},_=>()}}
fn main(){
 let root=std::path::PathBuf::from(std::env::args().nth(1).expect("fixture root"));
 let engine=dq_analyze::run::Engine::new(dq_analyze::run::registry(),dq_analyze::run::Options{root:std::fs::canonicalize(root).unwrap(),no_cache:true,raw:true,..Default::default()}).unwrap();
 let sem=dq_analyze::sem::sem_for(&engine.tree).expect("real independent original parser model");
 assert!(sem.errors.is_empty(),"original fixture parse errors: {:?}",sem.errors);
 // This isolated oracle disables the real legacy stores through Options.
 // Both frozen builders must actually scan, rather than share disk answers.
 assert!(dq_analyze::incr::dir().is_none(),"old body-index stores must be disabled");
 let old=old_globals::GlobalIndex::build(&sem);let shared=dq_analyze::sem::globals::GlobalIndex::build(&sem);
 let old_writes=old_writes::WriteIndex::build(&sem);let shared_writes=dq_analyze::sem::reads::WriteIndex::build(&sem);
 assert!(dq_analyze::incr::dir().is_none());
 let mut original=serde_json::json!({"globals":old,"writes":old_writes});let mut candidate=serde_json::json!({"globals":shared,"writes":shared_writes});canonical(&mut original);canonical(&mut candidate);assert_eq!(original,candidate,"whole original boot/global/typed-write classifications");
 let globals=&original["globals"];assert!(!globals["runtime_written"].as_array().unwrap().is_empty());assert!(globals["boot_procs"].as_u64().unwrap()>0);assert!(!original["writes"]["untyped"].as_array().unwrap().is_empty());
 println!("{}",serde_json::to_string_pretty(&original).unwrap());
}
