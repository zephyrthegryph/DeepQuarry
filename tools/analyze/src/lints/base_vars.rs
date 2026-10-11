//! Port of `tools/ci/base_vars_lint.py` (unified plan sec 2.16, migration guide B19 / A14): the
//! base-type var and instance-list ratchet. Two rules, both shrink-only:
//!
//! * `base_var`: a var declared on a base type (`BASE_TYPES`). A `const`/`static`/`global` var costs
//!   no per-instance memory and is not counted.
//! * `list_init`: an instance var initialised with `= list()`. It takes `instance_list`'s
//!   exemptions: an exempt path (`allow_annotations.exempt_path()`, the `list_init_exempt_*` lists
//!   in `tools/ci/lint_scopes.toml`), a singleton type, or `// ALLOW(instance_list): ...`.
//!
//! * `records_data_only` (a ban): a proc defined on `/datum/record` or a subtype other than an accessor
//!   (`record_accessor_prefixes`, `set_`/`get_`).
//!
//! A base var with a home is not counted (doc/rewrite/proposals/base_vars.md): one named by a
//! `TRACKED(T, v)`/`STAT(T, v, ...)` line or another `base_var_home_macros` declaration on its own
//! type, or one whose declared type is under a `base_var_home_types` path (the HUD datum, the profile
//! records, the sparse and cooldown stores). Trait blocks declare no var at all.
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
        banned: &["records_data_only"],
    },
    rules: &[
        RuleMeta {
            name: "base_var",
            hint: "don't add a var to a base type: make it a capability's state bit / cap_data, a system's private state or a flyweight (or `// ALLOW(base_vars): <reason>`)",
        },
        RuleMeta { name: "list_init", hint: "use `var/list/x` + LAZYADD/LAZYLEN, or `var/static/list/x` for a shared table" },
        RuleMeta {
            name: "records_data_only",
            hint: "a /datum/record holds data fields only: move the proc to the domain that uses the record (accessors `set_x`/`get_x` are fine)",
        },
    ],
    allow: &["base_vars", "instance_list"],
    lists: &["list_init_exempt_prefixes", "list_init_exempt_files", "base_var_home_macros", "base_var_home_types", "record_accessor_prefixes"],
};

pub const BASE_TYPES: &[&str] = &[
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
    /// `(type, var)` pairs a home macro (`TRACKED(T, v)`, `STAT(T, v, ...)`) names in this file.
    homes: Vec<(String, String)>,
}

/// The `(type, var)` pairs the home macros name in `text`.
fn homes_in(text: &str, macros: &[String]) -> Vec<(String, String)> {
    let mut out = Vec::new();
    for m in pat!(r"(?m)^[ 	]*([A-Z_]+)\(\s*(/[\w/]+)\s*,\s*(\w+)").captures_iter(text) {
        if macros.iter().any(|x| x == m.s(1)) {
            out.push((m.s(2).to_string(), m.s(3).to_string()));
        }
    }
    out
}

fn facts_of(f: &SourceFile, exempt_prefixes: &[String], exempt_files: &[String], macros: &[String]) -> Facts {
    let mut out = Facts::default();
    if f.rel.starts_with("code/") {
        let text = f.raw().text.as_str();
        out.homes = homes_in(f.code().text.as_str(), macros);
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
    let homes: HashSet<(String, String)> = out.homes.iter().cloned().collect();
    for (owner, vars) in owners {
        out.owners.push((owner.clone(), vars[0].line as u32));
        for v in &vars {
            if v.mods.iter().any(|m| NO_INSTANCE_COST.contains(&m.as_str())) {
                continue;
            }
            if crate::dm::sys::kept_recorded(f, v.line, "base_vars") {
                continue;
            }
            let base = BASE_TYPES.contains(&owner.as_str()) && !homes.contains(&(owner.clone(), v.name.clone()));
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

/// A var a type declares, from the model: `(file, line, owner, on a base type, an `= list()` candidate)`.
#[derive(Serialize, Deserialize, PartialEq)]
struct TypedVar {
    rel: String,
    line: u32,
    owner: String,
    name: String,
    /// The declared type path (`/datum/hud`), empty for an untyped var.
    vtype: String,
    base: bool,
    list_init: bool,
}

fn typed_vars(sem: &crate::sem::Sem) -> Vec<TypedVar> {
    use dreammaker::ast::{Expression, Term, VarTypeFlags};
    let mut out = Vec::new();
    for ty in sem.objtree.iter_types() {
        // A var at the top level of a file is a global (one value per world), not an instance var.
        if ty.get().path.is_empty() {
            continue;
        }
        let owner = ty.get().path.clone();
        let base = BASE_TYPES.contains(&owner.as_str());
        for (name, tv) in ty.get().vars.iter() {
            let Some(decl) = &tv.declaration else { continue };
            // const, static and global (one flag in the model) cost no instance memory.
            if decl.var_type.flags.intersects(VarTypeFlags::STATIC | VarTypeFlags::CONST) {
                continue;
            }
            let Some(rel) = sem.file_of(decl.location) else { continue };
            let list_init = matches!(&tv.value.expression, Some(Expression::Base { term, follow }) if follow.is_empty() && matches!(&term.elem, Term::List(args) if args.is_empty()));
            if base || list_init {
                let vtype = if decl.var_type.type_path.is_empty() { String::new() } else { format!("/{}", decl.var_type.type_path.join("/")) };
                out.push(TypedVar { rel: rel.to_string(), line: crate::sem::procs::engine_line(&sem.root, rel, decl.location.line), owner: owner.clone(), name: name.to_string(), vtype, base, list_init });
            }
        }
    }
    out.sort_by(|a, b| (&a.rel, a.line, &a.owner).cmp(&(&b.rel, b.line, &b.owner)));
    out
}

/// Procs defined on `/datum/record` and its subtypes: `(file, line, proc name)`.
fn record_procs(sem: &crate::sem::Sem) -> Vec<(String, u32, String)> {
    let mut out = Vec::new();
    for ty in sem.objtree.iter_types() {
        let path = &ty.get().path;
        if path != "/datum/record" && !path.starts_with("/datum/record/") {
            continue;
        }
        for (name, tp) in ty.get().procs.iter() {
            for v in tp.value.iter() {
                if v.code.is_none() {
                    continue;
                }
                let Some(rel) = sem.file_of(v.location) else { continue };
                out.push((rel.to_string(), crate::sem::procs::engine_line(&sem.root, rel, v.location.line), name.to_string()));
            }
        }
    }
    out.sort();
    out
}

/// The sites from the model, or None without one. ALLOW questions are asked live (recorded for the unused-annotation check).
fn typed_sites(cx: &Cx, singletons: &HashSet<String>, exempt_prefixes: &[String], exempt_files: &[String], homes: &HashSet<(String, String)>) -> Option<Vec<(&'static str, String, u32)>> {
    let all = cx.all_files();
    let key = incr::ctx_key(&all.iter().map(|f| (f.rel.as_str(), f.fkey)).collect::<Vec<_>>());
    let model: Option<(Vec<TypedVar>, Vec<(String, u32, String)>)> = incr::cached("base_vars-typed2", key, || cx.sem().map(|sem| (typed_vars(&sem), record_procs(&sem))));
    let (vars, records) = model?;
    let home_types = cx.list("base_var_home_types");
    let accessor_prefixes = cx.list("record_accessor_prefixes");
    let by_rel: HashMap<&str, &SourceFile> = all.iter().filter(|f| !f.hidden).map(|f| (f.rel.as_str(), *f)).collect();
    let empty: HashSet<String> = HashSet::new();
    let mut out = Vec::new();
    for v in &vars {
        let Some(f) = by_rel.get(v.rel.as_str()) else { continue };
        if crate::dm::sys::kept_recorded(f, v.line as usize, "base_vars") {
            continue;
        }
        let housed = homes.contains(&(v.owner.clone(), v.name.clone())) || home_types.iter().any(|h| v.vtype == *h || v.vtype.starts_with(&format!("{}/", h)));
        if v.base && !housed {
            out.push(("base_var", v.rel.clone(), v.line));
        }
        if v.list_init {
            let exempt = exempt_prefixes.iter().any(|p| v.rel.starts_with(p.as_str())) || exempt_files.iter().any(|e| *e == v.rel);
            if !exempt && !is_singleton(&v.owner, &empty) && !singletons.contains(&v.owner) && !crate::dm::sys::kept_recorded(f, v.line as usize, "instance_list") {
                out.push(("list_init", v.rel.clone(), v.line));
            }
        }
    }
    for (rel, line, name) in records {
        if accessor_prefixes.iter().any(|p| name.starts_with(p.as_str())) {
            continue;
        }
        out.push(("records_data_only", rel, line));
    }
    Some(out)
}

impl Lint for BaseVars {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let all = cx.all_files();
        let exempt_prefixes = cx.list("list_init_exempt_prefixes");
        let exempt_files = cx.list("list_init_exempt_files");
        let macros = cx.list("base_var_home_macros");
        let ctx = incr::ctx_key(&(exempt_prefixes, exempt_files, macros));
        let facts = recorded_into(out, || incr::keyed("base_vars-facts2", ctx, &all, |f| facts_of(f, exempt_prefixes, exempt_files, macros)));
        let homes: HashSet<(String, String)> = facts.iter().flat_map(|fa| fa.homes.iter().cloned()).collect();

        // `singleton_types()`: the union, minus bare `/datum`.
        let mut globals: BTreeSet<String> = facts.iter().flat_map(|fa| fa.singles.iter().cloned()).collect();
        globals.remove("/datum");
        let global_set: HashSet<String> = globals.iter().cloned().collect();

        // The `= list()` candidates the instance_list exemptions do not already cover.
        // On the typed tree: the vars each type declares, wherever and however they are written (a multi-var line, a nested
        // block, a macro that declares them), at their real line. The text parse is the fallback without a model.
        if let Some(sites) = recorded_into(out, || typed_sites(cx, &global_set, exempt_prefixes, exempt_files, &homes)) {
            for (rule, rel, line) in sites {
                out.site_in(rule, &rel, line as usize);
            }
            return;
        }

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
