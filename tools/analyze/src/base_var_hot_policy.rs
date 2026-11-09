//! Shared original base-vars hot-home classifier and raw home-marker policy.
//! No semantic model, raw variable parser, filesystem access or cache.
use std::collections::HashSet;
use crate::pat;
use crate::key_policy_control::{self as kc,Control};
fn listed<C:Control>(values:&[String],value:&str,control:&mut C)->Result<bool,C::Error>{for entry in values{control.checkpoint()?;if entry==value{return Ok(true)}}Ok(false)}
pub const BASE_TYPES: &[&str] = &[
    "/atom",
    "/atom/movable",
    "/obj",
    "/obj/item",
    "/obj/machinery",
    "/mob",
    "/mob/living",
    "/mob/living/carbon",
    "/mob/living/carbon/human",
];
/// Shortest justification a `base_var_home_hot` entry may carry.
pub const HOT_MIN_JUSTIFICATION: usize = 40;
pub(crate) const HOT_TABLE: &str = "base_var_home_hot";
pub(crate) const SCOPES_FILE: &str = "tools/ci/lint_scopes.toml";
pub(crate) fn homes_in(text:&str,macros:&[String],relations:&[String])->Vec<(String,String)>{homes_in_using(text,macros,relations,&mut kc::Compatibility).unwrap_or_else(|never|match never{})}
pub(crate) fn homes_in_using<C:Control>(text:&str,macros:&[String],relations:&[String],control:&mut C)->Result<Vec<(String,String)>,C::Error>{
    control.checkpoint()?;
    let mut out = Vec::new();
    for m in pat!(r"(?m)^[ 	]*([A-Z_]+)\(\s*(/[\w/]+)\s*,\s*(\w+)").captures_iter(text) {
        control.checkpoint()?;if listed(macros,m.s(1),control)? {
            kc::row(control,&mut out)?;out.push((kc::own(control,m.s(2))?,kc::own(control,m.s(3))?));
        }
    }
    if relations.is_empty() {
        return Ok(out);
    }
    let block = pat!(r"^CAPABILITIES(?:_PART)?\(\s*(/[\w/]+)\s*[,)]");
    let entry = pat!(r"\b([a-z_]+)\(\s*nameof\(\s*(?:(/[\w/]+)::|(?:src|[A-Za-z_]\w*)\.)?(\w+)\s*\)");
    let link_end = pat!(r"(/[\w/]+)::(\w+)");
    let mut owner: Option<String> = None;
    for line in text.lines() {
        control.checkpoint()?;
        if !line.starts_with('\t') && !line.starts_with(' ') && !line.trim().is_empty() {
            owner=match block.captures(line){Some(c)=>Some(kc::own(control,c.s(1))?),None=>None};
        }
        for c in entry.captures_iter(line) {
            control.checkpoint()?;if !listed(relations,c.s(1),control)? {
                continue;
            }
            if let Some(explicit) = c.get(2) {
                kc::row(control,&mut out)?;out.push((kc::own(control,explicit)?,kc::own(control,c.s(3))?));
            } else if let Some(o) = &owner {
                kc::row(control,&mut out)?;out.push((kc::own(control,o)?,kc::own(control,c.s(3))?));
            }
        }
        if listed(relations,"links",control)? && line.contains("links(") {
            if let Some(i) = line.find("links(") {
                for c in link_end.captures_iter(&line[i..]) {
                    control.checkpoint()?;kc::row(control,&mut out)?;out.push((kc::own(control,c.s(1))?,kc::own(control,c.s(2))?));
                }
            }
        }
    }
    Ok(out)
}

pub(crate) fn hot_key(key: &str) -> Option<(&str, &str)> {
    let (owner, name) = key.rsplit_once('/')?;
    if owner.is_empty() || name.is_empty() || !owner.starts_with('/') {
        return None;
    }
    Some((owner, name))
}

/// What is wrong with the hot table: `(key, message)`. `declared` is the `(type, var)` pairs that exist as counted base vars, or
/// None when there is no model to check existence against (the text fallback).
pub(crate) fn hot_problems(hot:&std::collections::BTreeMap<String,String>,declared:Option<&HashSet<(String,String)>>,homed:&HashSet<(String,String)>,ceiling:Option<usize>)->Vec<(String,String)>{hot_problems_using(hot.iter(),declared,homed,ceiling,&mut kc::Compatibility).unwrap_or_else(|never|match never{})}
pub(crate) fn hot_problems_using<'a,C:Control>(hot:impl ExactSizeIterator<Item=(&'a String,&'a String)>,declared:Option<&HashSet<(String,String)>>,homed:&HashSet<(String,String)>,ceiling:Option<usize>,control:&mut C)->Result<Vec<(String,String)>,C::Error>{
 control.checkpoint()?;let mut out=Vec::new();if let Some(c)=ceiling{if hot.len()>c{let msg=kc::format(control,format_args!("the hot list has {} entries, over hot_ceiling {} (the ceiling only falls; a new entry is a reviewed design change)",hot.len(),c))?;kc::row(control,&mut out)?;out.push((kc::own(control,"base_var_home_hot")?,msg));}}
 for(key,why)in hot{control.checkpoint()?;let Some((owner,name))=hot_key(key)else{let msg=kc::format(control,format_args!("`{}` is not a `<type>/<var>` key",key))?;kc::row(control,&mut out)?;out.push((kc::own(control,key)?,msg));continue};kc::reserve(control,||owner.len().checked_add(name.len())?.checked_mul(8)?.checked_add(256))?;
 if homed.contains(&(owner.to_owned(),name.to_owned())){let msg=kc::format(control,format_args!("`{}` is already homed by a TRACKED/STAT/SETTER declaration or a relation: drop the entry",key))?;kc::row(control,&mut out)?;out.push((kc::own(control,key)?,msg));}
 if !BASE_TYPES.contains(&owner){let msg=kc::format(control,format_args!("`{}`: {} is not a base type",key,owner))?;kc::row(control,&mut out)?;out.push((kc::own(control,key)?,msg));}else if let Some(declared)=declared{if !declared.contains(&(owner.to_owned(),name.to_owned())){let msg=kc::format(control,format_args!("`{}` is stale: {} declares no counted var `{}`",key,owner,name))?;kc::row(control,&mut out)?;out.push((kc::own(control,key)?,msg));}}
 let why=why.trim();let mut count=0usize;for _ in why.chars(){control.checkpoint()?;count=count.checked_add(1).ok_or_else(||control.overflow())?;}if count<HOT_MIN_JUSTIFICATION{let msg=kc::format(control,format_args!("`{}` needs a justification of at least {} characters (has {})",key,HOT_MIN_JUSTIFICATION,count))?;kc::row(control,&mut out)?;out.push((kc::own(control,key)?,msg));}else if !why.contains(".dm"){let msg=kc::format(control,format_args!("`{}`: the justification must name the hot reader (a .dm file and the proc that reads it)",key))?;kc::row(control,&mut out)?;out.push((kc::own(control,key)?,msg));}
 }Ok(out)
}
