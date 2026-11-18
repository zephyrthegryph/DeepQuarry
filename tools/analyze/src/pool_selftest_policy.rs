//! Same original Pool fixture assertions, using its existing native raw kernel.
//! Fixture DATA only: no Root, declaration or completed-source permission.
use crate::{captured_generator_budget::Budget,derived_selftest_policy::Failure,key_policy_control::{self as kc,Control},selftest_source_policy::{source,Views}};
use std::sync::Arc;
#[cfg(feature="native-policy")]
fn inspect(rows:&[(&str,&str)],budget:&Arc<Budget>,poll:&dyn Fn()->std::io::Result<()>)->Result<usize,Failure>{
 let mut keep=crate::derived_selftest_policy::NativeAssertions{budget,poll};let mut files=Vec::new();
 for(rel,text)in rows{kc::row(&mut keep,&mut files)?;files.push(source(rel,text,&mut keep)?)}
 let mut checked=Views{inner:&mut keep,files:&files};
 let mut pooled=std::collections::BTreeSet::new();
 for file in &files{
  let mut first=None;
  let facts=crate::pool_policy::facts_of(file,Some(budget),||match checked.checkpoint(){Ok(())=>Ok(()),Err(actual)=>{if first.is_none(){first=Some(actual)}Err("captured Pool fixture interrupted".into())}});
  if let Some(actual)=first{return Err(actual)}
  let facts=facts.map_err(|m|Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,m)))?;
  for name in facts.pooled{if !pooled.contains(&name){kc::reserve(&mut checked,||name.capacity().checked_add(128))?;pooled.insert(name);}}
 }
 let mut exemptions=Vec::new();for name in["code/tests/unit_tests/","code/library/lifecycle/pool.dm"]{kc::row(&mut checked,&mut exemptions)?;exemptions.push(kc::own(&mut checked,name)?)}
 let mut count=0usize;
 for file in &files{
  let mut first=None;
  let result=crate::pool_policy::judge(file,&pooled,&exemptions,Some(budget),||match checked.checkpoint(){Ok(())=>Ok(()),Err(actual)=>{if first.is_none(){first=Some(actual)}Err("captured Pool fixture interrupted".into())}},|_,_,_|{count=count.checked_add(1).ok_or_else(||"Pool fixture count overflow".to_owned())?;Ok(())});
  if let Some(actual)=first{return Err(actual)}
  result.map_err(|m|Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,m)))?;
 }
 checked.checkpoint()?;Ok(count)
}
pub trait Backend{fn inspect(&mut self,rows:&[(&str,&str)])->Result<usize,Failure>;}
pub fn assertions<B:Backend,C:Control<Error=Failure>>(backend:&mut B,c:&mut C)->Result<String,Failure>{
 let good="/datum/foo\n\tparent_type = /datum/pooled\n\n/proc/f()\n\tvar/datum/foo/F = take(/datum/foo)\n\tF.release()\n";
 let factory="/datum/foo\n\tparent_type = /datum/pooled\n\n/proc/factory()\n\tvar/datum/foo/packet = take(/datum/foo)\n\tpacket.zone = 1\n\treturn packet\n";
 kc::reserve(c,||factory.len().checked_mul(12)?.checked_add(1024))?;
 let reassigned=factory.replace("\tpacket.zone = 1","\tpacket = null");
 let conditional=factory.replace("\treturn packet","\tif(ok)\n\t\treturn packet");
 let multiple=factory.replace("\tpacket.zone = 1","\tvar/datum/foo/other = take(/datum/foo)");
 if backend.inspect(&[("factory.dm",factory)])?!=0||backend.inspect(&[("reassigned.dm",&reassigned)])?==0||backend.inspect(&[("conditional.dm",&conditional)])?==0||backend.inspect(&[("multiple.dm",&multiple)])?==0{return Err(Failure::Assertion(kc::own(c,"factory return contract misclassified")?))}
 if backend.inspect(&[("a.dm",good)])?!=0{return Err(Failure::Assertion(kc::own(c,"clean input flagged")?))}
 let bad_new="/proc/g()\n\tvar/datum/foo/F = new /datum/foo\n";
 if backend.inspect(&[("a.dm",good),("b.dm",bad_new)])?==0||backend.inspect(&[("a.dm","/datum/foo\n\tparent_type = /datum/pooled\n"),("c.dm","/proc/h()\n\treturn take(/datum/foo)\n")])?==0{return Err(Failure::Assertion(kc::own(c,"a violation went unflagged")?))}
 Ok(String::new())
}

#[cfg(feature="native-policy")]
pub fn run(budget:&Arc<Budget>,poll:&dyn Fn()->std::io::Result<()>)->Result<String,Failure>{
 struct Native<'a>{budget:&'a Arc<Budget>,poll:&'a dyn Fn()->std::io::Result<()>}
 impl Backend for Native<'_>{fn inspect(&mut self,rows:&[(&str,&str)])->Result<usize,Failure>{inspect(rows,self.budget,self.poll)}}
 assertions(&mut Native{budget,poll},&mut crate::derived_selftest_policy::NativeAssertions{budget,poll})
}
#[cfg(all(test,feature="native-policy"))]mod controls{
 use super::*;
 #[test]fn native_pool_callback_runs_every_original_factory_and_cross_file_assertion(){let b=Budget::new(crate::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();assert_eq!(run(&b,&||Ok(())).unwrap(),"");}
 #[test]fn native_pool_callback_preserves_first_io_and_real_quota_then_recovers(){let b=Budget::new(crate::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();assert!(matches!(run(&b,&||Err(std::io::Error::from_raw_os_error(1450))),Err(Failure::Operational(actual))if actual.raw_os_error()==Some(1450)));let b=Budget::new(1024).unwrap();assert!(matches!(run(&b,&||Ok(())),Err(Failure::Operational(actual))if actual.kind()==std::io::ErrorKind::OutOfMemory));let b=Budget::new(crate::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();assert!(run(&b,&||Ok(())).is_ok());}
}
