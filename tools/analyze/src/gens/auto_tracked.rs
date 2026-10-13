//! `analyze gen auto_tracked` -> `code/engine/_generated/auto_tracked.dm`: read-driven tracking (doc/rewrite/final_api.html section 7,
//! "Reactive closure", mechanism 1).
//!
//! A var that reactive code reads is tracked without anyone declaring it. Reactive code is what the dependency analysis walks
//! (`gens::deps`): a stat's contributions, conditions, requirements and formulas, a draw(), an every() gate, a Life step's `woken_by`,
//! an on_change consumer, a derived value. Every `(type, var)` those read off the holder (or across a declared relation) that no
//! declaration already makes reactive (tracked, a relation, a stat, a derived value) and that something writes is written here as the
//! `TRACKED(T, v)` the author would have written:
//!
//! ```text
//! TRACKED(/mob/living/carbon/human, w_uniform)   ->   /mob/living/carbon/human/proc/set_w_uniform(value)
//! ```
//!
//! so the setter has the semantics of every other tracked var (`TRACKED_UNCHANGED` compare, publish through `tracked_changed`, a list
//! gets the generated `add_v` / `remove_v` / ... of `gens::tracked_lists`) and the `tracked` lint holds every write of it to that setter;
//! `analyze fix` rewrites `v = x`, `src.v = x` and `O.v = x` to the setter call.
//!
//! The inference never reads its own output, so it is stable: it judges "is this var already reactive" from the declarations a person
//! wrote (`Decls::tracked_explicit`: TRACKED, SETTER and the other declaration forms outside this file) and not from the file it writes. A var stays here while
//! a consumer reads it, or while a call `set_v(...)` exists in the tree (a call written by `analyze fix` must keep compiling after the
//! last reader goes). A var is left alone (and listed in `blocked`) when a proc named `set_v` already exists on its type, an ancestor or a
//! subtype without being its registered setter, or when it cannot take a generated setter: a built-in var, a `static` / `const` var, a
//! var of a type that is not a /datum.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::sync::Arc;

use crate::sem::gen::{GenCx, GenOut, Generator};
use crate::sem::reads::ReadsEngine;
use crate::tree::{Tree, CODE_DM};

/// The file `analyze gen auto_tracked` writes.
pub const AUTO_REL: &str = "code/engine/_generated/auto_tracked.dm";

/// Names a generated setter must never shadow: the macro parameter and DM keywords.
const RESERVED: &[&str] = &["value", "src", "usr", "null", "world"];

/// Suffix of a `set_calls` entry that records a list mutator call (`add_V(`, `remove_V(`, `set_V_at(`, ...) instead of `set_V(`.
/// The file `gens::tracked_lists` writes: the list mutators it declares are the generator's own, not a clash.
const TRACKED_LISTS_REL: &str = "code/engine/_generated/tracked_lists.dm";

const LIST_CALL: &str = "[]";

/// The var names `V` of every call `set_V(...)` in the tree (a definition, `proc/set_V(` or a type-path `/t/set_V(` at column 0, is not a call).
pub fn set_calls(tree: &Tree) -> Arc<BTreeSet<String>> {
    tree.memo("gen/auto-set-calls", || {
        let files = tree.select(&CODE_DM);
        let facts: Vec<Vec<String>> = crate::incr::facts("auto-tracked-set-calls", &files, |f| {
            let mut out: Vec<String> = Vec::new();
            if f.rel == AUTO_REL || !f.text().contains("set_") {
                return out;
            }
            let call = crate::pat!(r"(?:^|[^\w/])set_(\w+)\s*\(");
            let list_call = crate::pat!(r"(?:^|[^\w/])(?:(?:add|include|remove|clear|insert|swap|cut)_(\w+)|set_(\w+)_at)\s*\(");
            for line in f.code().text.lines() {
                if !line.starts_with(char::is_whitespace) || line.contains("proc/set_") || line.trim_start().starts_with('#') {
                    continue;
                }
                for m in call.captures_iter(line) {
                    out.push(m.s(1).to_string());
                }
                for m in list_call.captures_iter(line) {
                    let v = if m.s(1).is_empty() { m.s(2) } else { m.s(1) };
                    out.push(format!("{}{}", v, LIST_CALL));
                }
            }
            out.sort();
            out.dedup();
            out
        });
        facts.into_iter().flatten().collect()
    })
}

/// Whether a declaration a person wrote already makes `owner.var` reactive.
fn declared_reactive(eng: &ReadsEngine, owner: &str, var: &str) -> bool {
    let mut cur = Some(owner.to_string());
    let mut guard = 0;
    while let Some(t) = cur {
        if eng.decls.tracked_explicit.get(&t).map(|s| s.contains(var)).unwrap_or(false) {
            return true;
        }
        guard += 1;
        if guard > 64 {
            break;
        }
        cur = eng.sem.parent_of(&t).filter(|p| p != &t && p != "/");
    }
    eng.is_relation(owner, var) || eng.is_stat(owner, var) || eng.is_derived(owner, var)
}

/// The var names some proc writes, not counting a setter's write of its own var (`set_v` writing `v`: the TRACKED() macro's body, and the one line of
/// every hand-written setter): a var written only there is written by nobody who could be asked to publish.
pub fn writes_outside_setters(sem: &crate::sem::Sem) -> HashSet<String> {
    let procs: Vec<dreammaker::objtree::ProcRef> = sem.objtree.iter_types().flat_map(|t| t.iter_self_procs().collect::<Vec<_>>()).filter(|p| !p.is_builtin()).collect();
    let sets: Vec<HashSet<String>> = crate::sem::par_map(&procs, |p| {
        let mut w = crate::sem::reads::proc_writes(*p);
        if let Some(v) = p.name().strip_prefix("set_") {
            w.remove(v);
        }
        w
    });
    sets.into_iter().flatten().collect()
}

/// A read the inference tracks: no declaration makes it reactive, it is not constant, and something writes it.
pub fn candidate(eng: &ReadsEngine, written: &HashSet<String>, calls: &BTreeSet<String>, owner: &str, var: &str) -> bool {
    if declared_reactive(eng, owner, var) {
        return false;
    }
    if eng.sem.var_decl(owner, var).map(|v| v.is_const).unwrap_or(false) {
        return false;
    }
    if written.contains(var) || calls.contains(var) {
        return true;
    }
    // A list is written through its generated mutators once `analyze fix` has rewritten the raw edits.
    calls.contains(&format!("{}{}", var, LIST_CALL)) && eng.sem.var_decl(owner, var).map(|v| v.is_list()).unwrap_or(false)
}

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

/// Every `set_*` proc defined outside the generated file, by name: the types that define it.
pub fn setter_defs(sem: &crate::sem::Sem) -> HashMap<String, Vec<String>> {
    let mut out: HashMap<String, Vec<String>> = HashMap::new();
    for t in sem.objtree.iter_types() {
        let path = if t.get().path.is_empty() { "/".to_string() } else { t.get().path.clone() };
        for (name, p) in &t.get().procs {
            if !["set_", "add_", "include_", "remove_", "clear_", "insert_", "swap_", "cut_"].iter().any(|p| name.starts_with(p)) {
                continue;
            }
            if p.value.iter().any(|v| sem.file_of(v.location) != Some(AUTO_REL) && sem.file_of(v.location) != Some(TRACKED_LISTS_REL)) {
                out.entry(name.clone()).or_default().push(path.clone());
            }
        }
    }
    out
}

/// The vars of `candidates` the generator can give a setter, and the ones it cannot (with why).
pub fn decide(sem: &crate::sem::Sem, candidates: &BTreeSet<(String, String)>, exclude: &[String]) -> AutoSet {
    let defs = setter_defs(sem);
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
            if crate::sem::reads::ENGINE_DIRS.iter().any(|d| sig.file.starts_with(d)) {
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
            // The declaring type: a read through a subtype of it names the same var.
            if sem.var_owner(owner, var).as_deref() != Some(owner.as_str()) {
                return why("declared on another type");
            }
            let name = format!("set_{}", var);
            if let Some(types) = defs.get(&name) {
                if let Some(t) = types.iter().find(|t| sem.is_subtype(t, owner) || sem.is_subtype(owner, t)) {
                    return Some(format!("{} already defines {}()", t, name));
                }
            }
            if sig.is_list() {
                for gen in [format!("add_{var}"), format!("include_{var}"), format!("remove_{var}"), format!("set_{var}_at"), format!("clear_{var}"), format!("insert_{var}"), format!("swap_{var}"), format!("cut_{var}")] {
                    if let Some(t) = defs.get(&gen).and_then(|types| types.iter().find(|t| sem.is_subtype(t, owner) || sem.is_subtype(owner, t))) {
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

/// The inference for a tree (memoized: the generator, the lints and `analyze fix` share it).
pub fn inferred(tree: &Tree) -> Arc<Option<AutoSet>> {
    tree.memo("gen/auto-tracked", || {
        let an = super::deps::analyzed(tree);
        let an = an.as_ref().as_ref()?;
        let sem = crate::sem::sem_for(tree)?;
        let scopes = crate::scopes::Scopes::load(&tree.root.join("tools/ci/lint_scopes.toml")).unwrap_or_default();
        let scope = scopes.for_lint("auto_tracked", "");
        let exclude: Vec<String> = scope.list("exclude").iter().chain(scope.list("exclude_fixtures")).chain(scope.list("exclude_heat")).cloned().collect();
        Some(decide(&sem, &an.candidates, &exclude))
    })
}

struct AutoTracked;

impl Generator for AutoTracked {
    fn name(&self) -> &'static str {
        "auto_tracked"
    }

    fn stage(&self) -> u8 {
        0
    }

    fn output(&self) -> &'static str {
        "auto_tracked.dm"
    }

    fn generate(&self, cx: &GenCx, out: &mut GenOut) {
        out.doc("Read-driven tracking: the vars reactive code reads that no declaration makes tracked, written as the TRACKED() their author would have");
        out.doc("declared (tools/analyze/src/gens/auto_tracked.rs, doc/rewrite/final_api.html section 7). Write them only through set_<var>();");
        out.doc("the `tracked` lint holds every write to that and `analyze fix` rewrites it.");
        let inf = inferred(cx.tree);
        let Some(set) = inf.as_ref().as_ref() else {
            out.diag("deepquarry.dme", 1, "the semantic model could not be built; read-driven tracking cannot be generated");
            return;
        };
        if std::env::var("DQ_AUTO_REPORT").is_ok() {
            eprintln!("auto_tracked: {} tracked ({} lists), {} blocked", set.tracked.len(), set.tracked.iter().filter(|a| a.list).count(), set.blocked.len());
            for (t, v, why) in &set.blocked {
                eprintln!("auto_tracked: blocked {}.{}: {}", t, v, why);
            }
        }
        let tests = crate::sem::gen::test_only_types(cx.tree);
        let (test, content): (Vec<&Auto>, Vec<&Auto>) = set.tracked.iter().partition(|a| tests.contains(&a.ty));
        for a in &content {
            out.line(format!("TRACKED({}, {})", a.ty, a.var));
        }
        if !test.is_empty() {
            out.line(crate::sem::gen::TEST_GUARD);
            for a in &test {
                out.line(format!("TRACKED({}, {})", a.ty, a.var));
            }
            out.line("#endif");
        }
    }
}

pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(AutoTracked));
}
