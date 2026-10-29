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
use crate::sem::decls::Decls;
use crate::sem::procs::engine_line;
use crate::sem::value_schema::{ValueKind, ValueSchemas};
use crate::sem::Sem;
use crate::tree::CODE_DM;

const HINT: &str = "give the var its type and declare it a relation (ref_one / owns_one, weak = TRUE for a null-check-only reader), or declare it a value: \
`SCHEMA(T, var, schema_path(/base) | schema_msg() | schema_text() | num() | schema_any())` on its own line (doc/rewrite/proposals/typed_values.md)";
const HINT_SCHEMA: &str = "the var's SCHEMA says it holds a path under a base (schema_path) or a /datum/msg path (schema_msg): assign a path that fits, or fix the declaration. \
doc/rewrite/proposals/typed_values.md section 5";

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
        banned: &["typed", "call", "schema"],
    },
    rules: &[RuleMeta { name: "typed", hint: HINT }, RuleMeta { name: "call", hint: HINT }, RuleMeta { name: "schema", hint: HINT_SCHEMA }],
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

/// The type path literals an assignment's right side is, when it is one or a ternary of them (other expressions are trusted: the declaration is the
/// author's claim and `schema_check` backs it at run time).
fn path_literals(e: &Expression, out: &mut Vec<String>) {
    match strip_parens(e) {
        Expression::TernaryOp { if_, else_, .. } => {
            path_literals(if_, out);
            path_literals(else_, out);
        }
        Expression::Base { term, follow } if follow.is_empty() => {
            if let Term::Prefab(p) = &term.elem {
                out.push(p.path.iter().map(|(_, n)| format!("/{n}")).collect());
            }
        }
        _ => {}
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
        scan(cx, out, &mut Lits::new());
    }
}

/// What the assignments to one untyped var say about its value (the evidence `analyze fix --propose-schema` reads).
#[derive(Default, Clone)]
pub struct Evidence {
    /// Every type path literal assigned (a ternary contributes both branches).
    pub paths: Vec<String>,
    pub texts: usize,
    pub nums: usize,
    /// Assignments of anything else (a call, a local, a read).
    pub other: usize,
}

type Lits = BTreeMap<(String, String), Evidence>;

fn scan(cx: &Cx, out: &mut Sink, lits_out: &mut Lits) {
    {
        let t_scan = std::time::Instant::now();
        let trace = std::env::var_os("DQ_ANALYZE_TRACE").is_some();
        let Some(sem) = cx.sem() else {
            out.note("untyped: the semantic model is unavailable; nothing checked");
            return;
        };
        let sem: &Sem = &sem;
        if trace {
            eprintln!("untyped: model ready after {:.2?}", t_scan.elapsed());
        }
        let kinds = Kinds { sem, exempt_types: cx.list("exempt_types").to_vec(), registry: Vec::new(), cache: Default::default() };
        let w = Walker { sem, kinds: &kinds };
        let values = ValueProcs::build(sem, &w);
        let schemas = ValueSchemas::build(&Decls::get(cx.tree));
        if trace {
            eprintln!("untyped: value procs and schemas built after {:.2?}", t_scan.elapsed());
        }
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
                            {
                                let ev = lits_out.entry((o.clone(), name.clone())).or_default();
                                let mut lits = Vec::new();
                                path_literals(rhs, &mut lits);
                                match rhs {
                                    _ if !lits.is_empty() => ev.paths.extend(lits),
                                    Expression::Base { term, follow } if follow.is_empty() && matches!(term.elem, Term::String(_) | Term::InterpString(..)) => ev.texts += 1,
                                    Expression::Base { term, follow } if follow.is_empty() && matches!(term.elem, Term::Int(_) | Term::Float(_)) => ev.nums += 1,
                                    _ => ev.other += 1,
                                }
                            }
                            // A var with a value schema is a value, never an entity: its assignments are checked against the schema instead.
                            let schema_kind = schemas.find(sem, &o, &name);
                            let any_value = matches!(schema_kind, Some(ValueKind::Any));
                            if let Some(kind) = schema_kind.filter(|_| !any_value) {
                                let mut lits = Vec::new();
                                path_literals(rhs, &mut lits);
                                if let Some(bad) = lits.iter().find(|l| !schemas.accepts_path(sem, kind, l)) {
                                    let at = format!("{}:{}", rel, engine_line(root, rel, line));
                                    let want = match kind {
                                        ValueKind::Path(b) => format!("a path under {}", b),
                                        ValueKind::Msg => "a /datum/msg path".to_string(),
                                        ValueKind::Plain | ValueKind::Many | ValueKind::Any => "a plain value".to_string(),
                                    };
                                    let slot = found.entry((o, name)).or_insert(("schema", Vec::new()));
                                    let note = format!("{} ({} is not {})", at, bad, want);
                                    if !slot.1.contains(&note) {
                                        slot.1.push(note);
                                    }
                                }
                                return;
                            }
                            let rule = match w.type_of(&sc, rhs) {
                                Some(t) if kinds.is_ref(&t) => "typed",
                                Some(t) if t.is_empty() && local_name(&sc, rhs).is_some_and(|n| values.local_holds_call(&sc, code, n)) => "call",
                                Some(_) => return,
                                None if is_call(rhs) && !values.is_value_call(&sc, rhs) => "call",
                                None => return,
                            };
                            // `schema_any()` declares the var carries whatever its producer returns: a call's result is that, an atom or datum is not.
                            if any_value && rule == "call" {
                                return;
                            }
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
        if trace {
            eprintln!("untyped: body walk done after {:.2?}", t_scan.elapsed());
        }
        let mut rows: Vec<(String, u32, &'static str, String, String)> = Vec::new();
        for ((o, name), (rule, at)) in found {
            let Some(sig) = sem.var_decl(&o, &name) else { continue };
            let what = match rule {
                "typed" => "an atom or datum",
                "schema" => "a value its SCHEMA refuses",
                _ => "a call's result",
            };
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

/// The longest shared type path of the literals (`/obj/item/fish/koi`, `/obj/item/fish/carp` -> `/obj/item/fish`), or the one literal's parent type.
fn common_base(sem: &Sem, paths: &[String]) -> Option<String> {
    let mut it = paths.iter();
    let first: Vec<&str> = it.next()?.split('/').filter(|s| !s.is_empty()).collect();
    let mut keep = first.len();
    for p in it {
        let seg: Vec<&str> = p.split('/').filter(|s| !s.is_empty()).collect();
        keep = keep.min(first.iter().zip(seg.iter()).take_while(|(a, b)| a == b).count());
    }
    if paths.iter().all(|p| p == &paths[0]) {
        return sem.parent_of(&paths[0]).filter(|p| p != "/");
    }
    if keep == 0 {
        return None;
    }
    Some(first[..keep].iter().fold(String::new(), |a, s| format!("{a}/{s}")))
}

/// `analyze fix --propose-schema`: for each untyped var the lint reports, the `SCHEMA` line it would take. It PROPOSES and never writes a file
/// (doc/rewrite/proposals/typed_values.md D4): the machine cannot know that `fish_type` is an `/obj/item/fish`, so a person picks the base.
pub fn propose_cli(root: &std::path::Path) -> std::process::ExitCode {
    use crate::lint::Cx;
    let opts = crate::run::Options { root: root.to_path_buf(), lints: vec!["untyped".to_string()], ..Default::default() };
    let engine = match crate::run::Engine::new(crate::run::registry(), opts) {
        Ok(e) => e,
        Err(e) => {
            eprintln!("analyze fix: {}", e);
            return std::process::ExitCode::from(2);
        }
    };
    let scope = engine.scopes.for_lint(META.name, META.group);
    let cx = Cx { tree: &engine.tree, meta: &META, scope: &scope };
    let mut sink = Sink::new();
    let mut lits = Lits::new();
    scan(&cx, &mut sink, &mut lits);
    let Some(sem) = cx.sem() else {
        println!("no semantic model");
        return std::process::ExitCode::from(2);
    };
    let mut n = 0;
    for site in sink.sites.iter().filter(|s| s.rule == "call") {
        let Some((o, v)) = site.ident.split_once("::") else { continue };
        let ev = lits.get(&(o.to_string(), v.to_string())).cloned().unwrap_or_default();
        let expr = if !ev.paths.is_empty() && ev.texts == 0 && ev.nums == 0 {
            match common_base(&sem, &ev.paths) {
                Some(b) => format!("schema_path({b})"),
                None => "schema_path(/*base: review*/)".to_string(),
            }
        } else if ev.texts > 0 && ev.paths.is_empty() && ev.nums == 0 {
            "schema_text()".to_string()
        } else if ev.nums > 0 && ev.paths.is_empty() && ev.texts == 0 {
            "num()".to_string()
        } else {
            "/*kind: review*/".to_string()
        };
        println!("{}:{}: PROPOSED (not applied; a person reviews the base): SCHEMA({}, {}, {})", site.rel, site.line, o, v, expr);
        n += 1;
    }
    println!("{n} proposal(s); nothing was written (--apply does not apply a schema_path base).");
    std::process::ExitCode::SUCCESS
}
