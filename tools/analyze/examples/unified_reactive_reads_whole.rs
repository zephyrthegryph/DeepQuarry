#![cfg(not(test))]
//! Whole frozen old read interpreter; only cache transport/type seams are projected.
pub use dq_analyze::{dm,gens,tree,sem};
pub use dq_analyze::sem::{Sem,ast,decls,walk_cache,body_facts,globals};
#[path="support/reactive_reads_original/projected.rs"]mod original;
#[derive(serde::Serialize)]struct Facts<'a>{
 reads:Vec<&'a original::Read>,ctx_fields:Vec<(&'a String,&'a(String,u32))>,sites:Vec<(&'a original::Read,&'a(String,u32))>,
 diags:&'a[original::Diag],lookup_diags:&'a[original::Diag],effects:&'a[original::Effect],followed:Vec<&'a String>,
 opaque:Vec<(&'a String,&'a(String,u32))>,internal:Vec<&'a original::Read>,sampled:Vec<&'a(String,u32)>,
}
fn relation_implementation(source:&str)->&str{
 let marker="impl Decls {";assert_eq!(source.matches(marker).count(),1,"relation policy block must be unique");let start=source.find(marker).unwrap();let end=start+source[start..].find("\n}\n").unwrap()+3;&source[start..end]
}
fn main(){
 assert_eq!(relation_implementation(include_str!("support/reactive_reads_original/producer.rs")),relation_implementation(include_str!("../src/sem/reads.rs")),"reused public relation chain must remain byte-identical to frozen original policy");
 let root=std::path::PathBuf::from(std::env::args().nth(1).expect("actual fixture root"));
 let host=dq_analyze::run::Engine::new(dq_analyze::run::registry(),dq_analyze::run::Options{root:std::fs::canonicalize(root).unwrap(),no_cache:true,raw:true,..Default::default()}).unwrap();
 let sem=Sem::build(&host.tree.root,&host.tree).expect("independent original parser");assert!(sem.errors.is_empty(),"old fixture parse errors: {:?}",sem.errors);
 assert!(dq_analyze::incr::dir().is_none(),"no cache may substitute an old interpreter answer");
 let declarations=decls::Decls::get(&host.tree);let annotations=original::Annotations::get(&sem,&declarations);
 for(name,context,closed)in [("leaf",None,true),("method_call",None,true),("global_wrapper",None,true),("global_wrapper",None,false),("contextual",Some("/datum/act/eval"),true),("virtual_probe",None,true)]{
  let base=original::ReadsEngine::new(&sem,&declarations,&annotations);let engine=if closed{base.closed()}else{base};
  let set=match context{Some(context)=>engine.analyze_handler("/datum/probe",name,context),None=>engine.analyze("/datum/probe",name)};
  let facts=Facts{reads:set.reads.iter().collect(),ctx_fields:set.ctx_fields.iter().collect(),sites:set.sites.iter().collect(),diags:&set.diags,lookup_diags:&set.lookup_diags,effects:&set.effects,followed:set.followed.iter().collect(),opaque:set.opaque.iter().collect(),internal:set.internal.iter().collect(),sampled:set.sampled.iter().collect()};
  assert!(!facts.reads.is_empty(),"old positive fixture must actually read: {name}/{closed}");
  println!("ORIGINAL_READ_FULL={}",serde_json::to_string(&serde_json::json!({"procedure":name,"context":context,"closed":closed,"facts":facts})).unwrap());
 }
 assert!(dq_analyze::incr::dir().is_none());
}
