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

trait Observer {
    fn expression(&mut self, _: &Expr, _: Span) {}
    fn assignment(&mut self, _: &Expr, _: &Expr, _: Span) {}
    fn statement_assignment(&mut self, _: &Expr, _: &Expr, _: Span) {}
}
struct Assignments<'a, F>(&'a mut F);
impl<F: FnMut(&Expr, &Expr, Span)> Observer for Assignments<'_, F> {
    fn assignment(&mut self, a: &Expr, b: &Expr, at: Span) {
        self.0(a, b, at);
    }
}
struct Expressions<'a, F>(&'a mut F);
impl<F: FnMut(&Expr, Span)> Observer for Expressions<'_, F> {
    fn expression(&mut self, node: &Expr, at: Span) {
        self.0(node, at);
    }
}
struct StatementAssignments<'a, F>(&'a mut F);
impl<F: FnMut(&Expr, &Expr, Span)> Observer for StatementAssignments<'_, F> {
    fn statement_assignment(&mut self, a: &Expr, b: &Expr, at: Span) {
        self.0(a, b, at);
    }
}
pub(crate) fn statement_assignments(
    statements: &[Statement],
    emit: &mut impl FnMut(&Expr, &Expr, Span),
) {
    walk(statements, &mut StatementAssignments(emit));
}
pub(crate) fn assignments(statements: &[Statement], emit: &mut impl FnMut(&Expr, &Expr, Span)) {
    walk(statements, &mut Assignments(emit));
}
pub(crate) fn expressions(statements: &[Statement], emit: &mut impl FnMut(&Expr, Span)) {
    walk(statements, &mut Expressions(emit));
}
fn walk(statements: &[Statement], emit: &mut impl Observer) {
    for statement in statements {
        statement_walk(statement, emit);
    }
}

fn expression(node: &Expr, at: Span, emit: &mut impl Observer) {
    if let ExprKind::Binary { op, lhs, rhs } = &node.kind {
        if op == "=" {
            emit.statement_assignment(lhs, rhs, at);
        }
    }
    expression_tree(node, at, emit);
}
fn expression_tree(node: &Expr, at: Span, emit: &mut impl Observer) {
    emit.expression(node, at);
    if let ExprKind::Binary { op, lhs, rhs } = &node.kind {
        if op == "=" {
            emit.assignment(lhs, rhs, at);
        }
    }
    if let ExprKind::Call { callee, .. } = &node.kind {
        if matches!(&callee.kind, ExprKind::StaticMember { .. }) {
            // Pinned Follow::ProcReference discards its parsed argument list.
            expression_tree(callee, at, emit);
            return;
        }
    }
    if let ExprKind::Unary { op, value } = &node.kind {
        if op == "new" {
            // Legacy New* walk visits arguments, never target mini-expressions.
            if let ExprKind::Call { args, .. } = &value.kind {
                for arg in args {
                    expression_tree(arg, at, emit);
                }
            }
            return;
        }
    }
    for_each_expression_child(node, |_, child| expression_tree(child, at, emit));
}

/// `parse_if` retains the `else` prefix in the whole span, but advances the
/// nested header past it. An ordinary `if` written inside an explicit `else`
/// block has equal starts and must remain a separate legacy statement.
fn next_arm(else_branch: &[Statement]) -> Option<&Statement> {
    let [next] = else_branch else { return None };
    (matches!(&next.kind, StatementKind::If { .. }) && next.header_span.start > next.span.start)
        .then_some(next)
}

fn statement_walk(statement: &Statement, emit: &mut impl Observer) {
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
                walk(then_branch, emit);
                match next_arm(else_branch) {
                    Some(next) => arm = next,
                    None => {
                        walk(else_branch, emit);
                        break;
                    }
                }
            }
        }
        StatementKind::While { condition, body } | StatementKind::DoWhile { condition, body } => {
            expression(condition, at, emit);
            walk(body, emit);
        }
        StatementKind::Spawn { delay, body } => {
            if let Some(delay) = delay {
                expression(delay, at, emit);
            }
            walk(body, emit);
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
            walk(body, emit);
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
                walk(&case.body, emit);
            }
            walk(else_branch, emit);
        }
        StatementKind::Try {
            body, catch_body, ..
        } => {
            walk(body, emit);
            walk(catch_body, emit);
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
                emit.statement_assignment(target, value, at);
                emit.assignment(target, value, at);
            }
            expression_tree(target, at, emit);
            expression_tree(value, at, emit);
        }
        StatementKind::Label { body, .. } => walk(body, emit),
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

#[cfg(test)]
mod statement_root_tests {
    #[test]
    fn statement_assignment_observer_excludes_nested_arguments_and_rhs_assignments() {
        let source="/proc/test()\n    outer = inner = 1\n    call(named = 2)\n    (grouped = 3)\n    if(condition = 4)\n        body = 5\n";
        let syntax = dm_syntax::parse(source);
        assert!(syntax.diagnostics.is_empty());
        let body = dm_syntax::parse_proc_body(&syntax.items[0]);
        assert!(body.diagnostics.is_empty());
        let mut found = Vec::new();
        super::statement_assignments(&body.statements, &mut |target, _, _| {
            if let dm_syntax::ExprKind::Ident(n) = &target.kind {
                found.push(n.clone());
            }
        });
        assert_eq!(found, ["outer", "condition", "body"]);
    }
}
