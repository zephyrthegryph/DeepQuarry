//! Original rel_write_undeclared metadata, shared without a semantic model.
use crate::{
    lint::{Meta, Policy, RuleMeta, ScanKind},
    tree::CODE_DM,
};
const HINT: &str = "declare the var in the holder type's CAPABILITIES block: ref_one(nameof(v)) (a reference), owns_one/owns_many (an owned value), links(A::a, B::b) \
(a pair); a write to an undeclared var is a test failure. doc/rewrite/proposals/relations.md D1";

pub(crate) static META: Meta = Meta {
    name: crate::allow_registry_fields::rel_write_undeclared::SCOPE_META_0.name,
    group: crate::allow_registry_fields::rel_write_undeclared::SCOPE_META_0.group,
    label: "rel_write_undeclared",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta {
        name: "undeclared",
        hint: HINT,
    }],
    allow: &[],
    lists: crate::allow_registry_fields::rel_write_undeclared::SCOPE_META_0.lists,
};

pub fn metadata() -> &'static Meta {
    &META
}

pub const PATH_FORM:&str=r"\b(rel_(?:set|add|remove|clear|take|take_all|move))\(\s*[^,]+,\s*nameof\(\s*(/[\w/]+?)/?::(\w+)\s*\)";
pub fn path_forms_using<C:crate::key_policy_control::Control>(file:&crate::tree::SourceFile,work:&mut C,mut emit:impl FnMut(usize,&str,&str,&str)->Result<(),C::Error>)->Result<(),C::Error>{let pattern=crate::pat!(PATH_FORM);for(i,line)in file.code().lines().enumerate(){work.checkpoint()?;for c in pattern.captures_iter(line){work.checkpoint()?;emit(i+1,c.s(1),c.s(2),c.s(3))?;}}work.checkpoint()}
