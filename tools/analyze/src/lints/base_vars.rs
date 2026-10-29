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
//! records, the sparse and cooldown stores), or one declared as a relation on its own type (a `base_var_home_relations` entry in its
//! `CAPABILITIES` block, or an end of `links()`: references live in relations). Trait blocks declare no var at all.
//!
//! A hot per-tick base var that has no better home is listed in `[lint.base_vars.tables.base_var_home_hot]` of
//! `tools/ci/lint_scopes.toml` as `"<type>/<var>" = "<justification>"`: a listed var is homed. The justification is at
//! least `HOT_MIN_JUSTIFICATION` characters and names the hot reader (a `.dm` file and the proc or path that reads
//! it every tick, move or turf update). The `hot_home` rule (a ban) fails a listed var that no longer exists on its
//! base type, a malformed key, a missing or short justification, a var a home macro already names, or a list longer than `hot_ceiling` (a one-number list in `[lint.base_vars.lists]` that only falls); the summary prints the list's size.
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
use crate::lint::{Cx, Lint, Meta, Registry, Sink};
use crate::parity::Parity;
use crate::pat;
use crate::tree::SourceFile;
use crate::util::py_strip;

use crate::base_var_metadata::{BASELINE, META};

#[cfg(test)]
use crate::base_var_hot_policy::hot_key;
use crate::base_var_hot_policy::{hot_problems, HOT_TABLE, SCOPES_FILE};
pub use crate::base_var_hot_policy::{BASE_TYPES, HOT_MIN_JUSTIFICATION};
const NO_INSTANCE_COST: &[&str] = &["const", "static", "global"];

struct BaseVars;

/// A var that can produce a site: not free of instance cost, not kept by `ALLOW(base_vars)`, and
/// either on a base type (`base`) or an `= list()` candidate for `list_init` (`cand`: the instance
/// list rule's own exemptions that depend only on the file and the type are already applied).
#[derive(Serialize, Deserialize, PartialEq)]
struct RVar {
    owner: String,
    /// The var's name: with `owner` it is the declaration identity the baseline row stores (`owner::name`).
    name: String,
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

/// The `(type, var)` pairs the home macros name in `text`, and the vars declared as relations: an entry of a
/// `base_var_home_relations` kind (`ref_one(nameof(v))`, `owns_many(nameof(/T::v))`) in the `CAPABILITIES(T)` block of the
/// var's own type, or either end of a `links(/A::a, /B::b)` (doc/rewrite/proposals/base_vars.md: references live in relations).
fn facts_of(
    f: &SourceFile,
    exempt_prefixes: &[String],
    exempt_files: &[String],
    macros: &[String],
    relations: &[String],
) -> Facts {
    let mut out = Facts::default();
    let shared = crate::base_var_candidate_policy::file_facts(f, macros, relations);
    out.homes = shared.homes;
    out.singles = shared.singles;
    if f.hidden {
        return out; // the vars come from the non-hidden files only
    }
    let mut decls: HashMap<String, Vec<Var>> = HashMap::new();
    let mut latent: HashMap<String, bool> = HashMap::new();
    parse_file(&f.rel, f.code(), &mut decls, &mut latent);
    let mut owners: Vec<(String, Vec<Var>)> = decls
        .into_iter()
        .filter(|(_, vars)| !vars.is_empty())
        .collect();
    owners.sort_by(|a, b| a.1[0].line.cmp(&b.1[0].line));
    let list_init = pat!(r"=\s*list\(\s*\)\s*(?:$|//|/\*)");
    let empty: HashSet<String> = HashSet::new();
    let raw = f.raw();
    let homes: HashSet<(String, String)> = out.homes.iter().cloned().collect();
    for (owner, vars) in owners {
        out.owners.push((owner.clone(), vars[0].line as u32));
        for v in &vars {
            if v.mods
                .iter()
                .any(|m| NO_INSTANCE_COST.contains(&m.as_str()))
            {
                continue;
            }
            if crate::dm::sys::kept_recorded(f, v.line, "base_vars") {
                continue;
            }
            let base = BASE_TYPES.contains(&owner.as_str())
                && !homes.contains(&(owner.clone(), v.name.clone()));
            let text = if v.line <= raw.num_lines() {
                py_strip(raw.line(v.line))
            } else {
                ""
            };
            // list_init is instance_list's twin and takes its exemptions: a declaration under an
            // exempt path, on a singleton type, or one that carries ALLOW(instance_list) is that
            // lint's, not a second ratchet row here. (The tree-wide singleton types and the ALLOW
            // question are the judge's.)
            let exempt = exempt_prefixes
                .iter()
                .any(|p| v.path.starts_with(p.as_str()))
                || exempt_files.iter().any(|e| *e == v.path);
            let cand = list_init.is_match(text) && !exempt && !is_singleton(&owner, &empty);
            if base || cand {
                out.vars.push(RVar {
                    owner: owner.clone(),
                    name: v.name.clone(),
                    line: v.line as u32,
                    base,
                    cand,
                });
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
            let Some(decl) = &tv.declaration else {
                continue;
            };
            // const, static and global (one flag in the model) cost no instance memory.
            if decl
                .var_type
                .flags
                .intersects(VarTypeFlags::STATIC | VarTypeFlags::CONST)
            {
                continue;
            }
            let Some(rel) = sem.file_of(decl.location) else {
                continue;
            };
            let list_init = matches!(&tv.value.expression, Some(Expression::Base { term, follow }) if follow.is_empty() && matches!(&term.elem, Term::List(args) if args.is_empty()));
            if base || list_init {
                let vtype = if decl.var_type.type_path.is_empty() {
                    String::new()
                } else {
                    format!("/{}", decl.var_type.type_path.join("/"))
                };
                out.push(TypedVar {
                    rel: rel.to_string(),
                    line: crate::sem::procs::engine_line(&sem.root, rel, decl.location.line),
                    owner: owner.clone(),
                    name: name.to_string(),
                    vtype,
                    base,
                    list_init,
                });
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
                if !v.code.has_body() {
                    continue;
                }
                let Some(rel) = sem.file_of(v.location) else {
                    continue;
                };
                out.push((
                    rel.to_string(),
                    crate::sem::procs::engine_line(&sem.root, rel, v.location.line),
                    name.to_string(),
                ));
            }
        }
    }
    out.sort();
    out
}

/// Independent migration oracle only: expose the existing, unchanged semantic
/// supplements before raw homing/exemption/admission policy is applied.
#[cfg(feature = "unified-oracle")]
pub fn unified_oracle_supplement(sem: &crate::sem::Sem) -> Vec<serde_json::Value> {
    let mut rows = Vec::new();
    for declaration in typed_vars(sem) {
        let mut row = serde_json::to_value(declaration).expect("serializable legacy supplement");
        row["row"] = serde_json::json!("base_var_declaration");
        rows.push(row);
    }
    for (rel, line, name) in record_procs(sem) {
        rows.push(serde_json::json!({"row":"record_proc", "rel":rel, "line":line, "name":name}));
    }
    rows
}

/// The `(type, var)` a `base_var_home_hot` key names: `/atom/movable/pressure_resistance` is `(/atom/movable, pressure_resistance)`.
/// `hot_ceiling` from the scope lists (a one-element list holding the number), None when absent or malformed.
fn hot_ceiling(cx: &Cx) -> Option<usize> {
    cx.list("hot_ceiling")
        .first()
        .and_then(|v| v.trim().parse().ok())
}

/// The sites from the model, or None without one. ALLOW questions are asked live (recorded for the unused-annotation check).
fn typed_sites(
    cx: &Cx,
    singletons: &HashSet<String>,
    exempt_prefixes: &[String],
    exempt_files: &[String],
    homes: &HashSet<(String, String)>,
    hot: &std::collections::BTreeMap<String, String>,
) -> Option<Vec<(&'static str, String, u32, String)>> {
    let all = cx.all_files();
    let key = incr::ctx_key(
        &all.iter()
            .map(|f| (f.rel.as_str(), f.fkey))
            .collect::<Vec<_>>(),
    );
    let model: Option<(Vec<TypedVar>, Vec<(String, u32, String)>)> =
        incr::cached("base_vars-typed2", key, || {
            cx.sem().map(|sem| (typed_vars(&sem), record_procs(&sem)))
        });
    let (vars, records) = model?;
    let home_types = cx.list("base_var_home_types");
    let accessor_prefixes = cx.list("record_accessor_prefixes");
    let by_rel: HashMap<&str, &SourceFile> = all
        .iter()
        .filter(|f| !f.hidden)
        .map(|f| (f.rel.as_str(), *f))
        .collect();
    let mut out = Vec::new();
    let declared: HashSet<(String, String)> = vars
        .iter()
        .filter(|v| v.base)
        .map(|v| (v.owner.clone(), v.name.clone()))
        .collect();
    for v in &vars {
        let Some(f) = by_rel.get(v.rel.as_str()) else {
            continue;
        };
        let view = crate::base_var_candidate_policy::VarView {
            rel: &v.rel,
            line: v.line,
            owner: &v.owner,
            name: &v.name,
            vtype: &v.vtype,
            base: v.base,
            list_init: v.list_init,
        };
        let Some(checked) = crate::base_var_candidate_policy::classify(
            view,
            f,
            singletons,
            exempt_prefixes,
            exempt_files,
            homes,
            hot,
            home_types,
        ) else {
            continue;
        };
        if checked.base {
            out.push((
                "base_var",
                v.rel.clone(),
                v.line,
                format!("{}::{}", v.owner, v.name),
            ));
        }
        if checked.list {
            out.push((
                "list_init",
                v.rel.clone(),
                v.line,
                format!("{}::{}", v.owner, v.name),
            ));
        }
    }
    for (key, msg) in hot_problems(hot, Some(&declared), homes, hot_ceiling(cx)) {
        out.push((
            "hot_home",
            SCOPES_FILE.to_string(),
            1,
            format!("{}\t{}", key, msg),
        ));
    }
    for (rel, line, name) in records {
        if accessor_prefixes
            .iter()
            .any(|p| name.starts_with(p.as_str()))
        {
            continue;
        }
        out.push(("records_data_only", rel, line, String::new()));
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
        let relations = cx.list("base_var_home_relations");
        let hot = cx.table(HOT_TABLE);
        out.note(format!(
            "base_vars: {} hot base vars homed by base_var_home_hot",
            hot.len()
        ));
        let ctx = incr::ctx_key(&(exempt_prefixes, exempt_files, macros, relations));
        let facts = recorded_into(out, || {
            incr::keyed("base_vars-facts4", ctx, &all, |f| {
                facts_of(f, exempt_prefixes, exempt_files, macros, relations)
            })
        });
        let homes: HashSet<(String, String)> = facts
            .iter()
            .flat_map(|fa| fa.homes.iter().cloned())
            .collect();

        // `singleton_types()`: the union, minus bare `/datum`.
        let mut globals: BTreeSet<String> = facts
            .iter()
            .flat_map(|fa| fa.singles.iter().cloned())
            .collect();
        globals.remove("/datum");
        let global_set: HashSet<String> = globals.iter().cloned().collect();

        // The `= list()` candidates the instance_list exemptions do not already cover.
        // On the typed tree: the vars each type declares, wherever and however they are written (a multi-var line, a nested
        // block, a macro that declares them), at their real line. The text parse is the fallback without a model.
        if let Some(sites) = recorded_into(out, || {
            typed_sites(cx, &global_set, exempt_prefixes, exempt_files, &homes, &hot)
        }) {
            // A base var that carries a value schema (`SCHEMA(T, v, schema_path(...))`) is a typed value: its home is the trait field or sparse
            // slot the schema types (doc/rewrite/proposals/typed_values.md section 5, step 4). The schema alone is no home (it saves no memory),
            // so the site stays; the message names the schema so the conversion has its type.
            let schemas = crate::sem::value_schema::ValueSchemas::build(
                &crate::sem::decls::Decls::get(cx.tree),
            );
            for (rule, rel, line, ident) in sites {
                if rule == "hot_home" {
                    let (key, msg) = ident.split_once('\t').unwrap_or((ident.as_str(), ""));
                    out.site_decl(
                        rule,
                        &rel,
                        line as usize,
                        msg.to_string(),
                        format!("hot::{}", key),
                    );
                    continue;
                }
                let msg = match ident.split_once("::") {
                    Some((o, v)) if rule == "base_var" && schemas.declared_on(o, v).is_some() => {
                        crate::value_schema_policy::hint_message(ident.as_str())
                    }
                    _ => String::new(),
                };
                out.site_decl(rule, &rel, line as usize, msg, ident);
            }
            return;
        }
        for (key, msg) in hot_problems(&hot, None, &homes, hot_ceiling(cx)) {
            out.site_decl("hot_home", SCOPES_FILE, 1, msg, format!("hot::{}", key));
        }
        text_sites(&all, &facts, &globals, &global_set, &hot, out);
    }

    fn parity(&self) -> Option<Parity> {
        let mut p = Parity::ratchet(&["tools/ci/base_vars_lint.py"], &[BASELINE]);
        p.update = Some(&["tools/ci/base_vars_lint.py", "--update"]);
        p.seed = Some(&["tools/ci/base_vars_lint.py", "--seed"]);
        Some(p)
    }
}

/// The sites without a semantic model, from the text parse. A declaration site carries `owner::var` like the typed path, so it matches
/// its baseline row.
fn text_sites(
    all: &[&SourceFile],
    facts: &[Facts],
    globals: &BTreeSet<String>,
    global_set: &HashSet<String>,
    hot: &std::collections::BTreeMap<String, String>,
    out: &mut Sink,
) {
    {
        let cand_files: Vec<&SourceFile> = all
            .iter()
            .copied()
            .zip(facts.iter())
            .filter(|(_, fa)| fa.vars.iter().any(|v| v.cand))
            .map(|(f, _)| f)
            .collect();
        let by_rel: HashMap<&str, &Facts> = all
            .iter()
            .zip(facts.iter())
            .map(|(f, fa)| (f.rel.as_str(), fa))
            .collect();
        let key = incr::ctx_key(&globals);
        let judged = recorded_into(out, || {
            incr::keyed("base_vars-judge", key, &cand_files, |f| {
                let fa = by_rel[f.rel.as_str()];
                let mut hit: Vec<u32> = Vec::new();
                for (i, v) in fa.vars.iter().enumerate() {
                    if v.cand
                        && !global_set.contains(&v.owner)
                        && !crate::dm::sys::kept_recorded(f, v.line as usize, "instance_list")
                    {
                        hit.push(i as u32);
                    }
                }
                hit
            })
        });
        let judged: HashMap<&str, Vec<u32>> = cand_files
            .iter()
            .map(|f| f.rel.as_str())
            .zip(judged)
            .collect();

        // `decls.items()` order: an owner is inserted when its first var is parsed (files in path
        // order, lines in order), so owners sort by (file, line) of their first var.
        let mut wanted: HashSet<&str> = HashSet::new();
        for fa in facts.iter() {
            wanted.extend(fa.vars.iter().map(|v| v.owner.as_str()));
        }
        let mut first: HashMap<&str, (&str, u32)> = HashMap::new();
        let mut vars_of: HashMap<&str, Vec<(usize, usize)>> = HashMap::new();
        for (fi, (f, fa)) in all.iter().zip(facts.iter()).enumerate() {
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
                if v.base && !hot.contains_key(&format!("{}/{}", v.owner, v.name)) {
                    out.site_decl(
                        "base_var",
                        &f.rel,
                        v.line as usize,
                        String::new(),
                        format!("{}::{}", v.owner, v.name),
                    );
                }
                if v.cand
                    && judged
                        .get(f.rel.as_str())
                        .map(|h| h.contains(&(vi as u32)))
                        .unwrap_or(false)
                {
                    out.site_decl(
                        "list_init",
                        &f.rel,
                        v.line as usize,
                        String::new(),
                        format!("{}::{}", v.owner, v.name),
                    );
                }
            }
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(BaseVars);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tree::SourceFile;

    /// Without a semantic model the lint judges from the text, and it must fingerprint a site by `owner::var` like the typed
    /// path does, or every baselined row (stored as `@owner::var`) would read as new debt.
    #[test]
    fn fallback_path_emits_owner_var_identities() {
        let f = SourceFile::from_text(
            "code/a.dm",
            "/atom
	var/tmp/flags_9 = 0
/obj/thing
	var/list/stuff = list()
",
        );
        let none: Vec<String> = Vec::new();
        let facts = vec![facts_of(&f, &none, &none, &none, &none)];
        let mut out = Sink::new();
        text_sites(
            &[&f],
            &facts,
            &BTreeSet::new(),
            &HashSet::new(),
            &Default::default(),
            &mut out,
        );
        let base: Vec<&str> = out
            .sites
            .iter()
            .filter(|s| s.rule == "base_var")
            .map(|s| s.ident.as_str())
            .collect();
        assert_eq!(base, vec!["/atom::flags_9"], "{:?}", out.sites);
        assert!(out
            .sites
            .iter()
            .filter(|s| s.rule == "list_init")
            .all(|s| s.ident == "/obj/thing::stuff"));
        assert!(
            out.sites.iter().all(|s| !s.ident.is_empty()),
            "{:?}",
            out.sites
        );
    }

    fn hot(rows: &[(&str, &str)]) -> std::collections::BTreeMap<String, String> {
        rows.iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }

    fn declared(rows: &[(&str, &str)]) -> HashSet<(String, String)> {
        rows.iter()
            .map(|(a, b)| (a.to_string(), b.to_string()))
            .collect()
    }

    const GOOD: &str = "read every turf update in code/ATMOSPHERICS/environmental/LINDA_system.dm";

    #[test]
    fn listed_var_with_reader_and_justification_is_accepted() {
        let d = declared(&[("/atom", "can_atmos_pass")]);
        assert!(hot_problems(
            &hot(&[("/atom/can_atmos_pass", GOOD)]),
            Some(&d),
            &HashSet::new(),
            None
        )
        .is_empty());
    }

    #[test]
    fn stale_entry_fails() {
        let d = declared(&[("/atom", "flags_1")]);
        let p = hot_problems(
            &hot(&[("/atom/can_atmos_pass", GOOD)]),
            Some(&d),
            &HashSet::new(),
            None,
        );
        assert_eq!(p.len(), 1);
        assert!(p[0].1.contains("stale"), "{:?}", p);
    }

    #[test]
    fn short_or_unnamed_justification_fails() {
        let d = declared(&[("/atom", "can_atmos_pass")]);
        let short = hot_problems(
            &hot(&[("/atom/can_atmos_pass", "hot")]),
            Some(&d),
            &HashSet::new(),
            None,
        );
        assert!(
            short.iter().any(|(_, m)| m.contains("at least 40")),
            "{:?}",
            short
        );
        let empty = hot_problems(
            &hot(&[("/atom/can_atmos_pass", "")]),
            Some(&d),
            &HashSet::new(),
            None,
        );
        assert!(
            empty.iter().any(|(_, m)| m.contains("at least 40")),
            "{:?}",
            empty
        );
        let noreader = hot_problems(
            &hot(&[(
                "/atom/can_atmos_pass",
                "this one is read a lot of the time by everything",
            )]),
            Some(&d),
            &HashSet::new(),
            None,
        );
        assert!(
            noreader.iter().any(|(_, m)| m.contains("hot reader")),
            "{:?}",
            noreader
        );
    }

    #[test]
    fn malformed_and_non_base_keys_fail() {
        assert_eq!(
            hot_problems(
                &hot(&[("can_atmos_pass", GOOD)]),
                None,
                &HashSet::new(),
                None
            )
            .len(),
            1
        );
        let p = hot_problems(
            &hot(&[("/datum/thing/x", GOOD)]),
            None,
            &HashSet::new(),
            None,
        );
        assert!(p[0].1.contains("not a base type"), "{:?}", p);
    }

    #[test]
    fn tracked_listed_var_and_over_ceiling_list_fail() {
        let d = declared(&[("/atom", "can_atmos_pass"), ("/atom", "flags_1")]);
        let h = hot(&[("/atom/can_atmos_pass", GOOD), ("/atom/flags_1", GOOD)]);
        let p = hot_problems(&h, Some(&d), &declared(&[("/atom", "flags_1")]), Some(2));
        assert_eq!(p.len(), 1);
        assert!(p[0].1.contains("already homed"), "{:?}", p);
        let p = hot_problems(&h, Some(&d), &HashSet::new(), Some(1));
        assert_eq!(p.len(), 1);
        assert!(p[0].1.contains("hot_ceiling"), "{:?}", p);
        assert!(hot_problems(&h, Some(&d), &HashSet::new(), Some(2)).is_empty());
    }

    #[test]
    fn hot_key_splits_at_the_last_slash() {
        assert_eq!(
            hot_key("/atom/movable/move_resist"),
            Some(("/atom/movable", "move_resist"))
        );
        assert_eq!(hot_key("move_resist"), None);
    }

    /// An unlisted var still fails and a listed one does not, through the text path.
    #[test]
    fn listed_var_is_not_a_site_and_unlisted_is() {
        let f = SourceFile::from_text(
            "code/a.dm",
            "/atom\n\tvar/tmp/flags_9 = 0\n\tvar/tmp/hot_one = 0\n",
        );
        let none: Vec<String> = Vec::new();
        let facts = vec![facts_of(&f, &none, &none, &none, &none)];
        let mut out = Sink::new();
        text_sites(
            &[&f],
            &facts,
            &BTreeSet::new(),
            &HashSet::new(),
            &hot(&[("/atom/hot_one", GOOD)]),
            &mut out,
        );
        let base: Vec<&str> = out
            .sites
            .iter()
            .filter(|s| s.rule == "base_var")
            .map(|s| s.ident.as_str())
            .collect();
        assert_eq!(base, vec!["/atom::flags_9"], "{:?}", out.sites);
    }
}
