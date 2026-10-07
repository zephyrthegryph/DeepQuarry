//! Per-proc structural checks on the AST: ACT_TRY pairing, context escape, boolean returns.
//!
//! These look at one proc body at a time (they need the proc's own statements and the names of
//! its act-typed locals, nothing from other files), so they run on a partial model of just the
//! files that mention an action or a context (see `lints/sem_handlers.rs`).

use std::collections::{BTreeMap, BTreeSet};

use dreammaker::ast::{AssignOp, BinaryOp, Block, Expression, Follow, Statement, Term, UnaryOp};

use super::ast::{as_call, as_ident, calls_in, stmt_blocks, stmt_exprs, strip_parens, walk_block, walk_expr};

/// Calls that start a world action (the macro `ACT_TRY` must survive expansion as one of these).
pub const DEFAULT_TRY_CALLS: &[&str] = &["ACT_TRY", "act_try", "e0_act_try"];
/// Calls that end one.
pub const CLOSE_CALLS: &[&str] = &["act_done", "act_cancel"];

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Found {
    pub rule: &'static str,
    pub line: u32,
    pub msg: String,
}

// ---- ACT_TRY pairing ----------------------------------------------------------------------------

/// "Every ACT_TRY has act_done or act_cancel on every path of the same proc." A returned
/// `null` (refused or taken over) and the ACT_PASS sentinel carry no act to close, so a branch
/// that tests the result for null or `ACT_PASS` is clean.
pub fn act_try_pairing(code: &Block, try_calls: &[&str], out: &mut Vec<Found>) {
    let mut seen_try = false;
    walk_block(code, &mut |e, _| {
        if let Some((n, _)) = as_call(e) {
            if try_calls.contains(&n) {
                seen_try = true;
            }
        }
    });
    if !seen_try {
        return;
    }
    let mut ctx = Pair { try_calls, found: Vec::new() };
    let end = ctx.block(code, BTreeMap::new());
    if let Some(pending) = end {
        for (var, line) in pending {
            ctx.found.push(Found { rule: "act_try_unpaired", line, msg: format!("ACT_TRY into `{}` reaches the end of the proc without act_done or act_cancel", var) });
        }
    }
    ctx.found.sort_by_key(|f| (f.line, f.msg.clone()));
    ctx.found.dedup();
    out.extend(ctx.found);
}

struct Pair<'a> {
    try_calls: &'a [&'a str],
    found: Vec<Found>,
}

type Pending = BTreeMap<String, u32>;

fn merge(outs: Vec<Pending>) -> Option<Pending> {
    if outs.is_empty() {
        return None;
    }
    let mut m = Pending::new();
    for o in outs {
        for (k, v) in o {
            m.entry(k).or_insert(v);
        }
    }
    Some(m)
}

impl<'a> Pair<'a> {
    fn is_try(&self, e: &Expression) -> bool {
        matches!(as_call(strip_parens(e)), Some((n, _)) if self.try_calls.contains(&n))
    }

    /// Closes every `act_done(X)` / `act_cancel(X)` in `e`.
    fn closes(&self, e: &Expression, pending: &mut Pending) {
        calls_in(e, &mut |n, args| {
            if CLOSE_CALLS.contains(&n) {
                if let Some(id) = args.first().and_then(|a| as_ident(strip_parens(a))) {
                    pending.remove(id);
                }
            }
        });
    }

    fn block(&mut self, b: &Block, mut pending: Pending) -> Option<Pending> {
        for st in b.iter() {
            let line = st.location.line;
            match &st.elem {
                Statement::Return(e) => {
                    let mut p = pending.clone();
                    if let Some(e) = e {
                        self.closes(e, &mut p);
                    }
                    for (var, at) in p {
                        self.found.push(Found { rule: "act_try_unpaired", line: at, msg: format!("ACT_TRY into `{}` is returned past at line {} without act_done or act_cancel", var, line) });
                    }
                    return None;
                }
                Statement::Throw(_) | Statement::Crash(_) => return None,
                Statement::If { arms, else_arm } => {
                    let mut outs: Vec<Pending> = Vec::new();
                    let mut on_false = pending.clone();
                    for (cond, blk) in arms {
                        self.closes(&cond.elem, &mut on_false);
                        let mut inner = on_false.clone();
                        for x in null_tested(&cond.elem) {
                            inner.remove(&x);
                        }
                        if let Some(o) = self.block(blk, inner) {
                            outs.push(o);
                        }
                        for x in non_null_tested(&cond.elem) {
                            on_false.remove(&x);
                        }
                    }
                    match else_arm {
                        Some(eb) => {
                            if let Some(o) = self.block(eb, on_false) {
                                outs.push(o);
                            }
                        }
                        None => outs.push(on_false),
                    }
                    pending = merge(outs)?;
                }
                Statement::Expr(e) => self.simple(e, line, &mut pending),
                Statement::Var(vs) => {
                    if let Some(v) = &vs.value {
                        if self.is_try(v) {
                            pending.insert(vs.name.clone(), line);
                        } else {
                            self.closes(v, &mut pending);
                        }
                    }
                }
                Statement::Vars(list) => {
                    for vs in list {
                        if let Some(v) = &vs.value {
                            if self.is_try(v) {
                                pending.insert(vs.name.clone(), line);
                            }
                        }
                    }
                }
                other => {
                    for e in stmt_exprs(other) {
                        self.closes(e, &mut pending);
                    }
                    let blocks = stmt_blocks(other);
                    if blocks.is_empty() {
                        continue;
                    }
                    let is_switch = matches!(other, Statement::Switch { default: Some(_), .. });
                    let mut outs: Vec<Pending> = Vec::new();
                    if !is_switch {
                        // The body may run zero times (loops), or a try/catch arm may be skipped.
                        outs.push(pending.clone());
                    }
                    for blk in blocks {
                        if let Some(o) = self.block(blk, pending.clone()) {
                            outs.push(o);
                        }
                    }
                    pending = merge(outs)?;
                }
            }
        }
        Some(pending)
    }

    fn simple(&mut self, e: &Expression, line: u32, pending: &mut Pending) {
        match e {
            Expression::AssignOp { op: AssignOp::Assign, lhs, rhs } if self.is_try(rhs) => {
                if let Some(id) = as_ident(strip_parens(lhs)) {
                    pending.insert(id.to_string(), line);
                } else {
                    self.found.push(Found { rule: "act_try_unpaired", line, msg: "ACT_TRY result is stored where act_done cannot name it; assign it to a local".to_string() });
                }
            }
            _ if self.is_try(e) => {
                self.found.push(Found { rule: "act_try_unpaired", line, msg: "ACT_TRY result is dropped: nothing can act_done or act_cancel it".to_string() });
            }
            _ => self.closes(e, pending),
        }
    }
}

/// Idents the condition proves null (or the ACT_PASS sentinel) when TRUE: `!X`, `isnull(X)`,
/// `X == null`, `X == (-1)`.
fn null_tested(c: &Expression) -> Vec<String> {
    let mut out = Vec::new();
    let c = strip_parens(c);
    match c {
        Expression::Base { term, follow } => {
            if follow.len() == 1 && matches!(follow[0].elem, Follow::Unary(UnaryOp::Not)) {
                if let Term::Ident(n) = &term.elem {
                    out.push(n.clone());
                }
                if let Term::Expr(inner) = &term.elem {
                    // !(X)
                    if let Some(id) = as_ident(strip_parens(inner)) {
                        out.push(id.to_string());
                    }
                }
            }
            if follow.is_empty() {
                if let Term::Call(n, args) = &term.elem {
                    if n.as_str() == "isnull" {
                        if let Some(id) = args.first().and_then(|a| as_ident(strip_parens(a))) {
                            out.push(id.to_string());
                        }
                    }
                }
            }
        }
        Expression::BinaryOp { op: BinaryOp::Eq, lhs, rhs } => {
            for (a, b) in [(lhs, rhs), (rhs, lhs)] {
                if let Some(id) = as_ident(strip_parens(a)) {
                    if is_null_or_sentinel(b) {
                        out.push(id.to_string());
                    }
                }
            }
        }
        Expression::BinaryOp { op: BinaryOp::Or, lhs, rhs } => {
            out.extend(null_tested(lhs));
            out.extend(null_tested(rhs));
        }
        _ => {}
    }
    out
}

/// Idents the condition proves non-null when TRUE (`if(X)`, `X != null`), so the else path has them null.
fn non_null_tested(c: &Expression) -> Vec<String> {
    let mut out = Vec::new();
    let c = strip_parens(c);
    match c {
        Expression::Base { term, follow } if follow.is_empty() => {
            if let Term::Ident(n) = &term.elem {
                out.push(n.clone());
            }
        }
        Expression::BinaryOp { op: BinaryOp::NotEq, lhs, rhs } => {
            for (a, b) in [(lhs, rhs), (rhs, lhs)] {
                if let Some(id) = as_ident(strip_parens(a)) {
                    if is_null_or_sentinel(b) {
                        out.push(id.to_string());
                    }
                }
            }
        }
        _ => {}
    }
    out
}

fn is_null_or_sentinel(e: &Expression) -> bool {
    let e = strip_parens(e);
    if let Expression::Base { term, follow } = e {
        match (&term.elem, follow.len()) {
            (Term::Null, 0) => return true,
            // (-1): the ACT_PASS sentinel after expansion.
            (Term::Int(i), 0) if *i < 0 => return true,
            (Term::Int(1), 1) if matches!(follow[0].elem, Follow::Unary(UnaryOp::Neg)) => return true,
            _ => {}
        }
    }
    false
}

// ---- context escape -----------------------------------------------------------------------------

/// "A pooled datum/act may not be stored in a var or passed in with =; use A.snapshot()."
/// `acts` are the proc's act-typed idents (params and locals).
pub fn context_escape(code: &Block, acts: &BTreeSet<String>, locals: &BTreeSet<String>, out: &mut Vec<Found>) {
    if acts.is_empty() {
        return;
    }
    let is_act = |e: &Expression| -> Option<String> {
        let id = as_ident(strip_parens(e))?;
        acts.contains(id).then(|| id.to_string())
    };
    let mut named_args: Vec<*const Expression> = Vec::new();
    walk_block(code, &mut |e, line| {
        match e {
            Expression::AssignOp { lhs, rhs, .. } => {
                // A named call argument (`with = A`) is reported by its call, not as a store.
                if named_args.contains(&(e as *const Expression)) {
                    return;
                }
                if let Some(a) = is_act(rhs) {
                    // Storing into a plain local is an alias for the trigger; anything else outlives it.
                    let local = as_ident(strip_parens(lhs)).map(|n| locals.contains(n)).unwrap_or(false);
                    if !local {
                        out.push(Found { rule: "context_escape", line, msg: format!("`{}` is a pooled context and is stored where it can outlive the trigger; use {}.snapshot()", a, a) });
                    }
                }
            }
            Expression::Base { term, follow } => {
                let mut note_named = |args: &[Expression]| {
                    for a in args {
                        if matches!(a, Expression::AssignOp { op: AssignOp::Assign, .. }) {
                            named_args.push(a as *const Expression);
                        }
                    }
                };
                match &term.elem {
                    Term::Call(_, args) | Term::NewPrefab { args: Some(args), .. } | Term::NewImplicit { args: Some(args) } => note_named(args),
                    _ => {}
                }
                for fo in follow.iter() {
                    if let Follow::Call(_, _, args) = &fo.elem {
                        note_named(args);
                    }
                }
                fn check_args(args: &[Expression], what: &str, line: u32, is_act: &dyn Fn(&Expression) -> Option<String>, out: &mut Vec<Found>) {
                    for a in args {
                        // A named argument `with = A`.
                        if let Expression::AssignOp { op: AssignOp::Assign, rhs, .. } = a {
                            if let Some(n) = is_act(rhs) {
                                out.push(Found { rule: "context_escape", line, msg: format!("`{}` is passed in with = to {}; use {}.snapshot()", n, what, n) });
                            }
                        }
                    }
                }
                match &term.elem {
                    Term::Call(n, args) => check_args(args, n.as_str(), line, &is_act, out),
                    Term::List(args) => {
                        for a in args.iter() {
                            if let Some(n) = is_act(a) {
                                out.push(Found { rule: "context_escape", line, msg: format!("`{}` is put in a list; use {}.snapshot()", n, n) });
                            }
                        }
                    }
                    Term::NewPrefab { args: Some(args), .. } | Term::NewImplicit { args: Some(args) } => check_args(args, "new", line, &is_act, out),
                    _ => {}
                }
                for fo in follow.iter() {
                    if let Follow::Call(_, n, args) = &fo.elem {
                        check_args(args, n.as_str(), line, &is_act, out);
                        if matches!(n.as_str(), "Add" | "Insert") {
                            for a in args.iter() {
                                if let Some(x) = is_act(a) {
                                    out.push(Found { rule: "context_escape", line, msg: format!("`{}` is added to a list; use {}.snapshot()", x, x) });
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

// ---- requirement and condition returns ------------------------------------------------------------

/// A requirement or condition answers TRUE or FALSE. A string, a type or a non-boolean number
/// would read as TRUE and silently allow the op, so a definite non-boolean return is an error.
pub fn boolean_returns(code: &Block, out: &mut Vec<Found>) {
    fn visit(b: &Block, out: &mut Vec<Found>) {
        for st in b.iter() {
            if let Statement::Return(e) = &st.elem {
                let line = st.location.line;
                match e {
                    None => out.push(Found { rule: "requirement_return", line, msg: "a bare `return` answers null, which reads as TRUE and allows the op".to_string() }),
                    Some(e) => {
                        if let Some(why) = non_boolean(e) {
                            out.push(Found { rule: "requirement_return", line, msg: format!("returns {}: a requirement answers TRUE or FALSE (the reason is declared beside it)", why) });
                        }
                    }
                }
            }
            for nb in stmt_blocks(&st.elem) {
                visit(nb, out);
            }
        }
    }
    visit(code, out);
}

fn non_boolean(e: &Expression) -> Option<&'static str> {
    let e = strip_parens(e);
    match e {
        Expression::Base { term, follow } => {
            if follow.iter().any(|f| matches!(f.elem, Follow::Unary(UnaryOp::Not))) {
                return None;
            }
            match &term.elem {
                Term::String(_) | Term::InterpString(..) => Some("text"),
                Term::Null => Some("null"),
                Term::Prefab(_) => Some("a type path"),
                Term::List(_) => Some("a list"),
                Term::Int(i) if *i != 0 && *i != 1 => Some("a number other than TRUE/FALSE"),
                Term::Float(_) => Some("a number other than TRUE/FALSE"),
                _ => None,
            }
        }
        Expression::TernaryOp { if_, else_, .. } => non_boolean(if_).or_else(|| non_boolean(else_)),
        _ => None,
    }
}

/// Locals and params of a proc that are act-typed, by declared type path.
pub fn act_idents(params: &[dreammaker::ast::Parameter], code: &Block, try_calls: &[&str]) -> (BTreeSet<String>, BTreeSet<String>) {
    let mut acts = BTreeSet::new();
    let mut locals = BTreeSet::new();
    let is_act_path = |p: &[String]| p.len() >= 2 && p[0] == "datum" && p[1] == "act";
    for p in params {
        locals.insert(p.name.clone());
        if is_act_path(&p.var_type.type_path) {
            acts.insert(p.name.clone());
        }
    }
    fn walk(b: &Block, acts: &mut BTreeSet<String>, locals: &mut BTreeSet<String>, try_calls: &[&str], is_act_path: &dyn Fn(&[String]) -> bool) {
        for st in b.iter() {
            let mut add = |name: &str, tp: &[String], v: &Option<Expression>| {
                locals.insert(name.to_string());
                if is_act_path(tp) {
                    acts.insert(name.to_string());
                } else if let Some(e) = v {
                    if matches!(as_call(strip_parens(e)), Some((n, _)) if try_calls.contains(&n)) {
                        acts.insert(name.to_string());
                    }
                }
            };
            match &st.elem {
                Statement::Var(vs) => add(&vs.name, &vs.var_type.type_path, &vs.value),
                Statement::Vars(l) => {
                    for vs in l {
                        add(&vs.name, &vs.var_type.type_path, &vs.value);
                    }
                }
                Statement::ForList(fl) => {
                    locals.insert(fl.name.as_str().to_string());
                    if let Some(vt) = &fl.var_type {
                        if is_act_path(&vt.type_path) {
                            acts.insert(fl.name.as_str().to_string());
                        }
                    }
                }
                _ => {}
            }
            for nb in stmt_blocks(&st.elem) {
                walk(nb, acts, locals, try_calls, is_act_path);
            }
        }
    }
    walk(code, &mut acts, &mut locals, try_calls, &is_act_path);
    (acts, locals)
}

#[allow(dead_code)]
fn unused(e: &Expression) {
    walk_expr(e, &mut |_| {});
}

/// Exact source positions of bare names used as named call arguments, not entity assignments.
/// The parser represents both as AssignOp; the enclosing call argument is the distinction.
pub fn named_argument_positions(sem: &super::Sem, file: &str) -> BTreeSet<(usize, usize)> {
    let mut positions = BTreeSet::new();
    for (_, owner, name) in sem.defs_in(file) {
        let Some(proc) = sem.proc_ref(owner, name) else { continue };
        let body = sem.proc_body(proc);
        if body.file != file { continue; }
        let Some(code) = body.code else { continue };
        walk_block(code, &mut |expression, _| {
            let Expression::Base { term, follow } = expression else { return };
            let mut collect = |args: &[Expression]| {
                for arg in args {
                    let Expression::AssignOp { op: AssignOp::Assign, lhs, .. } = arg else { continue };
                    // Dotted lhs arguments are actual assignments, not argument names.
                    let Expression::Base { term: lhs_term, follow: lhs_follow } = strip_parens(lhs) else { continue };
                    if !lhs_follow.is_empty() || as_ident(strip_parens(lhs)).is_none() { continue; }
                    if sem.rel(lhs_term.location) == file {
                        positions.insert((lhs_term.location.line as usize, lhs_term.location.column as usize));
                    }
                }
            };
            match &term.elem {
                Term::Call(_, args) | Term::NewPrefab { args: Some(args), .. } | Term::NewImplicit { args: Some(args) } => collect(args),
                _ => {}
            }
            for item in follow.iter() {
                if let Follow::Call(_, _, args) = &item.elem { collect(args); }
            }
        });
    }
    positions
}
