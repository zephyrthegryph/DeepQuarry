//! Independent original annotation producer versus the shared policy.
//! Oracle-only legacy executable; never a native producer dependency.
use dq_analyze::{pat,sem};
mod ast{pub use dq_analyze::sem::ast::*;}
use dq_analyze::sem::reads::{Annotations,LookupDeclaration,ProcSummary};
use dq_analyze::sem::decls::{Decls,split_args};
use dq_analyze::sem::ast::as_ident;
use dq_analyze::sem::Sem;
use std::{collections::{HashMap,HashSet},path::PathBuf};
use dreammaker::ast::{Expression,Term};
mod original{
 use super::*;
 include!(concat!(env!("CARGO_MANIFEST_DIR"),"/examples/support/reactive_annotations_original/producer.rs"));
}
fn rows(a:&Annotations)->Vec<String>{
 let mut out=Vec::new();
 out.extend(a.reads_as.iter().map(|(k,v)|format!("reads_as|{k:?}|{v:?}")));
 out.extend(a.reads_from.iter().map(|(k,v)|format!("reads_from|{k:?}|{v:?}")));
 out.extend(a.lookups.iter().map(|(k,v)|format!("lookups|{k:?}|{v:?}")));
 out.extend(a.accessors.iter().map(|(k,v)|format!("accessors|{k:?}|{v:?}")));
 out.extend(a.capkey_accessors.iter().map(|(k,v)|format!("capkey_accessors|{k:?}|{v:?}")));
 out.extend(a.summaries.iter().map(|(k,v)|format!("summaries|{k:?}|{v:?}")));
 out.extend(a.relations.iter().map(|(k,v)|{let mut names:Vec<_>=v.iter().collect();names.sort();format!("relations|{k:?}|{names:?}")}));
 out.sort();out
}
fn main()->Result<(),Box<dyn std::error::Error>>{
 use dq_analyze::run::{registry,Engine,Options};
 let root=PathBuf::from(std::env::args().nth(1).ok_or("fixture root required")?);
 let root=if root.is_absolute(){root}else{std::env::current_dir()?.join(root)};
 let engine=Engine::new(registry(),Options{root:root.clone(),scopes_from:Some(root.clone()),raw:true,no_cache:true,..Default::default()})?;
 let sem=sem::sem_for(&engine.tree).ok_or("independent old semantic owner absent")?;
 if !sem.errors.is_empty(){return Err(format!("original fixture parse errors: {:?}",sem.errors).into());}
 let decls=Decls::get(&engine.tree);let expected=original::get(&sem,&decls);let actual=Annotations::get(&sem,&decls);
 let expected=rows(&expected);let actual=rows(&actual);
 if expected!=actual{return Err(format!("complete annotation tables differ\nold={expected:#?}\nshared={actual:#?}").into());}
 for family in["reads_as|","reads_from|","lookups|","relations|","accessors|","capkey_accessors|","summaries|"]{
  if !expected.iter().any(|r|r.starts_with(family)){return Err(format!("independent old fixture lacks {family}").into());}
 }
 println!("original/shared reactive annotation tables exact: {} rows",expected.len());Ok(())
}
