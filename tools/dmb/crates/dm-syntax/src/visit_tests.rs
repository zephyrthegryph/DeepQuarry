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
        fn projected_expression(
            &mut self,
            view: crate::ProjectedExprView<'_>,
            path: &[crate::NodeStep],
        ) -> crate::VisitDecision {
            // Syntax shape/identity only, no current source lookup.
            self.expression(view.original(), path)
        }

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
        fn projected_expression(
            &mut self,
            _view: crate::ProjectedExprView<'_>,
            _path: &[crate::NodeStep],
        ) -> crate::VisitDecision {
            crate::VisitDecision::Descend
        }

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
        fn projected_expression(
            &mut self,
            view: crate::ProjectedExprView<'_>,
            path: &[crate::NodeStep],
        ) -> crate::VisitDecision {
            self.expression(view.original(), path)
        }
        fn leave_projected_expression(
            &mut self,
            view: crate::ProjectedExprView<'_>,
            path: &[crate::NodeStep],
        ) {
            self.leave_expression(view.original(), path);
        }

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

#[test]
fn projected_settings_use_same_original_root_and_current_spans_with_balanced_callbacks() {
    use std::sync::{atomic::AtomicUsize, Arc};
    struct Provider {
        root: crate::SettingExpression,
    }
    impl crate::SettingSyntaxProvider for Provider {
        fn setting(&self, _: &crate::Item) -> Result<crate::SettingStatement, crate::Diagnostic> {
            Ok(crate::SettingStatement {
                attribute: "name".into(),
                relation: "=".into(),
                value: self.root.clone(),
            })
        }
    }
    #[derive(Default)]
    struct Coordinates {
        rows: Vec<(Vec<NodeStep>, Span, std::mem::Discriminant<ExprKind>)>,
        depth: usize,
    }
    impl TypedVisitor for Coordinates {
        fn expression(&mut self, e: &Expr, p: &[NodeStep]) -> VisitDecision {
            self.depth += 1;
            self.rows
                .push((p.to_vec(), e.span, std::mem::discriminant(&e.kind)));
            VisitDecision::Descend
        }
        fn leave_expression(&mut self, _: &Expr, _: &[NodeStep]) {
            self.depth -= 1;
        }
        fn projected_expression(
            &mut self,
            v: crate::ProjectedExprView<'_>,
            p: &[NodeStep],
        ) -> VisitDecision {
            self.depth += 1;
            self.rows.push((
                p.to_vec(),
                v.current_span(),
                std::mem::discriminant(&v.original().kind),
            ));
            VisitDecision::Descend
        }
        fn leave_projected_expression(&mut self, _: crate::ProjectedExprView<'_>, _: &[NodeStep]) {
            self.depth -= 1;
        }
    }
    let rhs = "\"[call()]\"";
    let lexical = crate::lex_spans(rhs);
    let counter = Arc::new(AtomicUsize::new(0));
    let checkpoint = || Ok(());
    let admission = crate::SettingAdmission::new(&counter, 8 * 1024 * 1024, &checkpoint);
    let canonical = crate::prepare_setting_expression(
        rhs,
        &lexical.tokens,
        Span::new(0, rhs.len()),
        &admission,
    )
    .unwrap();
    let ptr = canonical.original_expression() as *const Expr;
    for padding in ["", "\n\n", "// é\n"] {
        let source = format!("{padding}/proc/p()\n    set name = {rhs}\n    return 1\n");
        let full = crate::parse(&source);
        let proc = &full.items[0];
        let at = source.find(rhs).unwrap();
        let projected = canonical.clone().project_current(at, rhs.len()).unwrap();
        let provider = Provider { root: projected };
        let owned = crate::parse_body_items_with_source(&proc.children, &source);
        let current = crate::parse_body_items_with_context_and_settings(
            &proc.children,
            &source,
            &|_| None,
            &provider,
            &admission,
        );
        assert!(owned.diagnostics.is_empty() && current.diagnostics.is_empty());
        assert!(matches!(
            owned.statements[0].kind,
            StatementKind::Set { .. }
        ));
        let StatementKind::ProjectedSet { value, .. } = &current.statements[0].kind else {
            panic!("native storage variant")
        };
        assert!(value.same_root(&canonical));
        assert_eq!(value.original_expression() as *const Expr, ptr);
        let mut left = Coordinates::default();
        let mut right = Coordinates::default();
        let a = visit_statements(&owned.statements, &mut left);
        let b = visit_statements(&current.statements, &mut right);
        assert_eq!(left.rows, right.rows);
        assert_eq!(a, b);
        assert_eq!((left.depth, right.depth), (0, 0));
    }
}
#[test]
fn native_setting_provider_refusal_never_retries_ordinary_set_text() {
    struct Refuse;
    impl crate::SettingSyntaxProvider for Refuse {
        fn setting(
            &self,
            item: &crate::Item,
        ) -> Result<crate::SettingStatement, crate::Diagnostic> {
            Err(crate::Diagnostic {
                span: item.header_span,
                kind: crate::DiagnosticKind::Statement,
                message: "actual original provider refusal".into(),
            })
        }
    }
    let source = "/proc/p()\n    set name = 7\n    return 1\n";
    let full = crate::parse(source);
    let counter = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let checkpoint = || Ok(());
    let a = crate::SettingAdmission::new(&counter, 8 * 1024 * 1024, &checkpoint);
    let native = crate::parse_body_items_with_context_and_settings(
        &full.items[0].children,
        source,
        &|_| None,
        &Refuse,
        &a,
    );
    assert!(native
        .diagnostics
        .iter()
        .any(|d| d.message == "actual original provider refusal"));
    assert!(!native.statements.iter().any(|s| s.setting().is_some()));
    let owned = crate::parse_body_items(&full.items[0].children);
    assert!(owned.diagnostics.is_empty());
    assert!(matches!(
        owned.statements[0].kind,
        StatementKind::Set { .. }
    ));
}
