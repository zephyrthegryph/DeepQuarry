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

use dreammaker::ast::{AssignOp, Block, Expression, Follow, Parameter, Statement, Term};

use super::ast::{stmt_blocks, stmt_exprs, strip_parens, walk_expr};
use super::Sem;

/// Every expression in a block with the line it is on: like `ast::walk_block`, but an `if` / `else if` arm's condition carries
/// its own line (a chain is one statement in the tree).
fn walk_lines<'a>(b: &'a Block, f: &mut dyn FnMut(&'a Expression, u32)) {
    for st in b.iter() {
        let line = st.location.line;
        if let Statement::If { arms, .. } = &st.elem {
            for (c, _) in arms.iter() {
                walk_expr(&c.elem, &mut |x| f(x, c.location.line));
            }
        } else {
            for e in stmt_exprs(&st.elem) {
                walk_expr(e, &mut |x| f(x, line));
            }
        }
        if let Statement::ForLoop { init, inc, .. } = &st.elem {
            for s in [init, inc].into_iter().flatten() {
                for e in stmt_exprs(s) {
                    walk_expr(e, &mut |x| f(x, line));
                }
            }
        }
        for nb in stmt_blocks(&st.elem) {
            walk_lines(nb, f);
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
pub fn is_handler(owner: &str, name: &str, params: &[Parameter]) -> bool {
    let mut any = false;
    for p in params {
        let tp = &p.var_type.type_path;
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

fn prefab_path(e: &Expression) -> Option<String> {
    if let Expression::Base { term, follow } = strip_parens(e) {
        if follow.is_empty() {
            if let Term::Prefab(p) = &term.elem {
                return Some(format!("/{}", p.path.iter().map(|(_, n)| n.as_str()).collect::<Vec<_>>().join("/")));
            }
        }
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
    fn is_act(&self, e: &Expression) -> bool {
        match strip_parens(e) {
            Expression::Base { term, follow } if follow.is_empty() => matches!(&term.elem, Term::Ident(n) if self.acts.contains(n.as_str())),
            _ => false,
        }
    }

    /// `A.actor` (an act's actor), or a name holding the actor.
    fn is_actor(&self, e: &Expression) -> bool {
        match strip_parens(e) {
            Expression::Base { term, follow } => match (&term.elem, follow.len()) {
                (Term::Ident(n), 0) => self.actors.contains(n.as_str()),
                (Term::Ident(n), 1) => self.acts.contains(n.as_str()) && matches!(&follow[0].elem, Follow::Field(_, f) if f.as_str() == "actor"),
                _ => false,
            },
            Expression::TernaryOp { if_, else_, .. } => self.is_actor(if_) || self.is_actor(else_),
            _ => false,
        }
    }

    /// Spreads the taint through the body's assignments until nothing changes (flow-insensitive).
    fn close_over(&mut self, code: &Block) {
        loop {
            let before = (self.acts.len(), self.actors.len());
            self.assign_block(code);
            if (self.acts.len(), self.actors.len()) == before {
                break;
            }
        }
    }

    fn take(&mut self, name: &str, value: &Expression) {
        if self.is_actor(value) {
            self.actors.insert(name.to_string());
        } else if self.is_act(value) {
            self.acts.insert(name.to_string());
        }
    }

    fn assign_block(&mut self, b: &Block) {
        for st in b.iter() {
            match &st.elem {
                Statement::Var(v) => {
                    if let Some(value) = &v.value {
                        self.take(&v.name, value);
                    }
                }
                Statement::Vars(vs) => {
                    for v in vs {
                        if let Some(value) = &v.value {
                            self.take(&v.name, value);
                        }
                    }
                }
                Statement::Expr(Expression::AssignOp { op: AssignOp::Assign, lhs, rhs }) => {
                    if let Expression::Base { term, follow } = strip_parens(lhs) {
                        if follow.is_empty() {
                            if let Term::Ident(n) = &term.elem {
                                let n = n.to_string();
                                self.take(&n, rhs);
                            }
                        }
                    }
                }
                _ => {}
            }
            for nb in stmt_blocks(&st.elem) {
                self.assign_block(nb);
            }
        }
    }
}

/// Declared object types of a body's names (params and `var/T/x` locals), for resolving `x.proc()`.
fn declared_types(params: &[Parameter], code: &Block) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    for p in params {
        if !p.var_type.type_path.is_empty() {
            out.insert(p.name.to_string(), type_path_of(&p.var_type.type_path));
        }
    }
    fn walk(b: &Block, out: &mut BTreeMap<String, String>) {
        for st in b.iter() {
            match &st.elem {
                Statement::Var(v) if !v.var_type.type_path.is_empty() => {
                    out.insert(v.name.to_string(), type_path_of(&v.var_type.type_path));
                }
                Statement::Vars(vs) => {
                    for v in vs {
                        if !v.var_type.type_path.is_empty() {
                            out.insert(v.name.to_string(), type_path_of(&v.var_type.type_path));
                        }
                    }
                }
                _ => {}
            }
            for nb in stmt_blocks(&st.elem) {
                walk(nb, out);
            }
        }
    }
    walk(code, &mut out);
    out
}

/// A call in a body and the proc it resolves to: `(callee owner, callee name, arguments)`.
fn calls<'a>(sem: &'a Sem, owner: &str, types: &BTreeMap<String, String>, e: &'a Expression, out: &mut Vec<(String, String, &'a [Expression])>) {
    let resolve_on = |ty: &str, name: &str| -> Option<String> {
        let p = sem.proc_ref(ty, name)?;
        let path = &p.ty().get().path;
        Some(if path.is_empty() { "/".to_string() } else { path.clone() })
    };
    if let Expression::Base { term, follow } = e {
        match &term.elem {
            Term::Call(n, args) if follow.is_empty() || !matches!(follow[0].elem, Follow::Call(..)) => {
                if let Some(o) = resolve_on(owner, n.as_str()).or_else(|| sem.global_proc(n.as_str()).map(|_| "/".to_string())) {
                    out.push((o, n.to_string(), args));
                }
            }
            Term::GlobalCall(n, args) => {
                if sem.global_proc(n.as_str()).is_some() {
                    out.push(("/".to_string(), n.to_string(), args));
                }
            }
            _ => {}
        }
        // `x.foo(...)` with `x` a name of a declared type, or `src`.
        if follow.len() == 1 {
            if let (Term::Ident(recv), Follow::Call(_, n, args)) = (&term.elem, &follow[0].elem) {
                let ty = if recv.as_str() == "src" { Some(owner.to_string()) } else { types.get(recv.as_str()).cloned() };
                if let Some(ty) = ty {
                    if let Some(o) = resolve_on(&ty, n.as_str()) {
                        out.push((o, n.to_string(), args));
                    }
                }
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
    fn body(&mut self, handler: &str, owner: &str, params: &[Parameter], code: &Block, rel: &str, taint: Taint, depth: usize) {
        let mut taint = taint;
        taint.close_over(code);
        let types = declared_types(params, code);
        let direct = depth == 0;
        let mut pending: Vec<(String, String, Vec<usize>, Vec<usize>)> = Vec::new();
        let sem = self.sem;
        let mut found: Vec<ActorTest> = Vec::new();
        let mut macro_lines: BTreeSet<u32> = BTreeSet::new();
        walk_lines(code, &mut |e, line| {
            if let Expression::Base { term, follow } = e {
                if let (Term::Call(n, args), true) = (&term.elem, follow.is_empty()) {
                    if n.as_str() == "istype" && args.len() == 2 && taint.is_actor(&args[0]) {
                        if let Some(p) = prefab_path(&args[1]).filter(|p| silicon_type(p)) {
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
                let mut cs = Vec::new();
                calls(sem, owner, &types, e, &mut cs);
                for (o, n, args) in cs {
                    let actor_pos: Vec<usize> = args.iter().enumerate().filter(|(_, a)| taint.is_actor(a)).map(|(i, _)| i).collect();
                    let act_pos: Vec<usize> = args.iter().enumerate().filter(|(_, a)| taint.is_act(a)).map(|(i, _)| i).collect();
                    if actor_pos.is_empty() && act_pos.is_empty() {
                        continue;
                    }
                    pending.push((o, n, actor_pos, act_pos));
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
            let v = p.get();
            let Some(code) = v.code.as_ref() else { continue };
            // A handler is checked on its own (as a handler); following it again would only relabel its sites.
            if is_handler(&o, &n, &v.parameters) {
                continue;
            }
            let mut t = Taint::default();
            for i in actor_pos {
                if let Some(param) = v.parameters.get(i) {
                    t.actors.insert(param.name.to_string());
                }
            }
            for i in act_pos {
                if let Some(param) = v.parameters.get(i) {
                    t.acts.insert(param.name.to_string());
                }
            }
            let callee_rel = sem.rel(v.location).to_string();
            self.body(handler, &o, &v.parameters, code, &callee_rel, t, depth + 1);
        }
    }
}

/// Every actor type test reachable from a handler. `lines(rel, line)` reads a source line (for the macro spelling).
pub fn actor_tests(sem: &Sem, lines: &dyn Fn(&str, u32) -> Option<String>) -> Vec<ActorTest> {
    let macro_re = crate::pat!(r"(?<![\w.])(?:isAI|issilicon|isrobot|ispAI)\(");
    let mut w = Walker { sem, found: Vec::new(), visited: HashSet::new(), macro_re, lines };
    let mut handlers: Vec<(String, String, usize)> = Vec::new();
    for ty in sem.objtree.iter_types() {
        let owner = if ty.get().path.is_empty() { "/".to_string() } else { ty.get().path.clone() };
        for (name, tp) in ty.get().procs.iter() {
            for (i, v) in tp.value.iter().enumerate() {
                if v.code.is_some() && is_handler(&owner, name, &v.parameters) {
                    handlers.push((owner.clone(), name.clone(), i));
                }
            }
        }
    }
    for (owner, name, i) in handlers {
        let Some(ty) = sem.ty(&owner) else { continue };
        let Some(tp) = ty.get().procs.get(name.as_str()) else { continue };
        let v = &tp.value[i];
        let Some(code) = v.code.as_ref() else { continue };
        let mut t = Taint::default();
        for p in v.parameters.iter() {
            if is_act(&p.var_type.type_path) {
                t.acts.insert(p.name.to_string());
            }
        }
        let rel = sem.rel(v.location).to_string();
        let handler = format!("{}/proc/{}", if owner == "/" { "" } else { owner.as_str() }, name);
        w.body(&handler, &owner, &v.parameters, code, &rel, t, 0);
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
