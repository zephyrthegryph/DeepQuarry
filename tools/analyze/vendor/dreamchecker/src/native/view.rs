//! The compiler front end's typed expressions (`dm_syntax::Expr`) read in SpacemanDMM's terms: a term with its follows (field
//! accesses, calls, indexes, unary operators) or an operator over expressions, each piece at the offset SpacemanDMM places it.
//!
//! The reading is the one the analysis bridge made (dmbc `analysis_bridge.rs`): `a.b()` is the term `a` followed by the call `b` at
//! the `.`; a prefix operator follows its operand at the expression's start, a postfix one at the operand's end; `new X(...)` is
//! one term; `locate(..) in L` and `input(..) as T in L` are one term. An expression that is exactly the expansion of a BYOND
//! constant written in the source (`NORTH`, dmbc's predefined macro) is that constant's name, as SpacemanDMM, whose preprocessor
//! does not define them, sees it.
use dm_syntax::{Expr, ExprKind};

use super::input::{InputType, Site};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum UnaryOp {
    Neg,
    Not,
    BitNot,
    Deref,
    Ref,
    PreIncr,
    PreDecr,
    PostIncr,
    PostDecr,
}

impl UnaryOp {
    pub fn name(self) -> &'static str {
        match self {
            UnaryOp::Neg => "-",
            UnaryOp::Not => "!",
            UnaryOp::BitNot => "~",
            UnaryOp::PreIncr | UnaryOp::PostIncr => "++",
            UnaryOp::PreDecr | UnaryOp::PostDecr => "--",
            UnaryOp::Ref => "&",
            UnaryOp::Deref => "*",
        }
    }
    pub fn around(self, expr: &str) -> String {
        match self {
            UnaryOp::Neg => format!("-{expr}"),
            UnaryOp::Not => format!("!{expr}"),
            UnaryOp::BitNot => format!("~{expr}"),
            UnaryOp::PreIncr => format!("++{expr}"),
            UnaryOp::PostIncr => format!("{expr}++"),
            UnaryOp::PreDecr => format!("--{expr}"),
            UnaryOp::PostDecr => format!("{expr}--"),
            UnaryOp::Ref => format!("&{expr}"),
            UnaryOp::Deref => format!("*{expr}"),
        }
    }
    fn of(op: &str) -> Option<UnaryOp> {
        Some(match op {
            "-" => UnaryOp::Neg,
            "!" => UnaryOp::Not,
            "~" => UnaryOp::BitNot,
            "*" => UnaryOp::Deref,
            "&" => UnaryOp::Ref,
            "pre++" => UnaryOp::PreIncr,
            "pre--" => UnaryOp::PreDecr,
            "post++" => UnaryOp::PostIncr,
            "post--" => UnaryOp::PostDecr,
            _ => return None,
        })
    }
}

/// The binary operators SpacemanDMM knows, by its spelling (`<>` is `!=`).
pub fn binary_op(op: &str) -> Option<&'static str> {
    Some(match op {
        "+" => "+",
        "-" => "-",
        "*" => "*",
        "/" => "/",
        "**" => "**",
        "%" => "%",
        "%%" => "%%",
        "==" => "==",
        "!=" | "<>" => "!=",
        "<" => "<",
        ">" => ">",
        "<=" => "<=",
        ">=" => ">=",
        "<=>" => "<=>",
        "~=" => "~=",
        "~!" => "~!",
        "&" => "&",
        "^" => "^",
        "|" => "|",
        "<<" => "<<",
        ">>" => ">>",
        "&&" => "&&",
        "||" => "||",
        "in" => "in",
        "to" => "to",
        _ => return None,
    })
}

pub fn assign_op(op: &str) -> Option<&'static str> {
    Some(match op {
        "=" => "=",
        "+=" => "+=",
        "-=" => "-=",
        "*=" => "*=",
        "/=" => "/=",
        "%=" => "%=",
        "%%=" => "%%=",
        ":=" => ":=",
        "&=" => "&=",
        "&&=" => "&&=",
        "|=" => "|=",
        "||=" => "||=",
        "^=" => "^=",
        "<<=" => "<<=",
        ">>=" => ">>=",
        _ => return None,
    })
}

/// How a field or call is reached: `.`, `:`, `?.`, `?:`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Access {
    Dot,
    Colon,
    SafeDot,
    SafeColon,
}

impl Access {
    fn of(safe: bool, colon: bool) -> Access {
        match (safe, colon) {
            (false, false) => Access::Dot,
            (false, true) => Access::Colon,
            (true, false) => Access::SafeDot,
            (true, true) => Access::SafeColon,
        }
    }
    pub fn is_colon(self) -> bool {
        matches!(self, Access::Colon | Access::SafeColon)
    }
}

/// An interpolated string's embedded expression: parsed on its own, its offsets relative to `base`.
pub struct Part {
    pub expr: Option<Expr>,
    pub base: usize,
}

pub enum Term<'e> {
    Null,
    Int(i32),
    Float(f32),
    Str(String),
    Resource(String),
    /// `"[a] b"`: the text before the first part, each part (none when it could not be read) and the text after it.
    Interp { first: String, parts: Vec<(Option<Part>, String)> },
    Ident(String),
    /// A type path (`/obj/item`, `.foo`) with its `{x = 1}` fields.
    Prefab { path: &'e str, fields: Vec<(&'e str, &'e Expr)> },
    /// A parenthesized expression.
    Group(&'e Expr),
    Call { name: &'e str, args: Vec<&'e Expr> },
    SelfCall(Vec<&'e Expr>),
    ParentCall(Vec<&'e Expr>),
    NewImplicit(Option<Vec<&'e Expr>>),
    NewPrefab { path: &'e str, args: Option<Vec<&'e Expr>> },
    NewMiniExpr,
    List(Vec<&'e Expr>),
    Input { args: Vec<&'e Expr>, input_type: Option<InputType>, in_list: Option<&'e Expr> },
    Locate { args: Vec<&'e Expr>, in_list: Option<&'e Expr> },
    Pick(Vec<(Option<&'e Expr>, &'e Expr)>),
    DynamicCall(Vec<&'e Expr>, Vec<&'e Expr>),
    ExternalCall { library: Option<&'e Expr>, function: Option<&'e Expr>, args: Vec<&'e Expr> },
    As,
    Proc,
    TypeConst,
    ImpliedType,
    /// A form the reading has no term for (it is not visited).
    Unread,
}

pub enum Follow<'e> {
    Unary(UnaryOp),
    Field(Access, &'e str),
    Call(Access, &'e str, Vec<&'e Expr>),
    Index(&'e Expr),
    StaticField(&'e str),
    ProcReference(&'e str),
}

pub struct Base<'e> {
    pub term: Term<'e>,
    pub term_at: usize,
    pub follows: Vec<(Follow<'e>, usize)>,
}

pub enum Shape<'e> {
    Base(Base<'e>),
    Binary { op: &'static str, lhs: &'e Expr, rhs: &'e Expr },
    Assign { op: &'static str, lhs: &'e Expr, rhs: &'e Expr },
    Ternary { cond: &'e Expr, if_: &'e Expr, else_: &'e Expr },
    /// An operator SpacemanDMM does not have (not visited).
    Unread,
}

/// A call's arguments without the empty ones (`f(a, , b)`: dm-syntax's zero-width `null`), which SpacemanDMM's tree has no node for.
pub fn args(args: &[Expr]) -> Vec<&Expr> {
    args.iter().filter(|a| !(a.span.start == a.span.end && matches!(&a.kind, ExprKind::Literal(t) if t == "null"))).collect()
}

/// Reads expressions; `shift` is added to every offset (an interpolated string's parts are parsed on their own).
pub struct Reader<'s, 'a> {
    pub site: &'s (dyn Site + 'a),
    pub shift: usize,
}

impl Reader<'_, '_> {
    /// The BYOND constant an expression is exactly the expansion of, if any.
    fn constant_name(&mut self, e: &Expr) -> Option<String> {
        if self.shift != 0 || !could_be_constant(e) {
            return None;
        }
        let (range, name, nested) = self.site.invocation(e.span.start)?;
        if range.start != e.span.start || range.end != e.span.end {
            return None;
        }
        let table = super::builtins::constants();
        if table.contains_key(&name) {
            return Some(name);
        }
        // An alias (`#define MY_FLAG WAVE_BOUNDED`): the one name its expansion expanded, when that is a constant.
        match nested.as_slice() {
            [only] if table.contains_key(only) => Some(only.clone()),
            _ => None,
        }
    }

    pub fn shape<'e>(&mut self, e: &'e Expr) -> Shape<'e> {
        match &e.kind {
            ExprKind::Binary { op, lhs, rhs } => {
                if op == "in" {
                    if let Some(b) = self.in_term(e, lhs, rhs) {
                        return Shape::Base(b);
                    }
                }
                if let Some(op) = assign_op(op) {
                    return Shape::Assign { op, lhs, rhs };
                }
                match binary_op(op) {
                    Some(op) => Shape::Binary { op, lhs, rhs },
                    None => Shape::Unread,
                }
            }
            ExprKind::Conditional { condition, then_value, else_value } => Shape::Ternary { cond: condition, if_: then_value, else_: else_value },
            _ => Shape::Base(self.base(e)),
        }
    }

    /// `locate(..) in L`, `input(..) in L`, `input(..) as T in L`: one term carrying the list.
    fn in_term<'e>(&mut self, _e: &'e Expr, lhs: &'e Expr, rhs: &'e Expr) -> Option<Base<'e>> {
        if let ExprKind::Call { callee, args: a } = &lhs.kind {
            if let ExprKind::Ident(n) = &callee.kind {
                if n == "locate" {
                    return Some(Base { term: Term::Locate { args: args(a), in_list: Some(rhs) }, term_at: lhs.span.start, follows: Vec::new() });
                }
                if n == "input" {
                    return Some(Base { term: Term::Input { args: args(a), input_type: None, in_list: Some(rhs) }, term_at: lhs.span.start, follows: Vec::new() });
                }
            }
        }
        if let ExprKind::TypeFilter { value, types } = &lhs.kind {
            if let ExprKind::Call { callee, args: a } = &value.kind {
                if matches!(&callee.kind, ExprKind::Ident(n) if n == "input") {
                    return Some(Base {
                        term: Term::Input { args: args(a), input_type: Some(InputType::from_names(types)), in_list: Some(rhs) },
                        term_at: lhs.span.start,
                        follows: Vec::new(),
                    });
                }
            }
        }
        None
    }

    /// `e` as a term with follows; an operator expression is a parenthesized term (SpacemanDMM's `Term::Expr`) at `e`'s start.
    pub fn base<'e>(&mut self, e: &'e Expr) -> Base<'e> {
        let at = e.span.start;
        let single = |term| Base { term, term_at: at, follows: Vec::new() };
        match &e.kind {
            ExprKind::Ident(name) => single(match name.as_str() {
                "__PROC__" => Term::Proc,
                "__TYPE__" => Term::TypeConst,
                "__IMPLIED_TYPE__" => Term::ImpliedType,
                _ => Term::Ident(name.clone()),
            }),
            ExprKind::Literal(text) => match self.constant_name(e) {
                Some(name) => single(Term::Ident(name)),
                None => single(literal(text)),
            },
            ExprKind::TypePath(p) => single(Term::Prefab { path: p, fields: Vec::new() }),
            ExprKind::Group(inner) => match self.constant_name(e) {
                Some(name) => single(Term::Ident(name)),
                None => single(Term::Group(inner)),
            },
            ExprKind::Unary { op, value } => {
                if op == "new" {
                    return self.new_term(e, value);
                }
                let Some(uop) = UnaryOp::of(op) else { return self.base(value) };
                let mut b = self.operand(value);
                b.follows.push((Follow::Unary(uop), if op.starts_with("post") { value.span.end } else { at }));
                b
            }
            ExprKind::Member { object, selector, via_colon } => self.follow_on(object, Follow::Field(Access::of(false, *via_colon), selector)),
            ExprKind::SafeMember { object, selector, via_colon } => self.follow_on(object, Follow::Field(Access::of(true, *via_colon), selector)),
            ExprKind::StaticMember { object, selector } => self.follow_on(object, Follow::StaticField(selector)),
            ExprKind::Index { object, index } | ExprKind::SafeIndex { object, index } => self.follow_on(object, Follow::Index(index)),
            ExprKind::Call { callee, args: a } => self.call(e, callee, a),
            ExprKind::TypeFilter { value, types } => {
                if let ExprKind::Call { callee, args: a } = &value.kind {
                    if matches!(&callee.kind, ExprKind::Ident(n) if n == "input") {
                        return single(Term::Input { args: args(a), input_type: Some(InputType::from_names(types)), in_list: None });
                    }
                }
                single(Term::Unread)
            }
            ExprKind::ObjectInitializer { object, fields } => match &object.kind {
                ExprKind::TypePath(p) => single(Term::Prefab { path: p, fields: fields.iter().map(|(k, v)| (k.as_str(), v)).collect() }),
                _ => single(Term::Unread),
            },
            ExprKind::Binary { .. } | ExprKind::Conditional { .. } => match self.shape(e) {
                Shape::Base(b) => b,
                _ => single(Term::Group(e)),
            },
        }
    }

    /// An operand that takes follows: its own term and follows, or (an operator expression) a parenthesized term at its start.
    fn operand<'e>(&mut self, e: &'e Expr) -> Base<'e> {
        match &e.kind {
            ExprKind::Binary { .. } | ExprKind::Conditional { .. } => match self.shape(e) {
                Shape::Base(b) => b,
                _ => Base { term: Term::Group(e), term_at: e.span.start, follows: Vec::new() },
            },
            _ => self.base(e),
        }
    }

    fn follow_on<'e>(&mut self, object: &'e Expr, follow: Follow<'e>) -> Base<'e> {
        let mut b = self.operand(object);
        b.follows.push((follow, object.span.end));
        b
    }

    fn call<'e>(&mut self, e: &'e Expr, callee: &'e Expr, a: &'e [Expr]) -> Base<'e> {
        let at = e.span.start;
        let single = |term| Base { term, term_at: at, follows: Vec::new() };
        match &callee.kind {
            ExprKind::Ident(name) => single(match name.as_str() {
                "new" => Term::NewImplicit(if e.span.end == callee.span.end { None } else { Some(args(a)) }),
                "list" | "alist" => Term::List(args(a)),
                "input" => Term::Input { args: args(a), input_type: None, in_list: None },
                "locate" => Term::Locate { args: args(a), in_list: None },
                "pick" => Term::Pick(
                    a.iter()
                        .map(|x| match &x.kind {
                            ExprKind::Binary { op, lhs, rhs } if op == ";" => (Some(&**lhs), &**rhs),
                            _ => (None, x),
                        })
                        .collect(),
                ),
                "." => Term::SelfCall(args(a)),
                ".." => Term::ParentCall(args(a)),
                "as" => Term::As,
                _ => Term::Call { name, args: args(a) },
            }),
            ExprKind::Call { callee: inner, args: first } if matches!(&inner.kind, ExprKind::Ident(n) if n == "call") => {
                single(Term::DynamicCall(args(first), args(a)))
            }
            ExprKind::Call { callee: inner, args: first } if matches!(&inner.kind, ExprKind::Ident(n) if n == "call_ext") => {
                let mut first = first.iter();
                let x = first.next();
                let y = first.next();
                single(match y {
                    Some(function) => Term::ExternalCall { library: x, function: Some(function), args: args(a) },
                    None => Term::ExternalCall { library: None, function: x, args: args(a) },
                })
            }
            ExprKind::Member { object, selector, via_colon } => self.follow_on(object, Follow::Call(Access::of(false, *via_colon), selector, args(a))),
            ExprKind::SafeMember { object, selector, via_colon } => self.follow_on(object, Follow::Call(Access::of(true, *via_colon), selector, args(a))),
            ExprKind::StaticMember { object, selector } => self.follow_on(object, Follow::ProcReference(selector)),
            _ => single(Term::Unread),
        }
    }

    /// `new X(...)`: the type (a prefab, or a name with field accesses) and the first argument list are the term; the rest of the
    /// postfix chain follows it.
    fn new_term<'e>(&mut self, e: &'e Expr, value: &'e Expr) -> Base<'e> {
        let at = e.span.start;
        let mut posts: Vec<(&'e Expr, usize)> = Vec::new();
        let mut core = value;
        loop {
            let inner = match &core.kind {
                ExprKind::Member { object, .. }
                | ExprKind::SafeMember { object, .. }
                | ExprKind::StaticMember { object, .. }
                | ExprKind::Index { object, .. }
                | ExprKind::SafeIndex { object, .. }
                | ExprKind::ObjectInitializer { object, .. } => object,
                ExprKind::Call { callee, .. } => callee,
                ExprKind::Unary { op, value } if op.starts_with("post") => value,
                _ => break,
            };
            posts.push((core, inner.span.end));
            core = inner;
        }
        posts.reverse();
        let call_at = posts.iter().position(|(p, _)| matches!(p.kind, ExprKind::Call { .. }));
        let (target, rest) = match call_at {
            Some(i) => (&posts[..i], &posts[i..]),
            None => (&posts[..], &posts[posts.len()..]),
        };
        let (call_args, rest) = match rest.split_first() {
            Some(((p, _), tail)) => match &p.kind {
                ExprKind::Call { args: a, .. } => (Some(args(a)), tail),
                _ => (None, rest),
            },
            None => (None, rest),
        };
        let term = match &core.kind {
            ExprKind::TypePath(p) => {
                if target.iter().any(|(t, _)| !matches!(t.kind, ExprKind::ObjectInitializer { .. })) {
                    return Base { term: Term::Unread, term_at: at, follows: Vec::new() };
                }
                Term::NewPrefab { path: p, args: call_args }
            }
            ExprKind::Ident(_) => {
                if target.iter().any(|(t, _)| !matches!(t.kind, ExprKind::Member { .. } | ExprKind::SafeMember { .. })) {
                    return Base { term: Term::Unread, term_at: at, follows: Vec::new() };
                }
                Term::NewMiniExpr
            }
            _ => return Base { term: Term::Unread, term_at: at, follows: Vec::new() },
        };
        let mut follows = Vec::new();
        for (p, place) in rest {
            let f = match &p.kind {
                ExprKind::Member { selector, via_colon, .. } => Follow::Field(Access::of(false, *via_colon), selector),
                ExprKind::SafeMember { selector, via_colon, .. } => Follow::Field(Access::of(true, *via_colon), selector),
                ExprKind::StaticMember { selector, .. } => Follow::StaticField(selector),
                ExprKind::Index { index, .. } | ExprKind::SafeIndex { index, .. } => Follow::Index(index),
                ExprKind::Unary { op, .. } => Follow::Unary(if op == "post++" { UnaryOp::PostIncr } else { UnaryOp::PostDecr }),
                _ => return Base { term: Term::Unread, term_at: at, follows: Vec::new() },
            };
            follows.push((f, *place));
        }
        Base { term, term_at: at, follows }
    }
}

/// Whether `e` is a value some BYOND constant has (`1`, `(-1)`, `"male"`): only then can it be one's expansion.
fn could_be_constant(e: &Expr) -> bool {
    use super::builtins::constant_values;
    let (numbers, texts) = constant_values();
    match &e.kind {
        ExprKind::Literal(text) => match literal(text) {
            Term::Int(n) => numbers.contains(&(n as f32).to_bits()),
            Term::Float(n) => numbers.contains(&n.to_bits()),
            Term::Str(s) => texts.contains(&s),
            _ => false,
        },
        ExprKind::Group(inner) => match &inner.kind {
            ExprKind::Unary { op, value } if op == "-" => match &value.kind {
                ExprKind::Literal(text) => match literal(text) {
                    Term::Int(n) => numbers.contains(&(-(n as f32)).to_bits()),
                    Term::Float(n) => numbers.contains(&(-n).to_bits()),
                    _ => false,
                },
                _ => false,
            },
            _ => could_be_constant(inner),
        },
        _ => false,
    }
}

/// A literal token as SpacemanDMM's lexer reads it (dm-syntax's literal decoder follows its rules).
pub fn literal<'e>(text: &str) -> Term<'e> {
    if text == "null" {
        return Term::Null;
    }
    let decoded = match dm_syntax::decode_literal(text) {
        Ok(lit) => lit,
        Err(dm_syntax::LiteralError { fallback: Some(lit), .. }) => lit,
        Err(_) => return Term::Unread,
    };
    match decoded {
        dm_syntax::Literal::Int(v) => Term::Int(v),
        dm_syntax::Literal::Float(v) => Term::Float(v),
        dm_syntax::Literal::String(s) => Term::Str(s),
        dm_syntax::Literal::Resource(s) => Term::Resource(s),
        dm_syntax::Literal::InterpString(interp) => {
            let parts = interp
                .parts
                .into_iter()
                .map(|part| {
                    let expr = part.expr.map(|dm_syntax::InterpExpr { source, offset }| {
                        // A part broken over lines with `\` continuations: blank the continuation, keeping every offset.
                        let source = source.replace("\\\r\n", "   ").replace("\\\n", "  ");
                        let parsed = dm_syntax::parse_expression(&source);
                        Part { expr: parsed.expr.filter(|_| parsed.diagnostics.is_empty()), base: offset }
                    });
                    (expr, part.text)
                })
                .collect();
            Term::Interp { first: interp.first, parts }
        }
    }
}

impl Term<'_> {
    /// `null`, a number, a string or a prefab.
    pub fn is_static(&self) -> bool {
        matches!(self, Term::Null | Term::Int(_) | Term::Float(_) | Term::Str(_) | Term::Prefab { .. })
    }

    /// SpacemanDMM's `Term::is_debug` spelling for the few terms a diagnostic prints (`Int(1)`, `Ident("NORTH")`).
    pub fn debug(&self) -> String {
        match self {
            Term::Null => "Null".into(),
            Term::Int(n) => format!("Int({n})"),
            Term::Float(n) => format!("Float({n:?})"),
            Term::Str(s) => format!("String({s:?})"),
            Term::Resource(s) => format!("Resource({s:?})"),
            Term::Ident(s) => format!("Ident({s:?})"),
            Term::Proc => "__PROC__".into(),
            Term::TypeConst => "__TYPE__".into(),
            Term::ImpliedType => "__IMPLIED_TYPE__".into(),
            Term::As => "As".into(),
            Term::Call { name, .. } => format!("Call({name:?}, ..)"),
            _ => "..".into(),
        }
    }
}
