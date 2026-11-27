//! The body walk (SpacemanDMM DreamChecker's `AnalyzeProc`) over the compiler front end's typed statements.
//!
//! A proc's walk is a pure function of its body and the declarations it reads (the model, the settings every proc's first
//! statements declare): it returns its [`ProcFacts`] (diagnostics, calls, blocking and impure operations, `waitfor`, keyword
//! arguments) and touches nothing else, so its result can be kept per proc and recomputed only when one of those inputs changes.
use dm::{DMError, Location, Severity};
use dm_syntax::{Expr, ForControl, ForInitializer, Statement, StatementKind, SwitchAlternative};
use foldhash::{HashMap, HashMapExt};

use super::analysis::{assumption_set, Analysis, Assumption, StaticType, Value};
use super::directives::{error, lookup, Directives, FILTER_FLAG_VALUES, VALID_FILTER_FLAGS, VALID_FILTER_TYPES};
use super::input::{InputType, Site, Where};
use super::model::{Model, ProcId, TypeId, VarFlags};
use super::type_expr::{TypeExpr, TypeExprContext};
use super::view::{Base, Follow, Part, Reader, Shape, Term, UnaryOp};

/// What every walk reads and none writes.
pub struct Shared {
    pub return_type: HashMap<ProcId, TypeExpr>,
    pub directives: Directives,
}

/// What one proc's walk found.
#[derive(Clone, Debug, Default, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct ProcFacts {
    pub diagnostics: Vec<super::facts::Diag>,
    /// (callee, where, inside a new context).
    pub calls: Vec<(ProcId, Where, bool)>,
    pub sleeps: Vec<(String, Where)>,
    pub impure: Vec<(String, Where)>,
    pub waitfor: bool,
    /// (`src/proc/name` key, the callee's location, keyword, where): an inexact call's keyword argument.
    pub kwargs: Vec<(String, Location, String, Where)>,
}

impl ProcFacts {
    /// Every place's offset through `f` (`At`, `LineEnd` and `DeclEnd` places; a location stays): a store keeps them relative to the
    /// body's start.
    pub fn map_places(&mut self, f: impl Fn(usize) -> usize) {
        let g = |w: &mut Where| match w {
            Where::At(o) | Where::LineEnd(o) | Where::DeclEnd(o) => *o = f(*o),
            Where::Fixed(_) => {}
        };
        for (_, w, _) in &mut self.calls {
            g(w);
        }
        for (_, w) in self.sleeps.iter_mut().chain(self.impure.iter_mut()) {
            g(w);
        }
        for (_, _, _, w) in &mut self.kwargs {
            g(w);
        }
    }
}

#[derive(Debug)]
pub struct ControlFlow {
    pub returns: bool,
    pub continues: bool,
    pub breaks: bool,
    pub fuzzy: bool,
}

impl ControlFlow {
    fn alltrue() -> ControlFlow {
        ControlFlow { returns: true, continues: true, breaks: true, fuzzy: false }
    }
    fn allfalse() -> ControlFlow {
        ControlFlow { returns: false, continues: false, breaks: false, fuzzy: false }
    }
    fn terminates(&self) -> bool {
        !self.fuzzy && (self.returns || self.continues || self.breaks)
    }
    fn terminates_loop(&self) -> bool {
        !self.fuzzy && (self.returns || self.breaks)
    }
    fn no_else(&mut self) {
        self.returns = false;
        self.continues = false;
        self.breaks = false;
    }
    fn merge(&mut self, other: ControlFlow) {
        if !self.fuzzy && other.returns {
            self.returns = true;
        }
        if other.fuzzy {
            self.returns = false;
        }
        if other.continues {
            self.continues = true;
        }
        if other.breaks {
            self.breaks = true;
        }
        if other.fuzzy {
            self.fuzzy = true;
        }
    }
    fn merge_false(&mut self, other: ControlFlow) {
        if !other.returns {
            self.returns = false;
        }
        if !other.continues {
            self.continues = false;
        }
        if !other.breaks {
            self.breaks = false;
        }
        if other.fuzzy {
            self.fuzzy = true;
        }
    }
    fn finalize(&mut self) {
        if self.returns || self.breaks || self.continues {
            self.fuzzy = false;
        }
    }
    fn end_loop(&mut self) {
        self.returns = false;
        self.continues = false;
        self.breaks = false;
        self.fuzzy = false;
    }
}

#[derive(Debug, Clone)]
struct LocalVar {
    location: Where,
    analysis: Analysis,
}

impl From<Analysis> for LocalVar {
    fn from(analysis: Analysis) -> Self {
        LocalVar { location: Where::none(), analysis }
    }
}

type Locals = HashMap<String, LocalVar>;

/// A declaration as SpacemanDMM reads it: flags, type pieces, name, and the dimensions of a `[..]` suffix.
pub struct Declared {
    pub flags: VarFlags,
    pub type_path: Vec<String>,
    pub name: String,
    pub dims: Vec<Option<String>>,
}

/// `var/static/list/x[4]`: the flags at the front, the type pieces, the name and the list suffix (a suffix makes the type `list/...`).
pub fn declared(declaration: &str) -> Declared {
    let decl = declaration.trim();
    let decl = decl.split(" as ").next().unwrap_or(decl).trim();
    let rest = decl.strip_prefix("var").unwrap_or(decl).trim_start_matches(['/', ' ', '\t']);
    let (path, suffix_text) = match rest.find('[') {
        Some(at) => (&rest[..at], &rest[at..]),
        None => (rest, ""),
    };
    let mut parts: Vec<String> = path.split('/').map(str::trim).filter(|p| !p.is_empty()).map(str::to_owned).collect();
    let name = parts.pop().unwrap_or_default();
    let mut flags = 0u8;
    let mut iter = parts.into_iter().peekable();
    while let Some(flag) = iter.peek().and_then(|p| VarFlags::from_name(p)) {
        flags |= flag;
        iter.next();
    }
    let mut type_path: Vec<String> = iter.collect();
    let mut dims = Vec::new();
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
        dims.push((!inner.is_empty()).then(|| inner.to_owned()));
        cursor = open.get(close + 1..).unwrap_or("").trim_start();
    }
    if !dims.is_empty() {
        type_path.insert(0, "list".to_owned());
    }
    Declared { flags: VarFlags(flags), type_path, name, dims }
}

/// A for binding (`var/obj/O as obj`, `O`): its declaration when it declares, and its name.
fn binding(binding: &str) -> (Option<Declared>, String) {
    let decl = binding.split_once(" as ").map_or(binding.trim(), |(d, _)| d.trim());
    if decl.starts_with("var/") || decl.starts_with("var ") {
        let d = declared(decl);
        let name = d.name.clone();
        (Some(d), name)
    } else {
        (None, decl.to_owned())
    }
}

/// A body's statements as SpacemanDMM's parser groups them: `var/a, b = 1` is one statement of several declarations.
enum Logical<'b> {
    One(&'b Statement),
    Vars(Vec<&'b Statement>),
}

pub struct Walk<'a, 's> {
    pub model: &'a Model,
    pub shared: &'a Shared,
    pub reader: Reader<'s, 'a>,
    pub ty: TypeId,
    pub proc: ProcId,
    pub facts: ProcFacts,
    calls_parent: bool,
    inside_newcontext: u32,
}

impl<'a, 's> Walk<'a, 's> {
    pub fn new(model: &'a Model, shared: &'a Shared, site: &'s (dyn Site + 'a), proc: ProcId) -> Self {
        Walk { model, shared, reader: Reader { site, shift: 0 }, ty: proc.ty, proc, facts: ProcFacts::default(), calls_parent: false, inside_newcontext: 0 }
    }

    fn register(&mut self, e: DMError) {
        self.facts.diagnostics.push(super::facts::Diag::of(&e));
    }

    fn loc(&self, offset: usize) -> Where {
        Where::At(self.reader.shift + offset)
    }

    fn place(&self, at: Where) -> Location {
        self.reader.site.place(at)
    }

    fn static_type_of(&mut self, location: Where, of: &[String]) -> StaticType {
        match static_type(self.model, self.place(location), of) {
            Ok(s) => s,
            Err(e) => {
                self.register(e);
                StaticType::None
            }
        }
    }

    fn static_type(&mut self, location: Where, of: &[String]) -> Analysis {
        Analysis::from(self.static_type_of(location, of))
    }

    pub fn run(&mut self, body: &[Statement]) {
        let m = self.model;
        let mut locals: Locals = HashMap::new();
        locals.insert(".".to_owned(), Analysis::empty().into());
        locals.insert("args".to_owned(), Analysis::from_static_type_impure(m.expect("/list")).into());
        locals.insert("usr".to_owned(), Analysis::from_static_type(m.expect("/mob")).into());
        locals.insert("callee".to_owned(), Analysis::from_static_type(m.expect("/callee")).into());
        locals.insert("caller".to_owned(), Analysis::from_static_type(m.expect("/callee")).into());
        if !m.ty(self.ty).is_root() {
            locals.insert("src".to_owned(), Analysis::from_static_type(self.ty).into());
        }
        locals.insert(
            "global".to_owned(),
            Analysis {
                static_ty: StaticType::Type(m.root()),
                aset: assumption_set![Assumption::IsNull(false)],
                value: None,
                fix_hint: None,
                is_impure: Some(true),
            }
            .into(),
        );
        let proc_location = m.value(self.proc).location;
        for param in m.value(self.proc).parameters.iter() {
            let mut analysis = self.static_type(param.location, &param.type_path);
            analysis.is_impure = Some(true);
            locals.insert(param.name.clone(), LocalVar { location: proc_location, analysis });
        }

        self.visit_block(body, &mut locals, true);

        let d = &self.shared.directives;
        let proc_location = self.place(proc_location);
        if let Some(parent) = m.parent_proc(self.proc) {
            if let Some((proc, true, location)) = d.private.get_self_or_parent(m, self.proc) {
                if proc != self.proc {
                    let e = error(proc_location, format!("proc overrides private parent, prohibited by {}", m.proc_display(proc)))
                        .with_note(location, "prohibited by this private_proc annotation")
                        .with_errortype("private_proc");
                    self.register(e);
                }
            }
            if let Some((proc, true, location)) = d.must_not_override.get_self_or_parent(m, self.proc) {
                if proc != self.proc {
                    let e = error(proc_location, format!("proc overrides parent, prohibited by {}", m.proc_display(proc)))
                        .with_note(location, "prohibited by this must_not_override annotation")
                        .with_errortype("must_not_override");
                    self.register(e);
                }
            }
            if !self.calls_parent {
                if let Some((proc, true, location)) = d.must_call_parent.get_self_or_parent(m, self.proc) {
                    let e = error(proc_location, format!("proc never calls parent, required by {}", m.proc_display(proc)))
                        .with_note(location, "required by this must_call_parent annotation")
                        .with_errortype("must_call_parent");
                    self.register(e);
                }
            }
            if !m.is_builtin(parent) && self.proc.ty == parent.ty && d.can_be_redefined.get_self_or_parent(m, self.proc).is_none() {
                let e = error(proc_location, format!("redefining proc {}/{}", m.ty(self.ty).pretty_path(), m.proc_name(self.proc)))
                    .with_errortype("redefined_proc")
                    .with_note(self.place(m.value(parent).location), "previous definition is here")
                    .set_severity(Severity::Hint);
                self.register(e);
            }
        }
    }

    /// The statements of a block grouped as SpacemanDMM's parser groups them, each at its place.
    fn logical<'b>(&mut self, block: &'b [Statement]) -> Vec<(Where, Logical<'b>)> {
        let mut out: Vec<(Where, Logical<'b>)> = Vec::new();
        for s in block {
            let location = self.loc(s.header_span.start);
            if let StatementKind::Var { .. } = &s.kind {
                if !s.raw_header.trim_start().starts_with("var") {
                    if let Some((prev_loc, prev)) = out.last_mut() {
                        if self.place(*prev_loc).line == self.place(location).line {
                            match prev {
                                Logical::One(p) if matches!(p.kind, StatementKind::Var { .. }) => {
                                    *prev = Logical::Vars(vec![p, s]);
                                    continue;
                                }
                                Logical::Vars(list) => {
                                    list.push(s);
                                    continue;
                                }
                                _ => {}
                            }
                        }
                    }
                }
            }
            out.push((location, Logical::One(s)));
        }
        out
    }

    fn visit_block(&mut self, block: &[Statement], locals: &mut Locals, mut setting_allowed: bool) -> ControlFlow {
        let mut term = ControlFlow::allfalse();
        for (location, stmt) in self.logical(block) {
            if term.terminates() {
                self.register(error(self.place(location), "possible unreachable code here").with_errortype("unreachable_code"));
                return term;
            }
            match &stmt {
                Logical::One(Statement { kind: StatementKind::Set { attribute, .. }, .. }) => {
                    if !setting_allowed && attribute.starts_with("SpacemanDMM_") {
                        self.register(error(self.place(location), "set statement not at the top of the proc").with_errortype("set_has_no_effect"));
                    }
                }
                _ => setting_allowed = false,
            }
            let state = self.visit_logical(location, &stmt, locals);
            term.merge(state);
        }
        term
    }

    fn visit_logical(&mut self, location: Where, stmt: &Logical<'_>, locals: &mut Locals) -> ControlFlow {
        match stmt {
            Logical::One(s) => self.visit_statement(location, s, locals),
            Logical::Vars(list) => {
                for s in list {
                    if let StatementKind::Var { declaration, value } = &s.kind {
                        self.visit_var_decl(location, declaration, value.as_ref(), locals);
                    }
                }
                ControlFlow::allfalse()
            }
        }
    }

    fn loop_condition_check(&mut self, location: Where, e: &Expr) {
        match self.is_truthy(e) {
            Some(true) => self.register(error(self.place(location), "loop condition is always true").with_errortype("loop_condition_determinate")),
            Some(false) => self.register(error(self.place(location), "loop condition is always false").with_errortype("loop_condition_determinate")),
            None => {}
        }
    }

    fn visit_control_condition(&mut self, location: Where, e: &Expr) {
        if self.is_const_eval(e) {
            self.register(error(self.place(location), "control flow condition is a constant evalutation").with_errortype("control_condition_static"));
        } else if self.as_term(e).is_some_and(|t| t.is_static()) {
            self.register(error(self.place(location), "control flow condition is a static term").with_errortype("control_condition_static"));
        }
    }

    /// A control's condition as SpacemanDMM places it: at the `(` it is read after.
    fn condition_loc(&mut self, condition: &Expr) -> Where {
        let at = dm_syntax::control_open_paren(self.reader.site.text(), condition.span.start).unwrap_or(condition.span.start);
        self.loc(at)
    }

    /// `e`'s term when it is a term with no follows.
    fn as_term<'e>(&mut self, e: &'e Expr) -> Option<Term<'e>> {
        match self.reader.shape(e) {
            Shape::Base(b) if b.follows.is_empty() => Some(b.term),
            _ => None,
        }
    }

    fn is_const_eval(&mut self, e: &Expr) -> bool {
        match self.reader.shape(e) {
            Shape::Binary { op, lhs, rhs } => {
                let l = self.as_term(lhs).is_some_and(|t| t.is_static());
                let r = l && self.as_term(rhs).is_some_and(|t| t.is_static());
                r && matches!(op, "==" | "!=" | "<" | ">" | "<=" | ">=" | "&&" | "||")
            }
            _ => false,
        }
    }

    pub fn is_truthy(&mut self, e: &Expr) -> Option<bool> {
        match self.reader.shape(e) {
            Shape::Base(b) => {
                let mut truthy = self.term_truthy(&b.term)?;
                for (f, _) in &b.follows {
                    match f {
                        Follow::Unary(UnaryOp::Not) => truthy = !truthy,
                        _ => return None,
                    }
                }
                Some(truthy)
            }
            Shape::Binary { op, lhs, rhs } => {
                let l = self.is_truthy(lhs)?;
                let r = self.is_truthy(rhs)?;
                match op {
                    "&&" => Some(l && r),
                    "||" => Some(l || r),
                    _ => None,
                }
            }
            Shape::Assign { op, rhs, .. } => {
                if op == "=" {
                    let t = self.as_term(rhs)?;
                    self.term_truthy(&t)
                } else {
                    None
                }
            }
            Shape::Ternary { cond, if_, else_ } => {
                if self.is_truthy(cond)? {
                    self.is_truthy(if_)
                } else {
                    self.is_truthy(else_)
                }
            }
            Shape::Unread => None,
        }
    }

    fn term_truthy(&mut self, t: &Term<'_>) -> Option<bool> {
        match t {
            Term::Null => Some(false),
            Term::Int(i) => Some(*i != 0),
            Term::Float(f) => Some(*f != 0.0),
            Term::Str(s) => Some(!s.is_empty()),
            Term::Prefab { .. } => Some(true),
            Term::NewImplicit(_) | Term::NewPrefab { .. } | Term::NewMiniExpr | Term::List(_) => Some(true),
            Term::Interp { first, parts } => {
                if !first.is_empty() || parts.iter().any(|(_, p)| !p.is_empty()) {
                    Some(true)
                } else {
                    None
                }
            }
            Term::Group(e) => self.is_truthy(e),
            _ => None,
        }
    }

    fn visit_statement(&mut self, location: Where, s: &Statement, locals: &mut Locals) -> ControlFlow {
        match &s.kind {
            StatementKind::Call(e) | StatementKind::Expression(e) => {
                if let dm_syntax::ExprKind::Call { callee, args } = &e.kind {
                    if let dm_syntax::ExprKind::Ident(name) = &callee.kind {
                        if name == "del" && args.len() == 1 {
                            // `del x`: an expression in parentheses at the argument.
                            let at = self.loc(args[0].span.start);
                            self.visit_expression(at, &args[0], None, locals);
                            return ControlFlow::allfalse();
                        }
                        if name == "CRASH" && args.len() <= 1 {
                            if let Some(a) = args.first() {
                                self.visit_expression(location, a, None, locals);
                            }
                            return ControlFlow { returns: true, continues: false, breaks: false, fuzzy: false };
                        }
                    }
                }
                self.visit_expr_statement(location, e, locals);
            }
            StatementKind::Assign { target, op, value } => {
                if let Some(op) = super::view::assign_op(op) {
                    self.visit_assign(location, op, target, value, None, locals);
                }
            }
            StatementKind::Return(Some(e)) => {
                if self.inside_newcontext > 0 {
                    self.register(error(self.place(location), "returning a value in a spawn has no effect").set_severity(Severity::Warning));
                }
                let return_type = self.visit_expression(location, e, None, locals);
                locals.get_mut(".").unwrap().analysis = return_type;
                return ControlFlow { returns: true, continues: false, breaks: false, fuzzy: false };
            }
            StatementKind::Return(None) => return ControlFlow { returns: true, continues: false, breaks: false, fuzzy: false },
            StatementKind::Throw(e) => {
                self.visit_expression(location, e, None, locals);
            }
            StatementKind::While { condition, body } => {
                let mut scoped = locals.clone();
                self.visit_expression(location, condition, None, &mut scoped);
                let mut state = self.visit_block(body, &mut scoped, false);
                state.end_loop();
                return state;
            }
            StatementKind::DoWhile { body, condition } => {
                let mut scoped = locals.clone();
                let mut state = self.visit_block(body, &mut scoped, false);
                if state.terminates_loop() {
                    self.register(error(self.place(location), "do while terminates without ever reaching condition"));
                    return state;
                }
                let cl = self.condition_loc(condition);
                self.visit_expression(cl, condition, None, &mut scoped);
                state.end_loop();
                return state;
            }
            StatementKind::If { condition, then_branch, else_branch, has_else } => {
                let mut arms: Vec<(&Expr, &[Statement])> = vec![(condition, then_branch)];
                let mut rest: &[Statement] = else_branch;
                let mut rest_has_else = *has_else;
                loop {
                    if let [only] = rest {
                        if let StatementKind::If { condition, then_branch, else_branch, has_else } = &only.kind {
                            if only.span.start < only.header_span.start {
                                arms.push((condition, then_branch));
                                rest = else_branch;
                                rest_has_else = *has_else;
                                continue;
                            }
                        }
                    }
                    break;
                }
                let else_arm = rest_has_else.then_some(rest);
                let mut allterm = ControlFlow::alltrue();
                let mut alwaystrue = false;
                for (condition, block) in arms {
                    let cl = self.condition_loc(condition);
                    let mut scoped = locals.clone();
                    self.visit_control_condition(cl, condition);
                    if alwaystrue {
                        self.register(
                            error(self.place(cl), "unreachable if block, preceeding if/elseif condition(s) are always true").with_errortype("unreachable_code"),
                        );
                    }
                    self.visit_expression(cl, condition, None, &mut scoped);
                    let state = self.visit_block(block, &mut scoped, false);
                    match self.is_truthy(condition) {
                        Some(true) => {
                            self.register(error(self.place(cl), "if condition is always true").with_errortype("if_condition_determinate"));
                            allterm.merge_false(state);
                            alwaystrue = true;
                        }
                        Some(false) => self.register(error(self.place(cl), "if condition is always false").with_errortype("if_condition_determinate")),
                        None => allterm.merge_false(state),
                    }
                }
                match else_arm {
                    Some(else_arm) => {
                        if alwaystrue {
                            if let Some(first) = else_arm.first() {
                                let at = self.loc(first.header_span.start);
                                self.register(
                                    error(self.place(at), "unreachable else block, preceeding if/elseif condition(s) are always true").with_errortype("unreachable_code"),
                                );
                            }
                        }
                        let state = self.visit_block(else_arm, &mut locals.clone(), false);
                        allterm.merge_false(state);
                    }
                    None => {
                        allterm.no_else();
                        return allterm;
                    }
                }
                allterm.finalize();
                return allterm;
            }
            StatementKind::For { control, body } => return self.visit_for(location, s, control, body, locals),
            StatementKind::Var { declaration, value } => self.visit_var_decl(location, declaration, value.as_ref(), locals),
            StatementKind::Set { attribute, relation, value } => {
                if relation == "in" {
                    return ControlFlow::allfalse();
                }
                if attribute != "waitfor" {
                    return ControlFlow::allfalse();
                }
                if matches!(self.as_term(value), Some(Term::Int(0))) || matches!(self.as_term(value), Some(Term::Ident(i)) if i == "FALSE") {
                    self.facts.waitfor = true;
                }
            }
            StatementKind::Spawn { delay, body } => {
                self.inside_newcontext = self.inside_newcontext.wrapping_add(1);
                let mut scoped = locals.clone();
                if let Some(delay) = delay {
                    self.visit_expression(location, delay, None, &mut scoped);
                }
                self.visit_block(body, &mut scoped, false);
                self.inside_newcontext = self.inside_newcontext.wrapping_sub(1);
            }
            StatementKind::Switch { selector, cases, else_branch } => {
                // Each case where SpacemanDMM places it: where its block ends, the newline after the block's last line.
                let mut case_locs = Vec::with_capacity(cases.len());
                for case in cases {
                    let end = case.alternatives.last().map(|a| match a {
                        SwitchAlternative::Exact(e) => e.span.end,
                        SwitchAlternative::Range(_, b) => b.span.end,
                    });
                    let last = case.body.iter().map(|s| s.span.end).max().or(end).unwrap_or(0);
                    case_locs.push(Where::LineEnd(self.reader.shift + last.saturating_sub(1)));
                }
                let default = if else_branch.is_empty() { None } else { Some(else_branch.as_slice()) };
                super::switch_rand::check(self, selector, cases, &case_locs, default.is_some(), location);
                let mut allterm = ControlFlow::alltrue();
                self.visit_control_condition(location, selector);
                self.visit_expression(location, selector, None, locals);
                for (case, &case_loc) in cases.iter().zip(&case_locs) {
                    let mut scoped = locals.clone();
                    if let [SwitchAlternative::Exact(e)] = case.alternatives.as_slice() {
                        if matches!(self.reader.shape(e), Shape::Binary { op: "||", .. }) {
                            self.register(
                                error(self.place(case_loc), "Elements in a switch-case branch separated by ||, this is likely in error and should be replaced by a comma")
                                    .set_severity(Severity::Warning),
                            );
                        }
                    }
                    for alt in &case.alternatives {
                        match alt {
                            SwitchAlternative::Exact(e) => {
                                self.visit_expression(case_loc, e, None, &mut scoped);
                            }
                            SwitchAlternative::Range(a, b) => {
                                self.visit_expression(case_loc, a, None, &mut scoped);
                                self.visit_expression(case_loc, b, None, &mut scoped);
                            }
                        }
                    }
                    let state = self.visit_block(&case.body, &mut scoped, false);
                    allterm.merge_false(state);
                }
                match default {
                    Some(d) => {
                        let state = self.visit_block(d, &mut locals.clone(), false);
                        allterm.merge_false(state);
                    }
                    None => {
                        allterm.no_else();
                        return allterm;
                    }
                }
                allterm.finalize();
                return allterm;
            }
            StatementKind::Try { body, catch_binding, catch_body, .. } => {
                self.visit_block(body, &mut locals.clone(), false);
                let mut catch_locals = locals.clone();
                if let Some(b) = catch_binding.as_deref().filter(|b| !b.is_empty()) {
                    let pieces: Vec<String> = b.split('/').map(str::trim).filter(|p| !p.is_empty()).map(str::to_owned).collect();
                    if let Some((name, mut type_path)) = pieces.split_last() {
                        if let Some((first, rest)) = type_path.split_first() {
                            if first == "var" {
                                type_path = rest;
                            }
                        }
                        let flags_skipped: Vec<String> = type_path.iter().skip_while(|p| VarFlags::from_name(p).is_some()).cloned().collect();
                        self.visit_var(location, &flags_skipped, name, None, &mut catch_locals);
                    }
                }
                self.visit_block(catch_body, &mut catch_locals, false);
            }
            StatementKind::Continue | StatementKind::ContinueLabel(_) => {
                return ControlFlow { returns: false, continues: true, breaks: false, fuzzy: true };
            }
            StatementKind::Break | StatementKind::BreakLabel(_) => {
                return ControlFlow { returns: false, continues: false, breaks: true, fuzzy: true };
            }
            StatementKind::Goto(_) => {}
            StatementKind::Label { body, .. } => {
                self.visit_block(body, &mut locals.clone(), false);
            }
            StatementKind::Unsupported => {}
        }
        ControlFlow::allfalse()
    }

    /// An expression statement: a discarded call to a pure proc, a `<<` onto an impure value, then the expression.
    fn visit_expr_statement(&mut self, location: Where, e: &Expr, locals: &mut Locals) {
        match self.reader.shape(e) {
            Shape::Base(Base { term: Term::Call { name, .. }, follows, .. }) => {
                if !follows.iter().any(|(f, _)| matches!(f, Follow::Call(..))) {
                    if let Some(proc) = self.model.get_proc(self.ty, name) {
                        if let Some((_, _, loc)) = self.shared.directives.must_be_pure.get_self_or_parent(self.model, proc) {
                            self.register(
                                error(self.place(location), format!("call to pure proc {name} discards return value"))
                                    .with_note(loc, "prohibited by this must_be_pure annotation"),
                            );
                        }
                    }
                }
            }
            Shape::Binary { op: "<<", lhs, .. } => {
                let l = self.visit_expression(location, lhs, None, locals);
                if l.is_impure == Some(true) {
                    self.facts.impure.push(("purity breaking << on expression".into(), location));
                }
            }
            _ => {}
        }
        self.visit_expression(location, e, None, locals);
    }

    fn visit_for(&mut self, location: Where, s: &Statement, control: &ForControl, body: &[Statement], locals: &mut Locals) -> ControlFlow {
        let mut scoped = locals.clone();
        match control {
            ForControl::CStyle { initializer, condition, step } => {
                let clause = s.raw_header.trim().strip_prefix("for").unwrap_or("").trim_start();
                let inner = clause.strip_prefix('(').and_then(|c| c.split(')').next()).unwrap_or("x");
                if initializer.is_none() && condition.is_none() && step.is_none() && inner.trim().is_empty() {
                    let mut state = self.visit_block(body, &mut scoped, false);
                    state.end_loop();
                    return state;
                }
                match initializer {
                    Some(ForInitializer::Declare { declaration, value }) => self.visit_var_decl(location, declaration, value.as_ref(), &mut scoped),
                    Some(ForInitializer::Expr(e)) => self.visit_expr_statement(location, e, &mut scoped),
                    None => {}
                }
                if let Some(test) = condition {
                    self.loop_condition_check(location, test);
                    self.visit_control_condition(location, test);
                    self.visit_expression(location, test, None, &mut scoped);
                }
                if let Some(inc) = step {
                    self.visit_expr_statement(location, inc, &mut scoped);
                }
                let mut state = self.visit_block(body, &mut scoped, false);
                state.end_loop();
                state
            }
            ForControl::All { declaration } => {
                let (decl, name) = binding(declaration);
                if let Some(d) = decl {
                    self.visit_var(location, &d.type_path, &name, None, &mut scoped);
                }
                let mut state = self.visit_block(body, &mut scoped, false);
                state.end_loop();
                state
            }
            ForControl::Each { binding: b, iterable } => {
                let list = self.visit_expression(location, iterable, None, &mut scoped);
                self.check_iterable(location, &list.static_ty);
                let (decl, name) = binding(b);
                if let Some(d) = decl {
                    self.visit_var(location, &d.type_path, &name, None, &mut scoped);
                }
                let mut state = self.visit_block(body, &mut scoped, false);
                state.end_loop();
                state
            }
            ForControl::Pair { key_binding, value_binding, iterable } => {
                let list = self.visit_expression(location, iterable, None, &mut scoped);
                self.check_iterable(location, &list.static_ty);
                let (decl, key) = binding(key_binding);
                if let Some(d) = decl {
                    self.visit_var(location, &d.type_path, &key, None, &mut scoped);
                }
                self.visit_var(location, &[], value_binding.trim(), None, &mut scoped);
                let mut state = self.visit_block(body, &mut scoped, false);
                state.end_loop();
                state
            }
            ForControl::Range { binding: b, start, end, step } => {
                self.visit_expression(location, end, None, &mut scoped);
                if let Some(step) = step {
                    self.visit_expression(location, step, None, &mut scoped);
                }
                let (decl, name) = binding(b);
                if let Some(d) = decl {
                    self.visit_var(location, &d.type_path, &name, Some(start), &mut scoped);
                }
                let mut state = self.visit_block(body, &mut scoped, false);
                let (st, et) = (self.as_term(start), self.as_term(end));
                if let (Some(Term::Int(i)), Some(Term::Int(o))) = (st, et) {
                    let validity = if i == 0 && o == 0 {
                        false
                    } else {
                        match step {
                            Some(stepexp) => match self.as_term(stepexp) {
                                Some(Term::Int(_)) | None => true,
                                Some(_) => i <= o,
                            },
                            None => i <= o,
                        }
                    };
                    if !validity {
                        self.register(error(self.place(location), "for range loop body is never reached due to invalid range"));
                    } else {
                        return state;
                    }
                }
                state.end_loop();
                state
            }
        }
    }

    fn check_iterable(&mut self, location: Where, st: &StaticType) {
        let m = self.model;
        match st {
            StaticType::None | StaticType::List { .. } => {}
            StaticType::Type(ty) => {
                let ty = *ty;
                if ty != m.expect("/world") && ty != m.expect("/list") && ty != m.expect("/alist") {
                    let atom = m.expect("/atom");
                    if m.is_subtype_of(ty, atom) {
                    } else if m.is_subtype_of(atom, ty) {
                        self.register(error(self.place(location), "iterating over a /datum which might not be an /atom").set_severity(Severity::Hint));
                    } else {
                        self.register(error(self.place(location), format!("iterating over a {} which cannot be iterated", m.ty(ty).path)));
                    }
                }
            }
            StaticType::Proc => self.register(error(self.place(location), "iterating over a procpath which cannot be iterated")),
        }
    }

    fn visit_var_decl(&mut self, location: Where, declaration: &str, value: Option<&Expr>, locals: &mut Locals) {
        let d = declared(declaration);
        match value {
            Some(v) => self.visit_var(location, &d.type_path, &d.name, Some(v), locals),
            None if d.dims.iter().any(Option::is_some) => {
                // `var/L[10]` is `var/list/L = new /list(10)`: SpacemanDMM's term carries no place.
                let static_type = self.static_type_of(location, &d.type_path);
                let list = self.model.expect("/list");
                let mut analysis = self.visit_new(Where::none(), list, &[], locals);
                analysis.static_ty = static_type;
                locals.insert(d.name.clone(), LocalVar { location, analysis });
            }
            None => self.visit_var(location, &d.type_path, &d.name, None, locals),
        }
    }

    fn visit_var(&mut self, location: Where, type_path: &[String], name: &str, value: Option<&Expr>, locals: &mut Locals) {
        let static_type = self.static_type_of(location, type_path);
        let mut analysis = match value {
            Some(expr) => self.visit_expression(location, expr, static_type.basic_type(), locals),
            None => Analysis::null(),
        };
        analysis.static_ty = static_type;
        locals.insert(name.to_owned(), LocalVar { location, analysis });
    }

    fn visit_assign(&mut self, location: Where, _op: &str, lhs: &Expr, rhs: &Expr, _hint: Option<TypeId>, locals: &mut Locals) -> Analysis {
        let l = self.visit_expression(location, lhs, None, locals);
        if l.is_impure == Some(true) {
            self.facts.impure.push(("Assignment on purity breaking expression".into(), location));
        }
        self.visit_expression(location, rhs, l.static_ty.basic_type(), locals)
    }

    fn visit_expression(&mut self, location: Where, e: &Expr, type_hint: Option<TypeId>, locals: &mut Locals) -> Analysis {
        match self.reader.shape(e) {
            Shape::Base(b) => {
                let base_hint = if b.follows.is_empty() { type_hint } else { None };
                let at = self.loc(b.term_at);
                let mut ty = self.visit_term(at, b.term_at, &b.term, base_hint, locals);
                for (f, place) in &b.follows {
                    let at = self.loc(*place);
                    ty = self.visit_follow(at, ty, f, locals);
                }
                ty
            }
            Shape::Binary { op: "<<", lhs, rhs } => {
                let lty = self.visit_expression(location, lhs, None, locals);
                let m = self.model;
                if lty.static_ty == StaticType::Type(m.expect("/mob")) {
                    self.facts.impure.push(("LShift onto mob".into(), location));
                } else if lty.static_ty == StaticType::Type(m.expect("/savefile")) {
                    self.facts.impure.push(("LShift onto savefile".into(), location));
                } else if lty.static_ty == StaticType::Type(m.expect("/list")) {
                    self.facts.impure.push(("LShift onto list".into(), location));
                }
                let rty = self.visit_expression(location, rhs, None, locals);
                self.visit_binary(lty, rty, "<<")
            }
            Shape::Binary { op: "in", lhs, rhs } => {
                match self.reader.shape(lhs) {
                    Shape::Base(b) => {
                        for (f, _) in &b.follows {
                            if let Follow::Unary(unary) = f {
                                self.register(
                                    error(self.place(location), format!("ambiguous `{}` on left side of an `in`", unary.name()))
                                        .set_severity(Severity::Warning)
                                        .with_errortype("ambiguous_in_lhs")
                                        .with_note(self.place(location), format!("add parentheses to fix: `{}`", unary.around("(a in b)")))
                                        .with_note(self.place(location), format!("add parentheses to disambiguate: `({}) in b`", unary.around("a"))),
                                );
                                break;
                            }
                        }
                    }
                    Shape::Binary { op, .. } | Shape::Assign { op, .. } => {
                        self.register(
                            error(self.place(location), format!("ambiguous `{op}` on left side of an `in`"))
                                .set_severity(Severity::Warning)
                                .with_errortype("ambiguous_in_lhs")
                                .with_note(self.place(location), format!("add parentheses to fix: `a {op} (b in c)`"))
                                .with_note(self.place(location), format!("add parentheses to disambiguate: `(a {op} b) in c`")),
                        );
                    }
                    Shape::Ternary { .. } => {
                        self.register(
                            error(self.place(location), "ambiguous ternary on left side of an `in`")
                                .set_severity(Severity::Warning)
                                .with_errortype("ambiguous_in_lhs")
                                .with_note(self.place(location), "add parentheses to fix: `a ? b : (c in d)`")
                                .with_note(self.place(location), "add parentheses to disambiguate: `(a ? b : c) in d`"),
                        );
                    }
                    Shape::Unread => {}
                }
                let lty = self.visit_expression(location, lhs, None, locals);
                let rty = self.visit_expression(location, rhs, None, locals);
                self.visit_binary(lty, rty, "in")
            }
            Shape::Binary { op: "||", lhs, rhs } => {
                let lty = self.visit_expression(location, lhs, type_hint, locals);
                let rty = self.visit_expression(location, rhs, type_hint, locals);
                self.visit_binary(lty, rty, "||")
            }
            Shape::Binary { op, lhs, rhs } => {
                let lty = self.visit_expression(location, lhs, None, locals);
                let rty = self.visit_expression(location, rhs, None, locals);
                match op {
                    "&" => self.check_negated_bitwise(lhs, location, "&", "&&"),
                    "|" => self.check_negated_bitwise(lhs, location, "|", "||"),
                    "^" => self.check_negated_bitwise(lhs, location, "^", "!="),
                    _ => {}
                }
                self.visit_binary(lty, rty, op)
            }
            Shape::Assign { op, lhs, rhs } => self.visit_assign(location, op, lhs, rhs, type_hint, locals),
            Shape::Ternary { cond, if_, else_ } => {
                self.visit_expression(location, cond, None, locals);
                let ty = self.visit_expression(location, if_, type_hint, locals);
                self.visit_expression(location, else_, type_hint, locals);
                ty
            }
            Shape::Unread => Analysis::empty(),
        }
    }

    /// `term` at `location`; `at` is its offset (an interpolated string's parts are placed from it).
    fn visit_term(&mut self, location: Where, at: usize, term: &Term<'_>, type_hint: Option<TypeId>, locals: &mut Locals) -> Analysis {
        let m = self.model;
        match term {
            Term::Null => Analysis::null(),
            Term::Int(n) => Analysis::from_value(m, Value::Float(*n as f32)),
            Term::Float(n) => Analysis::from_value(m, Value::Float(*n)),
            Term::Str(s) => Analysis::from_value(m, Value::Str(s.clone())),
            Term::Resource(s) => Analysis::from_value(m, Value::Resource(s.clone())),
            Term::As => assumption_set![Assumption::IsNum(true)].into(),
            Term::Ident(name) => {
                if let Some(var) = locals.get(name.as_str()) {
                    var.analysis.clone().with_fix_hint(var.location, "add additional type info here")
                } else if name == "type" {
                    Analysis {
                        static_ty: StaticType::None,
                        aset: assumption_set![Assumption::IsPath(true, self.ty)],
                        value: Some(Value::prefab_of(m, self.ty)),
                        fix_hint: None,
                        is_impure: None,
                    }
                } else if let Some(decl) = m.get_var_declaration(self.ty, name) {
                    let (path, decl_location) = (decl.type_path.clone(), decl.location);
                    let mut ana = self.static_type(location, &path).with_fix_hint(decl_location, "add additional type info here");
                    ana.is_impure = Some(true);
                    ana
                } else {
                    self.register(error(self.place(location), format!("undefined var: {name:?}")));
                    Analysis::empty()
                }
            }
            Term::Group(e) => self.visit_expression(location, e, type_hint, locals),
            Term::Prefab { path, .. } => {
                let pieces = type_path(path);
                match m.navigate_path(self.ty, &pieces) {
                    Some(ty) => Analysis {
                        static_ty: StaticType::None,
                        aset: assumption_set![Assumption::IsPath(true, ty)],
                        value: Some(Value::prefab_of(m, ty)),
                        fix_hint: None,
                        is_impure: None,
                    },
                    None => {
                        self.register(error(self.place(location), format!("failed to resolve path {}", format_type_path(&pieces))));
                        Analysis::empty()
                    }
                }
            }
            Term::Interp { parts, .. } => {
                for (part, _) in parts {
                    if let Some(Part { expr: Some(e), base }) = part {
                        // The part's offsets are relative to where it starts in the literal.
                        let saved = self.reader.shift;
                        self.reader.shift = saved + at + base;
                        self.visit_expression(location, e, None, locals);
                        self.reader.shift = saved;
                    }
                }
                assumption_set![Assumption::IsText(true)].into()
            }
            Term::Call { name, args } => {
                if self.inside_newcontext == 0 && matches!(*name, "sleep" | "alert" | "shell" | "winexists" | "winget") {
                    self.facts.sleeps.push((name.to_string(), location));
                }
                self.check_type_sleepers(self.ty, location, name);
                let src = self.ty;
                if let Some(proc) = m.get_proc(self.ty, name) {
                    self.visit_call(location, src, proc, args, false, locals)
                } else if *name == "__PROC__" {
                    self.visit_call(location, src, self.proc, args, false, locals)
                } else if *name == "SpacemanDMM_unlint" {
                    Analysis::empty()
                } else if *name == "SpacemanDMM_debug" {
                    dq_hostio::out(false, format_args!("SpacemanDMM_debug:"), true);
                    for arg in args {
                        let a = self.visit_expression(location, arg, None, locals);
                        dq_hostio::out(false, format_args!("    {:?}", a.static_ty.debug(m)), true);
                    }
                    Analysis::empty()
                } else {
                    self.register(error(self.place(location), format!("undefined proc: {:?} on {}", name, m.ty(self.ty).pretty_path())));
                    Analysis::empty()
                }
            }
            Term::SelfCall(args) => {
                let src = self.ty;
                let proc = self.proc;
                self.visit_call(location, src, proc, args, true, locals)
            }
            Term::ParentCall(args) => {
                self.calls_parent = true;
                if let Some(proc) = m.parent_proc(self.proc) {
                    let src = self.ty;
                    self.visit_call(location, src, proc, args, true, locals)
                } else {
                    self.register(error(self.place(location), format!("proc has no parent: {}", m.proc_display(self.proc))).with_errortype("proc_has_no_parent"));
                    Analysis::empty()
                }
            }
            Term::NewImplicit(args) => match type_hint {
                Some(hint) => {
                    let empty = Vec::new();
                    self.visit_new(location, hint, args.as_ref().unwrap_or(&empty), locals)
                }
                None => {
                    self.register(error(self.place(location), "no type hint available on implicit new()").with_errortype("no_typehint_implicit_new"));
                    Analysis::empty()
                }
            },
            Term::NewPrefab { path, args } => {
                let pieces = type_path(path);
                match m.navigate_path(self.ty, &pieces) {
                    Some(ty) => {
                        let empty = Vec::new();
                        self.visit_new(location, ty, args.as_ref().unwrap_or(&empty), locals)
                    }
                    None => {
                        self.register(error(self.place(location), format!("failed to resolve path {}", format_type_path(&pieces))));
                        Analysis::empty()
                    }
                }
            }
            Term::NewMiniExpr => Analysis::empty(),
            Term::List(args) => {
                self.visit_arguments(location, args, locals);
                Analysis::from_static_type(m.expect("/list"))
            }
            Term::Input { args, input_type, in_list } => {
                if self.inside_newcontext == 0 {
                    self.facts.sleeps.push(("input".into(), location));
                }
                self.visit_arguments(location, args, locals);
                if let Some(e) = in_list {
                    self.visit_expression(location, e, None, locals);
                }
                let input_type = input_type.unwrap_or_default();
                let without_null = input_type.0 & !InputType::NULL;
                if input_type.0 & InputType::ANYTHING != 0 {
                    Analysis::empty()
                } else if without_null == InputType::MOB {
                    assumption_set![Assumption::IsType(true, m.expect("/mob"))].into()
                } else if without_null == InputType::OBJ {
                    assumption_set![Assumption::IsType(true, m.expect("/obj"))].into()
                } else if without_null == InputType::AREA {
                    assumption_set![Assumption::IsType(true, m.expect("/area"))].into()
                } else if without_null == InputType::TURF {
                    assumption_set![Assumption::IsType(true, m.expect("/turf"))].into()
                } else if [InputType::TEXT, InputType::MESSAGE, InputType::KEY, InputType::PASSWORD, InputType::COLOR, 0].contains(&without_null) {
                    assumption_set![Assumption::IsText(true)].into()
                } else if without_null == InputType::NUM {
                    assumption_set![Assumption::IsNum(true)].into()
                } else if without_null == InputType::ICON {
                    assumption_set![Assumption::IsType(true, m.expect("/icon"))].into()
                } else if without_null == InputType::SOUND {
                    assumption_set![Assumption::IsType(true, m.expect("/sound"))].into()
                } else {
                    Analysis::empty()
                }
            }
            Term::Locate { args, in_list } => {
                self.visit_arguments(location, args, locals);
                if let Some(e) = in_list {
                    self.visit_expression(location, e, None, locals);
                }
                if args.len() == 3 {
                    assumption_set![Assumption::IsType(true, m.expect("/turf"))].into()
                } else {
                    Analysis::empty()
                }
            }
            Term::Pick(choices) => {
                for (weight, choice) in choices {
                    if let Some(w) = weight {
                        self.visit_expression(location, w, None, locals);
                    }
                    self.visit_expression(location, choice, None, locals);
                }
                Analysis::empty()
            }
            Term::DynamicCall(a, b) => {
                self.visit_arguments(location, a, locals);
                self.visit_arguments(location, b, locals);
                Analysis::empty()
            }
            Term::ExternalCall { library, function, args } => {
                if let Some(l) = library {
                    self.visit_expression(location, l, None, locals);
                }
                if let Some(f) = function {
                    self.visit_expression(location, f, None, locals);
                }
                self.visit_arguments(location, args, locals);
                Analysis::empty()
            }
            Term::TypeConst => Analysis {
                static_ty: StaticType::None,
                aset: assumption_set![Assumption::IsPath(true, self.ty)],
                value: Some(Value::prefab_of(m, self.ty)),
                fix_hint: None,
                is_impure: None,
            },
            Term::Proc => Analysis::empty(),
            Term::ImpliedType => match type_hint {
                None => Analysis::empty(),
                Some(implied) => Analysis {
                    static_ty: StaticType::None,
                    aset: assumption_set![Assumption::IsPath(true, self.ty)],
                    value: Some(Value::prefab_of(m, implied)),
                    fix_hint: None,
                    is_impure: None,
                },
            },
            Term::Unread => Analysis::empty(),
        }
    }

    fn visit_new(&mut self, location: Where, ty: TypeId, args: &[&Expr], locals: &mut Locals) -> Analysis {
        let m = self.model;
        if let Some(new_proc) = m.get_proc(ty, "New") {
            self.visit_call(location, ty, new_proc, args, true, locals);
        } else if !["/list", "/alist", "/vector", "/pixloc"].contains(&m.ty(ty).path.as_str()) {
            self.register(error(self.place(location), format!("couldn't find {}/proc/New", m.ty(ty).path)));
        }
        assumption_set![Assumption::IsType(true, ty)].into()
    }

    fn check_type_sleepers(&mut self, ty: TypeId, location: Where, name: &str) {
        match self.model.ty(ty).path.as_str() {
            "/client" if self.inside_newcontext == 0 && matches!(name, "SoundQuery" | "MeasureText") => {
                self.facts.sleeps.push((format!("client.{name}"), location));
            }
            "/world" if self.inside_newcontext == 0 && matches!(name, "Import" | "Export") => {
                self.facts.sleeps.push((format!("world.{name}"), location));
            }
            _ => {}
        }
    }

    fn visit_follow(&mut self, location: Where, lhs: Analysis, rhs: &Follow<'_>, locals: &mut Locals) -> Analysis {
        let m = self.model;
        match rhs {
            Follow::Unary(op) => self.visit_unary(lhs, *op, location, locals),
            Follow::Field(access, _) if access.is_colon() => Analysis::empty(),
            Follow::Call(access, _, args) if access.is_colon() => {
                for arg in args {
                    let value = self.kwarg_value(arg).map_or(*arg, |(_, v)| v);
                    self.visit_expression(location, value, None, locals);
                }
                Analysis::empty()
            }
            Follow::Index(e) => {
                self.visit_expression(location, e, None, locals);
                match lhs.static_ty {
                    StaticType::List { keys, .. } => {
                        let mut res = Analysis::from(*keys);
                        if let Some((loc, _)) = lhs.fix_hint {
                            res.fix_hint = Some((loc, super::analysis::Hint::Text("add a type annotation after /list here".to_owned())));
                        }
                        res
                    }
                    _ => lhs,
                }
            }
            Follow::Field(_, name) => {
                if let StaticType::Proc = lhs.static_ty {
                    if !matches!(*name, "type" | "name" | "desc" | "category" | "invisibility") {
                        self.register(error(self.place(location), format!("undefined field: {name:?} on procpath")));
                    }
                    Analysis::empty()
                } else if let Some(ty) = lhs.static_ty.basic_type() {
                    if m.ty(ty).path == "/callee" && *name == "proc" {
                        Analysis::from(StaticType::Proc)
                    } else if let Some(decl) = m.get_var_declaration(ty, name) {
                        let (path, decl_location, flags) = (decl.type_path.clone(), decl.location, decl.flags);
                        if ty != self.ty && flags.is_private() {
                            self.register(
                                error(self.place(location), format!("field {name:?} on {} is declared as private", m.ty(ty).pretty_path()))
                                    .with_errortype("private_var")
                                    .set_severity(Severity::Warning)
                                    .with_note(self.place(decl_location), "definition is here"),
                            );
                        } else if !m.is_subtype_of(self.ty, ty) && flags.is_protected() {
                            self.register(
                                error(self.place(location), format!("field {name:?} on {} is declared as protected", m.ty(ty).pretty_path()))
                                    .with_errortype("protected_var")
                                    .set_severity(Severity::Warning)
                                    .with_note(self.place(decl_location), "definition is here"),
                            );
                        }
                        self.static_type(location, &path).with_fix_hint(decl_location, "add additional type info here")
                    } else {
                        self.register(error(self.place(location), format!("undefined field: {name:?} on {}", m.ty(ty).pretty_path())));
                        Analysis::empty()
                    }
                } else {
                    let mut e = error(self.place(location), format!("field access requires static type: {name:?}"))
                        .set_severity(Severity::Warning)
                        .with_errortype("field_access_static_type");
                    if let Some((loc, desc)) = lhs.fix_hint.clone() {
                        let loc = self.place(loc);
                        if !loc.is_builtins() {
                            e.add_note(loc, desc.text(m));
                        }
                    }
                    self.register(e);
                    Analysis::empty()
                }
            }
            Follow::StaticField(name) => {
                let real_type = match lhs.static_ty.basic_type() {
                    Some(t) => t,
                    None => match self.static_typepath(location, &lhs, name, "static access") {
                        Some(t) => t,
                        None => return Analysis::empty(),
                    },
                };
                let Some(decl) = m.get_var_declaration(real_type, name) else {
                    self.register(error(self.place(location), format!("undefined field: {name:?} on {}", m.ty(real_type).pretty_path())));
                    return Analysis::empty();
                };
                let (path, decl_location) = (decl.type_path.clone(), decl.location);
                self.static_type(location, &path).with_fix_hint(decl_location, "add additional type info here")
            }
            Follow::Call(_, name, args) => {
                if let Some(ty) = lhs.static_ty.basic_type() {
                    self.check_type_sleepers(ty, location, name);
                    if let Some(proc) = m.get_proc(ty, name) {
                        let d = &self.shared.directives;
                        if let Some((privateproc, true, decl_location)) = d.private.get_self_or_parent(m, proc) {
                            if ty != privateproc.ty {
                                self.register(
                                    error(self.place(location), format!("{} attempting to call private proc {}, types do not match", m.proc_display(self.proc), m.proc_display(privateproc)))
                                        .with_errortype("private_proc")
                                        .with_note(decl_location, "prohibited by this private_proc annotation"),
                                );
                                return Analysis::empty();
                            }
                        }
                        if let Some((protectedproc, true, decl_location)) = d.protected.get_self_or_parent(m, proc) {
                            if !m.is_subtype_of(self.ty, protectedproc.ty) {
                                self.register(
                                    error(self.place(location), format!("{} attempting to call protected proc {}", m.proc_display(self.proc), m.proc_display(protectedproc)))
                                        .with_errortype("protected_proc")
                                        .with_note(decl_location, "prohibited by this protected_proc annotation"),
                                );
                            }
                        }
                        self.visit_call(location, ty, proc, args, false, locals)
                    } else {
                        self.register(error(self.place(location), format!("undefined proc: {name:?} on {}", m.ty(ty).pretty_path())));
                        Analysis::empty()
                    }
                } else {
                    let mut e = error(self.place(location), format!("proc call requires static type: {name:?}"))
                        .set_severity(Severity::Warning)
                        .with_errortype("proc_call_static_type");
                    if let Some((loc, desc)) = lhs.fix_hint.clone() {
                        let loc = self.place(loc);
                        if !loc.is_builtins() {
                            e.add_note(loc, desc.text(m));
                        }
                    }
                    self.register(e);
                    Analysis::empty()
                }
            }
            Follow::ProcReference(name) => {
                let real_type = match lhs.static_ty.basic_type() {
                    Some(t) => t,
                    None => match self.static_typepath(location, &lhs, name, "static proc reference") {
                        Some(t) => t,
                        None => return Analysis::empty(),
                    },
                };
                let Some(decl) = m.get_proc(real_type, name) else {
                    self.register(error(self.place(location), format!("undefined proc: {name:?} on {}", m.ty(real_type).pretty_path())));
                    return Analysis::empty();
                };
                let mut path: Vec<String> = m.ty(real_type).path.split('/').filter(|e| !e.is_empty()).map(str::to_owned).collect();
                if let Some(declaration) = m.get_declaration(decl) {
                    path.push(declaration.kind.name().to_owned());
                }
                path.push(m.proc_name(decl).to_owned());
                Analysis {
                    static_ty: StaticType::None,
                    aset: assumption_set![Assumption::IsPath(true, real_type)],
                    value: Some(Value::Prefab(path)),
                    fix_hint: None,
                    is_impure: None,
                }
            }
        }
    }

    /// The type a `X::y` reads when `X` has no static type: its value must be a type path that names a type.
    fn static_typepath(&mut self, location: Where, lhs: &Analysis, name: &str, what: &str) -> Option<TypeId> {
        let Some(value) = lhs.value.as_ref() else {
            self.register(error(self.place(location), format!("no typepath found for: {name:?}")));
            return None;
        };
        let Value::Prefab(path) = value else {
            self.register(error(self.place(location), format!("{what} requires a static typepath, {} found instead", value.display())));
            return None;
        };
        let typepath: String = path.iter().map(|p| format!("/{p}")).collect();
        match self.model.find(&typepath) {
            Some(t) => Some(t),
            None => {
                self.register(error(self.place(location), format!("{what} requires an existing typepath, {typepath} found instead")));
                None
            }
        }
    }

    fn check_operator_overload(&mut self, rhs: Analysis, location: Where, operator: &str, locals: &mut Locals) -> Analysis {
        let m = self.model;
        if rhs.is_impure == Some(true) {
            self.facts.impure.push((format!("{operator} done on non-local var"), location));
        }
        let typeerror = match rhs.static_ty {
            StaticType::None | StaticType::Proc => return Analysis::empty(),
            StaticType::Type(t) => {
                if let Some(proc) = m.get_proc(t, operator) {
                    return self.visit_call(location, t, proc, &[], true, locals);
                }
                m.ty(t).pretty_path().to_owned()
            }
            StaticType::List { .. } => "list".to_owned(),
        };
        self.register(error(self.place(location), format!("Attempting {operator} on a {typeerror} which does not overload {operator}")));
        Analysis::empty()
    }

    fn visit_unary(&mut self, rhs: Analysis, op: UnaryOp, location: Where, locals: &mut Locals) -> Analysis {
        match op {
            UnaryOp::Not => Analysis::from(assumption_set![Assumption::IsNum(true)]),
            UnaryOp::PreIncr | UnaryOp::PostIncr => self.check_operator_overload(rhs, location, "operator++", locals),
            UnaryOp::PreDecr | UnaryOp::PostDecr => self.check_operator_overload(rhs, location, "operator--", locals),
            _ => Analysis::empty(),
        }
    }

    fn check_negated_bitwise(&mut self, lhs: &Expr, location: Where, bit_op: &str, bool_op: &str) {
        let Shape::Base(b) = self.reader.shape(lhs) else { return };
        if b.follows.iter().any(|(f, _)| matches!(f, Follow::Unary(UnaryOp::Not))) {
            self.register(
                error(self.place(location), format!("Ambiguous `!` on left side of bitwise `{bit_op}` operator"))
                    .with_errortype("ambiguous_not_bitwise")
                    .set_severity(Severity::Warning)
                    .with_note(self.place(location), format!("Did you mean `!(x {bit_op} y)`?"))
                    .with_note(self.place(location), format!("Did you mean `!x {bool_op} y`?"))
                    .with_note(self.place(location), format!("Did you mean `~x {bit_op} y`?")),
            );
        }
    }

    fn visit_binary(&mut self, lhs: Analysis, _rhs: Analysis, op: &str) -> Analysis {
        if lhs.static_ty.is_list(self.model) && matches!(op, "+" | "-" | "|" | "&" | "^") {
            return lhs.static_ty.into();
        }
        Analysis::empty()
    }

    /// A `name = value` argument whose key is a name or a string: (key, value).
    fn kwarg_value<'e>(&mut self, arg: &'e Expr) -> Option<(String, &'e Expr)> {
        let Shape::Assign { op: "=", lhs, rhs } = self.reader.shape(arg) else { return None };
        match self.as_term(lhs) {
            Some(Term::Ident(name)) => Some((name, rhs)),
            Some(Term::Str(name)) => Some((name, rhs)),
            _ => None,
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn check_filter_flag(&mut self, e: &Expr, can_be_zero: bool, location: Where, typevalue: &str, valid_flags: &[&str], field: &str, exclusive: bool) {
        let note = format!("See: http://www.byond.com/docs/ref/#/{{notes}}/filters/{typevalue} for the permitted arguments");
        match self.reader.shape(e) {
            Shape::Binary { op: "|", lhs, rhs } => {
                if exclusive {
                    self.register(
                        error(self.place(location), format!("filter(type=\"{typevalue}\") '{field}' parameter must have one value, found bitwise OR")).with_note(self.place(location), note),
                    );
                    return;
                }
                self.check_filter_flag(lhs, can_be_zero, location, typevalue, valid_flags, field, exclusive);
                self.check_filter_flag(rhs, can_be_zero, location, typevalue, valid_flags, field, exclusive);
            }
            Shape::Base(b) => {
                if !b.follows.is_empty() {
                    self.register(error(self.place(location), "filter() flag fields cannot have unary ops or field accesses"));
                    return;
                }
                match &b.term {
                    Term::Ident(flag) => {
                        if !valid_flags.iter().any(|x| x == flag) {
                            self.register(
                                error(self.place(location), format!("filter(type=\"{typevalue}\") called with invalid '{field}' flag '{flag}'")).with_note(self.place(location), note),
                            );
                        }
                    }
                    Term::Int(0) if can_be_zero => {}
                    Term::Int(n) if {
                        let values: Vec<i32> = valid_flags.iter().filter_map(|f| lookup(FILTER_FLAG_VALUES, f).copied()).collect();
                        values.contains(n) || (!exclusive && *n != 0 && *n & !values.iter().fold(0, |a, v| a | v) == 0)
                    } => {}
                    other => {
                        self.register(
                            error(self.place(location), format!("filter(type=\"{typevalue}\") called with invalid '{field}' value '{}'", other.debug()))
                                .with_note(self.place(location), note),
                        );
                    }
                }
            }
            _ => {
                self.register(
                    error(self.place(location), format!("filter(type=\"{typevalue}\"), extremely invalid value passed to '{field}' field")).with_note(self.place(location), note),
                );
            }
        }
    }

    fn visit_call(&mut self, location: Where, src: TypeId, proc: ProcId, args: &[&Expr], is_exact: bool, locals: &mut Locals) -> Analysis {
        let m = self.model;
        self.facts.calls.push((proc, location, self.inside_newcontext != 0));
        if let Some((privateproc, true, decl_location)) = self.shared.directives.private.get_self_or_parent(m, proc) {
            if self.ty != privateproc.ty {
                self.register(
                    error(self.place(location), format!("{} attempting to call private proc {}, types do not match", m.proc_display(self.proc), m.proc_display(privateproc)))
                        .with_errortype("private_proc")
                        .with_note(decl_location, "prohibited by this private_proc annotation"),
                );
            }
        }
        let mut any_kwargs_yet = false;
        let mut param_name_map: HashMap<String, Analysis> = HashMap::new();
        let mut param_expr_map: HashMap<String, &Expr> = HashMap::new();
        let mut param_idx_map: HashMap<usize, Analysis> = HashMap::new();
        let mut param_idx = 0;
        let mut arglist_used = false;
        let params = &m.value(proc).parameters;
        for &arg in args {
            let mut argument_value = arg;
            let mut this_kwarg = None;
            match self.kwarg_value(arg) {
                Some((name, value)) => {
                    any_kwargs_yet = true;
                    argument_value = value;
                    if !params.iter().any(|p| p.name == name) {
                        let mut e = error(self.place(location), format!("bad keyword argument {name:?} to {}", m.proc_display(proc)));
                        m.recurse_children(proc, &mut |child| {
                            if child.ty == proc.ty {
                                return;
                            }
                            if m.value(child).parameters.iter().any(|p| p.name == name) {
                                e.add_note(self.reader.site.place(m.value(child).location), format!("an override has this parameter: {}", m.proc_display(child)));
                            }
                        });
                        self.register(e);
                    } else if !is_exact {
                        self.facts.kwargs.push((format!("{}/proc/{}", m.ty(src).pretty_path(), m.proc_name(proc)), self.place(m.value(proc).location), name.clone(), location));
                    }
                    this_kwarg = Some(name);
                }
                None => {
                    if let Some(Term::Call { name: "arglist", .. }) = self.as_term(arg) {
                        if param_name_map.is_empty() && param_idx == 0 {
                            arglist_used = true;
                        }
                    }
                }
            }
            if any_kwargs_yet && this_kwarg.is_none() && !(m.ty(proc.ty).is_root() && m.proc_name(proc) == "animate") {
                self.register(error(self.place(location), format!("proc called with non-kwargs after kwargs: {}()", m.proc_name(proc))));
            }
            let analysis = self.visit_expression(location, argument_value, None, locals);
            match this_kwarg {
                Some(kw) => {
                    param_name_map.insert(kw.clone(), analysis);
                    param_expr_map.insert(kw, argument_value);
                }
                None => {
                    param_idx_map.insert(param_idx, analysis);
                    param_idx += 1;
                }
            }
        }

        let is_global = m.ty(proc.ty).is_root();
        if is_global && m.proc_name(proc) == "astype" {
            if let Some(Analysis { value: Some(Value::Prefab(path)), .. }) = param_idx_map.get(&1) {
                let type_val: String = path.iter().map(|x| format!("/{x}")).collect();
                if let Some(t) = m.find(&type_val) {
                    return Analysis::from_static_type(t);
                }
            }
            if let Some(type_val) = param_idx_map.get(&0) {
                return Analysis::from(type_val.static_ty.clone());
            }
        }

        if is_global && m.proc_name(proc) == "filter" {
            let Some(typename) = param_name_map.get("type") else {
                if !arglist_used {
                    self.register(error(self.place(location), "filter() called without mandatory keyword parameter 'type'"));
                }
                return Analysis::empty();
            };
            let Some(Value::Str(typevalue)) = &typename.value else {
                let shown = match &typename.value {
                    Some(v) => format!("Some({})", v.debug()),
                    None => "None".to_owned(),
                };
                self.register(error(self.place(location), format!("filter() called with non-string type keyword parameter value '{shown}'")));
                return Analysis::empty();
            };
            let typevalue = typevalue.clone();
            let Some(arglist) = lookup(VALID_FILTER_TYPES, &typevalue) else {
                self.register(error(self.place(location), format!("filter() called with invalid type keyword parameter value '{typevalue}'")));
                return Analysis::empty();
            };
            // In name order (SpacemanDMM walks its hash map, whose order is not fixed).
            let mut names: Vec<&String> = param_name_map.keys().collect();
            names.sort();
            for arg in names {
                if arg != "type" && arg != "name" && !arglist.contains(&arg.as_str()) {
                    let note = format!("See: http://www.byond.com/docs/ref/#/{{notes}}/filters/{typevalue} for the permitted arguments");
                    self.register(
                        error(self.place(location), format!("filter(type=\"{typevalue}\") called with invalid keyword parameter '{arg}'")).with_note(self.place(location), note),
                    );
                }
            }
            if let Some((field, exclusive, can_be_zero, valid_flags)) = lookup(VALID_FILTER_FLAGS, &typevalue) {
                if let Some(flags) = param_expr_map.get(*field) {
                    let flags = *flags;
                    self.check_filter_flag(flags, *can_be_zero, location, &typevalue, valid_flags, field, *exclusive);
                }
            }
        }

        if is_global && m.is_builtin(proc) {
            Analysis::from(global_builtin_returntype(m, m.proc_name(proc)))
        } else if let Some(return_type) = self.shared.return_type.get(&proc) {
            let ec = TypeExprContext { model: m, param_name_map, param_idx_map };
            match return_type.evaluate(self.place(location), &ec) {
                Ok(st) => {
                    let hint = format!("return type evaluated to {}", st.debug(m));
                    Analysis::from(st).with_fix_hint(location, hint)
                }
                Err(err) => {
                    self.register(err.with_component(dm::Component::DreamChecker));
                    Analysis::empty()
                }
            }
        } else {
            Analysis::empty().with_fix_hint_for(m.value(proc).location, proc)
        }
    }

    fn visit_arguments(&mut self, location: Where, args: &[&Expr], locals: &mut Locals) {
        for &arg in args {
            let value = self.kwarg_value(arg).map_or(arg, |(_, v)| v);
            self.visit_expression(location, value, None, locals);
        }
    }
}

fn global_builtin_returntype(m: &Model, name: &str) -> StaticType {
    match name {
        "argslist" | "flist" | "icon_states" | "splittext" | "typesof" => StaticType::plain_list(m),
        "block" => StaticType::list_of_type(m, "/turf"),
        "bounds" | "obounds" | "orange" | "oview" | "range" | "view" => StaticType::list_of_type(m, "/atom"),
        "get_step" => StaticType::Type(m.expect("/turf")),
        "hearers" | "ohearers" | "oviewers" | "viewers" => StaticType::list_of_type(m, "/mob"),
        "icon" => StaticType::Type(m.expect("/icon")),
        "matrix" => StaticType::Type(m.expect("/matrix")),
        "regex" => StaticType::Type(m.expect("/regex")),
        _ => StaticType::None,
    }
}

/// A var's declared type: flags at the front skipped, `list` keys recursed, the rest a type path.
pub fn static_type(m: &Model, location: Location, mut of: &[String]) -> Result<StaticType, DMError> {
    while !of.is_empty() && ["static", "global", "const", "tmp", "final", "SpacemanDMM_final", "SpacemanDMM_private", "SpacemanDMM_protected"].contains(&of[0].as_str()) {
        of = &of[1..];
    }
    if of.is_empty() {
        Ok(StaticType::None)
    } else if of[0] == "list" {
        let keys = static_type(m, location, &of[1..])?;
        Ok(StaticType::List { list: m.expect("/list"), keys: Box::new(keys) })
    } else if let Some(ty) = m.type_by_path(of) {
        Ok(StaticType::Type(ty))
    } else {
        Err(error(location, format!("undefined type: {}", of.iter().map(|p| format!("/{p}")).collect::<String>())))
    }
}

/// `/obj/item`, `.foo`, `/datum:x` as (operator, name) pieces.
pub fn type_path(path: &str) -> Vec<(char, String)> {
    let mut out = Vec::new();
    let mut op = None;
    let mut name = String::new();
    for ch in path.chars() {
        match ch {
            '/' | '.' | ':' => {
                if let (Some(o), false) = (op, name.is_empty()) {
                    out.push((o, std::mem::take(&mut name)));
                }
                name.clear();
                op = Some(ch);
            }
            _ => name.push(ch),
        }
    }
    if let (Some(o), false) = (op, name.is_empty()) {
        out.push((o, name));
    }
    out
}

pub fn format_type_path(pieces: &[(char, String)]) -> String {
    pieces.iter().map(|(op, name)| format!("{op}{name}")).collect()
}
