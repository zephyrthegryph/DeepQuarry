//! Per-proc structural checks on the AST: ACT_TRY pairing, context escape, boolean returns.
//!
//! These look at one proc body at a time (they need the proc's own statements and the names of
//! its act-typed locals, nothing from other files), so they run on a partial model of just the
//! files that mention an action or a context (see `lints/sem_handlers.rs`).

use std::collections::{BTreeMap, BTreeSet};

use dm_syntax::{Expr, Statement};

use super::Sem;
use crate::model::expr::{as_call, as_ident, chain, form, literal, strip_groups, Args, Chain, Form, Hop, Lit, Root};
use crate::model::walk::{stmt_blocks, stmt_exprs, stmts, walk_block, walk_expr, Stmt};
use crate::model::Param;

/// Every call in the expression tree: the unscoped `foo(...)`, and methods `x.foo(...)` (name only), term first, then the hops.
fn calls_in(e: &Expr, f: &mut dyn FnMut(&str, Args<'_>)) {
    walk_expr(e, &mut |v| {
        if let Form::Chain(c) = &v.form {
            if let Root::Call { name, args } = &c.root {
                f(name, *args);
            }
            for h in &c.hops {
                if let Hop::Call { name, args, .. } = h {
                    f(name, *args);
                }
            }
        }
    });
}

fn is_not(h: &Hop<'_>) -> bool {
    matches!(h, Hop::Unary { op: "!", .. })
}

/// Calls that start a world action (the macro `ACT_TRY` must survive expansion as one of these).
pub const DEFAULT_TRY_CALLS: &[&str] = &["ACT_ATTEMPT", "ACT_TRY", "act_try", "e0_act_try"];
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
pub fn act_try_pairing(sem: &Sem, code: &[Statement], try_calls: &[&str], out: &mut Vec<Found>) {
    let mut seen_try = false;
    walk_block(code, &mut |v, _| {
        if let Some((n, _)) = v.node.and_then(as_call) {
            if try_calls.contains(&n) {
                seen_try = true;
            }
        }
    });
    if !seen_try {
        return;
    }
    let mut ctx = Pair { sem, try_calls, found: Vec::new() };
    let end = ctx.block(code, BTreeMap::new());
    if let Some(pending) = end {
        for (var, line) in pending {
            ctx.found.push(Found { rule: "act_try_unpaired", line, msg: format!("ACT_ATTEMPT into `{}` reaches the end of the proc without act_done or act_cancel", var) });
        }
    }
    ctx.found.sort_by_key(|f| (f.line, f.msg.clone()));
    ctx.found.dedup();
    out.extend(ctx.found);
}

struct Pair<'a> {
    sem: &'a Sem,
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
    fn is_try(&self, e: &Expr) -> bool {
        matches!(as_call(strip_groups(e)), Some((n, _)) if self.try_calls.contains(&n))
    }

    /// Closes every `act_done(X)` / `act_cancel(X)` in `e`.
    fn closes(&self, e: &Expr, pending: &mut Pending) {
        calls_in(e, &mut |n, args| {
            if CLOSE_CALLS.contains(&n) {
                if let Some(id) = args.first().and_then(|a| as_ident(strip_groups(a))) {
                    pending.remove(id);
                }
            }
        });
    }

    fn block(&mut self, b: &[Statement], mut pending: Pending) -> Option<Pending> {
        for st in stmts(b) {
            let line = self.sem.line(Some(st.site));
            match &st.stmt {
                Stmt::Return(e) => {
                    let mut p = pending.clone();
                    if let Some(e) = e {
                        self.closes(e, &mut p);
                    }
                    for (var, at) in p {
                        self.found.push(Found { rule: "act_try_unpaired", line: at, msg: format!("ACT_ATTEMPT into `{}` is returned past at line {} without act_done or act_cancel", var, line) });
                    }
                    return None;
                }
                Stmt::Throw(_) | Stmt::Crash(_) => return None,
                Stmt::If { arms, else_arm } => {
                    let mut outs: Vec<Pending> = Vec::new();
                    let mut on_false = pending.clone();
                    for &(cond, blk) in arms {
                        self.closes(cond, &mut on_false);
                        let mut inner = on_false.clone();
                        for x in null_tested(cond) {
                            inner.remove(&x);
                        }
                        if let Some(o) = self.block(blk, inner) {
                            outs.push(o);
                        }
                        for x in non_null_tested(cond) {
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
                Stmt::Expr(fm, node) => self.simple(fm, *node, line, &mut pending),
                // `var/a = x` is one declaration; `var/a = x, b = y` (several on one line) only records the ones that start an act.
                Stmt::Vars(list) if list.len() == 1 => {
                    if let Some(v) = list[0].value {
                        if self.is_try(v) {
                            pending.insert(list[0].name.clone(), line);
                        } else {
                            self.closes(v, &mut pending);
                        }
                    }
                }
                Stmt::Vars(list) => {
                    for vs in list {
                        if let Some(v) = vs.value {
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
                    let is_switch = matches!(other, Stmt::Switch { default: Some(_), .. });
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

    /// An expression statement: `fm` is its form, `node` its expression (none for an assignment statement).
    fn simple(&mut self, fm: &Form<'_>, node: Option<&Expr>, line: u32, pending: &mut Pending) {
        match fm {
            Form::Assign { op: "=", lhs, rhs } if self.is_try(rhs) => {
                if let Some(id) = as_ident(strip_groups(lhs)) {
                    pending.insert(id.to_string(), line);
                } else {
                    self.found.push(Found { rule: "act_try_unpaired", line, msg: "ACT_ATTEMPT result is stored where act_done cannot name it; assign it to a local".to_string() });
                }
            }
            _ if node.is_some_and(|e| self.is_try(e)) => {
                self.found.push(Found { rule: "act_try_unpaired", line, msg: "ACT_ATTEMPT result is dropped: nothing can act_done or act_cancel it".to_string() });
            }
            Form::Assign { lhs, rhs, .. } => {
                // The assignment node itself holds no call: its two sides do.
                self.closes(lhs, pending);
                self.closes(rhs, pending);
            }
            _ => {
                if let Some(e) = node {
                    self.closes(e, pending);
                }
            }
        }
    }
}

/// Idents the condition proves null (or the ACT_PASS sentinel) when TRUE: `!X`, `isnull(X)`,
/// `X == null`, `X == (-1)`.
fn null_tested(c: &Expr) -> Vec<String> {
    let mut out = Vec::new();
    let c = strip_groups(c);
    match form(c) {
        Form::Chain(ch) => {
            if ch.hops.len() == 1 && is_not(&ch.hops[0]) {
                if let Root::Ident(n) = &ch.root {
                    out.push(n.to_string());
                }
                if let Root::Group(inner) = &ch.root {
                    // !(X)
                    if let Some(id) = as_ident(strip_groups(inner)) {
                        out.push(id.to_string());
                    }
                }
            }
            if ch.hops.is_empty() {
                if let Root::Call { name, args } = &ch.root {
                    if *name == "isnull" {
                        if let Some(id) = args.first().and_then(|a| as_ident(strip_groups(a))) {
                            out.push(id.to_string());
                        }
                    }
                }
                // ACT_REFUSED_BY(X) after expansion: an ACT_ATTEMPT refusal carries no act to close.
                if let Some(id) = refusal_tested(&ch) {
                    out.push(id);
                }
            }
        }
        Form::Binary { op: "==", lhs, rhs } => {
            for (a, b) in [(lhs, rhs), (rhs, lhs)] {
                if let Some(id) = as_ident(strip_groups(a)) {
                    if is_null_or_sentinel(b) {
                        out.push(id.to_string());
                    }
                }
            }
        }
        Form::Binary { op: "||", lhs, rhs } => {
            out.extend(null_tested(lhs));
            out.extend(null_tested(rhs));
        }
        _ => {}
    }
    out
}

/// `istype(X, /datum/act_refusal)` (the expansion of ACT_REFUSED_BY(X)): X. `c` is the call's chain (its root is what is read).
fn refusal_tested(c: &Chain<'_>) -> Option<String> {
    if let Root::Call { name, args } = &c.root {
        if *name == "istype" && args.len() == 2 {
            let path = format!("{:?}", args.get(1)?);
            if path.contains("act_refusal") {
                return as_ident(strip_groups(args.get(0)?)).map(|s| s.to_string());
            }
        }
    }
    None
}

/// Idents the condition proves non-null when TRUE (`if(X)`, `X != null`, `!ACT_REFUSED_BY(X)`), so the else path has them null.
fn non_null_tested(c: &Expr) -> Vec<String> {
    let mut out = Vec::new();
    let c = strip_groups(c);
    let fm = form(c);
    if let Form::Chain(ch) = &fm {
        if ch.hops.len() == 1 && is_not(&ch.hops[0]) {
            let inner = match &ch.root {
                Root::Group(e) => match chain(strip_groups(e)) {
                    Some(ic) if ic.hops.is_empty() => refusal_tested(&ic),
                    _ => None,
                },
                _ => refusal_tested(ch),
            };
            if let Some(id) = inner {
                out.push(id);
            }
        }
    }
    match &fm {
        Form::Chain(ch) if ch.hops.is_empty() => {
            if let Root::Ident(n) = &ch.root {
                out.push(n.to_string());
            }
        }
        Form::Binary { op: "!=" | "<>", lhs, rhs } => {
            for (a, b) in [(lhs, rhs), (rhs, lhs)] {
                if let Some(id) = as_ident(strip_groups(a)) {
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

fn is_null_or_sentinel(e: &Expr) -> bool {
    let e = strip_groups(e);
    if let Some(c) = chain(e) {
        if let Root::Literal(text) = &c.root {
            match (literal(text), c.hops.len()) {
                (Lit::Null, 0) => return true,
                // (-1): the ACT_PASS sentinel after expansion.
                (Lit::Int(i), 0) if i < 0 => return true,
                (Lit::Int(1), 1) if matches!(c.hops[0], Hop::Unary { op: "-", .. }) => return true,
                _ => {}
            }
        }
    }
    false
}

// ---- context escape -----------------------------------------------------------------------------

/// "A pooled datum/act may not be stored in a var or passed in with =; use A.snapshot()."
/// `acts` are the proc's act-typed idents (params and locals).
pub fn context_escape(sem: &Sem, code: &[Statement], acts: &BTreeSet<String>, locals: &BTreeSet<String>, out: &mut Vec<Found>) {
    if acts.is_empty() {
        return;
    }
    let is_act = |e: &Expr| -> Option<String> {
        let id = as_ident(strip_groups(e))?;
        acts.contains(id).then(|| id.to_string())
    };
    fn check_args(args: Args<'_>, what: &str, line: u32, is_act: &dyn Fn(&Expr) -> Option<String>, out: &mut Vec<Found>) {
        for a in args.iter() {
            // A named argument `with = A`.
            if let Form::Assign { op: "=", rhs, .. } = form(a) {
                if let Some(n) = is_act(rhs) {
                    out.push(Found { rule: "context_escape", line, msg: format!("`{}` is passed in with = to {}; use {}.snapshot()", n, what, n) });
                }
            }
        }
    }
    // The assignments that are named call arguments, by where they start (an expanded offset: a node's identity, stable where the
    // parts of an interpolated string are parsed on the fly).
    let mut named_args: Vec<usize> = Vec::new();
    walk_block(code, &mut |v, site| {
        let line = sem.line(Some(site));
        match &v.form {
            Form::Assign { lhs, rhs, .. } => {
                // A named call argument (`with = A`) is reported by its call, not as a store.
                if v.node.is_some() && named_args.contains(&(v.site.0 as usize)) {
                    return;
                }
                if let Some(a) = is_act(rhs) {
                    // Storing into a plain local is an alias for the trigger; anything else outlives it.
                    let local = as_ident(strip_groups(lhs)).map(|n| locals.contains(n)).unwrap_or(false);
                    if !local {
                        out.push(Found { rule: "context_escape", line, msg: format!("`{}` is a pooled context and is stored where it can outlive the trigger; use {}.snapshot()", a, a) });
                    }
                }
            }
            Form::Chain(c) => {
                let mut note_named = |args: Args<'_>| {
                    if let Some(node) = v.node {
                        for a in args.iter() {
                            if matches!(form(a), Form::Assign { op: "=", .. }) {
                                named_args.push(v.site.0 as usize + a.span.start - node.span.start);
                            }
                        }
                    }
                };
                match &c.root {
                    Root::Call { args, .. } | Root::NewPrefab { args: Some(args), .. } | Root::NewImplicit { args: Some(args) } => note_named(*args),
                    _ => {}
                }
                for h in &c.hops {
                    if let Hop::Call { args, .. } = h {
                        note_named(*args);
                    }
                }
                match &c.root {
                    Root::Call { name, args } => check_args(*args, name, line, &is_act, out),
                    Root::List(args) => {
                        for a in args.iter() {
                            if let Some(n) = is_act(a) {
                                out.push(Found { rule: "context_escape", line, msg: format!("`{}` is put in a list; use {}.snapshot()", n, n) });
                            }
                        }
                    }
                    Root::NewPrefab { args: Some(args), .. } | Root::NewImplicit { args: Some(args) } => check_args(*args, "new", line, &is_act, out),
                    _ => {}
                }
                for h in &c.hops {
                    if let Hop::Call { name, args, .. } = h {
                        check_args(*args, name, line, &is_act, out);
                        if matches!(*name, "Add" | "Insert") {
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

/// A condition or transitional req_bool callback answers TRUE or FALSE. A string, a type or a non-boolean number
/// would read as TRUE and silently allow the op, so a definite non-boolean return is an error.
pub fn boolean_returns(sem: &Sem, code: &[Statement], out: &mut Vec<Found>) {
    fn visit(sem: &Sem, b: &[Statement], out: &mut Vec<Found>) {
        for st in stmts(b) {
            if let Stmt::Return(e) = &st.stmt {
                let line = sem.line(Some(st.site));
                match e {
                    None => out.push(Found { rule: "requirement_return", line, msg: "a bare `return` answers null; a condition or req_bool callback must answer TRUE or FALSE".to_string() }),
                    Some(e) => {
                        if let Some(why) = non_boolean(e) {
                            out.push(Found { rule: "requirement_return", line, msg: format!("returns {}: a condition or req_bool callback answers TRUE or FALSE", why) });
                        }
                    }
                }
            }
            for nb in stmt_blocks(&st.stmt) {
                visit(sem, nb, out);
            }
        }
    }
    visit(sem, code, out);
}

/// Final requirements return null (allow) or a refusal. Unknown callback return types are
/// checked by the engine; reject only expressions whose invalid shape is definite here.
pub fn requirement_returns(sem: &Sem, code: &[Statement], out: &mut Vec<Found>) {
    fn visit(sem: &Sem, block: &[Statement], out: &mut Vec<Found>) {
        for statement in stmts(block) {
            if let Stmt::Return(Some(expression)) = &statement.stmt {
                if let Some(why) = non_reason(expression) {
                    out.push(Found {
                        rule: "requirement_return",
                        line: sem.line(Some(statement.site)),
                        msg: format!("returns {}: req callbacks return null to allow, or text/a refusal datum to refuse; use req_bool only for transitional boolean callbacks", why),
                    });
                }
            }
            for nested in stmt_blocks(&statement.stmt) {
                visit(sem, nested, out);
            }
        }
    }
    visit(sem, code, out);
}

fn non_reason(expression: &Expr) -> Option<&'static str> {
    let expression = strip_groups(expression);
    match form(expression) {
        Form::Chain(c) => {
            if c.hops.iter().any(is_not) {
                return Some("a boolean");
            }
            match &c.root {
                Root::Literal(text) => match literal(text) {
                    Lit::Int(_) | Lit::Float(_) => Some("a number/boolean"),
                    _ => None,
                },
                Root::List(_) => Some("a list"),
                Root::Prefab { path, .. } => {
                    // The path's names, whatever operator joins them.
                    let path = path.split(['/', '.', ':']).filter(|s| !s.is_empty()).collect::<Vec<_>>().join("/");
                    if path == "datum/msg" || path.starts_with("datum/msg/") { None } else { Some("a non-refusal type path") }
                }
                _ => None,
            }
        }
        Form::Binary { op: "==" | "!=" | "<>", .. } => Some("a boolean comparison"),
        Form::Ternary { then_value, else_value, .. } => non_reason(then_value).or_else(|| non_reason(else_value)),
        _ => None,
    }
}

fn non_boolean(e: &Expr) -> Option<&'static str> {
    let e = strip_groups(e);
    match form(e) {
        Form::Chain(c) => {
            if c.hops.iter().any(is_not) {
                return None;
            }
            match &c.root {
                Root::Literal(text) => match literal(text) {
                    Lit::String(_) | Lit::Interp(_) => Some("text"),
                    Lit::Null => Some("null"),
                    Lit::Int(i) if i != 0 && i != 1 => Some("a number other than TRUE/FALSE"),
                    Lit::Float(_) => Some("a number other than TRUE/FALSE"),
                    _ => None,
                },
                Root::Prefab { .. } => Some("a type path"),
                Root::List(_) => Some("a list"),
                _ => None,
            }
        }
        Form::Ternary { then_value, else_value, .. } => non_boolean(then_value).or_else(|| non_boolean(else_value)),
        _ => None,
    }
}

/// Locals and params of a proc that are act-typed, by declared type path.
pub fn act_idents(params: &[Param], code: &[Statement], try_calls: &[&str]) -> (BTreeSet<String>, BTreeSet<String>) {
    let mut acts = BTreeSet::new();
    let mut locals = BTreeSet::new();
    let is_act_path = |p: &[String]| p.len() >= 2 && p[0] == "datum" && p[1] == "act";
    for p in params {
        locals.insert(p.name.clone());
        if is_act_path(&p.type_path) {
            acts.insert(p.name.clone());
        }
    }
    fn walk(b: &[Statement], acts: &mut BTreeSet<String>, locals: &mut BTreeSet<String>, try_calls: &[&str], is_act_path: &dyn Fn(&[String]) -> bool) {
        for st in stmts(b) {
            let mut add = |name: &str, tp: &[String], v: Option<&Expr>| {
                locals.insert(name.to_string());
                if is_act_path(tp) {
                    acts.insert(name.to_string());
                } else if let Some(e) = v {
                    if matches!(as_call(strip_groups(e)), Some((n, _)) if try_calls.contains(&n)) {
                        acts.insert(name.to_string());
                    }
                }
            };
            match &st.stmt {
                Stmt::Vars(list) => {
                    for vs in list {
                        add(&vs.name, &vs.type_path, vs.value);
                    }
                }
                Stmt::ForList { binding, .. } => {
                    locals.insert(binding.name.clone());
                    if let Some(vt) = &binding.decl {
                        if is_act_path(&vt.type_path) {
                            acts.insert(binding.name.clone());
                        }
                    }
                }
                _ => {}
            }
            for nb in stmt_blocks(&st.stmt) {
                walk(nb, acts, locals, try_calls, is_act_path);
            }
        }
    }
    walk(code, &mut acts, &mut locals, try_calls, &is_act_path);
    (acts, locals)
}

/// Exact source positions of bare names used as named call arguments, not entity assignments.
/// The parser represents both as assignments; the enclosing call argument is the distinction.
pub fn named_argument_positions(sem: &super::Sem, file: &str) -> BTreeSet<(usize, usize)> {
    let mut positions = BTreeSet::new();
    for (_, owner, name) in sem.defs_in(file) {
        let Some(proc) = sem.proc_ref(owner, name) else { continue };
        let body = sem.proc_body(proc);
        if body.file != file { continue }
        let Some(code) = body.code else { continue };
        walk_block(code, &mut |v, _| {
            let Form::Chain(c) = &v.form else { return };
            let mut collect = |args: Args<'_>| {
                for arg in args.iter() {
                    let Form::Assign { op: "=", lhs, .. } = form(arg) else { continue };
                    // Dotted lhs arguments are actual assignments, not argument names.
                    let lhs = strip_groups(lhs);
                    if as_ident(lhs).is_none() { continue }
                    let site = crate::model::Site(lhs.span.start as u32);
                    if sem.rel(Some(site)) == file {
                        if let Some((_, line, column)) = sem.m().line_column(site) {
                            positions.insert((line as usize, column as usize));
                        }
                    }
                }
            };
            match &c.root {
                Root::Call { args, .. } | Root::List(args) | Root::NewPrefab { args: Some(args), .. } | Root::NewImplicit { args: Some(args) } => collect(*args),
                _ => {}
            }
            for h in &c.hops {
                if let Hop::Call { args, .. } = h { collect(*args); }
            }
        });
    }
    positions
}

/// Exact self slot-flags reads that are the old value of a registered tracked setter
/// mutation. No conditions or arbitrary callback arguments receive this treatment.
pub fn slot_flags_mutation_positions(sem: &super::Sem, decls: &super::decls::Decls, file: &str) -> BTreeSet<(usize, usize)> {
    fn mask(e: &Expr) -> bool {
        let e = strip_groups(e);
        match form(e) {
            Form::Binary { op: "&" | "|" | "^" | "<<" | ">>", lhs, rhs } => mask(lhs) && mask(rhs),
            Form::Chain(c) => {
                if !c.hops.iter().all(|h| matches!(h, Hop::Unary { op: "~" | "-", .. })) { return false; }
                match &c.root {
                    Root::Literal(text) => matches!(literal(text), Lit::Int(_) | Lit::Float(_)),
                    Root::Ident(n) => *n != "slot_flags" && *n != "src",
                    Root::Group(inner) => mask(inner),
                    _ => false,
                }
            }
            _ => false,
        }
    }
    fn shadows(b: &[Statement]) -> bool {
        stmts(b).iter().any(|s| match &s.stmt {
            Stmt::Vars(v) if v.iter().any(|x| x.name.as_str() == "slot_flags") => true,
            Stmt::ForList { binding, .. } if binding.decl.is_some() && binding.name.as_str() == "slot_flags" => true,
            Stmt::ForKeyValue { binding, value, .. } if binding.decl.is_some() && (binding.name.as_str() == "slot_flags" || *value == "slot_flags") => true,
            other => stmt_blocks(other).iter().any(|b| shadows(b)),
        })
    }
    let mut positions = BTreeSet::new();
    for (_, owner, name) in sem.defs_in(file) {
        if !decls.tracked.iter().any(|(ty, vars)| vars.contains("slot_flags") && sem.is_subtype(owner, ty)) { continue; }
        let Some(setter) = sem.proc_ref(owner, "set_slot_flags") else { continue; };
        if setter.is_builtin() { continue; }
        let Some(proc) = sem.proc_ref(owner, name) else { continue; };
        let body = sem.proc_body(proc);
        if body.file != file { continue; }
        let Some(code) = body.code else { continue; };
        let shadowed = body.params.iter().any(|p| p.name.as_str() == "slot_flags") || shadows(code);
        walk_block(code, &mut |v, _| {
            let Form::Chain(c) = &v.form else { return; };
            let args = match (&c.root, c.hops.as_slice()) {
                (Root::Call { name: "set_slot_flags", args }, []) => args,
                (Root::Ident("src"), [Hop::Call { name: "set_slot_flags", args, .. }]) => args,
                _ => return,
            };
            if args.len() != 1 { return; }
            let Form::Binary { op: "&", lhs, rhs } = form(strip_groups(args.first().unwrap())) else { return; };
            if !mask(rhs) { return; }
            let Some(lc) = chain(strip_groups(lhs)) else { return; };
            let extra = match (&lc.root, lc.hops.as_slice()) {
                (Root::Ident("slot_flags"), []) if !shadowed => 0,
                (Root::Ident("src"), [Hop::Field { name: "slot_flags", .. }]) => 4,
                _ => return,
            };
            let site = lc.root_site();
            if sem.rel(Some(site)) == file {
                if let Some((_, line, column)) = sem.m().line_column(site) {
                    positions.insert((line as usize, column as usize + extra));
                }
            }
        });
    }
    positions
}

// Prove direct fields whose declared receiver cannot be a client. An action's
// borrowed holder and a pending operation's owner are ordinary engine references,
// not the admin datum reached through client.holder. Unknown receivers stay debt.
pub fn act_holder_positions(sem: &super::Sem, file: &str, text: &str) -> BTreeSet<(usize, usize)> {
    /// A declared type path, none when untyped.
    fn declared(path: String) -> Option<String> {
        (!path.is_empty()).then_some(path)
    }
    fn collect(b: &[Statement], types: &mut BTreeMap<String, Option<String>>) {
        for s in stmts(b) {
            let mut add = |name: &str, ty: Option<String>| {
                if types.contains_key(name) { types.insert(name.to_owned(), None); }
                else { types.insert(name.to_owned(), ty); }
            };
            match &s.stmt {
                Stmt::Vars(vs) => for v in vs { add(v.name.as_str(), declared(v.declared())); },
                Stmt::ForList { binding, .. } => add(binding.name.as_str(), binding.decl.as_ref().and_then(|d| declared(d.declared()))),
                Stmt::ForKeyValue { binding, value, .. } => { add(binding.name.as_str(), None); add(value, None); },
                _ => {}
            }
            for child in stmt_blocks(&s.stmt) { collect(child, types); }
        }
    }
    let mut positions = BTreeSet::new();
    for (_, owner, name) in sem.defs_in(file) {
        let Some(proc) = sem.proc_ref(owner, name) else { continue; };
        let body = sem.proc_body(proc);
        if body.file != file { continue; }
        let Some(code) = body.code else { continue; };
        let mut types: BTreeMap<String, Option<String>> = body.params.iter().map(|p| (p.name.to_string(), declared(p.declared()))).collect();
        collect(code, &mut types);
        walk_block(code, &mut |v, _| {
            let Form::Chain(c) = &v.form else { return; };
            let (Root::Ident(receiver), [Hop::Field { name: "holder", .. }]) = (&c.root, c.hops.as_slice()) else { return; };
            let ty = if *receiver == "src" { Some(owner.as_str()) }
                else { types.get(*receiver).and_then(|ty| ty.as_deref()) };
            let Some(ty) = ty else { return; };
            // A broad ancestor of /client is not sufficient proof either: an actual
            // client may inhabit it. Require a real declared field on a disjoint type.
            if sem.ty(ty).is_none() || sem.is_subtype(ty, "/client") || sem.is_subtype("/client", ty) || sem.var_owner(ty, "holder").is_none() { return; }
            let site = c.root_site();
            if sem.rel(Some(site)) != file { return; }
            let Some((_, line_no, column)) = sem.m().line_column(site) else { return; };
            let Some(line) = text.lines().nth(line_no as usize - 1) else { return; };
            let start = column as usize - 1;
            let Some(tail) = line.get(start..) else { return; };
            let Some(after_name) = tail.strip_prefix(*receiver) else { return; };
            let optional = after_name.starts_with('?');
            if !(after_name.starts_with(".holder") || after_name.starts_with("?.holder")) { return; }
            positions.insert((line_no as usize, start + receiver.len() + usize::from(optional) + 1));
        });
    }
    positions
}
