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
    fn literal<'a>(
        &mut self,
        owner: &str,
        text: &'a dm_syntax::LiteralText,
        pending: &mut Vec<Node<'a>>,
    ) {
        dm_syntax::visit_setting_literal_retention(text, |pointer, payload| {
            let bytes = payload.saturating_add(2 * size_of::<usize>());
            self.buffer(owner, pointer, bytes, bytes);
        });
        if let Some((pointer, bytes)) = text.shared_storage() {
            if !self.buffer(owner, pointer, bytes, bytes) {
                return;
            }
        }
        self.string(owner, text.raw_storage());
        match text.retained_parts() {
            Some(Ok(Some(parts))) => {
                self.vec_payload(owner, &parts.template);
                if self.vec_payload(owner, &parts.expressions) {
                    pending.extend(parts.expressions.iter().map(Node::Expr));
                }
            }
            Some(Err(error)) => self.string(owner, error),
            _ => (),
        }
    }

    pub(crate) fn typed_body(&mut self, owner: &str, body: &dm_tree::frontend::StatementBody) {
        body.visit_literal_admission_storage(|pointer,payload|{let bytes=payload.saturating_add(2*size_of::<usize>());self.buffer(owner,pointer,bytes,bytes);});
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
        let mut pending = Vec::new();
        self.vec_payload(owner, &parsed.control_origins);
        if self.vec_payload(owner, parsed.local_variables.storage()) {
            for local in parsed.local_variables.storage() {
                self.slice(owner, &local.type_components, true);
                if let Some(array) = &local.array_syntax {
                    self.slice(owner, &array.root.brackets, true);
                    self.slice(owner, &array.root.dimension_slots, true);
                    if self.slice(owner, &array.root.dimensions, true) {
                        pending.extend(array.root.dimensions.iter().map(Node::Expr));
                    }
                }
            }
        }
        self.vec_payload(owner, &parsed.pending_bodies);
        if self.vec_payload(owner, &parsed.diagnostics) {
            for diagnostic in &parsed.diagnostics {
                self.string(owner, &diagnostic.message);
            }
        }
        statements(self, owner, &parsed.statements, &mut pending);
        self.typed_nodes(owner, pending);
    }
    pub(crate) fn parameter_expressions(
        &mut self,
        owner: &str,
        signature: &dm_syntax::ParameterSignature,
    ) {
        let mut pending = Vec::new();
        signature.visit_expression_roots(|expr| pending.push(Node::Expr(expr)));
        self.typed_nodes(owner, pending);
    }
    pub(crate) fn setting_expression(&mut self, owner: &str, value: &dm_syntax::SettingExpression) {
        let mut fresh = false;
        value.visit_root_storage(|p, n| {
            let n = n.saturating_add(2 * size_of::<usize>());
            fresh |= self.buffer(owner, p, n, n);
        });
        value.visit_retention_storage(|p, n| {
            let n = n.saturating_add(2 * size_of::<usize>());
            self.buffer(owner, p, n, n);
        });
        if fresh {
            self.typed_expression(owner, value.original_expression());
        }
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
                        StatementKind::ProjectedSet {
                            attribute,
                            relation,
                            value,
                        } => {
                            self.string(owner, attribute);
                            self.string(owner, relation);
                            value.visit_retention_storage(|p, n| {
                                let n = n.saturating_add(2 * size_of::<usize>());
                                self.buffer(owner, p, n, n);
                            });
                            let mut fresh = false;
                            value.visit_root_storage(|p, n| {
                                let n = n.saturating_add(2 * size_of::<usize>());
                                fresh |= self.buffer(owner, p, n, n);
                            });
                            if fresh {
                                pending.push(Node::Expr(value.original_expression()));
                            }
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
                                ForControl::RangeImplicitArray { binding, end, step } => {
                                    self.string(owner, binding);
                                    pending.push(Node::Expr(end));
                                    pending.extend(step.iter().map(Node::Expr));
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
                    ExprKind::Ident(text) | ExprKind::TypePath(text) => self.string(owner, text),
                    ExprKind::Literal(text) => self.literal(owner, text, &mut pending),
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
                    | ExprKind::SafeMember {
                        object, selector, ..
                    } => {
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
            kind: ExprKind::Literal(text.into()),
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
            control_origins: vec![dm_syntax::ControlOrigin {
                condition: dm_syntax::Span::new(1, 2),
                opening: dm_syntax::Span::new(0, 1),
            }],
            pending_bodies: Vec::new(),
            local_variables: Default::default(),
        };
        let expected = parsed.statements.capacity() * size_of::<Statement>()
            + size_of::<Expr>()
            + 7
            + 6
            + parsed.control_origins.capacity() * size_of::<dm_syntax::ControlOrigin>();
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

#[cfg(test)]
mod local_fact_census_tests {
    use super::*;
    #[test]
    fn local_fact_vector_and_each_box_are_in_actual_typed_body_census() {
        let syntax=dm_syntax::parse("/proc/p()\n    var/SpacemanDMM_private/datum/x\n    var/SpacemanDMM_protected/list/datum/y[2]\n");
        let mut parsed = dm_syntax::parse_proc_body(&syntax.items[0]);
        let facts = parsed.local_variables.entries().unwrap();
        assert_eq!(facts.len(), 2);
        let expected = parsed.local_variables.storage().capacity()
            * size_of::<dm_syntax::LocalVariableSyntax>()
            + facts
                .iter()
                .map(|f| f.type_components.len() * size_of::<dm_syntax::Span>())
                .sum::<usize>();
        let expected = expected
            + facts
                .iter()
                .filter_map(|f| f.array_syntax.as_ref())
                .map(|array| {
                    let mut bytes = std::mem::size_of_val(array.root.brackets.as_ref())
                        + std::mem::size_of_val(array.root.dimension_slots.as_ref())
                        + std::mem::size_of_val(array.root.dimensions.as_ref());
                    for e in array.root.dimensions.iter() {
                        let ExprKind::Literal(text) = &e.kind else {
                            panic!("census fixture expects literal dimensions")
                        };
                        bytes += text.raw_storage().capacity();
                        if let Some((_, n)) = text.shared_storage() {
                            bytes += n;
                        }
                    }
                    bytes
                })
                .sum::<usize>();
        let mut before = HeapCensus::new("with_locals");
        before.typed_parsed_body("typed", &parsed);
        let before = before.finish().unique_known_capacity_bytes;
        let retained = std::mem::take(&mut parsed.local_variables);
        let mut after = HeapCensus::new("without_locals");
        after.typed_parsed_body("typed", &parsed);
        let after = after.finish().unique_known_capacity_bytes;
        assert!(expected > 0);
        assert_eq!(before - after, expected as u64);
        assert_eq!(retained.entries().unwrap().len(), 2);
    }
}

#[cfg(test)]
mod parameter_expression_census_tests {
    use super::*;
    #[test]
    fn original_formal_root_children_are_in_actual_heap_census() {
        let source = "/proc/p(x[dimension()] = make(1) as mob|obj in choose(2))\n    return x\n";
        let syntax = dm_syntax::parse_declaration_skeleton(source);
        let issued = dm_syntax::parse_proc_with_origins_from_spans(
            source,
            syntax.items[0].span,
            &syntax.tokens,
            0,
        )
        .unwrap();
        let parameters = issued.parameters;
        let mut base = HeapCensus::new("parameter_without_children");
        parameters.visit_storage(|pointer, n| {
            base.buffer("parameters", pointer, n, n);
        });
        let base = base.finish().unique_known_capacity_bytes;
        let mut complete = HeapCensus::new("parameter_with_children");
        parameters.visit_storage(|pointer, n| {
            complete.buffer("parameters", pointer, n, n);
        });
        complete.parameter_expressions("parameters", &parameters);
        let complete = complete.finish().unique_known_capacity_bytes;
        assert!(
            complete > base,
            "real nested call callee/argument owners must be visited"
        );
        assert_eq!(
            parameters.entries().unwrap()[0]
                .expressions()
                .unwrap()
                .unwrap()
                .dimensions()
                .len(),
            1
        );
    }
}
