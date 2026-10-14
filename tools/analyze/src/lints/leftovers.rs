//! Port of `tools/ci/leftovers_lints.py`: finished sweeps stay finished (doc/rewrite/archive/completion_plan.md:
//! I-menu, G-traits, MED-4). Three kinds in one script, each at 0 with no ceiling:
//!
//! * `radial`: `show_radial_menu(` / `show_radial_menu_persistent(` / `new /datum/radial_menu` outside
//!   the radial implementation (the `radial_impl_prefixes` list in `lint_scopes.toml`). A
//!   `// ALLOW(radial): reason` keeps one.
//! * `traits`: the `*_TRAIT` macros and `_status_traits`. No ALLOW.
//! * `disease`: `/datum/disease`. No ALLOW.
//!
//! Comments and strings are ignored (the `code_only` view).
//!
//! Quirks kept: line numbers are those of the `code_only` text, whose newline count can differ from
//! the raw file's after an unbalanced quote, and the same number indexes the raw lines for the ALLOW
//! lookup. A site is `radial` only when the path is not `<prefix><anything without />.dm`.
//! The old CI run lists at most 20 sites per kind; the engine lists them all.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat;
use crate::tree::{SourceFile, CODE_DM};

const HINT: &str = "Radials ask a typed prompt; traits are grants; diseases are afflictions (tools/ci/leftovers_lints.py)";

static META: Meta = Meta {
    name: "leftovers",
    group: "",
    label: "leftovers",
    legacy: "tools/ci/leftovers_lints.py",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "radial", hint: HINT },
        RuleMeta { name: "traits", hint: HINT },
        RuleMeta { name: "disease", hint: HINT },
    ],
    allow: &["radial"],
    lists: &["radial_impl_prefixes"],
};

struct Leftovers;

/// `re.match(r"^<prefix>[^/]*\.dm$", rel)` for one of the configured prefixes.
fn radial_impl(rel: &str, prefixes: &[String]) -> bool {
    prefixes.iter().any(|p| match rel.strip_prefix(p.as_str()) {
        Some(rest) => !rest.contains('/') && rest.ends_with(".dm"),
        None => false,
    })
}

impl Lint for Leftovers {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, cx: &Cx, f: &SourceFile, out: &mut Sink) {
        let prefixes = cx.list("radial_impl_prefixes");
        let radial_exempt = radial_impl(&f.rel, prefixes);
        for (lineno, line) in f.code().numbered() {
            if pat!(r"(?<![\w/])show_radial_menu(?:_persistent)?\s*\(|\bnew\s*/datum/radial_menu\b").is_match(line)
                && !radial_exempt
                && !out.allowed(f, lineno, "radial")
            {
                out.site("radial", lineno);
            }
            if pat!(
                r"(?<![\w/])(?:ADD_TRAIT|REMOVE_TRAIT|REMOVE_TRAITS_IN|REMOVE_TRAITS_NOT_IN|REMOVE_TRAIT_NOT_FROM|HAS_TRAIT|HAS_TRAIT_FROM|HAS_TRAIT_FROM_ONLY|HAS_TRAIT_NOT_FROM|HAS_MIND_TRAIT|GET_TRAIT_SOURCES|COUNT_TRAIT_SOURCES|TRAIT_CALLBACK_ADD|TRAIT_CALLBACK_REMOVE)\s*\(|\b_status_traits\b"
            )
            .is_match(line)
            {
                out.site("traits", lineno);
            }
            if pat!(r"/datum/disease\b").is_match(line) {
                out.site("disease", lineno);
            }
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/leftovers_lints.py"],
            old_raw: &[
                &["tools/ci/leftovers_lints.py", "--report", "radial"],
                &["tools/ci/leftovers_lints.py", "--report", "traits"],
                &["tools/ci/leftovers_lints.py", "--report", "disease"],
            ],
            blank: &[],
            parse: ParseKind::Bare,
            update: None,
            seed: None,
            files: &[],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(Leftovers);
}
