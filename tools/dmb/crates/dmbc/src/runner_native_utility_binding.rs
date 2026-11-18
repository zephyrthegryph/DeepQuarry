//! Fallible owned utility Binding copy under the current request's SAME work.
//! This is DATA custody only; no source/model/currentness grant is manufactured.
use std::{io,mem::size_of};
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaWork};
use dq_analyze::native_codemod_fixture_wire::{Binding,Question,SourceFrame,FrozenOracleBinding};
/// Payload first, credit last. The wrapper must keep the returned credit until
/// its report/terminal has adopted the actual payload, including error paths.
pub(crate)struct OwnedBinding{binding:Binding,credit:SourceArenaCredit}
impl OwnedBinding{pub(crate)fn binding(&self)->&Binding{&self.binding}pub(crate)fn into_parts(self)->(Binding,SourceArenaCredit){(self.binding,self.credit)}}
pub(crate)fn vector<T>(count:usize,work:&dyn SourceArenaWork,credit:&mut SourceArenaCredit)->io::Result<Vec<T>>{
 work.checkpoint()?;let frontier=count.checked_mul(4).ok_or(io::ErrorKind::OutOfMemory)?;let paid=frontier.checked_mul(size_of::<T>()).ok_or(io::ErrorKind::OutOfMemory)?;work.grow(credit,paid)?;
 let mut actual=Vec::new();actual.try_reserve_exact(count).map_err(|first|io::Error::new(io::ErrorKind::OutOfMemory,first))?;if actual.capacity()>frontier{return Err(io::ErrorKind::OutOfMemory.into())}
 let retained=actual.capacity().checked_mul(size_of::<T>()).ok_or(io::ErrorKind::OutOfMemory)?;work.shrink(credit,paid.checked_sub(retained).ok_or(io::ErrorKind::OutOfMemory)?)?;Ok(actual)
}
pub(crate)fn clone_binding(binding:&Binding,work:&dyn SourceArenaWork)->io::Result<OwnedBinding>{
 binding.validate()?;work.checkpoint()?;let mut credit=work.reserve(size_of::<OwnedBinding>())?;
 let root=dm_preprocess::regions::copy_path_into_credit(&binding.root,work,&mut credit)?;
 let question=match &binding.question{
  Question::CodemodList=>Question::CodemodList,
  Question::Codemod{name,apply,revert,write_residue,sites,paths}=>{
   let name=dm_preprocess::regions::copy_string_into_credit(name,work,&mut credit)?;let mut copied=vector(paths.len(),work,&mut credit)?;
   for path in paths{work.checkpoint()?;copied.push(dm_preprocess::regions::copy_string_into_credit(path,work,&mut credit)?);}
   Question::Codemod{name,apply:*apply,revert:*revert,write_residue:*write_residue,sites:*sites,paths:copied}
  },
  Question::Parity{selectors,fixtures_only,bless,oracle}=>{
   let mut copied=vector(selectors.len(),work,&mut credit)?;for selector in selectors{copied.push(dm_preprocess::regions::copy_string_into_credit(selector,work,&mut credit)?);}
   let image=dm_preprocess::regions::copy_path_into_credit(&oracle.image,work,&mut credit)?;let sha256=dm_preprocess::regions::copy_string_into_credit(&oracle.sha256,work,&mut credit)?;
   Question::Parity{selectors:copied,fixtures_only:*fixtures_only,bless:*bless,oracle:FrozenOracleBinding{image,sha256}}
  },
  Question::Fixture{lint,bless}=>Question::Fixture{lint:dm_preprocess::regions::copy_string_into_credit(lint,work,&mut credit)?,bless:*bless},
 };
 work.checkpoint()?;Ok(OwnedBinding{binding:Binding{schema:binding.schema,root,question},credit})
}
#[cfg(test)]mod controls{
 use super::*;
 fn binding()->Binding{Binding{schema:dq_analyze::native_codemod_fixture_wire::Schema::V2,root:std::path::PathBuf::from(if cfg!(windows){"E:/actual/root"}else{"/actual/root"}),question:Question::Codemod{name:"own_set".into(),apply:true,revert:true,write_residue:false,sites:true,paths:vec!["code/first".into(),"maps/next".into()]}}}
 #[test]fn actual_copied_binding_is_equal_independent_and_retains_credit_after_the_original_drops(){let work=crate::query_db::QueryDb::default();let source=binding();let owned=clone_binding(&source,&work).unwrap();assert_eq!(owned.binding(),&source);let expected=source.clone();drop(source);let(value,credit)=owned.into_parts();assert_eq!(value,expected);let size=value.root.capacity()+match &value.question{Question::Codemod{paths,name,..}=>name.capacity()+paths.capacity()*size_of::<String>()+paths.iter().map(String::capacity).sum::<usize>(),_=>0};assert!(credit.reserved_bytes()>=size+size_of::<OwnedBinding>());drop(value);drop(credit);}
 struct Denied;impl SourceArenaWork for Denied{fn checkpoint(&self)->io::Result<()>{Ok(())}fn reserve(&self,_:usize)->io::Result<SourceArenaCredit>{Err(io::Error::from_raw_os_error(1450))}fn grow(&self,_:&mut SourceArenaCredit,_:usize)->io::Result<()>{Err(io::Error::from_raw_os_error(1450))}fn shrink(&self,_:&mut SourceArenaCredit,_:usize)->io::Result<()>{panic!("no settlement after actual initial denial")}}
 #[test]fn initial_binding_copy_denial_preserves_first_actual_os_error(){let error=clone_binding(&binding(),&Denied).err().unwrap();assert_eq!(error.raw_os_error(),Some(1450));}
}

