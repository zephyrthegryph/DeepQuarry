//! The constant value of every var, as the analysis reads it: what each var's initializer folds to at compile time (a number, a text,
//! null, a list or object constructor), or nothing when it is not a constant. The rules are SpacemanDMM's constant folder's (the ones the
//! analysis was written against): each type's vars are folded in turn; a name in an initializer is the value of that var on the type
//! being folded (its parents', when it has no assignment of its own); `GLOB.x` on a typed null reads a const var of that type; a static
//! or protected var that is not const is not folded, nor a non-const var of the root.

use std::collections::HashMap;

use dm_syntax::{Expr, ExprKind};

use super::builtins::Const;
use super::expr::{form, literal, Args, Chain, Form, Hop, Lit, Root};
use super::{Model, Ty};
use dm_ir::TypeId;
use dm_tree::{VAR_SPACEMAN_PROTECTED, MemberKind};

/// A folded value.
#[derive(Clone, Debug, PartialEq)]
pub enum Value {
    /// `null`, with the declared type path of the var it came from (`GLOB` declared `/datum/globals`).
    Null(Option<String>),
    Float(f32),
    String(String),
    Resource(String),
    /// A type path (no vars), for `/x::y`.
    Prefab(String),
    /// A list, `new`, a prefab with vars or a constructor call: a constant, but not one the analysis looks into (the text compares them).
    Other(String),
}

impl Value {
    fn to_bool(&self) -> bool {
        match self {
            Value::Null(_) => false,
            Value::Float(f) => *f != 0.,
            Value::String(s) => !s.is_empty(),
            _ => true,
        }
    }

    /// As the lints classify a constant.
    pub fn kind(&self) -> Const {
        match self {
            Value::Null(_) => Const::Null,
            Value::Float(f) => Const::Float(*f),
            Value::String(s) => Const::String(s.clone()),
            Value::Resource(s) => Const::Resource(s.clone()),
            Value::Prefab(_) | Value::Other(_) => Const::Other,
        }
    }
}

fn from_bool(b: bool) -> Value {
    Value::Float(if b { 1. } else { 0. })
}

fn from_bits(bits: u32) -> Value {
    Value::Float((bits & 0xffffff) as f32)
}

#[derive(Clone)]
enum State {
    Evaluating,
    Done(Option<Value>),
}

/// Every var's folded value, by (type, name): `None` for a var that is not a constant (or not folded).
pub struct Folded {
    pub values: HashMap<(TypeId, String), Option<Value>>,
}

pub fn fold_all(m: &Model) -> Folded {
    let mut f = Folder { m, state: HashMap::new() };
    for ty in m.types() {
        for name in ty.var_names() {
            let decl = ty.var_declaration(&name);
            let evaluable = match &decl {
                None => true,
                Some(d) => d.const_evaluable() && (d.is_const() || ty.path() != "/"),
            };
            if !evaluable {
                continue;
            }
            let _ = f.lookup(ty, &name, false);
        }
    }
    let values = f
        .state
        .into_iter()
        .map(|(k, s)| (k, match s {
            State::Done(v) => v,
            State::Evaluating => None,
        }))
        .collect();
    Folded { values }
}

struct Folder<'m> {
    m: &'m Model,
    state: HashMap<(TypeId, String), State>,
}

type Res = Result<Value, ()>;

impl<'m> Folder<'m> {
    /// A name's value as seen from `ty` (SpacemanDMM's `recursive_lookup`).
    fn lookup(&mut self, mut ty: Ty<'m>, name: &str, must_be_const: bool) -> Res {
        loop {
            let Some(decl) = ty.var_declaration(name) else { return Err(()) };
            if ty.has_own_var(name) {
                let key = (ty.id, name.to_string());
                match self.state.get(&key) {
                    Some(State::Done(Some(v))) => return Ok(v.clone()),
                    Some(State::Done(None)) | Some(State::Evaluating) => return Err(()),
                    None => {}
                }
                let Some(value) = ty.own_var_value(name) else {
                    let v = Value::Null(Some(decl.declared.clone()).filter(|d| !d.is_empty()));
                    self.state.insert(key, State::Done(Some(v.clone())));
                    return Ok(v);
                };
                if !decl.const_evaluable() || (!decl.is_const() && must_be_const) {
                    return Err(());
                }
                self.state.insert(key.clone(), State::Evaluating);
                let hint = Some(decl.declared.clone()).filter(|d| !d.is_empty());
                let r = match value {
                    VarValue::Expr(e) => self.expr(ty, e, hint.as_deref()),
                    VarValue::Builtin(c) => Ok(c),
                };
                match &r {
                    Ok(v) => {
                        self.state.insert(key, State::Done(Some(v.clone())));
                    }
                    // SpacemanDMM leaves the var marked as being evaluated: a later reference to it fails too.
                    Err(()) => {}
                }
                return r;
            }
            ty = ty.parent().ok_or(())?;
        }
    }

    fn expr(&mut self, ty: Ty<'m>, e: &Expr, hint: Option<&str>) -> Res {
        match form(e) {
            Form::Chain(c) => {
                let base_hint = if c.hops.is_empty() { hint } else { None };
                let mut v = self.root(ty, &c, base_hint)?;
                for h in &c.hops {
                    v = self.hop(ty, v, h)?;
                }
                Ok(v)
            }
            Form::Binary { op, lhs, rhs } => {
                let l = self.expr(ty, lhs, None)?;
                let r = self.expr(ty, rhs, None)?;
                binary(op, l, r)
            }
            Form::Ternary { cond, then_value, else_value } => {
                if self.expr(ty, cond, None)?.to_bool() {
                    self.expr(ty, then_value, hint)
                } else {
                    self.expr(ty, else_value, hint)
                }
            }
            Form::Assign { .. } => Err(()),
        }
    }

    fn args(&mut self, ty: Ty<'m>, args: Args<'_>) -> Result<String, ()> {
        let mut out = Vec::new();
        for a in args.iter() {
            match form(a) {
                Form::Assign { op: "=", lhs, rhs } => {
                    let key = match &lhs.kind {
                        ExprKind::Ident(n) => format!("{n:?}"),
                        _ => format!("{:?}", self.expr(ty, lhs, None)?),
                    };
                    out.push(format!("{key}={:?}", self.expr(ty, rhs, None)?));
                }
                _ => out.push(format!("{:?}", self.expr(ty, a, None)?)),
            }
        }
        Ok(out.join(","))
    }

    fn root(&mut self, ty: Ty<'m>, c: &Chain<'_>, hint: Option<&str>) -> Res {
        Ok(match &c.root {
            Root::Literal(text) => match literal(text) {
                Lit::Null => Value::Null(hint.map(str::to_owned)),
                Lit::Int(v) => Value::Float(v as f32),
                Lit::Float(v) => Value::Float(v),
                Lit::String(s) => Value::String(s),
                Lit::Resource(s) => Value::Resource(s),
                Lit::Interp(_) | Lit::Bad => return Err(()),
            },
            Root::NewPrefab { path, vars, args } => {
                let mut v = Vec::new();
                for (k, e) in vars {
                    v.push(format!("{k}={:?}", self.expr(ty, e, None)?));
                }
                let args = match args {
                    Some(a) => self.args(ty, *a)?,
                    None => String::new(),
                };
                Value::Other(format!("new {path}{{{}}}({args})", v.join(";")))
            }
            Root::NewImplicit { args } => {
                let args = match args {
                    Some(a) => self.args(ty, *a)?,
                    None => String::new(),
                };
                Value::Other(format!("new ({args})"))
            }
            Root::NewMini { .. } => return Err(()),
            Root::List(a) => Value::Other(format!("list({})", self.args(ty, *a)?)),
            Root::Call { name, args } => match *name {
                "matrix" | "newlist" | "icon" | "sound" | "filter" | "file" | "generator" => {
                    Value::Other(format!("{name}({})", self.args(ty, *args)?))
                }
                "sin" | "cos" | "arcsin" | "arccos" => {
                    if args.len() != 1 {
                        return Err(());
                    }
                    let Value::Float(x) = self.expr(ty, args.first().unwrap(), None)? else { return Err(()) };
                    Value::Float(match *name {
                        "sin" => x.sin(),
                        "cos" => x.cos(),
                        "arcsin" => x.asin(),
                        _ => x.acos(),
                    })
                }
                "rgb" => Value::String(self.rgb(ty, *args)?),
                "nameof" => {
                    if args.len() != 1 {
                        return Err(());
                    }
                    Value::String(nameof(args.first().unwrap()).ok_or(())?.to_owned())
                }
                _ => return Err(()),
            },
            Root::Prefab { path, vars } => {
                if vars.is_empty() {
                    Value::Prefab(resolve_path(ty, path).ok_or(())?)
                } else {
                    let mut v = Vec::new();
                    for (k, e) in vars.iter() {
                        v.push(format!("{k}={:?}", self.expr(ty, e, None)?));
                    }
                    Value::Other(format!("{}{{{}}}", resolve_path(ty, path).ok_or(())?, v.join(";")))
                }
            }
            Root::Ident(name) => match *name {
                "type" | "__TYPE__" => Value::Prefab(ty.path().to_string()),
                "parent_type" => Value::Prefab(ty.parent().ok_or(())?.path().to_string()),
                "__IMPLIED_TYPE__" => Value::Prefab(hint.ok_or(())?.to_string()),
                _ => self.lookup(ty, name, false)?,
            },
            Root::Group(e) => self.expr(ty, e, hint)?,
            _ => return Err(()),
        })
    }

    fn hop(&mut self, ty: Ty<'m>, v: Value, h: &Hop<'_>) -> Res {
        match (v, h) {
            (Value::Null(Some(hint)), Hop::Field { name, .. }) => {
                let t = self.m.ty(&hint).ok_or(())?;
                self.lookup(t, name, true)
            }
            (v, Hop::Unary { op, .. }) => match (*op, v) {
                ("-", Value::Float(f)) => Ok(Value::Float(-f)),
                ("~", Value::Float(f)) => Ok(from_bits(!(f as u32))),
                ("!", c) => Ok(from_bool(!c.to_bool())),
                _ => Err(()),
            },
            (Value::Prefab(path), Hop::Static { name, .. }) => {
                let t = self.m.ty(&path).ok_or(())?;
                self.lookup(t, name, false)
            }
            (Value::Prefab(path), Hop::ProcRef { name, .. }) => {
                let t = self.m.ty(&path).ok_or(())?;
                let p = t.proc(name).ok_or(())?;
                let kind = if p.declared_verb().unwrap_or(false) { "/verb" } else if p.declared_verb().is_some() { "/proc" } else { "" };
                Ok(Value::Prefab(format!("{}{kind}/{name}", if path == "/" { "" } else { path.as_str() })))
            }
            _ => {
                let _ = ty;
                Err(())
            }
        }
    }

    fn rgb(&mut self, ty: Ty<'m>, args: Args<'_>) -> Result<String, ()> {
        let n = args.len();
        if !(3..=4).contains(&n) {
            return Err(());
        }
        let mut parts = Vec::new();
        for a in args.iter() {
            if matches!(form(a), Form::Assign { .. }) {
                return Err(());
            }
            let Value::Float(f) = self.expr(ty, a, None)? else { return Err(()) };
            parts.push((f as i32).clamp(0, 255));
        }
        Ok(parts.iter().map(|p| format!("{p:02x}")).fold("#".to_string(), |s, p| s + &p))
    }
}

/// A relative prefab path resolved from `ty` (`.child`, `:x`); an absolute path as written.
fn resolve_path(ty: Ty<'_>, path: &str) -> Option<String> {
    if path.starts_with('/') && !path.contains(['.', ':']) {
        return Some(path.trim_end_matches('/').to_string()).map(|p| if p.is_empty() { "/".into() } else { p });
    }
    let _ = ty;
    None
}

fn nameof(e: &Expr) -> Option<&str> {
    match form(e) {
        Form::Chain(c) => match c.hops.last() {
            Some(Hop::Field { name, .. }) | Some(Hop::Call { name, .. }) | Some(Hop::Static { name, .. }) | Some(Hop::ProcRef { name, .. }) => Some(name),
            Some(_) => None,
            None => match c.root {
                Root::Ident(n) => Some(n),
                Root::Call { name, .. } => Some(name),
                Root::Group(e) => nameof(e),
                Root::Prefab { path, .. } => path.rsplit('/').next(),
                _ => None,
            },
        },
        _ => None,
    }
}

fn binary(op: &str, l: Value, r: Value) -> Res {
    use Value::*;
    if let (Float(a), Float(b)) = (&l, &r) {
        let (a, b) = (*a, *b);
        let v = match op {
            "+" => Some(Float(a + b)),
            "-" => Some(Float(a - b)),
            "*" => Some(Float(a * b)),
            "/" => Some(Float(a / b)),
            "%" => Some(Float(a % b)),
            "<" => Some(from_bool(a < b)),
            "<=" => Some(from_bool(a <= b)),
            ">" => Some(from_bool(a > b)),
            ">=" => Some(from_bool(a >= b)),
            "%%" => Some(Float(a - ((a / b).floor() * b))),
            "**" => Some(Float(a.powf(b))),
            "|" => Some(from_bits((a as u32) | (b as u32))),
            "&" => Some(from_bits((a as u32) & (b as u32))),
            "^" => Some(from_bits((a as u32) ^ (b as u32))),
            "<<" => Some(from_bits((a as u32).wrapping_shl(b as u32))),
            ">>" => Some(from_bits((a as u32).wrapping_shr(b as u32))),
            _ => None,
        };
        if let Some(v) = v {
            return Ok(v);
        }
    }
    match op {
        "+" => match (l, r) {
            (String(a), String(b)) => Ok(String(a + &b)),
            _ => Err(()),
        },
        "==" => Ok(from_bool(l == r)),
        "!=" | "<>" => Ok(from_bool(l != r)),
        "&&" => Ok(if l.to_bool() { r } else { l }),
        "||" => Ok(if l.to_bool() { l } else { r }),
        _ => Err(()),
    }
}

/// A var's value on one type: its initializer as written, or a builtin's constant.
pub enum VarValue<'m> {
    Expr(&'m Expr),
    Builtin(Value),
}

impl<'m> Ty<'m> {
    /// The names of the vars this type declares or assigns (builtins first, in table order, then source order).
    pub fn var_names(&self) -> Vec<String> {
        let mut out: Vec<String> = Vec::new();
        if let Some(b) = super::builtins::get().vars.get(self.path()) {
            out.extend(b.iter().map(|(n, _)| n.clone()));
        }
        for m in self.vars() {
            if !out.iter().any(|n| n == m.name()) {
                out.push(m.name().to_string());
            }
        }
        out
    }

    /// Whether this type declares `name` itself (a code declaration, or BYOND's builtin one).
    pub fn declares_var(&self, name: &str) -> bool {
        self.own_vars_named(name).any(|m| m.declares()) || super::builtins::get().var(self.path(), name).is_some_and(|b| b.declares)
    }

    pub fn has_own_var(&self, name: &str) -> bool {
        self.own_vars_named(name).next().is_some() || super::builtins::get().var(self.path(), name).is_some()
    }

    /// The last value this type gives the var: its last own assignment's initializer, or the builtin's constant; none when the var is
    /// declared here without a value.
    pub fn own_var_value(&self, name: &str) -> Option<VarValue<'m>> {
        let last = self.own_vars_named(name).last();
        match last {
            Some(m) if m.sized_list() => Some(VarValue::Builtin(Value::Other("new /list".into()))),
            Some(m) => m.initializer().map(VarValue::Expr),
            None => {
                let b = super::builtins::get().var(self.path(), name)?;
                match &b.constant {
                    None => None,
                    Some(Const::Null) => Some(VarValue::Builtin(Value::Null(None))),
                    Some(Const::Float(f)) => Some(VarValue::Builtin(Value::Float(*f))),
                    Some(Const::String(s)) => Some(VarValue::Builtin(Value::String(s.clone()))),
                    Some(Const::Resource(s)) => Some(VarValue::Builtin(Value::Resource(s.clone()))),
                    Some(Const::Other) => Some(VarValue::Builtin(Value::Other(String::new()))),
                }
            }
        }
    }
}

/// A var's declaration as the folder and the lints read it (the nearest declaring type's, a builtin's included).
#[derive(Clone, Debug)]
pub struct VarDeclaration {
    pub declared: String,
    pub flags: u32,
    pub builtin: bool,
    /// Where the declaration is (none for a builtin).
    pub site: Option<super::Site>,
}

impl VarDeclaration {
    pub fn is_static(&self) -> bool {
        self.flags & (1 | 8) != 0
    }
    pub fn is_const(&self) -> bool {
        self.flags & 2 != 0
    }
    pub fn is_tmp(&self) -> bool {
        self.flags & 4 != 0
    }
    pub fn is_protected(&self) -> bool {
        self.flags & VAR_SPACEMAN_PROTECTED != 0
    }
    /// SpacemanDMM's `is_const_evaluable`: const, or neither static nor protected.
    pub fn const_evaluable(&self) -> bool {
        self.is_const() || !(self.is_static() || self.is_protected())
    }
}

impl<'m> Ty<'m> {
    /// The declaration of `name` on this type or the nearest parent that declares it.
    pub fn var_declaration(&self, name: &str) -> Option<VarDeclaration> {
        super::reads::note(|| super::reads::Read::Lookup { owner: std::sync::Arc::from(self.path()), name: std::sync::Arc::from(name), kind: super::reads::LookupKind::Var });
        super::profile::time(super::profile::VAR_DECL, || self.var_declaration_uncounted(name))
    }

    fn var_declaration_uncounted(&self, name: &str) -> Option<VarDeclaration> {
        self.m_ref().remembered_declaration(self.id, name, || self.find_var_declaration(name))
    }

    fn find_var_declaration(&self, name: &str) -> Option<VarDeclaration> {
        let mut cur = Some(*self);
        while let Some(t) = cur {
            if let Some(m) = t.own_vars_named(name).find(|m| m.declares()) {
                return Some(VarDeclaration { declared: m.declared_type(), flags: m.flags(), builtin: false, site: m.site() });
            }
            if let Some(b) = super::builtins::get().var(t.path(), name).filter(|b| b.declares) {
                return Some(VarDeclaration { declared: b.declared.clone(), flags: b.flags, builtin: true, site: None });
            }
            cur = t.parent();
        }
        None
    }
}

#[allow(dead_code)]
fn _kinds(_: MemberKind) {}
