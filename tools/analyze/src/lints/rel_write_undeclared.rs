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

use dreammaker::ast::{Expression, Follow, Term};

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::lints::stored_refs::{collect_locals, path_of, relation_index, Kinds, ProcScope, Walker};
use crate::sem::ast::{strip_parens, walk_expr};
use crate::sem::procs::engine_line;
use crate::sem::Sem;
use crate::tree::{SourceFile, CODE_DM};

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
fn nameof_arg(e: &Expression) -> Option<(Option<Expression>, String)> {
    let e = strip_parens(e);
    let Expression::Base { term, follow } = e else { return None };
    if !follow.is_empty() {
        return None;
    }
    let Term::Call(n, args) = &term.elem else { return None };
    if n.as_str() != "nameof" || args.len() != 1 {
        return None;
    }
    let inner = strip_parens(&args[0]);
    let Expression::Base { term, follow } = inner else { return None };
    match follow.last() {
        None => match &term.elem {
            Term::Ident(v) => Some((None, v.to_string())),
            _ => None,
        },
        Some(last) => {
            let Follow::Field(_, v) = &last.elem else { return None };
            let recv = Expression::Base { term: term.clone(), follow: follow[..follow.len() - 1].to_vec().into_boxed_slice() };
            Some((Some(recv), v.to_string()))
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
        let root = &cx.tree.root;
        let mut seen: HashSet<(String, u32, String)> = HashSet::new();
        let mut found: Vec<(String, u32, String)> = Vec::new();
        // Kept per file (`procs::per_file_in`): a file's writes read its own bodies, the model's structure and where it sits (the message
        // names the declaring file) and the relation index, which the context names.
        let mut rel_rows: Vec<(&String, &Vec<String>)> = rels.iter().collect();
        rel_rows.sort();
        let ctx = crate::incr::mix(&[sem.structure_digest(), sem.placement_digest(), crate::incr::ctx_key(&rel_rows)]);
        let per_file: Vec<Vec<(String, u32, String, String)>> = crate::sem::procs::per_file_in(sem, "rel_write_undeclared-writes", ctx, |rel, defs| {
            let mut writes: Vec<(String, u32, String, String)> = Vec::new();
            if cx.exempt(rel) {
                return writes;
            }
            // The type cache is per file (a judgement runs on many threads).
            let kinds = Kinds { sem, exempt_types: Vec::new(), registry: Vec::new(), cache: Default::default() };
            let w = Walker { sem, kinds: &kinds };
            for (owner, v) in defs {
                {
                    let Some(code) = v.code.as_ref() else { continue };
                    let mut locals = std::collections::HashMap::new();
                    for p in v.parameters.iter() {
                        locals.insert(p.name.to_string(), (path_of(&p.var_type.type_path), None));
                    }
                    collect_locals(code, rel, &mut locals);
                    let sc = ProcScope { owner, locals };
                    walk_block(code, &mut |e, line| {
                        walk_expr(e, &mut |x| {
                            let Expression::Base { term, follow } = x else { return };
                            if !follow.is_empty() {
                                return;
                            }
                            let Term::Call(name, args) = &term.elem else { return };
                            for (hi, vi) in verb_pairs(name.as_str()) {
                                let (Some(h), Some(vn)) = (args.get(*hi), args.get(*vi)) else { continue };
                                let Some((recv, var)) = nameof_arg(vn) else { continue };
                                let holder_ty = recv.as_ref().and_then(|r| w.type_of(&sc, r)).or_else(|| w.type_of(&sc, h)).filter(|t| !t.is_empty() && t != "/");
                                if is_declared(sem, &rels, holder_ty.as_deref(), &var) {
                                    continue;
                                }
                                let at = engine_line(root, rel, line) as u32;
                                {
                                    let who = holder_ty.clone().unwrap_or_else(|| "an untyped holder".to_string());
                                    let decl = holder_ty.as_deref().and_then(|t| sem.var_owner(t, &var)).unwrap_or_default();
                                    let listy = holder_ty.as_deref().and_then(|t| sem.var_decl(t, &var)).map(|d| d.is_list()).unwrap_or(false) || matches!(name.as_str(), "rel_add" | "rel_remove" | "rel_take_all");
                                    let keyed = name.as_str() == "rel_add" && args.len() > 3;
                                    writes.push((rel.to_string(), at, var.clone(), format!("{} writes `{}` of {}, which no relation declares [decl {}::{} many={} keyed={} at={}]", name, var, who, decl, var, listy as u8, keyed as u8, holder_ty.as_deref().and_then(|t| sem.var_decl(t, &var)).map(|d| d.file).unwrap_or_default())));
                                }
                            }
                        });
                    });
                }
            }
            writes
        });
        for (rel, at, var, msg) in per_file.into_iter().flatten() {
            if seen.insert((rel.clone(), at, var)) {
                found.push((rel, at, msg));
            }
        }
        // The path form `nameof(/type::var)`: the holder type is named in the argument, so a text scan finds it.
        let path_form = crate::pat!(r"\b(rel_(?:set|add|remove|clear|take|take_all|move))\(\s*[^,]+,\s*nameof\(\s*(/[\w/]+?)/?::(\w+)\s*\)");
        let dm_files: Vec<&SourceFile> = cx.files().into_iter().filter(|f| f.rel.ends_with(".dm")).collect();
        // Each file's path-form writes (verb, type, var, line), kept per file (`crate::incr`).
        let path_writes: Vec<Vec<(String, String, String, u32)>> = crate::incr::facts("rel_write_undeclared-path-form", &dm_files, |f| {
            let mut out = Vec::new();
            for (i, line) in f.code().lines().enumerate() {
                for c in path_form.captures_iter(line).iter() {
                    out.push((c.s(1).to_string(), c.s(2).to_string(), c.s(3).to_string(), (i + 1) as u32));
                }
            }
            out
        });
        for (f, writes) in dm_files.iter().zip(path_writes) {
            {
                for (verb, ty, var, at) in &writes {
                    let (verb, ty, var) = (verb.as_str(), ty.as_str(), var.as_str());
                    if is_declared(sem, &rels, Some(ty), var) {
                        continue;
                    }
                    let at = *at;
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

fn walk_block(b: &dreammaker::ast::Block, f: &mut dyn FnMut(&Expression, u32)) {
    use crate::sem::ast::{stmt_blocks, stmt_exprs};
    use dreammaker::ast::Statement;
    for st in b.iter() {
        let line = st.location.line;
        for e in stmt_exprs(&st.elem) {
            f(e, line);
        }
        if let Statement::ForLoop { init, inc, .. } = &st.elem {
            for s in [init, inc].into_iter().flatten() {
                for e in stmt_exprs(s) {
                    f(e, line);
                }
            }
        }
        for nb in stmt_blocks(&st.elem) {
            walk_block(nb, f);
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(RelWriteUndeclared);
}

/// The statement walk, for the other typed lints of this proposal (player_link).
pub(crate) fn walk_block_pub(b: &dreammaker::ast::Block, f: &mut dyn FnMut(&Expression, u32)) {
    walk_block(b, f)
}
