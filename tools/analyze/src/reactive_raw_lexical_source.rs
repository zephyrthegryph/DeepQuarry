//! Lexical-only policy DATA loan. No semantic tree, compiled member, Globals,
//! unavailable-model witness or completion role can be requested through it.
use crate::{captured_generator_budget::Budget,reactive_reads_native::Failure};
use std::{io,sync::Arc};
pub(crate) trait Source{
 fn budget(&self)->&Arc<Budget>;
 fn checkpoint(&self)->io::Result<()>;
 fn require(&self)->Result<(),Failure>;
 fn reserve(&self,bytes:Option<usize>)->Result<(),Failure>;
 fn with_reaction_code(&self,hint:&str,visit:&mut dyn FnMut(&str,&crate::tree::View)->Result<bool,Failure>)->Result<(),Failure>;
}
/// Stack-only loan from the existing genuine semantic source. No source copy,
/// new resource counter or changed operation frontier is introduced.
pub(crate) struct SemanticLoan<'a>(&'a dyn crate::reactive_global_source::Source);
impl<'a> SemanticLoan<'a>{pub(crate) fn borrow(source:&'a dyn crate::reactive_global_source::Source)->Self{Self(source)}}
impl Source for SemanticLoan<'_>{
 fn budget(&self)->&Arc<Budget>{self.0.budget()}
 fn checkpoint(&self)->io::Result<()>{self.0.checkpoint()}
 fn require(&self)->Result<(),Failure>{self.0.require()}
 fn reserve(&self,bytes:Option<usize>)->Result<(),Failure>{self.0.reserve(bytes)}
 fn with_reaction_code(&self,hint:&str,visit:&mut dyn FnMut(&str,&crate::tree::View)->Result<bool,Failure>)->Result<(),Failure>{self.0.with_reaction_code(hint,visit)}
}

#[cfg(test)]mod tests{
 use super::*;use std::cell::Cell;
 struct Raw{file:crate::captured_raw_file::File,budget:Arc<Budget>,fail:Cell<bool>,loans:Cell<usize>}
 impl Source for Raw{
  fn budget(&self)->&Arc<Budget>{&self.budget}
  fn checkpoint(&self)->io::Result<()>{if self.fail.get(){Err(io::Error::from_raw_os_error(1450))}else{Ok(())}}
  fn require(&self)->Result<(),Failure>{self.budget.require().map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))}
  fn reserve(&self,bytes:Option<usize>)->Result<(),Failure>{let bytes=bytes.ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;self.budget.charge(bytes).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))}
  fn with_reaction_code(&self,hint:&str,visit:&mut dyn FnMut(&str,&crate::tree::View)->Result<bool,Failure>)->Result<(),Failure>{self.checkpoint()?;self.require()?;self.loans.set(self.loans.get()+1);self.file.with_policy_views(&mut|relative,views|{if !views.raw()?.contains(hint){return Ok(true)}visit(relative,views.code()?)})?;self.require()}
 }
 fn raw(limit:usize)->Raw{let root=std::env::current_dir().unwrap().join("raw-derived-no-semantic-model");let text="/datum/probe\n    var/value\n/datum/probe/draw()\n    return value\n";Raw{file:crate::captured_raw_file::File::capture(&root,&root.join("code/probe.dm"),text.into()).unwrap(),budget:Budget::new(limit).unwrap(),fail:Cell::new(false),loans:Cell::new(0)}}
 #[test]fn lexical_derived_data_core_requires_no_semantic_tree_or_globals(){let source=raw(8*1024*1024);let result=crate::reactive_derived_generator_native::generate_raw(&source,&Default::default()).unwrap();assert!(result.contains("/datum/probe/generated_reads()"));assert!(result.contains("drawn_from(nameof(value))"));assert!(source.loans.get()>1);assert_eq!(crate::reactive_reaction_native::raw_has_variable_raw(&source,"/datum/probe","value").unwrap(),true);assert!(!crate::reactive_reaction_native::raw_has_variable_raw(&source,"/datum/probe","not_declared").unwrap());}
 #[test]fn lexical_data_core_preserves_actual_io_quota_and_fresh_recovery(){let source=raw(8*1024*1024);source.fail.set(true);assert!(matches!(crate::reactive_derived_generator_native::generate_raw(&source,&Default::default()),Err(Failure::Operational(ref e))if e.raw_os_error()==Some(1450)));assert_eq!(source.loans.get(),0);source.fail.set(false);assert!(crate::reactive_derived_generator_native::generate_raw(&source,&Default::default()).is_ok());let tiny=raw(256);assert!(matches!(crate::reactive_derived_generator_native::generate_raw(&tiny,&Default::default()),Err(Failure::Operational(ref e))if e.kind()==io::ErrorKind::OutOfMemory));let fresh=raw(8*1024*1024);assert!(crate::reactive_derived_generator_native::generate_raw(&fresh,&Default::default()).unwrap().contains("nameof(value)"));}
}
