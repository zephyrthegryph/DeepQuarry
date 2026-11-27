//! Which global vars change after boot.
//!
//! The reads walk follows a global proc like any other proc. What it finds inside is a read of global state (`GLOB.x`, a real global var,
//! a var of a global singleton such as `SSair.x`), and global state is not an entity the runtime can subscribe to. The walk therefore asks
//! one question of each global var it meets: is it written only while the world boots? A var that is written only by code that runs before
//! the first round (the `InitGlobal<X>` initializer, a system's `New`/`preinit`/`initialize`, the static-entry build) and by procs that
//! only such code calls is constant after init and reads like a constant. Any other global var is dynamic state: reactive code that reads
//! it has an input nothing publishes, until the state moves into a system's tracked vars.
//!
//! The proof is a call graph over proc *names* (a call `x.f()` or `f()` may run any proc named `f`, so the graph is an over-approximation of
//! who calls what), seeded with the boot roots:
//!
//! 1. the nodes are `(owner type, proc)`; an edge goes from every proc to every proc a call in its body can name; `new` is a call of `New`;
//! 2. a proc named by `PROC_REF`/`TYPE_PROC_REF`/`GLOBAL_PROC_REF` or by `CALLBACK` runs when something else decides, so it is never boot-only;
//! 3. the boot set starts as everything the roots reach, then loses every non-root proc that some proc outside the set can call, until nothing
//!    changes. What is left runs only from boot code.
//!
//! A global var is **constant after init** when every proc that writes it (assigns it, indexes into it, calls a mutating list proc on it) is in
//! the boot set, or when the declaration is `const`. The write test is on the expression `GLOB.x` / `x`, not on aliases: a list handed to a
//! proc that mutates it is not seen (the same limit the per-var write index has).

use std::collections::{HashMap, HashSet};

use dm_syntax::{Expr, Statement};

use super::Sem;
use crate::model::expr::{chain, literal, Args, Chain, Form, Hop, Lit, Root};
use crate::model::procs::Proc;
use crate::model::walk::{stmt_blocks, stmts, Stmt};

/// The lifecycle procs of a system and a controller: the kernel calls them once, while the world boots.
const BOOT_PROCS: &[&str] = &["New", "preinit", "initialize", "Initialize", "on_members_ready", "kernel_members_ready", "OnConfigLoad"];

/// Procs that run once before the first map load by the engine's own contract, though a late atom may call them as a fallback
/// (`static_entries_ensure`, `static_entries_setup_early`): both are guarded by `ready`.
const BOOT_ONCE: &[&str] = &["static_entries_build"];

/// Calls that change the list they are called on.
const LIST_MUTATORS: &[&str] = &["Add", "Cut", "Remove", "Insert", "Swap", "Splice"];

/// Calls that change their first argument in place.
const ARG_MUTATORS: &[&str] = &["sortTim", "shuffle", "reverse_range"];

/// The relation layer's mutators (code/engine/declare/relations.dm) and which of their arguments name a var they write: `rel_add(E, nameof(E.v), x)`
/// changes `v` as an assignment would, so a relation list filled at run time is not constant after init (sem/reads.rs `global_field`).
const REL_MUTATORS: &[(&str, &[usize])] = &[
    ("rel_set", &[1]),
    ("rel_add", &[1]),
    ("rel_remove", &[1]),
    ("rel_clear", &[1]),
    ("rel_take", &[1]),
    ("rel_take_all", &[1]),
    ("rel_move", &[1, 3]),
    ("rel_link", &[1]),
    ("rel_unlink", &[1]),
];

/// The vars a relation mutator call writes: (the index of the holder argument, the var name, the type a `nameof(/type::v)` names).
pub(crate) fn rel_mutator_vars(name: &str, args: Args<'_>) -> Vec<(usize, String, Option<String>)> {
    let Some((_, slots)) = REL_MUTATORS.iter().find(|(m, _)| *m == name) else { return Vec::new() };
    slots.iter().filter_map(|&k| args.get(k).and_then(rel_var_arg).map(|(v, at)| (k - 1, v, at))).collect()
}

/// The var a relation mutator's name argument names: `nameof(v)`, `nameof(x.v)`, `nameof(/type::v)` (with the type) or a string literal.
fn rel_var_arg(e: &Expr) -> Option<(String, Option<String>)> {
    let c = chain(e)?;
    if !c.hops.is_empty() {
        return None;
    }
    match &c.root {
        Root::Literal(text) => match literal(text) {
            Lit::String(s) => Some((s, None)),
            _ => None,
        },
        Root::Call { name: "nameof", args } => {
            let first = chain(args.first()?)?;
            if let Some(f) = first.hops.last() {
                return match f {
                    Hop::Field { name, .. } => Some((name.to_string(), None)),
                    Hop::Static { name, .. } => {
                        let at = match &first.root {
                            Root::Prefab { path, .. } if first.hops.len() == 1 => Some(super::reads::prefab_text(path)),
                            _ => None,
                        };
                        Some((name.to_string(), at))
                    }
                    _ => None,
                };
            }
            match &first.root {
                Root::Ident(n) => Some((n.to_string(), None)),
                _ => None,
            }
        }
        _ => None,
    }
}

/// The per-tick procs of objects: what a machine, mob or processing object runs every tick it is processed.
const TICK_PROCS: &[&str] = &["process", "Life", "life_tick", "handle_life", "process_atmos", "process_cell"];

/// The names a `PROC_REF` family macro takes.
const REF_MACROS: &[&str] = &["PROC_REF", "TYPE_PROC_REF", "GLOBAL_PROC_REF"];

type Node = (String, String);

#[derive(Default, serde::Serialize, serde::Deserialize)]
pub struct GlobalIndex {
    /// Global vars (`GLOB.x` as `x`, a real global as its name) written by a proc that is not boot-only.
    runtime_written: HashSet<String>,
    /// Every global var that is written anywhere.
    written: HashSet<String>,
    /// Var names (of any object) written by a proc that is not boot-only: the name-based test for a var of a global singleton (`SSjob.x`,
    /// `using_map.x`). Test code is compiled out of production and does not count.
    runtime_field_written: HashSet<String>,
    /// Var names (of any object) written on a per-tick path: a system's own procs (its every() handlers run each kernel tick) and the per-tick
    /// procs of objects (TICK_PROCS). Name-based like `runtime_field_written`. A draw does not bind a global chain ending at one of these: every
    /// instance would redraw every tick (gens/reads.rs, the draw scope of a GlobalRead).
    #[serde(default)]
    tick_field_written: HashSet<String>,
    /// How many procs the boot set holds (for the report).
    pub boot_procs: usize,
}

impl GlobalIndex {
    /// A digest of the index (`walk_cache`).
    pub fn digest(&self) -> u128 {
        let mut h = blake3::Hasher::new();
        for set in [&self.runtime_written, &self.written, &self.runtime_field_written, &self.tick_field_written] {
            let mut v: Vec<&String> = set.iter().collect();
            v.sort();
            for x in v {
                h.update(x.as_bytes());
                h.update(b"\n");
            }
            h.update(b"|");
        }
        h.update(&self.boot_procs.to_le_bytes());
        u128::from_le_bytes(h.finalize().as_bytes()[..16].try_into().unwrap())
    }

    /// True when `var` (a `GLOB` field or a real global) is never changed after the world booted.
    pub fn constant_after_init(&self, var: &str) -> bool {
        !self.runtime_written.contains(var)
    }

    /// True when no proc outside the boot set writes a var of this name on any object: a var of a global singleton that only boot code fills reads
    /// like a constant. Name-based, so it over-approximates who writes (a same-named var elsewhere keeps it dynamic).
    pub fn field_constant_after_init(&self, var: &str) -> bool {
        !self.runtime_field_written.contains(var)
    }

    /// True when a per-tick path (a system's procs, an object's process()/Life()) writes a var of this name.
    pub fn field_written_per_tick(&self, var: &str) -> bool {
        self.tick_field_written.contains(var)
    }

    pub fn is_written(&self, var: &str) -> bool {
        self.written.contains(var)
    }

    pub fn build(sem: &Sem) -> GlobalIndex {
        let declared_vars = |t: crate::model::Ty<'_>| -> HashSet<String> { t.var_names().into_iter().filter(|n| t.declares_var(n)).collect() };
        let global_vars: HashSet<String> = sem.m().ty("/").map(declared_vars).unwrap_or_default();
        let glob_fields: HashSet<String> = sem.ty("/datum/controller/global_vars").map(declared_vars).unwrap_or_default();
        // Every body is scanned on its own: on all cores, kept in definition order.
        let mut procs: Vec<(String, Proc<'_>)> = Vec::new();
        for t in sem.m().types() {
            let path = t.path().to_string();
            for name in t.proc_names() {
                for p in t.proc_definitions(name) {
                    if p.is_builtin() {
                        continue;
                    }
                    // Test code is compiled out of production: it neither writes state nor calls a proc the world could run.
                    if super::reads::is_test_code(&sem.rel(p.site())) {
                        continue;
                    }
                    if p.body().is_none() {
                        continue;
                    }
                    procs.push((path.clone(), p));
                }
            }
        }
        // A scan reads the body and the global var names: kept per file between runs (`body_facts`).
        let ctx = {
            let mut g: Vec<&String> = global_vars.iter().collect();
            g.sort();
            let mut f: Vec<&String> = glob_fields.iter().collect();
            f.sort();
            let h = blake3::hash(format!("{:?}|{:?}", g, f).as_bytes());
            u128::from_le_bytes(h.as_bytes()[..16].try_into().unwrap())
        };
        let refs: Vec<Proc<'_>> = procs.iter().map(|(_, p)| *p).collect();
        super::body_facts::indexed(sem, "globals", ctx, &refs, |p| {
            let mut facts = Facts::default();
            let locals: HashSet<String> = p.parameters().iter().map(|x| x.name.clone()).collect();
            if let Some(code) = p.body() {
                scan(sem.m(), code, &locals, &global_vars, &glob_fields, &mut facts);
            }
            facts
        }, |scanned: Vec<Facts>| {
            let mut nodes: Vec<(Node, Facts)> = Vec::new();
            for ((path, p), facts) in procs.iter().zip(scanned) {
                nodes.push(((path.clone(), p.name().to_string()), facts));
            }
            // Who defines each name, and who calls it.
            let mut defined: HashMap<&str, Vec<usize>> = HashMap::new();
            for (i, (n, _)) in nodes.iter().enumerate() {
                defined.entry(n.1.as_str()).or_default().push(i);
            }
            let mut callers: HashMap<&str, Vec<usize>> = HashMap::new();
            let mut referenced: HashSet<&str> = HashSet::new();
            for (i, (_, f)) in nodes.iter().enumerate() {
                for c in &f.calls {
                    callers.entry(c.as_str()).or_default().push(i);
                }
                for r in &f.refs {
                    referenced.insert(r.as_str());
                }
            }
            let is_root = |n: &Node| -> bool {
                if n.0 == "/datum/controller/global_vars" && n.1.starts_with("InitGlobal") {
                    return true;
                }
                if n.0 == "/world" && n.1 == "New" {
                    return true;
                }
                if BOOT_ONCE.contains(&n.1.as_str()) && n.0 == "/" {
                    return true;
                }
                (sem.is_subtype(&n.0, "/datum/system") || sem.is_subtype(&n.0, "/datum/world_service") || sem.is_subtype(&n.0, "/datum/controller")) && BOOT_PROCS.contains(&n.1.as_str())
            };
            let roots: Vec<bool> = nodes.iter().map(|(n, _)| is_root(n)).collect();
            // What the roots reach.
            let mut boot = vec![false; nodes.len()];
            let mut stack: Vec<usize> = Vec::new();
            for (i, r) in roots.iter().enumerate() {
                if *r {
                    boot[i] = true;
                    stack.push(i);
                }
            }
            while let Some(i) = stack.pop() {
                for c in &nodes[i].1.calls {
                    for &d in defined.get(c.as_str()).map(|v| v.as_slice()).unwrap_or(&[]) {
                        if !boot[d] {
                            boot[d] = true;
                            stack.push(d);
                        }
                    }
                }
            }
            // Drop what something outside the set can also call, or what a callback names.
            loop {
                let mut changed = false;
                for i in 0..nodes.len() {
                    if !boot[i] || roots[i] {
                        continue;
                    }
                    let name = nodes[i].0 .1.as_str();
                    let outside = referenced.contains(name) || callers.get(name).map(|cs| cs.iter().any(|&c| !boot[c])).unwrap_or(false);
                    if outside {
                        boot[i] = false;
                        changed = true;
                    }
                }
                if !changed {
                    break;
                }
            }
            let mut out = GlobalIndex { boot_procs: boot.iter().filter(|b| **b).count(), ..Default::default() };
            for (i, (_, f)) in nodes.iter().enumerate() {
                for w in &f.writes {
                    out.written.insert(w.clone());
                    if !boot[i] {
                        out.runtime_written.insert(w.clone());
                    }
                }
                if !boot[i] {
                    out.runtime_field_written.extend(f.field_writes.iter().cloned());
                    let (ty, name) = &nodes[i].0;
                    if TICK_PROCS.contains(&name.as_str()) || sem.is_subtype(ty, "/datum/system") {
                        out.tick_field_written.extend(f.field_writes.iter().cloned());
                    }
                }
            }
            out
        })
    }
}

#[derive(Default, Clone, serde::Serialize, serde::Deserialize)]
struct Facts {
    // Ordered sets: `body_facts` digests them.
    /// Names this body can call (`f()`, `x.f()`, `..()` as the proc's own name is not known here, so parent calls are skipped).
    calls: std::collections::BTreeSet<String>,
    /// Names a PROC_REF-family macro or a CALLBACK takes.
    refs: std::collections::BTreeSet<String>,
    /// Global vars written.
    writes: std::collections::BTreeSet<String>,
    /// Names of vars written on any object (`x = ..`, `a.x = ..`, `a.x[i] = ..`, `a.x.Add(..)`, `a.x++`).
    field_writes: std::collections::BTreeSet<String>,
}

/// The global var an lvalue-ish expression names: `GLOB.x` (+ index steps) or a real global `x` (+ index steps), and whether anything but
/// index steps follows it. The expression is the chain's root and its first `n` hops.
fn global_of(c: &Chain<'_>, n: usize, globals: &HashSet<String>, glob_fields: &HashSet<String>, locals: &HashSet<String>) -> Option<(String, usize)> {
    let Root::Ident(id) = &c.root else { return None };
    if *id == "GLOB" {
        let Some(Hop::Field { name: f, .. }) = c.hops[..n].first() else { return None };
        if !glob_fields.contains(*f) {
            return None;
        }
        return Some((f.to_string(), 1));
    }
    if locals.contains(*id) || !globals.contains(*id) {
        return None;
    }
    Some((id.to_string(), 0))
}

/// Records the var name an lvalue-ish expression writes (a bare identifier that is a local or parameter is not a var). The expression is
/// the chain's root and its first `n` hops.
fn note_field(c: &Chain<'_>, n: usize, locals: &HashSet<String>, f: &mut Facts) {
    let Some(name) = super::reads::lvalue_name_of(c, n) else { return };
    let bare = !c.hops[..n].iter().any(|x| matches!(x, Hop::Field { .. }));
    if bare && locals.contains(&name) {
        return;
    }
    f.field_writes.insert(name);
}

fn only_index(hops: &[Hop<'_>]) -> bool {
    hops.iter().all(|f| matches!(f, Hop::Index { .. }) || matches!(f, Hop::Field { name: "len", .. }))
}

fn is_incr(op: &str) -> bool {
    matches!(op, "pre++" | "post++" | "pre--" | "post--")
}

fn scan<'m>(m: &'m crate::model::Model, code: &'m [Statement], params: &HashSet<String>, globals: &HashSet<String>, glob_fields: &HashSet<String>, f: &mut Facts) {
    let mut locals = params.clone();
    collect_locals(code, &mut locals);
    crate::model::walk::walk_block_in(m, code, &mut |v, _| {
        match &v.form {
            Form::Assign { lhs, .. } => {
                if let Some(c) = chain(lhs) {
                    let n = c.hops.len();
                    note_field(&c, n, &locals, f);
                    if let Some((g, skip)) = global_of(&c, n, globals, glob_fields, &locals) {
                        if only_index(&c.hops[skip..]) {
                            f.writes.insert(g);
                        }
                    }
                }
            }
            Form::Chain(c) => {
                if let Root::Call { name: n, args } = &c.root {
                    f.calls.insert(n.to_string());
                    if REF_MACROS.contains(n) {
                        if let Some(last) = args.iter().last().and_then(chain) {
                            if let (Root::Ident(r), true) = (&last.root, last.hops.is_empty()) {
                                f.refs.insert(r.to_string());
                            }
                        }
                    }
                    // A tracked setter writes its var (`set_v(x)` on src).
                    if let Some(v) = n.strip_prefix("set_").filter(|v| !v.is_empty()) {
                        f.field_writes.insert(v.to_string());
                    }
                    for (_, v, _) in rel_mutator_vars(n, *args) {
                        f.field_writes.insert(v);
                    }
                    if ARG_MUTATORS.contains(n) {
                        if let Some(first) = args.first().and_then(chain) {
                            let fo = first.hops.len();
                            note_field(&first, fo, &locals, f);
                            if let Some((g, skip)) = global_of(&first, fo, globals, glob_fields, &locals) {
                                if only_index(&first.hops[skip..]) {
                                    f.writes.insert(g);
                                }
                            }
                        }
                    }
                }
                if matches!(c.root, Root::NewImplicit { .. } | Root::NewPrefab { .. } | Root::NewMini { .. }) {
                    f.calls.insert("New".to_string());
                }
                for (i, h) in c.hops.iter().enumerate() {
                    if let Hop::Call { name, .. } = h {
                        f.calls.insert(name.to_string());
                        // `x.set_v(..)`: a tracked setter writes `v` on the receiver.
                        if let Some(v) = name.strip_prefix("set_").filter(|v| !v.is_empty()) {
                            f.field_writes.insert(v.to_string());
                        }
                        if LIST_MUTATORS.contains(name) {
                            note_field(c, i, &locals, f);
                            if let Some((g, skip)) = global_of(c, i, globals, glob_fields, &locals) {
                                if i >= skip && only_index(&c.hops[skip..i]) {
                                    f.writes.insert(g);
                                }
                            }
                        }
                    }
                    if let Hop::ProcRef { name, .. } = h {
                        f.refs.insert(name.to_string());
                    }
                    if let Hop::Unary { op, .. } = h {
                        if is_incr(op) {
                            note_field(c, i, &locals, f);
                            if let Some((g, skip)) = global_of(c, i, globals, glob_fields, &locals) {
                                if i >= skip && only_index(&c.hops[skip..i]) {
                                    f.writes.insert(g);
                                }
                            }
                        }
                    }
                }
            }
            _ => {}
        }
    });
}

/// The names `var/x` declares in a body: a local shadows a global of the same name.
fn collect_locals(code: &[Statement], out: &mut HashSet<String>) {
    for st in stmts(code) {
        match &st.stmt {
            Stmt::Vars(list) => {
                for v in list {
                    out.insert(v.name.clone());
                }
            }
            Stmt::ForList { binding, .. } => {
                out.insert(binding.name.clone());
            }
            Stmt::ForKeyValue { binding, value, .. } => {
                out.insert(binding.name.clone());
                out.insert(value.to_string());
            }
            Stmt::ForRange { binding, .. } => {
                out.insert(binding.name.clone());
            }
            _ => {}
        }
        for b in stmt_blocks(&st.stmt) {
            collect_locals(b, out);
        }
    }
}
