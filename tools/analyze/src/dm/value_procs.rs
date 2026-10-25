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
//! Two reads are values as well. A read of a builtin `world` var that is a number or text (`world.time`, [`WORLD_VALUE_VARS`]); and a read
//! of a var that holds only values: the declaration of the var and every override of it has no type and a null, number or text initial
//! value, and every assignment to it (any operator) is a value. A var is the type that declares it and its name, so two types that
//! happen to name a var alike do not judge each other. An assignment reaches the one var its receiver's static type (or the proc's own
//! type) finds; an assignment through a receiver of unknown type counts against every var of that name. The proof does not see a write
//! through `vars[...]` or a map instance var; the lint's own rules do not either.
//!
//! A proc whose declaration says `as text` / `as num` returns a value. A parameter is a value when it has no type path (an `as text` input type is
//! allowed: DM does not enforce it for a plain call, so the call sites below still decide), takes a literal default, and every call of a proc of that name in the tree passes a value in
//! its position (a call may reach any proc of its name, so this is judged by name). A name is ruled out when a definition is a verb or
//! overrides a DM builtin (a player or the engine supplies the arguments), when the name appears as a bare identifier, a string or a type
//! path anywhere (`PROC_REF(x)`, `call(o, "x")`: a call nothing here sees), and when any call of it uses a named argument or `arglist()`.
//! A method call on a receiver of unknown type is a value when every definition of that name is and no DM builtin type has one.
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
    "ref", "url_encode", "url_decode", "sha1", "findtextEx", "findlasttext", "findlasttextEx", "findtext_char", "length_char", "copytext_char", "sorttext", "sorttextEx", "log", "tan", "arcsin", "arccos", "arctan", "sign", "text",
    "roll", "cmptext", "cmptextEx", "lentext", "winget", "fexists", "file", "hascall",
];

/// Methods of the DM builtin types (`list.Find`, `list.Join`, `regex.Replace`) whose result is a number or text. Used for a method call
/// on a receiver of unknown type, and only when no proc of the tree has that name (so the call can reach nothing but the builtin).
pub const BUILTIN_VALUE_METHODS: &[&str] = &["Find", "Join", "Replace"];

/// Methods of the builtin `/regex` type that return a number (`Find`) or text (`Replace`); used when the receiver is statically a regex.
const REGEX_VALUE_METHODS: &[&str] = &["Find", "Replace"];

/// The config entry classes whose stored value is a number, flag or text (`ValidateAndSet` of the class is the only writer): a
/// `global.config.Get(/datum/config_entry/number/x)` read is then a value.
const CONFIG_VALUE_CLASSES: &[&str] = &["/datum/config_entry/number", "/datum/config_entry/flag", "/datum/config_entry/string"];
const CONFIG_TYPE: &str = "/datum/controller/configuration";

/// Builtin `world` vars that are a number, text or null.
pub const WORLD_VALUE_VARS: &[&str] = &[
    "time", "timeofday", "realtime", "tick_lag", "tick_usage", "cpu", "map_cpu", "maxx", "maxy", "maxz", "fps", "byond_version", "byond_build", "port", "address", "name", "version",
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
    /// Var names that still hold only values (candidates start in; an assignment of a non-value takes a name out).
    vars: RefCell<HashMap<String, bool>>,
    /// Var name -> every key of `vars` with that name, for a write whose receiver cannot be typed.
    var_keys: HashMap<String, Vec<String>>,
    /// Set when a var name left `vars` during this pass: the definitions that read it must be looked at again.
    vars_changed: RefCell<bool>,
    /// Proc name -> per parameter position: still known to receive only values at every call in the tree. Judged by name, since a call
    /// whose receiver cannot be typed may reach any proc of that name.
    params: RefCell<HashMap<String, Vec<bool>>>,
    /// The name of each definition.
    def_names: Vec<String>,
    /// Names of the procs the tree itself defines with a body or declaration (not the DM builtin types').
    tree_names: HashSet<String>,
    /// Names of the procs the DM builtin types define.
    builtin_names: HashSet<String>,
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
        let vars = value_var_candidates(sem);
        let mut var_keys: HashMap<String, Vec<String>> = HashMap::new();
        for k in vars.keys() {
            if let Some((_, n)) = k.rsplit_once("::") {
                var_keys.entry(n.to_string()).or_default().push(k.clone());
            }
        }
        let def_names: Vec<String> = refs.iter().map(|r| r.name().to_string()).collect();
        let params = param_candidates(sem, &refs);
        let tree_names: HashSet<String> = refs.iter().filter(|r| !r.is_builtin() && !r.get().location.is_builtins()).map(|r| r.name().to_string()).collect();
        let mut builtin_names: HashSet<String> = HashSet::new();
        for ty in sem.objtree.iter_types() {
            for (name, tp) in ty.get().procs.iter() {
                if tp.value.iter().any(|v| v.location.is_builtins()) {
                    builtin_names.insert(name.to_string());
                }
            }
        }
        let mut me = ValueProcs { sem, w, ids, value: vec![true; refs.len()], parent, finals, targets: RefCell::new(HashMap::new()), touched: RefCell::new(false), vars: RefCell::new(vars), var_keys, vars_changed: RefCell::new(false), params: RefCell::new(params), def_names, tree_names, builtin_names };
        let mut live: Vec<usize> = (0..refs.len()).collect();
        loop {
            let mut changed = false;
            *me.vars_changed.borrow_mut() = false;
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
            if !changed && !*me.vars_changed.borrow() {
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
                        Follow::Field(_, name) if follow.len() == 1 && matches!(&term.elem, Term::Ident(n) if n == "world") => WORLD_VALUE_VARS.contains(&name.as_str()),
                        Follow::Field(_, name) => {
                            let recv = Expression::Base { term: term.clone(), follow: follow[..follow.len() - 1].to_vec().into_boxed_slice() };
                            match self.w.type_of(ctx.sc, &recv) {
                                Some(t) if !t.is_empty() => self.var_value(&t, name),
                                _ => false,
                            }
                        }
                        Follow::Call(_, name, _) if follow.len() == 1 && matches!(&term.elem, Term::Ident(n) if n == "global") => self.call_value("/", name, true),
                        Follow::Call(_, name, args) if name == "Get" && self.config_value_get(ctx, term, &follow[..follow.len() - 1], args) => true,
                        Follow::Call(_, name, _) => {
                            let recv = Expression::Base { term: term.clone(), follow: follow[..follow.len() - 1].to_vec().into_boxed_slice() };
                            match self.w.type_of(ctx.sc, &recv) {
                                Some(t) if !t.is_empty() => self.call_value(&t, name, false) || (t == "/regex" && REGEX_VALUE_METHODS.contains(&name.as_str()) && self.sem.proc_ref("/regex", name).is_none_or(|r| r.is_builtin())) || (BUILTIN_VALUE_METHODS.contains(&name.as_str()) && !self.tree_names.contains(name.as_str())),
                                _ => self.any_receiver_value(name),
                            }
                        }
                        _ => false,
                    };
                }
                match &term.elem {
                    Term::Null | Term::Int(_) | Term::Float(_) | Term::String(_) | Term::Resource(_) | Term::InterpString(..) | Term::__PROC__ | Term::__TYPE__ => true,
                    Term::Expr(inner) => self.value_expr(ctx, inner),
                    Term::Ident(n) => n == "." || ctx.locals.contains(n.as_str()) || (!ctx.sc.locals.contains_key(n.as_str()) && self.var_value(ctx.sc.owner, n)),
                    Term::Pick(choices) => choices.iter().all(|(w, v)| w.as_ref().is_none_or(|w| self.value_expr(ctx, w)) && self.value_expr(ctx, v)),
                    Term::Call(n, args) if (n == "pick" || n == "pickweight") && matches!(self.target(ctx.sc.owner, n), Target::Builtin) => self.pick_value(ctx, args),
                    Term::Call(n, _) => {
                        let owner = if ctx.sc.owner == "/" { "/" } else { ctx.sc.owner };
                        self.call_value(owner, n, true)
                    }
                    Term::GlobalCall(n, _) => self.call_value("/", n, true),
                    // `call_ext(lib, fn)(args)` hands back the external function's text (or null), never a reference.
                    Term::ExternalCall { .. } => true,
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

    /// `pick(a, b, c)` over value arguments, or `pick(list(...))` / `pickweight(list(...))` over a literal list of values (and value keys).
    fn pick_value(&self, ctx: &Ctx, args: &[Expression]) -> bool {
        let item = |e: &Expression| match strip_parens(e) {
            Expression::AssignOp { op: AssignOp::Assign, lhs, rhs } => self.value_expr(ctx, lhs) && self.value_expr(ctx, rhs),
            other => self.value_expr(ctx, other),
        };
        match args {
            [one] => match strip_parens(one) {
                Expression::Base { term, follow } if follow.is_empty() => match &term.elem {
                    Term::List(items) => items.iter().all(item),
                    _ => false,
                },
                _ => false,
            },
            _ => !args.is_empty() && args.iter().all(item),
        }
    }

    /// `recv.Get(/datum/config_entry/number/x)` where `recv` is the configuration controller and the entry is a number, flag or string
    /// entry whose class is the only definer of `ValidateAndSet` on the path (no subtype stores anything else).
    fn config_value_get(&self, ctx: &Ctx, term: &Box<dreammaker::ast::Spanned<Term>>, recv_follow: &[dreammaker::ast::Spanned<Follow>], args: &[Expression]) -> bool {
        let [arg] = args else { return false };
        let Expression::Base { term: at, follow: af } = strip_parens(arg) else { return false };
        let Term::Prefab(p) = &at.elem else { return false };
        if !af.is_empty() {
            return false;
        }
        let path: String = p.path.iter().map(|(_, n)| format!("/{n}")).collect();
        let recv = Expression::Base { term: term.clone(), follow: recv_follow.to_vec().into_boxed_slice() };
        let global_recv = match (&term.elem, recv_follow) {
            (Term::Ident(g), [f]) if g == "global" => match &f.elem {
                Follow::Field(_, n) => self.sem.var_decl("/", n).is_some_and(|d| d.declared == CONFIG_TYPE),
                _ => false,
            },
            _ => false,
        };
        if !global_recv && self.w.type_of(ctx.sc, &recv).as_deref() != Some(CONFIG_TYPE) {
            return false;
        }
        let Some(class) = CONFIG_VALUE_CLASSES.iter().find(|c| path == **c || path.starts_with(&format!("{c}/"))) else { return false };
        self.config_class_clean(&path, class)
    }

    /// No type from `path` up to (not including) `class` assigns `config_entry_value`: the class's `ValidateAndSet` stays its one writer, so a
    /// subtype that only adds a side effect (`. = ..()` then a call) still holds a number, flag or text.
    fn config_class_clean(&self, path: &str, class: &str) -> bool {
        let Some(mut cur) = self.sem.ty(path) else { return false };
        loop {
            if type_key(&cur.get().path) == class {
                return true;
            }
            for (_, tp) in cur.get().procs.iter() {
                for v in tp.value.iter() {
                    let Some(code) = v.code.as_ref() else { continue };
                    let mut writes = false;
                    for_each_expr(code, &mut |e| {
                        let Expression::AssignOp { lhs, .. } = e else { return };
                        let Expression::Base { term, follow } = strip_parens(lhs) else { return };
                        writes |= match follow.last() {
                            Some(last) => matches!(&last.elem, Follow::Field(_, n) if n == "config_entry_value"),
                            None => matches!(&term.elem, Term::Ident(n) if n == "config_entry_value"),
                        };
                    });
                    if writes {
                        return false;
                    }
                }
            }
            match cur.parent_type() {
                Some(p) => cur = p,
                None => return false,
            }
        }
    }

    /// Whether the var `name` read on type `ty` holds only values.
    fn var_value(&self, ty: &str, name: &str) -> bool {
        *self.touched.borrow_mut() = true;
        let Some(sig) = self.sem.var_decl(ty, name) else { return false };
        let Some(owner) = self.sem.var_owner(ty, name) else { return false };
        sig.declared.is_empty() && self.vars.borrow().get(&var_key(&owner, name)).copied().unwrap_or(false)
    }

    /// Takes out of `vars` every var that `code` assigns a non-value to. A write through a receiver of known type (or to the proc's own var)
    /// takes out the one var it reaches, found by the type that declares it; a write through a receiver of unknown type takes out every
    /// var of that name.
    fn scan_var_writes(&self, ctx: &Ctx, code: &Block) {
        for_each_expr(code, &mut |e| {
            let Expression::AssignOp { lhs, rhs, .. } = e else { return };
            let Expression::Base { term, follow } = strip_parens(lhs) else { return };
            let (name, owner): (String, Option<String>) = match follow.last() {
                Some(last) => match &last.elem {
                    Follow::Field(_, n) => {
                        let recv = Expression::Base { term: term.clone(), follow: follow[..follow.len() - 1].to_vec().into_boxed_slice() };
                        let owner = match self.w.type_of(ctx.sc, &recv) {
                            Some(t) if !t.is_empty() && t != "/" => self.sem.var_owner(&t, n),
                            _ => None,
                        };
                        (n.to_string(), owner)
                    }
                    Follow::StaticField(n) => (n.to_string(), None),
                    _ => return,
                },
                None => match &term.elem {
                    Term::Ident(n) if !ctx.sc.locals.contains_key(n.as_str()) && n != "." => {
                        let owner = if ctx.sc.owner == "/" { None } else { self.sem.var_owner(ctx.sc.owner, n) };
                        (n.to_string(), owner)
                    }
                    _ => return,
                },
            };
            let keys: Vec<String> = match owner {
                Some(o) => vec![var_key(&o, &name)],
                None => self.var_keys.get(&name).cloned().unwrap_or_default(),
            };
            if keys.is_empty() || !keys.iter().any(|k| self.vars.borrow().get(k).copied().unwrap_or(false)) {
                return;
            }
            if !self.value_expr(ctx, rhs) {
                let mut vars = self.vars.borrow_mut();
                for k in keys {
                    if let Some(b) = vars.get_mut(&k) {
                        *b = false;
                    }
                }
                *self.vars_changed.borrow_mut() = true;
            }
        });
    }

    /// A method call `x.name()` whose receiver has no static type: it runs some definition named `name`, so it is a value when every
    /// definition of that name in the tree is and no DM builtin type has a proc of that name.
    fn any_receiver_value(&self, name: &str) -> bool {
        *self.touched.borrow_mut() = true;
        if self.builtin_names.contains(name) {
            return false;
        }
        if BUILTIN_VALUE_METHODS.contains(&name) && !self.tree_names.contains(name) {
            return true;
        }
        let mut any = false;
        for (i, n) in self.def_names.iter().enumerate() {
            if n == name {
                any = true;
                if !self.value[i] {
                    return false;
                }
            }
        }
        any
    }

    /// Takes a parameter position out of `params` for good.
    fn kill_param(&self, name: &str, i: Option<usize>) {
        let mut ps = self.params.borrow_mut();
        let Some(v) = ps.get_mut(name) else { return };
        let mut hit = false;
        for (j, b) in v.iter_mut().enumerate() {
            if *b && i.is_none_or(|i| i == j) {
                *b = false;
                hit = true;
            }
        }
        if hit {
            *self.vars_changed.borrow_mut() = true;
        }
    }

    /// One call of `name`: a position that gets a non-value, a named argument or an `arglist()` leaves `params`.
    fn call_site(&self, ctx: &Ctx, name: &str, args: &[Expression]) {
        if !self.params.borrow().contains_key(name) {
            return;
        }
        let spread = args.iter().any(|a| match strip_parens(a) {
            Expression::AssignOp { .. } => true,
            Expression::Base { term, follow } => follow.is_empty() && matches!(&term.elem, Term::Call(n, _) if n == "arglist"),
            _ => false,
        });
        if spread {
            self.kill_param(name, None);
            return;
        }
        for (i, a) in args.iter().enumerate() {
            if !self.value_expr(ctx, a) {
                self.kill_param(name, Some(i));
            }
        }
    }

    /// Every call in `code` narrows the parameter positions of the procs it can reach.
    fn scan_calls(&self, ctx: &Ctx, code: &Block, me: &str) {
        for_each_expr(code, &mut |e| {
            let Expression::Base { term, follow } = e else { return };
            match &term.elem {
                Term::Call(n, args) | Term::GlobalCall(n, args) => self.call_site(ctx, n, args),
                Term::SelfCall(args) | Term::ParentCall(args) if !args.is_empty() => self.call_site(ctx, me, args),
                _ => {}
            }
            for fo in follow.iter() {
                if let Follow::Call(_, n, args) = &fo.elem {
                    self.call_site(ctx, n, args);
                }
            }
        });
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
        let mut value_params: Vec<String> = Vec::new();
        *self.touched.borrow_mut() = true;
        let flags = self.params.borrow().get(&self.def_names[id]).cloned().unwrap_or_default();
        for (i, p) in v.parameters.iter().enumerate() {
            locals.insert(p.name.to_string(), (path_of(&p.var_type.type_path), None));
            if flags.get(i).copied().unwrap_or(false) {
                value_params.push(p.name.to_string());
            } else {
                bad.insert(p.name.to_string());
            }
        }
        collect_locals(code, "", &mut locals);
        let sc = ProcScope { owner: &path, locals };
        let value_locals = self.value_locals(&sc, code, &mut bad, id, &value_params);
        let ctx = Ctx { sc: &sc, locals: &value_locals, def: Some(id) };
        self.scan_var_writes(&ctx, code);
        self.scan_calls(&ctx, code, &self.def_names[id]);
        // The body is still scanned above (its calls narrow the parameters); a declared `as text` / `as num` return then settles the answer.
        declared_value_return(r) || self.returns_ok(&ctx, code)
    }

    /// The locals of a proc whose every assignment is a value.
    fn value_locals(&self, sc: &ProcScope, code: &Block, bad: &mut HashSet<String>, id: usize, value_params: &[String]) -> HashSet<String> {
        let mut assigns: HashMap<String, Vec<&Expression>> = HashMap::new();
        declared_locals(code, &mut assigns, bad, self.w);
        for n in value_params {
            assigns.entry(n.clone()).or_default();
        }
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

    /// Whether the local `name` of the proc body `code` is assigned the result of a call that is not a value, directly or through other
    /// locals (`var/x = f()`, then `y = x`): a local holds what was assigned to it, so passing it on passes the call's result on.
    pub(crate) fn local_holds_call(&self, sc: &ProcScope, code: &Block, name: &str) -> bool {
        let mut assigns: HashMap<String, Vec<&Expression>> = HashMap::new();
        let mut bad: HashSet<String> = HashSet::new();
        declared_locals(code, &mut assigns, &mut bad, self.w);
        for_each_expr(code, &mut |e| {
            let Expression::AssignOp { op, lhs, rhs } = e else { return };
            let Expression::Base { term, follow } = strip_parens(lhs) else { return };
            let Term::Ident(n) = &term.elem else { return };
            if follow.is_empty() && matches!(op, AssignOp::Assign | AssignOp::AssignInto | AssignOp::AndAssign | AssignOp::OrAssign) {
                assigns.entry(n.to_string()).or_default().push(rhs);
            }
        });
        let mut seen: HashSet<String> = HashSet::new();
        let mut todo = vec![name.to_string()];
        while let Some(n) = todo.pop() {
            if !seen.insert(n.clone()) {
                continue;
            }
            for rhs in assigns.get(&n).map(|v| v.as_slice()).unwrap_or(&[]) {
                let r = strip_parens(rhs);
                if let Expression::Base { term, follow } = r {
                    if let (true, Term::Ident(l)) = (follow.is_empty(), &term.elem) {
                        if sc.locals.contains_key(l.as_str()) {
                            todo.push(l.to_string());
                            continue;
                        }
                    }
                }
                if is_call(r) && !self.is_value_call(sc, r) {
                    return true;
                }
            }
        }
        false
    }

    /// How many definitions are value-returning, and how many there are.
    #[allow(dead_code)]
    pub(crate) fn counts(&self) -> (usize, usize) {
        (self.value.iter().filter(|v| **v).count(), self.value.len())
    }
}

/// The value is the result of a proc call (a plain, global, or method call at the end of the chain).
pub(crate) fn is_call(e: &Expression) -> bool {
    let e = strip_parens(e);
    let Expression::Base { term, follow } = e else { return false };
    if let Some(last) = follow.last() {
        return matches!(last.elem, Follow::Call(..));
    }
    matches!(term.elem, Term::Call(..) | Term::GlobalCall(..))
}

/// A literal: a null, number or text.
fn literal_expr(e: &Expression) -> bool {
    matches!(strip_parens(e), Expression::Base { term, follow } if follow.is_empty() && matches!(term.elem, Term::Null | Term::Int(_) | Term::Float(_) | Term::String(_)))
}

/// The procs whose untyped parameters could receive only values: per name and position, true unless something rules it out here. A name is
/// ruled out when a definition is a verb (a player supplies the arguments), overrides a DM builtin (the engine calls it), or is named by a
/// reference or a string anywhere (`PROC_REF(x)`, `/proc/x`, `call(o, "x")`: called with arguments nothing here can see). A position is ruled
/// out when its parameter has a type, an input type that is not text/num/null kinds or a non-literal default. The call sites then narrow it (`call_site`).
/// An input type made only of number, text and null kinds (`as text`, `as num|null`): never a reference.
fn value_input(t: dreammaker::ast::InputType) -> bool {
    use dreammaker::ast::InputType as I;
    let allowed = I::TEXT | I::NUM | I::NULL | I::MESSAGE | I::PASSWORD | I::COMMAND_TEXT | I::COLOR | I::KEY;
    !t.is_empty() && t.difference(allowed).is_empty()
}

/// The proc's declaration says it returns only numbers and text (`/proc/f() as text`). A pointer-ish declared type never counts.
fn declared_value_return(r: ProcRef) -> bool {
    use dreammaker::ast::ProcReturnType;
    r.get_declaration().is_some_and(|d| matches!(&d.return_type, ProcReturnType::InputType(t) if value_input(*t)))
}

fn param_candidates(sem: &Sem, refs: &[ProcRef]) -> HashMap<String, Vec<bool>> {
    use dreammaker::constants::Constant;
    let mut named: HashSet<String> = HashSet::new();
    for ty in sem.objtree.iter_types() {
        for (_, tv) in ty.get().vars.iter() {
            if let Some(Constant::String(s)) = &tv.value.constant {
                named.insert(s.to_string());
            }
        }
    }
    let mut out: HashMap<String, Vec<bool>> = HashMap::new();
    let mut barred: HashSet<String> = HashSet::new();
    for r in refs {
        let name = r.name().to_string();
        let v = r.get();
        let slot = out.entry(name.clone()).or_default();
        if slot.len() < v.parameters.len() {
            slot.resize(v.parameters.len(), true);
        }
        for (i, p) in v.parameters.iter().enumerate() {
            if !p.var_type.type_path.is_empty() || p.input_type.is_some_and(|t| !value_input(t)) || p.in_list.is_some() || p.default.as_ref().is_some_and(|d| !literal_expr(d)) {
                slot[i] = false;
            }
        }
        if r.get_declaration().is_some_and(|d| matches!(d.kind, dreammaker::ast::ProcDeclKind::Verb)) {
            barred.insert(name.clone());
        }
        let mut cur = Some(*r);
        while let Some(x) = cur {
            if x.is_builtin() {
                barred.insert(name.clone());
                break;
            }
            cur = x.parent_proc();
        }
        if let Some(code) = v.code.as_ref() {
            for_each_expr(code, &mut |e| {
                let Expression::Base { term, follow } = e else { return };
                match &term.elem {
                    Term::Ident(n) => {
                        named.insert(n.to_string());
                    }
                    Term::String(s) => {
                        named.insert(s.to_string());
                    }
                    Term::Prefab(p) | Term::NewPrefab { prefab: p, .. } => {
                        for (_, n) in p.path.iter() {
                            named.insert(n.to_string());
                        }
                    }
                    _ => {}
                }
                for fo in follow.iter() {
                    if let Follow::ProcReference(n) = &fo.elem {
                        named.insert(n.to_string());
                    }
                }
            });
        }
    }
    for n in barred.iter().chain(named.iter()) {
        if let Some(v) = out.get_mut(n) {
            v.iter_mut().for_each(|b| *b = false);
        }
    }
    out
}

/// The key of a var in `vars`: the type that declares it and its name (a subtype's override is the same var).
fn var_key(owner: &str, name: &str) -> String {
    format!("{owner}::{name}")
}

/// The vars that could hold only values, by declaring type and name: every declaration or override of the var has no type and a null,
/// number or text initial value.
fn value_var_candidates(sem: &Sem) -> HashMap<String, bool> {
    use dreammaker::constants::Constant;
    let mut out: HashMap<String, bool> = HashMap::new();
    for ty in sem.objtree.iter_types() {
        let path = type_key(&ty.get().path);
        for (name, tv) in ty.get().vars.iter() {
            let typed = tv.declaration.as_ref().map(|d| !d.var_type.type_path.is_empty()).unwrap_or(false);
            let init_ok = match (&tv.value.constant, &tv.value.expression) {
                (Some(Constant::Null(_) | Constant::Float(_) | Constant::String(_) | Constant::Resource(_)), _) => true,
                (None, None) => true,
                _ => false,
            };
            let owner = sem.var_owner(&path, name).unwrap_or_else(|| path.clone());
            let slot = out.entry(var_key(&owner, name)).or_insert(true);
            if typed || !init_ok {
                *slot = false;
            }
        }
    }
    out
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
