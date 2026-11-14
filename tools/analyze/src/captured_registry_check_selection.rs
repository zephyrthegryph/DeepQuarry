//! Registry-derived selection DATA for native CHECK, never source completeness.
//! The existing real producer coordinator still owes every selected fold/EOF.
use crate::{captured_generator_budget::Budget,captured_reactive_reads::Failure,key_policy_control::{self as kc,Control},captured_allow_annotations::Operation};
use std::{io,sync::Arc};
/// Exact existing Select matcher; callers still owe actual filesystem evidence.
pub fn matches_meta_path(meta:&crate::lint::Meta,relative:&str)->bool{meta.select.matches_path(relative)}
/// Directory intersection of the SAME declared Select roots, with component
/// boundaries and hidden policy retained. Traversal receipts remain separate.
pub fn matches_meta_directory(meta:&crate::lint::Meta,relative:&str)->bool{matches_select_directory(&meta.select,relative)}
/// Actual full declaration environment needed by a selected semantic model.
pub fn matches_model_declaration_path(relative:&str)->bool{crate::tree::CODE_DM.matches_path(relative)}
pub fn matches_model_declaration_directory(relative:&str)->bool{matches_select_directory(&crate::tree::CODE_DM,relative)}
fn matches_select_directory(select:&crate::tree::Select,relative:&str)->bool{
 let relative=relative.trim_end_matches('/');
 if !select.hidden&&relative.split('/').any(|part|part.starts_with('.')){return false}
 select.roots.iter().any(|(root,_)|{let root=root.trim_end_matches('/');relative.is_empty()||root.is_empty()||relative==root||relative.strip_prefix(root).is_some_and(|tail|tail.starts_with('/'))||root.strip_prefix(relative).is_some_and(|tail|tail.starts_with('/'))})
}
pub struct Selection{names:Vec<String>,exclusions:Vec<String>,full_run:bool}
impl Selection{
 pub fn names(&self)->&[String]{&self.names}pub fn exclusions(&self)->&[String]{&self.exclusions}pub fn full_run(&self)->bool{self.full_run}
 pub fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){for rows in [&self.names,&self.exclusions]{visit(rows.as_ptr()as usize,rows.len()*std::mem::size_of::<String>(),rows.capacity()*std::mem::size_of::<String>());for row in rows{visit(row.as_ptr()as usize,row.len(),row.capacity())}}}
}
pub fn select(selectors:&[String],budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<Selection,Failure>{
 let mut work=Operation{budget,poll};select_using(selectors,&mut work)
}
pub fn select_using<C:Control<Error=Failure>>(selectors:&[String],work:&mut C)->Result<Selection,Failure>{
 let mut names=Vec::<String>::new();let mut exclusions=Vec::<String>::new();
 crate::allow_registry_fields::visit_all_scopes(work,&mut|meta,work|{
  work.checkpoint()?;
  if names.iter().any(|name|name==meta.name)||exclusions.iter().any(|name:&String|name.strip_prefix('-')==Some(meta.name)){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,"registered CHECK metadata repeats a policy name")))}
  if crate::cli_arguments::lint_selected(meta.name,meta.group,selectors){kc::row(work,&mut names)?;names.push(kc::own(work,meta.name)?);}
  else{kc::row(work,&mut exclusions)?;exclusions.push(kc::format(work,format_args!("-{}",meta.name))?);}Ok(())
 })?;
 if names.is_empty(){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,kc::format(work,format_args!("no lint matches {:?}",selectors))?)))}
 work.checkpoint()?;Ok(Selection{names,exclusions,full_run:crate::cli_arguments::full_check_selection(selectors)})
}
#[cfg(test)]mod tests{
 use super::*;
 #[test]fn metadata_selection_preserves_original_positive_negative_group_unknown_and_registry_order(){
  let b=Budget::new(1<<20).unwrap();let all=select(&[],&b,&||Ok(())).unwrap();assert!(all.full_run());assert!(all.names().len()>3);
  let positive=select(&["scheduler".into()],&b,&||Ok(())).unwrap();assert_eq!(positive.names(),["scheduler"]);assert!(!positive.full_run());
  let exclude=select(&["-scheduler".into()],&b,&||Ok(())).unwrap();assert!(exclude.full_run());assert_eq!(exclude.names().iter().map(String::as_str).collect::<Vec<_>>(),all.names().iter().map(String::as_str).filter(|name|*name!="scheduler").collect::<Vec<_>>());
  let group=select(&["sem".into(),"-sem/reads".into(),"sem".into(),"unknown-positive".into()],&b,&||Ok(())).unwrap();assert!(!group.full_run());assert!(!group.names().iter().any(|n|n=="sem/reads"));assert!(group.names().iter().any(|n|n=="sem/keys"));let positions=group.names().iter().map(|name|all.names().iter().position(|all|all==name).unwrap()).collect::<Vec<_>>();assert!(positions.windows(2).all(|pair|pair[0]<pair[1]));
  assert!(select(&["no-such-lint-or-group".into()],&b,&||Ok(())).is_err());
 }
 #[test]fn metadata_selection_preserves_first_real_io_before_any_source_claim(){let b=Budget::new(1<<20).unwrap();let error=select(&[],&b,&||Err(io::Error::from_raw_os_error(1450))).err().unwrap();assert!(matches!(error,Failure::Operational(actual)if actual.raw_os_error()==Some(1450)));}
}

#[cfg(test)]mod productive_directory_controls{
 #[test]fn declared_roots_keep_component_boundaries_and_hidden_policy(){
  let meta=crate::doc_snippets_policy::metadata();
  for path in ["", "doc", "doc/rewrite", "code", "code/host"]{assert!(super::matches_meta_directory(meta,path),"{path}")}
  for path in ["doc/rewriter", "codes", "code/.hidden"]{assert!(!super::matches_meta_directory(meta,path),"{path}")}
  assert!(super::matches_meta_path(meta,"doc/rewrite/kernel.md"));assert!(!super::matches_meta_path(meta,"doc/rewrite/kernel.dm"));
 }
}
