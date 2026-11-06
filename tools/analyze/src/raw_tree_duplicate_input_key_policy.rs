//! Unique input-key lexical policy, with unsealed borrowed facts.
use std::collections::HashMap;
use crate::lint::{Meta,Policy,RuleMeta,ScanKind};
use crate::pat::Pat;
use crate::tree::{SourceFile,CODE_DM};
use crate::raw_tree_report::Reporter;
const HINT: &str = "one handler per input key for a type: merge the handlers into one proc that tries each case in priority order and answers INPUT_FALLTHROUGH for the cases it does not take";

pub static META: Meta = Meta {
    name: crate::allow_registry_fields::duplicate_input_key::SCOPE_META_0.name,
    group: crate::allow_registry_fields::duplicate_input_key::SCOPE_META_0.group,
    label: "duplicate_input_key",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "duplicate_input_key", hint: HINT }],
    allow: crate::allow_registry_fields::duplicate_input_key::ALLOW_0,
    lists: crate::allow_registry_fields::duplicate_input_key::SCOPE_META_0.lists,
};

pub struct Patterns{block:Pat,entry:Pat}
impl Patterns{pub fn new()->Self{Self{block:Pat::new(r"^CAPABILITIES(?:_PART)?\(\s*(/[\w/]+)\s*[,)]"),entry:Pat::new(r"^(click_on|double_click_on|drag_onto|drag_over|hover|tooltip)\(")}}}
pub fn declared(f:&SourceFile,p:&Patterns,mut visit:impl FnMut(&str,&str,usize)){declared_using(f,p,visit,&mut crate::key_policy_control::Compatibility).expect("original duplicate_input_key source index")}
pub fn declared_using<C:crate::key_policy_control::Control>(f:&SourceFile,p:&Patterns,mut visit:impl FnMut(&str,&str,usize),c:&mut C)->Result<(),C::Error>{c.checkpoint()?;let block=&p.block;let entry=&p.entry;
        let mut current: Option<&str> = None;
        for (number, line) in f.code().numbered() {c.checkpoint()?;
            if line.trim().is_empty() {
                continue;
            }
            if !line.starts_with(['\t', ' ']) {
                current = block.captures(line.trim_end()).map(|m| m.s(1));
                continue;
            }
            let Some(ty) = &current else { continue };
            if !line.starts_with('\t') || line.starts_with("\t\t") {
                continue;
            }
            if let Some(m) = entry.captures(line.trim_start()) {
                visit(ty,m.s(1),number);
            }
        }
c.checkpoint()?;Ok(())}
pub fn assemble<'a>(rows:impl IntoIterator<Item=(&'a str,&'a str,&'a str,usize)>,out:&mut impl Reporter){
        let mut first: HashMap<(String, String), (String, usize)> = HashMap::new();
        for (ty, key, rel, line) in rows {
 if !out.checkpoint(){return}
            match first.get(&(ty.to_string(), key.to_string())) {
                Some((r0, l0)) => out.site_in_msg("duplicate_input_key", &rel, line, format!("{} declares {}() twice (first at {}:{}): the later one replaces the earlier", ty, key, r0, l0)),
                None => {
                    first.insert((ty.to_string(), key.to_string()), (rel.to_string(), line));
                }
            }
        }
}
