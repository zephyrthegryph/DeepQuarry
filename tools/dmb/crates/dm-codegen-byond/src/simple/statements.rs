//! Statements lowering over the shared compiler context.
use super::*;

impl Compiler<'_> {
    pub(super) fn statements(&mut self, body: &[Item]) -> Result<(), LowerError> {
        let saved_coordinates = self.diagnostic_expression_coordinates;
        self.diagnostic_expression_coordinates = false;
        let saved_debug = self.debug_current;
        let saved_span = self.statement_span;
        let result = self
            .statements_inner(body)
            .map_err(|error| error.at(self.statement_span));
        self.debug_current = saved_debug;
        self.diagnostic_expression_coordinates = saved_coordinates;
        self.statement_span = saved_span;
        result
    }
    #[allow(clippy::needless_range_loop)]
    pub(super) fn statements_inner(&mut self, body: &[Item]) -> Result<(), LowerError> {
        let mut index = 0;
        while index < body.len() {
            let item = &body[index];
            self.debug_at(item.header_span.start, &item.header)?;
            let text = item.header.trim();
            if text.starts_with("if(") || text.starts_with("if (") {
                let mut last = index + 1;
                while body
                    .get(last)
                    .is_some_and(|next| next.header.trim().starts_with("else"))
                {
                    last += 1;
                }
                let end_label = self.label();
                for clause_index in index..last {
                    let clause = &body[clause_index];
                    self.debug_at(clause.header_span.start, &clause.header)?;
                    let header = clause.header.trim();
                    let condition = if clause_index == index {
                        header
                    } else if header == "else" {
                        ""
                    } else {
                        header
                            .strip_prefix("else ")
                            .ok_or_else(|| error(header, "unsupported else clause"))?
                    };
                    if !condition.is_empty() {
                        if !(condition.starts_with("if(") || condition.starts_with("if (")) {
                            return Err(error(header, "unsupported else-if condition"));
                        }
                        let expression = parenthesized(condition)
                            .ok_or_else(|| error(header, "malformed if condition"))?;
                        self.expression_text(expression, header)?;
                        self.emit(opcode::TEST, vec![]);
                        let next = self.label();
                        self.emit(opcode::JZ, vec![Word::Branch(next)]);
                        self.statements(&clause.children)?;
                        if clause_index + 1 < last {
                            self.emit(opcode::JMP, vec![Word::Branch(end_label)]);
                        }
                        self.result.code.items.push(CodeItem::Label(next));
                    } else {
                        if clause_index + 1 != last {
                            return Err(error(header, "else must be final"));
                        }
                        self.statements(&clause.children)?;
                    }
                }
                self.result.code.items.push(CodeItem::Label(end_label));
                index = last;
                continue;
            }
            if text.starts_with("while(") || text.starts_with("while (") {
                let condition =
                    parenthesized(text).ok_or_else(|| error(text, "malformed while condition"))?;
                let start_label = self.label();
                let end_label = self.label();
                self.result.code.items.push(CodeItem::Label(start_label));
                self.expression_text(condition, text)?;
                self.emit(opcode::TEST, vec![]);
                self.emit(opcode::JZ, vec![Word::Branch(end_label)]);
                self.loops.push((start_label, end_label));
                self.breaks.push(end_label);
                let body_result = self.statements(&item.children);
                self.loops.pop();
                self.breaks.pop();
                body_result?;
                self.emit(opcode::JMP_LOOP, vec![Word::Branch(start_label)]);
                self.result.code.items.push(CodeItem::Label(end_label));
                index += 1;
                continue;
            }
            if text.starts_with("for(") || text.starts_with("for (") {
                let control =
                    parenthesized(text).ok_or_else(|| error(text, "malformed for control"))?;
                if let Some((binding, iterable)) = control.split_once(" in ") {
                    let binding = binding.trim();
                    let (binding, mask) = binding
                        .strip_suffix(" as anything")
                        .map_or((binding, 0), |name| (name.trim(), 0x1000));
                    let name = binding
                        .strip_prefix("var/")
                        .ok_or_else(|| error(text, "iterator binding must declare a local"))?;
                    if self.bindings.parameters.iter().any(|formal| formal == name) {
                        self.check_local_declaration(
                            name,
                            text,
                            LowerSpan {
                                start: item.header_span.start,
                                end: item.header_span.end,
                            },
                        )?;
                    }
                    if name.is_empty() || name.contains('/') || self.local_slots.contains_key(name)
                    {
                        return Err(error(text, "unsupported iterator binding"));
                    }
                    let slot = self.locals.len() as u32;
                    self.locals.push(name.into());
                    self.local_slots.insert(name.into(), slot);
                    self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                    self.emit(
                        opcode::SET_VAR,
                        vec![Word::Variable(VariableWord::Local(slot))],
                    );
                    self.expression_text(iterable.trim(), text)?;
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
                        vec![Word::Variable(VariableWord::Local(slot))],
                    );
                    self.emit(opcode::JZ, vec![Word::Branch(end)]);
                    self.iterator_depth += 1;
                    self.loops.push((start, end));
                    self.breaks.push(end);
                    let result = self.statements(&item.children);
                    self.breaks.pop();
                    self.loops.pop();
                    self.iterator_depth -= 1;
                    result?;
                    self.emit(opcode::JMP_LOOP, vec![Word::Branch(start)]);
                    self.result.code.items.push(CodeItem::Label(end));
                    if self.iterator_depth > 0 {
                        self.emit(opcode::ITER_POP, vec![]);
                    }
                    index += 1;
                    continue;
                }
                if let Some((begin, remainder)) = control.split_once(" to ") {
                    let (binding, start_value) = begin
                        .split_once('=')
                        .ok_or_else(|| error(text, "range for requires initialized binding"))?;
                    let binding = binding.trim();
                    let (end_value, step_value) = remainder
                        .split_once(" step ")
                        .map_or((remainder.trim(), "1"), |(end, step)| {
                            (end.trim(), step.trim())
                        });
                    let step_number = step_value
                        .parse::<f32>()
                        .map_err(|_| error(text, "range step must be a numeric literal"))?;
                    if !step_number.is_finite() || step_number == 0.0 {
                        return Err(error(text, "range step must be finite and nonzero"));
                    }
                    let name = if let Some(name) = binding.strip_prefix("var/") {
                        let mut declaration = item.clone();
                        declaration.header = format!("var/{name}");
                        declaration.children.clear();
                        self.statement(&declaration)?;
                        name
                    } else {
                        binding
                    };
                    let binding_variable = self.variable(name, text)?;
                    self.ensure_writable(&binding_variable, text)?;
                    self.expression_text(start_value.trim(), text)?;
                    self.expression_text(end_value, text)?;
                    let has_step = remainder.contains(" step ");
                    if has_step {
                        self.expression_text(step_value, text)?;
                    }
                    self.emit(if has_step { 0xfe } else { 0xfc }, vec![]);
                    let start = self.label();
                    let end = self.label();
                    self.result.code.items.push(CodeItem::Label(start));
                    self.emit(
                        if has_step { 0xff } else { 0xfd },
                        vec![Word::Branch(end), Word::Variable(binding_variable)],
                    );
                    self.loops.push((start, end));
                    self.breaks.push(end);
                    let result = self.statements(&item.children);
                    self.breaks.pop();
                    self.loops.pop();
                    result?;
                    self.emit(opcode::JMP_LOOP, vec![Word::Branch(start)]);
                    self.result.code.items.push(CodeItem::Label(end));
                    self.emit(0xfb, vec![Word::Immediate(if has_step { 3 } else { 2 })]);
                    index += 1;
                    continue;
                }
                let parts: Vec<_> = control.split(';').map(str::trim).collect();
                if parts.len() != 3 {
                    return Err(error(
                        text,
                        "only C-style semicolon for loops are supported",
                    ));
                }
                if !parts[0].is_empty() {
                    let mut initializer = item.clone();
                    initializer.header = parts[0].into();
                    initializer.children.clear();
                    self.statement(&initializer)?;
                }
                let start = self.label();
                let step = self.label();
                let end = self.label();
                self.result.code.items.push(CodeItem::Label(start));
                if !parts[1].is_empty() {
                    self.expression_text(parts[1], text)?;
                    self.emit(opcode::TEST, vec![]);
                    self.emit(opcode::JZ, vec![Word::Branch(end)]);
                }
                self.loops.push((step, end));
                self.breaks.push(end);
                let result = self.statements(&item.children);
                self.loops.pop();
                self.breaks.pop();
                result?;
                self.result.code.items.push(CodeItem::Label(step));
                if !parts[2].is_empty() {
                    let mut increment = item.clone();
                    increment.header = parts[2].into();
                    increment.children.clear();
                    self.statement(&increment)?;
                }
                self.emit(opcode::JMP_LOOP, vec![Word::Branch(start)]);
                self.result.code.items.push(CodeItem::Label(end));
                index += 1;
                continue;
            }
            if text.starts_with("switch(") || text.starts_with("switch (") {
                let selector =
                    parenthesized(text).ok_or_else(|| error(text, "malformed switch selector"))?;
                let slot = self.locals.len() as u32;
                let temp = format!("__dmb_switch_{slot}");
                if self.local_slots.contains_key(&temp) {
                    return Err(error(text, "switch temporary conflicts with local"));
                }
                self.locals.push(temp.clone());
                self.local_slots.insert(temp, slot);
                self.expression_text(selector, text)?;
                self.emit(
                    opcode::SET_VAR,
                    vec![Word::Variable(VariableWord::Local(slot))],
                );
                let end = self.label();
                for (case_index, case) in item.children.iter().enumerate() {
                    let header = case.header.trim();
                    if header == "else" {
                        if case_index + 1 != item.children.len() {
                            return Err(error(header, "switch else must be final"));
                        }
                        self.statements(&case.children)?;
                        continue;
                    }
                    if !(header.starts_with("if(") || header.starts_with("if (")) {
                        return Err(error(header, "unsupported switch case"));
                    }
                    let value = parenthesized(header)
                        .ok_or_else(|| error(header, "malformed switch case"))?;
                    let matched = self.label();
                    let next = self.label();
                    for alternative in value.split(',').map(str::trim) {
                        if alternative.is_empty() {
                            return Err(error(header, "empty switch alternative"));
                        }
                        if let Some((lower, upper)) = alternative.split_once(" to ") {
                            let after_range = self.label();
                            self.emit(
                                opcode::GET_VAR,
                                vec![Word::Variable(VariableWord::Local(slot))],
                            );
                            self.expression_text(lower.trim(), header)?;
                            self.emit(opcode::TGE, vec![]);
                            self.emit(opcode::TEST, vec![]);
                            self.emit(opcode::JZ, vec![Word::Branch(after_range)]);
                            self.emit(
                                opcode::GET_VAR,
                                vec![Word::Variable(VariableWord::Local(slot))],
                            );
                            self.expression_text(upper.trim(), header)?;
                            self.emit(opcode::TLE, vec![]);
                            self.emit(opcode::TEST, vec![]);
                            self.emit(opcode::JNZ, vec![Word::Branch(matched)]);
                            self.result.code.items.push(CodeItem::Label(after_range));
                        } else {
                            self.emit(
                                opcode::GET_VAR,
                                vec![Word::Variable(VariableWord::Local(slot))],
                            );
                            self.expression_text(alternative, header)?;
                            self.emit(opcode::TEQ, vec![]);
                            self.emit(opcode::POP, vec![]);
                            self.emit(opcode::JNZ, vec![Word::Branch(matched)]);
                        }
                    }
                    self.emit(opcode::JMP, vec![Word::Branch(next)]);
                    self.result.code.items.push(CodeItem::Label(matched));
                    self.statements(&case.children)?;
                    self.emit(opcode::JMP, vec![Word::Branch(end)]);
                    self.result.code.items.push(CodeItem::Label(next));
                }
                self.result.code.items.push(CodeItem::Label(end));
                index += 1;
                continue;
            }
            self.statement(item)?;
            index += 1;
        }
        Ok(())
    }

    pub(super) fn statement(&mut self, item: &Item) -> Result<(), LowerError> {
        self.debug_at(item.header_span.start, &item.header)?;
        let text = item.header.trim();
        if text.starts_with("sleep(") && text.ends_with(')') {
            let duration =
                parenthesized(text).ok_or_else(|| error(text, "malformed sleep call"))?;
            self.expression_text(duration, text)?;
            self.emit(opcode::SLEEP, vec![]);
            return Ok(());
        }
        if text == "break" || text == "continue" {
            let target = *if text == "break" {
                self.breaks
                    .last()
                    .ok_or_else(|| error(text, "break outside a loop or switch"))?
            } else {
                &self
                    .loops
                    .last()
                    .ok_or_else(|| error(text, "continue outside a loop"))?
                    .0
            };
            self.emit(opcode::JMP, vec![Word::Branch(target)]);
            return Ok(());
        }
        if text == "return" {
            self.emit(opcode::END, vec![]);
            return Ok(());
        }
        if let Some(rest) = text.strip_prefix("return ") {
            let previous = std::mem::replace(&mut self.nameof_return_context, true);
            let lowered = self.expression_text(rest, text);
            self.nameof_return_context = previous;
            lowered?;
            self.emit(opcode::RET, vec![]);
            return Ok(());
        }
        if text.starts_with("var/")
            || text
                .strip_prefix("var")
                .is_some_and(|tail| tail.chars().next().is_some_and(char::is_whitespace))
        {
            let (declaration, initial) = text
                .split_once('=')
                .map_or((text.trim(), None), |(n, e)| (n.trim(), Some(e.trim())));
            let name = local_name(declaration)
                .ok_or_else(|| error(text, "unsupported local declaration"))?;
            self.check_local_declaration(
                name,
                text,
                LowerSpan {
                    start: item.header_span.start,
                    end: item.header_span.end,
                },
            )?;
            let slot = self.locals.len() as u32;
            self.locals.push(name.into());
            self.local_slots.insert(name.into(), slot);
            self.local_declarations.insert(
                slot,
                LowerSpan {
                    start: item.header_span.start,
                    end: item.header_span.end,
                },
            );
            if let Some(dimensions) = local_array_dimensions(declaration) {
                self.local_array_declaration(
                    &dimensions,
                    slot,
                    text,
                    initial.map(|initial| {
                        |compiler: &mut Self| {
                            let parsed = parse_expression(initial);
                            if !parsed.diagnostics.is_empty() {
                                return Err(error(text, "expression syntax is unsupported"));
                            }
                            let value = parsed
                                .expr
                                .ok_or_else(|| error(text, "missing expression"))?;
                            compiler.local_declaration_initializer(&value, declaration, text)
                        }
                    }),
                )?;
                return Ok(());
            }
            if let Some(initial) = initial {
                self.expression_text(initial, text)?;
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
            return Ok(());
        }
        if !item.children.is_empty() {
            return Err(error(text, "control-flow statement is not lowered yet"));
        }
        let parsed = parse_expression(text);
        if !parsed.diagnostics.is_empty() {
            return Err(error(text, "expression syntax is unsupported"));
        }
        let expr = parsed
            .expr
            .ok_or_else(|| error(text, "missing expression"))?;
        if let ExprKind::Binary { op, lhs, rhs } = &expr.kind {
            if matches!(
                op.as_str(),
                "=" | "+="
                    | "-="
                    | "*="
                    | "/="
                    | "%="
                    | "&="
                    | "|="
                    | "^="
                    | "<<="
                    | ">>="
                    | "||="
                    | "&&="
            ) {
                return self.assign_expr(lhs, op, rhs, text);
            }
        }
        if self.crash_statement(&expr, text)? {
            return Ok(());
        }
        if self.output_statement(&expr, text)? {
            return Ok(());
        }
        if self.builtin_statement(&expr, text)? {
            return Ok(());
        }
        self.expression(&expr, text)?;
        self.emit(opcode::POP, vec![]);
        Ok(())
    }

    pub(super) fn expression_statement(
        &mut self,
        expr: &Expr,
        statement: &str,
    ) -> Result<(), LowerError> {
        if self.crash_statement(expr, statement)? {
            return Ok(());
        }
        if self.output_statement(expr, statement)? {
            return Ok(());
        }
        if self.builtin_statement(expr, statement)? {
            return Ok(());
        }
        if let ExprKind::Unary { op, value } = &expr.kind {
            if matches!(op.as_str(), "post++" | "post--" | "pre++" | "pre--") {
                return self.inc_dec(
                    value,
                    if op.ends_with("++") { 0x66 } else { 0x67 },
                    statement,
                );
            }
        }
        if let ExprKind::Binary { op, lhs, rhs } = &expr.kind {
            if matches!(
                op.as_str(),
                "=" | "+="
                    | "-="
                    | "*="
                    | "/="
                    | "%="
                    | "&="
                    | "|="
                    | "^="
                    | "<<="
                    | ">>="
                    | "||="
                    | "&&="
            ) {
                return self.assign_expr(lhs, op, rhs, statement);
            }
        }
        self.discarded_expression(expr, statement)?;
        Ok(())
    }

    pub(super) fn direct_call_opcode(&self, expr: &Expr) -> u32 {
        if self
            .discarded_call_root
            .is_some_and(|root| std::ptr::eq(root, expr))
        {
            0x2a
        } else {
            opcode::CALL
        }
    }
    pub(super) fn discarded_expression(
        &mut self,
        expr: &Expr,
        statement: &str,
    ) -> Result<(), LowerError> {
        let previous = self.discarded_call_root.replace(expr);
        let result = self.expression(expr, statement);
        self.discarded_call_root = previous;
        result?;
        if matches!(self.result.code.items.last(), Some(CodeItem::Instruction(instruction)) if instruction.opcode == 0x2a)
        {
            // CallStatement skips one raw word. A source marker must never be
            // inserted between it and this otherwise executable Pop marker.
            self.result
                .code
                .items
                .push(CodeItem::Instruction(Instruction {
                    opcode: opcode::POP,
                    operands: vec![],
                }));
        } else {
            self.emit(opcode::POP, vec![]);
        }
        Ok(())
    }

    pub(super) fn crash_statement(
        &mut self,
        expr: &Expr,
        statement: &str,
    ) -> Result<bool, LowerError> {
        let ExprKind::Call { callee, args } = &expr.kind else {
            return Ok(false);
        };
        if !matches!(&callee.kind, ExprKind::Ident(name) if name == "CRASH") {
            return Ok(false);
        }
        if args.len() > 1 {
            return Err(error(statement, "CRASH expects zero or one argument"));
        }
        if let Some(value) = args.first() {
            self.expression(value, statement)?;
        } else {
            self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
        }
        self.emit(0xc7, vec![]);
        Ok(true)
    }

    pub(super) fn output_statement(
        &mut self,
        expr: &Expr,
        statement: &str,
    ) -> Result<bool, LowerError> {
        let ExprKind::Binary { op, lhs, rhs } = &expr.kind else {
            return Ok(false);
        };
        if op == ">>" {
            self.output_receiver(lhs, statement)?;
            self.emit(0xaf, vec![]);
            if let ExprKind::Index { object, index } = &rhs.kind {
                self.expression(object, statement)?;
                self.expression(index, statement)?;
                self.emit(opcode::LIST_SET, vec![]);
                return Ok(true);
            }
            let variable = match self.variable_expr(rhs, statement) {
                Ok(variable) => variable,
                Err(_) => {
                    let ExprKind::Member {
                        object, selector, ..
                    } = &rhs.kind
                    else {
                        return Err(error(statement, "unsupported read destination"));
                    };
                    self.expression(object, statement)?;
                    self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                    self.intern_string(selector);
                    VariableWord::Field(SymbolId::of(selector))
                }
            };
            self.ensure_writable(&variable, statement)?;
            self.emit(opcode::SET_VAR, vec![Word::Variable(variable)]);
            return Ok(true);
        }
        if op != "<<" {
            return Ok(false);
        }
        self.output_receiver(lhs, statement)?;
        if let ExprKind::Call { callee, args } = &rhs.kind {
            if let ExprKind::Ident(name) = &callee.kind {
                if name == "load_resource" {
                    if args.len() < 2 {
                        return Err(error(
                            statement,
                            "load_resource expects at least two arguments",
                        ));
                    }
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                    self.emit(0x165, vec![Word::Immediate(args.len() as u32 + 1)]);
                    return Ok(true);
                }
                let special = match (name.as_str(), args.len()) {
                    ("run", 1) => Some((0x09, false)),
                    ("link", 1) => Some((0x07, false)),
                    ("browse", 1) => Some((0xaa, false)),
                    ("browse", 2) => Some((0xab, false)),
                    ("browse_rsc", 1..=2) => Some((0x27, args.len() == 1)),
                    ("ftp", 1..=2) => Some((0x08, args.len() == 1)),
                    ("output", 2) => Some((0x10b, false)),
                    _ => None,
                };
                if let Some((opcode, pad_null)) = special {
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                    if pad_null {
                        self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                    }
                    self.emit(opcode, vec![]);
                    return Ok(true);
                }
            }
        }
        self.expression(rhs, statement)?;
        self.emit(0x03, vec![]);
        Ok(true)
    }

    pub(super) fn output_receiver(
        &mut self,
        expr: &Expr,
        statement: &str,
    ) -> Result<(), LowerError> {
        if let ExprKind::Index { object, index } = &expr.kind {
            self.expression(object, statement)?;
            self.expression(index, statement)?;
            self.emit(0xb0, vec![]);
            Ok(())
        } else {
            self.expression(expr, statement)
        }
    }

    pub(super) fn builtin_statement(
        &mut self,
        expr: &Expr,
        statement: &str,
    ) -> Result<bool, LowerError> {
        let ExprKind::Call { callee, args } = &expr.kind else {
            return Ok(false);
        };
        let ExprKind::Ident(name) = &callee.kind else {
            return Ok(false);
        };
        if name == "stat" {
            if !(1..=2).contains(&args.len()) {
                return Err(error(statement, "stat expects one or two arguments"));
            }
            if args.len() == 1 {
                self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
            }
            for arg in args {
                self.expression(arg, statement)?;
            }
            self.emit(0x05, vec![]);
            return Ok(true);
        }
        if name == "statpanel" {
            if !(1..=3).contains(&args.len()) {
                return Err(error(statement, "statpanel expects one to three arguments"));
            }
            self.expression(&args[0], statement)?;
            if args.len() == 1 {
                self.emit(0xa2, vec![]);
            } else {
                if args.len() == 2 {
                    self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                }
                for arg in &args[1..] {
                    self.expression(arg, statement)?;
                }
                self.emit(0xa1, vec![]);
            }
            return Ok(true);
        }
        if name == "missile" {
            if args.len() != 3 {
                return Err(error(statement, "missile expects three arguments"));
            }
            for arg in args {
                self.expression(arg, statement)?;
            }
            self.emit(0x0b, vec![]);
            return Ok(true);
        }
        let Some(spec) = crate::builtin_catalog::lookup_with_arity(name, args.len()) else {
            return Ok(false);
        };
        if spec.post_opcode != Some(0x36) && !crate::builtin_catalog::is_void(name) {
            return Ok(false);
        }
        self.expression(expr, statement)?;
        // Expressions materialize the flag or a null value. Native statement
        // calls discard it by omitting that materialization altogether.
        self.result.code.items.pop();
        Ok(true)
    }
}
