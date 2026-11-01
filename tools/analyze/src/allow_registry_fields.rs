//! Unique complete ALLOW metadata. The build generates this module traversal
//! from the SAME actual full lint discovery used by legacy registration.
//! Static fields below are also referenced by the original real Meta values.
use std::collections::BTreeSet;
use crate::key_policy_control::{self as kc,Control};
pub(crate) fn plain<C:Control>(fields:&[&[&str]],names:&mut BTreeSet<String>,control:&mut C)->Result<(),C::Error>{for field in fields{for name in *field{if !names.contains(*name){kc::reserve(control,||name.len().checked_mul(4)?.checked_add(2048))?;names.insert((*name).to_owned());}}}Ok(())}
pub(crate) fn sys_name<C:Control>(name:&str,control:&mut C)->Result<String,C::Error>{kc::format(control,format_args!("sys_{}",name))}
pub(crate) fn legacy_sys_name(name:&str)->String{match sys_name(name,&mut kc::Compatibility){Ok(value)=>value,Err(never)=>match never{}}}
pub(crate) fn sys<C:Control>(rules:&[crate::lint::RuleMeta],extra:&[&str],names:&mut BTreeSet<String>,control:&mut C)->Result<(),C::Error>{for name in rules.iter().map(|rule|rule.name).chain(extra.iter().copied()){let name=sys_name(name,control)?;if !names.contains(&name){kc::reserve(control,||Some(2048))?;names.insert(name);}}Ok(())}
include!(concat!(env!("OUT_DIR"),"/allow_registry_fields_gen.rs"));
