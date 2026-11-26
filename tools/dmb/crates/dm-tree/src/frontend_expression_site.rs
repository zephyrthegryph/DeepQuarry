//! Borrowed expression lookup authenticated by the current issued body.
use super::ParsedBody;
use dm_syntax::{
    Expr, ExprKind, ForControl, ForInitializer, Span, Statement, StatementKind, SwitchAlternative,
};

impl ParsedBody<'_> {
    /// Find a unique modifier expression in this issued typed parse. Unsupported
    /// lossless bodies have no recipe; their ordinary lowering remains authoritative.
    pub fn object_initializer_at(&self, span: Span) -> Result<Option<&Expr>, String> {
        self.issuer
            .validate_parsed_body(self, self.occurrence)
            .map_err(|error| format!("expression body issuance: {error:?}"))?;
        let Some(body) = self.statement_body() else {
            return Ok(None);
        };
        let mut found = None;
        let mut duplicate = false;
        statements(&body.parsed().statements, &mut |expr| {
            if expr.span == span && matches!(&expr.kind, ExprKind::ObjectInitializer { .. }) {
                if found.replace(expr).is_some() {
                    duplicate = true;
                }
            }
        });
        Ok(if duplicate { None } else { found })
    }
}
fn expression<'a>(expr: &'a Expr, visit: &mut impl FnMut(&'a Expr)) {
    visit(expr);
    use ExprKind as E;
    match &expr.kind {
        E::Ident(_) | E::Literal(_) | E::TypePath(_) => {}
        E::Unary { value, .. } | E::Group(value) | E::TypeFilter { value, .. } => {
            expression(value, visit)
        }
        E::Binary { lhs, rhs, .. } => {
            expression(lhs, visit);
            expression(rhs, visit);
        }
        E::Conditional {
            condition,
            then_value,
            else_value,
        } => {
            expression(condition, visit);
            expression(then_value, visit);
            expression(else_value, visit);
        }
        E::Call { callee, args } => {
            expression(callee, visit);
            for arg in args {
                expression(arg, visit);
            }
        }
        E::Member { object, .. }
        | E::StaticMember { object, .. }
        | E::SafeMember { object, .. } => expression(object, visit),
        E::ObjectInitializer { object, fields } => {
            expression(object, visit);
            for (_, value) in fields {
                expression(value, visit);
            }
        }
        E::Index { object, index } | E::SafeIndex { object, index } => {
            expression(object, visit);
            expression(index, visit);
        }
    }
}
fn optional<'a>(expr: &'a Option<Expr>, visit: &mut impl FnMut(&'a Expr)) {
    if let Some(expr) = expr {
        expression(expr, visit);
    }
}
fn statements<'a>(body: &'a [Statement], visit: &mut impl FnMut(&'a Expr)) {
    use StatementKind as S;
    for statement in body {
        match &statement.kind {
            S::If {
                condition,
                then_branch,
                else_branch,
            } => {
                expression(condition, visit);
                statements(then_branch, visit);
                statements(else_branch, visit);
            }
            S::While { condition, body } | S::DoWhile { body, condition } => {
                expression(condition, visit);
                statements(body, visit);
            }
            S::Spawn { delay, body } => {
                optional(delay, visit);
                statements(body, visit);
            }
            S::Set { value, .. } | S::Throw(value) | S::Call(value) | S::Expression(value) => {
                expression(value, visit)
            }
            S::For { control, body } => {
                match control {
                    ForControl::All { .. } => {}
                    ForControl::Each { iterable, .. } | ForControl::Pair { iterable, .. } => {
                        expression(iterable, visit)
                    }
                    ForControl::Range {
                        start, end, step, ..
                    } => {
                        expression(start, visit);
                        expression(end, visit);
                        optional(step, visit);
                    }
                    ForControl::CStyle {
                        initializer,
                        condition,
                        step,
                    } => {
                        if let Some(initializer) = initializer {
                            match initializer {
                                ForInitializer::Declare { value, .. } => optional(value, visit),
                                ForInitializer::Expr(value) => expression(value, visit),
                            }
                        }
                        optional(condition, visit);
                        optional(step, visit);
                    }
                }
                statements(body, visit);
            }
            S::Switch {
                selector,
                cases,
                else_branch,
            } => {
                expression(selector, visit);
                for case in cases {
                    for alternative in &case.alternatives {
                        match alternative {
                            SwitchAlternative::Exact(value) => expression(value, visit),
                            SwitchAlternative::Range(start, end) => {
                                expression(start, visit);
                                expression(end, visit);
                            }
                        }
                    }
                    statements(&case.body, visit);
                }
                statements(else_branch, visit);
            }
            S::Try {
                body, catch_body, ..
            } => {
                statements(body, visit);
                statements(catch_body, visit);
            }
            S::Label { body, .. } => statements(body, visit),
            S::Return(value) | S::Var { value, .. } => optional(value, visit),
            S::Assign { target, value, .. } => {
                expression(target, visit);
                expression(value, visit);
            }
            S::Goto(_)
            | S::Break
            | S::BreakLabel(_)
            | S::Continue
            | S::ContinueLabel(_)
            | S::Unsupported => {}
        }
    }
}
