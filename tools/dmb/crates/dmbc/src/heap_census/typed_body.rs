//! Borrow typed body ownership without parsing, copying, or counting inline nodes twice.
use super::*;
use dm_syntax::{
    Expr, ExprKind, ForControl, ForInitializer, Statement, StatementKind, SwitchAlternative,
};
enum Node<'a> {
    Statement(&'a Statement),
    Expr(&'a Expr),
}
fn statements<'a>(
    c: &mut HeapCensus,
    owner: &str,
    values: &'a Vec<Statement>,
    pending: &mut Vec<Node<'a>>,
) {
    if c.vec_payload(owner, values) {
        pending.extend(values.iter().map(Node::Statement));
    }
}
fn boxed<'a>(c: &mut HeapCensus, owner: &str, value: &'a Expr, pending: &mut Vec<Node<'a>>) {
    if c.buffer(
        owner,
        value as *const Expr as usize,
        size_of::<Expr>(),
        size_of::<Expr>(),
    ) {
        pending.push(Node::Expr(value));
    }
}
impl HeapCensus {
    pub(crate) fn typed_body(&mut self, owner: &str, body: &dm_tree::frontend::StatementBody) {
        // HashSet buckets and controls are private; report logical entries as lower bounds.
        let (headers, capacity) = body.declaration_header_storage();
        if capacity != 0 {
            self.unknown(
                owner,
                "typed declaration-header HashSet bucket/control allocation capacity is opaque",
            );
        }
        self.collection_entries::<(usize, usize)>(owner, body as *const _ as usize, headers);
        self.typed_parsed_body(owner, body.parsed());
    }
    fn typed_parsed_body(&mut self, owner: &str, parsed: &dm_syntax::ParsedBody) {
        if self.vec_payload(owner, &parsed.diagnostics) {
            for diagnostic in &parsed.diagnostics {
                self.string(owner, &diagnostic.message);
            }
        }
        let mut pending = Vec::new();
        statements(self, owner, &parsed.statements, &mut pending);
        self.typed_nodes(owner, pending);
    }
    pub(crate) fn typed_expression(&mut self, owner: &str, expression: &Expr) {
        // The root is inline in its containing owner; only nested allocations count.
        self.typed_nodes(owner, vec![Node::Expr(expression)]);
    }
    fn typed_nodes(&mut self, owner: &str, mut pending: Vec<Node<'_>>) {
        while let Some(node) = pending.pop() {
            match node {
                Node::Statement(statement) => {
                    self.string(owner, &statement.raw_header);
                    match &statement.kind {
                        StatementKind::If {
                            condition,
                            then_branch,
                            else_branch,
                        } => {
                            pending.push(Node::Expr(condition));
                            statements(self, owner, then_branch, &mut pending);
                            statements(self, owner, else_branch, &mut pending);
                        }
                        StatementKind::While { condition, body }
                        | StatementKind::DoWhile { condition, body } => {
                            pending.push(Node::Expr(condition));
                            statements(self, owner, body, &mut pending);
                        }
                        StatementKind::Spawn { delay, body } => {
                            pending.extend(delay.iter().map(Node::Expr));
                            statements(self, owner, body, &mut pending);
                        }
                        StatementKind::Set {
                            attribute,
                            relation,
                            value,
                        } => {
                            self.string(owner, attribute);
                            self.string(owner, relation);
                            pending.push(Node::Expr(value));
                        }
                        StatementKind::For { control, body } => {
                            statements(self, owner, body, &mut pending);
                            match control {
                                ForControl::All { declaration } => self.string(owner, declaration),
                                ForControl::Each { binding, iterable } => {
                                    self.string(owner, binding);
                                    pending.push(Node::Expr(iterable));
                                }
                                ForControl::Pair {
                                    key_binding,
                                    value_binding,
                                    iterable,
                                } => {
                                    self.string(owner, key_binding);
                                    self.string(owner, value_binding);
                                    pending.push(Node::Expr(iterable));
                                }
                                ForControl::Range {
                                    binding,
                                    start,
                                    end,
                                    step,
                                } => {
                                    self.string(owner, binding);
                                    pending.extend([Node::Expr(start), Node::Expr(end)]);
                                    pending.extend(step.iter().map(Node::Expr));
                                }
                                ForControl::CStyle {
                                    initializer,
                                    condition,
                                    step,
                                } => {
                                    match initializer {
                                        Some(ForInitializer::Declare { declaration, value }) => {
                                            self.string(owner, declaration);
                                            pending.extend(value.iter().map(Node::Expr));
                                        }
                                        Some(ForInitializer::Expr(value)) => {
                                            pending.push(Node::Expr(value))
                                        }
                                        None => {}
                                    }
                                    pending.extend(
                                        condition.iter().chain(step.iter()).map(Node::Expr),
                                    );
                                }
                            }
                        }
                        StatementKind::Switch {
                            selector,
                            cases,
                            else_branch,
                        } => {
                            pending.push(Node::Expr(selector));
                            statements(self, owner, else_branch, &mut pending);
                            if self.vec_payload(owner, cases) {
                                for case in cases {
                                    statements(self, owner, &case.body, &mut pending);
                                    if self.vec_payload(owner, &case.alternatives) {
                                        for alternative in &case.alternatives {
                                            match alternative {
                                                SwitchAlternative::Exact(value) => {
                                                    pending.push(Node::Expr(value))
                                                }
                                                SwitchAlternative::Range(start, end) => pending
                                                    .extend([Node::Expr(start), Node::Expr(end)]),
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        StatementKind::Try {
                            body,
                            catch_binding,
                            catch_header_span: _,
                            catch_body,
                        } => {
                            statements(self, owner, body, &mut pending);
                            statements(self, owner, catch_body, &mut pending);
                            if let Some(binding) = catch_binding {
                                self.string(owner, binding);
                            }
                        }
                        StatementKind::Label { name, body } => {
                            self.string(owner, name);
                            statements(self, owner, body, &mut pending);
                        }
                        StatementKind::Goto(name)
                        | StatementKind::BreakLabel(name)
                        | StatementKind::ContinueLabel(name) => self.string(owner, name),
                        StatementKind::Return(value) => {
                            pending.extend(value.iter().map(Node::Expr))
                        }
                        StatementKind::Var { declaration, value } => {
                            self.string(owner, declaration);
                            pending.extend(value.iter().map(Node::Expr));
                        }
                        StatementKind::Assign { target, op, value } => {
                            self.string(owner, op);
                            pending.extend([Node::Expr(target), Node::Expr(value)]);
                        }
                        StatementKind::Throw(value)
                        | StatementKind::Call(value)
                        | StatementKind::Expression(value) => pending.push(Node::Expr(value)),
                        StatementKind::Break
                        | StatementKind::Continue
                        | StatementKind::Unsupported => {}
                    }
                }
                Node::Expr(value) => match &value.kind {
                    ExprKind::Ident(text) | ExprKind::Literal(text) | ExprKind::TypePath(text) => {
                        self.string(owner, text)
                    }
                    ExprKind::Unary { op, value } => {
                        self.string(owner, op);
                        boxed(self, owner, value, &mut pending);
                    }
                    ExprKind::Binary { op, lhs, rhs } => {
                        self.string(owner, op);
                        boxed(self, owner, lhs, &mut pending);
                        boxed(self, owner, rhs, &mut pending);
                    }
                    ExprKind::Conditional {
                        condition,
                        then_value,
                        else_value,
                    } => {
                        for value in [condition, then_value, else_value] {
                            boxed(self, owner, value, &mut pending);
                        }
                    }
                    ExprKind::Call { callee, args } => {
                        boxed(self, owner, callee, &mut pending);
                        if self.vec_payload(owner, args) {
                            pending.extend(args.iter().map(Node::Expr));
                        }
                    }
                    ExprKind::Member {
                        object, selector, ..
                    }
                    | ExprKind::StaticMember { object, selector }
                    | ExprKind::SafeMember { object, selector } => {
                        self.string(owner, selector);
                        boxed(self, owner, object, &mut pending);
                    }
                    ExprKind::TypeFilter { value, types } => {
                        boxed(self, owner, value, &mut pending);
                        self.strings(owner, types);
                    }
                    ExprKind::ObjectInitializer { object, fields } => {
                        boxed(self, owner, object, &mut pending);
                        if self.vec_payload(owner, fields) {
                            for (name, value) in fields {
                                self.string(owner, name);
                                pending.push(Node::Expr(value));
                            }
                        }
                    }
                    ExprKind::Index { object, index } | ExprKind::SafeIndex { object, index } => {
                        boxed(self, owner, object, &mut pending);
                        boxed(self, owner, index, &mut pending);
                    }
                    ExprKind::Group(value) => boxed(self, owner, value, &mut pending),
                },
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn typed_nested_boxes_vectors_and_strings_are_counted_once() {
        let text = String::from("payload");
        let inner = Box::new(Expr {
            kind: ExprKind::Literal(text),
            span: dm_syntax::Span::new(0, 7),
        });
        let parsed = dm_syntax::ParsedBody {
            statements: vec![Statement {
                kind: StatementKind::Return(Some(Expr {
                    kind: ExprKind::Group(inner),
                    span: dm_syntax::Span::new(0, 7),
                })),
                span: dm_syntax::Span::new(0, 7),
                header_span: dm_syntax::Span::new(0, 7),
                raw_header: String::from("return"),
            }],
            diagnostics: Vec::new(),
        };
        let expected =
            parsed.statements.capacity() * size_of::<Statement>() + size_of::<Expr>() + 7 + 6;
        let mut census = HeapCensus::new("test");
        census.typed_parsed_body("typed", &parsed);
        census.typed_parsed_body("alias", &parsed);
        let report = census.finish();
        assert_eq!(report.unique_known_capacity_bytes, expected as u64);
        assert!(
            report
                .owners
                .iter()
                .find(|row| row.owner == "alias")
                .unwrap()
                .shared_encounters
                > 0
        );
    }
}
