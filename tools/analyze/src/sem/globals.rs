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

use std::collections::HashSet;

use dreammaker::ast::{Expression, Follow, Statement, Term};

use super::ast::walk_block;
use super::Sem;

pub use crate::global_policy::GlobalIndex;
use crate::global_policy::{Node,Facts,LIST_MUTATORS,ARG_MUTATORS,REF_MACROS};
impl GlobalIndex {
    pub fn build(sem: &Sem) -> GlobalIndex {
                let global_vars: HashSet<String> = sem.objtree.root().get().vars.iter().filter(|(_, v)| v.declaration.is_some()).map(|(n, _)| n.clone()).collect();
        let glob_fields: HashSet<String> = sem.ty("/datum/controller/global_vars").map(|t| t.get().vars.iter().filter(|(_, v)| v.declaration.is_some()).map(|(n, _)| n.clone()).collect()).unwrap_or_default();
        // Every body is scanned on its own: on all cores, kept in definition order.
        let mut procs: Vec<(String, dreammaker::objtree::ProcRef)> = Vec::new();
        for t in sem.objtree.iter_types() {
            let path = if t.get().path.is_empty() { "/".to_string() } else { t.get().path.clone() };
            for p in t.iter_self_procs() {
                if p.is_builtin() {
                    continue;
                }
                // Test code is compiled out of production: it neither writes state nor calls a proc the world could run.
                if super::reads::is_test_code(sem.rel(p.get().location)) {
                    continue;
                }
                if !p.get().code.has_body() {
                    continue;
                }
                procs.push((path.clone(), p));
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
        let refs: Vec<dreammaker::objtree::ProcRef> = procs.iter().map(|(_, p)| *p).collect();
        super::body_facts::indexed(sem, "globals", ctx, &refs, |p| {
            let mut facts = Facts::default();
            let locals: HashSet<String> = p.get().parameters.iter().map(|x| x.name.clone()).collect();
            if let Some(code) = &*p.get().code {
                scan(code, &locals, &global_vars, &glob_fields, &mut facts);
            }
            facts
        }, |scanned: Vec<Facts>| {
            let mut nodes: Vec<(Node, Facts)> = Vec::new();
            for ((path, p), facts) in procs.iter().zip(scanned) {
                nodes.push(((path.clone(), p.name().to_string()), facts));
            }
            GlobalIndex::from_facts(&nodes,|owner|sem.is_subtype(owner,"/datum/system")||sem.is_subtype(owner,"/datum/world_service")||sem.is_subtype(owner,"/datum/controller"))
        })
    }
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

/// Records the var name an lvalue-ish expression writes (a bare identifier that is a local or parameter is not a var).
fn note_field(term: &dreammaker::ast::Spanned<Term>, follow: &[dreammaker::ast::Spanned<Follow>], locals: &HashSet<String>, f: &mut Facts) {
    let Some(name) = super::reads::lvalue_name_of(term, follow) else { return };
    let bare = !follow.iter().any(|x| matches!(&x.elem, Follow::Field(..)));
    if bare && locals.contains(&name) {
        return;
    }
    f.field_writes.insert(name);
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
                    note_field(term, follow, &locals, f);
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
                            note_field(t, fo, &locals, f);
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
                            note_field(term, &follow[..i], &locals, f);
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
                            note_field(term, &follow[..i], &locals, f);
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
