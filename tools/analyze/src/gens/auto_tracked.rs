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
use dreammaker::ast::{Expression, Follow, Term};

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
            if f.rel == AUTO_REL || !SETTER_PREFIXES.iter().any(|p| f.text().contains(p)) {
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
    // The generated setters and list mutators write the vars they are generated for: counting them would keep a var tracked because it was tracked.
    let procs: Vec<dreammaker::objtree::ProcRef> = sem.objtree.iter_types().flat_map(|t| t.iter_self_procs().collect::<Vec<_>>()).filter(|p| !p.is_builtin() && !matches!(sem.file_of(p.get().location), Some(AUTO_REL) | Some(TRACKED_LISTS_REL))).collect();
    let sets: Vec<HashSet<String>> = crate::sem::par_map(&procs, |p| {
        let mut w = crate::sem::reads::proc_writes(*p);
        if let Some(v) = p.name().strip_prefix("set_") {
            w.remove(v);
        }
        w
    });
    sets.into_iter().flatten().collect()
}

/// `writes_outside_setters`, computed once per tree.
pub fn writes_outside_setters_of(tree: &Tree, sem: &crate::sem::Sem) -> Arc<HashSet<String>> {
    tree.memo("gen/writes-outside-setters", || writes_outside_setters(sem))
}

/// A var named in a CAPABILITIES block: tracked unless a declaration already makes it reactive, or it is constant.
pub fn named_candidate(eng: &ReadsEngine, owner: &str, var: &str) -> bool {
    !declared_reactive(eng, owner, var) && !eng.sem.var_decl(owner, var).map(|v| v.is_const).unwrap_or(false)
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

/// The `(declaring type, var)` pairs a `set_v(` / `add_v(` call in the tree names, whether or not reactive code reads them: the transition set.
/// A var is tracked when something reads it (`candidate` over the read set) or when it is written through its setter. The second kind is what the
/// dropped `TRACKED(T, v)` lines become: a var nobody walked reads is still published for what asks at run time (`on_change`, a Life step's
/// `woken_by`, an observer, a VV edit), and the calls `analyze fix` wrote have to keep compiling when the last static reader goes. Only the
/// declaring type of a var is a candidate (a subtype reads the same var), and `decide` drops the ones a hand-written `set_v` already covers.
pub fn called_candidates(tree: &Tree, sem: &crate::sem::Sem, eng: &ReadsEngine, written: &HashSet<String>, calls: &BTreeSet<String>) -> BTreeSet<(String, String)> {
    let defs = setter_defs(tree, sem);
    let mut out = BTreeSet::new();
    for t in sem.objtree.iter_types() {
        let path = if t.get().path.is_empty() { "/".to_string() } else { t.get().path.clone() };
        for (name, v) in &t.get().vars {
            if v.declaration.is_none() {
                continue;
            }
            if let Ok(want) = std::env::var("DQ_AUTO_DEBUG") {
                if *name == want {
                    eprintln!("auto_tracked debug typed: {:?} calls: {} {}", typed_set_calls(tree).get(&format!("remove_{want}")).or(typed_set_calls(tree).get(&format!("add_{want}"))), calls.contains(want.as_str()), calls.contains(&format!("{want}[]")));
                    eprintln!("auto_tracked debug: {}.{} called_here={} candidate={} declared_reactive={}", path, name, called_here(tree, sem, &defs, calls, &path, name), candidate(eng, written, calls, &path, name), declared_reactive(eng, &path, name));
                }
            }
            if called_here(tree, sem, &defs, calls, &path, name) && candidate(eng, written, calls, &path, name) {
                out.insert((path.clone(), name.clone()));
            }
        }
    }
    out
}

/// The receiver of a setter-shaped call that `typed_set_calls` could not type.
pub const UNTYPED: &str = "?";

/// Whether some call of `set_v` / a list mutator of `v` has a receiver the scan could not type: it may be this var's setter, whatever the typed calls say.
pub fn untyped_call(tree: &Tree, var: &str) -> bool {
    let typed = typed_set_calls(tree);
    setter_names(var).iter().any(|n| typed.get(n).is_some_and(|t| t.contains(UNTYPED)))
}

fn setter_names(var: &str) -> [String; 9] {
    [format!("set_{var}"), format!("add_{var}"), format!("include_{var}"), format!("remove_{var}"), format!("set_{var}_at"), format!("clear_{var}"), format!("insert_{var}"), format!("swap_{var}"), format!("cut_{var}")]
}

const SETTER_PREFIXES: &[&str] = &["set_", "add_", "include_", "remove_", "clear_", "insert_", "swap_", "cut_"];

/// The static type of each receiver of a setter-shaped call (`set_*`, `add_*`, ... ) in the tree, by call name: an unqualified call and `src.` are the
/// proc's own type, `X.set_v()` is the declared type of the proc's parameter or local `X`, or of the var `X` of the proc's type, followed through
/// `a.b.c` field hops. A receiver it cannot type is not recorded. Names are flat per proc (the last declaration of a name wins).
pub fn typed_set_calls(tree: &Tree) -> Arc<HashMap<String, BTreeSet<String>>> {
    tree.memo("gen/typed-set-calls", || {
        let mut out: HashMap<String, BTreeSet<String>> = HashMap::new();
        let Some(sem) = crate::sem::sem_for(tree) else { return out };
        let mut work: Vec<(String, dreammaker::objtree::ProcRef)> = Vec::new();
        for t in sem.objtree.iter_types() {
            let path = if t.get().path.is_empty() { "/".to_string() } else { t.get().path.clone() };
            for p in t.iter_self_procs() {
                if p.is_builtin() {
                    continue;
                }
                let rel = p.get().location;
                if matches!(sem.file_of(rel), Some(AUTO_REL) | Some(TRACKED_LISTS_REL)) {
                    continue;
                }
                work.push((path.clone(), p));
            }
        }
        let found: Vec<Vec<(String, String)>> = crate::sem::par_map(&work, |(owner, p)| {
            let mut hits: Vec<(String, String)> = Vec::new();
            let Some(code) = &p.get().code else { return hits };
            let mut locals: HashMap<String, String> = HashMap::new();
            for prm in p.get().parameters.iter() {
                if !prm.var_type.type_path.is_empty() {
                    locals.insert(prm.name.clone(), format!("/{}", prm.var_type.type_path.join("/")));
                }
            }
            collect_local_types(code, &mut locals);
            let is_call = |n: &str| SETTER_PREFIXES.iter().any(|p| n.starts_with(p));
            crate::sem::ast::walk_block(code, &mut |e, _| {
                let Expression::Base { term, follow } = e else { return };
                let mut cur: Option<String> = match &term.elem {
                    Term::Ident(n) if n.as_str() == "src" => Some(owner.clone()),
                    Term::Ident(n) => locals.get(n).cloned().or_else(|| sem.var_decl(owner, n).map(|v| v.declared).filter(|d| !d.is_empty())),
                    Term::Call(n, _) => {
                        if is_call(n) {
                            hits.push((n.as_str().to_string(), owner.clone()));
                        }
                        None
                    }
                    _ => None,
                };
                for fo in follow.iter() {
                    match &fo.elem {
                        Follow::Field(_, n) => cur = cur.and_then(|c| sem.var_decl(&c, n.as_str())).map(|v| v.declared).filter(|d| !d.is_empty()),
                        Follow::Call(_, n, _) => {
                            if is_call(n.as_str()) {
                                hits.push((n.as_str().to_string(), cur.clone().unwrap_or_else(|| UNTYPED.to_string())));
                            }
                            cur = None;
                        }
                        _ => cur = None,
                    }
                }
            });
            hits
        });
        for (n, t) in found.into_iter().flatten() {
            out.entry(n).or_default().insert(t);
        }
        out
    })
}

fn collect_local_types(b: &dreammaker::ast::Block, out: &mut HashMap<String, String>) {
    use dreammaker::ast::Statement;
    for st in b.iter() {
        match &st.elem {
            Statement::Var(vs) if !vs.var_type.type_path.is_empty() => {
                out.insert(vs.name.clone(), format!("/{}", vs.var_type.type_path.join("/")));
            }
            Statement::Vars(list) => {
                for vs in list.iter().filter(|v| !v.var_type.type_path.is_empty()) {
                    out.insert(vs.name.clone(), format!("/{}", vs.var_type.type_path.join("/")));
                }
            }
            Statement::ForList(fl) => {
                if let Some(vt) = fl.var_type.as_ref().filter(|v| !v.type_path.is_empty()) {
                    out.insert(fl.name.as_str().to_string(), format!("/{}", vt.type_path.join("/")));
                }
            }
            _ => {}
        }
        for nb in crate::sem::ast::stmt_blocks(&st.elem) {
            collect_local_types(nb, out);
        }
    }
}

/// Whether a `set_v(` / `add_v(` call in the tree can be a call of `owner.v`'s setter. The calls are collected by name, so a name another type owns a
/// hand-written setter for (`set_active`, `set_id`) says nothing about this var by itself. Calls with a typed receiver decide it when there are any
/// (`typed_set_calls`: a type related to `owner` receives one); when none is typed, the name is enough if every non-generated definition of `set_v` /
/// its list mutators is on a type related to `owner`.
pub fn called_here(tree: &Tree, sem: &crate::sem::Sem, defs: &HashMap<String, Vec<String>>, calls: &BTreeSet<String>, owner: &str, var: &str) -> bool {
    let plain = calls.contains(var);
    let list = calls.contains(&format!("{}{}", var, LIST_CALL));
    if !plain && !list {
        return false;
    }
    let names = setter_names(var);
    let related = |t: &String| sem.is_subtype(t, owner) || sem.is_subtype(owner, t);
    // A call whose receiver has a static type speaks for that type only: `locked` is declared on forty types, and a typed
    // `door.set_locked()` says nothing about the other thirty-nine.
    let typed = typed_set_calls(tree);
    let typed_for: Vec<&BTreeSet<String>> = names.iter().filter_map(|n| typed.get(n)).collect();
    if !typed_for.is_empty() {
        return typed_for.iter().any(|types| types.iter().any(related));
    }
    // Only calls whose receiver could not be typed name it: the name is enough when no unrelated type owns a hand-written proc of it.
    names.iter().all(|n| defs.get(n).is_none_or(|types| types.iter().all(related)))
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

/// Whether a proc definition at `loc` is the expansion of a `TRACKED(T, v)` line (the macro writes `set_v` at the line of its invocation): that is
/// the declaration the generator replaces, not a hand-written proc it would clash with.
fn from_tracked_macro(tree: &Tree, sem: &crate::sem::Sem, loc: dreammaker::Location) -> bool {
    let Some(rel) = sem.file_of(loc) else { return false };
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
            if p.declaration.is_some() && p.value.iter().any(|v| sem.file_of(v.location) != Some(AUTO_REL) && sem.file_of(v.location) != Some(TRACKED_LISTS_REL) && !from_tracked_macro(tree, sem, v.location)) {
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

/// The inference for a tree (memoized: the generator, the lints and `analyze fix` share it).
pub fn inferred(tree: &Tree) -> Arc<Option<AutoSet>> {
    tree.memo("gen/auto-tracked", || {
        let an = super::deps::analyzed(tree);
        let an = an.as_ref().as_ref()?;
        let sem = crate::sem::sem_for(tree)?;
        let scopes = crate::scopes::Scopes::load(&tree.root.join("tools/ci/lint_scopes.toml")).unwrap_or_default();
        let scope = scopes.for_lint("auto_tracked", "");
        let exclude: Vec<String> = scope.list("exclude").iter().chain(scope.list("exclude_fixtures")).chain(scope.list("exclude_heat")).chain(scope.list("exclude_memo")).cloned().collect();
        // Vars whose setter calls reach them through an accessor the call scan cannot type (`connected().set_locked(...)`): named by hand.
        let mut candidates = an.candidates.clone();
        for entry in scope.list("include") {
            if let Some((ty, var)) = entry.split_once("::") {
                candidates.insert((ty.to_string(), var.to_string()));
            }
        }
        Some(decide(tree, &sem, &candidates, &exclude))
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
