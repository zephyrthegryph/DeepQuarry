//! Expressions of the compiler's typed bodies (`dm_syntax::Expr`), read the way the analysis reads them.
//!
//! dmbc's tree nests a receiver chain (`a.b(c)[d]` is `Index { Call { Member { a, b }, c }, d }`); the analysis asks "what is the root,
//! and what follows it". [`chain`] peels a chain once into a [`Chain`]: a [`Root`] and the [`Hop`]s after it, borrowed from the tree
//! (nothing is copied or rebuilt, so a node's address is stable for the life of the model). The call forms dmbc spells as ordinary
//! calls (`list(...)`, `new`, `locate(...) in L`, `..()`, `call(a)(b)`) are classified there, once, by the rules the old conversion to
//! dreammaker's AST used (`dmbc::analysis_bridge`): a prefix unary operator follows its operand as a hop, an empty argument
//! (`f(a, , b)`) is skipped, `x::y()` is a proc reference that drops its arguments.

use dm_syntax::{Expr, ExprKind};

/// What an expression is, at the level the analysis distinguishes.
#[derive(Clone, Debug)]
pub enum Form<'a> {
    /// A term and what follows it.
    Chain(Chain<'a>),
    /// `a op b` (not an assignment).
    Binary { op: &'a str, lhs: &'a Expr, rhs: &'a Expr },
    /// `a = b`, `a += b`, ... (inside an expression, or an assignment statement).
    Assign { op: &'a str, lhs: &'a Expr, rhs: &'a Expr },
    /// `c ? a : b`.
    Ternary { cond: &'a Expr, then_value: &'a Expr, else_value: &'a Expr },
}

#[derive(Clone, Debug)]
pub struct Chain<'a> {
    pub root: Root<'a>,
    /// The node the root was read from (its span is where the term starts).
    pub root_expr: &'a Expr,
    pub hops: Vec<Hop<'a>>,
}

/// The arguments of a call, the empty ones (`f(a, , b)`) left out.
#[derive(Clone, Copy, Debug)]
pub struct Args<'a>(pub &'a [Expr]);

impl<'a> Args<'a> {
    pub fn iter(&self) -> impl Iterator<Item = &'a Expr> + 'a {
        self.0.iter().filter(|a| !is_empty_argument(a))
    }
    pub fn len(&self) -> usize {
        self.iter().count()
    }
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
    pub fn get(&self, i: usize) -> Option<&'a Expr> {
        self.iter().nth(i)
    }
    pub fn first(&self) -> Option<&'a Expr> {
        self.get(0)
    }
}

pub fn is_empty_argument(a: &Expr) -> bool {
    a.span.start == a.span.end && matches!(&a.kind, ExprKind::Literal(t) if t == "null")
}

#[derive(Clone, Debug)]
pub enum Root<'a> {
    /// A name (`src`, `usr`, a local, a var, `global`, `__PROC__`).
    Ident(&'a str),
    /// `null`, a number, a string or resource, an interpolated string: decode with [`literal`].
    Literal(&'a str),
    /// A type path (`/obj/item`), with `{vars}` when written with an initializer block.
    Prefab { path: &'a str, vars: &'a [(String, Expr)] },
    /// `name(args)` for any name not below.
    Call { name: &'a str, args: Args<'a> },
    /// `list(...)`, `alist(...)`.
    List(Args<'a>),
    /// `input(...)`, with `as T|U` and `in L` when written.
    Input { args: Args<'a>, types: Option<&'a [String]>, in_list: Option<&'a Expr> },
    /// `locate(...)`, with `in L` when written.
    Locate { args: Args<'a>, in_list: Option<&'a Expr> },
    /// `pick(...)`: each argument, with its weight when written `weight; value`.
    Pick(Vec<(Option<&'a Expr>, &'a Expr)>),
    /// `new` with no type (`new()`, a bare `new`): the arguments when written.
    NewImplicit { args: Option<Args<'a>> },
    /// `new /path{vars}(args)`.
    NewPrefab { path: &'a str, vars: Vec<&'a (String, Expr)>, args: Option<Args<'a>> },
    /// `new name.field(args)`: a name and field accesses naming the type.
    NewMini { name: &'a str, fields: Vec<(&'a str, bool, bool)>, args: Option<Args<'a>> },
    /// `.(args)`.
    SelfCall(Args<'a>),
    /// `..(args)`.
    ParentCall(Args<'a>),
    /// `call(first)(args)`.
    DynamicCall { first: Args<'a>, args: Args<'a> },
    /// `call_ext(library, function)(args)`.
    ExternalCall { first: Args<'a>, args: Args<'a> },
    /// A parenthesized expression, or a non-chain expression a chain starts from.
    Group(&'a Expr),
    /// A form the analysis has no reading for (`new` over an expression); visited, never matched.
    Opaque(&'a Expr),
}

#[derive(Clone, Debug)]
pub enum Hop<'a> {
    /// `.name`, `?.name`, `:name`.
    Field { name: &'a str, safe: bool, colon: bool, at: &'a Expr },
    /// `.name(args)`.
    Call { name: &'a str, args: Args<'a>, safe: bool, colon: bool, at: &'a Expr },
    /// `[index]`, `?[index]`.
    Index { index: &'a Expr, safe: bool, at: &'a Expr },
    /// `::name`.
    Static { name: &'a str, at: &'a Expr },
    /// `::name()`: a proc reference (the arguments are dropped).
    ProcRef { name: &'a str, at: &'a Expr },
    /// A unary operator on what precedes it: `-`, `!`, `~`, `*`, `&`, `pre++`, `pre--`, `post++`, `post--`.
    Unary { op: &'a str, at: &'a Expr },
}

impl<'a> Chain<'a> {
    /// The expression the root and the first `n` hops make (what dreammaker's AST rebuilt as `term` + `follow[..n]`): the root's node
    /// for `n == 0`, else the node of hop `n - 1`.
    pub fn prefix_node(&self, n: usize) -> &'a Expr {
        if n == 0 {
            self.root_expr
        } else {
            self.hops[n - 1].node()
        }
    }

    /// Where hop `i` sits: right after the expression it applies to (its `.`, `[`, `(`), as dreammaker placed a follow.
    pub fn hop_site(&self, i: usize) -> super::Site {
        super::Site(self.prefix_node(i).span.end as u32)
    }

    /// Where the root term starts.
    pub fn root_site(&self) -> super::Site {
        super::Site(self.root_expr.span.start as u32)
    }
}

impl<'a> Hop<'a> {
    /// The node this hop was read from: its object is everything before the hop.
    pub fn node(&self) -> &'a Expr {
        match self {
            Hop::Field { at, .. } | Hop::Call { at, .. } | Hop::Index { at, .. } | Hop::Static { at, .. } | Hop::ProcRef { at, .. } | Hop::Unary { at, .. } => at,
        }
    }
}

pub fn is_assign_op(op: &str) -> bool {
    matches!(op, "=" | "+=" | "-=" | "*=" | "/=" | "%=" | "%%=" | "&=" | "|=" | "^=" | "<<=" | ">>=" | "&&=" | "||=" | ":=")
}

/// The form of `e`.
pub fn form(e: &Expr) -> Form<'_> {
    match &e.kind {
        ExprKind::Binary { op, lhs, rhs } => {
            if op == "in" {
                if let Some(c) = in_form(lhs, rhs) {
                    return Form::Chain(Chain { root: c, root_expr: e, hops: Vec::new() });
                }
            }
            if is_assign_op(op) {
                Form::Assign { op, lhs, rhs }
            } else {
                Form::Binary { op, lhs, rhs }
            }
        }
        ExprKind::Conditional { condition, then_value, else_value } => Form::Ternary { cond: condition, then_value, else_value },
        _ => Form::Chain(chain_of(e)),
    }
}

/// `e` as a chain, when it is one (not a binary, assignment or conditional expression).
pub fn chain(e: &Expr) -> Option<Chain<'_>> {
    match form(e) {
        Form::Chain(c) => Some(c),
        _ => None,
    }
}

/// `locate(...) in L`, `input(...) in L`, `input(...) as T in L`.
fn in_form<'a>(lhs: &'a Expr, rhs: &'a Expr) -> Option<Root<'a>> {
    if let ExprKind::Call { callee, args } = &lhs.kind {
        if let ExprKind::Ident(n) = &callee.kind {
            if n == "locate" {
                return Some(Root::Locate { args: Args(args), in_list: Some(rhs) });
            }
            if n == "input" {
                return Some(Root::Input { args: Args(args), types: None, in_list: Some(rhs) });
            }
        }
    }
    if let ExprKind::TypeFilter { value, types } = &lhs.kind {
        if let ExprKind::Call { callee, args } = &value.kind {
            if matches!(&callee.kind, ExprKind::Ident(n) if n == "input") {
                return Some(Root::Input { args: Args(args), types: Some(types), in_list: Some(rhs) });
            }
        }
    }
    None
}

fn chain_of(e: &Expr) -> Chain<'_> {
    let mut hops = Vec::new();
    let mut cur = e;
    loop {
        match &cur.kind {
            ExprKind::Member { object, selector, via_colon } => {
                hops.push(Hop::Field { name: selector, safe: false, colon: *via_colon, at: cur });
                cur = object;
            }
            ExprKind::SafeMember { object, selector, via_colon } => {
                hops.push(Hop::Field { name: selector, safe: true, colon: *via_colon, at: cur });
                cur = object;
            }
            ExprKind::StaticMember { object, selector } => {
                hops.push(Hop::Static { name: selector, at: cur });
                cur = object;
            }
            ExprKind::Index { object, index } => {
                hops.push(Hop::Index { index, safe: false, at: cur });
                cur = object;
            }
            ExprKind::SafeIndex { object, index } => {
                hops.push(Hop::Index { index, safe: true, at: cur });
                cur = object;
            }
            ExprKind::Call { callee, args } => match &callee.kind {
                ExprKind::Member { object, selector, via_colon } => {
                    hops.push(Hop::Call { name: selector, args: Args(args), safe: false, colon: *via_colon, at: cur });
                    cur = object;
                }
                ExprKind::SafeMember { object, selector, via_colon } => {
                    hops.push(Hop::Call { name: selector, args: Args(args), safe: true, colon: *via_colon, at: cur });
                    cur = object;
                }
                ExprKind::StaticMember { object, selector } => {
                    hops.push(Hop::ProcRef { name: selector, at: cur });
                    cur = object;
                }
                _ => break,
            },
            ExprKind::Unary { op, value } if op != "new" && is_hop_unary(op) => {
                hops.push(Hop::Unary { op, at: cur });
                cur = value;
            }
            ExprKind::Unary { op, value } if op != "new" => {
                // An operator the analysis has no hop for reads as its operand.
                cur = value;
            }
            _ => break,
        }
    }
    hops.reverse();
    if let ExprKind::Unary { op, value } = &cur.kind {
        if op == "new" {
            return new_chain(cur, value, hops);
        }
    }
    Chain { root: root_of(cur), root_expr: cur, hops }
}

fn is_hop_unary(op: &str) -> bool {
    matches!(op, "-" | "!" | "~" | "*" | "&" | "pre++" | "pre--" | "post++" | "post--")
}

fn root_of(e: &Expr) -> Root<'_> {
    match &e.kind {
        ExprKind::Ident(name) => Root::Ident(name),
        ExprKind::Literal(text) => Root::Literal(text),
        ExprKind::TypePath(p) => Root::Prefab { path: p, vars: &[] },
        ExprKind::ObjectInitializer { object, fields } => match &object.kind {
            ExprKind::TypePath(p) => Root::Prefab { path: p, vars: fields },
            _ => Root::Opaque(e),
        },
        ExprKind::Group(inner) => Root::Group(inner),
        ExprKind::TypeFilter { value, types } => match &value.kind {
            ExprKind::Call { callee, args } if matches!(&callee.kind, ExprKind::Ident(n) if n == "input") => {
                Root::Input { args: Args(args), types: Some(types), in_list: None }
            }
            _ => Root::Opaque(e),
        },
        ExprKind::Call { callee, args } => match &callee.kind {
            ExprKind::Ident(name) => match name.as_str() {
                "new" => Root::NewImplicit { args: if e.span.end == callee.span.end { None } else { Some(Args(args)) } },
                "list" | "alist" => Root::List(Args(args)),
                "input" => Root::Input { args: Args(args), types: None, in_list: None },
                "locate" => Root::Locate { args: Args(args), in_list: None },
                "pick" => Root::Pick(
                    args.iter()
                        .filter(|a| !is_empty_argument(a))
                        .map(|a| match &a.kind {
                            ExprKind::Binary { op, lhs, rhs } if op == ";" => (Some(&**lhs), &**rhs),
                            _ => (None, a),
                        })
                        .collect(),
                ),
                "." => Root::SelfCall(Args(args)),
                ".." => Root::ParentCall(Args(args)),
                _ => Root::Call { name, args: Args(args) },
            },
            ExprKind::Call { callee: inner, args: first } if matches!(&inner.kind, ExprKind::Ident(n) if n == "call") => {
                Root::DynamicCall { first: Args(first), args: Args(args) }
            }
            ExprKind::Call { callee: inner, args: first } if matches!(&inner.kind, ExprKind::Ident(n) if n == "call_ext") => {
                Root::ExternalCall { first: Args(first), args: Args(args) }
            }
            _ => Root::Opaque(e),
        },
        // Binary, conditional and the rest, met as the start of a chain (`(a || b).x` is a Group; these are the operands of a prefix
        // operator).
        _ => Root::Group(e),
    }
}

/// `new X(...)...`: dmbc reads `new` as a prefix over a postfix chain; the analysis reads the type (a prefab or a name with field
/// accesses) and the first argument list as the root, the rest of the chain as hops.
fn new_chain<'a>(new_node: &'a Expr, value: &'a Expr, outer: Vec<Hop<'a>>) -> Chain<'a> {
    // The chain under `new`, root first.
    let inner = chain_of_posts(value);
    let (core, posts) = inner;
    let call_at = posts.iter().position(|p| matches!(p, Post::Call(..)));
    let (target, rest) = match call_at {
        Some(i) => posts.split_at(i),
        None => (&posts[..], &posts[posts.len()..]),
    };
    let (args, rest) = match rest.split_first() {
        Some((Post::Call(a), tail)) => (Some(Args(a)), tail),
        _ => (None, rest),
    };
    let root = match &core.kind {
        ExprKind::TypePath(p) => {
            let mut vars = Vec::new();
            for post in target {
                match post {
                    Post::Init(fields) => vars.extend(fields.iter()),
                    _ => return Chain { root: Root::Opaque(new_node), root_expr: new_node, hops: outer },
                }
            }
            Root::NewPrefab { path: p, vars, args }
        }
        ExprKind::Ident(name) => {
            let mut fields = Vec::new();
            for post in target {
                match post {
                    Post::Hop(Hop::Field { name, safe, colon, .. }) => fields.push((*name, *colon, *safe)),
                    _ => return Chain { root: Root::Opaque(new_node), root_expr: new_node, hops: outer },
                }
            }
            Root::NewMini { name, fields, args }
        }
        _ => return Chain { root: Root::Opaque(new_node), root_expr: new_node, hops: outer },
    };
    let mut hops = Vec::new();
    for post in rest {
        match post {
            Post::Hop(h) => hops.push(h.clone()),
            Post::Call(..) | Post::Init(_) => return Chain { root: Root::Opaque(new_node), root_expr: new_node, hops: outer },
        }
    }
    hops.extend(outer);
    Chain { root, root_expr: new_node, hops }
}

enum Post<'a> {
    Hop(Hop<'a>),
    Call(&'a [Expr]),
    Init(&'a [(String, Expr)]),
}

/// The postfix chain under a `new`, root first (calls and initializer blocks kept apart: they end the type).
fn chain_of_posts(mut e: &Expr) -> (&Expr, Vec<Post<'_>>) {
    let mut out = Vec::new();
    loop {
        let (inner, post) = match &e.kind {
            ExprKind::Member { object, selector, via_colon } => (&**object, Post::Hop(Hop::Field { name: selector, safe: false, colon: *via_colon, at: e })),
            ExprKind::SafeMember { object, selector, via_colon } => (&**object, Post::Hop(Hop::Field { name: selector, safe: true, colon: *via_colon, at: e })),
            ExprKind::StaticMember { object, selector } => (&**object, Post::Hop(Hop::Static { name: selector, at: e })),
            ExprKind::Index { object, index } => (&**object, Post::Hop(Hop::Index { index, safe: false, at: e })),
            ExprKind::SafeIndex { object, index } => (&**object, Post::Hop(Hop::Index { index, safe: true, at: e })),
            ExprKind::Call { callee, args } => (&**callee, Post::Call(args)),
            ExprKind::ObjectInitializer { object, fields } => (&**object, Post::Init(fields)),
            ExprKind::Unary { op, value } if op.starts_with("post") => (&**value, Post::Hop(Hop::Unary { op, at: e })),
            _ => break,
        };
        out.push(post);
        e = inner;
    }
    out.reverse();
    (e, out)
}

/// A decoded literal.
#[derive(Clone, Debug, PartialEq)]
pub enum Lit {
    Null,
    Int(i32),
    Float(f32),
    String(String),
    Resource(String),
    /// An interpolated string: the text before the first `[`, then each embedded expression's source with its offset in the token
    /// and the text after it. [`interp_parts`] parses the expressions.
    Interp(dm_syntax::InterpString),
    /// A token the decoder rejects.
    Bad,
}

pub fn literal(text: &str) -> Lit {
    if text == "null" {
        return Lit::Null;
    }
    let decoded = match dm_syntax::decode_literal(text) {
        Ok(lit) => lit,
        Err(dm_syntax::LiteralError { fallback: Some(lit), .. }) => lit,
        Err(_) => return Lit::Bad,
    };
    match decoded {
        dm_syntax::Literal::Int(v) => Lit::Int(v),
        dm_syntax::Literal::Float(v) => Lit::Float(v),
        dm_syntax::Literal::String(s) => Lit::String(s),
        dm_syntax::Literal::Resource(s) => Lit::Resource(s),
        dm_syntax::Literal::InterpString(i) => Lit::Interp(i),
    }
}

/// The embedded expressions of an interpolated string token at `at`: each parsed expression (none for an empty or unparsable part)
/// with the expanded offset its spans are relative to, and the text after it.
pub fn interp_parts(interp: &dm_syntax::InterpString, at: usize) -> Vec<(Option<(Expr, usize)>, String)> {
    interp
        .parts
        .iter()
        .map(|part| {
            let expr = part.expr.as_ref().and_then(|dm_syntax::InterpExpr { source, offset }| {
                // A part broken over lines with `\` continuations: blank the continuation, keeping every offset.
                let source = source.replace("\\\r\n", "   ").replace("\\\n", "  ");
                let parsed = dm_syntax::parse_expression(&source);
                match parsed.expr {
                    Some(e) if parsed.diagnostics.is_empty() => Some((e, at + offset)),
                    _ => None,
                }
            });
            (expr, part.text.clone())
        })
        .collect()
}

/// `(e)` with every pair of parentheses taken off.
pub fn strip_groups(mut e: &Expr) -> &Expr {
    while let ExprKind::Group(inner) = &e.kind {
        e = inner;
    }
    e
}

/// A bare name: `x` (no hops).
pub fn as_ident(e: &Expr) -> Option<&str> {
    match &e.kind {
        ExprKind::Ident(n) => Some(n),
        _ => None,
    }
}

/// A bare call: `name(args)` (no hops, not one of the special forms).
pub fn as_call(e: &Expr) -> Option<(&str, Args<'_>)> {
    match chain(e)? {
        Chain { root: Root::Call { name, args }, hops, .. } if hops.is_empty() => Some((name, args)),
        _ => None,
    }
}

fn is_input_call(e: &Expr) -> bool {
    matches!(&e.kind, ExprKind::Call { callee, .. } if matches!(&callee.kind, ExprKind::Ident(n) if n == "input"))
}

/// A declared value (a var initializer, a parameter default) without its specifiers: `x as num in L` is `x`. Returns the value, the
/// `as` types and the `in` list, as written.
pub fn specified(e: &Expr) -> (&Expr, Option<&[String]>, Option<&Expr>) {
    let mut value = e;
    let mut in_list = None;
    if let ExprKind::Binary { op, lhs, rhs } = &value.kind {
        if op == "in" && matches!(&lhs.kind, ExprKind::TypeFilter { value, .. } if !is_input_call(value)) {
            in_list = Some(&**rhs);
            value = lhs;
        }
    }
    let mut types = None;
    if let ExprKind::TypeFilter { value: inner, types: t } = &value.kind {
        if !is_input_call(inner) {
            types = Some(&t[..]);
            value = inner;
        }
    }
    (value, types, in_list)
}
