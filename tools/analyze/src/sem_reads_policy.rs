//! Unique semantic-read diagnostic wording and ordered row projection.
//! Facts only: no source, handler or execution completion is granted.
use crate::{lint::{Meta,Policy,RuleMeta,ScanKind},tree::CODE_DM};
const H_UNKNOWN: &str = "make it tracked, add a relation, add READS_FROM(arg) to the global proc it came through, or add READS_AS(proc, key)";
const H_GLOBAL: &str = "move the state into a system's tracked vars (SYSTEM_DEF) and read it through its accessor, or write it only while the world boots: reactive code cannot read a global that changes and nothing publishes";
const H_DYNAMIC: &str = "read a declared var; nothing uses vars[] or call() in a handler";
const H_HOP: &str = "declare the link var a relation (REL/OWN or rel_one in relations()); a hop only follows a declared relation";
const H_FIELD: &str = "read a var the type declares (the build checks each read against the receiver's type)";
const H_CYCLE: &str = "break the cycle: a derived value cannot read itself through its own dependencies";
const H_COVER: &str = "publish the key where the state changes (PUBLISH_CHANGE(E, KEY)), or make the vars tracked";

static META: Meta = Meta {
    name: crate::allow_registry_fields::sem_reads::SCOPE_META_0.name,
    group: crate::allow_registry_fields::sem_reads::SCOPE_META_0.group,
    label: "reads",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "unknown_read", hint: H_UNKNOWN },
        RuleMeta { name: "untracked_global", hint: H_GLOBAL },
        RuleMeta { name: "dynamic_read", hint: H_DYNAMIC },
        RuleMeta { name: "hop_not_relation", hint: H_HOP },
        RuleMeta { name: "unknown_field", hint: H_FIELD },
        RuleMeta { name: "condition_cycle", hint: H_CYCLE },
        RuleMeta { name: "reads_as_uncovered", hint: H_COVER },
    ],
    allow: crate::allow_registry_fields::sem_reads::ALLOW_0,
    lists: crate::allow_registry_fields::sem_reads::SCOPE_META_0.lists,
};


pub fn metadata()->&'static Meta{&META}
use crate::key_policy_control as kc;
pub(crate) trait Reporter<C:kc::Control>{fn reader(&mut self,rel:&str,line:u32,control:&mut C)->Result<String,C::Error>;fn put(&mut self,rule:&'static str,rel:&str,line:u32,key:String,ident:String,message:String,control:&mut C)->Result<(),C::Error>;}
pub(crate) struct Handler<'a>{pub owner:&'a str,pub procedure:&'a str,pub form:&'a str}
fn who<C:kc::Control>(h:Handler<'_>,control:&mut C)->Result<String,C::Error>{kc::format(control,format_args!("{}::{} ({}())",h.owner,h.procedure,h.form))}
pub(crate) fn unknown<C:kc::Control>(out:&mut impl Reporter<C>,h:Handler<'_>,key:&str,var:&str,owner:&str,rel:&str,line:u32,control:&mut C)->Result<(),C::Error>{control.checkpoint()?;let who=who(h,control)?;let reader=out.reader(rel,line,control)?;let dedup=kc::format(control,format_args!("{key}|{var}|{owner}"))?;let ident=kc::format(control,format_args!("{reader} reads {owner}::{key}"))?;let message=kc::format(control,format_args!("{who} reads `{key}`: {var} on {owner} is not tracked, a relation, a stat, derived or constant"))?;out.put("unknown_read",rel,line,dedup,ident,message,control)}
pub(crate) fn diagnostic<C:kc::Control>(out:&mut impl Reporter<C>,h:Handler<'_>,rule:&'static str,rel:&str,line:u32,message:&str,control:&mut C)->Result<(),C::Error>{if !matches!(rule,"untracked_global"|"dynamic_read"|"hop_not_relation"|"unknown_field"){return Ok(())}control.checkpoint()?;let who=who(h,control)?;let reader=out.reader(rel,line,control)?;let key=kc::own(control,message)?;let ident=kc::format(control,format_args!("{reader} reads {message}"))?;let message=kc::format(control,format_args!("{who}: {message}"))?;out.put(rule,rel,line,key,ident,message,control)}
pub(crate) fn cycle<C:kc::Control>(out:&mut impl Reporter<C>,cycle:&[String],rel:&str,line:u32,control:&mut C)->Result<(),C::Error>{control.checkpoint()?;let Some(first)=cycle.first()else{return Err(control.overflow())};let bytes=cycle.iter().try_fold(0usize,|sum,name|sum.checked_add(name.len()).and_then(|n|n.checked_add(4)));kc::reserve(control,||bytes.and_then(|n|n.checked_mul(12)).and_then(|n|n.checked_add(512)))?;let key=cycle.join(">");let ident=format!("cycle {}",cycle.join(">"));let message=format!("cycle in the condition and stat graph: {} -> {}",cycle.join(" -> "),first);out.put("condition_cycle",rel,line,key,ident,message,control)}
pub(crate) fn accessor_gap<C:kc::Control>(out:&mut impl Reporter<C>,owner:&str,procedure:&str,key:&str,vars:&[String],rel:&str,line:u32,control:&mut C)->Result<(),C::Error>{control.checkpoint()?;let dedup=kc::format(control,format_args!("{procedure}|{key}"))?;let ident=kc::format(control,format_args!("{owner}::{procedure} publishes {key}"))?;kc::reserve(control,||vars.iter().try_fold(0usize,|n,var|n.checked_add(var.len()).and_then(|n|n.checked_add(2))).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(128)))?;let joined=vars.join(", ");let message=kc::format(control,format_args!("READS_AS({procedure}, {key}) on {owner} reads {joined} which are not tracked and nothing publishes {key}"))?;out.put("reads_as_uncovered",rel,line,dedup,ident,message,control)}
