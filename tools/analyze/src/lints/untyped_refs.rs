//! `untyped`: a var with no declared type that a proc assigns an atom or datum (doc/rewrite/proposals/relations.md D8).
//!
//! `stored_refs` classifies a var by its declared type, so an untyped var (`var/x`) holding an entity is invisible to it. This lint closes that
//! path and fails closed: a var that carries no type and is assigned
//! * `typed`: a value the model types as an atom or datum (a typed local, parameter, field, `new /type`), or
//! * `call`: the result of a proc call the model cannot type (unknown counts: the value may be an entity),
//!
//! is reported at the var's declaration. Declare the var with its type and a relation (`ref_one`, `owns_one`, `weak = TRUE`), or give it a type
//! that is not a reference. An untyped list is `stored_refs`'s list rule, not this one. Its own shrink-only baseline.

use std::collections::{BTreeMap, HashMap};

use dreammaker::ast::{AssignOp, Expression, Follow, Term};

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
    lists: &["exempt_types", "value_calls"],
};

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

/// The value is the result of a proc call (a plain, global, or method call at the end of the chain).
fn is_call(e: &Expression) -> bool {
    let e = strip_parens(e);
    let Expression::Base { term, follow } = e else { return false };
    if let Some(last) = follow.last() {
        return matches!(last.elem, Follow::Call(..));
    }
    matches!(term.elem, Term::Call(..) | Term::GlobalCall(..))
}

/// Builtin calls whose result is never an entity: numbers, text, tests and the like.
fn is_value_call(e: &Expression, extra: &[String]) -> bool {
    let e = strip_parens(e);
    let Expression::Base { term, follow } = e else { return false };
    if !follow.is_empty() {
        return false;
    }
    let name = match &term.elem {
        Term::Call(n, _) | Term::GlobalCall(n, _) => n.as_str(),
        _ => return false,
    };
    if extra.iter().any(|n| n == name) {
        return true;
    }
    matches!(
        name,
        "rand" | "prob" | "round" | "floor" | "ceil" | "abs" | "min" | "max" | "sqrt" | "sin" | "cos" | "num2text" | "text2num" | "list2params" | "length" | "lowertext"
            | "uppertext" | "copytext" | "replacetext" | "findtext" | "jointext" | "get_dist" | "nameof" | "REF" | "ckey" | "trim" | "clamp" | "text" | "isnull"
            | "initial" | "md5" | "replacetextEx" | "turn" | "get_dir" | "html_decode" | "html_encode" | "text2ascii" | "ascii2text" | "file2text" | "rgb" | "ref" | "istype" | "ispath" | "islist" | "isnum" | "istext" | "time2text" | "addtext" | "splittext" | "json_encode" | "sanitize" | "text2path"
    )
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
        let value_calls = cx.list("value_calls").to_vec();
        let w = Walker { sem, kinds: &kinds };
        let root = &cx.tree.root;
        // (declaring type, var) -> (rule, "file:line of the first assignment")
        let mut found: BTreeMap<(String, String), (&'static str, String)> = BTreeMap::new();
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
                                Some(_) => return,
                                None if is_call(rhs) && !is_value_call(rhs, &value_calls) => "call",
                                None => return,
                            };
                            let at = format!("{}:{}", rel, engine_line(root, rel, line));
                            let slot = found.entry((o, name)).or_insert((rule, at));
                            if rule == "typed" && slot.0 == "call" {
                                slot.0 = "typed";
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
            rows.push((sig.file.clone(), sig.line, rule, format!("{}/var/{} has no type and is assigned {} (e.g. {})", if o == "/" { "" } else { o.as_str() }, name, what, at), format!("{}::{}", o, name)));
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
