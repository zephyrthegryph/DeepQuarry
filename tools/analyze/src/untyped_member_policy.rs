//! Original complete lint metadata/message, shared by legacy/native facts.
use crate::{
    lint::{Meta, Policy, RuleMeta, ScanKind},
    tree::CODE_DM,
};
const HINT: &str = "the receiver has no static type and the member name is declared static/global on some type, so DreamMaker may bind the static. Give the receiver \
its type: a typed local (`var/obj/belly/B = x`, assigned after `istype`) or a typed parameter. A proc's RETURN_TYPE does not type its result for DreamMaker. \
doc/rewrite/native_compiler_issues.md, untyped receiver";

pub(crate) static META: Meta = Meta {
    name: crate::allow_registry_fields::untyped_member::SCOPE_META_0.name,
    group: crate::allow_registry_fields::untyped_member::SCOPE_META_0.group,
    label: "untyped_member",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta {
        name: "static_member",
        hint: HINT,
    }],
    allow: &[],
    lists: crate::allow_registry_fields::untyped_member::SCOPE_META_0.lists,
};

pub fn metadata() -> &'static Meta {
    &META
}
pub fn message(name: &str) -> String {
    format!("`.{}` is read through a receiver with no static type, and `{}` is declared static on some type",name,name)
}
