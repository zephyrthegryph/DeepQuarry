//! Original base/list policy over a borrowed single-variable projection.
//! No type model or filesystem reads. Raw annotation questions are only line
//! identities emitted by the existing source-policy callback scanner.
use crate::{base_var_hot_policy::homes_in, pat, tree::SourceFile};
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use crate::key_policy_control::{self as kc,Control};
pub const SINGLETON_ROOTS: &[&str] = &["/datum/world_service", "/datum/controller"];
pub fn is_singleton(type_path: &str, globals: &HashSet<String>) -> bool {
    globals.contains(type_path)
        || SINGLETON_ROOTS.iter().any(|r| {
            type_path == *r
                || (type_path.starts_with(r) && type_path.as_bytes().get(r.len()) == Some(&b'/'))
        })
}
pub struct VarView<'a> {
    pub rel: &'a str,
    pub line: u32,
    pub owner: &'a str,
    pub name: &'a str,
    pub vtype: &'a str,
    pub base: bool,
    pub list_init: bool,
}
pub struct Classification {
    pub base: bool,
    pub list: bool,
}
#[allow(clippy::too_many_arguments)]
pub(crate) fn classify(v:VarView<'_>,file:&SourceFile,singletons:&HashSet<String>,exempt_prefixes:&[String],exempt_files:&[String],homes:&HashSet<(String,String)>,hot:&BTreeMap<String,String>,home_types:&[String])->Option<Classification>{classify_using(v,singletons,exempt_prefixes,exempt_files,homes,|name|hot.contains_key(name),home_types,&mut kc::Compatibility,&mut|name,line,_|Ok(crate::dm::sys::kept_recorded(file,line,name))).unwrap_or_else(|never|match never{})}
#[allow(clippy::too_many_arguments)]
pub(crate) fn classify_using<C:Control>(v:VarView<'_>,singletons:&HashSet<String>,exempt_prefixes:&[String],exempt_files:&[String],homes:&HashSet<(String,String)>,hot_contains:impl Fn(&str)->bool,home_types:&[String],control:&mut C,kept:&mut impl FnMut(&'static str,usize,&mut C)->Result<bool,C::Error>)->Result<Option<Classification>,C::Error>{
 control.checkpoint()?;if kept("base_vars",v.line as usize,control)?{return Ok(None)}kc::reserve(control,||v.owner.len().checked_add(v.name.len())?.checked_add(v.vtype.len())?.checked_mul(8)?.checked_add(512))?;
 let mut housed=homes.contains(&(v.owner.to_owned(),v.name.to_owned()))||hot_contains(&format!("{}/{}",v.owner,v.name));if !housed{for home in home_types{control.checkpoint()?;kc::reserve(control,||home.len().checked_add(128))?;if v.vtype==home.as_str()||v.vtype.starts_with(&format!("{}/",home)){housed=true;break}}}let base=v.base&&!housed;let mut list=false;
 if v.list_init{let mut exempt=false;for prefix in exempt_prefixes{control.checkpoint()?;if v.rel.starts_with(prefix.as_str()){exempt=true;break}}if !exempt{for file in exempt_files{control.checkpoint()?;if file.as_str()==v.rel{exempt=true;break}}}let empty=HashSet::new();if !exempt&&!is_singleton(v.owner,&empty)&&!singletons.contains(v.owner)&&!kept("instance_list",v.line as usize,control)?{list=true}}
 Ok(Some(Classification{base,list}))
}
/// Exactly the questions facts_of asks, including raw noncompiled declarations.
/// The compact ledger retains owner-order and line only, never a variable tree,
/// declared type model, initializer AST or duplicate source text.
pub(crate) fn raw_allow_lines(file:&SourceFile)->Vec<usize>{raw_allow_lines_using(file,&mut kc::Compatibility).unwrap_or_else(|never|match never{})}
pub(crate) fn raw_allow_lines_using<C:Control>(file:&SourceFile,control:&mut C)->Result<Vec<usize>,C::Error>{
 control.checkpoint()?;if file.hidden{return Ok(Vec::new())}let mut owners:HashMap<String,(usize,usize)>=HashMap::new();let mut rows=Vec::new();crate::raw_declaration_policy::visit_file_using(&file.rel,file.code(),control,|owner,(_,mods,_,_),_,line,control|{control.checkpoint()?;let first=match owners.get(owner){Some((_,first))=>*first,None=>{kc::reserve(control,||Some(2048))?;let next=owners.len();owners.insert(kc::own(control,owner)?,(next,line));line}};if mods.iter().any(|word|["const","static","global"].contains(&word.as_str())){return Ok(())}kc::row(control,&mut rows)?;rows.push((first,rows.len(),line));Ok(())},|_,_,_|Ok(()))?;
 let mut error=None;rows.sort_by(|a,b|{if error.is_none(){if let Err(actual)=control.checkpoint(){error=Some(actual)}}(a.0,a.1).cmp(&(b.0,b.1))});if let Some(actual)=error{return Err(actual)}kc::reserve(control,||rows.len().checked_mul(4*std::mem::size_of::<usize>())?.checked_add(128))?;Ok(rows.into_iter().map(|(_,_,line)|line).collect())
}
#[derive(Default)]
pub(crate) struct RawFacts {
    pub homes: Vec<(String, String)>,
    pub singles: Vec<String>,
}
// file_facts is appended mechanically from the original facts_of prefix by
// prepare.py; its regex policy is not independently reimplemented here.

pub(crate) fn file_facts(f:&SourceFile,macros:&[String],relations:&[String])->RawFacts{file_facts_using(f,macros,relations,&mut kc::Compatibility).unwrap_or_else(|never|match never{})}
pub(crate) fn file_facts_using<C:Control>(f:&SourceFile,macros:&[String],relations:&[String],control:&mut C)->Result<RawFacts,C::Error>{
 control.checkpoint()?;
let mut out=RawFacts::default();
    if f.rel.starts_with("code/") {
        let text = f.raw().text.as_str();
        out.homes = crate::base_var_hot_policy::homes_in_using(f.code().text.as_str(),macros,relations,control)?;
        if text.contains("GLOBAL_DATUM_INIT") {
            let mut set: BTreeSet<String> = BTreeSet::new();
            for m in pat!(r"GLOBAL_DATUM_INIT\(\s*\w+\s*,\s*(/[\w/]+)\s*,\s*new\b").captures_iter(text) {
                control.checkpoint()?;if !set.contains(m.s(1)){kc::reserve(control,||Some(2048))?;set.insert(kc::own(control,m.s(1))?);}
            }
            kc::reserve(control,||set.len().checked_mul(4*std::mem::size_of::<String>())?.checked_add(128))?;out.singles = set.into_iter().collect();
        }
        if text.contains("SYSTEM_DEF(") {
            // SYSTEM_DEF(x) declares the one instance of /datum/system/x.
            let mut set:BTreeSet<String>=BTreeSet::new();for word in &out.singles{control.checkpoint()?;kc::reserve(control,||Some(2048))?;set.insert(kc::own(control,word)?);}
            for m in pat!(r"(?m)^SYSTEM_DEF\((\w+)\)").captures_iter(text) {
                control.checkpoint()?;kc::reserve(control,||Some(2048))?;set.insert(kc::format(control,format_args!("/datum/system/{}",m.s(1)))?);
            }
            kc::reserve(control,||set.len().checked_mul(4*std::mem::size_of::<String>())?.checked_add(128))?;out.singles = set.into_iter().collect();
        }
    }
Ok(out)
}
