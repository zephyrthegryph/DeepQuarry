//! The lifecycle forms' checks (doc/rewrite/final_api.html section 6 "Lifecycle forms"; code/engine/lifeforms/).
//!
//! Two lints:
//!
//! * `lifeforms` (hard): what the forms promise and DM cannot check.
//!   * `make_unknown_param`: `make(/T, ..., name = v)` where neither `/T` nor an ancestor declares `param(nameof(name))` (and `name` is
//!     not one of make()'s own `at`, `by`, `parts`).
//!   * `make_missing_required`: a `make(/T, ...)` that leaves out a `param(..., required = TRUE)` of `/T` or an ancestor.
//!   * `make_parts_without_built_from`: `make(/T, parts = ...)` where `/T` declares no `built_from()`.
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
        RuleMeta { name: "per_type_write", hint: "a per_type() table is read-only and shared by every instance of the type: build it in its build proc, copy it to change it" },
    ],
    allow: &[],
    lists: &[],
};

static ALLOWS: Meta = Meta {
    name: "lifeform_allows",
    group: "",
    label: "lifeform_allows",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Sites {
        baseline: "tools/ci/lifeform_allows_baseline.txt",
        header: &[
            "ALLOW keeps whose reason describes a lifecycle form (tools/analyze/src/lints/lifeforms.rs). rule<TAB>file<TAB>normalized line.",
            "Shrink-only: convert the site to its form, then `analyze baseline --update --lint lifeform_allows`. A new one fails.",
        ],
        banned: &[],
    },
    rules: &[RuleMeta { name: "allow_matches_form", hint: "the reason names what a lifecycle form declares: convert the site (rolls(), param()/make(), expire()/spent()/consumed()/destroyed()/dissolved()/replace_with(), lives_while(), tooltip()/click_on()/drag_onto(), with_actor()) instead of keeping it" }],
    allow: &[],
    lists: &[],
};

static HATCHES: Meta = Meta {
    name: "escape_hatches",
    group: "",
    label: "escape_hatches",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Ceilings {
        baseline: "tools/ci/escape_hatches_baseline.txt",
        header: &[
            "escape_hatches ceilings (tools/analyze/src/lints/lifeforms.rs): the Initialize(), qdel and usr sites the lifecycle forms replace that remain.",
            "Shrink-only: `analyze baseline --update --lint escape_hatches` lowers them; a kind at 0 has no line, so its next site fails (the hard ban).",
        ],
    },
    rules: &[
        RuleMeta { name: "init_allow", hint: "an Initialize() kept with ALLOW(init/...): declare what it sets (rolls(), param(), contains(), starts_as(), derives(), registry())" },
        RuleMeta { name: "lifecycle_allow", hint: "a qdel kept with ALLOW(lifecycle): end it with a verb that says why (spent(), consumed(), destroyed(), dissolved(), expire(), replace_with())" },
        RuleMeta { name: "usr_allow", hint: "usr kept with ALLOW(sys_usr_outside_verb): take the actor from the input (click_on(), drag_onto(), hover(), tooltip()) or run under with_actor()" },
        RuleMeta { name: "qdel_content", hint: "qdel() is the engine's: content ends a thing with spent(), consumed(), destroyed(), dissolved(), expire(), replace_with(), consume() or slot_clear()" },
        RuleMeta { name: "usr_content", hint: "usr is the engine's: content takes its actor as an argument (click_on()/drag_onto()/hover()/tooltip() hand it one)" },
    ],
    allow: &[],
    lists: &[],
};

/// The engine and the paths whose qdel and usr are the mechanism: they do not count against content.
const ENGINE_PREFIXES: &[&str] = &[
    "code/engine/",
    "code/library/",
    "code/datums/lifecycle/",
    "code/controllers/subsystems/garbage.dm",
    "code/__defines/",
    "code/modules/unit_tests/",
    "code/modules/benchmarks/",
    "code/tests/",
    "code/modules/tgs/",
];

fn is_engine(rel: &str) -> bool {
    ENGINE_PREFIXES.iter().any(|p| rel.starts_with(p))
}

/// (pattern, form) pairs: an ALLOW reason matching the pattern describes what the form declares.
fn form_reasons() -> Vec<(&'static str, regex::Regex, &'static str)> {
    let r = |p: &str| regex::Regex::new(p).expect("form reason pattern");
    vec![
        ("init", r(r"(?i)rolled at random|random(ly)? (roll|pick|chosen)"), "rolls()"),
        ("init", r(r"(?i)constructor argument"), "param() and make()"),
        ("lifecycle", r(r"(?i)\b(expires?|timed (delete|deletion|removal)|times out)\b"), "expire()"),
        ("lifecycle", r(r"(?i)\b(used up|single[- ]use|spent)\b"), "spent()"),
        ("lifecycle", r(r"(?i)\b(eaten|drunk|consumed by)\b"), "consumed()"),
        ("lifecycle", r(r"(?i)\b(dissolve[sd]?|melts?|melted)\b"), "dissolved()"),
        ("lifecycle", r(r"(?i)\b(replaced by|becomes (a|an|the))\b"), "replace_with()"),
        ("sys_usr_outside_verb", r(r"(?i)\btooltip"), "tooltip()"),
        ("sys_usr_outside_verb", r(r"(?i)\b(native|hud|screen)\b.*\bclick"), "click_on()"),
        ("sys_usr_outside_verb", r(r"(?i)\b(drag|drop)\b"), "drag_onto()"),
        ("sys_usr_outside_verb", r(r"(?i)\b(callback|proc ?call|admin call)\b"), "with_actor()"),
    ]
}

/// What the CAPABILITIES blocks declare for the checks: per type, its params, required params, built_from and per_type vars.
#[derive(Default)]
struct Declared {
    params: HashMap<String, BTreeSet<String>>,
    required: HashMap<String, BTreeSet<String>>,
    built_from: BTreeSet<String>,
    /// type -> (var, build proc)
    per_type: HashMap<String, Vec<(String, String)>>,
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
                            if args.iter().any(|x| x.replace(' ', "") == "required=TRUE") {
                                d.required.entry(ty.clone()).or_default().insert(var);
                            }
                        }
                        "built_from" => {
                            d.built_from.insert(ty.clone());
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
        let make = crate::pat!(r"\bmake\(\s*(/[\w/]+)");
        for f in cx.all_files() {
            if f.rel.starts_with("code/engine/") || cx.exempt(&f.rel) {
                continue;
            }
            let clean = f.clean();
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

struct LifeformAllows;

impl Lint for LifeformAllows {
    fn meta(&self) -> &Meta {
        &ALLOWS
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        if f.rel.starts_with("code/engine/_generated/") {
            return;
        }
        let reasons = form_reasons();
        let raw = f.raw();
        for number in 1..=raw.num_lines() {
            let line = raw.line(number);
            let Some(a) = crate::allow::parse(line) else { continue };
            for (lint, pat, form) in &reasons {
                if a.names.contains(*lint) && pat.is_match(&a.reason) {
                    out.site_msg("allow_matches_form", number, format!("ALLOW({}) \"{}\": {} declares this", lint, a.reason, form));
                    break;
                }
            }
        }
    }
}

struct EscapeHatches;

impl Lint for EscapeHatches {
    fn meta(&self) -> &Meta {
        &HATCHES
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        if is_engine(&f.rel) || f.rel.starts_with("maps/") {
            return;
        }
        let raw = f.raw();
        let clean = f.clean();
        let qdel = crate::pat!(r"(?<![\w.])qdel\s*\(");
        let usr = crate::pat!(r"(?<![\w.])usr(?!\w)");
        let verbs = verb_lines(f);
        let mut counts: BTreeMap<&str, Vec<usize>> = BTreeMap::new();
        for number in 1..=raw.num_lines() {
            if let Some(a) = crate::allow::parse(raw.line(number)) {
                if a.names.contains("init") {
                    counts.entry("init_allow").or_default().push(number);
                }
                if a.names.contains("lifecycle") {
                    counts.entry("lifecycle_allow").or_default().push(number);
                }
                if a.names.contains("sys_usr_outside_verb") {
                    counts.entry("usr_allow").or_default().push(number);
                }
            }
            let code = clean.line(number);
            if code.contains("qdel") && qdel.is_match(code) && !code.trim_start().starts_with('#') {
                counts.entry("qdel_content").or_default().push(number);
            }
            if code.contains("usr") && usr.is_match(code) && !verbs.contains(&number) && !code.trim_start().starts_with('#') {
                counts.entry("usr_content").or_default().push(number);
            }
        }
        for (kind, lines) in counts {
            for number in lines {
                let rel = f.rel.clone();
                out.site_keyed(kind, &rel, number, f.line(number).trim().to_string(), kind);
            }
        }
    }
}

/// The lines of a verb's body (where `usr` is the verb's own caller): a proc under /verb/ or one with a `set name`-style line, and the body of
/// an ADMIN_VERB / DECLARE_*VERB macro. The same reading as sys/usr_use.
fn verb_lines(f: &SourceFile) -> std::collections::HashSet<usize> {
    let set_stmt = crate::pat!(r"^\s*set\s+(?:name|category|src|desc|hidden|popup_menu|instant)\b");
    let verb_macro = crate::pat!(r"^(?:ADMIN_VERB\w*|DECLARE_\w*VERB\w*)\(");
    let clean = f.clean();
    let mut out = std::collections::HashSet::new();
    for proc in crate::dm::dx::procs_in(f) {
        let end = proc.body_start + proc.body_len.max(1) - 1;
        let head = clean.line(proc.line);
        let verb = head.split('(').next().unwrap_or("").contains("/verb/") || (0..proc.body_len).any(|k| set_stmt.is_match(clean.line(proc.body_start + k)));
        if verb {
            out.extend(proc.line..=end);
        }
    }
    let n = clean.num_lines();
    let mut i = 1;
    while i <= n {
        if verb_macro.is_match(clean.line(i)) {
            out.insert(i);
            let mut j = i + 1;
            while j <= n && (clean.line(j).starts_with('\t') || clean.line(j).starts_with(' ') || clean.line(j).trim().is_empty()) {
                out.insert(j);
                j += 1;
            }
            i = j;
            continue;
        }
        i += 1;
    }
    out
}

pub fn register(reg: &mut Registry) {
    reg.add(Lifeforms);
    reg.add(LifeformAllows);
    reg.add(EscapeHatches);
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
