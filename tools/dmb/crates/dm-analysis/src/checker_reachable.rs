//! Pinned checker *policy* block traversal, not runtime/compiler reachability.
//!
//! Adapted from SpacemanDMM dreamchecker ControlFlow/visit_block/visit_statement
//! and dreammaker Expression::is_truthy at commit
//! 0290db5c752fa292f9824521515b603a2afd11dc (GPL-3.0). In particular throws,
//! labels, fuzzy breaks and ordinary loop returns intentionally retain the
//! reference's surprising behavior. No second parser/model is constructed.
//!
//! Unresolved contracts are explicit errors: CR-altered interpolation boundaries
//! and some range-step term/follow distinctions still need primary origins.
//! Constructor terms use the primary parser's bounded target/argument grammar;
//! ordinary follows are not folded back into that term. Checker-prefix settings
//! remain shared native source metadata; Compile rejects them separately.
//! Macro provenance is
//! borrowed from the source mapping; this module never reverses expansion.

use crate::checker_evaluated_observer::{EvaluatedObserver, ScopeKind};
use crate::checks::BodyView;
use dm_syntax::{
    numeric_form::{numeric_form, NumericForm},
    Expr, ExprKind, ForControl, Span, Statement, StatementKind,
};
use dm_tree::frontend::{ArchivedBody, StatementBody};

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct ControlFlow {
    pub returns: bool,
    pub continues: bool,
    pub breaks: bool,
    pub fuzzy: bool,
}
impl ControlFlow {
    fn all_true() -> Self {
        Self {
            returns: true,
            continues: true,
            breaks: true,
            fuzzy: false,
        }
    }
    fn terminates(self) -> bool {
        !self.fuzzy && (self.returns || self.continues || self.breaks)
    }
    fn terminates_loop(self) -> bool {
        !self.fuzzy && (self.returns || self.breaks)
    }
    fn no_else(&mut self) {
        self.returns = false;
        self.continues = false;
        self.breaks = false;
    }
    fn merge(&mut self, other: Self) {
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
    fn merge_false(&mut self, other: Self) {
        self.returns &= other.returns;
        self.continues &= other.continues;
        self.breaks &= other.breaks;
        self.fuzzy |= other.fuzzy;
    }
    fn finalize(&mut self) {
        if self.returns || self.breaks || self.continues {
            self.fuzzy = false;
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ConditionKind {
    If,
    ForTest,
    Switch,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum UnreachableKind {
    Sibling,
    IfArm,
    ElseArm,
}
#[derive(Clone, Copy, Debug)]
pub enum Event<'a> {
    DoWhileUnreachable{at:Span,condition:Span},
    Unreachable {
        kind: UnreachableKind,
        at: Span,
    },
    LoopCondition {
        expression: &'a Expr,
        at: Span,
    },
    IfDeterminate {
        expression: &'a Expr,
        at: Span,
        value: bool,
    },
    ControlCondition {
        kind: ConditionKind,
        expression: &'a Expr,
        at: Span,
    },
    SettingOutsidePrefix {
        statement: &'a Statement,
        attribute: &'a str,
    },
}
#[derive(Debug)]
pub struct Walk<'a> {
    pub flow: ControlFlow,
    pub events: Vec<Event<'a>>,
}

pub fn analyze<'a>(view: &'a BodyView<'_>) -> Result<Walk<'a>, String> {
    walk(view.syntax())
}
pub fn archived<'a>(body: &'a ArchivedBody<'_>) -> Result<Walk<'a>, String> {
    walk(body.statement_body())
}
/// The SAME pinned reachability walk issues evaluated roots. No parallel CFG
/// or procedure parser is created. Observers must stage output until success.
pub fn analyze_with_observer<'a>(
    view: &BodyView<'a>,
    observer: &mut impl EvaluatedObserver<'a>,
) -> Result<Walk<'a>, String> {
    let syntax = view.syntax();
    if !syntax.syntax_complete() {
        return Err("checker traversal has incomplete native syntax".into());
    }
    let mut walker = Walker {
        syntax,
        events: Vec::new(),
        observer: Some(observer),
    };
    let flow = walker.block(&syntax.parsed().statements, true)?;
    Ok(Walk {
        flow,
        events: walker.events,
    })
}
pub fn archived_with_observer<'a>(
    body: &'a ArchivedBody<'_>,
    observer: &mut impl EvaluatedObserver<'a>,
) -> Result<Walk<'a>, String> {archived_with_observer_using(body,observer)}
pub(crate) fn archived_with_observer_using<'a,E:From<String>+for<'e>From<&'e str>>(
    body: &'a ArchivedBody<'_>,
    observer: &mut impl EvaluatedObserver<'a,E>,
) -> Result<Walk<'a>, E> {archived_with_observer_mode(body,observer,false)}
/// Exact source diagnostic entry over already-prepared original literal parts;
/// runtime/compatibility callers retain the strict readiness wrapper above.
pub(crate) fn archived_original_syntax_with_observer_using<'a,E:From<String>+for<'e>From<&'e str>>(body:&'a ArchivedBody<'_>,observer:&mut impl EvaluatedObserver<'a,E>)->Result<Walk<'a>,E>{archived_with_observer_mode(body,observer,true)}
fn archived_with_observer_mode<'a,E:From<String>+for<'e>From<&'e str>>(body:&'a ArchivedBody<'_>,observer:&mut impl EvaluatedObserver<'a,E>,original:bool)->Result<Walk<'a>,E>{
    let syntax = body.statement_body();
    if !(if original{syntax.original_literal_syntax_complete()}else{syntax.syntax_complete()}) {
        return Err("checker traversal has incomplete native syntax".into());
    }
    let mut walker = Walker {
        syntax,
        events: Vec::new(),
        observer: Some(observer),
    };
    let flow = walker.block(&syntax.parsed().statements, true)?;
    Ok(Walk {
        flow,
        events: walker.events,
    })
}
/// SAME policy CFG over the canonical roots of an actual current binding.
/// The caller must first authenticate genuine Original body availability; this
/// function is syntax traversal only and never turns parse failure into None.
pub(crate) fn current_original_syntax_with_observer_using<'ast,E:From<String>+for<'e>From<&'e str>>(body:&'ast dm_tree::frontend::CurrentArchivedBody<'_,'_>,observer:&mut impl EvaluatedObserver<'ast,E>)->Result<Walk<'ast>,E>{
 let syntax=body.syntax().canonical_statement_storage();if !syntax.original_literal_syntax_complete(){return Err("current checker traversal has incomplete native literal syntax".into())}let mut walker=Walker{syntax,events:Vec::new(),observer:Some(observer)};let flow=walker.block(&syntax.parsed().statements,true)?;Ok(Walk{flow,events:walker.events})
}
fn walk(syntax: &StatementBody) -> Result<Walk<'_>, String> {
    if !syntax.syntax_complete() {
        return Err("checker traversal has incomplete native syntax".into());
    }
    let mut walker:Walker<'_, '_, String> = Walker {
        syntax,
        events: Vec::new(),
        observer: None,
    };
    let flow = walker.block(&syntax.parsed().statements, true)?;
    Ok(Walk {
        flow,
        events: walker.events,
    })
}
struct Walker<'a, 'o,E=String> {
    syntax: &'a StatementBody,
    events: Vec<Event<'a>>,
    observer: Option<&'o mut dyn EvaluatedObserver<'a,E>>,
}
impl<'a,E:From<String>+for<'e>From<&'e str>> Walker<'a, '_,E> {
    fn check_observer_admission(&mut self) -> Result<(), E> {
        if let Some(observer) = self.observer.as_deref_mut() {
            observer.admit_storage(0)?;
        }
        Ok(())
    }
    fn event(&mut self, event: Event<'a>) -> Result<(), E> {
        self.check_observer_admission()?;
        if let Some(observer)=self.observer.as_deref_mut(){if observer.control_event(event)?{return Ok(())}}
        if self.events.len() == self.events.capacity() {
            let cap = self
                .events
                .capacity()
                .checked_mul(2)
                .unwrap_or(usize::MAX)
                .max(4);
            let bytes = cap
                .saturating_mul(std::mem::size_of::<Event<'a>>())
                .saturating_add(64);
            let bounded = if let Some(observer) = self.observer.as_deref_mut() {
                observer.admit_storage(bytes)?
            } else {
                false
            };
            if bounded
                && self
                    .events
                    .try_reserve_exact(cap.saturating_sub(self.events.len()))
                    .is_err()
            {
                if let Some(observer) = self.observer.as_deref_mut() {
                    observer.storage_allocation_failed()
                }
                return Err("bounded control-observer event allocation refused".into());
            }
        }
        self.events.push(event);
        Ok(())
    }
    fn block(
        &mut self,
        statements: &'a [Statement],
        mut setting_allowed: bool,
    ) -> Result<ControlFlow, E> {
        self.check_observer_admission()?;
        let mut flow = ControlFlow::default();
        for statement in statements {
            self.check_observer_admission()?;
            if flow.terminates() {
                self.event(Event::Unreachable {
                    kind: UnreachableKind::Sibling,
                    at: statement.header_span,
                })?;
                break;
            }
            if let Some(setting) = statement.setting() {
                let attribute = setting.attribute;
                if !setting_allowed && attribute.starts_with("SpacemanDMM_") {
                    self.event(Event::SettingOutsidePrefix {
                        statement,
                        attribute,
                    })?;
                }
            } else {
                setting_allowed = false;
            }
            flow.merge(self.statement(statement)?);
        }
        self.check_observer_admission()?;
        Ok(flow)
    }
    fn condition(
        &mut self,
        kind: ConditionKind,
        expression: &'a Expr,
        at: Span,
    ) -> Result<(), E> {
        self.event(Event::ControlCondition {
            kind,
            expression,
            at,
        })?;
        Ok(())
    }
    fn scoped<T>(
        &mut self,
        kind: ScopeKind,
        run: impl FnOnce(&mut Self) -> Result<T, E>,
    ) -> Result<T, E> {
        let entered = if let Some(observer) = self.observer.as_deref_mut() {
            observer.enter_scope(kind);
            observer.admit_storage(0).map(|_| ())
        } else {
            Ok(())
        };
        let result = entered.and_then(|_| run(self));
        let exited = if let Some(observer) = self.observer.as_deref_mut() {
            observer.leave_scope(kind);
            observer.admit_storage(0).map(|_| ())
        } else {
            Ok(())
        };
        result.and_then(|value| exited.map(|_| value))
    }
    fn evaluated(&mut self, expression: &'a Expr) -> Result<(), E> {
        if let Some(observer) = self.observer.as_deref_mut() {
            observer.expression(expression)?;
        }
        Ok(())
    }
    fn binding(
        &mut self,
        binding: &'a str,
        value: Option<&'a Expr>,
        always_untyped: bool,
        at: Span,
    ) -> Result<(), E> {
        if let Some(observer) = self.observer.as_deref_mut() {
            observer.binding(binding, value, always_untyped, at)?;
        }
        Ok(())
    }
    fn statement(&mut self, statement: &'a Statement) -> Result<ControlFlow, E> {
        if matches!(
            &statement.kind,
            StatementKind::Return(_)
                | StatementKind::Throw(_)
                | StatementKind::Var { .. }
                | StatementKind::Assign { .. }
                | StatementKind::Call(_)
                | StatementKind::Expression(_)
                | StatementKind::Set { .. }
                | StatementKind::ProjectedSet { .. }
                | StatementKind::Goto(_)
                | StatementKind::Break
                | StatementKind::BreakLabel(_)
                | StatementKind::Continue
                | StatementKind::ContinueLabel(_)
        ) {
            if let Some(observer) = self.observer.as_deref_mut() {
                observer.leaf(statement)?;
            }
        }
        match &statement.kind {
            StatementKind::Return(_) => Ok(ControlFlow {
                returns: true,
                ..Default::default()
            }),
            StatementKind::If { .. } => self.if_chain(statement),
            StatementKind::While { condition, body } => self.scoped(ScopeKind::While, |this| {
                this.evaluated(condition)?;
                this.block(body, false)?;
                Ok(ControlFlow::default())
            }),
            StatementKind::DoWhile { body, condition } => self.scoped(ScopeKind::DoWhile, |this| {
                let state = this.block(body, false)?;
                if state.terminates_loop() {
                    this.event(Event::DoWhileUnreachable{at:statement.header_span,condition:condition.span})?;
                    if let Some(observer)=this.observer.as_deref_mut(){observer.do_while_unreachable(statement.header_span,condition.span)?;}
                    return Ok(state);
                }
                this.evaluated(condition)?;
                Ok(ControlFlow::default())
            }),
            StatementKind::For { control, body } => self.scoped(ScopeKind::For, |this| {
                match control {
                    ForControl::CStyle {
                        initializer,
                        condition,
                        step,
                    } => {
                        if let (Some(observer), Some(initializer)) =
                            (this.observer.as_deref_mut(), initializer)
                        {
                            observer.initializer(initializer, statement.header_span)?;
                        }
                        if let Some(condition) = condition {
                            this.event(Event::LoopCondition {
                                expression: condition,
                                at: statement.span,
                            })?;
                            this.condition(ConditionKind::ForTest, condition, statement.span)?;
                            this.evaluated(condition)?;
                        }
                        // Pinned visitor evaluates inc BEFORE visiting the body.
                        if let (Some(observer), Some(step)) = (this.observer.as_deref_mut(), step) {
                            observer.statement_expression(step)?;
                        }
                    }
                    ForControl::Each { binding, iterable, .. } => {
                        if let Some(observer)=this.observer.as_deref_mut(){observer.iterable(iterable,statement.header_span)?;}
                        this.binding(binding, None, false, statement.header_span)?;
                    }
                    ForControl::Pair {
                        key_binding,
                        value_binding,
                        iterable,
                    } => {
                        if let Some(observer)=this.observer.as_deref_mut(){observer.iterable(iterable,statement.header_span)?;}
                        this.binding(key_binding, None, false, statement.header_span)?;
                        this.binding(value_binding, None, true, statement.header_span)?;
                    }
                    ForControl::RangeImplicitArray { binding, end, step } => {
                        this.evaluated(end)?;
                        if let Some(step) = step {
                            this.evaluated(step)?;
                        }
                        this.binding(binding, None, false, statement.header_span)?;
                    }
                    ForControl::Range {
                        binding,
                        start,
                        end,
                        step,
                    } => {
                        this.evaluated(end)?;
                        if let Some(step) = step {
                            this.evaluated(step)?;
                        }
                        this.binding(binding, Some(start), false, statement.header_span)?;
                    }
                    ForControl::All { declaration, .. } => {
                        this.binding(declaration, None, false, statement.header_span)?;
                    }
                }
                let state = this.block(body, false)?;
                if let ForControl::Range {
                    start, end, step, ..
                } = control
                {
                    match valid_range(start,end,step.as_ref())?{Some(true)=>return Ok(state),Some(false)=>{if let Some(observer)=this.observer.as_deref_mut(){observer.invalid_range(statement.header_span)?;}},None=>{}}
                }
                Ok(ControlFlow::default())
            }),
            StatementKind::Switch {
                selector,
                cases,
                else_branch,
                default_present,
            } => {
                if let Some(observer)=self.observer.as_deref_mut(){observer.switch_started(selector,cases,*default_present,statement.span)?;}
                self.condition(ConditionKind::Switch, selector, statement.span)?;
                self.evaluated(selector)?;
                let mut all = ControlFlow::all_true();
                for case in cases {
                    let state = self.scoped(ScopeKind::SwitchCase, |this| {
                        if let Some(observer)=this.observer.as_deref_mut(){observer.switch_case(case)?;}
                        for alternative in &case.alternatives {
                            match alternative {
                                dm_syntax::SwitchAlternative::Exact(value) => {
                                    this.evaluated(value)?
                                }
                                dm_syntax::SwitchAlternative::Range(start, end) => {
                                    this.evaluated(start)?;
                                    this.evaluated(end)?;
                                }
                            }
                        }
                        this.block(&case.body, false)
                    })?;
                    all.merge_false(state);
                }
                if else_branch.is_empty() {
                    all.no_else();
                } else {
                    all.merge_false(self.scoped(ScopeKind::SwitchDefault, |this| {
                        this.block(else_branch, false)
                    })?);
                    all.finalize();
                }
                Ok(all)
            }
            StatementKind::Spawn { delay, body } => {
                self.scoped(ScopeKind::Spawn, |this| {
                    if let Some(delay) = delay {
                        this.evaluated(delay)?;
                    }
                    this.block(body, false)
                })?;
                Ok(ControlFlow::default())
            }
            StatementKind::Label { body, .. } => {
                self.scoped(ScopeKind::Label, |this| this.block(body, false))?;
                Ok(ControlFlow::default())
            }
            StatementKind::Try {
                body,
                catch_binding,
                catch_parameter_count,
                catch_header_span,
                catch_body,
            } => {
                self.scoped(ScopeKind::Try, |this| this.block(body, false))?;
                if let Some(observer)=self.observer.as_deref_mut(){observer.catch_parameters(*catch_parameter_count,statement.header_span,*catch_header_span)?;}
                self.scoped(ScopeKind::Catch, |this| {
                    if let Some(observer) = this.observer.as_deref_mut() {
                        observer.catch_binding(catch_binding.as_deref(), *catch_header_span)?;
                    }
                    this.block(catch_body, false)
                })?;
                Ok(ControlFlow::default())
            }
            StatementKind::Break | StatementKind::BreakLabel(_) => Ok(ControlFlow {
                breaks: true,
                fuzzy: true,
                ..Default::default()
            }),
            StatementKind::Continue | StatementKind::ContinueLabel(_) => Ok(ControlFlow {
                continues: true,
                fuzzy: true,
                ..Default::default()
            }),
            StatementKind::Call(value) | StatementKind::Expression(value) => {
                if let ExprKind::Call { callee, args } = &value.kind {
                    if matches!(&callee.kind,ExprKind::Ident(name) if name=="CRASH") {
                        if args.len() > 1 {
                            return Err(
                                "pinned CRASH statement accepts at most one expression".into()
                            );
                        }
                        return Ok(ControlFlow {
                            returns: true,
                            ..Default::default()
                        });
                    }
                }
                Ok(ControlFlow::default())
            }
            StatementKind::Unsupported => {
                Err("unsupported native statement in checker traversal".into())
            }
            StatementKind::Throw(_)
            | StatementKind::Goto(_)
            | StatementKind::Set { .. }
            | StatementKind::ProjectedSet { .. }
            | StatementKind::Var { .. }
            | StatementKind::Assign { .. } => Ok(ControlFlow::default()),
        }
    }
    fn if_chain(&mut self, mut arm: &'a Statement) -> Result<ControlFlow, E> {
        let mut all = ControlFlow::all_true();
        let mut always_true = false;
        loop {
            let StatementKind::If {
                condition,
                then_branch,
                else_branch,
            } = &arm.kind
            else {
                unreachable!()
            };
            let at = self
                .syntax
                .parsed()
                .control_origin(condition.span)
                .ok_or("missing primary if origin")?;
            self.condition(ConditionKind::If, condition, at)?;
            if always_true {
                self.event(Event::Unreachable {
                    kind: UnreachableKind::IfArm,
                    at,
                })?;
            }
            let state = self.scoped(ScopeKind::IfArm, |this| {
                this.evaluated(condition)?;
                this.block(then_branch, false)
            })?;
            match truthy(condition)? {
                Some(value) => {
                    self.event(Event::IfDeterminate {
                        expression: condition,
                        at,
                        value,
                    })?;
                    if value {
                        all.merge_false(state);
                        always_true = true;
                    }
                }
                None => all.merge_false(state),
            }
            // Authored else-if is one reference arms vector. An explicit else
            // containing an if is a separate block; primary spans distinguish it.
            if let [next] = else_branch.as_slice() {
                if matches!(next.kind, StatementKind::If { .. })
                    && next.span.start < next.header_span.start
                {
                    arm = next;
                    continue;
                }
            }
            if else_branch.is_empty() {
                all.no_else();
            } else {
                if always_true {
                    self.event(Event::Unreachable {
                        kind: UnreachableKind::ElseArm,
                        at: else_branch[0].header_span,
                    })?;
                }
                all.merge_false(
                    self.scoped(ScopeKind::ElseArm, |this| this.block(else_branch, false))?,
                );
                all.finalize();
            }
            return Ok(all);
        }
    }
}

/// Pinned syntactic truthiness; this is not name lookup or constant folding.
pub fn truthy(expression: &Expr) -> Result<Option<bool>, String> {
    match &expression.kind {
        ExprKind::Group(value) => truthy(value),
        ExprKind::Unary { op, value } if op == "!" => Ok(truthy(value)?.map(|v| !v)),
        // The primary parser now bounds the constructor term itself; any
        // later field/index/call follows are OUTSIDE this Unary node.
        ExprKind::Unary { op, .. } if op == "new" || op == "new()" => Ok(Some(true)),
        ExprKind::Binary { op, lhs, rhs } if matches!(op.as_str(), "&&" | "||") => {
            let Some(left) = truthy(lhs)? else {
                return Ok(None);
            };
            let Some(right) = truthy(rhs)? else {
                return Ok(None);
            };
            Ok(Some(if op == "&&" {
                left && right
            } else {
                left || right
            }))
        }
        ExprKind::Binary { op, rhs, .. } if op == "=" => bare_truthy(rhs),
        ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } => match truthy(condition)? {
            Some(true) => truthy(then_value),
            Some(false) => truthy(else_value),
            None => Ok(None),
        },
        _ => bare_truthy(expression),
    }
}
fn bare_truthy(expression: &Expr) -> Result<Option<bool>, String> {
    match &expression.kind {
        ExprKind::Group(value) => truthy(value),
        ExprKind::TypePath(_) => Ok(Some(true)),
        ExprKind::ObjectInitializer { object, .. }
            if matches!(object.kind, ExprKind::TypePath(_)) =>
        {
            Ok(Some(true))
        }
        ExprKind::ObjectInitializer { .. } => {
            Err("prefab truthiness needs a primary term origin".into())
        }
        ExprKind::Literal(text) => {
            if let Some(value)=text.original_value(){return Ok(match value{dm_syntax::OriginalTokenValue::Int(n)=>Some(n!=0),dm_syntax::OriginalTokenValue::Float(n)=>Some(n!=0.0),dm_syntax::OriginalTokenValue::String(s)=>Some(!s.is_empty()),_=>None})}
            let raw = text.as_str();
            if raw == "null" {
                return Ok(Some(false));
            }
            if raw
                .as_bytes()
                .first()
                .is_some_and(|c| c.is_ascii_digit() || *c == b'.')
            {
                return Ok(Some(match numeric_form(raw)? {
                    NumericForm::Integer(value) => value != 0,
                    NumericForm::Float if raw.contains('#') => true,
                    NumericForm::Float => {
                        raw.replace('_', "")
                            .parse::<f32>()
                            .map_err(|_| "invalid issued float")?
                            != 0.0
                    }
                }));
            }
            if let Some(parts) = text.parts().map_err(str::to_owned)? {
                let lexical = parts
                    .lexical
                    .map_err(|e| format!("truthiness lexical facts unavailable: {e:?}"))?;
                return Ok(
                    if lexical.interpolated && !lexical.pinned_segment_nonempty {
                        None
                    } else {
                        Some(lexical.pinned_segment_nonempty)
                    },
                );
            }
            Ok(None)
        }
        ExprKind::Call { callee, .. } if matches!(&callee.kind,ExprKind::Ident(name) if name=="list"||name=="alist"||name=="new") => {
            Ok(Some(true))
        }
        // Constructor syntax remains a term when used as an assignment rhs.
        ExprKind::Unary { op, .. } if op == "new" || op == "new()" => truthy(expression),
        _ => Ok(None),
    }
}
fn integer(expression: &Expr) -> Result<Option<i32>, String> {
    if let ExprKind::Literal(text) = &expression.kind {
        if let Some(value)=text.original_value(){return Ok(match value{dm_syntax::OriginalTokenValue::Int(n)=>Some(n),_=>None})}
        if text
            .as_bytes()
            .first()
            .is_some_and(|c| c.is_ascii_digit() || *c == b'.')
        {
            return Ok(match numeric_form(text.as_str())? {
                NumericForm::Integer(value) => Some(value),
                NumericForm::Float => None,
            });
        }
    }
    Ok(None)
}
fn as_term(expression: &Expr) -> Result<bool, String> {
    Ok(match &expression.kind {
        ExprKind::Ident(_)
        | ExprKind::Literal(_)
        | ExprKind::TypePath(_)
        | ExprKind::Group(_)
        | ExprKind::ObjectInitializer { .. } => true,
        ExprKind::Unary { op, .. } if op == "new" || op == "new()" => true,
        ExprKind::Call { callee, .. }
            if matches!(callee.kind, ExprKind::Ident(_) | ExprKind::TypePath(_))
                || matches!(
                    dm_syntax::call_target(callee),
                    dm_syntax::CallTarget::GlobalNamed(_)
                ) =>
        {
            true
        }
        ExprKind::Call { callee, .. } if matches!(&callee.kind, ExprKind::Unary { op, .. } if op == "new" || op == "new()") => {
            false
        }
        ExprKind::Call { .. } | ExprKind::StaticMember { .. } | ExprKind::TypeFilter { .. } => {
            return Err("range-step classification needs primary term/follow origin".into())
        }
        _ => false,
    })
}
fn valid_range(start: &Expr, end: &Expr, step: Option<&Expr>) -> Result<Option<bool>, String> {
    let (Some(start), Some(end)) = (integer(start)?, integer(end)?) else {
        return Ok(None);
    };
    if start == 0 && end == 0 {
        return Ok(Some(false));
    }
    if let Some(step) = step {
        if integer(step)?.is_some() || !as_term(step)? {
            return Ok(Some(true));
        }
    }
    Ok(Some(start <= end))
}

#[cfg(test)]
#[path = "checker_reachable_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "checker_reachable_storage_tests.rs"]
mod storage_tests;
