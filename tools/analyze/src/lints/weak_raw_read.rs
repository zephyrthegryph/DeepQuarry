//! `weak_raw_read`: a weak relation var is read or written raw, not through its generated accessor
//! (doc/rewrite/proposals/relations.md, D5).
//!
//! A `ref_one` / `ref_many(nameof(v), ..., weak = TRUE)` var holds a handle (`ref_token()` text, or a list of them), never the target. The
//! target is read with the generated accessor `v()` and written with `rel_set` / `rel_add` / `rel_remove` / `rel_clear`. A raw read of
//! `v` sees the handle text: `istype()` fails, `.name` is runtime-null, `== target` is false. A hard ban, no baseline.
//!
//! The holder of a read comes from the receiver's static type (`src` and bare names use the proc's own type). A receiver the model cannot
//! type is not judged: the lint is exact where it can see the type and silent where it cannot.

use std::collections::{HashMap, HashSet};

use dreammaker::ast::{Expression, Follow, Term};

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::lints::rel_write_undeclared::walk_block_pub;
use crate::lints::stored_refs::{collect_locals, path_of, Kinds, ProcScope, Walker};
use crate::sem::ast::walk_expr;
use crate::sem::procs::engine_line;
use crate::sem::Sem;
use crate::tree::CODE_DM;

const HINT: &str = "a weak relation var holds a handle, not the target: read it with its generated accessor v() and write it with rel_set / rel_add / rel_remove / rel_clear. \
doc/rewrite/proposals/relations.md D5";

static META: Meta = Meta {
    name: "weak_raw_read",
    group: "",
    label: "weak_raw_read",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "raw", hint: HINT }],
    allow: &[],
    lists: &[],
};

struct WeakRawRead;

/// Weak declarations by var name: name -> the types whose CAPABILITIES block declares it `weak = TRUE`.
fn weak_index(cx: &Cx) -> HashMap<String, Vec<String>> {
    let header = crate::pat!(r"^\s*CAPABILITIES\(\s*(/[\w/]+)\s*\)");
    let decl = crate::pat!(r"\bref_(?:one|many)\(\s*nameof\(\s*(\w+)\s*\)[^\n]*\bweak\s*=\s*TRUE");
    let mut out: HashMap<String, Vec<String>> = HashMap::new();
    for f in cx.files() {
        if !f.rel.ends_with(".dm") {
            continue;
        }
        let mut owner: Option<String> = None;
        for line in f.code().lines() {
            if let Some(c) = header.captures(line) {
                owner = Some(c.s(1).to_string());
                continue;
            }
            if !line.starts_with(char::is_whitespace) && !line.trim().is_empty() {
                owner = None;
            }
            let Some(o) = owner.as_ref() else { continue };
            if let Some(c) = decl.captures(line) {
                let types = out.entry(c.s(1).to_string()).or_default();
                if !types.contains(o) {
                    types.push(o.clone());
                }
            }
        }
    }
    out
}

fn compatible(sem: &Sem, declarers: &[String], ty: &str) -> bool {
    declarers.iter().any(|d| d == ty || sem.is_subtype(ty, d) || sem.is_subtype(d, ty))
}

impl Lint for WeakRawRead {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let Some(sem) = cx.sem() else {
            out.note("weak_raw_read: the semantic model is unavailable; nothing checked");
            return;
        };
        let sem: &Sem = &sem;
        let weak = weak_index(cx);
        if weak.is_empty() {
            return;
        }
        let kinds = Kinds { sem, exempt_types: Vec::new(), registry: Vec::new(), cache: Default::default() };
        let w = Walker { sem, kinds: &kinds };
        let root = &cx.tree.root;
        let mut seen: HashSet<(String, u32, String)> = HashSet::new();
        let mut found: Vec<(String, u32, String)> = Vec::new();
        for ty in sem.objtree.iter_types() {
            let owner = if ty.get().path.is_empty() { "/".to_string() } else { ty.get().path.clone() };
            for (_, tp) in ty.get().procs.iter() {
                for v in tp.value.iter() {
                    let Some(code) = v.code.as_ref() else { continue };
                    let Some(rel) = sem.file_of(v.location) else { continue };
                    if cx.exempt(rel) {
                        continue;
                    }
                    let mut locals = HashMap::new();
                    for p in v.parameters.iter() {
                        locals.insert(p.name.to_string(), (path_of(&p.var_type.type_path), None));
                    }
                    collect_locals(code, rel, &mut locals);
                    let sc = ProcScope { owner: &owner, locals };
                    walk_block_pub(code, &mut |e, line| {
                        // Everything inside a nameof(...) names the var, it does not read it.
                        let mut named: HashSet<usize> = HashSet::new();
                        walk_expr(e, &mut |x| {
                            if let Expression::Base { term, .. } = x {
                                if let Term::Call(n, args) = &term.elem {
                                    if n.as_str() == "nameof" {
                                        for a in args.iter() {
                                            walk_expr(a, &mut |y| {
                                                named.insert(y as *const Expression as usize);
                                            });
                                        }
                                    }
                                }
                            }
                        });
                        walk_expr(e, &mut |x| {
                            if named.contains(&(x as *const Expression as usize)) {
                                return;
                            }
                            let Expression::Base { term, follow } = x else { return };
                            let mut hits: Vec<(String, Option<String>)> = Vec::new();
                            if let Term::Ident(n) = &term.elem {
                                if weak.contains_key(n.as_str()) && !sc.locals.contains_key(n.as_str()) {
                                    hits.push((n.to_string(), Some(owner.clone())));
                                }
                            }
                            for (i, fo) in follow.iter().enumerate() {
                                let Follow::Field(_, f) = &fo.elem else { continue };
                                if !weak.contains_key(f.as_str()) {
                                    continue;
                                }
                                let recv = Expression::Base { term: term.clone(), follow: follow[..i].to_vec().into_boxed_slice() };
                                hits.push((f.to_string(), w.type_of(&sc, &recv)));
                            }
                            for (var, holder) in hits {
                                let Some(holder) = holder.filter(|t| !t.is_empty() && t != "/") else { continue };
                                if !compatible(sem, &weak[&var], &holder) {
                                    continue;
                                }
                                let at = engine_line(root, rel, line) as u32;
                                if seen.insert((rel.to_string(), at, var.clone())) {
                                    found.push((rel.to_string(), at, format!("`{}` of {} is a weak relation read raw; use {}()", var, holder, var)));
                                }
                            }
                        });
                    });
                }
            }
        }
        found.sort();
        for (rel, line, msg) in found {
            out.site_in_msg("raw", &rel, line as usize, msg);
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(WeakRawRead);
}
