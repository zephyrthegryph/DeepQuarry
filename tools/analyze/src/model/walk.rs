//! Statements of the compiler's typed bodies (`dm_syntax::Statement`), read the way the analysis reads them, and the walkers over
//! bodies and expressions (what `sem::ast` did over dreammaker's AST).
//!
//! [`stmts`] reads a block as [`Stmt`]s: `var/a, b = 1` (dm-syntax splits it into one statement per name) is one [`Stmt::Vars`]; an
//! `else if` chain is one [`Stmt::If`] with an arm per condition; an assignment statement is a [`Form::Assign`]; `del x` and `CRASH(x)`
//! are statements of their own; `for()` with nothing in it is [`Stmt::ForInfinite`]. Each carries its [`Site`] (the statement header's
//! start), which [`super::Model::line`] maps to a line.

use dm_syntax::{Expr, ExprKind, ForControl, ForInitializer, Statement, StatementKind, SwitchAlternative};

use super::expr::{form, interp_parts, literal, Args, Chain, Form, Hop, Lit, Root};
use super::Site;

/// A `var/...` declaration: a local, a `for` binding, a C-style `for` initializer.
#[derive(Clone, Debug)]
pub struct VarDecl<'a> {
    pub name: String,
    /// The declared type path segments, flags removed (`["obj", "item"]`); a size suffix (`L[3]`) puts `list` first.
    pub type_path: Vec<String>,
    pub is_static: bool,
    pub is_const: bool,
    pub is_tmp: bool,
    pub value: Option<&'a Expr>,
    /// The size suffix's expressions (`var/L[3][x]`), parsed from the declaration text. With no value written, the var starts as
    /// `new /list(...)` of these (dreammaker spelled that initializer; here `value` stays none).
    pub suffix: Vec<Option<Expr>>,
    /// The suffix's written sizes, in order (the arguments of the `new /list(...)` the var starts as).
    pub suffix_args: Vec<Expr>,
}

impl<'a> VarDecl<'a> {
    /// The initializer: the written value, or for `var/L[3]` (no value) the `new /list(3)` it stands for.
    pub fn initializer(&self) -> Option<Form<'_>> {
        if let Some(v) = self.value {
            return Some(form(v));
        }
        let first = self.suffix_args.first()?;
        Some(Form::Chain(Chain {
            root: Root::NewPrefab { path: "/list", vars: Vec::new(), args: Some(Args(&self.suffix_args)) },
            root_expr: first,
            hops: Vec::new(),
        }))
    }

    /// `/obj/item`, `""` when untyped.
    pub fn declared(&self) -> String {
        if self.type_path.is_empty() {
            String::new()
        } else {
            format!("/{}", self.type_path.join("/"))
        }
    }
}

/// A `for (... in L)` / `for (k, v in L)` / `for (x = a to b)` binding.
#[derive(Clone, Debug)]
pub struct Binding {
    /// The declaration when written `var/...`; none for an existing name.
    pub decl: Option<VarDecl<'static>>,
    pub name: String,
    /// `as obj|mob`.
    pub as_types: Option<Vec<String>>,
}

#[derive(Clone, Debug)]
pub enum CaseRef<'a> {
    Exact(&'a Expr),
    Range(&'a Expr, &'a Expr),
}

#[derive(Clone, Debug)]
pub enum ForInit<'a> {
    Var(VarDecl<'a>),
    Expr(&'a Expr),
}

#[derive(Clone, Debug)]
pub enum Stmt<'a> {
    /// An expression statement; an assignment is [`Form::Assign`].
    Expr(Form<'a>, Option<&'a Expr>),
    /// One `var/` statement (one declaration, or several names on one line).
    Vars(Vec<VarDecl<'a>>),
    Return(Option<&'a Expr>),
    Throw(&'a Expr),
    /// `del x` (the operand as written, parentheses kept).
    Del(&'a Expr),
    /// `CRASH(x)`.
    Crash(Option<&'a Expr>),
    If { arms: Vec<(&'a Expr, &'a [Statement])>, else_arm: Option<&'a [Statement]> },
    While { condition: &'a Expr, body: &'a [Statement] },
    DoWhile { body: &'a [Statement], condition: &'a Expr },
    Spawn { delay: Option<&'a Expr>, body: &'a [Statement] },
    /// `set name = value` / `set name in value`.
    Setting { name: &'a str, is_in: bool, value: &'a Expr },
    ForList { binding: Binding, in_list: Option<&'a Expr>, body: &'a [Statement] },
    ForKeyValue { binding: Binding, value: &'a str, in_list: &'a Expr, body: &'a [Statement] },
    ForRange { binding: Binding, start: &'a Expr, end: &'a Expr, step: Option<&'a Expr>, body: &'a [Statement] },
    ForLoop { init: Option<ForInit<'a>>, test: Option<&'a Expr>, inc: Option<&'a Expr>, body: &'a [Statement] },
    ForInfinite { body: &'a [Statement] },
    Switch { input: &'a Expr, cases: Vec<(Vec<CaseRef<'a>>, Site, &'a [Statement])>, default: Option<&'a [Statement]> },
    Try { body: &'a [Statement], catch_params: Vec<Vec<String>>, catch_body: &'a [Statement] },
    Label { name: &'a str, body: &'a [Statement] },
    Goto(&'a str),
    Break(Option<&'a str>),
    Continue(Option<&'a str>),
    Unsupported,
}

#[derive(Clone, Debug)]
pub struct StmtAt<'a> {
    pub site: Site,
    pub stmt: Stmt<'a>,
    /// The statement it was read from (the first, for a merged `var/a, b`).
    pub source: &'a Statement,
}

fn site(offset: usize) -> Site {
    Site(offset as u32)
}

/// `var/static/list/x[4]`: flags, type path, name and size suffix.
pub fn declaration<'a>(declaration: &str, value: Option<&'a Expr>) -> VarDecl<'a> {
    let decl = declaration.trim();
    let decl = decl.split(" as ").next().unwrap_or(decl).trim();
    let rest = decl.strip_prefix("var").unwrap_or(decl).trim_start_matches(['/', ' ', '\t']);
    let (path, suffix_text) = match rest.find('[') {
        Some(at) => (&rest[..at], &rest[at..]),
        None => (rest, ""),
    };
    let mut parts: Vec<String> = path.split('/').map(str::trim).filter(|p| !p.is_empty()).map(str::to_owned).collect();
    let name = parts.pop().unwrap_or_default();
    let (mut is_static, mut is_const, mut is_tmp) = (false, false, false);
    let mut type_path = Vec::new();
    for p in parts {
        match p.as_str() {
            "static" | "global" => is_static = true,
            "const" => is_const = true,
            "tmp" => is_tmp = true,
            "SpacemanDMM_private" | "SpacemanDMM_protected" | "SpacemanDMM_final" => {}
            _ => type_path.push(p),
        }
    }
    let mut suffix = Vec::new();
    let mut cursor = suffix_text;
    while let Some(open) = cursor.strip_prefix('[') {
        let mut depth = 0usize;
        let mut close = open.len();
        for (i, ch) in open.char_indices() {
            match ch {
                '[' | '(' => depth += 1,
                ')' => depth = depth.saturating_sub(1),
                ']' if depth == 0 => {
                    close = i;
                    break;
                }
                ']' => depth -= 1,
                _ => {}
            }
        }
        let inner = open[..close].trim();
        suffix.push(if inner.is_empty() {
            None
        } else {
            let parsed = dm_syntax::parse_expression(inner);
            parsed.expr.filter(|_| parsed.diagnostics.is_empty())
        });
        cursor = open.get(close + 1..).unwrap_or("").trim_start();
    }
    if !suffix.is_empty() {
        type_path.insert(0, "list".to_owned());
    }
    let suffix_args: Vec<Expr> = suffix.iter().flatten().cloned().collect();
    VarDecl { name, type_path, is_static, is_const, is_tmp, value, suffix, suffix_args }
}

/// A for binding (`var/obj/O as obj`, `O`).
pub fn binding(text: &str) -> Binding {
    let (decl, as_types) = match text.split_once(" as ") {
        Some((d, t)) => (d.trim(), Some(t.split('|').map(|x| x.trim().to_owned()).collect::<Vec<_>>())),
        None => (text.trim(), None),
    };
    if decl.starts_with("var/") || decl.starts_with("var ") {
        let d = declaration(decl, None);
        Binding { name: d.name.clone(), decl: Some(d), as_types }
    } else {
        Binding { decl: None, name: decl.to_owned(), as_types }
    }
}

/// A block read as the analysis reads it.
pub fn stmts(block: &[Statement]) -> Vec<StmtAt<'_>> {
    let mut out: Vec<StmtAt<'_>> = Vec::new();
    for s in block {
        // `var/a, b = 1`: dm-syntax splits the line into one Var per part; the later parts' headers drop the `var` spelling and continue
        // the statement before them.
        if let StatementKind::Var { declaration: d, value } = &s.kind {
            let head = s.raw_header.trim_start();
            if !head.starts_with("var") {
                if let Some(StmtAt { stmt: Stmt::Vars(list), .. }) = out.last_mut() {
                    list.push(declaration(d, value.as_ref()));
                    continue;
                }
            }
        }
        out.push(StmtAt { site: site(s.header_span.start), stmt: stmt(s), source: s });
    }
    out
}

fn stmt(s: &Statement) -> Stmt<'_> {
    match &s.kind {
        StatementKind::If { condition, then_branch, else_branch, has_else } => {
            let mut arms = vec![(condition, &then_branch[..])];
            let mut else_arm = None;
            let mut rest: &[Statement] = else_branch;
            let mut rest_has_else = *has_else;
            loop {
                // `else if (...)`: dm-syntax nests the If in the else branch; its span still starts at `else`.
                if let [only] = rest {
                    if let StatementKind::If { condition, then_branch, else_branch, has_else } = &only.kind {
                        if only.span.start < only.header_span.start {
                            arms.push((condition, &then_branch[..]));
                            rest = else_branch;
                            rest_has_else = *has_else;
                            continue;
                        }
                    }
                }
                if rest_has_else {
                    else_arm = Some(rest);
                }
                break;
            }
            Stmt::If { arms, else_arm }
        }
        StatementKind::While { condition, body } => Stmt::While { condition, body },
        StatementKind::DoWhile { body, condition } => Stmt::DoWhile { body, condition },
        StatementKind::Spawn { delay, body } => Stmt::Spawn { delay: delay.as_ref(), body },
        StatementKind::Set { attribute, relation, value } => Stmt::Setting { name: attribute, is_in: relation == "in", value },
        StatementKind::For { control, body } => match control {
            ForControl::All { declaration } => Stmt::ForList { binding: binding(declaration), in_list: None, body },
            ForControl::Each { binding: b, iterable } => Stmt::ForList { binding: binding(b), in_list: Some(iterable), body },
            ForControl::Pair { key_binding, value_binding, iterable } => {
                Stmt::ForKeyValue { binding: binding(key_binding), value: value_binding.trim(), in_list: iterable, body }
            }
            ForControl::Range { binding: b, start, end, step } => Stmt::ForRange { binding: binding(b), start, end, step: step.as_ref(), body },
            ForControl::CStyle { initializer, condition, step } => {
                // `for()` is an infinite loop; `for(;;)` is a C-style loop with nothing in it.
                let clause = s.raw_header.trim().strip_prefix("for").unwrap_or("").trim_start();
                let inner = clause.strip_prefix('(').and_then(|c| c.split(')').next()).unwrap_or("x");
                if initializer.is_none() && condition.is_none() && step.is_none() && inner.trim().is_empty() {
                    return Stmt::ForInfinite { body };
                }
                let init = initializer.as_ref().map(|i| match i {
                    ForInitializer::Declare { declaration: d, value } => ForInit::Var(declaration(d, value.as_ref())),
                    ForInitializer::Expr(e) => ForInit::Expr(e),
                });
                Stmt::ForLoop { init, test: condition.as_ref(), inc: step.as_ref(), body }
            }
        },
        StatementKind::Switch { selector, cases, else_branch } => {
            let cases = cases
                .iter()
                .map(|case| {
                    let mut at = 0;
                    let alts = case
                        .alternatives
                        .iter()
                        .map(|alt| match alt {
                            SwitchAlternative::Exact(e) => {
                                at = e.span.start;
                                CaseRef::Exact(e)
                            }
                            SwitchAlternative::Range(a, b) => {
                                at = a.span.start;
                                CaseRef::Range(a, b)
                            }
                        })
                        .collect();
                    (alts, site(at), &case.body[..])
                })
                .collect();
            Stmt::Switch { input: selector, cases, default: if else_branch.is_empty() { None } else { Some(else_branch) } }
        }
        StatementKind::Try { body, catch_binding, catch_body, .. } => {
            let catch_params = match catch_binding {
                Some(b) if !b.is_empty() => vec![b.split('/').map(str::trim).filter(|p| !p.is_empty()).map(str::to_owned).collect()],
                _ => Vec::new(),
            };
            Stmt::Try { body, catch_params, catch_body }
        }
        StatementKind::Throw(e) => Stmt::Throw(e),
        StatementKind::Label { name, body } => Stmt::Label { name, body },
        StatementKind::Goto(l) => Stmt::Goto(l),
        StatementKind::Return(e) => Stmt::Return(e.as_ref()),
        StatementKind::Var { declaration: d, value } => Stmt::Vars(vec![declaration(d, value.as_ref())]),
        StatementKind::Assign { target, op, value } => Stmt::Expr(Form::Assign { op, lhs: target, rhs: value }, None),
        StatementKind::Call(e) | StatementKind::Expression(e) => {
            if let ExprKind::Call { callee, args } = &e.kind {
                if let ExprKind::Ident(name) = &callee.kind {
                    let args = Args(args);
                    if name == "del" && args.len() == 1 {
                        return Stmt::Del(args.first().unwrap());
                    }
                    if name == "CRASH" && args.len() <= 1 {
                        return Stmt::Crash(args.first());
                    }
                }
            }
            Stmt::Expr(form(e), Some(e))
        }
        StatementKind::Break => Stmt::Break(None),
        StatementKind::BreakLabel(l) => Stmt::Break(Some(l)),
        StatementKind::Continue => Stmt::Continue(None),
        StatementKind::ContinueLabel(l) => Stmt::Continue(Some(l)),
        StatementKind::Unsupported => Stmt::Unsupported,
    }
}

/// One visited expression: its form, the node (none for an assignment statement, which has no node of its own) and where it starts.
pub struct Visit<'v> {
    pub form: Form<'v>,
    pub node: Option<&'v Expr>,
    pub site: Site,
}

/// Every expression of `e`, pre-order, as dreammaker's walk visited them: a chain once (not each nested `Member`/`Call` node), then the
/// expressions inside it (arguments, indexes, interpolated parts, prefab initializers). `base` shifts the sites of an expression parsed
/// from an interpolation part (0 for a body's own nodes).
pub fn walk_expr(e: &Expr, f: &mut dyn FnMut(&Visit<'_>)) {
    walk_expr_at(e, 0, f)
}

fn walk_expr_at(e: &Expr, base: usize, f: &mut dyn FnMut(&Visit<'_>)) {
    let fm = form(e);
    walk_form(fm, Some(e), Site((base + e.span.start) as u32), base, f);
}

/// Visit `fm` (the form of `node`, or an assignment statement's) and everything inside it.
pub fn walk_form<'v>(fm: Form<'v>, node: Option<&'v Expr>, at: Site, base: usize, f: &mut dyn FnMut(&Visit<'_>)) {
    let children: Vec<&Expr> = match &fm {
        Form::Binary { lhs, rhs, .. } | Form::Assign { lhs, rhs, .. } => vec![*lhs, *rhs],
        Form::Ternary { cond, then_value, else_value } => vec![*cond, *then_value, *else_value],
        Form::Chain(_) => Vec::new(),
    };
    let chain = if let Form::Chain(c) = &fm { Some(c.clone()) } else { None };
    f(&Visit { form: fm, node, site: at });
    for c in children {
        walk_expr_at(c, base, f);
    }
    if let Some(c) = chain {
        walk_chain(&c, base, f);
    }
}

fn walk_chain(c: &Chain<'_>, base: usize, f: &mut dyn FnMut(&Visit<'_>)) {
    let each = |args: &Args<'_>, f: &mut dyn FnMut(&Visit<'_>)| {
        for a in args.iter() {
            walk_expr_at(a, base, f);
        }
    };
    match &c.root {
        Root::Group(e) => walk_expr_at(e, base, f),
        Root::Literal(text) => {
            if let Lit::Interp(interp) = literal(text) {
                for (part, _) in interp_parts(&interp, base + c.root_expr.span.start) {
                    if let Some((e, at)) = part {
                        walk_expr_at(&e, at, f);
                    }
                }
            }
        }
        Root::Call { args, .. } | Root::SelfCall(args) | Root::ParentCall(args) | Root::List(args) => each(args, f),
        Root::NewImplicit { args } | Root::NewPrefab { args, .. } | Root::NewMini { args, .. } => {
            if let Some(a) = args {
                each(a, f);
            }
        }
        Root::Input { args, in_list, .. } | Root::Locate { args, in_list } => {
            each(args, f);
            if let Some(l) = in_list {
                walk_expr_at(l, base, f);
            }
        }
        Root::DynamicCall { first, args } | Root::ExternalCall { first, args } => {
            each(first, f);
            each(args, f);
        }
        Root::Pick(p) => {
            for (w, e) in p {
                if let Some(w) = w {
                    walk_expr_at(w, base, f);
                }
                walk_expr_at(e, base, f);
            }
        }
        Root::Prefab { vars, .. } => {
            for (_, e) in vars.iter() {
                walk_expr_at(e, base, f);
            }
        }
        Root::Ident(_) | Root::Opaque(_) => {}
    }
    for h in &c.hops {
        match h {
            Hop::Index { index, .. } => walk_expr_at(index, base, f),
            Hop::Call { args, .. } => each(args, f),
            _ => {}
        }
    }
}

/// The expressions a statement holds directly (not those of its nested blocks), as `(form, node, site)`; a C-style `for`'s
/// initializer and step are [`for_parts`].
pub fn stmt_exprs<'a>(s: &Stmt<'a>) -> Vec<&'a Expr> {
    let mut v: Vec<&'a Expr> = Vec::new();
    match s {
        Stmt::Expr(_, Some(e)) | Stmt::Throw(e) | Stmt::Del(e) => v.push(e),
        Stmt::Return(Some(e)) | Stmt::Crash(Some(e)) => v.push(e),
        Stmt::While { condition, .. } | Stmt::DoWhile { condition, .. } => v.push(condition),
        Stmt::If { arms, .. } => v.extend(arms.iter().map(|(c, _)| *c)),
        Stmt::ForLoop { test: Some(t), .. } => v.push(t),
        Stmt::ForList { in_list: Some(l), .. } => v.push(l),
        Stmt::ForKeyValue { in_list, .. } => v.push(in_list),
        Stmt::ForRange { start, end, step, .. } => {
            v.push(start);
            v.push(end);
            v.extend(step.iter().copied());
        }
        Stmt::Vars(vs) => v.extend(vs.iter().filter_map(|x| x.value)),
        Stmt::Setting { value, .. } => v.push(value),
        Stmt::Spawn { delay: Some(d), .. } => v.push(d),
        Stmt::Switch { input, cases, .. } => {
            v.push(input);
            for (alts, _, _) in cases {
                for a in alts {
                    match a {
                        CaseRef::Exact(e) => v.push(e),
                        CaseRef::Range(a, b) => {
                            v.push(a);
                            v.push(b);
                        }
                    }
                }
            }
        }
        _ => {}
    }
    v
}

/// The nested blocks of a statement, in order.
pub fn stmt_blocks<'a>(s: &Stmt<'a>) -> Vec<&'a [Statement]> {
    match s {
        Stmt::While { body, .. }
        | Stmt::DoWhile { body, .. }
        | Stmt::ForInfinite { body }
        | Stmt::ForLoop { body, .. }
        | Stmt::ForList { body, .. }
        | Stmt::ForKeyValue { body, .. }
        | Stmt::ForRange { body, .. }
        | Stmt::Spawn { body, .. }
        | Stmt::Label { body, .. } => vec![body],
        Stmt::If { arms, else_arm } => arms.iter().map(|(_, b)| *b).chain(else_arm.iter().copied()).collect(),
        Stmt::Switch { cases, default, .. } => cases.iter().map(|(_, _, b)| *b).chain(default.iter().copied()).collect(),
        Stmt::Try { body, catch_body, .. } => vec![body, catch_body],
        _ => Vec::new(),
    }
}

/// Every expression of a body with the site of the statement it is in (what `sem::ast::walk_block` gave with the statement's line).
pub fn walk_block(block: &[Statement], f: &mut dyn FnMut(&Visit<'_>, Site)) {
    for st in stmts(block) {
        let at = st.site;
        match &st.stmt {
            Stmt::Expr(Form::Assign { op, lhs, rhs }, None) => walk_form(Form::Assign { op, lhs, rhs }, None, at, 0, &mut |v| f(v, at)),
            // `del x` reads its operand as a parenthesized expression.
            Stmt::Del(e) => {
                let group = Form::Chain(Chain { root: Root::Group(e), root_expr: e, hops: Vec::new() });
                walk_form(group, None, Site(e.span.start as u32), 0, &mut |v| f(v, at));
            }
            // A sized list with no value starts as `new /list(...)`.
            Stmt::Vars(vs) => {
                for d in vs {
                    match d.value {
                        Some(e) => walk_expr(e, &mut |v| f(v, at)),
                        None => {
                            if let Some(init) = d.initializer() {
                                walk_form(init, None, at, 0, &mut |v| f(v, at));
                            }
                        }
                    }
                }
            }
            _ => {}
        }
        if !matches!(st.stmt, Stmt::Del(_) | Stmt::Vars(_)) {
            for e in stmt_exprs(&st.stmt) {
                walk_expr(e, &mut |v| f(v, at));
            }
        }
        if let Stmt::ForLoop { init, inc, .. } = &st.stmt {
            match init {
                Some(ForInit::Var(d)) => {
                    if let Some(e) = d.value {
                        walk_expr(e, &mut |v| f(v, at));
                    }
                }
                Some(ForInit::Expr(e)) => walk_expr(e, &mut |v| f(v, at)),
                None => {}
            }
            if let Some(e) = inc {
                walk_expr(e, &mut |v| f(v, at));
            }
        }
        for b in stmt_blocks(&st.stmt) {
            walk_block(b, f);
        }
    }
}
