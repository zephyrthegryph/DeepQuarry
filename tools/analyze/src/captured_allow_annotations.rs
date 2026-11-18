//! Source-loaned per-file validation. This is an internal DATA fold, not a
//! complete source/public report issuer. Whole-unused deliberately has no native route.
use crate::{captured_raw_file::{Config,RawPolicyViews},allow_registry_metadata::CompleteRegistryAllowNames,key_policy_control::Control,captured_reactive_reads::Failure};
pub struct ConfigurationNames<'a>{names:&'a std::collections::BTreeSet<String>,_configuration:&'a Config}
/// Build the complete registry/config union once per operation, then lend it
/// across all actual raw-file callbacks. Neither names nor Config escape this loan.
pub fn with_names<C:Control<Error=Failure>,R>(registry:&CompleteRegistryAllowNames,configuration:&Config,control:&mut C,consume:impl FnOnce(&ConfigurationNames<'_>,&mut C)->Result<R,Failure>)->Result<R,Failure>{
 let pending=configuration.with_allow_known(|explicit|registry.with_config(explicit,control,|names,control|consume(&ConfigurationNames{names,_configuration:configuration},control)));if matches!(&pending,Err(Failure::Operational(_))){return pending}control.checkpoint()?;pending
}
pub fn validate_original<C:Control<Error=Failure>>(known:&ConfigurationNames<'_>,views:RawPolicyViews<'_>,control:&mut C,emit:impl FnMut(&'static str,usize,&str,&str)->Result<(),Failure>)->Result<(),Failure>{validate_original_borrowed(known,&views,control,emit)}
fn validate_original_borrowed<C:Control<Error=Failure>>(known:&ConfigurationNames<'_>,views:&RawPolicyViews<'_>,control:&mut C,mut emit:impl FnMut(&'static str,usize,&str,&str)->Result<(),Failure>)->Result<(),Failure>{
 let pending=(||{let raw=views.raw()?;if !raw.contains("ALLOW("){return Ok(())}for(number,raw_line)in raw.split('\n').enumerate(){crate::allow_annotation_policy::validate_line(known.names,number+1,raw_line,control,|rule,line,message|emit(rule,line,&message,raw_line))?;}Ok(())})();if matches!(&pending,Err(Failure::Operational(_))){return pending}control.checkpoint()?;pending
}
/// SAME private source FileScope funds only its real parser/reason temporaries;
/// caller separately funds retained copies while borrowed messages/lines live.
pub fn validate_original_budgeted(known:&ConfigurationNames<'_>,views:RawPolicyViews<'_>,fallback:&crate::captured_generator_budget::Budget,poll:&dyn Fn()->std::io::Result<()>,emit:impl FnMut(&'static str,usize,&str,&str)->Result<(),Failure>)->Result<(),Failure>{
 let local=views.allocation_budget(fallback);let mut control=Operation{budget:local,poll};validate_original_borrowed(known,&views,&mut control,emit)
}


/// Operation-local resource control; this grants no source or completion role.
pub struct Operation<'a>{pub budget:&'a crate::captured_generator_budget::Budget,pub poll:&'a dyn Fn()->std::io::Result<()>}
impl Control for Operation<'_>{type Error=Failure;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Failure>{self.budget.require().map_err(oom)?;(self.poll)()?;self.budget.require().map_err(oom)}fn reserve(&mut self,bytes:usize)->Result<(),Failure>{self.budget.charge(bytes).map_err(oom)}fn overflow(&mut self)->Failure{self.budget.deny();oom("ALLOW accounting overflow".to_owned())}fn allocation_failed(&mut self)->Failure{self.budget.deny();oom("ALLOW allocation refused".to_owned())}}
fn oom(message:String)->Failure{Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message))}
#[cfg(test)]mod tests{
 use super::*;use crate::{captured_generator_budget::Budget,captured_raw_file::File,captured_raw_policy::Configuration};
 #[test]fn actual_raw_file_validation_requires_real_full_registry_and_captured_known_configuration(){
  let root=std::env::current_dir().unwrap().join("allow-original-data");let budget=Budget::new(16*1024*1024).unwrap();let mut control=Operation{budget:&budget,poll:&||Ok(())};let registry=crate::allow_registry_metadata::complete_registry_allow_names(&mut control).unwrap();
  let config=Config::capture(Configuration::Captured(b"[allow]\nknown=[\"fixture_custom\"]\n")).unwrap();let file=File::capture(&root,&root.join("code/probe.dm"),"// ALLOW(fixture_custom): actual captured configuration declares this precise name\n// ALLOW(not_a_known_lint): this annotation must preserve its unknown verdict\n".to_owned().into()).unwrap();let mut rows=Vec::new();
  with_names(&registry,&config,&mut control,|names,control|{file.with_policy_views(&mut|_,views|{validate_original(names,views,control,|rule,line,message,_original|{budget.charge(message.len()*4+128).map_err(oom)?;rows.push((rule,line,message.to_owned()));Ok(())})?;Ok(true)})?;Ok(())}).unwrap();assert_eq!(rows.len(),1);assert_eq!(rows[0].0,"unknown_lint");assert_eq!(rows[0].1,2);assert!(rows[0].2.contains("fixture_custom"));
  let tiny_budget=Budget::new(128).unwrap();let late=||if tiny_budget.denied(){Err(std::io::ErrorKind::Interrupted.into())}else{Ok(())};let mut tiny=Operation{budget:&tiny_budget,poll:&late};let error=with_names(&registry,&config,&mut tiny,|_,_| -> Result<(),Failure> { panic!("metadata denial must precede raw loan") }).unwrap_err();assert!(matches!(error,Failure::Operational(ref actual)if actual.kind()==std::io::ErrorKind::OutOfMemory));
 }
 #[test]fn native_allow_semantic_callbacks_run_final_control_and_preserve_first_actual_io(){
  let root=std::env::current_dir().unwrap().join("allow-native-final-control");let budget=Budget::new(16*1024*1024).unwrap();let late=std::cell::Cell::new(false);let poll=||if late.get(){Err(std::io::ErrorKind::Interrupted.into())}else{Ok(())};let mut control=Operation{budget:&budget,poll:&poll};let registry=crate::allow_registry_metadata::complete_registry_allow_names(&mut control).unwrap();let config=Config::capture(Configuration::ProvenMissing).unwrap();let file=File::capture(&root,&root.join("code/probe.dm"),"// ALLOW():\n".to_owned().into()).unwrap();
  for actual in [false,true]{late.set(false);let error=with_names(&registry,&config,&mut control,|known,control|{file.with_policy_views(&mut|_,views|{validate_original(known,views,control,|_,_,_,_|{late.set(true);if actual{Err(Failure::Operational(std::io::Error::from_raw_os_error(1450)))}else{Err(Failure::Unsupported("actual native annotation consumer refused".into()))}})?;Ok(true)})?;Ok(())}).unwrap_err();match error{Failure::Operational(error)if actual=>assert_eq!(error.raw_os_error(),Some(1450)),Failure::Operational(error)=>assert_eq!(error.kind(),std::io::ErrorKind::Interrupted),Failure::Unsupported(message)=>panic!("native final control was bypassed: {message}")};
   late.set(false);let error=with_names(&registry,&config,&mut control,|_,_|->Result<(),Failure>{late.set(true);if actual{Err(Failure::Operational(std::io::Error::from_raw_os_error(1450)))}else{Err(Failure::Unsupported("actual name-loan consumer refused".into()))}}).unwrap_err();match error{Failure::Operational(error)if actual=>assert_eq!(error.raw_os_error(),Some(1450)),Failure::Operational(error)=>assert_eq!(error.kind(),std::io::ErrorKind::Interrupted),Failure::Unsupported(message)=>panic!("name-loan final control was bypassed: {message}")};
  }late.set(false);with_names(&registry,&config,&mut control,|known,control|{file.with_policy_views(&mut|_,views|{validate_original(known,views,control,|_,_,_,_|Ok(()))?;Ok(true)})?;Ok(())}).unwrap();
 }
 #[test]fn native_allow_parser_temporaries_retire_with_each_actual_original_file_scope(){
  let root=std::env::current_dir().unwrap().join("allow-file-scope");let path=root.join("code/probe.dm");let budget=Budget::new(16*1024*1024).unwrap();let mut control=Operation{budget:&budget,poll:&||Ok(())};let registry=crate::allow_registry_metadata::complete_registry_allow_names(&mut control).unwrap();let config=Config::capture(Configuration::ProvenMissing).unwrap();let fixed=std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>();let fallback=Budget::new(fixed).unwrap();
  with_names(&registry,&config,&mut control,|known,_|{let before=budget.used();for page in 0..80{let mut visits=0;crate::captured_raw_file::with_original_policy_file_prepared(&root,&path,0,&budget,|scratch|{scratch.charge(4096).map_err(oom)?;Ok(dm_preprocess::SourceText::from("// ALLOW(__never_a_registered_name__): world.Export() is a blocking external call\n"))},&mut|_,views|{validate_original_budgeted(known,views,&fallback,&||Ok(()),|rule,_,message,original|{assert_eq!(rule,"unknown_lint");assert!(message.contains("__never_a_registered_name__"));assert!(original.contains("ALLOW("));visits+=1;Ok(())})?;Ok(true)})?;assert_eq!(visits,1);assert_eq!(budget.used(),before+(page+1)*fixed,"only actual fixed scratch metadata may survive the physical File drop");assert_eq!(fallback.used(),fixed,"actual file allocation loan must bypass zero-headroom fallback");assert!(!fallback.denied());}Ok(())}).unwrap();
 }

}

/// Unsealed per-file validation DATA, never a source/execution completion.
pub struct ValidationData{pub sites:Vec<crate::lint::Site>,pub source_text:Vec<String>}

#[path="captured_allow_unused.rs"]
pub mod full_unused;

/// Resource-only adapter over the same existing Operation. No owned patterns,
/// source facts, extra budget or cache survive this borrowed phase control.
pub(crate) struct PatternOperation<'a>{pub budget:&'a crate::captured_generator_budget::Budget,pub poll:&'a dyn Fn()->std::io::Result<()>,pub patterns:Option<&'a dyn crate::native_pattern::Provider>}
impl crate::key_policy_control::Control for PatternOperation<'_>{
 type Error=Failure;const CHECKED:bool=true;
 fn native_patterns(&self)->Option<&dyn crate::native_pattern::Provider>{self.patterns}
 fn native_pattern_failed(&mut self,actual:std::io::Error)->Failure{Failure::Operational(actual)}
 fn checkpoint(&mut self)->Result<(),Failure>{crate::key_policy_control::Control::checkpoint(&mut Operation{budget:self.budget,poll:self.poll})}
 fn reserve(&mut self,n:usize)->Result<(),Failure>{crate::key_policy_control::Control::reserve(&mut Operation{budget:self.budget,poll:self.poll},n)}
 fn overflow(&mut self)->Failure{crate::key_policy_control::Control::overflow(&mut Operation{budget:self.budget,poll:self.poll})}
 fn allocation_failed(&mut self)->Failure{crate::key_policy_control::Control::allocation_failed(&mut Operation{budget:self.budget,poll:self.poll})}
}

impl<'a> Operation<'a>{
 /// Exact same budget/checkpoint control with a borrowed actual program lender.
 /// The opaque control carries no source/registry/execution authority.
 pub fn with_patterns<'p>(self,patterns:&'p dyn crate::native_pattern::Provider)->impl Control<Error=Failure>+'p where 'a:'p{PatternOperation{budget:self.budget,poll:self.poll,patterns:Some(patterns)}}
}
pub fn validate_original_budgeted_with_patterns(known:&ConfigurationNames<'_>,views:RawPolicyViews<'_>,fallback:&crate::captured_generator_budget::Budget,poll:&dyn Fn()->std::io::Result<()>,patterns:&dyn crate::native_pattern::Provider,emit:impl FnMut(&'static str,usize,&str,&str)->Result<(),Failure>)->Result<(),Failure>{
 let local=views.allocation_budget(fallback);let mut control=PatternOperation{budget:local,poll,patterns:Some(patterns)};validate_original_borrowed(known,&views,&mut control,emit)
}
