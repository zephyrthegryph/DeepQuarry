//! Which procs return only numbers or text, found from their bodies (never from their names).
//!
//! A proc definition is *value-returning* when every way it can return yields a number, text or null, or the result of another
//! value-returning proc:
//!
//! * each `return expr`,
//! * each assignment to `.` (a bare `return` and the end of the body both return `.`),
//! * a `..()` / `.()` result, which is the result of the parent or of the proc itself.
//!
//! A value expression is a number or text literal, an interpolated string, arithmetic, a comparison or a unary operator (this tree
//! defines no operator overloads, so none yields an entity), `a || b` / `a && b` when both operands are values, a ternary whose
//! branches both are, a local whose every assignment in the proc is a value, or a call that resolves to value-returning procs or to a
//! DM builtin in [`BUILTIN_VALUE_CALLS`].
//!
//! A call resolves by the proc's identity, never by its name: an unscoped call is the proc found on the calling type (walking its
//! parents) or else the global proc; `recv.f()` is found on the static type of `recv`, which must be known. A call may reach an
//! override, so the call is a value only when the found definition and every override on the receiver type or below it are. A proc
//! that is declared and never defined by a body returns null.
//!
//! The answer is the greatest fixpoint: every definition starts as a value-returning one and loses the title when a return path does
//! not qualify, until nothing changes. Recursion therefore terminates (the set only shrinks) and a cycle with no other way out stays
//! as it is, since it returns nothing at all.

use std::cell::RefCell;
use std::collections::{HashMap, HashSet};

use dreammaker::ast::{AssignOp, BinaryOp, Block, Expression, Follow, Statement, Term, UnaryOp};
use dreammaker::objtree::ProcRef;

use crate::lints::stored_refs::{collect_locals, path_of, ProcScope, Walker};
use crate::sem::ast::{stmt_blocks, stmt_exprs, strip_parens, walk_expr};
use crate::sem::Sem;

/// DM builtins whose result is never an entity. Used only when the name is not a proc of the tree.
pub const BUILTIN_VALUE_CALLS: &[&str] = &[
    "rand", "prob", "round", "floor", "ceil", "abs", "min", "max", "sqrt", "sin", "cos", "num2text", "text2num", "list2params", "length", "lowertext", "uppertext", "copytext",
    "replacetext", "findtext", "jointext", "get_dist", "nameof", "ckey", "clamp", "isnull", "initial", "md5", "replacetextEx", "turn", "get_dir", "html_decode", "html_encode",
    "text2ascii", "ascii2text", "file2text", "rgb", "istype", "ispath", "islist", "isnum", "istext", "time2text", "addtext", "splittext", "json_encode", "text2path", "trim",
];

type DefKey = (String, String, usize);

/// What a call resolves to.
#[derive(Clone)]
enum Target {
    /// A DM builtin or a name nothing in the tree defines.
    Builtin,
    /// The definitions the call can run.
    Defs(Vec<usize>),
}

pub(crate) struct ValueProcs<'a, 'k> {
    sem: &'a Sem,
    w: &'a Walker<'a, 'k>,
    ids: HashMap<DefKey, usize>,
    /// `value[id]` after the fixpoint.
    value: Vec<bool>,
    /// The definition `..()` reaches from each definition (None: a builtin or nothing).
    parent: Vec<Option<usize>>,
    /// The final definition of each type's own proc `name`, for finding overrides.
    finals: HashMap<String, Vec<(String, usize)>>,
    targets: RefCell<HashMap<(String, String), Target>>,
    /// Set while a definition is evaluated: it read another definition's answer.
    touched: RefCell<bool>,
}

struct Ctx<'c> {
    sc: &'c ProcScope<'c>,
    locals: &'c HashSet<String>,
    def: Option<usize>,
}

fn type_key(path: &str) -> String {
    if path.is_empty() { "/".to_string() } else { path.to_string() }
}

impl<'a, 'k> ValueProcs<'a, 'k> {
    pub(crate) fn build(sem: &'a Sem, w: &'a Walker<'a, 'k>) -> Self {
        let mut ids: HashMap<DefKey, usize> = HashMap::new();
        let mut refs: Vec<ProcRef<'a>> = Vec::new();
        let mut finals: HashMap<String, Vec<(String, usize)>> = HashMap::new();
        for ty in sem.objtree.iter_types() {
            let path = type_key(&ty.get().path);
            for (name, tp) in ty.get().procs.iter() {
                if tp.value.is_empty() {
                    continue;
                }
                let Some(mut r) = ty.get_proc(name) else { continue };
                loop {
                    let id = refs.len();
                    ids.insert((path.clone(), name.to_string(), r.index()), id);
                    if r.index() + 1 == tp.value.len() {
                        finals.entry(name.to_string()).or_default().push((path.clone(), id));
                    }
                    refs.push(r);
                    if r.index() == 0 {
                        break;
                    }
                    match r.parent_proc() {
                        Some(p) => r = p,
                        None => break,
                    }
                }
            }
        }
        let parent: Vec<Option<usize>> = refs.iter().map(|r| r.parent_proc().filter(|p| !p.is_builtin()).and_then(|p| ids.get(&(type_key(&p.ty().get().path), p.name().to_string(), p.index())).copied())).collect();
        let mut me = ValueProcs { sem, w, ids, value: vec![true; refs.len()], parent, finals, targets: RefCell::new(HashMap::new()), touched: RefCell::new(false) };
        let mut live: Vec<usize> = (0..refs.len()).collect();
        loop {
            let mut changed = false;
            let mut next = Vec::new();
            for id in live {
                *me.touched.borrow_mut() = false;
                let ok = me.eval_def(id, refs[id]);
                if !ok {
                    me.value[id] = false;
                    changed = true;
                } else if *me.touched.borrow() {
                    next.push(id);
                }
            }
            if !changed {
                break;
            }
            live = next;
        }
        me
    }

    fn id_of(&self, r: ProcRef<'a>) -> Option<usize> {
        self.ids.get(&(type_key(&r.ty().get().path), r.name().to_string(), r.index())).copied()
    }

    /// The definitions a call of `name` on static type `ty` can run; `Builtin` when the lookup ends in a DM builtin or nothing.
    fn target(&self, ty: &str, name: &str) -> Target {
        let key = (ty.to_string(), name.to_string());
        if let Some(t) = self.targets.borrow().get(&key) {
            return t.clone();
        }
        let t = self.resolve(ty, name);
        self.targets.borrow_mut().insert(key, t.clone());
        t
    }

    fn resolve(&self, ty: &str, name: &str) -> Target {
        let found = if ty == "/" { self.sem.global_proc(name) } else { self.sem.proc_ref(ty, name) };
        let Some(r) = found else { return Target::Builtin };
        if r.is_builtin() {
            return Target::Builtin;
        }
        let Some(id) = self.id_of(r) else { return Target::Builtin };
        let mut defs = vec![id];
        if ty != "/" && type_key(&r.ty().get().path) != "/" {
            for (d, fid) in self.finals.get(name).map(|v| v.as_slice()).unwrap_or(&[]) {
                if d != &type_key(&r.ty().get().path) && self.sem.is_subtype(d, ty) {
                    defs.push(*fid);
                }
            }
        }
        defs.sort_unstable();
        defs.dedup();
        Target::Defs(defs)
    }

    fn defs_value(&self, defs: &[usize]) -> bool {
        *self.touched.borrow_mut() = true;
        defs.iter().all(|d| self.value[*d])
    }

    fn call_value(&self, owner: &str, name: &str, builtin_ok: bool) -> bool {
        match self.target(owner, name) {
            Target::Defs(d) => self.defs_value(&d),
            Target::Builtin => builtin_ok && BUILTIN_VALUE_CALLS.contains(&name),
        }
    }

    fn value_expr(&self, ctx: &Ctx, e: &Expression) -> bool {
        let e = strip_parens(e);
        match e {
            Expression::BinaryOp { op, lhs, rhs } => match op {
                BinaryOp::And | BinaryOp::Or => self.value_expr(ctx, lhs) && self.value_expr(ctx, rhs),
                _ => true,
            },
            Expression::AssignOp { op, rhs, .. } => match op {
                AssignOp::Assign | AssignOp::AssignInto | AssignOp::AndAssign | AssignOp::OrAssign => self.value_expr(ctx, rhs),
                _ => true,
            },
            Expression::TernaryOp { if_, else_, .. } => self.value_expr(ctx, if_) && self.value_expr(ctx, else_),
            Expression::Base { term, follow } => {
                if let Some(last) = follow.last() {
                    return match &last.elem {
                        Follow::Unary(UnaryOp::Reference | UnaryOp::Dereference) => false,
                        Follow::Unary(_) => true,
                        Follow::Call(_, name, _) if follow.len() == 1 && matches!(&term.elem, Term::Ident(n) if n == "global") => self.call_value("/", name, true),
                        Follow::Call(_, name, _) => {
                            let recv = Expression::Base { term: term.clone(), follow: follow[..follow.len() - 1].to_vec().into_boxed_slice() };
                            match self.w.type_of(ctx.sc, &recv) {
                                Some(t) if !t.is_empty() => self.call_value(&t, name, false),
                                _ => false,
                            }
                        }
                        _ => false,
                    };
                }
                match &term.elem {
                    Term::Null | Term::Int(_) | Term::Float(_) | Term::String(_) | Term::Resource(_) | Term::InterpString(..) | Term::__PROC__ | Term::__TYPE__ => true,
                    Term::Expr(inner) => self.value_expr(ctx, inner),
                    Term::Ident(n) => n == "." || ctx.locals.contains(n.as_str()),
                    Term::Call(n, _) => {
                        let owner = if ctx.sc.owner == "/" { "/" } else { ctx.sc.owner };
                        self.call_value(owner, n, true)
                    }
                    Term::GlobalCall(n, _) => self.call_value("/", n, true),
                    Term::ParentCall(_) => match ctx.def {
                        Some(id) => self.parent_value(id),
                        None => false,
                    },
                    Term::SelfCall(_) => match ctx.def {
                        Some(id) => {
                            *self.touched.borrow_mut() = true;
                            self.value[id]
                        }
                        None => false,
                    },
                    _ => false,
                }
            }
        }
    }

    fn parent_value(&self, id: usize) -> bool {
        match self.parent[id] {
            Some(pid) => self.defs_value(&[pid]),
            None => false,
        }
    }

    fn eval_def(&self, id: usize, r: ProcRef<'a>) -> bool {
        let v = r.get();
        if !v.code.has_body() {
            return true;
        }
        let Some(code) = v.code.as_ref() else { return false };
        let path = type_key(&r.ty().get().path);
        let mut locals: HashMap<String, (String, Option<crate::lints::stored_refs::Place>)> = HashMap::new();
        let mut bad: HashSet<String> = HashSet::new();
        for p in v.parameters.iter() {
            locals.insert(p.name.to_string(), (path_of(&p.var_type.type_path), None));
            bad.insert(p.name.to_string());
        }
        collect_locals(code, "", &mut locals);
        let sc = ProcScope { owner: &path, locals };
        let value_locals = self.value_locals(&sc, code, &mut bad, id);
        let ctx = Ctx { sc: &sc, locals: &value_locals, def: Some(id) };
        self.returns_ok(&ctx, code)
    }

    /// The locals of a proc whose every assignment is a value.
    fn value_locals(&self, sc: &ProcScope, code: &Block, bad: &mut HashSet<String>, id: usize) -> HashSet<String> {
        let mut assigns: HashMap<String, Vec<&Expression>> = HashMap::new();
        declared_locals(code, &mut assigns, bad, self.w);
        for_each_expr(code, &mut |e| {
            let Expression::AssignOp { op, lhs, rhs } = e else { return };
            let Expression::Base { term, follow } = strip_parens(lhs) else { return };
            let Term::Ident(n) = &term.elem else { return };
            if !follow.is_empty() {
                return;
            }
            match op {
                AssignOp::Assign | AssignOp::AssignInto | AssignOp::AndAssign | AssignOp::OrAssign => assigns.entry(n.to_string()).or_default().push(rhs),
                _ => {}
            }
        });
        let mut set: HashSet<String> = assigns.keys().filter(|n| !bad.contains(*n) && self.sem.var_decl(sc.owner, n).is_none() && self.sem.var_decl("/", n).is_none()).cloned().collect();
        loop {
            let mut gone: Vec<String> = Vec::new();
            {
                let ctx = Ctx { sc, locals: &set, def: Some(id) };
                for n in set.iter() {
                    if assigns[n].iter().any(|rhs| !self.value_expr(&ctx, rhs)) {
                        gone.push(n.clone());
                    }
                }
            }
            if gone.is_empty() {
                return set;
            }
            for n in gone {
                set.remove(&n);
            }
        }
    }

    /// Every `return expr` and every assignment to `.` is a value.
    fn returns_ok(&self, ctx: &Ctx, code: &Block) -> bool {
        let mut ok = true;
        for_each_return(code, &mut |e| {
            if ok && !self.value_expr(ctx, e) {
                ok = false;
            }
        });
        if !ok {
            return false;
        }
        for_each_expr(code, &mut |e| {
            if !ok {
                return;
            }
            let Expression::AssignOp { op, lhs, rhs } = e else { return };
            let Expression::Base { term, follow } = strip_parens(lhs) else { return };
            if !follow.is_empty() || !matches!(&term.elem, Term::Ident(n) if n == ".") {
                return;
            }
            if matches!(op, AssignOp::Assign | AssignOp::AssignInto | AssignOp::AndAssign | AssignOp::OrAssign) && !self.value_expr(ctx, rhs) {
                ok = false;
            }
        });
        ok
    }

    /// Whether the call `e`, at a site in a proc of type `owner`, can only return a number, text or null.
    pub(crate) fn is_value_call(&self, sc: &ProcScope, e: &Expression) -> bool {
        let empty = HashSet::new();
        let ctx = Ctx { sc, locals: &empty, def: None };
        self.value_expr(&ctx, e)
    }

    /// How many definitions are value-returning, and how many there are.
    #[allow(dead_code)]
    pub(crate) fn counts(&self) -> (usize, usize) {
        (self.value.iter().filter(|v| **v).count(), self.value.len())
    }
}

fn for_each_expr<'b>(b: &'b Block, f: &mut dyn FnMut(&'b Expression)) {
    for st in b.iter() {
        let mut exprs = stmt_exprs(&st.elem);
        if let Statement::ForLoop { init, inc, .. } = &st.elem {
            for s in [init, inc].into_iter().flatten() {
                exprs.extend(stmt_exprs(s));
            }
        }
        for e in exprs {
            walk_expr(e, &mut |x| f(x));
        }
        for nb in stmt_blocks(&st.elem) {
            for_each_expr(nb, f);
        }
    }
}

fn for_each_return<'b>(b: &'b Block, f: &mut dyn FnMut(&'b Expression)) {
    for st in b.iter() {
        if let Statement::Return(Some(e)) = &st.elem {
            f(e);
        }
        for nb in stmt_blocks(&st.elem) {
            for_each_return(nb, f);
        }
    }
}

/// The locals declared in the body with their initial values; a local of an entity type, or one a loop sets, can never be a value.
fn declared_locals<'b>(b: &'b Block, out: &mut HashMap<String, Vec<&'b Expression>>, bad: &mut HashSet<String>, w: &Walker) {
    fn declare<'b>(name: &str, tp: &[String], init: Option<&'b Expression>, out: &mut HashMap<String, Vec<&'b Expression>>, bad: &mut HashSet<String>, w: &Walker) {
        if w.kinds.is_ref(&path_of(tp)) {
            bad.insert(name.to_string());
        }
        let slot = out.entry(name.to_string()).or_default();
        if let Some(i) = init {
            slot.push(i);
        }
    }
    for st in b.iter() {
        match &st.elem {
            Statement::Var(v) => declare(&v.name, &v.var_type.type_path, v.value.as_ref(), out, bad, w),
            Statement::Vars(vs) => {
                for v in vs {
                    declare(&v.name, &v.var_type.type_path, v.value.as_ref(), out, bad, w);
                }
            }
            Statement::ForList(fl) => {
                bad.insert(fl.name.to_string());
            }
            Statement::ForKeyValue(fk) => {
                bad.insert(fk.key.to_string());
                bad.insert(fk.value.to_string());
            }
            Statement::ForRange(fr) => {
                bad.insert(fr.name.to_string());
            }
            Statement::ForLoop { init: Some(init), .. } => {
                if let Statement::Var(v) = init.as_ref() {
                    declare(&v.name, &v.var_type.type_path, v.value.as_ref(), out, bad, w);
                }
            }
            _ => {}
        }
        for nb in stmt_blocks(&st.elem) {
            declared_locals(nb, out, bad, w);
        }
    }
}
