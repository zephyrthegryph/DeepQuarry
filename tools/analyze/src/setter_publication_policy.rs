//! Exact original setter-publication messages over the shared scalar judge.
use crate::key_policy_control::{self as kc,Control};
#[path="../../dmb/shared/setter_publication.rs"]mod core;
pub use core::{PUBLISHERS,publishes_named,owned_base_call,Finding,judge};
impl Finding{pub fn message<C:Control>(self,definer:&str,name:&str,var:&str,c:&mut C)->Result<String,C::Error>{match self{Self::NoPublish=>kc::format(c,format_args!("{definer}/{name}() writes {var} and never publishes it")),Self::NotSetter=>kc::format(c,format_args!("{definer}/{name}() does not write {var}"))}}}

/// The original tuple keeps `must` as an ordering/identity dimension: an explicit
/// registration and an inference clash may judge the same procedure twice.
pub type Judged=std::collections::BTreeSet<(String,String,String,bool)>;
fn insert<C:Control>(rows:&mut Judged,owner:&str,name:&str,var:&str,must:bool,c:&mut C)->Result<(),C::Error>{
 c.checkpoint()?;
 kc::reserve(c,||owner.len().checked_add(name.len())?.checked_add(var.len())?.checked_add(std::mem::size_of::<(String,String,String,bool)>())?.checked_add(128))?;
 rows.insert((owner.to_owned(),name.to_owned(),var.to_owned(),must));Ok(())
}
/// Feed the SAME AutoSet.blocked rows already computed for generation.
/// This function does not infer candidates, resolve types, or load configuration.
pub fn inferred_judgment<C:Control>(rows:&mut Judged,var:&str,why:&str,c:&mut C)->Result<(),C::Error>{
 c.checkpoint()?;let Some((owner,rest))=why.split_once(" already defines ")else{return Ok(())};
 let name=rest.trim_end_matches("()");
 if name.strip_prefix("set_")==Some(var){insert(rows,owner,name,var,true,c)?}Ok(())
}
/// The caller must establish an OWN proc name group, not an inherited lookup.
pub fn explicit_judgment<C:Control>(rows:&mut Judged,owner:&str,var:&str,c:&mut C)->Result<(),C::Error>{
 let name=kc::format(c,format_args!("set_{var}"))?;insert(rows,owner,&name,var,false,c)
}

use crate::lint::{Meta,Policy,RuleMeta,ScanKind};use crate::tree::CODE_DM;
pub static META: Meta = Meta {
    name: crate::allow_registry_fields::setter_publishes::SCOPE_META_0.name,
    group: crate::allow_registry_fields::setter_publishes::SCOPE_META_0.group,
    label: "setter_publishes",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "no_publish", hint: "call tracked_changed(src, nameof(v)) on every path that changes the var (or chain to ..()): a write nothing publishes leaves the var silently untracked" },
        RuleMeta { name: "not_a_setter", hint: "this proc shares the name of a setter but does not write the var, so the var (read by reactive code) cannot get a generated setter: rename the proc" },
    ],
    allow: crate::allow_registry_fields::setter_publishes::ALLOW_0,
    lists: crate::allow_registry_fields::setter_publishes::SCOPE_META_0.lists,
};
pub fn metadata()->&'static Meta{&META}
