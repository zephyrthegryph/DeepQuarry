//! Exact shared metadata only; no legacy lint module or semantic model.
use crate::{lint::{Meta,Policy,RuleMeta,ScanKind},tree::CODE_DM};
const H_UNDECLARED: &str = "declare it in derived() (`--fix` adds it), or keep with // ALLOW(derived_reads): <reason>";
const H_UNTRACKED: &str = "make it TRACKED / SETTER, a derive() value or a declared relation (OWN / REL)";
const H_HOP: &str = "declare the link var REL / REL_LIST / OWN; a hop only follows a declared relation";
const H_REACTION: &str = "make the var TRACKED / SETTER / an OM field or a relation, or name the key its producer publishes with PUBLISHED_BY(T, var, KEY)";
const H_UI_UNTRACKED: &str = "make the var TRACKED / SETTER (and write it through its setter), a derive() value or a declared relation (REL / OWN): a window host must track what its ui_data() shows, or the window never hears it change";
const H_EXACT: &str = "use push_to_rust() with rust_push(...): an exact type is not woken for on_state_changed";

pub(crate) static META: Meta = Meta {
    name: crate::allow_registry_fields::derived_reads::SCOPE_META_0.name,
    group: crate::allow_registry_fields::derived_reads::SCOPE_META_0.group,
    label: "derived_reads",
    legacy: "tools/ci/derived_reads_lint.py",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Sites {
        baseline: "tools/ci/derived_reads_baseline.txt",
        header: &[
            "Legacy derived-proc reads a type's derived() doesn't declare (tools/ci/derived_reads_lint.py).",
            "rule<TAB>file<TAB>normalized line. Shrink-only: after a sweep, `python tools/ci/derived_reads_lint.py --update`.",
        ],
        banned: &["untracked_ui_read"],
    },
    rules: &[
        RuleMeta { name: "undeclared_read", hint: H_UNDECLARED },
        RuleMeta { name: "declared_untracked", hint: H_UNTRACKED },
        RuleMeta { name: "hop_not_relation", hint: H_HOP },
        RuleMeta { name: "reaction_read_untracked", hint: H_REACTION },
        RuleMeta { name: "untracked_ui_read", hint: H_UI_UNTRACKED },
        RuleMeta { name: "exact_on_state_changed", hint: H_EXACT },
    ],
    allow: crate::allow_registry_fields::derived_reads::ALLOW_0,
    lists: crate::allow_registry_fields::derived_reads::SCOPE_META_0.lists,
};

