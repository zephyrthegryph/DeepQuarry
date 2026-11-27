//! Actor type tests reachable from an op handler, on the typed tree (`silicon_entry`'s `handler_actor_check` and
//! `helper_actor_check`).
//!
//! A handler is a proc that takes a `/datum/act` (an op's effect, requirement or condition), except a timer's context
//! (`datum/act/timer`: simulation work, not input) and a prompt's `prepare()` (eligibility for an admitted request). In a
//! handler the act's `actor` is tainted, and so is every local assigned from it; a call that passes the actor (or the act)
//! carries the taint into the callee's parameter at that position, recursively (the helpers). An actor type test is
//! `istype(<tainted>, /mob/living/silicon...)`, which is what `isAI()`, `issilicon()`, `isrobot()` and `ispAI()` expand to.
//!
//! * `handler_actor_check`: a line of the handler spells one of the four macros (any argument: the text rule this replaces,
//!   with the handler found on the tree instead of by its header line).
//! * `handler_actor_istype`: the handler tests the actor's type with a literal `istype()` (which the text rule never saw).
//! * `helper_actor_check`: the test is in a proc the handler reaches with the actor.

use std::collections::{BTreeMap, BTreeSet, HashSet};

use dm_syntax::{Expr, Statement};

use super::Sem;
use crate::model::expr::{as_ident, chain, form, strip_groups, Args, Chain, Form, Hop, Root};
use crate::model::procs::Proc;
use crate::model::walk::{stmt_blocks, stmt_exprs, stmts, walk_expr, ForInit, Stmt, Visit};
use crate::model::{Param, Site};

/// Where the old tree placed a control's condition: at the `(` it is read after (`if (x)`), which the condition's own span leaves out.
fn condition_site(sem: &Sem, condition: &Expr) -> Site {
    let text = sem.m().frontend().expanded.text.as_str();
    Site(dm_syntax::control_open_paren(text, condition.span.start).unwrap_or(condition.span.start) as u32)
}

/// Every expression in a block with the line it is on: like `walk_block`, but an `if` / `else if` arm's condition carries
/// its own line (a chain is one statement in the tree).
fn walk_lines(sem: &Sem, b: &[Statement], f: &mut dyn FnMut(&Visit<'_>, u32)) {
    for st in stmts(b) {
        let line = sem.line(Some(st.site));
        if let Stmt::If { arms, .. } = &st.stmt {
            for &(c, _) in arms {
                let at = sem.line(Some(condition_site(sem, c)));
                walk_expr(c, &mut |x| f(x, at));
            }
        } else {
            for e in stmt_exprs(&st.stmt) {
                walk_expr(e, &mut |x| f(x, line));
            }
            // An assignment statement has no node of its own: its two sides are the expressions.
            if let Stmt::Expr(Form::Assign { lhs, rhs, .. }, None) = &st.stmt {
                walk_expr(lhs, &mut |x| f(x, line));
                walk_expr(rhs, &mut |x| f(x, line));
            }
        }
        // A sized list with no value starts as `new /list(sizes)`: the sizes are expressions of the statement.
        if let Stmt::Vars(vs) = &st.stmt {
            for v in vs.iter().filter(|v| v.value.is_none()) {
                for e in &v.suffix_args {
                    walk_expr(e, &mut |x| f(x, line));
                }
            }
        }
        if let Stmt::ForLoop { init, inc, .. } = &st.stmt {
            match init {
                Some(ForInit::Var(d)) => {
                    if let Some(e) = d.value {
                        walk_expr(e, &mut |x| f(x, line));
                    } else {
                        for e in &d.suffix_args {
                            walk_expr(e, &mut |x| f(x, line));
                        }
                    }
                }
                Some(ForInit::Expr(e)) => walk_expr(e, &mut |x| f(x, line)),
                None => {}
            }
            if let Some(e) = inc {
                walk_expr(e, &mut |x| f(x, line));
            }
        }
        for nb in stmt_blocks(&st.stmt) {
            walk_lines(sem, nb, f);
        }
    }
}

/// How deep a helper chain is followed from a handler.
const MAX_DEPTH: usize = 8;

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct ActorTest {
    pub rule: &'static str,
    pub rel: String,
    pub line: u32,
    /// The handler the test is reached from (`/type/proc/name`).
    pub handler: String,
    /// The tested type.
    pub tested: String,
}

fn type_path_of(tp: &[String]) -> String {
    format!("/{}", tp.join("/"))
}

fn is_act(tp: &[String]) -> bool {
    tp.len() >= 2 && tp[0] == "datum" && tp[1] == "act"
}

/// A handler: a `/datum/act` parameter other than a timer context, and not a prompt's `prepare()`.
pub fn is_handler(owner: &str, name: &str, params: &[Param]) -> bool {
    let mut any = false;
    for p in params {
        let tp = &p.type_path;
        if is_act(tp) {
            if tp.len() >= 3 && tp[2] == "timer" {
                return false;
            }
            any = true;
        }
    }
    if !any {
        return false;
    }
    !(name == "prepare" && owner.starts_with("/datum/prompt/"))
}

fn prefab_path(e: &Expr) -> Option<String> {
    let c = chain(strip_groups(e))?;
    if !c.hops.is_empty() {
        return None;
    }
    if let Root::Prefab { path, .. } = &c.root {
        // The path's names, whatever operator joins them.
        return Some(format!("/{}", path.split(['/', '.', ':']).filter(|n| !n.is_empty()).collect::<Vec<_>>().join("/")));
    }
    None
}

fn silicon_type(path: &str) -> bool {
    path == "/mob/living/silicon" || path.starts_with("/mob/living/silicon/")
}

/// The taint of one proc body: the names holding the act and the names holding the actor.
#[derive(Clone, Default, Debug)]
struct Taint {
    acts: BTreeSet<String>,
    actors: BTreeSet<String>,
}

impl Taint {
    fn is_act(&self, e: &Expr) -> bool {
        as_ident(strip_groups(e)).is_some_and(|n| self.acts.contains(n))
    }

    /// `A.actor` (an act's actor), or a name holding the actor.
    fn is_actor(&self, e: &Expr) -> bool {
        match form(strip_groups(e)) {
            Form::Chain(c) => match (&c.root, c.hops.as_slice()) {
                (Root::Ident(n), []) => self.actors.contains(*n),
                (Root::Ident(n), [Hop::Field { name: "actor", .. }]) => self.acts.contains(*n),
                _ => false,
            },
            Form::Ternary { then_value, else_value, .. } => self.is_actor(then_value) || self.is_actor(else_value),
            _ => false,
        }
    }

    /// Spreads the taint through the body's assignments until nothing changes (flow-insensitive).
    fn close_over(&mut self, code: &[Statement]) {
        loop {
            let before = (self.acts.len(), self.actors.len());
            self.assign_block(code);
            if (self.acts.len(), self.actors.len()) == before {
                break;
            }
        }
    }

    fn take(&mut self, name: &str, value: &Expr) {
        if self.is_actor(value) {
            self.actors.insert(name.to_string());
        } else if self.is_act(value) {
            self.acts.insert(name.to_string());
        }
    }

    fn assign_block(&mut self, b: &[Statement]) {
        for st in stmts(b) {
            match &st.stmt {
                Stmt::Vars(vs) => {
                    for v in vs {
                        if let Some(value) = v.value {
                            self.take(&v.name, value);
                        }
                    }
                }
                Stmt::Expr(Form::Assign { op: "=", lhs, rhs }, _) => {
                    if let Some(n) = as_ident(strip_groups(lhs)) {
                        let n = n.to_string();
                        self.take(&n, rhs);
                    }
                }
                _ => {}
            }
            for nb in stmt_blocks(&st.stmt) {
                self.assign_block(nb);
            }
        }
    }
}

/// Declared object types of a body's names (params and `var/T/x` locals), for resolving `x.proc()`.
fn declared_types(params: &[Param], code: &[Statement]) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    for p in params {
        if !p.type_path.is_empty() {
            out.insert(p.name.to_string(), type_path_of(&p.type_path));
        }
    }
    fn walk(b: &[Statement], out: &mut BTreeMap<String, String>) {
        for st in stmts(b) {
            if let Stmt::Vars(vs) = &st.stmt {
                for v in vs {
                    if !v.type_path.is_empty() {
                        out.insert(v.name.to_string(), type_path_of(&v.type_path));
                    }
                }
            }
            for nb in stmt_blocks(&st.stmt) {
                walk(nb, out);
            }
        }
    }
    walk(code, &mut out);
    out
}

/// A call in a body and the proc it resolves to: `(callee owner, callee name, arguments)`.
fn calls<'c>(sem: &Sem, owner: &str, types: &BTreeMap<String, String>, c: &Chain<'c>, out: &mut Vec<(String, String, Args<'c>)>) {
    let resolve_on = |ty: &str, name: &str| -> Option<String> {
        let p = sem.proc_ref(ty, name)?;
        Some(p.owner().path().to_string())
    };
    if let Root::Call { name: n, args } = &c.root {
        if c.hops.is_empty() || !matches!(c.hops[0], Hop::Call { .. }) {
            if let Some(o) = resolve_on(owner, n).or_else(|| sem.global_proc(n).map(|_| "/".to_string())) {
                out.push((o, n.to_string(), *args));
            }
        }
    }
    // `x.foo(...)` with `x` a name of a declared type, or `src`.
    if let (Root::Ident(recv), [Hop::Call { name: n, args, .. }]) = (&c.root, c.hops.as_slice()) {
        let ty = if *recv == "src" { Some(owner.to_string()) } else { types.get(*recv).cloned() };
        if let Some(ty) = ty {
            if let Some(o) = resolve_on(&ty, n) {
                out.push((o, n.to_string(), *args));
            }
        }
    }
}

struct Walker<'s> {
    sem: &'s Sem,
    found: Vec<ActorTest>,
    visited: HashSet<(String, String, Vec<usize>, Vec<usize>)>,
    macro_re: &'s crate::pat::Pat,
    lines: &'s dyn Fn(&str, u32) -> Option<String>,
}

impl<'s> Walker<'s> {
    fn body(&mut self, handler: &str, owner: &str, params: &[Param], code: &[Statement], rel: &str, taint: Taint, depth: usize) {
        let mut taint = taint;
        taint.close_over(code);
        let types = declared_types(params, code);
        let direct = depth == 0;
        let mut pending: Vec<(String, String, Vec<usize>, Vec<usize>)> = Vec::new();
        let sem = self.sem;
        let mut found: Vec<ActorTest> = Vec::new();
        let mut macro_lines: BTreeSet<u32> = BTreeSet::new();
        walk_lines(sem, code, &mut |v, line| {
            if let Form::Chain(c) = &v.form {
                if let (Root::Call { name: "istype", args }, true) = (&c.root, c.hops.is_empty()) {
                    if args.len() == 2 && taint.is_actor(args.get(0).unwrap()) {
                        if let Some(p) = prefab_path(args.get(1).unwrap()).filter(|p| silicon_type(p)) {
                            found.push(ActorTest {
                                rule: if direct { "handler_actor_istype" } else { "helper_actor_check" },
                                rel: rel.to_string(),
                                line: super::procs::engine_line(&sem.root, rel, line),
                                handler: handler.to_string(),
                                tested: p,
                            });
                        }
                    }
                }
            }
            if direct {
                macro_lines.insert(super::procs::engine_line(&sem.root, rel, line));
            }
            if depth < MAX_DEPTH {
                if let Form::Chain(c) = &v.form {
                    let mut cs = Vec::new();
                    calls(sem, owner, &types, c, &mut cs);
                    for (o, n, args) in cs {
                        let actor_pos: Vec<usize> = args.iter().enumerate().filter(|(_, a)| taint.is_actor(a)).map(|(i, _)| i).collect();
                        let act_pos: Vec<usize> = args.iter().enumerate().filter(|(_, a)| taint.is_act(a)).map(|(i, _)| i).collect();
                        if actor_pos.is_empty() && act_pos.is_empty() {
                            continue;
                        }
                        pending.push((o, n, actor_pos, act_pos));
                    }
                }
            }
        });
        // The text rule this replaces: a line in a handler that spells one of the macros, whatever it tests.
        for line in macro_lines {
            if let Some(text) = (self.lines)(rel, line) {
                if self.macro_re.is_match(&text) {
                    found.retain(|f| f.line != line);
                    found.push(ActorTest { rule: "handler_actor_check", rel: rel.to_string(), line, handler: handler.to_string(), tested: "macro".to_string() });
                }
            }
        }
        self.found.extend(found);
        for (o, n, actor_pos, act_pos) in pending {
            if !self.visited.insert((o.clone(), n.clone(), actor_pos.clone(), act_pos.clone())) {
                continue;
            }
            let Some(p) = sem.proc_ref(&o, &n) else { continue };
            if p.is_builtin() {
                continue;
            }
            let Some(code) = p.body() else { continue };
            let parameters = p.parameters();
            // A handler is checked on its own (as a handler); following it again would only relabel its sites.
            if is_handler(&o, &n, &parameters) {
                continue;
            }
            let mut t = Taint::default();
            for i in actor_pos {
                if let Some(param) = parameters.get(i) {
                    t.actors.insert(param.name.to_string());
                }
            }
            for i in act_pos {
                if let Some(param) = parameters.get(i) {
                    t.acts.insert(param.name.to_string());
                }
            }
            let callee_rel = sem.rel(p.site());
            self.body(handler, &o, &parameters, code, &callee_rel, t, depth + 1);
        }
    }
}

/// Every actor type test reachable from a handler. `lines(rel, line)` reads a source line (for the macro spelling).
pub fn actor_tests(sem: &Sem, lines: &dyn Fn(&str, u32) -> Option<String>) -> Vec<ActorTest> {
    let macro_re = crate::pat!(r"(?<![\w.])(?:isAI|issilicon|isrobot|ispAI)\(");
    let mut w = Walker { sem, found: Vec::new(), visited: HashSet::new(), macro_re, lines };
    let mut handlers: Vec<(String, String, Proc<'_>)> = Vec::new();
    for ty in sem.m().types() {
        let owner = ty.path().to_string();
        for name in ty.proc_names() {
            for v in ty.proc_definitions(name) {
                if v.body().is_some() && is_handler(&owner, name, &v.parameters()) {
                    handlers.push((owner.clone(), name.to_string(), v));
                }
            }
        }
    }
    for (owner, name, v) in handlers {
        let Some(code) = v.body() else { continue };
        let parameters = v.parameters();
        let mut t = Taint::default();
        for p in parameters.iter() {
            if is_act(&p.type_path) {
                t.acts.insert(p.name.to_string());
            }
        }
        let rel = sem.rel(v.site());
        let handler = format!("{}/proc/{}", if owner == "/" { "" } else { owner.as_str() }, name);
        w.body(&handler, &owner, &parameters, code, &rel, t, 0);
    }
    let mut out = w.found;
    out.sort();
    // One site per line: a line a handler tests directly is not also a helper site of another handler.
    let direct: BTreeSet<(String, u32)> = out.iter().filter(|f| f.rule != "helper_actor_check").map(|f| (f.rel.clone(), f.line)).collect();
    let mut seen: BTreeSet<(&'static str, String, u32)> = BTreeSet::new();
    out.retain(|f| {
        if f.rule == "helper_actor_check" && direct.contains(&(f.rel.clone(), f.line)) {
            return false;
        }
        seen.insert((f.rule, f.rel.clone(), f.line))
    });
    out
}
