//! Original rel_write_undeclared metadata, shared without a semantic model.
use crate::{
    lint::{Meta, Policy, RuleMeta, ScanKind},
    tree::CODE_DM,
};
const HINT: &str = "declare the var in the holder type's CAPABILITIES block: ref_one(nameof(v)) (a reference), owns_one/owns_many (an owned value), links(A::a, B::b) \
(a pair); a write to an undeclared var is a test failure. doc/rewrite/proposals/relations.md D1";

pub(crate) static META: Meta = Meta {
    name: "rel_write_undeclared",
    group: "",
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
    lists: &[],
};

pub fn metadata() -> &'static Meta {
    &META
}
