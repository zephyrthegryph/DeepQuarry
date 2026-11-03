//! Original weak-relation declaration matcher and metadata. No typed model.
use crate::{
    lint::{Meta, Policy, RuleMeta, ScanKind},
    tree::{SourceFile, CODE_DM},
};
use std::collections::HashMap;
const HINT: &str = "a weak relation var holds a handle, not the target: read it with its generated accessor v() and write it with rel_set / rel_add / rel_remove / rel_clear. \
doc/rewrite/proposals/relations.md D5";

pub(crate) static META: Meta = Meta {
    name: crate::allow_registry_fields::weak_raw_read::SCOPE_META_0.name,
    group: crate::allow_registry_fields::weak_raw_read::SCOPE_META_0.group,
    label: "weak_raw_read",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta {
        name: "raw",
        hint: HINT,
    }],
    allow: &[],
    lists: crate::allow_registry_fields::weak_raw_read::SCOPE_META_0.lists,
};

pub fn metadata() -> &'static Meta {
    &META
}
pub(crate) fn declarations<'a>(
    files: impl IntoIterator<Item = &'a SourceFile>,
) -> HashMap<String, Vec<String>> {
    let mut out=HashMap::new();for file in files{match declarations_file_using(file,&mut out,&mut crate::key_policy_control::Compatibility){Ok(())=>(),Err(never)=>match never{}}}out
}
/// SAME original regexp/header-reset/declaration order over a borrowed source.
pub(crate) fn declarations_file_using<C:crate::key_policy_control::Control>(f:&SourceFile,out:&mut HashMap<String,Vec<String>>,work:&mut C)->Result<(),C::Error>{
 use crate::key_policy_control as kc;
 let header=crate::pat!(r"^\s*CAPABILITIES\(\s*(/[\w/]+)\s*\)");
 let decl=crate::pat!(r"\bref_(?:one|many)\(\s*nameof\(\s*(\w+)\s*\)[^\n]*\bweak\s*=\s*TRUE");
 work.checkpoint()?;if !f.rel.ends_with(".dm"){return Ok(())}let mut owner:Option<String>=None;
 for line in f.code().lines(){work.checkpoint()?;if let Some(c)=header.captures(line){owner=Some(kc::own(work,c.s(1))?);continue}if !line.starts_with(char::is_whitespace)&&!line.trim().is_empty(){owner=None}let Some(o)=owner.as_ref()else{continue};if let Some(c)=decl.captures(line){let name=c.s(1);if !out.contains_key(name){kc::reserve(work,||Some(2048))?;out.insert(kc::own(work,name)?,Vec::new());}let types=out.get_mut(name).unwrap();work.checkpoint()?;if !types.contains(o){kc::row(work,types)?;types.push(kc::own(work,o)?);}}}work.checkpoint()
}

pub fn message(var:&str,holder:&str)->String{format!("`{}` of {} is a weak relation read raw; use {}()",var,holder,var)}
