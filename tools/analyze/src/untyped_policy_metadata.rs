use crate::{
    lint::{Meta, Policy, RuleMeta, ScanKind},
    tree::CODE_DM,
};
const HINT: &str = "give the var its type and declare it a relation (ref_one / owns_one, weak = TRUE for a null-check-only reader), or declare it a value: \
`SCHEMA(T, var, schema_path(/base) | schema_msg() | schema_text() | num() | schema_any())` on its own line (doc/rewrite/proposals/typed_values.md)";
const HINT_SCHEMA: &str = "the var's SCHEMA says it holds a path under a base (schema_path) or a /datum/msg path (schema_msg): assign a path that fits, or fix the declaration. \
doc/rewrite/proposals/typed_values.md section 5";

pub(crate) static META: Meta = Meta {
    name: crate::allow_registry_fields::untyped_refs::SCOPE_META_0.name,
    group: crate::allow_registry_fields::untyped_refs::SCOPE_META_0.group,
    label: "untyped",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Sites {
        baseline: "tools/ci/untyped_baseline.txt",
        header: &[
            "Untyped vars assigned an atom or datum, or an unknown call result (doc/rewrite/proposals/relations.md D8). rule<TAB>file<TAB>text.",
            "Shrink-only: after a sweep run `analyze baseline --update --lint untyped`; it drops fixed sites and never adds one.",
        ],
        banned: &["typed", "call", "schema"],
    },
    rules: &[RuleMeta { name: "typed", hint: HINT }, RuleMeta { name: "call", hint: HINT }, RuleMeta { name: "schema", hint: HINT_SCHEMA }],
    allow: &[],
    lists: crate::allow_registry_fields::untyped_refs::SCOPE_META_0.lists,
};

pub fn metadata() -> &'static Meta {
    &META
}
