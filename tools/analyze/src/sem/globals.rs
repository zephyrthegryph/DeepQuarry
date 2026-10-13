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

use dreammaker::ast::{Expression, Follow, Statement, Term};

use super::ast::walk_block;
use super::Sem;

/// The lifecycle procs of a system and a controller: the kernel calls them once, while the world boots.
const BOOT_PROCS: &[&str] = &["New", "preinit", "initialize", "Initialize", "on_members_ready", "kernel_members_ready", "OnConfigLoad"];

/// Procs that run once before the first map load by the engine's own contract, though a late atom may call them as a fallback
/// (`static_entries_ensure`, `static_entries_setup_early`): both are guarded by `ready`.
const BOOT_ONCE: &[&str] = &["static_entries_build"];

/// Calls that change the list they are called on.
const LIST_MUTATORS: &[&str] = &["Add", "Cut", "Remove", "Insert", "Swap", "Splice"];

/// Calls that change their first argument in place.
const ARG_MUTATORS: &[&str] = &["sortTim", "shuffle", "reverse_range"];

/// The names a `PROC_REF` family macro takes.
const REF_MACROS: &[&str] = &["PROC_REF", "TYPE_PROC_REF", "GLOBAL_PROC_REF"];

type Node = (String, String);

#[derive(Default)]
pub struct GlobalIndex {
    /// Global vars (`GLOB.x` as `x`, a real global as its name) written by a proc that is not boot-only.
    runtime_written: HashSet<String>,
    /// Every global var that is written anywhere.
    written: HashSet<String>,
    /// How many procs the boot set holds (for the report).
    pub boot_procs: usize,
}

impl GlobalIndex {
    /// True when `var` (a `GLOB` field or a real global) is never changed after the world booted.
    pub fn constant_after_init(&self, var: &str) -> bool {
        !self.runtime_written.contains(var)
    }

    pub fn is_written(&self, var: &str) -> bool {
        self.written.contains(var)
    }

    pub fn build(sem: &Sem) -> GlobalIndex {
        let mut nodes: Vec<(Node, Facts)> = Vec::new();
        let global_vars: HashSet<String> = sem.objtree.root().get().vars.iter().filter(|(_, v)| v.declaration.is_some()).map(|(n, _)| n.clone()).collect();
        let glob_fields: HashSet<String> = sem.ty("/datum/controller/global_vars").map(|t| t.get().vars.iter().filter(|(_, v)| v.declaration.is_some()).map(|(n, _)| n.clone()).collect()).unwrap_or_default();
        for t in sem.objtree.iter_types() {
            let path = if t.get().path.is_empty() { "/".to_string() } else { t.get().path.clone() };
            for p in t.iter_self_procs() {
                if p.is_builtin() {
                    continue;
                }
                let Some(code) = &p.get().code else { continue };
                let mut facts = Facts::default();
                let locals: HashSet<String> = p.get().parameters.iter().map(|x| x.name.clone()).collect();
                scan(code, &locals, &global_vars, &glob_fields, &mut facts);
                nodes.push(((path.clone(), p.name().to_string()), facts));
            }
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
        }
        out
    }
}

#[derive(Default)]
struct Facts {
    /// Names this body can call (`f()`, `x.f()`, `..()` as the proc's own name is not known here, so parent calls are skipped).
    calls: HashSet<String>,
    /// Names a PROC_REF-family macro or a CALLBACK takes.
    refs: HashSet<String>,
    /// Global vars written.
    writes: HashSet<String>,
}

/// The global var an lvalue-ish expression names: `GLOB.x` (+ index steps) or a real global `x` (+ index steps), and whether anything but
/// index steps follows it.
fn global_of(term: &dreammaker::ast::Spanned<Term>, follow: &[dreammaker::ast::Spanned<Follow>], globals: &HashSet<String>, glob_fields: &HashSet<String>, locals: &HashSet<String>) -> Option<(String, usize)> {
    let Term::Ident(n) = &term.elem else { return None };
    if n == "GLOB" {
        let Some(Follow::Field(_, f)) = follow.first().map(|f| &f.elem) else { return None };
        if !glob_fields.contains(f.as_str()) {
            return None;
        }
        return Some((f.as_str().to_string(), 1));
    }
    if locals.contains(n) || !globals.contains(n) {
        return None;
    }
    Some((n.clone(), 0))
}

fn only_index(follow: &[dreammaker::ast::Spanned<Follow>]) -> bool {
    follow.iter().all(|f| matches!(&f.elem, Follow::Index(..)) || matches!(&f.elem, Follow::Field(_, n) if n.as_str() == "len"))
}

fn scan(code: &dreammaker::ast::Block, params: &HashSet<String>, globals: &HashSet<String>, glob_fields: &HashSet<String>, f: &mut Facts) {
    let mut locals = params.clone();
    collect_locals(code, &mut locals);
    walk_block(code, &mut |e, _| {
        match e {
            Expression::AssignOp { lhs, .. } => {
                if let Expression::Base { term, follow } = &**lhs {
                    if let Some((g, skip)) = global_of(term, follow, globals, glob_fields, &locals) {
                        if only_index(&follow[skip..]) {
                            f.writes.insert(g);
                        }
                    }
                }
            }
            Expression::Base { term, follow } => {
                if let Term::Call(n, args) = &term.elem {
                    f.calls.insert(n.as_str().to_string());
                    if REF_MACROS.contains(&n.as_str()) {
                        if let Some(Expression::Base { term: t, follow: fo }) = args.last() {
                            if let (Term::Ident(r), true) = (&t.elem, fo.is_empty()) {
                                f.refs.insert(r.clone());
                            }
                        }
                    }
                    if ARG_MUTATORS.contains(&n.as_str()) {
                        if let Some(Expression::Base { term: t, follow: fo }) = args.first() {
                            if let Some((g, skip)) = global_of(t, fo, globals, glob_fields, &locals) {
                                if only_index(&fo[skip..]) {
                                    f.writes.insert(g);
                                }
                            }
                        }
                    }
                }
                if matches!(term.elem, Term::NewImplicit { .. } | Term::NewPrefab { .. } | Term::NewMiniExpr { .. }) {
                    f.calls.insert("New".to_string());
                }
                if let Term::GlobalCall(n, _) = &term.elem {
                    f.calls.insert(n.as_str().to_string());
                }
                let mut i = 0;
                for fo in follow.iter() {
                    if let Follow::Call(_, name, _) = &fo.elem {
                        f.calls.insert(name.as_str().to_string());
                        if LIST_MUTATORS.contains(&name.as_str()) {
                            if let Some((g, skip)) = global_of(term, &follow[..i], globals, glob_fields, &locals) {
                                if i >= skip && only_index(&follow[skip..i]) {
                                    f.writes.insert(g);
                                }
                            }
                        }
                    }
                    if let Follow::ProcReference(name) = &fo.elem {
                        f.refs.insert(name.as_str().to_string());
                    }
                    if let Follow::Unary(op) = &fo.elem {
                        use dreammaker::ast::UnaryOp::*;
                        if matches!(op, PreIncr | PostIncr | PreDecr | PostDecr) {
                            if let Some((g, skip)) = global_of(term, &follow[..i], globals, glob_fields, &locals) {
                                if i >= skip && only_index(&follow[skip..i]) {
                                    f.writes.insert(g);
                                }
                            }
                        }
                    }
                    i += 1;
                }
            }
            _ => {}
        }
    });
}

/// The names `var/x` declares in a body: a local shadows a global of the same name.
fn collect_locals(code: &dreammaker::ast::Block, out: &mut HashSet<String>) {
    for st in code.iter() {
        match &st.elem {
            Statement::Var(v) => {
                out.insert(v.name.clone());
            }
            Statement::Vars(list) => {
                for v in list {
                    out.insert(v.name.clone());
                }
            }
            Statement::ForList(fl) => {
                out.insert(fl.name.as_str().to_string());
            }
            Statement::ForKeyValue(fk) => {
                out.insert(fk.key.as_str().to_string());
                out.insert(fk.value.as_str().to_string());
            }
            Statement::ForRange(fr) => {
                out.insert(fr.name.as_str().to_string());
            }
            _ => {}
        }
        for b in super::ast::stmt_blocks(&st.elem) {
            collect_locals(b, out);
        }
    }
}
