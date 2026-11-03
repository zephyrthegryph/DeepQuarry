//! Independent pinned original Sem parser/preprocessor causality oracle.
#[path="../../dmb/shared/test_scratch.rs"]mod test_scratch;
#[path="../../dmb/fixtures/unified_original_preprocess_prefix/fixture.rs"]mod fixture;
use sha2::Digest;
fn main()->Result<(),Box<dyn std::error::Error>>{
 for(name,source,suffix)in fixture::CASES{
  let root=test_scratch::dir(&format!("old-preprocess-prefix-{name}"));std::fs::create_dir(root.join("code"))?;let manifest=format!("#include \"code/probe.dm\"\n{suffix}");std::fs::write(root.join("deepquarry.dme"),manifest.as_bytes())?;std::fs::write(root.join("code/probe.dm"),source.as_bytes())?;
  let mut plan=dq_analyze::tree::Plan::default();plan.add("code","dm");let(tree,_)=dq_analyze::tree::Tree::load(&root,&plan,&Default::default(),true);
  let observation=match dq_analyze::sem::Sem::build(&root,&tree){Ok(model)=>serde_json::json!({"model_available":true,"errors":model.errors,"type_paths":model.type_paths(),"good_declared":model.global_proc("good").is_some(),"bad_declared":model.global_proc("bad").is_some()}),Err(actual)=>serde_json::json!({"build_error":actual.to_string()})};
  println!("ORIGINAL_PREPROCESS_PREFIX={}",serde_json::json!({"schema":"actual-original-preprocess-prefix-v1","case":name,"source_sha256":format!("{:x}",sha2::Sha256::digest(source.as_bytes())),"manifest_sha256":format!("{:x}",sha2::Sha256::digest(manifest.as_bytes())),"actual":observation}));
 }Ok(())
}
