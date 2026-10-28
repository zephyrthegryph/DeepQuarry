//! Legacy untyped-policy observation order over the compiler's borrowed AST.
//!
//! This is deliberately not execution order. The independent legacy policy
//! observes every control header before any nested block. Its `if` arms are a
//! single statement, whereas native syntax retains each authored `else if` as
//! an `If` inside the else branch. No model or expression is cloned here.
//! Callers must first reject unsupported/malformed issued body syntax.

use dm_syntax::{
    for_each_expression_child, Expr, ExprKind, ForControl, ForInitializer, Span, Statement,
    StatementKind, SwitchAlternative,
};

pub(crate) fn assignments(statements: &[Statement], emit: &mut impl FnMut(&Expr, &Expr, Span)) {
    for statement in statements {
        statement_assignments(statement, emit);
    }
}

fn expression(node: &Expr, at: Span, emit: &mut impl FnMut(&Expr, &Expr, Span)) {
    if let ExprKind::Binary { op, lhs, rhs } = &node.kind {
        if op == "=" {
            emit(lhs, rhs, at);
        }
    }
    for_each_expression_child(node, |_, child| expression(child, at, emit));
}

/// `parse_if` retains the `else` prefix in the whole span, but advances the
/// nested header past it. An ordinary `if` written inside an explicit `else`
/// block has equal starts and must remain a separate legacy statement.
fn next_arm(else_branch: &[Statement]) -> Option<&Statement> {
    let [next] = else_branch else { return None };
    (matches!(&next.kind, StatementKind::If { .. }) && next.header_span.start > next.span.start)
        .then_some(next)
}

fn statement_assignments(statement: &Statement, emit: &mut impl FnMut(&Expr, &Expr, Span)) {
    let at = statement.span;
    match &statement.kind {
        StatementKind::If { .. } => {
            // All conditions of one legacy If share its first statement's
            // location, including conditions authored on later else-if lines.
            let mut arm = statement;
            loop {
                let StatementKind::If {
                    condition,
                    else_branch,
                    ..
                } = &arm.kind
                else {
                    unreachable!("if-arm chain is checked above")
                };
                expression(condition, at, emit);
                match next_arm(else_branch) {
                    Some(next) => arm = next,
                    None => break,
                }
            }
            let mut arm = statement;
            loop {
                let StatementKind::If {
                    then_branch,
                    else_branch,
                    ..
                } = &arm.kind
                else {
                    unreachable!("if-arm chain is checked above")
                };
                assignments(then_branch, emit);
                match next_arm(else_branch) {
                    Some(next) => arm = next,
                    None => {
                        assignments(else_branch, emit);
                        break;
                    }
                }
            }
        }
        StatementKind::While { condition, body } | StatementKind::DoWhile { condition, body } => {
            expression(condition, at, emit);
            assignments(body, emit);
        }
        StatementKind::Spawn { delay, body } => {
            if let Some(delay) = delay {
                expression(delay, at, emit);
            }
            assignments(body, emit);
        }
        StatementKind::Set { value, .. } => expression(value, at, emit),
        StatementKind::For { control, body } => {
            match control {
                ForControl::All { .. } => {}
                ForControl::Each { iterable, .. } | ForControl::Pair { iterable, .. } => {
                    expression(iterable, at, emit);
                }
                ForControl::Range {
                    start, end, step, ..
                } => {
                    expression(start, at, emit);
                    expression(end, at, emit);
                    if let Some(step) = step {
                        expression(step, at, emit);
                    }
                }
                ForControl::CStyle {
                    initializer,
                    condition,
                    step,
                } => {
                    // Legacy stmt_exprs(ForLoop) visits test; walk_block then
                    // visits init and inc, in that order, at the For's location.
                    if let Some(condition) = condition {
                        expression(condition, at, emit);
                    }
                    match initializer {
                        Some(ForInitializer::Declare {
                            value: Some(value), ..
                        })
                        | Some(ForInitializer::Expr(value)) => expression(value, at, emit),
                        _ => {}
                    }
                    if let Some(step) = step {
                        expression(step, at, emit);
                    }
                }
            }
            assignments(body, emit);
        }
        StatementKind::Switch {
            selector,
            cases,
            else_branch,
        } => {
            expression(selector, at, emit);
            for case in cases {
                for alternative in &case.alternatives {
                    match alternative {
                        SwitchAlternative::Exact(value) => expression(value, at, emit),
                        SwitchAlternative::Range(start, end) => {
                            expression(start, at, emit);
                            expression(end, at, emit);
                        }
                    }
                }
            }
            for case in cases {
                assignments(&case.body, emit);
            }
            assignments(else_branch, emit);
        }
        StatementKind::Try {
            body, catch_body, ..
        } => {
            assignments(body, emit);
            assignments(catch_body, emit);
        }
        StatementKind::Throw(value)
        | StatementKind::Call(value)
        | StatementKind::Expression(value) => expression(value, at, emit),
        StatementKind::Return(Some(value))
        | StatementKind::Var {
            value: Some(value), ..
        } => {
            expression(value, at, emit);
        }
        StatementKind::Assign { target, op, value } => {
            if op == "=" {
                emit(target, value, at);
            }
            expression(target, at, emit);
            expression(value, at, emit);
        }
        StatementKind::Label { body, .. } => assignments(body, emit),
        StatementKind::Goto(_)
        | StatementKind::Return(None)
        | StatementKind::Var { value: None, .. }
        | StatementKind::Break
        | StatementKind::BreakLabel(_)
        | StatementKind::Continue
        | StatementKind::ContinueLabel(_)
        | StatementKind::Unsupported => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn observed(source: &str) -> Vec<(String, usize)> {
        let ast = dm_syntax::parse(source);
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let body = dm_syntax::parse_proc_body(&ast.items[0]);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
        let mut found = Vec::new();
        assignments(&body.statements, &mut |lhs, _, at| {
            let ExprKind::Ident(name) = &lhs.kind else {
                panic!("expected test identifier")
            };
            let line = source[..at.start]
                .bytes()
                .filter(|byte| *byte == b'\n')
                .count()
                + 1;
            found.push((name.clone(), line));
        });
        found
    }

    #[test]
    fn do_while_condition_precedes_body_at_the_do_statement() {
        assert_eq!(
            observed("/proc/test()\n    do\n        body = 1\n    while(condition = 2)\n"),
            [("condition".into(), 2), ("body".into(), 3)]
        );
    }

    #[test]
    fn c_style_for_observes_test_then_init_then_step_then_body() {
        assert_eq!(
            observed("/proc/test()\n    for(init = 0; (check = 1); step = 2)\n        body = 3\n"),
            [
                ("check".into(), 2),
                ("init".into(), 2),
                ("step".into(), 2),
                ("body".into(), 3)
            ]
        );
    }

    #[test]
    fn switch_observes_every_case_condition_before_any_case_body() {
        assert_eq!(
            observed("/proc/test()\n    switch(selector = 0)\n        if(first = 1)\n            body_one = 3\n        if(second = 2)\n            body_two = 4\n"),
            [("selector".into(), 2), ("first".into(), 2), ("second".into(), 2),
             ("body_one".into(), 4), ("body_two".into(), 6)]
        );
    }

    #[test]
    fn flattened_else_if_headers_precede_bodies_but_explicit_nested_if_is_separate() {
        assert_eq!(
            observed("/proc/test()\n    if(first = 1)\n        body_one = 3\n    else if(second = 2)\n        body_two = 4\n    else\n        if(nested = 5)\n            body_three = 6\n"),
            [("first".into(), 2), ("second".into(), 2), ("body_one".into(), 3),
             ("body_two".into(), 5), ("nested".into(), 7), ("body_three".into(), 8)]
        );
    }

    #[test]
    fn iteration_bindings_and_declarations_are_not_fabricated_assignments() {
        assert_eq!(
            observed("/proc/test()\n    for(var/element in list(nested = 1))\n        var/local = (other = 2)\n    outer = (inner = 3)\n    outer += (last = 4)\n"),
            [("nested".into(), 2), ("other".into(), 3), ("outer".into(), 4),
             ("inner".into(), 4), ("last".into(), 5)]
        );
    }
}
