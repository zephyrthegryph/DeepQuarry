//! Unique state-schema judgment over borrowed lexical schema facts.
//! All inputs and output are DATA. Neither this interface nor a successful
//! callback certifies source coverage, current compiler state or execution.
use std::collections::HashSet;
use crate::lint::{Meta,Policy,RuleMeta,ScanKind};use crate::tree::CODE_DM;
pub static META: Meta = Meta {
    name: crate::allow_registry_fields::state_schema::SCOPE_META_0.name,
    group: crate::allow_registry_fields::state_schema::SCOPE_META_0.group,
    label: "state_schema",
    legacy: "tools/ci/state_schema_lint.py",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta {
        name: "schema",
        hint: "make it tmp, give it a codec in state_codecs(), or give it an ownership kind (own_set/rel_set/proto_set)",
    }],
    allow: crate::allow_registry_fields::state_schema::ALLOW_0,
    lists: crate::allow_registry_fields::state_schema::SCOPE_META_0.lists,
};

#[derive(Clone,Copy)]pub struct Variable<'a>{pub name:&'a str,pub vtype:&'a str,pub path:&'a str,pub line:usize,pub is_list:bool,pub saved:bool,pub holds_ref:bool,pub registry:bool}
/// Borrowed lexical DATA; no implementation is a source-completion issuer.
pub trait SchemaView<C:crate::key_policy_control::Control>{
 fn visit_safe_types(&self,c:&mut C,emit:&mut dyn FnMut(&str,&mut C)->Result<(),C::Error>)->Result<usize,C::Error>;
 fn visit_chain(&self,subject:&str,c:&mut C,emit:&mut dyn FnMut(&str,&mut C)->Result<(),C::Error>)->Result<(),C::Error>;
 fn variables(&self,owner:&str,c:&mut C,visit:&mut dyn FnMut(Variable<'_>,&mut C)->Result<(),C::Error>)->Result<(),C::Error>;
 fn has_codec(&self,name:&str,subject:&str,c:&mut C)->Result<bool,C::Error>;
 fn has_kind(&self,owner:&str,name:&str,c:&mut C)->Result<bool,C::Error>;
}
pub fn judge<S:SchemaView<crate::key_policy_control::Compatibility>>(schema:&S,mut site:impl FnMut(&str,usize,String),mut note:impl FnMut(String)){match judge_using(schema,&mut crate::key_policy_control::Compatibility,&mut|path,line,message,_|{site(path,line,message);Ok(())},&mut|message,_|{note(message);Ok(())}){Ok(())=>(),Err(never)=>match never{}}}
/// Unique original suppression, first-safe-owner, message and note policy.
/// Native callbacks receive only data and must fund retained output separately.
pub fn judge_using<C:crate::key_policy_control::Control,S:SchemaView<C>>(schema:&S,c:&mut C,site:&mut impl FnMut(&str,usize,String,&mut C)->Result<(),C::Error>,note:&mut impl FnMut(String,&mut C)->Result<(),C::Error>)->Result<(),C::Error>{
 use crate::key_policy_control as kc;use std::collections::HashMap;
 let mut used:HashSet<String>=HashSet::new();let mut checked:HashMap<String,HashSet<String>>=HashMap::new();let mut problems=0usize;let mut entry=String::new();
 let count=schema.visit_safe_types(c,&mut|t,c|{schema.visit_chain(t,c,&mut|a,c|{schema.variables(a,c,&mut|v,c|{c.checkpoint()?;if !v.saved||!v.holds_ref||v.registry{return Ok(())}if schema.has_codec(v.name,t,c)?{return Ok(())}
  let need=if C::CHECKED{a.len().checked_add(1).and_then(|n|n.checked_add(v.name.len())).ok_or_else(||c.overflow())?}else{a.len()+1+v.name.len()};if C::CHECKED&&need>entry.capacity(){let cap=need.max(entry.capacity().checked_mul(2).ok_or_else(||c.overflow())?).max(64);kc::reserve(c,||cap.checked_add(64))?;entry.try_reserve_exact(cap-entry.len()).map_err(|_|c.allocation_failed())?;if entry.capacity()>cap.checked_mul(4).ok_or_else(||c.overflow())?{return Err(c.allocation_failed())}}entry.clear();entry.push_str(a);entry.push('/');entry.push_str(v.name);
  if schema.has_kind(a,v.name,c)?{if !used.contains(&entry){kc::reserve(c,||Some(2048))?;used.insert(kc::own(c,&entry)?);}return Ok(())}
  if checked.get(a).is_some_and(|names|names.contains(v.name)){return Ok(())}if !checked.contains_key(a){kc::reserve(c,||Some(2048))?;checked.insert(kc::own(c,a)?,HashSet::new());}kc::reserve(c,||Some(2048))?;checked.get_mut(a).expect("actual schema checked owner").insert(kc::own(c,v.name)?);problems=problems.checked_add(1).ok_or_else(||c.overflow())?;
  let message=kc::format(c,format_args!("{} holds a reference ({}{}) and is saved on latent-safe {}",entry,if v.is_list{"list of "}else{""},v.vtype,t))?;site(v.path,v.line,message,c)
 })})})?;
 let message=kc::format(c,format_args!("state schema lint: {} latent-safe types, {} vars with an ownership codec, {} problems",count,used.len(),problems))?;note(message,c)?;c.checkpoint()
}
