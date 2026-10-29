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
fn walk(syntax: &StatementBody) -> Result<Walk<'_>, String> {
    if !syntax.syntax_complete() {
        return Err("checker traversal has incomplete native syntax".into());
    }
    let mut walker = Walker {
        syntax,
        events: Vec::new(),
    };
    let flow = walker.block(&syntax.parsed().statements, true)?;
    Ok(Walk {
        flow,
        events: walker.events,
    })
}
struct Walker<'a> {
    syntax: &'a StatementBody,
    events: Vec<Event<'a>>,
}
impl<'a> Walker<'a> {
    fn block(
        &mut self,
        statements: &'a [Statement],
        mut setting_allowed: bool,
    ) -> Result<ControlFlow, String> {
        let mut flow = ControlFlow::default();
        for statement in statements {
            if flow.terminates() {
                self.events.push(Event::Unreachable {
                    kind: UnreachableKind::Sibling,
                    at: statement.header_span,
                });
                break;
            }
            if let StatementKind::Set { attribute, .. } = &statement.kind {
                if !setting_allowed && attribute.starts_with("SpacemanDMM_") {
                    self.events.push(Event::SettingOutsidePrefix {
                        statement,
                        attribute,
                    });
                }
            } else {
                setting_allowed = false;
            }
            flow.merge(self.statement(statement)?);
        }
        Ok(flow)
    }
    fn condition(&mut self, kind: ConditionKind, expression: &'a Expr, at: Span) {
        self.events.push(Event::ControlCondition {
            kind,
            expression,
            at,
        });
    }
    fn statement(&mut self, statement: &'a Statement) -> Result<ControlFlow, String> {
        match &statement.kind {
            StatementKind::Return(_) => Ok(ControlFlow {
                returns: true,
                ..Default::default()
            }),
            StatementKind::If { .. } => self.if_chain(statement),
            StatementKind::While { body, .. } => {
                self.block(body, false)?;
                Ok(ControlFlow::default())
            }
            StatementKind::DoWhile { body, .. } => {
                let state = self.block(body, false)?;
                Ok(if state.terminates_loop() {
                    state
                } else {
                    ControlFlow::default()
                })
            }
            StatementKind::For { control, body } => {
                if let ForControl::CStyle {
                    condition: Some(condition),
                    ..
                } = control
                {
                    self.events.push(Event::LoopCondition {
                        expression: condition,
                        at: statement.span,
                    });
                    self.condition(ConditionKind::ForTest, condition, statement.span);
                }
                let state = self.block(body, false)?;
                if let ForControl::Range {
                    start, end, step, ..
                } = control
                {
                    if valid_range(start, end, step.as_ref())? == Some(true) {
                        return Ok(state);
                    }
                }
                Ok(ControlFlow::default())
            }
            StatementKind::Switch {
                selector,
                cases,
                else_branch,
            } => {
                self.condition(ConditionKind::Switch, selector, statement.span);
                let mut all = ControlFlow::all_true();
                for case in cases {
                    all.merge_false(self.block(&case.body, false)?);
                }
                if else_branch.is_empty() {
                    all.no_else();
                } else {
                    all.merge_false(self.block(else_branch, false)?);
                    all.finalize();
                }
                Ok(all)
            }
            StatementKind::Spawn { body, .. } | StatementKind::Label { body, .. } => {
                self.block(body, false)?;
                Ok(ControlFlow::default())
            }
            StatementKind::Try {
                body, catch_body, ..
            } => {
                self.block(body, false)?;
                self.block(catch_body, false)?;
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
            // Pinned Throw and Goto intentionally do not terminate a block.
            StatementKind::Throw(_)
            | StatementKind::Goto(_)
            | StatementKind::Set { .. }
            | StatementKind::Var { .. }
            | StatementKind::Assign { .. } => Ok(ControlFlow::default()),
        }
    }
    fn if_chain(&mut self, mut arm: &'a Statement) -> Result<ControlFlow, String> {
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
            self.condition(ConditionKind::If, condition, at);
            if always_true {
                self.events.push(Event::Unreachable {
                    kind: UnreachableKind::IfArm,
                    at,
                });
            }
            let state = self.block(then_branch, false)?;
            match truthy(condition)? {
                Some(value) => {
                    self.events.push(Event::IfDeterminate {
                        expression: condition,
                        at,
                        value,
                    });
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
                    self.events.push(Event::Unreachable {
                        kind: UnreachableKind::ElseArm,
                        at: else_branch[0].header_span,
                    });
                }
                all.merge_false(self.block(else_branch, false)?);
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
            if matches!(callee.kind, ExprKind::Ident(_) | ExprKind::TypePath(_)) =>
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
