//! dmbc's typed proc bodies as dreammaker's AST (doc/rewrite/proposals/lean_unified.md, "One program", step 2a).
//!
//! The analysis engine (tools/analyze) reads SpacemanDMM dreammaker's syntax tree. To move it onto dmbc's own front end, each typed body
//! (`dm_syntax::Statement` / `dm_syntax::Expr`) is converted into the `dreammaker::ast::Block` dreammaker's parser would have built for the
//! same source. `dmbc analysis-parity` (`crate::analysis_parity`) measures how often the conversion is exact.
//!
//! Known remaining use of dreammaker's parser: a string, resource or number literal is decoded by running dreammaker's lexer on that one
//! token (escapes, `\the`/`\a`/`\improper` macros, Int vs Float rules), and an interpolated string's embedded `[expr]` parts are parsed
//! by dreammaker's expression parser on that literal alone. dm-syntax keeps a literal as its token text only; decoding it natively is
//! the next step.
//!
//! Where dmbc's grammar follows DreamMaker and SpacemanDMM's does not (operator precedence: `a == b | c` is `(a == b) | c`, `in` is the
//! loosest operator), the conversion keeps dmbc's tree: it does not copy dreammaker's mistakes.
use dm_syntax::{Expr, ExprKind, ForControl, ForInitializer, Statement as SStatement, StatementKind, SwitchAlternative};
use dreammaker::ast::{
    AssignOp, BinaryOp, Block, Case, Expression, Field, Follow, ForKeyValueStatement, ForListStatement, ForRangeStatement, Ident2, InputType,
    ListAccessKind, MiniExpr, PathOp, Prefab, PropertyAccessKind, SettingMode, Spanned, Statement, Term, TypePath, UnaryOp, VarStatement,
    VarSuffix, VarType, VarTypeBuilder,
};
use dreammaker::Location;
use std::str::FromStr;

/// Maps an offset in the expanded arena (a `dm_syntax::Span` bound) to a dreammaker location.
pub trait Locate {
    fn locate(&mut self, offset: usize) -> Location;
}

impl<F: FnMut(usize) -> Location> Locate for F {
    fn locate(&mut self, offset: usize) -> Location {
        self(offset)
    }
}

/// Locations from the front end's line map, with dreammaker's "bad file" id (the caller that has a dreammaker file list maps paths with
/// [`convert_body_with`]). Columns are not carried (0): `debug_site` gives logical lines only.
pub struct FrontendLocator<'a> {
    pub frontend: &'a dm_tree::frontend::ColdFrontend,
}

impl Locate for FrontendLocator<'_> {
    fn locate(&mut self, offset: usize) -> Location {
        let line = self.frontend.debug_site(offset).map_or(0, |(_, line)| line as u32);
        Location { file: Default::default(), line, column: 0 }
    }
}

/// Convert a typed body to dreammaker's AST, locating through the front end's line map.
pub fn convert_body(frontend: &dm_tree::frontend::ColdFrontend, statements: &[SStatement]) -> Block {
    convert_body_with(statements, &mut FrontendLocator { frontend })
}

/// Convert a typed body to dreammaker's AST with the caller's location mapper.
pub fn convert_body_with(statements: &[SStatement], locate: &mut dyn Locate) -> Block {
    Converter { locate, parse_error: None }.block(statements)
}

/// Convert a typed body, or report where dreammaker's parser rejects it (a form BYOND accepts and dreammaker does not, such as
/// `new L[1](at)`): its location and dreammaker's message.
pub fn convert_body_checked(statements: &[SStatement], locate: &mut dyn Locate) -> Result<Block, (Location, String)> {
    let mut c = Converter { locate, parse_error: None };
    let block = c.block(statements);
    match c.parse_error.take() {
        Some((at, message)) => Err((c.locate.locate(at), message)),
        None => Ok(block),
    }
}

/// Convert one typed expression (a var initializer, a parameter default) with the caller's location mapper.
pub fn convert_expression_with(expression: &Expr, locate: &mut dyn Locate) -> Expression {
    Converter { locate, parse_error: None }.expr(expression)
}

struct Converter<'a> {
    locate: &'a mut dyn Locate,
    /// The first form dreammaker's parser rejects (where it stops, and its message): the body is then a parse failure, as dreammaker's.
    parse_error: Option<(usize, String)>,
}

/// Marker for a statement or expression dm-syntax kept unsupported, or a form the converter has no mapping for.
pub const UNCONVERTED: &str = "__DMBC_UNCONVERTED__";

fn unconverted(what: &str) -> Expression {
    Expression::from(Term::Call(UNCONVERTED.into(), vec![Expression::from(Term::String(what.to_owned()))].into_boxed_slice()))
}

fn base(term: Spanned<Term>, follow: Vec<Spanned<Follow>>) -> Expression {
    Expression::Base { term: Box::new(term), follow: follow.into_boxed_slice() }
}

fn ident2(s: &str) -> Ident2 {
    Ident2::from(s)
}

fn binary_op(op: &str) -> Option<BinaryOp> {
    Some(match op {
        "+" => BinaryOp::Add,
        "-" => BinaryOp::Sub,
        "*" => BinaryOp::Mul,
        "/" => BinaryOp::Div,
        "**" => BinaryOp::Pow,
        "%" => BinaryOp::Mod,
        "%%" => BinaryOp::FloatMod,
        "==" => BinaryOp::Eq,
        "!=" | "<>" => BinaryOp::NotEq,
        "<" => BinaryOp::Less,
        ">" => BinaryOp::Greater,
        "<=" => BinaryOp::LessEq,
        ">=" => BinaryOp::GreaterEq,
        "<=>" => BinaryOp::LessOrGreater,
        "~=" => BinaryOp::Equiv,
        "~!" => BinaryOp::NotEquiv,
        "&" => BinaryOp::BitAnd,
        "^" => BinaryOp::BitXor,
        "|" => BinaryOp::BitOr,
        "<<" => BinaryOp::LShift,
        ">>" => BinaryOp::RShift,
        "&&" => BinaryOp::And,
        "||" => BinaryOp::Or,
        "in" => BinaryOp::In,
        "to" => BinaryOp::To,
        _ => return None,
    })
}

fn assign_op(op: &str) -> Option<AssignOp> {
    Some(match op {
        "=" => AssignOp::Assign,
        "+=" => AssignOp::AddAssign,
        "-=" => AssignOp::SubAssign,
        "*=" => AssignOp::MulAssign,
        "/=" => AssignOp::DivAssign,
        "%=" => AssignOp::ModAssign,
        "%%=" => AssignOp::FloatModAssign,
        ":=" => AssignOp::AssignInto,
        "&=" => AssignOp::BitAndAssign,
        "&&=" => AssignOp::AndAssign,
        "|=" => AssignOp::BitOrAssign,
        "||=" => AssignOp::OrAssign,
        "^=" => AssignOp::BitXorAssign,
        "<<=" => AssignOp::LShiftAssign,
        ">>=" => AssignOp::RShiftAssign,
        _ => return None,
    })
}

pub(crate) fn input_type(types: &[String]) -> InputType {
    let mut out = InputType::empty();
    for t in types {
        if let Ok(v) = InputType::from_str(t) {
            out |= v;
        }
    }
    out
}

/// `/obj/item`, `.proc/foo`, `/datum.proc/x` as dreammaker's (operator, name) pairs.
fn type_path(path: &str) -> TypePath {
    let mut out = Vec::new();
    let mut op = None;
    let mut name = String::new();
    for ch in path.chars() {
        let sep = match ch {
            '/' => Some(PathOp::Slash),
            '.' => Some(PathOp::Dot),
            ':' => Some(PathOp::Colon),
            _ => None,
        };
        match sep {
            Some(sep) => {
                if let (Some(o), false) = (op, name.is_empty()) {
                    out.push((o, std::mem::take(&mut name)));
                }
                name.clear();
                op = Some(sep);
            }
            None => name.push(ch),
        }
    }
    if let (Some(o), false) = (op, name.is_empty()) {
        out.push((o, name));
    }
    out
}

/// The leftmost postfix chain of an expression, innermost first: `new` takes its constructor arguments from it.
enum Post<'e> {
    Member(&'e str, bool),
    SafeMember(&'e str, bool),
    Static(&'e str),
    Index(&'e Expr),
    SafeIndex(&'e Expr),
    Call(&'e [Expr]),
    Init(&'e [(String, Expr)]),
    Unary(&'e str),
}

fn spine(mut e: &Expr) -> (&Expr, Vec<(Post<'_>, usize)>) {
    let mut out = Vec::new();
    loop {
        let (inner, post) = match &e.kind {
            ExprKind::Member { object, selector, via_colon } => (object, Post::Member(selector, *via_colon)),
            ExprKind::SafeMember { object, selector, via_colon } => (object, Post::SafeMember(selector, *via_colon)),
            ExprKind::StaticMember { object, selector } => (object, Post::Static(selector)),
            ExprKind::Index { object, index } => (object, Post::Index(index)),
            ExprKind::SafeIndex { object, index } => (object, Post::SafeIndex(index)),
            ExprKind::Call { callee, args } => (callee, Post::Call(args)),
            ExprKind::ObjectInitializer { object, fields } => (object, Post::Init(fields)),
            ExprKind::Unary { op, value } if op.starts_with("post") => (value, Post::Unary(op)),
            _ => break,
        };
        // dreammaker places a follow at its operator token (`.`, `[`, `++`): right after the object.
        out.push((post, inner.span.end));
        e = inner;
    }
    out.reverse();
    (e, out)
}

impl Converter<'_> {
    /// A literal token decoded by dm-syntax's literal decoder (`dm_syntax::decode_literal`, dreammaker's lexer rules). An
    /// interpolation's expressions are parsed with dm-syntax and converted with spans shifted to their place in the token at `at`.
    fn literal(&mut self, text: &str, at: usize) -> Expression {
        let location = self.loc(at);
        if text == "null" {
            return base(Spanned::new(location, Term::Null), Vec::new());
        }
        let decoded = match dm_syntax::decode_literal(text) {
            Ok(lit) => lit,
            Err(dm_syntax::LiteralError { fallback: Some(lit), .. }) => lit,
            Err(_) => return unconverted("literal"),
        };
        let term = match decoded {
            dm_syntax::Literal::Int(v) => Term::Int(v),
            dm_syntax::Literal::Float(v) => Term::Float(v),
            dm_syntax::Literal::String(s) => Term::String(s),
            dm_syntax::Literal::Resource(s) => Term::Resource(s),
            dm_syntax::Literal::InterpString(interp) => {
                let mut parts = Vec::with_capacity(interp.parts.len());
                for part in interp.parts {
                    let expr = match part.expr {
                        None => None,
                        Some(dm_syntax::InterpExpr { source, offset }) => {
                            // A part broken over lines with `\` continuations (inside the string the preprocessor does not join
                            // them): blank the continuation, keeping every offset.
                            let source = source.replace("\\\r\n", "   ").replace("\\\n", "  ");
                            let parsed = dm_syntax::parse_expression(&source);
                            Some(match parsed.expr {
                                Some(e) if parsed.diagnostics.is_empty() => {
                                    let outer = &mut *self.locate;
                                    let base_at = at + offset;
                                    let mut shifted = |o: usize| outer.locate(base_at + o);
                                    Converter { locate: &mut shifted, parse_error: None }.expr(&e)
                                }
                                _ => {
                                    if std::env::var_os("DQ_BRIDGE_TRACE_LITERALS").is_some() {
                                        eprintln!("interpolation part not converted: {source:?} {:?}", parsed.diagnostics);
                                    }
                                    unconverted("interpolation")
                                }
                            })
                        }
                    };
                    parts.push((expr, part.text.into_boxed_str()));
                }
                Term::InterpString(ident2(&interp.first), parts.into_boxed_slice())
            }
        };
        base(Spanned::new(location, term), Vec::new())
    }

    fn loc(&mut self, offset: usize) -> Location {
        self.locate.locate(offset)
    }

    fn block(&mut self, statements: &[SStatement]) -> Block {
        let mut out: Vec<Spanned<Statement>> = Vec::new();
        for s in statements {
            let location = self.loc(s.header_span.start);
            // `var/a, b = 1`: dm-syntax splits the line into one Var per part; the later parts' headers drop the `var` spelling.
            if let StatementKind::Var { .. } = &s.kind {
                let head = s.raw_header.trim_start();
                if !head.starts_with("var") {
                    if let Some(prev) = out.last_mut().filter(|p| p.location.line == location.line) {
                        let next = self.var(s);
                        match &mut prev.elem {
                            Statement::Var(v) => {
                                let first = (**v).clone();
                                prev.elem = Statement::Vars(vec![first, next]);
                                continue;
                            }
                            Statement::Vars(list) => {
                                list.push(next);
                                continue;
                            }
                            _ => {}
                        }
                    }
                }
            }
            let elem = self.statement(s);
            out.push(Spanned::new(location, elem));
        }
        out.into_boxed_slice()
    }

    fn var(&mut self, s: &SStatement) -> VarStatement {
        let StatementKind::Var { declaration, value } = &s.kind else { unreachable!() };
        let (var_type, name, suffix) = self.declaration(declaration);
        let mut builder = var_type;
        builder.suffix(&suffix);
        let value = match value {
            Some(v) => Some(self.expr(v)),
            None => suffix.into_initializer(),
        };
        VarStatement { var_type: builder.build(), name, value }
    }

    /// `var/static/list/x[4]` as dreammaker's builder (flags and type path), name and list suffix.
    fn declaration(&mut self, declaration: &str) -> (VarTypeBuilder, String, VarSuffix) {
        let decl = declaration.trim();
        let decl = decl.split(" as ").next().unwrap_or(decl).trim();
        let rest = decl.strip_prefix("var").unwrap_or(decl).trim_start_matches(['/', ' ', '\t']);
        let (path, suffix_text) = match rest.find('[') {
            Some(at) => (&rest[..at], &rest[at..]),
            None => (rest, ""),
        };
        let mut parts: Vec<String> = path.split('/').map(str::trim).filter(|p| !p.is_empty()).map(str::to_owned).collect();
        let name = parts.pop().unwrap_or_default();
        let builder: VarTypeBuilder = parts.into_iter().collect();
        let mut list = Vec::new();
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
            if inner.is_empty() {
                list.push(None);
            } else {
                let parsed = dm_syntax::parse_expression(inner);
                list.push(Some(match parsed.expr {
                    Some(e) if parsed.diagnostics.is_empty() => self.expr(&e),
                    _ => unconverted("var suffix"),
                }));
            }
            cursor = open.get(close + 1..).unwrap_or("").trim_start();
        }
        (builder, name, VarSuffix { list })
    }

    /// A for binding (`var/obj/O as obj`, `O`): type, name, input type.
    fn binding(&mut self, binding: &str) -> (Option<VarType>, String, Option<InputType>) {
        let (decl, as_types) = match binding.split_once(" as ") {
            Some((d, t)) => (d.trim(), Some(t.split('|').map(|x| x.trim().to_owned()).collect::<Vec<_>>())),
            None => (binding.trim(), None),
        };
        let input = as_types.map(|t| input_type(&t));
        if decl.starts_with("var/") || decl.starts_with("var ") {
            let (builder, name, suffix) = self.declaration(decl);
            let mut builder = builder;
            builder.suffix(&suffix);
            (Some(builder.build()), name, input)
        } else {
            (None, decl.to_owned(), input)
        }
    }

    fn statement(&mut self, s: &SStatement) -> Statement {
        match &s.kind {
            StatementKind::If { condition, then_branch, else_branch, has_else } => {
                let mut arms = Vec::new();
                let cl = self.loc(condition.span.start);
                arms.push((Spanned::new(cl, self.expr(condition)), self.block(then_branch)));
                let mut else_arm = None;
                let mut rest: &[SStatement] = else_branch;
                let mut rest_has_else = *has_else;
                loop {
                    // `else if (...)`: dm-syntax nests the If in the else branch; its span still starts at `else`.
                    if let [only] = rest {
                        if let StatementKind::If { condition, then_branch, else_branch, has_else } = &only.kind {
                            if only.span.start < only.header_span.start {
                                let cl = self.loc(condition.span.start);
                                arms.push((Spanned::new(cl, self.expr(condition)), self.block(then_branch)));
                                rest = else_branch;
                                rest_has_else = *has_else;
                                continue;
                            }
                        }
                    }
                    // An `else` with nothing in it is an empty block, as dreammaker parses it; no `else` is none.
                    if rest_has_else {
                        else_arm = Some(self.block(rest));
                    }
                    break;
                }
                Statement::If { arms, else_arm }
            }
            StatementKind::While { condition, body } => Statement::While { condition: self.expr(condition), block: self.block(body) },
            StatementKind::DoWhile { body, condition } => {
                let block = self.block(body);
                let cl = self.loc(condition.span.start);
                Statement::DoWhile { block, condition: Box::new(Spanned::new(cl, self.expr(condition))) }
            }
            StatementKind::Spawn { delay, body } => {
                Statement::Spawn { delay: delay.as_ref().map(|d| self.expr(d)), block: self.block(body) }
            }
            StatementKind::Set { attribute, relation, value } => Statement::Setting {
                name: ident2(attribute),
                mode: if relation == "in" { SettingMode::In } else { SettingMode::Assign },
                value: self.expr(value),
            },
            StatementKind::For { control, body } => self.for_statement(s, control, body),
            StatementKind::Switch { selector, cases, else_branch } => {
                let input = Box::new(self.expr(selector));
                let mut out = Vec::new();
                for case in cases {
                    let mut alts = Vec::new();
                    let mut at = 0;
                    for alt in &case.alternatives {
                        alts.push(match alt {
                            SwitchAlternative::Exact(e) => {
                                at = e.span.start;
                                Case::Exact(self.expr(e))
                            }
                            SwitchAlternative::Range(a, b) => {
                                at = a.span.start;
                                Case::Range(self.expr(a), self.expr(b))
                            }
                        });
                    }
                    let l = self.loc(at);
                    out.push((Spanned::new(l, alts), self.block(&case.body)));
                }
                let default = if else_branch.is_empty() { None } else { Some(self.block(else_branch)) };
                Statement::Switch { input, cases: out.into_boxed_slice(), default }
            }
            StatementKind::Try { body, catch_binding, catch_body, .. } => {
                let try_block = self.block(body);
                let catch_params: Vec<Box<[String]>> = match catch_binding {
                    Some(b) if !b.is_empty() => {
                        vec![b.split('/').map(str::trim).filter(|p| !p.is_empty()).map(str::to_owned).collect::<Vec<_>>().into_boxed_slice()]
                    }
                    _ => Vec::new(),
                };
                Statement::TryCatch { try_block, catch_params: catch_params.into_boxed_slice(), catch_block: self.block(catch_body) }
            }
            StatementKind::Throw(e) => Statement::Throw(self.expr(e)),
            StatementKind::Label { name, body } => Statement::Label { name: name.clone(), block: self.block(body) },
            StatementKind::Goto(l) => Statement::Goto(l.clone()),
            StatementKind::Return(e) => Statement::Return(e.as_ref().map(|e| self.expr(e))),
            StatementKind::Var { .. } => Statement::Var(Box::new(self.var(s))),
            StatementKind::Assign { target, op, value } => {
                let lhs = Box::new(self.expr(target));
                let rhs = Box::new(self.expr(value));
                match assign_op(op) {
                    Some(op) => Statement::Expr(Expression::AssignOp { op, lhs, rhs }),
                    None => Statement::Expr(unconverted(op)),
                }
            }
            StatementKind::Call(e) | StatementKind::Expression(e) => {
                if let ExprKind::Call { callee, args } = &e.kind {
                    if let ExprKind::Ident(name) = &callee.kind {
                        if name == "del" && args.len() == 1 {
                            // dreammaker reads `del` then an expression: `(x)` keeps its parentheses.
                            let l = self.loc(args[0].span.start);
                            let inner = self.expr(&args[0]);
                            return Statement::Del(base(Spanned::new(l, Term::Expr(Box::new(inner))), Vec::new()));
                        }
                        if name == "CRASH" && args.len() <= 1 {
                            return Statement::Crash(args.first().map(|a| self.expr(a)));
                        }
                    }
                }
                Statement::Expr(self.expr(e))
            }
            StatementKind::Break => Statement::Break(None),
            StatementKind::BreakLabel(l) => Statement::Break(Some(l.clone())),
            StatementKind::Continue => Statement::Continue(None),
            StatementKind::ContinueLabel(l) => Statement::Continue(Some(l.clone())),
            StatementKind::Unsupported => Statement::Expr(unconverted("unsupported statement")),
        }
    }

    fn for_statement(&mut self, s: &SStatement, control: &ForControl, body: &[SStatement]) -> Statement {
        match control {
            ForControl::All { declaration } => {
                let (var_type, name, input_type) = self.binding(declaration);
                Statement::ForList(Box::new(ForListStatement { var_type, name: ident2(&name), input_type, in_list: None, block: self.block(body) }))
            }
            ForControl::Each { binding, iterable } => {
                let (var_type, name, input_type) = self.binding(binding);
                let in_list = Some(self.expr(iterable));
                Statement::ForList(Box::new(ForListStatement { var_type, name: ident2(&name), input_type, in_list, block: self.block(body) }))
            }
            ForControl::Pair { key_binding, value_binding, iterable } => {
                let (var_type, key, _) = self.binding(key_binding);
                let in_list = Some(self.expr(iterable));
                Statement::ForKeyValue(Box::new(ForKeyValueStatement {
                    var_type,
                    key: ident2(&key),
                    value: ident2(value_binding.trim()),
                    in_list,
                    block: self.block(body),
                }))
            }
            ForControl::Range { binding, start, end, step } => {
                let (var_type, name, _) = self.binding(binding);
                Statement::ForRange(Box::new(ForRangeStatement {
                    var_type,
                    name: ident2(&name),
                    start: self.expr(start),
                    end: self.expr(end),
                    step: step.as_ref().map(|e| self.expr(e)),
                    block: self.block(body),
                }))
            }
            ForControl::CStyle { initializer, condition, step } => {
                // `for()` is dreammaker's ForInfinite; `for(;;)` is a ForLoop with nothing in it.
                let clause = s.raw_header.trim().strip_prefix("for").unwrap_or("").trim_start();
                let inner = clause.strip_prefix('(').and_then(|c| c.split(')').next()).unwrap_or("x");
                if initializer.is_none() && condition.is_none() && step.is_none() && inner.trim().is_empty() {
                    return Statement::ForInfinite { block: self.block(body) };
                }
                let init = initializer.as_ref().map(|i| {
                    Box::new(match i {
                        ForInitializer::Declare { declaration, value } => {
                            let (builder, name, suffix) = self.declaration(declaration);
                            let mut builder = builder;
                            builder.suffix(&suffix);
                            let value = match value {
                                Some(v) => Some(self.expr(v)),
                                None => suffix.into_initializer(),
                            };
                            Statement::Var(Box::new(VarStatement { var_type: builder.build(), name, value }))
                        }
                        ForInitializer::Expr(e) => Statement::Expr(self.expr(e)),
                    })
                });
                let test = condition.as_ref().map(|c| Box::new(self.expr(c)));
                let inc = step.as_ref().map(|c| Box::new(Statement::Expr(self.expr(c))));
                Statement::ForLoop { init, test, inc, block: self.block(body) }
            }
        }
    }

    fn args(&mut self, args: &[Expr]) -> Box<[Expression]> {
        // An empty argument (`f(a, , b)`) is a zero-width `null` from dm-syntax. The analysis model is dreammaker's, which has no node for it.
        let empty = |a: &Expr| a.span.start == a.span.end && matches!(&a.kind, ExprKind::Literal(t) if t == "null");
        args.iter().filter(|a| !empty(a)).map(|a| self.expr(a)).collect()
    }

    /// A term with follows appended (unary operators and field accesses go into dreammaker's `follow` list).
    fn into_base(&mut self, e: Expression, at: usize) -> (Spanned<Term>, Vec<Spanned<Follow>>) {
        match e {
            Expression::Base { term, follow } => (*term, follow.into_vec()),
            other => {
                let l = self.loc(at);
                (Spanned::new(l, Term::Expr(Box::new(other))), Vec::new())
            }
        }
    }

    /// `object` followed by `follow`, placed as dreammaker places it: at the operator token (`.`, `?.`, `:`, `[`), right after the object.
    fn follow_on(&mut self, object: &Expr, follow: Follow) -> Expression {
        let inner = self.expr(object);
        let (term, mut follows) = self.into_base(inner, object.span.start);
        let l = self.loc(object.span.end);
        follows.push(Spanned::new(l, follow));
        base(term, follows)
    }

    fn call(&mut self, e: &Expr, callee: &Expr, args: &[Expr]) -> Expression {
        let at = e.span.start;
        let l = self.loc(at);
        match &callee.kind {
            ExprKind::Ident(name) => {
                let term = match name.as_str() {
                    // A bare `new` (no parentheses) has no argument list.
                    "new" => Term::NewImplicit { args: if e.span.end == callee.span.end { None } else { Some(self.args(args)) } },
                    "list" | "alist" => Term::List(self.args(args)),
                    "input" => Term::Input { args: self.args(args), input_type: None, in_list: None },
                    "locate" => Term::Locate { args: self.args(args), in_list: None },
                    "pick" => Term::Pick(
                        args.iter()
                            .map(|a| match &a.kind {
                                ExprKind::Binary { op, lhs, rhs } if op == ";" => (Some(self.expr(lhs)), self.expr(rhs)),
                                _ => (None, self.expr(a)),
                            })
                            .collect::<Vec<_>>()
                            .into_boxed_slice(),
                    ),
                    "." => Term::SelfCall(self.args(args)),
                    ".." => Term::ParentCall(self.args(args)),
                    "as" => Term::As(InputType::empty()),
                    _ => Term::Call(ident2(name), self.args(args)),
                };
                base(Spanned::new(l, term), Vec::new())
            }
            ExprKind::Call { callee: inner, args: first } if matches!(&inner.kind, ExprKind::Ident(n) if n == "call") => {
                base(Spanned::new(l, Term::DynamicCall(self.args(first), self.args(args))), Vec::new())
            }
            ExprKind::Call { callee: inner, args: first } if matches!(&inner.kind, ExprKind::Ident(n) if n == "call_ext") => {
                let mut first = first.iter().map(|a| self.expr(a));
                let a = first.next().unwrap_or_else(|| unconverted("call_ext"));
                let b = first.next();
                let term = match b {
                    Some(function) => Term::ExternalCall { library: Some(Box::new(a)), function: Box::new(function), args: self.args(args) },
                    None => Term::ExternalCall { library: None, function: Box::new(a), args: self.args(args) },
                };
                base(Spanned::new(l, term), Vec::new())
            }
            ExprKind::Member { object, selector, via_colon } => {
                let kind = if *via_colon { PropertyAccessKind::Colon } else { PropertyAccessKind::Dot };
                let args = self.args(args);
                self.follow_on(object, Follow::Call(kind, ident2(selector), args))
            }
            ExprKind::SafeMember { object, selector, via_colon } => {
                let kind = if *via_colon { PropertyAccessKind::SafeColon } else { PropertyAccessKind::SafeDot };
                let args = self.args(args);
                self.follow_on(object, Follow::Call(kind, ident2(selector), args))
            }
            // dreammaker keeps `x::proc()` as a proc reference and drops the arguments.
            ExprKind::StaticMember { object, selector } => self.follow_on(object, Follow::ProcReference(ident2(selector))),
            _ => {
                let _ = self.args(args);
                unconverted("call of a non-name")
            }
        }
    }

    /// `new X(...)`: dmbc reads `new` as a prefix over a postfix chain; dreammaker's term is the type (a prefab or a name with field
    /// accesses) and the first argument list, the rest of the chain follows the term.
    fn new_expr(&mut self, e: &Expr, value: &Expr) -> Expression {
        let l = self.loc(e.span.start);
        let (core, posts) = spine(value);
        let call_at = posts.iter().position(|(p, _)| matches!(p, Post::Call(_)));
        let (target, rest) = match call_at {
            Some(i) => (&posts[..i], &posts[i..]),
            None => (&posts[..], &posts[posts.len()..]),
        };
        let (args, rest) = match rest.split_first() {
            Some(((Post::Call(a), _), tail)) => (Some(self.args(a)), tail),
            _ => (None, rest),
        };
        let term = match &core.kind {
            ExprKind::TypePath(p) => {
                let mut vars = Vec::new();
                let mut ok = true;
                for (p, _) in target {
                    match p {
                        Post::Init(fields) => {
                            for (k, v) in fields.iter() {
                                vars.push((ident2(k), self.expr(v)));
                            }
                        }
                        _ => ok = false,
                    }
                }
                if !ok {
                    return unconverted("new over a path chain");
                }
                Term::NewPrefab { prefab: Box::new(Prefab { path: type_path(p), vars: vars.into_boxed_slice() }), args }
            }
            ExprKind::Ident(name) => {
                let mut fields = Vec::new();
                for (p, _) in target {
                    match p {
                        Post::Member(s, colon) => {
                            fields.push(Field { kind: if *colon { PropertyAccessKind::Colon } else { PropertyAccessKind::Dot }, ident: ident2(s) })
                        }
                        Post::SafeMember(s, colon) => fields.push(Field {
                            kind: if *colon { PropertyAccessKind::SafeColon } else { PropertyAccessKind::SafeDot },
                            ident: ident2(s),
                        }),
                        _ => {
                            // dreammaker reads `new L[1]` as `new L` and an index, and stops at a following argument list.
                            if let (Some(i), None) = (call_at, self.parse_error.as_ref()) {
                                self.parse_error = Some((posts[i].1, "got '(', expected one of: operator, field access, ';'".into()));
                            }
                            return unconverted("new over an indexed name");
                        }
                    }
                }
                Term::NewMiniExpr { expr: Box::new(MiniExpr { ident: ident2(name), fields: fields.into_boxed_slice() }), args }
            }
            _ => return unconverted("new over an expression"),
        };
        let mut follows = Vec::new();
        for (p, at) in rest {
            let l = self.loc(*at);
            let f = match p {
                Post::Member(s, colon) => Follow::Field(if *colon { PropertyAccessKind::Colon } else { PropertyAccessKind::Dot }, ident2(s)),
                Post::SafeMember(s, colon) => {
                    Follow::Field(if *colon { PropertyAccessKind::SafeColon } else { PropertyAccessKind::SafeDot }, ident2(s))
                }
                Post::Static(s) => Follow::StaticField(ident2(s)),
                Post::Index(i) => Follow::Index(ListAccessKind::Normal, Box::new(self.expr(i))),
                Post::SafeIndex(i) => Follow::Index(ListAccessKind::Safe, Box::new(self.expr(i))),
                Post::Unary(op) => Follow::Unary(if *op == "post++" { UnaryOp::PostIncr } else { UnaryOp::PostDecr }),
                Post::Call(_) | Post::Init(_) => return unconverted("new followed by a call"),
            };
            follows.push(Spanned::new(l, f));
        }
        base(Spanned::new(l, term), follows)
    }

    pub(crate) fn expr(&mut self, e: &Expr) -> Expression {
        let at = e.span.start;
        match &e.kind {
            ExprKind::Ident(name) => {
                let l = self.loc(at);
                let term = match name.as_str() {
                    "__PROC__" => Term::__PROC__,
                    "__TYPE__" => Term::__TYPE__,
                    "__IMPLIED_TYPE__" => Term::__IMPLIED_TYPE__,
                    _ => Term::Ident(name.clone()),
                };
                base(Spanned::new(l, term), Vec::new())
            }
            ExprKind::Literal(text) => {
                self.literal(text, at)
            }
            ExprKind::TypePath(p) => {
                let l = self.loc(at);
                base(Spanned::new(l, Term::Prefab(Box::new(Prefab::from(type_path(p))))), Vec::new())
            }
            ExprKind::Unary { op, value } => {
                if op == "new" {
                    return self.new_expr(e, value);
                }
                let uop = match op.as_str() {
                    "-" => UnaryOp::Neg,
                    "!" => UnaryOp::Not,
                    "~" => UnaryOp::BitNot,
                    "*" => UnaryOp::Dereference,
                    "&" => UnaryOp::Reference,
                    "pre++" => UnaryOp::PreIncr,
                    "pre--" => UnaryOp::PreDecr,
                    "post++" => UnaryOp::PostIncr,
                    "post--" => UnaryOp::PostDecr,
                    _ => return self.expr(value),
                };
                let inner = self.expr(value);
                let (term, mut follows) = self.into_base(inner, value.span.start);
                // A postfix operator sits after its operand, a prefix one at the expression's start.
                let l = self.loc(if op.starts_with("post") { value.span.end } else { at });
                follows.push(Spanned::new(l, Follow::Unary(uop)));
                base(term, follows)
            }
            ExprKind::Binary { op, lhs, rhs } => {
                if op == "in" {
                    // `locate(T) in L`: dreammaker's Locate term carries the list.
                    if let ExprKind::Call { callee, args } = &lhs.kind {
                        if let ExprKind::Ident(n) = &callee.kind {
                            if n == "locate" {
                                let l = self.loc(lhs.span.start);
                                let args = self.args(args);
                                let in_list = Some(Box::new(self.expr(rhs)));
                                return base(Spanned::new(l, Term::Locate { args, in_list }), Vec::new());
                            }
                            if n == "input" {
                                let l = self.loc(lhs.span.start);
                                let args = self.args(args);
                                let in_list = Some(Box::new(self.expr(rhs)));
                                return base(Spanned::new(l, Term::Input { args, input_type: None, in_list }), Vec::new());
                            }
                        }
                    }
                    if let ExprKind::TypeFilter { value, types } = &lhs.kind {
                        if let ExprKind::Call { callee, args } = &value.kind {
                            if matches!(&callee.kind, ExprKind::Ident(n) if n == "input") {
                                let l = self.loc(lhs.span.start);
                                let args = self.args(args);
                                let in_list = Some(Box::new(self.expr(rhs)));
                                return base(Spanned::new(l, Term::Input { args, input_type: Some(input_type(types)), in_list }), Vec::new());
                            }
                        }
                    }
                }
                let l = Box::new(self.expr(lhs));
                let r = Box::new(self.expr(rhs));
                if let Some(op) = assign_op(op) {
                    return Expression::AssignOp { op, lhs: l, rhs: r };
                }
                match binary_op(op) {
                    Some(op) => Expression::BinaryOp { op, lhs: l, rhs: r },
                    None => unconverted(op),
                }
            }
            ExprKind::Conditional { condition, then_value, else_value } => Expression::TernaryOp {
                cond: Box::new(self.expr(condition)),
                if_: Box::new(self.expr(then_value)),
                else_: Box::new(self.expr(else_value)),
            },
            ExprKind::Call { callee, args } => self.call(e, callee, args),
            ExprKind::Member { object, selector, via_colon } => {
                let kind = if *via_colon { PropertyAccessKind::Colon } else { PropertyAccessKind::Dot };
                self.follow_on(object, Follow::Field(kind, ident2(selector)))
            }
            ExprKind::SafeMember { object, selector, via_colon } => {
                let kind = if *via_colon { PropertyAccessKind::SafeColon } else { PropertyAccessKind::SafeDot };
                self.follow_on(object, Follow::Field(kind, ident2(selector)))
            }
            ExprKind::StaticMember { object, selector } => self.follow_on(object, Follow::StaticField(ident2(selector))),
            ExprKind::Index { object, index } => {
                let i = Box::new(self.expr(index));
                self.follow_on(object, Follow::Index(ListAccessKind::Normal, i))
            }
            ExprKind::SafeIndex { object, index } => {
                let i = Box::new(self.expr(index));
                self.follow_on(object, Follow::Index(ListAccessKind::Safe, i))
            }
            ExprKind::TypeFilter { value, types } => {
                if let ExprKind::Call { callee, args } = &value.kind {
                    if matches!(&callee.kind, ExprKind::Ident(n) if n == "input") {
                        let l = self.loc(at);
                        let args = self.args(args);
                        return base(Spanned::new(l, Term::Input { args, input_type: Some(input_type(types)), in_list: None }), Vec::new());
                    }
                }
                unconverted("as")
            }
            ExprKind::ObjectInitializer { object, fields } => match &object.kind {
                ExprKind::TypePath(p) => {
                    let l = self.loc(at);
                    let vars: Vec<_> = fields.iter().map(|(k, v)| (ident2(k), self.expr(v))).collect();
                    base(Spanned::new(l, Term::Prefab(Box::new(Prefab { path: type_path(p), vars: vars.into_boxed_slice() }))), Vec::new())
                }
                _ => unconverted("initializer"),
            },
            ExprKind::Group(inner) => {
                let l = self.loc(at);
                let inner = self.expr(inner);
                base(Spanned::new(l, Term::Expr(Box::new(inner))), Vec::new())
            }
        }
    }
}

#[cfg(test)]
mod literal_tests {
    use super::*;

    #[test]
    fn multi_line_interpolation_converts() {
        let text = "\"[pick(\n\t\t\t\"a\",\n\t\t\t\"b\")] end\"";
        let mut locate = |_: usize| Location::default();
        let e = Converter { locate: &mut locate, parse_error: None }.literal(text, 0);
        let s = format!("{e:?}");
        assert!(!s.contains(UNCONVERTED), "{s}");
        assert!(s.contains("Pick"), "{s}");
    }
}
