//! Independent actual old Sem::build/proc_body availability oracle. It does not
//! share a native parser, graph, body receipt, source owner or expected outcome.
#[path="../../dmb/shared/test_scratch.rs"]mod test_scratch;
#[path="../../dmb/fixtures/unified_original_body_outcomes/fixture.rs"]mod fixture;
use sha2::Digest;
fn main()->Result<(),Box<dyn std::error::Error>>{
 let cases:Vec<(String,String)>=match std::env::args().nth(1){Some(path)=>{use std::io::Read;let mut bytes=Vec::new();std::fs::File::open(path)?.take(1024*1024+1).read_to_end(&mut bytes)?;if bytes.len()>1024*1024{return Err("original fixture input exceeds one MiB".into())}let rows:Vec<(String,String)>=serde_json::from_slice(&bytes)?;if rows.len()>256{return Err("original fixture input exceeds256 cases".into())}rows},None=>fixture::CASES.iter().map(|(name,body)|(name.to_string(),body.to_string())).collect()};
 for(name,body)in &cases{
  let root=test_scratch::dir(&format!("old-body-disposition-{name}"));std::fs::create_dir(root.join("code"))?;let source=fixture::source(body);std::fs::write(root.join("deepquarry.dme"),b"#include \"code/probe.dm\"
")?;std::fs::write(root.join("code/probe.dm"),&source)?;
  let mut plan=dq_analyze::tree::Plan::default();plan.add("code","dm");let(tree,_)=dq_analyze::tree::Tree::load(&root,&plan,&Default::default(),true);let model=dq_analyze::sem::Sem::build(&root,&tree)?;
  let mut procs=Vec::new();for name in["before","probe","after"]{let value=model.global_proc(name).map(|p|model.proc_body(p));procs.push(serde_json::json!({"name":name,"declared":value.is_some(),"code_some":value.as_ref().map(|v|v.code.is_some()),"parameters":value.as_ref().map(|v|v.params.len())}));}
  println!("ORIGINAL_BODY_DISPOSITION={}",serde_json::json!({"schema":"actual-original-body-disposition-v1","case":name,"source_sha256":format!("{:x}",sha2::Sha256::digest(source.as_bytes())),"model_available":true,"later_type_declared":model.type_paths().contains(&"/datum/later".to_owned()),"procs":procs,"actual_parser_errors":model.errors}));
 }Ok(())
}
