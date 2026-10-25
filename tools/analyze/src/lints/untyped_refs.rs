//! `untyped`: a var with no declared type that a proc assigns an atom or datum (doc/rewrite/proposals/relations.md D8).
//!
//! `stored_refs` classifies a var by its declared type, so an untyped var (`var/x`) holding an entity is invisible to it. This lint closes that
//! path and fails closed: a var that carries no type and is assigned
//! * `typed`: a value the model types as an atom or datum (a typed local, parameter, field, `new /type`), or
//! * `call`: the result of a proc call the model cannot type (unknown counts: the value may be an entity),
//!
//! is reported at the var's declaration. A call is a value, not an entity source, when it resolves (by the proc's identity: the calling type's
//! lookup, a global proc, or the static type of the receiver) to procs whose every return path yields a number, text or null
//! (`dm::value_procs`: a fixpoint over the whole tree, never a list of names), or to a DM builtin that returns one.
//! Declare the var with its type and a relation (`ref_one`, `owns_one`, `weak = TRUE`), or give it a type
//! that is not a reference. An untyped list is `stored_refs`'s list rule, not this one. Its own shrink-only baseline.

use std::collections::{BTreeMap, HashMap};

use dreammaker::ast::{AssignOp, Expression, Term};

use crate::dm::value_procs::{is_call, ValueProcs};
use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::lints::stored_refs::{collect_locals, path_of, Kinds, Place, ProcScope, Walker};
use crate::sem::ast::{stmt_blocks, stmt_exprs, strip_parens, walk_expr};
use crate::sem::procs::engine_line;
use crate::sem::Sem;
use crate::tree::CODE_DM;

const HINT: &str = "give the var its type and declare it a relation (ref_one / owns_one, weak = TRUE for a null-check-only reader), or type it as a value. \
doc/rewrite/proposals/relations.md D8";

static META: Meta = Meta {
    name: "untyped",
    group: "",
    label: "untyped",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Sites {
        baseline: "tools/ci/untyped_baseline.txt",
        header: &[
            "Untyped vars assigned an atom or datum, or an unknown call result (doc/rewrite/proposals/relations.md D8). rule<TAB>file<TAB>text.",
            "Shrink-only: after a sweep run `analyze baseline --update --lint untyped`; it drops fixed sites and never adds one.",
        ],
        banned: &[],
    },
    rules: &[RuleMeta { name: "typed", hint: HINT }, RuleMeta { name: "call", hint: HINT }],
    allow: &[],
    lists: &["exempt_types"],
};

/// How many offending assignment lines one finding lists.
const MAX_SHOWN: usize = 8;

struct Untyped;

fn walk_block(b: &dreammaker::ast::Block, f: &mut dyn FnMut(&Expression, u32)) {
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

/// The name of the local the value is, when it is a bare local or parameter.
fn local_name<'e>(sc: &ProcScope, e: &'e Expression) -> Option<&'e str> {
    let Expression::Base { term, follow } = strip_parens(e) else { return None };
    match &term.elem {
        Term::Ident(n) if follow.is_empty() && sc.locals.contains_key(n.as_str()) => Some(n.as_str()),
        _ => None,
    }
}

impl Lint for Untyped {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let Some(sem) = cx.sem() else {
            out.note("untyped: the semantic model is unavailable; nothing checked");
            return;
        };
        let sem: &Sem = &sem;
        let kinds = Kinds { sem, exempt_types: cx.list("exempt_types").to_vec(), registry: Vec::new(), cache: Default::default() };
        let w = Walker { sem, kinds: &kinds };
        let values = ValueProcs::build(sem, &w);
        let root = &cx.tree.root;
        // (declaring type, var) -> (rule, every "file:line" that assigns it an offending value)
        let mut found: BTreeMap<(String, String), (&'static str, Vec<String>)> = BTreeMap::new();
        for ty in sem.objtree.iter_types() {
            let owner = if ty.get().path.is_empty() { "/".to_string() } else { ty.get().path.clone() };
            for (_, tp) in ty.get().procs.iter() {
                for v in tp.value.iter() {
                    let Some(code) = v.code.as_ref() else { continue };
                    let Some(rel) = sem.file_of(v.location) else { continue };
                    if cx.exempt(rel) {
                        continue;
                    }
                    let mut locals: HashMap<String, (String, Option<Place>)> = HashMap::new();
                    for p in v.parameters.iter() {
                        locals.insert(p.name.to_string(), (path_of(&p.var_type.type_path), None));
                    }
                    collect_locals(code, rel, &mut locals);
                    let sc = ProcScope { owner: &owner, locals };
                    walk_block(code, &mut |e, line| {
                        walk_expr(e, &mut |x| {
                            let Expression::AssignOp { op: AssignOp::Assign, lhs, rhs } = x else { return };
                            let Some(Place::Member(o, name)) = w.place_of(&sc, lhs) else { return };
                            let Some(sig) = sem.var_decl(&o, &name) else { return };
                            if !sig.declared.is_empty() || sig.is_const || sig.file.is_empty() {
                                return;
                            }
                            let rhs = strip_parens(rhs);
                            if matches!(rhs, Expression::Base { term, follow } if follow.is_empty() && matches!(term.elem, Term::List(_))) {
                                return;
                            }
                            let rule = match w.type_of(&sc, rhs) {
                                Some(t) if kinds.is_ref(&t) => "typed",
                                Some(t) if t.is_empty() && local_name(&sc, rhs).is_some_and(|n| values.local_holds_call(&sc, code, n)) => "call",
                                Some(_) => return,
                                None if is_call(rhs) && !values.is_value_call(&sc, rhs) => "call",
                                None => return,
                            };
                            let at = format!("{}:{}", rel, engine_line(root, rel, line));
                            let slot = found.entry((o, name)).or_insert((rule, Vec::new()));
                            if rule == "typed" && slot.0 == "call" {
                                slot.0 = "typed";
                            }
                            if !slot.1.contains(&at) {
                                slot.1.push(at);
                            }
                        });
                    });
                }
            }
        }
        let mut rows: Vec<(String, u32, &'static str, String, String)> = Vec::new();
        for ((o, name), (rule, at)) in found {
            let Some(sig) = sem.var_decl(&o, &name) else { continue };
            let what = if rule == "typed" { "an atom or datum" } else { "a call's result" };
            let shown = at.iter().take(MAX_SHOWN).cloned().collect::<Vec<_>>().join(", ");
            let more = if at.len() > MAX_SHOWN { format!(" and {} more", at.len() - MAX_SHOWN) } else { String::new() };
            rows.push((sig.file.clone(), sig.line, rule, format!("{}/var/{} has no type and is assigned {} at {}{}", if o == "/" { "" } else { o.as_str() }, name, what, shown, more), format!("{}::{}", o, name)));
        }
        rows.sort();
        for (rel, line, rule, msg, ident) in rows {
            if !rel.starts_with("code/") || cx.exempt(&rel) {
                continue;
            }
            out.site_decl(rule, &rel, engine_line(root, &rel, line) as usize, msg, ident);
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(Untyped);
}
