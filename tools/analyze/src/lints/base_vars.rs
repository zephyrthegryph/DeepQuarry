//! Port of `tools/ci/base_vars_lint.py` (unified plan sec 2.16, migration guide B19 / A14): the
//! base-type var and instance-list ratchet. Two rules, both shrink-only:
//!
//! * `base_var`: a var declared on a base type (`BASE_TYPES`). A `const`/`static`/`global` var costs
//!   no per-instance memory and is not counted.
//! * `list_init`: an instance var initialised with `= list()`. It takes `instance_list`'s
//!   exemptions: an exempt path (`allow_annotations.exempt_path()`, the `list_init_exempt_*` lists
//!   in `tools/ci/lint_scopes.toml`), a singleton type, or `// ALLOW(instance_list): ...`.
//!
//! A justified keep of either is `// ALLOW(base_vars): <reason>` (asked for every counted var, as
//! the Python did, so it keeps both rules at once).
//!
//! Quirks kept from the Python:
//! * the vars come from the shared `state_schema` parse (`glob.glob`: no dot-files, no dot
//!   directories), but the singleton scan walks with `os.walk` (dot-files included), so the select is
//!   hidden-inclusive and the parse gets the non-hidden subset;
//! * `exempt_path()` applies to `list_init` only: `base_var` counts unit tests, benchmarks and TGS;
//! * a var's line number is a line of the `code_only` view (not length-preserving: an unbalanced `'`
//!   swallows newlines) and is used as an index into the raw lines, so after such a swallow the raw
//!   line read (and the ALLOW lookup) is a different line than the declaration;
//! * the Python walked owners in dict insertion order (first declaring file, then line): sites are
//!   emitted in that order so duplicate fingerprints are matched the same way;
//! * `ALLOW(base_vars)` is not listed in `allow_annotations.LINTS`, so `allow_annotations.py` rejects
//!   the annotation as an unknown lint although this lint (and its docstring) accept it.

use crate::dm::schema::Schema;
use crate::dm::singletons::{is_singleton, singleton_types};
use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::Parity;
use crate::pat;
use crate::tree::{Select, SourceFile};
use crate::util::py_strip;

const BASELINE: &str = "tools/ci/base_vars_baseline.txt";

static META: Meta = Meta {
    name: "base_vars",
    group: "",
    label: "base_vars",
    legacy: "tools/ci/base_vars_lint.py",
    // The vars are parsed from `glob.glob` files (non-hidden); the singleton scan is `os.walk`.
    select: Select { roots: &[("code", "dm")], hidden: true },
    scan: ScanKind::Tree,
    policy: Policy::Sites {
        baseline: BASELINE,
        header: &[
            "Base-type vars and `= list()` instance vars (unified plan sec 2.16). rule<TAB>file<TAB>text.",
            "tools/ci/base_vars_lint.py fails on a site not listed here. A site with",
            "`// ALLOW(base_vars): <reason>` doesn't count.",
            "Shrink-only: after a sweep, `python tools/ci/base_vars_lint.py --update`.",
        ],
        banned: &[],
    },
    rules: &[
        RuleMeta {
            name: "base_var",
            hint: "don't add a var to a base type: make it a capability's state bit / cap_data, a system's private state or a flyweight (or `// ALLOW(base_vars): <reason>`)",
        },
        RuleMeta { name: "list_init", hint: "use `var/list/x` + LAZYADD/LAZYLEN, or `var/static/list/x` for a shared table" },
    ],
    allow: &["base_vars", "instance_list"],
    lists: &["list_init_exempt_prefixes", "list_init_exempt_files"],
};

const BASE_TYPES: &[&str] = &[
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
const NO_INSTANCE_COST: &[&str] = &["const", "static", "global"];

struct BaseVars;

impl Lint for BaseVars {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let all = cx.all_files();
        let parsed: Vec<&SourceFile> = all.iter().copied().filter(|f| !f.hidden).collect();
        let schema = Schema::get(cx.tree, &parsed);
        let singletons = singleton_types(cx.tree, &all);
        let exempt_prefixes = cx.list("list_init_exempt_prefixes");
        let exempt_files = cx.list("list_init_exempt_files");
        let list_init = pat!(r"=\s*list\(\s*\)\s*(?:$|//|/\*)");

        // `decls.items()` order: an owner is inserted when its first var is parsed (files in path
        // order, lines in order), so that is (file, line) of its first var.
        let mut owners: Vec<_> = schema.decls.iter().filter(|(_, vars)| !vars.is_empty()).collect();
        owners.sort_by(|a, b| (a.1[0].path.as_str(), a.1[0].line).cmp(&(b.1[0].path.as_str(), b.1[0].line)));

        for (owner, vars) in owners {
            for v in vars {
                if v.mods.iter().any(|m| NO_INSTANCE_COST.contains(&m.as_str())) {
                    continue;
                }
                let Some(f) = cx.tree.get(&v.path) else { continue };
                if out.allowed(f, v.line, "base_vars") {
                    continue;
                }
                if BASE_TYPES.contains(&owner.as_str()) {
                    out.site_in("base_var", &v.path, v.line);
                }
                let raw = f.raw();
                let text = if v.line <= raw.num_lines() { py_strip(raw.line(v.line)) } else { "" };
                // list_init is instance_list's twin and takes its exemptions: a declaration under an
                // exempt path, on a singleton type, or one that carries ALLOW(instance_list) is that
                // lint's, not a second ratchet row here.
                let exempt = exempt_prefixes.iter().any(|p| v.path.starts_with(p.as_str())) || exempt_files.iter().any(|e| *e == v.path);
                if list_init.is_match(text) && !exempt && !is_singleton(owner, &singletons) && !out.allowed(f, v.line, "instance_list") {
                    out.site_in("list_init", &v.path, v.line);
                }
            }
        }
    }

    fn parity(&self) -> Option<Parity> {
        let mut p = Parity::ratchet(&["tools/ci/base_vars_lint.py"], &[BASELINE]);
        p.update = Some(&["tools/ci/base_vars_lint.py", "--update"]);
        p.seed = Some(&["tools/ci/base_vars_lint.py", "--seed"]);
        Some(p)
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(BaseVars);
}
