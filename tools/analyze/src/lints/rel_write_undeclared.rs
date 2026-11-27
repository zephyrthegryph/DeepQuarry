//! `rel_write_undeclared`: a `rel_*` write names a var that no relation declares
//! (doc/rewrite/proposals/relations.md, D1).
//!
//! `rel_set` / `rel_add` / `rel_remove` / `rel_clear` / `rel_take` / `rel_take_all` / `rel_move` dispatch on the var's declaration. A var with
//! none was silently learned as a plain `ref_one` at runtime; that is gone (`own_entry_of_kind()` reports it), so a written var is declared:
//! `ref_one` / `ref_many` / `owns_one` / `owns_many` / a `links()` end in the holder type's CAPABILITIES block, a `LIST_STATE`, or a
//! capability's own entry.
//!
//! The holder's type comes from the `nameof(x.var)` receiver when there is one, else from the first argument; a holder the model cannot
//! type is checked by the var name alone (the lint fails closed: a name no type declares is reported). A hard ban, no baseline.

use std::collections::HashSet;

use dm_syntax::{Expr, Statement};

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::lints::stored_refs::{collect_locals, path_of, relation_index, Kinds, ProcScope, Walker};
use crate::model::expr::{as_call, chain, form, strip_groups, Chain, Form, Hop, Root};
use crate::model::walk::{stmt_blocks, stmt_exprs, stmts, walk_block, ForInit, Stmt};
use crate::model::Site;
use crate::sem::procs::engine_line;
use crate::sem::Sem;
use crate::tree::CODE_DM;

const HINT: &str = "declare the var in the holder type's CAPABILITIES block: ref_one(nameof(v)) (a reference), owns_one/owns_many (an owned value), links(A::a, B::b) \
(a pair); a write to an undeclared var is a test failure. doc/rewrite/proposals/relations.md D1";

static META: Meta = Meta {
    name: "rel_write_undeclared",
    group: "",
    label: "rel_write_undeclared",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "undeclared", hint: HINT }],
    allow: &[],
    lists: &[],
};

struct RelWriteUndeclared;

/// The write verbs and the argument positions of their (holder, var) pairs.
fn verb_pairs(name: &str) -> &'static [(usize, usize)] {
    match name {
        "rel_set" | "rel_add" | "rel_remove" | "rel_clear" | "rel_take" | "rel_take_all" | "rel_private" | "rel_is_private" => &[(0, 1)],
        "rel_move" => &[(0, 1), (2, 3)],
        _ => &[],
    }
}

/// `nameof(x)` / `nameof(a.b.var)`: (receiver expression if dotted, var name).
fn nameof_arg(e: &Expr) -> Option<(Option<&Expr>, String)> {
    let e = strip_groups(e);
    let (name, args) = as_call(e)?;
    if name != "nameof" || args.len() != 1 {
        return None;
    }
    let inner = strip_groups(args.get(0)?);
    let c = chain(inner)?;
    match c.hops.last() {
        None => match &c.root {
            Root::Ident(v) => Some((None, v.to_string())),
            _ => None,
        },
        Some(last) => {
            let Hop::Field { name: v, .. } = last else { return None };
            Some((Some(c.prefix_node(c.hops.len() - 1)), v.to_string()))
        }
    }
}

impl Lint for RelWriteUndeclared {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let Some(sem) = cx.sem() else {
            out.note("rel_write_undeclared: the semantic model is unavailable; nothing checked");
            return;
        };
        let sem: &Sem = &sem;
        let rels = relation_index(cx);
        let kinds = Kinds { sem, exempt_types: Vec::new(), registry: Vec::new(), cache: Default::default() };
        let w = Walker { sem, kinds: &kinds };
        let root = &cx.tree.root;
        let mut seen: HashSet<(String, u32, String)> = HashSet::new();
        let mut found: Vec<(String, u32, String)> = Vec::new();
        for ty in sem.m().types() {
            let owner = ty.path().to_string();
            for pname in ty.proc_names() {
                for v in ty.proc_definitions(pname) {
                    let Some(code) = v.body() else { continue };
                    let Some(rel) = sem.file_of(v.site()) else { continue };
                    if cx.exempt(&rel) {
                        continue;
                    }
                    let mut locals = std::collections::HashMap::new();
                    for p in v.parameters().iter() {
                        locals.insert(p.name.to_string(), (path_of(&p.type_path), None));
                    }
                    collect_locals(code, &rel, &mut locals);
                    let sc = ProcScope { owner: &owner, locals };
                    walk_block(code, &mut |vis, site| {
                        let line = sem.line(Some(site));
                        let Form::Chain(c) = &vis.form else { return };
                        if !c.hops.is_empty() {
                            return;
                        }
                        let Root::Call { name, args } = &c.root else { return };
                        for (hi, vi) in verb_pairs(name) {
                            let (Some(h), Some(vn)) = (args.get(*hi), args.get(*vi)) else { continue };
                            let Some((recv, var)) = nameof_arg(vn) else { continue };
                            let holder_ty = recv.and_then(|r| w.type_of(&sc, r)).or_else(|| w.type_of(&sc, h)).filter(|t| !t.is_empty() && t != "/");
                            if is_declared(sem, &rels, holder_ty.as_deref(), &var) {
                                continue;
                            }
                            let at = engine_line(root, &rel, line) as u32;
                            if seen.insert((rel.to_string(), at, var.clone())) {
                                let who = holder_ty.clone().unwrap_or_else(|| "an untyped holder".to_string());
                                let decl = holder_ty.as_deref().and_then(|t| sem.var_owner(t, &var)).unwrap_or_default();
                                let listy = holder_ty.as_deref().and_then(|t| sem.var_decl(t, &var)).map(|d| d.is_list()).unwrap_or(false) || matches!(*name, "rel_add" | "rel_remove" | "rel_take_all");
                                let keyed = *name == "rel_add" && args.len() > 3;
                                found.push((rel.to_string(), at, format!("{} writes `{}` of {}, which no relation declares [decl {}::{} many={} keyed={} at={}]", name, var, who, decl, var, listy as u8, keyed as u8, holder_ty.as_deref().and_then(|t| sem.var_decl(t, &var)).map(|d| d.file).unwrap_or_default())));
                            }
                        }
                    });
                }
            }
        }
        // The path form `nameof(/type::var)`: the holder type is named in the argument, so a text scan finds it.
        let path_form = crate::pat!(r"\b(rel_(?:set|add|remove|clear|take|take_all|move))\(\s*[^,]+,\s*nameof\(\s*(/[\w/]+?)/?::(\w+)\s*\)");
        for f in cx.files() {
            if !f.rel.ends_with(".dm") {
                continue;
            }
            for (i, line) in f.code().lines().enumerate() {
                for c in path_form.captures_iter(line).iter() {
                    let (verb, ty, var) = (c.s(1), c.s(2), c.s(3));
                    if is_declared(sem, &rels, Some(ty), var) {
                        continue;
                    }
                    let at = (i + 1) as u32;
                    if seen.insert((f.rel.to_string(), at, var.to_string())) {
                        let decl = sem.var_owner(ty, var).unwrap_or_default();
                        let listy = sem.var_decl(ty, var).map(|d| d.is_list()).unwrap_or(false) || matches!(verb, "rel_add" | "rel_remove" | "rel_take_all");
                        let file = sem.var_decl(ty, var).map(|d| d.file).unwrap_or_default();
                        found.push((f.rel.to_string(), at, format!("{} writes `{}` of {}, which no relation declares [decl {}::{} many={} keyed=0 at={}]", verb, var, ty, decl, var, listy as u8, file)));
                    }
                }
            }
        }
        found.sort();
        for (rel, line, msg) in found {
            out.site_in_msg("undeclared", &rel, line as usize, msg);
        }
    }
}

/// Is `var` a declared relation of `ty` (or a parent or subtype)? Without a type: declared by any type.
fn is_declared(sem: &Sem, rels: &std::collections::HashMap<String, Vec<String>>, ty: Option<&str>, var: &str) -> bool {
    let Some(types) = rels.get(var) else { return false };
    match ty {
        None => true,
        Some(t) => // A declaration on a subtype counts: the static type is often a base (a `/datum/request` view of a prompt), and the runtime
        // check reports the write the static view cannot decide.
        types.iter().any(|d| d == t || sem.is_subtype(t, d) || sem.is_subtype(d, t)),
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(RelWriteUndeclared);
}

/// The statement walk, for the other typed lints of this proposal (player_link, weak_raw_read): every statement's own top-level expressions
/// (an assignment statement, a `del` operand, a declaration's value, a condition, a loop header), not what they nest, with the statement's site.
/// The node is none for an assignment statement, which has none of its own.
pub(crate) fn walk_block_pub(b: &[Statement], f: &mut dyn FnMut(Form<'_>, Option<&Expr>, Site)) {
    for st in stmts(b) {
        let at = st.site;
        match &st.stmt {
            Stmt::Expr(fm @ Form::Assign { .. }, None) => f(fm.clone(), None, at),
            // `del x` reads its operand as a parenthesized expression.
            Stmt::Del(e) => f(Form::Chain(Chain { root: Root::Group(e), root_expr: e, hops: Vec::new() }), None, at),
            // A sized list with no value starts as `new /list(...)`.
            Stmt::Vars(vs) => {
                for d in vs {
                    match d.value {
                        Some(e) => f(form(e), Some(e), at),
                        None => {
                            if let Some(init) = d.initializer() {
                                f(init, None, at);
                            }
                        }
                    }
                }
            }
            _ => {}
        }
        if !matches!(st.stmt, Stmt::Del(_) | Stmt::Vars(_)) {
            for e in stmt_exprs(&st.stmt) {
                f(form(e), Some(e), at);
            }
        }
        if let Stmt::ForLoop { init, inc, .. } = &st.stmt {
            match init {
                Some(ForInit::Var(d)) => {
                    if let Some(e) = d.value {
                        f(form(e), Some(e), at);
                    }
                }
                Some(ForInit::Expr(e)) => f(form(e), Some(e), at),
                None => {}
            }
            if let Some(e) = inc {
                f(form(e), Some(e), at);
            }
        }
        for nb in stmt_blocks(&st.stmt) {
            walk_block_pub(nb, f);
        }
    }
}
