//! Frozen original auto-tracking decision and collision producer.
use std::collections::{BTreeMap,BTreeSet,HashMap};
use dq_analyze::tree::Tree;
const RESERVED:&[&str]=&["value","src","usr","null","world"];
const AUTO_REL:&str="code/engine/_generated/auto_tracked.dm";
const TRACKED_LISTS_REL:&str="code/engine/_generated/tracked_lists.dm";
/// One var the generator tracks.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct Auto {
    pub ty: String,
    pub var: String,
    pub list: bool,
}

/// What the inference decided.
#[derive(Default)]
pub struct AutoSet {
    pub tracked: Vec<Auto>,
    /// `(type, var, why)` candidates left alone.
    pub blocked: Vec<(String, String, String)>,
}

/// Whether a proc definition at `loc` is the expansion of a `TRACKED(T, v)` line (the macro writes `set_v` at the line of its invocation): that is
/// the declaration the generator replaces, not a hand-written proc it would clash with.
fn from_tracked_macro(tree: &Tree, sem: &crate::sem::Sem, loc: dreammaker::Location) -> bool {
    let Some(rel) = crate::file_of_public(sem,loc) else { return false };
    let Some(f) = tree.get(rel) else { return false };
    f.raw().lines().nth((loc.line as usize).saturating_sub(1)).is_some_and(|l| {
        let t = l.trim_start();
        t.starts_with("TRACKED(") || t.starts_with("TRACKED_BRIDGED(")
    })
}

/// Every `set_*` proc defined outside the generated file, by name: the types that define it.
pub fn setter_defs(tree: &Tree, sem: &crate::sem::Sem) -> HashMap<String, Vec<String>> {
    let mut out: HashMap<String, Vec<String>> = HashMap::new();
    for t in sem.objtree.iter_types() {
        let path = if t.get().path.is_empty() { "/".to_string() } else { t.get().path.clone() };
        for (name, p) in &t.get().procs {
            if !["set_", "add_", "include_", "remove_", "clear_", "insert_", "swap_", "cut_"].iter().any(|p| name.starts_with(p)) {
                continue;
            }
            if p.declaration.is_some() && p.value.iter().any(|v| crate::file_of_public(sem,v.location) != Some(AUTO_REL) && crate::file_of_public(sem,v.location) != Some(TRACKED_LISTS_REL) && !from_tracked_macro(tree, sem, v.location)) {
                out.entry(name.clone()).or_default().push(path.clone());
            }
        }
    }
    out
}

/// The vars of `candidates` the generator can give a setter, and the ones it cannot (with why).
pub fn decide(tree: &Tree, sem: &crate::sem::Sem, candidates: &BTreeSet<(String, String)>, exclude: &[String]) -> AutoSet {
    let defs = setter_defs(tree, sem);
    let mut out = AutoSet::default();
    let mut kept: Vec<Auto> = Vec::new();
    for (owner, var) in candidates {
        let why = |s: &str| Some(s.to_string());
        let blocked = (|| {
            if RESERVED.contains(&var.as_str()) {
                return why("a reserved name");
            }
            if exclude.iter().any(|e| e == var || e.strip_prefix(owner.as_str()).and_then(|r| r.strip_prefix("::")) == Some(var.as_str())) {
                return why("excluded in tools/ci/lint_scopes.toml [lint.auto_tracked.lists] exclude");
            }
            let Some(sig) = sem.var_decl(owner, var) else { return why("no declaration") };
            if sig.file.is_empty() {
                return why("a built-in var");
            }
            if sig.file == AUTO_REL {
                return why("declared in the generated file");
            }
            // code/modules/tgui/modules/ holds window hosts (content); the rest of code/modules/tgui/ is the engine's own.
            if crate::sem::reads::ENGINE_DIRS.iter().any(|d| sig.file.starts_with(d)) && !sig.file.starts_with("code/modules/tgui/modules/") {
                return why("engine-internal state: the framework's own bookkeeping publishes itself");
            }
            if sig.file.contains("benchmarks/") {
                return why("declared in a benchmark file, which only the bench build compiles");
            }
            if sig.is_static || sig.is_const {
                return why("static or const");
            }
            if !sem.is_subtype(owner, "/datum") {
                return why("not a /datum type");
            }
            if sem.is_subtype(owner, "/datum/record") {
                return why("a profile record: its fields are TRACKED_DATA, and a record holds data only");
            }
            // The declaring type: a read through a subtype of it names the same var.
            if sem.var_owner(owner, var).as_deref() != Some(owner.as_str()) {
                return why("declared on another type");
            }
            let name = format!("set_{}", var);
            if let Some(types) = defs.get(&name) {
                if let Some(t) = types.iter().find(|t| sem.is_subtype(owner, t) || sem.is_subtype(t, owner)) {
                    return Some(format!("{} already defines {}()", t, name));
                }
            }
            if sig.is_list() {
                for gen in [format!("add_{var}"), format!("include_{var}"), format!("remove_{var}"), format!("set_{var}_at"), format!("clear_{var}"), format!("insert_{var}"), format!("swap_{var}"), format!("cut_{var}")] {
                    if let Some(t) = defs.get(&gen).and_then(|types| types.iter().find(|t| sem.is_subtype(owner, t) || sem.is_subtype(t, owner))) {
                        return Some(format!("{} already defines {}(), a list mutator the generator would write", t, gen));
                    }
                }
            }
            if sig.is_list() && sem.var_decl(owner, &format!("{}_version", var)).is_some_and(|v| v.file != TRACKED_LISTS_REL) {
                return why("the list's _version var is taken");
            }
            None
        })();
        match blocked {
            Some(w) => out.blocked.push((owner.clone(), var.clone(), w)),
            None => kept.push(Auto { ty: owner.clone(), var: var.clone(), list: sem.var_decl(owner, var).map(|s| s.is_list()).unwrap_or(false) }),
        }
    }
    // A `proc/set_v` declared on the type, an ancestor or a subtype is a clash (the compiler rejects the second declaration). An override
    // written without `proc/` (`/mob/living/set_stat(x)`, calling `..()`) is not a declaration and is ignored by `setter_defs`.
    // A var tracked on a type and again on one of its subtypes needs one setter: the ancestor's.
    let by_var: BTreeMap<&str, Vec<&Auto>> = kept.iter().fold(BTreeMap::new(), |mut m, a| {
        m.entry(a.var.as_str()).or_default().push(a);
        m
    });
    for a in &kept {
        let shadowed = by_var[a.var.as_str()].iter().any(|b| b.ty != a.ty && sem.is_subtype(&a.ty, &b.ty));
        if shadowed {
            out.blocked.push((a.ty.clone(), a.var.clone(), "an ancestor tracks it".to_string()));
        } else {
            out.tracked.push(a.clone());
        }
    }
    out.tracked.sort();
    out.blocked.sort();
    out
}

