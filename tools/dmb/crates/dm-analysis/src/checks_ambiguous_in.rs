//! `ambiguous_in_lhs` over the compiler's authenticated, borrowed syntax.
//!
//! Diagnostic policy adapted from SpacemanDMM dreamchecker, lib.rs at commit
//! 0290db5c752fa292f9824521515b603a2afd11dc (GPL-3.0). This family alone does not
//! certify full checker parity. Unknown diagnostic origins are explicit errors,
//! never guessed source coordinates or clean results.

use crate::checks::{BodyView, Diagnostic, Note, Severity};
use dm_syntax::{
    Expr, ExprKind, NodeStep, Span, Statement, StatementKind, SwitchAlternative, TypedVisitor,
    VisitDecision,
};
use dm_tree::frontend::{ArchivedBody, StatementBody};

pub fn check(view: &BodyView<'_>, severity: Severity) -> Result<Vec<Diagnostic>, String> {
    check_syntax(view.syntax(), severity)
}

pub fn archived(body: &ArchivedBody<'_>, severity: Severity) -> Result<Vec<Diagnostic>, String> {
    check_syntax(body.statement_body(), severity)
}

fn check_syntax(syntax: &StatementBody, severity: Severity) -> Result<Vec<Diagnostic>, String> {
    if !syntax.syntax_complete() {
        return Err("body has unsupported or malformed native syntax".into());
    }
    if severity == Severity::Disabled {
        return Ok(Vec::new());
    }
    let mut visitor = Membership {
        origins: syntax.parsed(),
        severity,
        diagnostics: Vec::new(),
        statements: Vec::new(),
        expressions: Vec::new(),
        error: None,
    };
    dm_syntax::visit_statements(&syntax.parsed().statements, &mut visitor);
    match visitor.error {
        Some(error) => Err(error),
        None => Ok(visitor.diagnostics),
    }
}

#[derive(Clone, Copy)]
struct Unary {
    spelling: &'static str,
    postfix: bool,
}
impl Unary {
    fn from_native(op: &str) -> Option<Self> {
        Some(Self {
            spelling: match op {
                "-" => "-",
                "!" => "!",
                "~" => "~",
                "pre++" | "post++" => "++",
                "pre--" | "post--" => "--",
                "&" => "&",
                "*" => "*",
                _ => return None,
            },
            postfix: matches!(op, "post++" | "post--"),
        })
    }
    fn around(self, operand: &str) -> String {
        if self.postfix {
            format!("{operand}{}", self.spelling)
        } else {
            format!("{}{operand}", self.spelling)
        }
    }
}

/// The reference scans a Base's follows from the term outward, so its first
/// unary is the innermost prefix/postfix in the native chain. Groups end that
/// chain; unary operators in call arguments or index operands are unrelated.
fn unary_in_base(mut expression: &Expr) -> Result<Option<Unary>, String> {
    let mut selected = None;
    loop {
        expression = match &expression.kind {
            ExprKind::Unary { op, .. } if op == "new" || op == "new()" => break,
            ExprKind::Unary { op, value } => {
                selected = Some(Unary::from_native(op).ok_or_else(|| {
                    format!("native unary {op:?} has no pinned checker interpretation")
                })?);
                value
            }
            ExprKind::Member { object, .. }
            | ExprKind::StaticMember { object, .. }
            | ExprKind::SafeMember { object, .. }
            | ExprKind::Index { object, .. }
            | ExprKind::SafeIndex { object, .. } => object,
            ExprKind::Call { callee, .. } => callee,
            _ => break,
        };
    }
    Ok(selected)
}

fn wording(lhs: &Expr) -> Result<Option<(String, [String; 2])>, String> {
    match &lhs.kind {
        ExprKind::Binary { op, .. } => {
            // Both spellings parse as the reference's BinaryOp::NotEq.
            let op = if op == "<>" { "!=" } else { op.as_str() };
            Ok(Some((
                format!("ambiguous `{op}` on left side of an `in`"),
                [
                    format!("add parentheses to fix: `a {op} (b in c)`"),
                    format!("add parentheses to disambiguate: `(a {op} b) in c`"),
                ],
            )))
        }
        ExprKind::Conditional { .. } => Ok(Some((
            "ambiguous ternary on left side of an `in`".into(),
            [
                "add parentheses to fix: `a ? b : (c in d)`".into(),
                "add parentheses to disambiguate: `(a ? b : c) in d`".into(),
            ],
        ))),
        _ => Ok(unary_in_base(lhs)?.map(|unary| {
            (
                format!("ambiguous `{}` on left side of an `in`", unary.spelling),
                [
                    format!("add parentheses to fix: `{}`", unary.around("(a in b)")),
                    format!(
                        "add parentheses to disambiguate: `({}) in b`",
                        unary.around("a")
                    ),
                ],
            )
        })),
    }
}

type Anchor = Result<Span, &'static str>;

#[derive(Clone, Copy)]
enum Children {
    Inherit(Anchor),
    All(Span),
    Call { callee: Anchor, arguments: Anchor },
    Index { receiver: Anchor },
}
impl Children {
    fn at(self, index: usize) -> Anchor {
        match self {
            Self::Inherit(at) => at,
            Self::All(at) => Ok(at),
            Self::Call { callee, arguments } => {
                if index == 0 {
                    callee
                } else {
                    arguments
                }
            }
            Self::Index { receiver } => {
                if index == 0 {
                    receiver
                } else {
                    Err("membership diagnostic needs an uncaptured index-token origin")
                }
            }
        }
    }
}

struct StatementFrame {
    at: Span,
    direct: Option<Anchor>,
}

struct Membership<'a> {
    origins: &'a dm_syntax::ParsedBody,
    severity: Severity,
    diagnostics: Vec<Diagnostic>,
    statements: Vec<StatementFrame>,
    expressions: Vec<Children>,
    error: Option<String>,
}
impl Membership<'_> {
    fn origin(&self, path: &[NodeStep], expression: &Expr) -> Anchor {
        if let Some(parent) = self.expressions.last() {
            let Some(NodeStep::Child(index)) = path.last() else {
                return Err("membership diagnostic has no issued child coordinate");
            };
            return parent.at(*index);
        }
        self.statements.last().map_or(Ok(expression.span), |frame| {
            frame.direct.unwrap_or(Ok(frame.at))
        })
    }

    fn children(expression: &Expr, at: Anchor) -> Children {
        match &expression.kind {
            // The reference enters these through visit_term(term.location),
            // then uses that term location for their nested expressions.
            ExprKind::Group(_) | ExprKind::Literal(_) => Children::All(expression.span),
            ExprKind::Call { callee, .. } => {
                let arguments = match &callee.kind {
                    ExprKind::Ident(_) | ExprKind::TypePath(_) => Ok(callee.span),
                    ExprKind::Unary { op, .. } if op == "new" || op == "new()" => {
                        Ok(expression.span)
                    }
                    ExprKind::Member { object, .. } if matches!(&object.kind, ExprKind::Ident(name) if name == "global") => {
                        Ok(expression.span)
                    }
                    _ => Err("membership diagnostic needs an uncaptured call-selector origin"),
                };
                Children::Call {
                    callee: at,
                    arguments,
                }
            }
            ExprKind::Index { .. } | ExprKind::SafeIndex { .. } => Children::Index { receiver: at },
            _ => Children::Inherit(at),
        }
    }
}

impl TypedVisitor for Membership<'_> {
    fn statement(&mut self, statement: &Statement, _: &[NodeStep]) -> VisitDecision {
        let direct = match &statement.kind {
            StatementKind::If { condition, .. } | StatementKind::DoWhile { condition, .. } => Some(
                self.origins
                    .control_origin(condition.span)
                    .ok_or("membership condition has no primary control origin"),
            ),
            _ => None,
        };
        self.statements.push(StatementFrame {
            at: statement.span,
            direct,
        });
        // Normal setting values are not evaluated by the reference checker.
        if matches!(&statement.kind, StatementKind::Set { .. }) {
            VisitDecision::Skip
        } else {
            VisitDecision::Descend
        }
    }
    fn leave_statement(&mut self, _: &Statement, _: &[NodeStep]) {
        self.statements.pop();
    }
    fn enter_branch(&mut self, owner: &Statement, index: usize, _: &[NodeStep]) {
        if let StatementKind::Switch { cases, .. } = &owner.kind {
            let at = cases
                .get(index)
                .and_then(|case| match case.alternatives.first()? {
                    SwitchAlternative::Exact(value) | SwitchAlternative::Range(value, _) => {
                        Some(value.span)
                    }
                });
            if let Some(frame) = self.statements.last_mut() {
                frame.direct = at.map(Ok);
            }
        }
    }
    fn leave_branch(&mut self, owner: &Statement, _: usize, _: &[NodeStep]) {
        if matches!(&owner.kind, StatementKind::Switch { .. }) {
            if let Some(frame) = self.statements.last_mut() {
                frame.direct = None;
            }
        }
    }
    fn expression(&mut self, expression: &Expr, path: &[NodeStep]) -> VisitDecision {
        let at = self.origin(path, expression);
        self.expressions.push(Self::children(expression, at));
        if let ExprKind::Binary { op, lhs, .. } = &expression.kind {
            if op == "in" {
                match wording(lhs) {
                    Ok(Some((message, notes))) => match at {
                        Ok(span) => self.diagnostics.push(Diagnostic {
                            family: "ambiguous_in_lhs",
                            severity: self.severity,
                            span,
                            expression_span: expression.span,
                            message,
                            notes: notes.into_iter().map(|message| Note { message }).collect(),
                        }),
                        Err(error) => {
                            self.error = Some(error.into());
                            return VisitDecision::Stop;
                        }
                    },
                    Ok(None) => {}
                    Err(error) => {
                        self.error = Some(error);
                        return VisitDecision::Stop;
                    }
                }
            }
        }
        if matches!(&expression.kind, ExprKind::ObjectInitializer { .. }) {
            // Pinned visit_term(Prefab) does not evaluate its modified fields.
            VisitDecision::Skip
        } else {
            VisitDecision::Descend
        }
    }
    fn leave_expression(&mut self, _: &Expr, _: &[NodeStep]) {
        self.expressions.pop();
    }
}

#[cfg(test)]
#[path = "checks_ambiguous_in_tests.rs"]
mod tests;
