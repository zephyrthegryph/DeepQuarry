//! Complete ALLOW metadata shares the actual all-registration fields and factory discovery.
//! It carries no source/configuration/usage completion or semantic model.
use std::collections::BTreeSet;
use crate::key_policy_control::{self as kc,Control};
pub struct CompleteRegistryAllowNames{names:BTreeSet<String>}
impl CompleteRegistryAllowNames{
 /// The actual captured configuration supplies its complete explicit [allow] known list.
 pub(crate) fn with_config<C:Control,R>(&self,explicit:&[String],control:&mut C,consume:impl FnOnce(&BTreeSet<String>,&mut C)->Result<R,C::Error>)->Result<R,C::Error>{
  let mut names=BTreeSet::new();for name in self.names.iter().chain(explicit){if !names.contains(name){kc::reserve(control,||name.len().checked_mul(4)?.checked_add(2048))?;names.insert(name.clone());}}control.checkpoint()?;consume(&names,control)
 }
}
/// Complete metadata from the SAME build-discovered full registration modules.
/// No partial Registry argument, caller completion bool or semantic model is accepted.
pub fn complete_registry_allow_names<C:Control>(control:&mut C)->Result<CompleteRegistryAllowNames,C::Error>{
 let mut names=BTreeSet::new();crate::allow_registry_fields::collect_all(&mut names,control)?;control.checkpoint()?;Ok(CompleteRegistryAllowNames{names})
}
#[cfg(test)]mod tests{
 use super::*;
 #[test]fn native_full_metadata_contains_actual_non_native_registry_names(){let names=complete_registry_allow_names(&mut kc::Compatibility).unwrap();for name in ["keys","base_vars","instance_list","sys_update_icon","sys_world_time_expiry"]{assert!(names.names.contains(name),"complete metadata must include real non-RAW42 namespace {name}");}}
 #[cfg(feature="legacy-sem")]
 #[test]fn native_metadata_equals_actual_finished_full_registry_and_config_union(){let actual=complete_registry_allow_names(&mut kc::Compatibility).unwrap();let registry=crate::run::registry();let expected:BTreeSet<String>=registry.lints.iter().flat_map(|lint|lint.meta().allow.iter().map(|name|(*name).to_owned())).collect();assert_eq!(actual.names,expected,"source-neutral metadata must equal the real full finished registration factory");let fields:Vec<_>=registry.lints.iter().map(|lint|{let meta=lint.meta();serde_json::json!({"name":meta.name,"allow":meta.allow})}).collect();let record=serde_json::json!({"engine_hash":env!("DQ_ENGINE_HASH"),"names":&actual.names,"registered_fields":fields});println!("NATIVE_ALLOW_REGISTRY={record}");let extra=vec!["fixture_explicit".to_owned(),"keys".to_owned()];actual.with_config(&extra,&mut kc::Compatibility,|known,_|{let mut expected=expected.clone();expected.extend(extra.iter().cloned());assert_eq!(*known,expected);Ok(())}).unwrap();}
}
