//! Unique original untracked-input grouping, counts and diagnostic policy.
//! The borrowed dependency view contains policy facts, never source completion.
use std::collections::BTreeMap;
use crate::{key_policy_control as kc,reactive_dependency_view::Analysis,sem_reads_policy::Reporter,lint::{Meta,Policy,RuleMeta,ScanKind},tree::CODE_DM};
const H_STAT: &str = "make the var TRACKED (write it through set_<var>()), declare the relation, or publish a READS_AS key where it changes: a stat reading it recomputes on every read";
const H_DRAW: &str = "make the var TRACKED (write it through set_<var>()), declare the relation, or publish a READS_AS key where it changes: the look cannot follow it";
const H_SAMPLED: &str = "a draw or a stat input must not read_once(): track the var (write it through set_<var>()), declare the relation, or publish a READS_AS key";
const H_LEAF: &str = "make the var TRACKED and write it through its setter: a stat whose input never publishes recomputes on every read";

static META: Meta = Meta {
    name: crate::allow_registry_fields::untracked_inputs::SCOPE_META_0.name,
    group: crate::allow_registry_fields::untracked_inputs::SCOPE_META_0.group,
    label: "untracked_inputs",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "stat_input_untracked", hint: H_STAT },
        RuleMeta { name: "draw_untracked", hint: H_DRAW },
        RuleMeta { name: "sampled_in_look", hint: H_SAMPLED },
        RuleMeta { name: "leaf_untracked", hint: H_LEAF },
    ],
    allow: crate::allow_registry_fields::untracked_inputs::ALLOW_0,
    lists: crate::allow_registry_fields::untracked_inputs::SCOPE_META_0.lists,
};


pub fn metadata()->&'static Meta{&META}
fn node<C:kc::Control>(control:&mut C)->Result<(),C::Error>{kc::reserve(control,||Some(2048))}
fn more<C:kc::Control>(count:usize,control:&mut C)->Result<String,C::Error>{if count>1{kc::format(control,format_args!(" (and {} more)",count-1))}else{Ok(String::new())}}
pub(crate) fn scan<C:kc::Control>(analysis:Analysis<'_>,out:&mut impl Reporter<C>,control:&mut C)->Result<(),C::Error>{
 control.checkpoint()?;let mut sites:BTreeMap<(&'static str,&str,u32,&str,&str),Vec<&String>>=BTreeMap::new();
 for(id,reads)in analysis.consumers(){control.checkpoint()?;let rule=if analysis.is_draw(id){"draw_untracked"}else{"stat_input_untracked"};for read in reads{control.checkpoint()?;let key=(rule,read.rel.as_str(),read.line,read.what.as_str(),read.owner.as_str());if !sites.contains_key(&key){node(control)?;sites.insert(key,Vec::new());}let ids=sites.get_mut(&key).ok_or_else(||control.overflow())?;crate::reactive_dependency_fold::row(control,ids)?;ids.push(id);}}
 for((rule,rel,line,what,owner),ids)in sites{control.checkpoint()?;let first=ids.first().ok_or_else(||control.overflow())?;let more=more(ids.len(),control)?;let reader=out.reader(rel,line,control)?;let read=if owner.is_empty(){kc::own(control,what)?}else{kc::format(control,format_args!("{owner}::{what}"))?};let ident=kc::format(control,format_args!("{reader} reads {read}"))?;let message=kc::format(control,format_args!("{first}{more} reads `{what}`, which nothing publishes"))?;let key=kc::own(control,&message)?;out.put(rule,rel,line,key,ident,message,control)?;}
 let mut sampled:BTreeMap<(&str,u32),Vec<&String>>=BTreeMap::new();for(id,at)in analysis.sampled(){control.checkpoint()?;for(relative,line)in at.iter(){control.checkpoint()?;let key=(relative.as_str(),*line);if !sampled.contains_key(&key){node(control)?;sampled.insert(key,Vec::new());}let ids=sampled.get_mut(&key).ok_or_else(||control.overflow())?;crate::reactive_dependency_fold::row(control,ids)?;ids.push(id);}}
 for((rel,line),ids)in sampled{control.checkpoint()?;let first=ids.first().ok_or_else(||control.overflow())?;let more=more(ids.len(),control)?;let reader=out.reader(rel,line,control)?;let ident=kc::format(control,format_args!("{reader} samples"))?;let message=kc::format(control,format_args!("{first}{more} reaches a read_once(), which a look or a stat input must not sample"))?;let key=kc::own(control,&message)?;out.put("sampled_in_look",rel,line,key,ident,message,control)?;}
 for leaf in analysis.leaves(){control.checkpoint()?;let ident=kc::format(control,format_args!("{}::{}",leaf.owner,leaf.var))?;let message=kc::format(control,format_args!("{} names `{}` as a stat input, and nothing publishes it",leaf.owner,leaf.var))?;let key=kc::own(control,&message)?;out.put("leaf_untracked",&leaf.rel,leaf.line,key,ident,message,control)?;}control.checkpoint()?;Ok(())
}
