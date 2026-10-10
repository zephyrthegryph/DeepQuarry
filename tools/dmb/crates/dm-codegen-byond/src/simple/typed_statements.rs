//! Typed statements lowering over the shared compiler context.
use super::*;
#[path = "typed_delete.rs"]
mod deletion;
#[path = "local_array_initializers.rs"]
mod local_array_initializers;

impl Compiler<'_> {
    pub(super) fn typed_statements_inner(
        &mut self,
        statements: &[Statement],
    ) -> Result<(), LowerError> {
        for statement in statements {
            if !self.statement_visible(statement) {
                continue;
            }
            let scoped_statement = matches!(
                &statement.kind,
                StatementKind::For { .. } | StatementKind::Try { .. }
            );
            let saved_slots = scoped_statement.then(|| self.local_slots.checkpoint());
            let saved_types = scoped_statement.then(|| self.local_types.checkpoint());
            self.debug_at(statement.header_span.start, &statement.raw_header)?;
            match &statement.kind {
                StatementKind::Set { .. } => {
                    return Err(error(
                        &statement.raw_header,
                        "procedure setting was not normalized",
                    ));
                }
                StatementKind::Return(None) => self.emit(opcode::END, vec![]),
                StatementKind::Return(Some(value)) => {
                    self.expression(value, &statement.raw_header)?;
                    self.emit(opcode::RET, vec![]);
                }
                StatementKind::Throw(value) => {
                    self.expression(value, &statement.raw_header)?;
                    self.emit(0x12d, vec![]);
                }
                StatementKind::Label { name, body } => {
                    let label = self
                        .user_labels
                        .get(name)
                        .copied()
                        .ok_or_else(|| error(&statement.raw_header, "undefined label"))?;
                    self.result.code.items.push(CodeItem::Label(label));
                    let end = self.label();
                    let prior_break = self.label_breaks.insert(name.clone(), end);
                    let prior_depth = self
                        .label_loop_depths
                        .insert(name.clone(), self.loops.len());
                    let is_iterator_loop =
                        self.statement_view(body).first().is_some_and(|statement| {
                            matches!(
                                &statement.kind,
                                StatementKind::For {
                                    control: ForControl::Each { .. }
                                        | ForControl::Pair { .. }
                                        | ForControl::All { .. },
                                    ..
                                }
                            )
                        });
                    let target_iterator_depth = self.iterator_depth + usize::from(is_iterator_loop);
                    let prior_iterator_depth = self
                        .label_iterator_depths
                        .insert(name.clone(), target_iterator_depth);
                    self.typed_statements(body)?;
                    if let Some(prior) = prior_break {
                        self.label_breaks.insert(name.clone(), prior);
                    } else {
                        self.label_breaks.remove(name);
                    }
                    if let Some(prior) = prior_depth {
                        self.label_loop_depths.insert(name.clone(), prior);
                    } else {
                        self.label_loop_depths.remove(name);
                    }
                    if let Some(prior) = prior_iterator_depth {
                        self.label_iterator_depths.insert(name.clone(), prior);
                    } else {
                        self.label_iterator_depths.remove(name);
                    }
                    self.result.code.items.push(CodeItem::Label(end));
                }
                StatementKind::Goto(name) => {
                    let label = self
                        .user_labels
                        .get(name)
                        .copied()
                        .ok_or_else(|| error(&statement.raw_header, "undefined goto label"))?;
                    let depth = *self.label_try_depths.get(&label).unwrap_or(&0);
                    if depth > self.try_depth {
                        return Err(error(
                            &statement.raw_header,
                            "goto into protected try body is unsupported",
                        ));
                    }
                    let target_iterator_depth =
                        *self.user_label_iterator_depths.get(name).ok_or_else(|| {
                            error(
                                &statement.raw_header,
                                "goto label iterator depth is unknown",
                            )
                        })?;
                    if target_iterator_depth > self.iterator_depth {
                        return Err(error(
                            &statement.raw_header,
                            "goto into iterator body is unsupported",
                        ));
                    }
                    for _ in target_iterator_depth.max(1)..self.iterator_depth {
                        self.emit(opcode::ITER_POP, vec![]);
                    }
                    self.emit(
                        if self.try_depth > 0 {
                            // Authored protected gotos use TryJmp, even when
                            // their target remains inside the same try frame.
                            0x12f
                        } else {
                            // Authored forward and backward gotos both perform
                            // native budget dispatch; synthetic routing uses JMP.
                            opcode::JMP_LOOP
                        },
                        vec![Word::Branch(label)],
                    );
                }
                StatementKind::Call(value) if matches!(&value.kind, ExprKind::Call { callee, args } if matches!(&callee.kind, ExprKind::Ident(name) if name == "sleep") && args.len() == 1) =>
                {
                    let ExprKind::Call { args, .. } = &value.kind else {
                        unreachable!()
                    };
                    self.expression(&args[0], &statement.raw_header)?;
                    self.emit(opcode::SLEEP, vec![]);
                }
                StatementKind::Call(value) if matches!(&value.kind, ExprKind::Call { callee, args } if matches!(&callee.kind, ExprKind::Ident(name) if name == "del") && args.len() == 1) =>
                {
                    let ExprKind::Call { args, .. } = &value.kind else {
                        unreachable!()
                    };
                    if self.typed_delete(&args[0], &statement.raw_header)? {
                        break;
                    }
                }
                StatementKind::Expression(value) if matches!(&value.kind, ExprKind::Binary { op, .. } if op == "<<") =>
                {
                    self.output_statement(value, &statement.raw_header)?;
                }
                StatementKind::Call(value) | StatementKind::Expression(value) => {
                    if self.crash_statement(value, &statement.raw_header)? {
                        continue;
                    }
                    if self.output_statement(value, &statement.raw_header)? {
                        continue;
                    }
                    if self.builtin_statement(value, &statement.raw_header)? {
                        continue;
                    }
                    if let ExprKind::Binary { op, lhs, rhs } = &value.kind {
                        if op == "||=" || op == "&&=" {
                            self.assign_expr(lhs, op, rhs, &statement.raw_header)?;
                            continue;
                        }
                    }
                    if let ExprKind::Unary { op, value } = &value.kind {
                        if matches!(op.as_str(), "post++" | "post--" | "pre++" | "pre--") {
                            self.inc_dec(
                                value,
                                if op.ends_with("++") { 0x66 } else { 0x67 },
                                &statement.raw_header,
                            )?;
                            continue;
                        }
                    }
                    self.discarded_expression(value, &statement.raw_header)?;
                }
                StatementKind::Assign { target, op, value } => {
                    self.assign_expr(target, op, value, &statement.raw_header)?;
                }
                StatementKind::Var { declaration, value } => {
                    let name = local_name(declaration).ok_or_else(|| {
                        error(&statement.raw_header, "unsupported local declaration")
                    })?;
                    if name.is_empty() {
                        return Err(error(
                            &statement.raw_header,
                            "unsupported local declaration",
                        ));
                    }
                    if self.local_slots.contains_key(name) {
                        let mut failure = error(
                            &statement.raw_header,
                            &format!("{name}: duplicate definition"),
                        );
                        failure.kind = LowerErrorKind::SourceError;
                        if let Some(previous) = self
                            .local_slots
                            .get(name)
                            .and_then(|slot| self.local_declarations.get(slot))
                        {
                            failure.related.push(LowerRelated {
                                span: *previous,
                                message: format!("{name}: previous definition"),
                            });
                        }
                        return Err(failure.at(Some(LowerSpan {
                            start: statement.header_span.start,
                            end: statement.header_span.end,
                        })));
                    }
                    let slot = self.locals.len() as u32;
                    self.locals.push(name.into());
                    self.local_slots.insert(name.into(), slot);
                    self.local_declarations.insert(
                        slot,
                        LowerSpan {
                            start: statement.header_span.start,
                            end: statement.header_span.end,
                        },
                    );
                    if let Some(dimensions) = local_array_dimensions(declaration) {
                        self.local_array_declaration(
                            &dimensions,
                            slot,
                            &statement.raw_header,
                            value.as_ref().map(|value| {
                                |compiler: &mut Self| {
                                    compiler.local_declaration_initializer(
                                        value,
                                        declaration,
                                        &statement.raw_header,
                                    )
                                }
                            }),
                        )?;
                        continue;
                    }
                    if let Some((path, _)) = declaration
                        .strip_prefix("var/")
                        .and_then(|raw| raw.rsplit_once('/'))
                    {
                        self.local_types
                            .insert(name.into(), runtime_declaration_path(path));
                    } else if declaration.trim_end().ends_with("[]") {
                        self.local_types.insert(name.into(), "/list".into());
                    }
                    if let Some(value) = value {
                        self.local_declaration_initializer(
                            value,
                            declaration,
                            &statement.raw_header,
                        )?;
                        self.emit(
                            opcode::SET_VAR,
                            vec![Word::Variable(VariableWord::Local(slot))],
                        );
                    } else if !self.loops.is_empty() {
                        self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                        self.emit(
                            opcode::SET_VAR,
                            vec![Word::Variable(VariableWord::Local(slot))],
                        );
                    }
                }
                StatementKind::While { condition, body } => {
                    let start = self.label();
                    let end = self.label();
                    self.result.code.items.push(CodeItem::Label(start));
                    self.condition(condition, &statement.raw_header)?;
                    self.emit(opcode::JZ, vec![Word::Branch(end)]);
                    self.loops.push((start, end));
                    self.breaks.push(end);
                    let result = self.typed_statements(body);
                    self.loops.pop();
                    self.breaks.pop();
                    result?;
                    self.emit(opcode::JMP_LOOP, vec![Word::Branch(start)]);
                    self.result.code.items.push(CodeItem::Label(end));
                }
                StatementKind::DoWhile { body, condition } => {
                    let start = self.label();
                    let continue_label = self.label();
                    let end = self.label();
                    self.result.code.items.push(CodeItem::Label(start));
                    self.loops.push((continue_label, end));
                    self.breaks.push(end);
                    let result = self.typed_statements(body);
                    self.loops.pop();
                    self.breaks.pop();
                    result?;
                    self.result.code.items.push(CodeItem::Label(continue_label));
                    self.condition(condition, &statement.raw_header)?;
                    self.emit(0xf9, vec![Word::Branch(start)]);
                    self.result.code.items.push(CodeItem::Label(end));
                }
                StatementKind::Spawn { delay, body } => {
                    if let Some(delay) = delay {
                        self.expression(delay, &statement.raw_header)?;
                    } else {
                        self.emit(opcode::PUSH_INT, vec![Word::Immediate(0)]);
                    }
                    let end = self.label();
                    self.emit(0x25, vec![Word::Branch(end)]);
                    self.typed_statements(body)?;
                    self.emit(opcode::END, vec![]);
                    self.result.code.items.push(CodeItem::Label(end));
                }
                StatementKind::For {
                    control: ForControl::All { declaration },
                    body,
                } => {
                    let name = local_name(declaration).ok_or_else(|| {
                        error(&statement.raw_header, "world iterator must declare a local")
                    })?;
                    let raw = declaration.strip_prefix("var/").ok_or_else(|| {
                        error(&statement.raw_header, "world iterator requires a type")
                    })?;
                    let (type_name, _) = raw.rsplit_once('/').ok_or_else(|| {
                        error(&statement.raw_header, "world iterator requires a type")
                    })?;
                    let path = runtime_declaration_path(type_name);
                    let tag = self.class_tag(&path)?.ok_or_else(|| {
                        error(&statement.raw_header, "unsupported world iterator type")
                    })?;
                    if self.local_slots.contains_key(name) {
                        return Err(error(&statement.raw_header, "repeated iterator binding"));
                    }
                    let slot = self.locals.len() as u32;
                    self.locals.push(name.into());
                    self.local_slots.insert(name.into(), slot);
                    self.local_types.insert(name.into(), path.clone());
                    self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                    self.emit(
                        opcode::SET_VAR,
                        vec![Word::Variable(VariableWord::Local(slot))],
                    );
                    self.emit(opcode::GET_VAR, vec![Word::Variable(VariableWord::World)]);
                    if self.seen_classes.insert(SymbolId::of(&path)) {
                        self.result.class_paths.push(SymbolId::of(&path));
                    }
                    self.emit(
                        opcode::PUSH_VAL,
                        vec![Word::Value(ValueWord::ClassPath {
                            path: SymbolId::of(&path),
                            tag,
                        })],
                    );
                    if self.iterator_depth > 0 {
                        self.emit(opcode::ITER_PUSH, vec![]);
                    }
                    self.emit(
                        opcode::ITER_LOAD,
                        vec![Word::Immediate(5), Word::Immediate(0x4000)],
                    );
                    let start = self.label();
                    let end = self.label();
                    self.result.code.items.push(CodeItem::Label(start));
                    self.emit(opcode::ITER_NEXT, vec![]);
                    self.emit(
                        opcode::SET_VAR,
                        vec![Word::Variable(VariableWord::Local(slot))],
                    );
                    self.emit(opcode::JZ, vec![Word::Branch(end)]);
                    self.iterator_depth += 1;
                    self.loops.push((start, end));
                    self.breaks.push(end);
                    let result = self.typed_statements(body);
                    self.breaks.pop();
                    self.loops.pop();
                    self.iterator_depth -= 1;
                    result?;
                    self.emit(opcode::JMP_LOOP, vec![Word::Branch(start)]);
                    self.result.code.items.push(CodeItem::Label(end));
                    if self.iterator_depth > 0 {
                        self.emit(opcode::ITER_POP, vec![]);
                    }
                }
                StatementKind::For {
                    control: ForControl::Each { binding, iterable },
                    body,
                } => {
                    let (binding, explicit_mask) =
                        if let Some((name, filter)) = binding.rsplit_once(" as ") {
                            let mask = filter
                                .split('|')
                                .map(str::trim)
                                .try_fold(0u32, |mask, part| {
                                    Some(
                                        mask | match part {
                                            "anything" => 0x1000,
                                            "mob" => 1,
                                            "obj" => 2,
                                            "turf" => 32,
                                            _ => return None,
                                        },
                                    )
                                })
                                .ok_or_else(|| {
                                    error(&statement.raw_header, "unsupported iterator type filter")
                                })?;
                            (name.trim(), Some(mask))
                        } else {
                            (binding.trim(), None)
                        };
                    let mask = explicit_mask.unwrap_or_else(|| {
                        let path = binding.strip_prefix("var/").unwrap_or(binding);
                        match path.split('/').next().unwrap_or("") {
                            "mob" => 1,
                            "obj" => 2,
                            "turf" => 32,
                            _ => 0,
                        }
                    });
                    let binding_variable = if let Some(name) = local_name(binding) {
                        if self.local_slots.contains_key(name) {
                            return Err(error(&statement.raw_header, "repeated iterator binding"));
                        }
                        let slot = self.locals.len() as u32;
                        self.locals.push(name.into());
                        self.local_slots.insert(name.into(), slot);
                        if let Some((path, _)) = binding
                            .strip_prefix("var/")
                            .and_then(|raw| raw.rsplit_once('/'))
                        {
                            self.local_types
                                .insert(name.into(), runtime_declaration_path(path));
                        }
                        self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                        self.emit(
                            opcode::SET_VAR,
                            vec![Word::Variable(VariableWord::Local(slot))],
                        );
                        VariableWord::Local(slot)
                    } else {
                        self.variable(binding, &statement.raw_header)?
                    };
                    self.ensure_writable(&binding_variable, &statement.raw_header)?;
                    self.expression(iterable, &statement.raw_header)?;
                    if self.iterator_depth > 0 {
                        self.emit(opcode::ITER_PUSH, vec![]);
                    }
                    self.emit(
                        opcode::ITER_LOAD,
                        vec![Word::Immediate(5), Word::Immediate(mask)],
                    );
                    let start = self.label();
                    let end = self.label();
                    self.result.code.items.push(CodeItem::Label(start));
                    self.emit(opcode::ITER_NEXT, vec![]);
                    self.emit(
                        opcode::SET_VAR,
                        vec![Word::Variable(binding_variable.clone())],
                    );
                    self.emit(opcode::JZ, vec![Word::Branch(end)]);
                    if mask == 0
                        || (explicit_mask.is_none()
                            && binding
                                .strip_prefix("var/")
                                .and_then(|raw| raw.rsplit_once('/'))
                                .is_some_and(|(path, _)| path.contains('/')))
                    {
                        if let Some((type_name, _)) = binding
                            .strip_prefix("var/")
                            .and_then(|raw| raw.rsplit_once('/'))
                        {
                            let path = runtime_declaration_path(type_name);
                            let tag = self.class_tag(&path)?.ok_or_else(|| {
                                error(&statement.raw_header, "unsupported iterator type")
                            })?;
                            if self.seen_classes.insert(SymbolId::of(&path)) {
                                self.result.class_paths.push(SymbolId::of(&path));
                            }
                            self.emit(
                                opcode::GET_VAR,
                                vec![Word::Variable(binding_variable.clone())],
                            );
                            self.emit(
                                opcode::PUSH_VAL,
                                vec![Word::Value(ValueWord::ClassPath {
                                    path: SymbolId::of(&path),
                                    tag,
                                })],
                            );
                            self.emit(0x7d, vec![]);
                            self.emit(opcode::TEST, vec![]);
                            self.emit(0xfa, vec![Word::Branch(start)]);
                        }
                    }
                    self.iterator_depth += 1;
                    self.loops.push((start, end));
                    self.breaks.push(end);
                    let result = self.typed_statements(body);
                    self.breaks.pop();
                    self.loops.pop();
                    self.iterator_depth -= 1;
                    result?;
                    self.emit(opcode::JMP_LOOP, vec![Word::Branch(start)]);
                    self.result.code.items.push(CodeItem::Label(end));
                    if self.iterator_depth > 0 {
                        self.emit(opcode::ITER_POP, vec![]);
                    }
                }
                StatementKind::For {
                    control:
                        ForControl::Pair {
                            key_binding,
                            value_binding,
                            iterable,
                        },
                    body,
                } => {
                    let mut pair = Vec::with_capacity(2);
                    for binding in [key_binding, value_binding] {
                        let name = local_name(binding).unwrap_or(binding);
                        let variable = if binding.starts_with("var/")
                            || (!self.local_slots.contains_key(name)
                                && !self.bindings.parameters.iter().any(|param| param == name))
                        {
                            if self.local_slots.contains_key(name) {
                                return Err(error(
                                    &statement.raw_header,
                                    "repeated iterator binding",
                                ));
                            }
                            let slot = self.locals.len() as u32;
                            self.locals.push(name.into());
                            self.local_slots.insert(name.into(), slot);
                            if let Some((path, _)) = binding
                                .strip_prefix("var/")
                                .and_then(|raw| raw.rsplit_once('/'))
                            {
                                self.local_types
                                    .insert(name.into(), runtime_declaration_path(path));
                            }
                            self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                            self.emit(
                                opcode::SET_VAR,
                                vec![Word::Variable(VariableWord::Local(slot))],
                            );
                            VariableWord::Local(slot)
                        } else {
                            self.variable(name, &statement.raw_header)?
                        };
                        self.ensure_writable(&variable, &statement.raw_header)?;
                        pair.push(variable);
                    }
                    self.expression(iterable, &statement.raw_header)?;
                    if self.iterator_depth > 0 {
                        self.emit(opcode::ITER_PUSH, vec![]);
                    }
                    self.emit(
                        opcode::ITER_LOAD,
                        vec![Word::Immediate(20), Word::Immediate(0)],
                    );
                    let start = self.label();
                    let end = self.label();
                    self.result.code.items.push(CodeItem::Label(start));
                    self.emit(opcode::ITER_NEXT, vec![]);
                    self.emit(0x17e, vec![Word::Variable(pair[1].clone())]);
                    self.emit(opcode::SET_VAR, vec![Word::Variable(pair[0].clone())]);
                    self.emit(opcode::JZ, vec![Word::Branch(end)]);
                    self.iterator_depth += 1;
                    self.loops.push((start, end));
                    self.breaks.push(end);
                    let result = self.typed_statements(body);
                    self.breaks.pop();
                    self.loops.pop();
                    self.iterator_depth -= 1;
                    result?;
                    self.emit(opcode::JMP_LOOP, vec![Word::Branch(start)]);
                    self.result.code.items.push(CodeItem::Label(end));
                    if self.iterator_depth > 0 {
                        self.emit(opcode::ITER_POP, vec![]);
                    }
                }
                StatementKind::For {
                    control:
                        ForControl::Range {
                            binding,
                            start,
                            end,
                            step,
                        },
                    body,
                } => {
                    if step
                        .as_ref()
                        .and_then(fold_number)
                        .is_some_and(|value| !value.is_finite() || value == 0.0)
                    {
                        return Err(error(
                            &statement.raw_header,
                            "range step must be finite and nonzero",
                        ));
                    }
                    let binding_name = if binding.starts_with("var/") {
                        let name = local_name(binding).ok_or_else(|| {
                            error(&statement.raw_header, "unsupported range binding")
                        })?;
                        if self.local_slots.contains_key(name) {
                            return Err(error(&statement.raw_header, "repeated range binding"));
                        }
                        let slot = self.locals.len() as u32;
                        self.locals.push(name.into());
                        self.local_slots.insert(name.into(), slot);
                        self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                        self.emit(
                            opcode::SET_VAR,
                            vec![Word::Variable(VariableWord::Local(slot))],
                        );
                        name
                    } else {
                        binding.as_str()
                    };
                    let binding_variable = self.variable(binding_name, &statement.raw_header)?;
                    self.ensure_writable(&binding_variable, &statement.raw_header)?;
                    self.expression(start, &statement.raw_header)?;
                    self.expression(end, &statement.raw_header)?;
                    if let Some(step) = step {
                        self.expression(step, &statement.raw_header)?;
                    }
                    // Native range state assigns the visible binding only when
                    // entering an iteration. Empty ranges preserve its value,
                    // and completion preserves the last body assignment.
                    self.emit(if step.is_some() { 0xfe } else { 0xfc }, vec![]);
                    let loop_start = self.label();
                    let loop_end = self.label();
                    self.result.code.items.push(CodeItem::Label(loop_start));
                    self.emit(
                        if step.is_some() { 0xff } else { 0xfd },
                        vec![Word::Branch(loop_end), Word::Variable(binding_variable)],
                    );
                    self.loops.push((loop_start, loop_end));
                    self.breaks.push(loop_end);
                    let result = self.typed_statements(body);
                    self.breaks.pop();
                    self.loops.pop();
                    result?;
                    self.emit(opcode::JMP_LOOP, vec![Word::Branch(loop_start)]);
                    self.result.code.items.push(CodeItem::Label(loop_end));
                    self.emit(
                        0xfb,
                        vec![Word::Immediate(if step.is_some() { 3 } else { 2 })],
                    );
                }
                StatementKind::For {
                    control:
                        ForControl::CStyle {
                            initializer,
                            condition,
                            step,
                        },
                    body,
                } => {
                    if let Some(initializer) = initializer {
                        match initializer {
                            ForInitializer::Declare { declaration, value } => {
                                let name = local_name(declaration).ok_or_else(|| {
                                    error(
                                        &statement.raw_header,
                                        "unsupported for initializer declaration",
                                    )
                                })?;
                                if self.local_slots.contains_key(name) {
                                    return Err(error(
                                        &statement.raw_header,
                                        "repeated for initializer local",
                                    ));
                                }
                                let slot = self.locals.len() as u32;
                                self.locals.push(name.into());
                                self.local_slots.insert(name.into(), slot);
                                if let Some(value) = value {
                                    self.expression(value, &statement.raw_header)?;
                                    self.emit(
                                        opcode::SET_VAR,
                                        vec![Word::Variable(VariableWord::Local(slot))],
                                    );
                                }
                            }
                            ForInitializer::Expr(value) => {
                                self.expression_statement(value, &statement.raw_header)?
                            }
                        }
                    }
                    let start = self.label();
                    let increment = self.label();
                    let end = self.label();
                    self.result.code.items.push(CodeItem::Label(start));
                    if let Some(condition) = condition {
                        self.condition(condition, &statement.raw_header)?;
                        self.emit(opcode::JZ, vec![Word::Branch(end)]);
                    }
                    self.loops.push((increment, end));
                    self.breaks.push(end);
                    let result = self.typed_statements(body);
                    self.loops.pop();
                    self.breaks.pop();
                    result?;
                    self.result.code.items.push(CodeItem::Label(increment));
                    if let Some(step) = step {
                        self.expression_statement(step, &statement.raw_header)?;
                    }
                    self.emit(opcode::JMP_LOOP, vec![Word::Branch(start)]);
                    self.result.code.items.push(CodeItem::Label(end));
                }
                StatementKind::Switch {
                    selector,
                    cases,
                    else_branch,
                } => {
                    if self.native_switch(selector, cases, else_branch, &statement.raw_header)? {
                        continue;
                    }
                    let slot = self.locals.len() as u32;
                    let name = format!("__dmb_switch_{slot}");
                    self.locals.push(name.clone());
                    self.local_slots.insert(name, slot);
                    self.expression(selector, &statement.raw_header)?;
                    self.emit(
                        opcode::SET_VAR,
                        vec![Word::Variable(VariableWord::Local(slot))],
                    );
                    let end = self.label();
                    for case in cases {
                        let matched = self.label();
                        let next = self.label();
                        for alternative in &case.alternatives {
                            match alternative {
                                SwitchAlternative::Exact(value) => {
                                    self.emit(
                                        opcode::GET_VAR,
                                        vec![Word::Variable(VariableWord::Local(slot))],
                                    );
                                    self.expression(value, &statement.raw_header)?;
                                    self.emit(opcode::TEQ, vec![]);
                                    self.emit(opcode::POP, vec![]);
                                    self.emit(opcode::JNZ, vec![Word::Branch(matched)]);
                                }
                                SwitchAlternative::Range(lower, upper) => {
                                    let after = self.label();
                                    self.emit(
                                        opcode::GET_VAR,
                                        vec![Word::Variable(VariableWord::Local(slot))],
                                    );
                                    self.expression(lower, &statement.raw_header)?;
                                    self.emit(opcode::TGE, vec![]);
                                    self.emit(opcode::TEST, vec![]);
                                    self.emit(opcode::JZ, vec![Word::Branch(after)]);
                                    self.emit(
                                        opcode::GET_VAR,
                                        vec![Word::Variable(VariableWord::Local(slot))],
                                    );
                                    self.expression(upper, &statement.raw_header)?;
                                    self.emit(opcode::TLE, vec![]);
                                    self.emit(opcode::TEST, vec![]);
                                    self.emit(opcode::JNZ, vec![Word::Branch(matched)]);
                                    self.result.code.items.push(CodeItem::Label(after));
                                }
                            }
                        }
                        self.emit(opcode::JMP, vec![Word::Branch(next)]);
                        self.result.code.items.push(CodeItem::Label(matched));
                        self.typed_statements(&case.body)?;
                        self.emit(opcode::JMP, vec![Word::Branch(end)]);
                        self.result.code.items.push(CodeItem::Label(next));
                    }
                    self.typed_statements(else_branch)?;
                    self.result.code.items.push(CodeItem::Label(end));
                }
                StatementKind::Try {
                    body,
                    catch_binding,
                    catch_body,
                } => {
                    let catch_label = self.label();
                    let end_label = self.label();
                    self.emit(0x12c, vec![Word::Branch(catch_label)]);
                    self.try_depth += 1;
                    let protected = self.typed_statements(body);
                    self.try_depth -= 1;
                    protected?;
                    self.emit(0x12e, vec![Word::Branch(end_label)]);
                    self.result.code.items.push(CodeItem::Label(catch_label));
                    if let Some(binding) = catch_binding {
                        let name = local_name(binding).ok_or_else(|| {
                            error(&statement.raw_header, "unsupported catch binding")
                        })?;
                        if self.local_slots.contains_key(name) {
                            return Err(error(&statement.raw_header, "repeated catch binding"));
                        }
                        let slot = self.locals.len() as u32;
                        self.locals.push(name.into());
                        self.local_slots.insert(name.into(), slot);
                        self.emit(
                            opcode::SET_VAR,
                            vec![Word::Variable(VariableWord::Local(slot))],
                        );
                    } else {
                        self.emit(opcode::POP, vec![]);
                    }
                    self.typed_statements(catch_body)?;
                    self.result.code.items.push(CodeItem::Label(end_label));
                }
                StatementKind::Break => {
                    let target = self
                        .breaks
                        .last()
                        .copied()
                        .ok_or_else(|| error(&statement.raw_header, "break outside loop"))?;
                    let leaves_try = self
                        .label_try_depths
                        .get(&target)
                        .is_some_and(|depth| self.try_depth > *depth);
                    self.emit(
                        if self.try_depth > 0 || leaves_try {
                            0x12e
                        } else {
                            opcode::JMP
                        },
                        vec![Word::Branch(target)],
                    );
                }
                StatementKind::BreakLabel(name) => {
                    let target =
                        self.label_breaks.get(name).copied().ok_or_else(|| {
                            error(&statement.raw_header, "break label is not active")
                        })?;
                    let leaves_try = self
                        .label_try_depths
                        .get(&target)
                        .is_some_and(|depth| self.try_depth > *depth);
                    let target_iterator_depth =
                        *self.label_iterator_depths.get(name).ok_or_else(|| {
                            error(
                                &statement.raw_header,
                                "break label iterator depth is unknown",
                            )
                        })?;
                    for _ in target_iterator_depth.max(1)..self.iterator_depth {
                        self.emit(opcode::ITER_POP, vec![]);
                    }
                    self.emit(
                        if self.try_depth > 0 || leaves_try {
                            0x12e
                        } else {
                            opcode::JMP
                        },
                        vec![Word::Branch(target)],
                    );
                }
                // Authored transfers inside Try use native cleanup handlers even
                // for same-frame destinations. TryJmp checks target minus one;
                // a loop at the first protected word exits that exception frame.
                StatementKind::Continue => {
                    let target = self
                        .loops
                        .last()
                        .ok_or_else(|| error(&statement.raw_header, "continue outside loop"))?
                        .0;
                    let leaves_try = self
                        .label_try_depths
                        .get(&target)
                        .is_some_and(|depth| self.try_depth > *depth);
                    self.emit(
                        if self.try_depth > 0 || leaves_try {
                            0x12f
                        } else {
                            opcode::JMP_LOOP
                        },
                        vec![Word::Branch(target)],
                    );
                }
                StatementKind::ContinueLabel(name) => {
                    let depth = *self.label_loop_depths.get(name).ok_or_else(|| {
                        error(&statement.raw_header, "continue label is not active")
                    })?;
                    let target = self
                        .loops
                        .get(depth)
                        .ok_or_else(|| error(&statement.raw_header, "continue label has no loop"))?
                        .0;
                    let leaves_try = self
                        .label_try_depths
                        .get(&target)
                        .is_some_and(|depth| self.try_depth > *depth);
                    let target_iterator_depth =
                        *self.label_iterator_depths.get(name).ok_or_else(|| {
                            error(
                                &statement.raw_header,
                                "continue label iterator depth is unknown",
                            )
                        })?;
                    for _ in target_iterator_depth.max(1)..self.iterator_depth {
                        self.emit(opcode::ITER_POP, vec![]);
                    }
                    self.emit(
                        if self.try_depth > 0 || leaves_try {
                            0x12f
                        } else {
                            opcode::JMP_LOOP
                        },
                        vec![Word::Branch(target)],
                    );
                }
                StatementKind::If {
                    condition,
                    then_branch,
                    else_branch,
                } => {
                    self.condition(condition, &statement.raw_header)?;
                    let else_label = self.label();
                    self.emit(opcode::JZ, vec![Word::Branch(else_label)]);
                    self.typed_statements(then_branch)?;
                    if self.statement_view(else_branch).is_empty() {
                        self.result.code.items.push(CodeItem::Label(else_label));
                    } else {
                        let end_label = self.label();
                        self.emit(opcode::JMP, vec![Word::Branch(end_label)]);
                        self.result.code.items.push(CodeItem::Label(else_label));
                        self.typed_statements(else_branch)?;
                        self.result.code.items.push(CodeItem::Label(end_label));
                    }
                }
                _ => {
                    return Err(error(
                        &statement.raw_header,
                        "typed statement is not lowered",
                    ))
                }
            }
            if let Some(saved_slots) = saved_slots {
                self.local_slots.restore(saved_slots);
            }
            if let Some(saved_types) = saved_types {
                self.local_types.restore(saved_types);
            }
        }
        Ok(())
    }
}
