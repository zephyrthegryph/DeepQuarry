use super::*;
use crate::{parse_expression, Span};

#[test]
fn expression_children_use_the_original_nodes_in_canonical_order() {
    let parsed = parse_expression("f(a + b, c ? d : e)");
    assert!(parsed.diagnostics.is_empty());
    let root = parsed.expr.unwrap();
    let mut direct = Vec::new();
    for_each_expression_child(&root, |index, child| direct.push((index, child)));
    assert_eq!(direct.len(), 3);
    let ExprKind::Call { callee, args } = &root.kind else {
        panic!("call expected")
    };
    assert!(std::ptr::eq(direct[0].1, &**callee));
    assert!(std::ptr::eq(direct[1].1, &args[0]));
    assert!(std::ptr::eq(direct[2].1, &args[1]));
    assert_eq!(
        direct.iter().map(|(i, _)| *i).collect::<Vec<_>>(),
        [0, 1, 2]
    );
    struct Record(Vec<Vec<NodeStep>>);
    impl TypedVisitor for Record {
        fn expression(&mut self, _: &Expr, path: &[NodeStep]) -> VisitDecision {
            self.0.push(path.to_vec());
            VisitDecision::Descend
        }
    }
    let mut visitor = Record(Vec::new());
    let report = visit_expression(&root, &mut visitor);
    assert_eq!(report.expressions, 9);
    assert!(visitor
        .0
        .contains(&vec![NodeStep::Child(2), NodeStep::Child(2)]));
}

#[test]
fn skip_and_stop_preserve_statement_order_and_do_not_visit_hidden_children() {
    let expression = parse_expression("a + b").expr.unwrap();
    let statement = |kind| Statement {
        kind,
        span: Span::new(0, 5),
        header_span: Span::new(0, 5),
        raw_header: "test".into(),
    };
    let nodes = vec![
        statement(StatementKind::If {
            condition: expression.clone(),
            then_branch: vec![statement(StatementKind::Unsupported)],
            else_branch: Vec::new(),
        }),
        statement(StatementKind::Return(Some(expression))),
        statement(StatementKind::Unsupported),
    ];
    struct Filter(Vec<Vec<NodeStep>>);
    impl TypedVisitor for Filter {
        fn statement(&mut self, _: &Statement, path: &[NodeStep]) -> VisitDecision {
            self.0.push(path.to_vec());
            if path == [NodeStep::Statement(0)] {
                VisitDecision::Skip
            } else {
                VisitDecision::Stop
            }
        }
    }
    let mut visitor = Filter(Vec::new());
    let report = visit_statements(&nodes, &mut visitor);
    assert_eq!(
        visitor.0,
        [vec![NodeStep::Statement(0)], vec![NodeStep::Statement(1)]]
    );
    assert_eq!(report.statements, 2);
    assert_eq!(report.expressions, 0);
    assert_eq!(report.unsupported_statements, 0);
    assert!(report.stopped);
}

#[test]
fn masked_authored_paths_and_scope_callbacks_remain_balanced_on_stop() {
    let child = Statement {
        kind: StatementKind::Return(Some(parse_expression("x").expr.unwrap())),
        span: Span::new(20, 28),
        header_span: Span::new(20, 28),
        raw_header: "return x".into(),
    };
    let nodes = vec![
        Statement {
            kind: StatementKind::Unsupported,
            span: Span::new(0, 3),
            header_span: Span::new(0, 3),
            raw_header: "set".into(),
        },
        Statement {
            kind: StatementKind::While {
                condition: parse_expression("1").expr.unwrap(),
                body: vec![child],
            },
            span: Span::new(5, 28),
            header_span: Span::new(5, 15),
            raw_header: "while(1)".into(),
        },
    ];
    let mask = crate::StatementMask::from_predicate(&nodes, |node| node.header_span.start == 0);
    #[derive(Default)]
    struct Balanced {
        statements: usize,
        expressions: usize,
        branches: usize,
        seen: Vec<Vec<NodeStep>>,
    }
    impl TypedVisitor for Balanced {
        fn statement(&mut self, _: &Statement, path: &[NodeStep]) -> VisitDecision {
            self.statements += 1;
            self.seen.push(path.to_vec());
            VisitDecision::Descend
        }
        fn leave_statement(&mut self, _: &Statement, _: &[NodeStep]) {
            self.statements -= 1;
        }
        fn expression(&mut self, node: &Expr, _: &[NodeStep]) -> VisitDecision {
            self.expressions += 1;
            if matches!(&node.kind, ExprKind::Ident(_)) {
                VisitDecision::Stop
            } else {
                VisitDecision::Descend
            }
        }
        fn leave_expression(&mut self, _: &Expr, _: &[NodeStep]) {
            self.expressions -= 1;
        }
        fn enter_branch(&mut self, _: &Statement, _: usize, _: &[NodeStep]) {
            self.branches += 1;
        }
        fn leave_branch(&mut self, _: &Statement, _: usize, _: &[NodeStep]) {
            self.branches -= 1;
        }
    }
    let mut visitor = Balanced::default();
    let report = visit_statement_view(crate::StatementView::masked(&nodes, &mask), &mut visitor);
    assert!(report.stopped);
    assert_eq!(
        (visitor.statements, visitor.expressions, visitor.branches),
        (0, 0, 0)
    );
    assert_eq!(visitor.seen[0], [NodeStep::Statement(1)]);
    assert_eq!(
        visitor.seen[1],
        [
            NodeStep::Statement(1),
            NodeStep::Branch(0),
            NodeStep::Statement(0)
        ]
    );
    assert_eq!(report.unsupported_statements, 0);
}
