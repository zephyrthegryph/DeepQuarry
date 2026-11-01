//! The lifecycle forms' checks (doc/rewrite/final_api.html section 6 "Lifecycle forms"; code/engine/lifeforms/).
//!
//! Two lints:
//!
//! * `lifeforms` (hard): what the forms promise and DM cannot check.
//!   * `make_unknown_param`: `make(/T, ..., name = v)` where neither `/T` nor an ancestor declares `param(nameof(name))` (and `name` is
//!     not one of make()'s own `at`, `by`, `parts`).
//!   * `make_missing_required`: a `make(/T, ...)` that leaves out a `param(..., required = TRUE)` of `/T` or an ancestor.
//!   * `make_parts_without_built_from`: `make(/T, parts = ...)` where `/T` declares no `built_from()`.
//!   * `after_init_bare_new`: `new /T` (or `var/T/x = new`) of a plain datum type that declares `after_init()` (or whose ancestor does).
//!     A plain datum's after_init() is armed only by make() (code/engine/actions/after_init.dm); a bare new never runs it.
//!   * `per_type_write`: a write to a `per_type(nameof(v), ...)` var (`v[...] =`, `v +=`, `v -=`, `v |=`, `v &=`, `v.Add(`, `v.Remove(`,
//!     `v.Cut(`, `v.Insert(`, `v.Swap(`, `v = `) in a proc of the declaring type or a subtype, other than its build proc.
//!   * `allow_matches_form`: an `ALLOW(init/...)`, `ALLOW(lifecycle)` or `ALLOW(sys_usr_outside_verb)` whose reason describes what a form
//!     now declares (a random roll, a constructor argument, a timed or used-up ending, a tooltip, an admin call): the site is converted, not kept.
//! * `escape_hatches` (count ceilings, `tools/ci/escape_hatches_baseline.txt`): the sites the forms replace that remain, by kind. Each
//!   ceiling only falls (`analyze baseline --update --lint escape_hatches`); a kind whose count reached 0 has no ceiling, so its next site
//!   fails: that is the hard ban. Kinds: `init_allow` (ALLOW(init/...) keeps), `lifecycle_allow` (ALLOW(lifecycle) keeps), `usr_allow`
//!   (ALLOW(sys_usr_outside_verb) keeps), `qdel_content` (every qdel( outside the engine) and `usr_content` (every `usr` outside the engine
//!   and verb bodies).

use std::collections::{BTreeMap, BTreeSet, HashMap};

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::sem::decls::{matching_paren, split_args, Decls};
use crate::tree::{SourceFile, CODE_DM};

static META: Meta = Meta {
    name: "lifeforms",
    group: "",
    label: "lifeforms",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "make_unknown_param", hint: "declare it on the made type: param(nameof(var), schema) in its CAPABILITIES block (code/engine/lifeforms/params.dm)" },
        RuleMeta { name: "make_missing_required", hint: "pass every required param: make(/T, at = loc, name = value)" },
        RuleMeta { name: "make_parts_without_built_from", hint: "declare built_from(nameof(var)) on the made type, or drop parts =" },
        RuleMeta { name: "after_init_bare_new", hint: "the type declares after_init(), which a plain datum runs only when made by make(/T, ...): make it with make()" },
        RuleMeta { name: "per_type_write", hint: "a per_type() table is read-only and shared by every instance of the type: build it in its build proc, copy it to change it" },
        RuleMeta { name: "ctor_dead_arg", hint: "no param(nameof(v), pos = N) of the type takes the argument and no New()/Initialize() reads it: drop it (python3 tools/dx/codemods/ctor_args.py --apply), or declare the param it was meant for" },
        RuleMeta { name: "ctor_forward_only", hint: "the override only hands these parameters to ..(), which passes the caller's arguments by itself: drop them (python3 tools/dx/codemods/ctor_args.py --apply)" },
        RuleMeta { name: "param_pos_override", hint: "an ancestor already maps this constructor position: say param(..., pos = N, overrides = TRUE) when the subtype means to take it over" },
        RuleMeta { name: "param_overrides_nothing", hint: "overrides = TRUE but no ancestor declares a param at this position: drop overrides =" },
    ],
    allow: crate::allow_registry_fields::lifeforms::ALLOW_0,
    lists: &[],
};

use crate::lifeform_source_policy::is_engine;
#[cfg(test)] use crate::lifeform_source_policy::form_reasons;

#[derive(Default)]
struct Declared {
    params: HashMap<String, BTreeSet<String>>,
    required: HashMap<String, BTreeSet<String>>,
    built_from: BTreeSet<String>,
    /// type -> (var, build proc)
    per_type: HashMap<String, Vec<(String, String)>>,
    /// Plain datum types whose block declares after_init().
    after_init: BTreeSet<String>,
    /// type -> constructor position -> (var, overrides = TRUE, file, line of the CAPABILITIES block)
    positions: HashMap<String, BTreeMap<usize, (String, bool, String, u32)>>,
}

impl Declared {
    fn build(decls: &Decls) -> Declared {
        let mut d = Declared::default();
        for m in decls.markers_named("CAPABILITIES") {
            let Some(ty) = m.args.first() else { continue };
            let ty = ty.trim().to_string();
            for a in m.args.iter().skip(1) {
                for (name, args) in calls(a) {
                    match name.as_str() {
                        "param" => {
                            let Some(var) = args.first().and_then(|x| nameof_inner(x)) else { continue };
                            d.params.entry(ty.clone()).or_default().insert(var.clone());
                            let named = |key: &str| args.iter().find_map(|x| x.replace(' ', "").strip_prefix(&format!("{key}=")).map(|v| v.to_string()));
                            if let Some(pos) = named("pos").and_then(|v| v.parse::<usize>().ok()) {
                                let overrides = named("overrides").is_some_and(|v| v == "TRUE" || v == "1");
                                d.positions.entry(ty.clone()).or_default().insert(pos, (var.clone(), overrides, m.rel.clone(), m.line));
                            }
                            if args.iter().any(|x| x.replace(' ', "") == "required=TRUE") {
                                d.required.entry(ty.clone()).or_default().insert(var);
                            }
                        }
                        "built_from" => {
                            d.built_from.insert(ty.clone());
                        }
                        "after_init" if ty.starts_with("/datum") => {
                            d.after_init.insert(ty.clone());
                        }
                        "per_type" => {
                            let var = args.first().and_then(|x| nameof_inner(x));
                            let build = args.get(1).and_then(|x| x.trim().strip_prefix("PROC_REF(").and_then(|s| s.strip_suffix(')')).map(|s| s.trim().to_string()));
                            if let (Some(var), Some(build)) = (var, build) {
                                d.per_type.entry(ty.clone()).or_default().push((var, build));
                            }
                        }
                        _ => {}
                    }
                }
            }
        }
        d
    }

    /// The type and its ancestors (by path prefix), nearest first.
    fn lineage(ty: &str) -> Vec<String> {
        let parts: Vec<&str> = ty.split('/').collect();
        (2..=parts.len()).rev().map(|cut| parts[..cut].join("/")).collect()
    }

    fn has_param(&self, ty: &str, name: &str) -> bool {
        Self::lineage(ty).iter().any(|t| self.params.get(t).is_some_and(|s| s.contains(name)))
    }

    fn required_of(&self, ty: &str) -> BTreeSet<String> {
        let mut out = BTreeSet::new();
        for t in Self::lineage(ty) {
            if let Some(s) = self.required.get(&t) {
                out.extend(s.iter().cloned());
            }
        }
        out
    }

    fn builds_from(&self, ty: &str) -> bool {
        Self::lineage(ty).iter().any(|t| self.built_from.contains(t))
    }

    /// `ty` or an ancestor is a plain datum that declares after_init().
    fn after_init_of(&self, ty: &str) -> Option<String> {
        Self::lineage(ty).into_iter().find(|t| self.after_init.contains(t))
    }

    /// A line (comments and strings cleaned) that makes a plain datum declaring after_init() with a bare new: `new /T(...)` or
    /// `var/T/x = new` / `new()`. (made type, declaring type). `new some_var` is a type in a var: /datum/New() reports it at run time.
    fn after_init_bare_new(&self, line: &str) -> Option<(String, String)> {
        let bare_new = crate::pat!(r"\bnew\s*(/datum/[\w/]+)");
        let typed_new = crate::pat!(r"\bvar/(datum/[\w/]+)/\w+\s*=\s*new\s*(?:\(|$)");
        let ty = bare_new
            .captures(line)
            .and_then(|c| c.get(1).map(str::to_string))
            .or_else(|| typed_new.captures(line).and_then(|c| c.get(1).map(|t| format!("/{}", t))))?;
        let ty = ty.trim_end_matches('/').to_string();
        let decl = self.after_init_of(&ty)?;
        Some((ty, decl))
    }
}

fn nameof_inner(arg: &str) -> Option<String> {
    arg.trim().strip_prefix("nameof(").and_then(|s| s.strip_suffix(')')).map(|s| s.trim().to_string())
}

/// Every call in `text`: (name, arguments), outermost first, nested calls too.
fn calls(text: &str) -> Vec<(String, Vec<String>)> {
    let mut out = Vec::new();
    let b = text.as_bytes();
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'"' {
            i += 1;
            while i < b.len() && b[i] != b'"' {
                if b[i] == b'\\' {
                    i += 1;
                }
                i += 1;
            }
            i += 1;
            continue;
        }
        if b[i].is_ascii_alphabetic() || b[i] == b'_' {
            let start = i;
            while i < b.len() && (b[i].is_ascii_alphanumeric() || b[i] == b'_') {
                i += 1;
            }
            let prev = if start > 0 { b[start - 1] } else { b' ' };
            if i < b.len() && b[i] == b'(' && prev != b'.' && prev != b'/' {
                if let Some(close) = matching_paren(text, i) {
                    out.push((text[start..i].to_string(), split_args(&text[i + 1..close])));
                }
            }
            continue;
        }
        i += 1;
    }
    out
}

struct Lifeforms;

impl Lint for Lifeforms {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let decls = Decls::get(cx.tree);
        let d = Declared::build(&decls);
        self.constructor_positions(cx, &d, out);
        let make = crate::pat!(r"\bmake\(\s*(/[\w/]+)");
        for f in cx.all_files() {
            if f.rel.starts_with("code/engine/") || cx.exempt(&f.rel) {
                continue;
            }
            let clean = f.clean();
            if !d.after_init.is_empty() && !is_engine(&f.rel) && f.text().contains("new") {
                for (number, line) in clean.numbered() {
                    if !line.contains("new") {
                        continue;
                    }
                    if let Some((ty, decl)) = d.after_init_bare_new(line) {
                        out.site_in_msg("after_init_bare_new", &f.rel, number, format!("new {}: {} declares after_init(), which runs only for make({})", ty, decl, ty));
                    }
                }
            }
            if f.text().contains("make(") {
                for (number, line) in clean.numbered() {
                    if !line.contains("make(") {
                        continue;
                    }
                    for (name, args) in calls(line) {
                        if name != "make" {
                            continue;
                        }
                        let Some(first) = args.first() else { continue };
                        if !make.is_match(&format!("make({}", first)) {
                            continue; // a type in a var: checked at runtime
                        }
                        let ty = first.trim().to_string();
                        let mut given = BTreeSet::new();
                        for a in args.iter().skip(1) {
                            let Some((k, _)) = a.split_once('=') else { continue };
                            let k = k.trim();
                            if k.is_empty() || !k.chars().all(|c| c.is_alphanumeric() || c == '_') || a.contains("==") {
                                continue;
                            }
                            given.insert(k.to_string());
                            if k == "parts" {
                                if !d.builds_from(&ty) {
                                    out.site_in_msg("make_parts_without_built_from", &f.rel, number, format!("make({}, parts = ...): no built_from()", ty));
                                }
                                continue;
                            }
                            if k == "at" || k == "by" {
                                continue;
                            }
                            if !d.has_param(&ty, k) {
                                out.site_in_msg("make_unknown_param", &f.rel, number, format!("make({}, {} = ...): {} declares no param(nameof({}))", ty, k, ty, k));
                            }
                        }
                        for req in d.required_of(&ty) {
                            if !given.contains(&req) {
                                out.site_in_msg("make_missing_required", &f.rel, number, format!("make({}): the required param {} is not given", ty, req));
                            }
                        }
                    }
                }
            }
            if d.per_type.is_empty() {
                continue;
            }
            for p in crate::dm::dx::procs_in(f) {
                if p.is_global() {
                    continue;
                }
                for ancestor in Declared::lineage(&p.path) {
                    let Some(list) = d.per_type.get(&ancestor) else { continue };
                    for (var, build) in list {
                        if &p.name == build {
                            continue;
                        }
                        let v = regex::escape(var);
                        let write = regex::Regex::new(&format!(r"(?:^|[^\w.]){v}(?:\s*\[[^\]]*\]\s*=[^=]|\s*(?:\+=|-=|\|=|&=)|\.(?:Add|Remove|Cut|Insert|Swap)\(|\s*=[^=])")).expect("per_type write");
                        for k in 0..p.body_len {
                            let number = p.body_start + k;
                            if write.is_match(clean.line(number)) {
                                out.site_in_msg("per_type_write", &f.rel, number, format!("{} is a per_type() table of {}: read-only", var, ancestor));
                            }
                        }
                    }
                }
            }
        }
    }
}

impl Lifeforms {
    /// `param_pos_override` / `param_overrides_nothing` from the declarations, then `ctor_dead_arg` / `ctor_forward_only` on the typed tree
    /// (`sem::ctor_args`).
    fn constructor_positions(&self, cx: &Cx, d: &Declared, out: &mut Sink) {
        let skip = |rel: &str| rel.starts_with("code/engine/") || cx.exempt(rel);
        let mut types: Vec<&String> = d.positions.keys().collect();
        types.sort();
        for ty in types {
            for (pos, (var, overrides, rel, line)) in &d.positions[ty] {
                if skip(rel) {
                    continue;
                }
                let lineage = Declared::lineage(ty);
                let inherited = lineage.iter().skip(1).find(|t| d.positions.get(*t).is_some_and(|m| m.contains_key(pos)));
                match (inherited, overrides) {
                    (Some(from), false) => out.site_in_msg(
                        "param_pos_override",
                        rel,
                        *line as usize,
                        format!("{ty}: param(nameof({var}), pos = {pos}) takes over the position {from} maps; add overrides = TRUE"),
                    ),
                    (None, true) => out.site_in_msg("param_overrides_nothing", rel, *line as usize, format!("{ty}: param(nameof({var}), pos = {pos}, overrides = TRUE) overrides no ancestor's position")),
                    _ => {}
                }
            }
        }
        let files = cx.all_files();
        let key = crate::incr::ctx_key(&files.iter().map(|f| (f.rel.as_str(), f.fkey)).collect::<Vec<_>>());
        let positions: crate::sem::ctor_args::ParamPositions = d.positions.iter().map(|(t, m)| (t.clone(), m.keys().copied().collect())).collect();
        type Found = Vec<(String, u32, String)>;
        let found: Option<(Found, Found)> = crate::incr::cached("lifeforms-ctor-args", key, || {
            cx.sem().map(|sem| {
                let dead = crate::sem::ctor_args::dead_args(&sem, &positions)
                    .into_iter()
                    .map(|a| {
                        let list = a.dead.iter().map(|p| p.to_string()).collect::<Vec<_>>().join(",");
                        (a.rel, a.line, format!("new {}(loc, ...) passes {} argument(s) after the location; position(s) {} reach no param(pos =) and no New()/Initialize() [ctor-dead {} {} {}]", a.ty, a.passed, list, a.ty, a.passed, list))
                    })
                    .collect();
                let fwd = crate::sem::ctor_args::forward_only(&sem)
                    .into_iter()
                    .map(|o| {
                        let list = o.params.join(",");
                        (o.rel, o.line, format!("{}/{}(): {} only reach ..() [ctor-forward {}]", o.owner, o.name, list, list))
                    })
                    .collect();
                (dead, fwd)
            })
        });
        let Some((dead, fwd)) = found else { return };
        for (rel, line, msg) in dead {
            if !skip(&rel) {
                out.site_in_msg("ctor_dead_arg", &rel, line as usize, msg);
            }
        }
        for (rel, line, msg) in fwd {
            if !skip(&rel) {
                out.site_in_msg("ctor_forward_only", &rel, line as usize, msg);
            }
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(Lifeforms);
    crate::lifeform_source_policy::register_allows(reg);
    crate::lifeform_source_policy::register_hatches(reg);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn calls_finds_nested_and_skips_members() {
        let c = calls("x = make(/obj/item/paper, at = src, info = foo(bar)) + P.make(2)");
        let names: Vec<&str> = c.iter().map(|(n, _)| n.as_str()).collect();
        assert_eq!(names, vec!["make", "foo"]);
        assert_eq!(c[0].1, vec!["/obj/item/paper", "at = src", "info = foo(bar)"]);
    }

    #[test]
    fn after_init_bare_new_finds_literal_and_typed_news() {
        let mut d = Declared::default();
        d.after_init.insert("/datum/seed".to_string());
        assert_eq!(d.after_init_bare_new("\tvar/datum/seed/S = new /datum/seed/apple"), Some(("/datum/seed/apple".to_string(), "/datum/seed".to_string())));
        assert_eq!(d.after_init_bare_new("\tvar/datum/seed/S = new"), Some(("/datum/seed".to_string(), "/datum/seed".to_string())));
        assert_eq!(d.after_init_bare_new("\tvar/datum/seed/S = new()"), Some(("/datum/seed".to_string(), "/datum/seed".to_string())));
        assert_eq!(d.after_init_bare_new("\tvar/datum/seed/S = make(/datum/seed)"), None);
        assert_eq!(d.after_init_bare_new("\tvar/datum/seed/S = new type"), None, "a type in a var is the run-time report's");
        assert_eq!(d.after_init_bare_new("\tvar/datum/seed_pile/P = new /datum/seed_pile(O, 1)"), None, "a sibling path is not a subtype");
    }

    #[test]
    fn lineage_is_nearest_first() {
        assert_eq!(Declared::lineage("/obj/item/a"), vec!["/obj/item/a", "/obj/item", "/obj"]);
    }

    #[test]
    fn form_reasons_catch_the_codemods_old_texts() {
        let r = form_reasons();
        let hit = |lint: &str, text: &str| r.iter().any(|(l, p, _)| *l == lint && p.is_match(text));
        assert!(hit("init", "icon_state rolled at random for each instance"));
        assert!(hit("init", "charge is a constructor argument from whoever builds it"));
        assert!(hit("lifecycle", "the flare is used up"));
        assert!(!hit("init", "map edits set the id tag"));
    }
}
