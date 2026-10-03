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

use std::collections::{BTreeSet, HashMap, HashSet};

use serde::{Deserialize, Serialize};

use crate::dm::pylines::recorded_into;
use crate::dm::schema::{parse_file, Var};
use crate::dm::singletons::is_singleton;
use crate::incr;
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

/// A var that can produce a site: not free of instance cost, not kept by `ALLOW(base_vars)`, and
/// either on a base type (`base`) or an `= list()` candidate for `list_init` (`cand`: the instance
/// list rule's own exemptions that depend only on the file and the type are already applied).
#[derive(Serialize, Deserialize, PartialEq)]
struct RVar {
    owner: String,
    line: u32,
    base: bool,
    cand: bool,
}

/// One file's contribution: every owner it declares a var for with its first var's line, the vars
/// that can matter (in the schema's order: owners by first line, vars in file order), and the types
/// its `GLOBAL_DATUM_INIT`s make singletons.
#[derive(Serialize, Deserialize, Default, PartialEq)]
struct Facts {
    owners: Vec<(String, u32)>,
    vars: Vec<RVar>,
    singles: Vec<String>,
}

fn facts_of(f: &SourceFile, exempt_prefixes: &[String], exempt_files: &[String]) -> Facts {
    let mut out = Facts::default();
    if f.rel.starts_with("code/") {
        let text = f.raw().text.as_str();
        if text.contains("GLOBAL_DATUM_INIT") {
            // The trailing `\x08` is the Python's literal backspace (see dm/singletons.rs).
            let mut set: BTreeSet<String> = BTreeSet::new();
            for m in pat!(r"GLOBAL_DATUM_INIT\(\s*\w+\s*,\s*(/[\w/]+)\s*,\s*new\x08").captures_iter(text) {
                set.insert(m.s(1).to_string());
            }
            out.singles = set.into_iter().collect();
        }
        if text.contains("SYSTEM_DEF(") {
            // SYSTEM_DEF(x) declares the one instance of /datum/system/x.
            let mut set: BTreeSet<String> = out.singles.iter().cloned().collect();
            for m in pat!(r"(?m)^SYSTEM_DEF\((\w+)\)").captures_iter(text) {
                set.insert(format!("/datum/system/{}", m.s(1)));
            }
            out.singles = set.into_iter().collect();
        }
    }
    if f.hidden {
        return out; // the vars come from the non-hidden files only
    }
    let mut decls: HashMap<String, Vec<Var>> = HashMap::new();
    let mut latent: HashMap<String, bool> = HashMap::new();
    parse_file(&f.rel, f.code(), &mut decls, &mut latent);
    let mut owners: Vec<(String, Vec<Var>)> = decls.into_iter().filter(|(_, vars)| !vars.is_empty()).collect();
    owners.sort_by(|a, b| a.1[0].line.cmp(&b.1[0].line));
    let list_init = pat!(r"=\s*list\(\s*\)\s*(?:$|//|/\*)");
    let empty: HashSet<String> = HashSet::new();
    let raw = f.raw();
    for (owner, vars) in owners {
        out.owners.push((owner.clone(), vars[0].line as u32));
        for v in &vars {
            if v.mods.iter().any(|m| NO_INSTANCE_COST.contains(&m.as_str())) {
                continue;
            }
            if crate::dm::sys::kept_recorded(f, v.line, "base_vars") {
                continue;
            }
            let base = BASE_TYPES.contains(&owner.as_str());
            let text = if v.line <= raw.num_lines() { py_strip(raw.line(v.line)) } else { "" };
            // list_init is instance_list's twin and takes its exemptions: a declaration under an
            // exempt path, on a singleton type, or one that carries ALLOW(instance_list) is that
            // lint's, not a second ratchet row here. (The tree-wide singleton types and the ALLOW
            // question are the judge's.)
            let exempt = exempt_prefixes.iter().any(|p| v.path.starts_with(p.as_str())) || exempt_files.iter().any(|e| *e == v.path);
            let cand = list_init.is_match(text) && !exempt && !is_singleton(&owner, &empty);
            if base || cand {
                out.vars.push(RVar { owner: owner.clone(), line: v.line as u32, base, cand });
            }
        }
    }
    out
}

impl Lint for BaseVars {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let all = cx.all_files();
        let exempt_prefixes = cx.list("list_init_exempt_prefixes");
        let exempt_files = cx.list("list_init_exempt_files");
        let ctx = incr::ctx_key(&(exempt_prefixes, exempt_files));
        let facts = recorded_into(out, || incr::keyed("base_vars-facts", ctx, &all, |f| facts_of(f, exempt_prefixes, exempt_files)));

        // `singleton_types()`: the union, minus bare `/datum`.
        let mut globals: BTreeSet<String> = facts.iter().flat_map(|fa| fa.singles.iter().cloned()).collect();
        globals.remove("/datum");
        let global_set: HashSet<String> = globals.iter().cloned().collect();

        // The `= list()` candidates the instance_list exemptions do not already cover.
        let cand_files: Vec<&SourceFile> = all.iter().copied().zip(&facts).filter(|(_, fa)| fa.vars.iter().any(|v| v.cand)).map(|(f, _)| f).collect();
        let by_rel: HashMap<&str, &Facts> = all.iter().zip(&facts).map(|(f, fa)| (f.rel.as_str(), fa)).collect();
        let key = incr::ctx_key(&globals);
        let judged = recorded_into(out, || {
            incr::keyed("base_vars-judge", key, &cand_files, |f| {
                let fa = by_rel[f.rel.as_str()];
                let mut hit: Vec<u32> = Vec::new();
                for (i, v) in fa.vars.iter().enumerate() {
                    if v.cand && !global_set.contains(&v.owner) && !crate::dm::sys::kept_recorded(f, v.line as usize, "instance_list") {
                        hit.push(i as u32);
                    }
                }
                hit
            })
        });
        let judged: HashMap<&str, Vec<u32>> = cand_files.iter().map(|f| f.rel.as_str()).zip(judged).collect();

        // `decls.items()` order: an owner is inserted when its first var is parsed (files in path
        // order, lines in order), so owners sort by (file, line) of their first var.
        let mut wanted: HashSet<&str> = HashSet::new();
        for fa in &facts {
            wanted.extend(fa.vars.iter().map(|v| v.owner.as_str()));
        }
        let mut first: HashMap<&str, (&str, u32)> = HashMap::new();
        let mut vars_of: HashMap<&str, Vec<(usize, usize)>> = HashMap::new();
        for (fi, (f, fa)) in all.iter().zip(&facts).enumerate() {
            for (owner, line) in &fa.owners {
                if wanted.contains(owner.as_str()) {
                    let cur = (f.rel.as_str(), *line);
                    let e = first.entry(owner.as_str()).or_insert(cur);
                    if cur < *e {
                        *e = cur;
                    }
                }
            }
            for (vi, v) in fa.vars.iter().enumerate() {
                vars_of.entry(v.owner.as_str()).or_default().push((fi, vi));
            }
        }
        let mut owners: Vec<&str> = vars_of.keys().copied().collect();
        owners.sort_by(|a, b| first[a].cmp(&first[b]));
        for owner in owners {
            for &(fi, vi) in &vars_of[owner] {
                let (f, v) = (all[fi], &facts[fi].vars[vi]);
                if v.base {
                    out.site_in("base_var", &f.rel, v.line as usize);
                }
                if v.cand && judged.get(f.rel.as_str()).map(|h| h.contains(&(vi as u32))).unwrap_or(false) {
                    out.site_in("list_init", &f.rel, v.line as usize);
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
