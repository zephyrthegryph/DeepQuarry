//! Shared original four-site CheckGrep fixture. No semantic model/parser/cache.
//! The native caller must lend the actual caller-CWD .gitignore observation;
//! this module never reads it or claims that a supplied None is a captured fact.
use crate::{derived_selftest_policy::Failure,key_policy_control::{self as kc,Control}};
pub const REL:&str="code/a.dm";
pub const SOURCE:&str="/mob/proc/Life()\n  x\n\tisSynthetic(M) // ALLOW(check_grep): kept\n\tisSynthetic(M)\nno newline";
const WANT:[(&str,usize);4]=[("life_no_life_procs",1),("space_indentation",2),("biology_no_issynthetic",4),("trailing_newlines",5)];
pub fn assert_sites<C:Control<Error=Failure>,T:Control<Error=Failure>>(got:&mut[(String,usize)],keep:&mut C,temp:&mut T)->Result<String,Failure>{
 keep.checkpoint()?;
 // Reserve actual stable-sort scratch before sorting, including unexpected rows.
 kc::reserve(temp,||got.len().checked_mul(std::mem::size_of::<(String,usize)>())?.checked_mul(2))?;
 got.sort_by_key(|(_,line)|*line);
 if got.len()!=WANT.len()||got.iter().zip(WANT).any(|((rule,line),(want,at))|rule!=want||*line!=at){return Err(Failure::Assertion(kc::format(keep,format_args!("unexpected sites {:?}",got))?))}
 keep.checkpoint()?;Ok(String::new())
}
#[cfg(feature="native-policy")]
pub fn run_native(ignore_text:Option<&str>,budget:&std::sync::Arc<crate::captured_generator_budget::Budget>,poll:&dyn Fn()->std::io::Result<()>)->Result<String,Failure>{
 use crate::derived_selftest_policy::NativeAssertions;
 let mut keep=NativeAssertions{budget,poll};let mut temp=NativeAssertions{budget,poll};keep.checkpoint()?;
 let mut got=Vec::new();
 let mut ignored=false;
 if let Some(text)=ignore_text{for line in text.lines(){keep.checkpoint()?;if super::ignored_outputs(line).any(|path|path==REL){ignored=true;break;}}}
 if !ignored{
  // Only these fixed, newline-normalized fixture bytes are accepted. Four
  // existing split envelopes prepay raw/code/clean/marker source views and the
  // bounded constructor's metadata; its smaller child ledger grants no memory.
  let room=kc::split_bound(SOURCE.len()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(std::mem::size_of::<crate::tree::SourceFile>())).ok_or_else(||temp.overflow())?;
  kc::reserve(&mut temp,||room.checked_add(SOURCE.len().checked_mul(4)?)?.checked_add(REL.len().checked_mul(8)?)?.checked_add(128))?;
  let file=crate::tree::SourceFile::from_shared_budgeted(REL,std::path::PathBuf::from(REL),SOURCE.to_owned().into(),room).map_err(|message|{budget.deny();Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message))})?;
  let actual=super::native::scan_static_file(&crate::scopes::LintScope::default(),budget,poll,&file).map_err(|failure|match failure{
   crate::captured_reactive_reads::Failure::Operational(error)=>Failure::Operational(error),
   crate::captured_reactive_reads::Failure::Unsupported(message)=>Failure::Operational(std::io::Error::new(std::io::ErrorKind::Unsupported,message)),
  })?;
  if let Some(message)=file.captured_budget_error(){budget.deny();return Err(Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message)))}
  for site in actual.run.sites{keep.checkpoint()?;kc::row(&mut keep,&mut got)?;got.push((site.rule,site.line as usize));}
 }
 assert_sites(&mut got,&mut keep,&mut temp)
}
#[cfg(all(test,feature="native-policy"))]mod tests{
 use super::*;use crate::captured_generator_budget::Budget;
 #[test]fn native_check_grep_selftest_runs_same_four_sites_without_legacy_model_or_disk(){let b=Budget::new(8<<20).unwrap();assert!(run_native(None,&b,&||Ok(())).unwrap().is_empty());}
 #[test]fn native_check_grep_selftest_uses_actual_supplied_ignore_semantics_and_preserves_failure_text(){let b=Budget::new(8<<20).unwrap();assert!(matches!(run_native(Some("/code/a.dm\n"),&b,&||Ok(())),Err(Failure::Assertion(text))if text=="unexpected sites []"));}
 #[test]fn native_check_grep_selftest_preserves_first_operational_io(){let b=Budget::new(8<<20).unwrap();let Err(Failure::Operational(error))=run_native(None,&b,&||Err(std::io::Error::from_raw_os_error(1450)))else{panic!("actual first IO")};assert_eq!(error.raw_os_error(),Some(1450));}
 #[test]fn native_check_grep_selftest_quota_failure_is_not_a_semantic_fixture_failure(){let b=Budget::new(128).unwrap();let Err(Failure::Operational(error))=run_native(None,&b,&||Ok(()))else{panic!("actual paid fixture bound")};assert_eq!(error.kind(),std::io::ErrorKind::OutOfMemory);}
}
