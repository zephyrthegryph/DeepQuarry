//! Independent actual Sem::build subject selection, with no native source/model.
#[path="../../dmb/shared/test_scratch.rs"]mod test_scratch;
#[path="../../dmb/fixtures/unified_analysis_subject/source.rs"]mod fixture;
fn main()->Result<(),Box<dyn std::error::Error>>{
 for mode in fixture::MODES{let root=test_scratch::dir(&format!("old-analysis-subject-{mode}"));for(relative,bytes)in fixture::files(mode){let path=root.join(relative);std::fs::create_dir_all(path.parent().ok_or("fixture parent absent")?)?;std::fs::write(path,bytes)?;}
  let mut plan=dq_analyze::tree::Plan::default();plan.add("code","dm");let(tree,_)=dq_analyze::tree::Tree::load(&root,&plan,&Default::default(),true);let subject=dq_analyze::sem::Sem::build(&root,&tree)?;if !subject.errors.is_empty(){return Err(format!("actual original subject errors {mode}: {:?}",subject.errors).into())}
  let mut types:Vec<_>=subject.type_paths().into_iter().map(|path|{let parent=subject.parent_of(&path);(path,parent)}).collect();types.sort();println!("OLD_ANALYSIS_SUBJECT={}",serde_json::json!({"schema":"original-analysis-whole-subject-v1","case":mode,"types":types}));
 }Ok(())
}
