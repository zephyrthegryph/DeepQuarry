//! Expression lowering over the shared compiler context.
use super::*;

impl Compiler<'_> {
    /// Lowers code DreamMaker drops (the dead side of a constant condition) so that its diagnostics and source features still count,
    /// and discards the instructions.
    pub(super) fn lower_dead(
        &mut self,
        lower: impl FnOnce(&mut Self) -> Result<(), LowerError>,
    ) -> Result<(), LowerError> {
        let mark = self.result.code.items.len();
        let lowered = lower(self);
        self.result.code.items.truncate(mark);
        lowered
    }

    /// Lowers one expression. DreamMaker leaves the chain of `+ * | & ^` as written when it is the whole value of an
    /// assignment, a variable initializer, a condition, a switch selector or the operand of `<<` (`assoc_off_op` names
    /// the chain's operator); it rewrites every other chain (after `return`, nested under a different operator, in a
    /// call argument).
    pub(super) fn expression(&mut self, expr: &Expr, statement: &str) -> Result<(), LowerError> {
        let before = self.assoc_off_op.clone();
        // Only the chain itself is exempt: a parenthesised sub-expression (a `Group`, also the macro-generated parentheses
        // around a whole value) is an expression of its own and is rewritten.
        let shape = match &expr.kind {
            ExprKind::Binary { op, .. } if is_associative_operator(op) => Some(op.clone()),
            _ => None,
        };
        if self.assoc_exempt_root == Some(expr as *const Expr) {
            self.assoc_off_op = shape.clone();
        } else if self.assoc_off_op.is_some() && self.assoc_off_op != shape {
            self.assoc_off_op = None;
        }
        if matches!(expr.kind, ExprKind::Call { .. }) {
            self.assoc_off_op = None;
        }
        let lowered = self.expression_scoped(expr, statement);
        self.assoc_off_op = before;
        lowered
    }

    fn expression_scoped(&mut self, expr: &Expr, statement: &str) -> Result<(), LowerError> {
        self.source_feature_reference(
            expr,
            self.discarded_call_root != Some(expr as *const Expr),
            statement,
        )?;
        // `!"text"` is a constant too (DreamMaker folds it to 0 or 1).
        let folded = fold_number(expr).or_else(|| match &expr.kind {
            ExprKind::Unary { op, value } if op == "!" => {
                constant_truth(value).map(|truth| if truth { 0.0 } else { 1.0 })
            }
            _ => None,
        });
        if let Some(number) = folded {
            if number >= 0.0 && number <= u16::MAX as f32 && number.fract() == 0.0 {
                self.emit(opcode::PUSH_INT, vec![Word::Immediate(number as u32)]);
            } else {
                self.emit(
                    opcode::PUSH_VAL,
                    vec![Word::Value(ValueWord::Number(number.to_bits()))],
                );
            }
            return Ok(());
        }
        // A `const` variable inside an operator expression that folds is its value (a bare read stays a variable read).
        if matches!(&expr.kind, ExprKind::Binary { .. } | ExprKind::Unary { .. }) {
            if let Some(substituted) = self.substitute_constants(expr) {
                if fold_number(&substituted).is_some()
                    || fold_literal_string_expression(&substituted).is_some()
                {
                    return self.expression(&substituted, statement);
                }
            }
        }
        // The left operand of `*`, `|`, `&` and `^` that names a `const` variable is its value, even when the other
        // operand is not constant (`MC * x` is `6 * x`, `x * MC` reads the variable).
        if let ExprKind::Binary { op, lhs, rhs } = &expr.kind {
            if matches!(op.as_str(), "*" | "|" | "&" | "^") {
                if let Some(value) = self.const_reference_literal(lhs) {
                    let folded = Expr {
                        kind: ExprKind::Binary {
                            op: op.clone(),
                            lhs: Box::new(value),
                            rhs: rhs.clone(),
                        },
                        span: expr.span,
                    };
                    return self.expression(&folded, statement);
                }
            }
        }
        if let ExprKind::Binary { op, .. } = &expr.kind {
            if is_associative_operator(op) && self.assoc_off_op.as_deref() != Some(op.as_str()) {
                let mut changed = false;
                let normalized = reassociate(expr, &mut changed);
                if changed {
                    return self.expression(&normalized, statement);
                }
            }
        }
        // A constant condition leaves only the branch DreamMaker keeps; `0 && x` and `1 || x` never reach `x`.
        match &expr.kind {
            ExprKind::Conditional {
                condition,
                then_value,
                else_value,
            } => {
                if let Some(condition) =
                    constant_truth(condition).or_else(|| self.const_reference_truth(condition))
                {
                    let (kept, dead) = if condition {
                        (then_value, else_value)
                    } else {
                        (else_value, then_value)
                    };
                    self.lower_dead(|compiler| compiler.expression(dead, statement))?;
                    return self.expression(kept, statement);
                }
            }
            ExprKind::Binary { op, lhs, rhs } if op == "&&" || op == "||" => {
                // A constant left side decides the result (DreamMaker folds `"name" || src.name`, the NAMEOF idiom).
                let left = constant_truth(lhs);
                if let Some(left) = left {
                    if (op == "&&") == left {
                        return self.expression(rhs, statement);
                    }
                    self.lower_dead(|compiler| compiler.expression(rhs, statement))?;
                    return self.expression(lhs, statement);
                }
            }
            _ => {}
        }
        if let Some(bytes) = fold_literal_string_expression(expr) {
            let id = self.intern_format_template(bytes);
            self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::String(id))]);
            return Ok(());
        }
        match &expr.kind {
            ExprKind::ObjectInitializer { object, fields } => {
                let ExprKind::TypePath(path) = &object.kind else {
                    return Err(error(
                        statement,
                        "modified instance requires an explicit type",
                    ));
                };
                let lookup = self.lookup.ok_or_else(|| {
                    error(
                        statement,
                        "object initializer requires captured descriptor support",
                    )
                })?;
                let owner = self.bindings.current_type_path.as_deref().unwrap_or("/");
                let alias = self.semantic(lookup.modified_instance(
                    path.trim_end_matches('/'),
                    owner,
                    fields,
                    self.debug_current,
                    expr.span,
                ))?;
                if !self.result.instance_paths.contains(&alias) {
                    self.result.instance_paths.push(alias);
                }
                self.emit(
                    opcode::PUSH_VAL,
                    vec![Word::Value(ValueWord::Instance(alias))],
                );
            }
            ExprKind::TypeFilter { .. } => {
                if let Some((args, types)) = self.input_form(expr) {
                    self.input_call(args, types, None, Some(expr.span.end), statement)?;
                } else if let ExprKind::TypeFilter { value, .. } = &expr.kind {
                    self.expression(value, statement)?;
                }
            }
            ExprKind::Binary { op, lhs, rhs } if op == "in" => {
                if let ExprKind::Call { callee, args } = &lhs.kind {
                    if matches!(&callee.kind, ExprKind::Ident(name) if name == "locate")
                        && args.len() == 1
                    {
                        self.expression(&args[0], statement)?;
                        self.expression(rhs, statement)?;
                        self.emit(0x97, vec![]);
                        return Ok(());
                    }
                }
                if let Some((args, types)) = self.input_form(lhs) {
                    self.input_call(args, types, Some(rhs), Some(lhs.span.end), statement)?;
                } else if let ExprKind::Binary {
                    op: range_op,
                    lhs: low,
                    rhs: high,
                } = &rhs.kind
                {
                    if range_op == "to" {
                        self.expression(low, statement)?;
                        self.expression(high, statement)?;
                        self.expression(lhs, statement)?;
                        self.emit(0xa9, vec![Word::Immediate(11)]);
                        self.emit(0x36, vec![]);
                    } else {
                        self.expression(rhs, statement)?;
                        self.expression(lhs, statement)?;
                        self.emit(0xa9, vec![Word::Immediate(5)]);
                        self.emit(0x36, vec![]);
                    }
                } else {
                    self.expression(rhs, statement)?;
                    self.expression(lhs, statement)?;
                    self.emit(0xa9, vec![Word::Immediate(5)]);
                    self.emit(0x36, vec![]);
                }
            }
            ExprKind::Conditional {
                condition,
                then_value,
                else_value,
            } => {
                self.condition(condition, statement)?;
                let else_label = self.label();
                let end_label = self.label();
                self.emit(opcode::JZ, vec![Word::Branch(else_label)]);
                self.expression(then_value, statement)?;
                self.emit(opcode::JMP, vec![Word::Branch(end_label)]);
                self.result.code.items.push(CodeItem::Label(else_label));
                self.expression(else_value, statement)?;
                self.result.code.items.push(CodeItem::Label(end_label));
            }
            ExprKind::Literal(literal) => {
                if literal == "null" {
                    // DreamMaker reads an authored null through the Null variable reader (two words) and pushes a null
                    // for an omitted argument (`f(1,,3)`, a zero-width literal; three words). The difference decides
                    // whether a large initializer fits the 65,535-word procedure limit.
                    if expr.span.start == expr.span.end {
                        self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                    } else {
                        self.emit(opcode::GET_VAR, vec![Word::Variable(VariableWord::Null)]);
                    }
                } else if literal == "FALSE" {
                    self.emit(opcode::PUSH_INT, vec![Word::Immediate(0)]);
                } else if literal == "TRUE" {
                    self.emit(opcode::PUSH_INT, vec![Word::Immediate(1)]);
                } else if literal.starts_with("@{\"")
                    && literal.ends_with("\"}")
                    && literal.len() >= 5
                {
                    let value = literal[3..literal.len() - 2].to_owned();
                    self.intern_string(&value);
                    self.emit(
                        opcode::PUSH_VAL,
                        vec![Word::Value(ValueWord::String(SymbolId::of(&value)))],
                    );
                } else if literal.starts_with("@\"") && literal.ends_with('"') && literal.len() >= 3
                {
                    let value = literal[2..literal.len() - 1].to_owned();
                    self.intern_string(&value);
                    self.emit(
                        opcode::PUSH_VAL,
                        vec![Word::Value(ValueWord::String(SymbolId::of(&value)))],
                    );
                } else if (literal.starts_with('"') && literal.ends_with('"') && literal.len() >= 2)
                    || (literal.starts_with("{\"")
                        && literal.ends_with("\"}")
                        && literal.len() >= 4)
                {
                    let value = if literal.starts_with("{\"") {
                        &literal[2..literal.len() - 2]
                    } else {
                        &literal[1..literal.len() - 1]
                    };
                    let (template, expressions) = parse_interpolated_string(value)
                        .map_err(|reason| error(statement, &reason))?;
                    if expressions.is_empty() {
                        let value = match String::from_utf8(template.clone()) {
                            Ok(value) => self.intern_string(&value),
                            Err(_) => self.intern_format_template(template),
                        };
                        self.emit(
                            opcode::PUSH_VAL,
                            vec![Word::Value(ValueWord::String(value))],
                        );
                    } else {
                        for expression in &expressions {
                            self.expression(expression, statement)?;
                        }
                        let key = self.intern_format_template(template);
                        self.emit(
                            2,
                            vec![
                                Word::Reference(SymRef::String(key)),
                                Word::Immediate(expressions.len() as u32),
                            ],
                        );
                    }
                } else if literal.starts_with("@'") && literal.ends_with('\'') && literal.len() >= 3
                {
                    let value = literal[2..literal.len() - 1].to_owned();
                    self.intern_string(&value);
                    self.emit(
                        opcode::PUSH_VAL,
                        vec![Word::Value(ValueWord::String(SymbolId::of(&value)))],
                    );
                } else if literal.starts_with('\'') && literal.ends_with('\'') && literal.len() >= 2
                {
                    let path = &literal[1..literal.len() - 1];
                    if path.contains(['\\', '[', ']']) {
                        return Err(error(
                            statement,
                            "escaped or interpolated resource path is unsupported",
                        ));
                    }
                    let path = match self.lookup {
                        Some(lookup) => self.semantic(lookup.resource(path))?,
                        None => *self.bindings.resource_ids.get(path).ok_or_else(|| {
                            error(
                                statement,
                                "resource literal requires captured resource identity",
                            )
                        })?,
                    };
                    if self.seen_resources.insert(path) {
                        self.result.resources.push(path);
                    }
                    self.emit(
                        opcode::PUSH_VAL,
                        vec![Word::Value(ValueWord::Resource(path))],
                    );
                } else if let Ok(number) = literal.parse::<f32>() {
                    self.emit(
                        opcode::PUSH_VAL,
                        vec![Word::Value(ValueWord::Number(number.to_bits()))],
                    );
                } else if literal.matches('.').count() > 1
                    && literal.starts_with(|ch: char| ch.is_ascii_digit())
                {
                    // `1.2.3`: DreamMaker reads `.3` as a member of `1.2`.
                    return Err(source_error(
                        statement,
                        "expected var or proc name after . operator",
                    ));
                } else {
                    return Err(error(statement, "unsupported literal"));
                }
            }
            ExprKind::TypePath(path) => {
                if path.ends_with("/proc") || path.ends_with("/verb") {
                    // A procedure namespace is a native string path used by
                    // typesof(), not a runtime class or a single procedure.
                    self.intern_string(path);
                    self.emit(
                        opcode::PUSH_VAL,
                        vec![Word::Value(ValueWord::String(SymbolId::of(path)))],
                    );
                    return Ok(());
                }
                if path.starts_with("/proc/")
                    || path.contains("/proc/")
                    || path.starts_with("/verb/")
                    || path.contains("/verb/")
                {
                    let value_path = self.procedure_literal(path)?;
                    self.emit(
                        opcode::PUSH_VAL,
                        vec![Word::Value(ValueWord::ProcPath(value_path))],
                    );
                    return Ok(());
                }
                let tag = self
                    .class_tag(path)?
                    .ok_or_else(|| error(statement, "unsupported type path literal"))?;
                if self.seen_classes.insert(SymbolId::of(path)) {
                    self.result.class_paths.push(SymbolId::of(path));
                }
                self.emit(
                    opcode::PUSH_VAL,
                    vec![Word::Value(ValueWord::ClassPath {
                        path: SymbolId::of(path),
                        tag,
                    })],
                );
            }
            ExprKind::Ident(name) => {
                if name == "__PROC__"
                    && !self.local_slots.contains_key(name)
                    && !self
                        .bindings
                        .parameters
                        .iter()
                        .any(|parameter| parameter == name)
                {
                    if let Some(lookup) = self.lookup {
                        if self
                            .semantic(
                                lookup
                                    .procedure_static_slot(self.bindings.procedure_identity, name),
                            )?
                            .is_some()
                        {
                            let variable = self.variable_for_node(expr, name, statement)?;
                            self.emit(opcode::GET_VAR, vec![Word::Variable(variable)]);
                            return Ok(());
                        }
                    }
                    let path = self.current_procedure_value(statement)?;
                    self.record_selection(expr, name, dm_ir::SelectedMeaning::ProcedureValue(path));
                    self.emit(
                        opcode::PUSH_VAL,
                        vec![Word::Value(ValueWord::ProcPath(path))],
                    );
                    return Ok(());
                }
                if dm_syntax::is_literal_identifier(name) {
                    self.record_selection(expr, name, dm_ir::SelectedMeaning::Literal);
                    let literal = Expr {
                        kind: ExprKind::Literal(name.clone()),
                        span: expr.span,
                    };
                    return self.expression(&literal, statement);
                }
                if !matches!(
                    name.as_str(),
                    "src" | "usr" | "world" | "args" | "caller" | "callee" | "."
                ) && !self.local_slots.contains_key(name)
                    && !self
                        .bindings
                        .parameters
                        .iter()
                        .any(|parameter| parameter == name)
                    && !self.has_field(name)?
                    && !self.has_visible_global(name)?
                {
                    if name == "__PROC__" {
                        let path = self.current_procedure_value(statement)?;
                        self.record_selection(
                            expr,
                            name,
                            dm_ir::SelectedMeaning::ProcedureValue(path),
                        );
                        self.emit(
                            opcode::PUSH_VAL,
                            vec![Word::Value(ValueWord::ProcPath(path))],
                        );
                        return Ok(());
                    }
                    if name == "__TYPE__" {
                        if let Some(path) = self.bindings.current_type_path.as_ref() {
                            let path = path.clone();
                            let tag = self.class_tag(&path)?.ok_or_else(|| {
                                error(statement, "__TYPE__ has unsupported owner type")
                            })?;
                            self.record_selection(
                                expr,
                                name,
                                dm_ir::SelectedMeaning::TypeValue(Some(SymbolId::of(&path))),
                            );
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
                        } else {
                            self.record_selection(
                                expr,
                                name,
                                dm_ir::SelectedMeaning::TypeValue(None),
                            );
                            self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                        }
                        return Ok(());
                    }
                    match dm_ir::predefined_resolution::select_predefined(
                        &predefined_resolution::PredefinedCompiler(self),
                        name,
                    )? {
                        Some(dm_ir::predefined_resolution::PredefinedConstant::NumberBits(
                            bits,
                        )) => {
                            self.record_selection(
                                expr,
                                name,
                                dm_ir::SelectedMeaning::NumericConstant(bits),
                            );
                            let number = f32::from_bits(bits);
                            if number >= 0.0 && number <= u16::MAX as f32 && number.fract() == 0.0 {
                                self.emit(opcode::PUSH_INT, vec![Word::Immediate(number as u32)]);
                            } else {
                                self.emit(
                                    opcode::PUSH_VAL,
                                    vec![Word::Value(ValueWord::Number(bits))],
                                );
                            }
                            return Ok(());
                        }
                        Some(dm_ir::predefined_resolution::PredefinedConstant::Text(value)) => {
                            self.record_selection(
                                expr,
                                name,
                                dm_ir::SelectedMeaning::StringConstant(SymbolId::of(&value)),
                            );
                            self.intern_string(&value);
                            self.emit(
                                opcode::PUSH_VAL,
                                vec![Word::Value(ValueWord::String(SymbolId::of(&value)))],
                            );
                            return Ok(());
                        }
                        None => {}
                    }
                }
                let var = self.variable_for_node(expr, name, statement)?;
                self.emit(opcode::GET_VAR, vec![Word::Variable(var)]);
            }
            ExprKind::Member { .. } => {
                let mut safe_labels = Vec::new();
                self.validate_member_var(expr, statement)?;
                let var = match self.variable_expr(expr, statement) {
                    Ok(var) => var,
                    Err(_) => {
                        let ExprKind::Member {
                            object, selector, ..
                        } = &expr.kind
                        else {
                            return Err(error(statement, "unsupported member expression"));
                        };
                        self.expression(object, statement)?;
                        safe_labels = self.defer_safe_postfix_labels(object);
                        self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                        if let Some(symbol) = self.fallback_member_global(
                            object,
                            selector,
                            matches!(
                                &expr.kind,
                                ExprKind::Member {
                                    via_colon: true,
                                    ..
                                }
                            ),
                        )? {
                            self.record_property_selection(
                                expr,
                                selector,
                                &VariableWord::Global(symbol),
                                false,
                            );
                            VariableWord::Global(symbol)
                        } else {
                            self.intern_string(selector);
                            self.record_property_selection(
                                expr,
                                selector,
                                &VariableWord::Field(SymbolId::of(selector)),
                                false,
                            );
                            VariableWord::Field(SymbolId::of(selector))
                        }
                    }
                };
                self.emit(opcode::GET_VAR, vec![Word::Variable(var)]);
                self.result.code.items.extend(safe_labels);
            }
            ExprKind::StaticMember { object, selector } => {
                if let ExprKind::TypePath(path) = &peel_groups(object).kind {
                    if let Some(default) = self.static_list_default(path, selector) {
                        return self.expression(&default, statement);
                    }
                    // `Type::name` of a `const` variable reads the variable (DreamMaker does not take `initial()` of it).
                    if let Ok(Some(symbol)) = self.member_global(path, selector) {
                        if self.is_constant_variable(symbol) {
                            self.emit(
                                opcode::GET_VAR,
                                vec![Word::Variable(VariableWord::Global(symbol))],
                            );
                            return Ok(());
                        }
                    }
                }
                self.record_property_selection(
                    expr,
                    selector,
                    &VariableWord::StaticField(SymbolId::of(selector)),
                    false,
                );
                self.expression(object, statement)?;
                let safe_labels = self.defer_safe_postfix_labels(object);
                self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                self.intern_string(selector);
                self.emit(
                    opcode::GET_VAR,
                    vec![Word::Variable(VariableWord::StaticField(SymbolId::of(
                        selector,
                    )))],
                );
                self.result.code.items.extend(safe_labels);
            }
            ExprKind::SafeMember {
                object,
                selector,
                via_colon,
            } => {
                self.expression(object, statement)?;
                let end = self.label();
                self.emit(317, vec![Word::Branch(end)]);
                let shared = if *via_colon {
                    None
                } else {
                    self.expression_member_global(object, selector)?
                };
                let variable = shared
                    .map(VariableWord::Global)
                    .unwrap_or_else(|| VariableWord::Field(SymbolId::of(selector)));
                if matches!(variable, VariableWord::Field(_)) {
                    self.intern_string(selector);
                }
                self.record_property_selection(expr, selector, &variable, true);
                self.emit(opcode::GET_VAR, vec![Word::Variable(variable)]);
                self.result.code.items.push(CodeItem::Label(end));
            }
            ExprKind::Index { object, index } => {
                self.expression(object, statement)?;
                let safe_labels = self.defer_safe_postfix_labels(object);
                self.expression(index, statement)?;
                self.emit(opcode::LIST_GET, vec![]);
                self.result.code.items.extend(safe_labels);
            }
            ExprKind::SafeIndex { object, index } => {
                self.expression(object, statement)?;
                let end = self.label();
                self.emit(317, vec![Word::Branch(end)]);
                self.emit(opcode::PUSH_CACHE, vec![]);
                self.emit(opcode::GET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                self.expression(index, statement)?;
                self.emit(opcode::LIST_GET, vec![]);
                self.emit(opcode::POP_CACHE, vec![]);
                self.result.code.items.push(CodeItem::Label(end));
            }
            ExprKind::Group(inner) => self.expression(inner, statement)?,
            ExprKind::Unary { op, value } => {
                if matches!(op.as_str(), "post++" | "post--" | "pre++" | "pre--") {
                    let opcode = match op.as_str() {
                        "pre++" => 0x62,
                        "post++" => 0x63,
                        "pre--" => 0x64,
                        "post--" => 0x65,
                        _ => unreachable!(),
                    };
                    return self.inc_dec(value, opcode, statement);
                }
                if op == "new" {
                    if let ExprKind::Call {
                        callee,
                        args: method_args,
                    } = &value.kind
                    {
                        if let ExprKind::Member {
                            object, selector, ..
                        } = &callee.kind
                        {
                            if matches!(&object.kind, ExprKind::Call { callee, .. } if matches!(&callee.kind, ExprKind::TypePath(_)))
                            {
                                let constructor = Expr {
                                    kind: ExprKind::Unary {
                                        op: "new".into(),
                                        value: object.clone(),
                                    },
                                    span: expr.span,
                                };
                                self.expression(&constructor, statement)?;
                                self.emit(
                                    opcode::SET_VAR,
                                    vec![Word::Variable(VariableWord::Cache)],
                                );
                                self.emit(opcode::PUSH_CACHE, vec![]);
                                let named = method_args.iter().any(|arg| matches!(&arg.kind, ExprKind::Binary { op, .. } if op == "="));
                                if named {
                                    self.named_arguments(method_args, statement)?;
                                } else {
                                    for arg in method_args {
                                        self.expression(arg, statement)?;
                                    }
                                }
                                self.emit(opcode::POP_CACHE, vec![]);
                                let proc_selector =
                                    if let ExprKind::Call { callee, .. } = &object.kind {
                                        if let ExprKind::TypePath(path) = &callee.kind {
                                            self.member_proc(path, selector)?
                                        } else {
                                            None
                                        }
                                    } else {
                                        None
                                    };
                                let proc_selector =
                                    proc_selector.map(member_proc_selector).unwrap_or_else(|| {
                                        VariableWord::DynamicProc(
                                            self.intern_string(&selector.replace('_', " ")),
                                        )
                                    });
                                self.emit(
                                    opcode::CALL,
                                    vec![
                                        Word::Variable(proc_selector),
                                        Word::Immediate(if named {
                                            u16::MAX as u32
                                        } else {
                                            method_args.len() as u32
                                        }),
                                    ],
                                );
                                return Ok(());
                            }
                        }
                    }
                    let (target, args): (&Expr, &[Expr]) = match &value.kind {
                        ExprKind::Call { callee, args } => (callee, args),
                        _ => (value, &[]),
                    };
                    // Native new accepts class values and proc/verb references.
                    // Use the same symbolic path encoding as ordinary values.
                    self.expression(target, statement)?;
                    if args
                        .iter()
                        .any(|arg| matches!(&arg.kind, ExprKind::Binary { op, .. } if op == "="))
                    {
                        self.named_arguments(args, statement)?;
                        self.emit(0xcf, vec![]);
                    } else if let [Expr {
                        kind:
                            ExprKind::Call {
                                callee,
                                args: list_args,
                            },
                        ..
                    }] = args
                    {
                        if matches!(&callee.kind, ExprKind::Ident(name) if name == "arglist") {
                            let [list] = list_args.as_slice() else {
                                return Err(error(statement, "arglist() requires one argument"));
                            };
                            self.expression(list, statement)?;
                            self.emit(0xcf, vec![]);
                        } else {
                            self.expression(&args[0], statement)?;
                            self.emit(opcode::NEW, vec![Word::Immediate(1)]);
                        }
                    } else {
                        for arg in args {
                            self.expression(arg, statement)?;
                        }
                        self.emit(opcode::NEW, vec![Word::Immediate(args.len() as u32)]);
                    }
                    return Ok(());
                }
                self.expression(value, statement)?;
                let opcode = match op.as_str() {
                    "-" => opcode::UNARY_NEG,
                    "!" => opcode::NOT,
                    "~" => opcode::BNOT,
                    // DreamMaker accepts the pointer dereference `*x` on any operand; the
                    // value of a non-pointer operand is the operand itself.
                    "+" | "*" => return Ok(()),
                    _ => return Err(error(statement, "unsupported unary operator")),
                };
                self.emit(opcode, vec![]);
            }
            ExprKind::Binary { op, lhs, rhs }
                if dm_syntax::assignment_target_access(op)
                    == Some(dm_syntax::ReferenceAccess::Write) =>
            {
                if let ExprKind::Index { object, index } = &lhs.kind {
                    self.expression(rhs, statement)?;
                    self.emit(opcode::PUSH_TOP, vec![]);
                    self.expression(object, statement)?;
                    self.expression(index, statement)?;
                    self.emit(opcode::LIST_SET, vec![]);
                    return Ok(());
                }
                if let ExprKind::Member {
                    object,
                    selector,
                    via_colon: false,
                } = &lhs.kind
                {
                    // A parenthesized receiver is not a plain reference chain to DreamMaker: the value is kept with
                    // `PushTop` and the receiver goes through the cache register, not `SetVarExpr`.
                    if self.variable_expr(object, statement).is_err()
                        || parenthesized_receiver(object)
                    {
                        self.expression(rhs, statement)?;
                        self.emit(opcode::PUSH_TOP, vec![]);
                        self.expression(object, statement)?;
                        self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                        self.intern_string(selector);
                        self.emit(
                            opcode::SET_VAR,
                            vec![Word::Variable(VariableWord::Field(SymbolId::of(selector)))],
                        );
                        return Ok(());
                    }
                }
                let var = self.variable_expr(lhs, statement)?;
                self.expression(rhs, statement)?;
                self.emit(opcode::SET_VAR_EXPR, vec![Word::Variable(var)]);
            }
            ExprKind::Binary { op, lhs, rhs } if op == "||=" || op == "&&=" => {
                let variable = self.assignment_variable(lhs, statement)?;
                self.emit(opcode::GET_VAR, vec![Word::Variable(variable.clone())]);
                let end = self.label();
                self.emit(
                    if op == "||=" {
                        opcode::JMP_OR
                    } else {
                        opcode::JMP_AND
                    },
                    vec![Word::Branch(end)],
                );
                self.assignment_value_preserving_cache(&variable, rhs, statement)?;
                self.emit(opcode::SET_VAR_EXPR, vec![Word::Variable(variable)]);
                self.result.code.items.push(CodeItem::Label(end));
            }
            ExprKind::Binary { op, lhs, rhs } if op == "<<=" || op == ">>=" => {
                self.assign_expr(lhs, op, rhs, statement)?;
                self.emit(0x13f, vec![]);
            }
            ExprKind::Binary { op, lhs, rhs }
                if matches!(
                    op.as_str(),
                    "+=" | "-=" | "*=" | "/=" | "%=" | "&=" | "|=" | "^="
                ) =>
            {
                self.assign_expr(lhs, op, rhs, statement)?;
                self.emit(0x13f, vec![]);
            }
            ExprKind::Binary { op, lhs, rhs } => {
                if op == "<<" && is_output_target(lhs) {
                    return Err(error(
                        statement,
                        "output operator requires statement context",
                    ));
                }
                if op == "||" || op == "&&" {
                    let operands = self.short_circuit_operands(expr, op, statement)?;
                    let Some((first, tails)) = operands.split_first() else {
                        return Err(error(statement, "empty short-circuit chain"));
                    };
                    self.expression(first, statement)?;
                    if tails.is_empty() {
                        return Ok(());
                    }
                    let end = self.label();
                    for next in tails {
                        self.emit(
                            if op == "||" {
                                opcode::JMP_OR
                            } else {
                                opcode::JMP_AND
                            },
                            vec![Word::Branch(end)],
                        );
                        self.expression(next, statement)?;
                    }
                    self.result.code.items.push(CodeItem::Label(end));
                    return Ok(());
                }
                if op == "*" {
                    return self.multiplication(lhs, rhs, true, statement);
                }
                self.expression(lhs, statement)?;
                if op == "**" && fold_number(rhs) == Some(2.0) {
                    // DreamMaker squares with its own opcode (Square, 0x173) instead of pushing 2 and calling Pow.
                    self.emit(0x173, vec![]);
                    return Ok(());
                }
                self.expression(rhs, statement)?;
                let opcode = match op.as_str() {
                    "+" => opcode::ADD,
                    "-" => opcode::SUB,
                    "*" => opcode::MUL,
                    "**" => 0x6a,
                    "/" => opcode::DIV,
                    "%" => opcode::MOD,
                    "==" => opcode::TEQ,
                    "!=" => opcode::TNE,
                    "~=" => 0x140,
                    "~!" => 0x141,
                    "<" => opcode::TL,
                    ">" => opcode::TG,
                    "<=" => opcode::TLE,
                    ">=" => opcode::TGE,
                    "&" => opcode::BAND,
                    "|" => opcode::BOR,
                    "^" => opcode::BXOR,
                    "<<" => opcode::LSHIFT,
                    ">>" => opcode::RSHIFT,
                    _ => return Err(error(statement, "unsupported binary operator")),
                };
                self.emit(opcode, vec![]);
                if op == "==" {
                    self.emit(opcode::POP, vec![]);
                    self.emit(opcode::GET_FLAG, vec![]);
                }
            }
            ExprKind::Call { callee, args } => {
                self.expression_call(expr, callee, args, statement)?;
            }
        }
        Ok(())
    }
}

impl Compiler<'_> {
    /// `lhs * rhs`. DreamMaker squares with `Square` (0x173) when both operands are the same side-effect-free
    /// expression, except for a product that is the left operand of another product (`a*a*b` is `a a Mul b Mul`, while
    /// `b*(a*a)` is `b a Square Mul`): a left-nested chain of products is emitted as plain multiplications.
    fn multiplication(
        &mut self,
        lhs: &Expr,
        rhs: &Expr,
        square_ok: bool,
        statement: &str,
    ) -> Result<(), LowerError> {
        if square_ok && same_pure_expression(lhs, rhs) {
            self.expression(lhs, statement)?;
            self.emit(0x173, vec![]);
            return Ok(());
        }
        let mut left = lhs;
        while let ExprKind::Group(inner) = &left.kind {
            left = inner;
        }
        // A sub-product of `const` variables is a constant; a `const` variable on the left of a product is its value.
        let folded = self
            .substitute_constants(left)
            .filter(|substituted| fold_number(substituted).is_some());
        match &left.kind {
            _ if folded.is_some() => self.expression(folded.as_ref().unwrap(), statement)?,
            ExprKind::Binary {
                op,
                lhs: l2,
                rhs: r2,
            } if op == "*" && fold_number(left).is_none() => {
                self.multiplication(l2, r2, false, statement)?
            }
            _ => match self.const_reference_literal(left) {
                Some(value) => self.expression(&value, statement)?,
                None => self.expression(lhs, statement)?,
            },
        }
        self.expression(rhs, statement)?;
        self.emit(opcode::MUL, vec![]);
        Ok(())
    }
}

/// The two expressions are written the same and DreamMaker treats the text as a plain value: names, member reads,
/// numbers, negation and the arithmetic and comparison operators measured against `dm.exe`
/// (`+ - / % ** >`, `round()`), but not products, bit operations, `!`, `~`, indexing, ternaries or calls.
fn same_pure_expression(a: &Expr, b: &Expr) -> bool {
    use ExprKind::*;
    let (mut a, mut b) = (a, b);
    while let Group(inner) = &a.kind {
        a = inner;
    }
    while let Group(inner) = &b.kind {
        b = inner;
    }
    match (&a.kind, &b.kind) {
        (Ident(x), Ident(y)) => x == y,
        (Literal(x), Literal(y)) => x == y,
        (
            Member {
                object: o1,
                selector: s1,
                via_colon: false,
            },
            Member {
                object: o2,
                selector: s2,
                via_colon: false,
            },
        ) => s1 == s2 && same_pure_expression(o1, o2),
        (Unary { op: p1, value: v1 }, Unary { op: p2, value: v2 }) => {
            p1 == "-" && p2 == "-" && same_pure_expression(v1, v2)
        }
        (
            Binary {
                op: p1,
                lhs: l1,
                rhs: r1,
            },
            Binary {
                op: p2,
                lhs: l2,
                rhs: r2,
            },
        ) => {
            p1 == p2
                && matches!(p1.as_str(), "+" | "-" | "/" | "%" | "**" | ">")
                && same_pure_expression(l1, l2)
                && same_pure_expression(r1, r2)
        }
        (
            Call {
                callee: c1,
                args: a1,
            },
            Call {
                callee: c2,
                args: a2,
            },
        ) => {
            matches!((&c1.kind, &c2.kind), (Ident(x), Ident(y)) if x == "round" && y == "round")
                && a1.len() == a2.len()
                && a1.iter().zip(a2).all(|(x, y)| same_pure_expression(x, y))
        }
        _ => false,
    }
}

/// Truthiness of a plain text literal (`""` is false, any other constant text true); None for anything with
/// interpolation or any other expression.
pub(super) fn constant_text_truth(expr: &Expr) -> Option<bool> {
    let mut expr = expr;
    while let ExprKind::Group(inner) = &expr.kind {
        expr = inner;
    }
    let ExprKind::Literal(raw) = &expr.kind else {
        return None;
    };
    if raw.starts_with("@'") {
        return None;
    }
    match decode_constant_string_literal(raw) {
        Ok(Some(text)) => Some(!text.is_empty()),
        _ => None,
    }
}

fn is_associative_operator(op: &str) -> bool {
    matches!(op, "+" | "*" | "|" | "&" | "^")
}

/// A member chain with a parenthesis anywhere in it (`(a).b`, `(a.b).c`).
fn parenthesized_receiver(expr: &Expr) -> bool {
    match &expr.kind {
        ExprKind::Group(_) => true,
        ExprKind::Member { object, .. } | ExprKind::SafeMember { object, .. } => {
            parenthesized_receiver(object)
        }
        _ => false,
    }
}

pub(super) fn peel_groups(expr: &Expr) -> &Expr {
    let mut expr = expr;
    while let ExprKind::Group(inner) = &expr.kind {
        expr = inner;
    }
    expr
}

/// DreamMaker builds `(l op x) op r` as `l op (x op r)` when `x` is itself an `op` expression, for `+ * | & ^` (measured
/// against dm.exe: `"P" + (a + b) + "."` is `P (a b Add) "." Add Add`, `a - (b - c) - d` and `a + (b - c) + d` are
/// not rewritten). The rewrite happens as each node is built, so a longer chain keeps moving to the right
/// (`a + (b + c) + d + e` is `a + (((b + c) + d) + e)`).
fn reassociate(expr: &Expr, changed: &mut bool) -> Expr {
    match &expr.kind {
        ExprKind::Group(inner) => Expr {
            kind: ExprKind::Group(Box::new(reassociate(inner, changed))),
            span: expr.span,
        },
        ExprKind::Binary { op, lhs, rhs } if is_associative_operator(op) => {
            let (l, r) = (reassociate(lhs, changed), reassociate(rhs, changed));
            associative_node(op, expr.span, l, r, changed)
        }
        _ => expr.clone(),
    }
}

fn associative_node(
    op: &str,
    span: dm_syntax::Span,
    lhs: Expr,
    rhs: Expr,
    changed: &mut bool,
) -> Expr {
    if let ExprKind::Binary {
        op: left_op,
        lhs: first,
        rhs: middle,
    } = &peel_groups(&lhs).kind
    {
        if left_op == op
            && matches!(&peel_groups(middle).kind, ExprKind::Binary { op: inner, .. } if inner == op)
        {
            *changed = true;
            let inner = associative_node(op, span, (**middle).clone(), rhs, changed);
            return Expr {
                kind: ExprKind::Binary {
                    op: op.to_string(),
                    lhs: first.clone(),
                    rhs: Box::new(inner),
                },
                span,
            };
        }
    }
    Expr {
        kind: ExprKind::Binary {
            op: op.to_string(),
            lhs: Box::new(lhs),
            rhs: Box::new(rhs),
        },
        span,
    }
}

/// Whether DreamMaker folds the truth of `expr` at compile time: a number, a plain text literal, `!`, and `||`, `&&` and
/// `?:` chains whose deciding side is constant (the other side need not be).
pub(super) fn constant_truth(expr: &Expr) -> Option<bool> {
    if let Some(number) = fold_number(expr) {
        return Some(number != 0.0);
    }
    let expr = peel_groups(expr);
    match &expr.kind {
        ExprKind::Literal(raw) if raw == "null" => Some(false),
        // A `list(...)` of constants is an object, so it is true (`list(EAST, WEST) ? a : b` is `a`).
        ExprKind::Call { callee, args }
            if matches!(&callee.kind, ExprKind::Ident(name) if name == "list")
                && args.iter().all(|arg| {
                    fold_number(arg).is_some() || constant_text_truth(arg).is_some()
                }) =>
        {
            Some(true)
        }
        ExprKind::Literal(_) => constant_text_truth(expr),
        ExprKind::Unary { op, value } if op == "!" => constant_truth(value).map(|truth| !truth),
        ExprKind::Binary { op, lhs, rhs } if op == "||" => match constant_truth(lhs)? {
            true => Some(true),
            false => constant_truth(rhs),
        },
        ExprKind::Binary { op, lhs, rhs } if op == "&&" => match constant_truth(lhs)? {
            false => Some(false),
            true => constant_truth(rhs),
        },
        ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } => match constant_truth(condition)? {
            true => constant_truth(then_value),
            false => constant_truth(else_value),
        },
        _ => None,
    }
}

impl Compiler<'_> {
    /// The operands of an `&&` or `||` chain that DreamMaker keeps, in order. The chain is flattened through parentheses
    /// of the same operator; a constant that cannot decide the result (true in `&&`, false in `||`) is dropped unless it is
    /// last, and a constant that decides it ends the chain (measured against dm.exe: `a && 0 && b` is `a && 0`,
    /// `a && 1 && b` is `a && b`, `a || null || b` is `a || b`). Dropped operands are still lowered for their diagnostics.
    pub(super) fn short_circuit_operands<'e>(
        &mut self,
        expr: &'e Expr,
        op: &str,
        statement: &str,
    ) -> Result<Vec<&'e Expr>, LowerError> {
        fn collect<'e>(expr: &'e Expr, op: &str, out: &mut Vec<&'e Expr>) {
            match &peel_groups(expr).kind {
                ExprKind::Binary {
                    op: inner,
                    lhs,
                    rhs,
                } if inner == op => {
                    collect(lhs, op, out);
                    collect(rhs, op, out);
                }
                _ => out.push(expr),
            }
        }
        let mut all = Vec::new();
        collect(expr, op, &mut all);
        let mut kept = Vec::with_capacity(all.len());
        let mut done = false;
        let last = all.len().saturating_sub(1);
        for (index, operand) in all.into_iter().enumerate() {
            if done {
                self.lower_dead(|compiler| compiler.expression(operand, statement))?;
                continue;
            }
            match constant_truth(operand).or_else(|| self.const_reference_truth(operand)) {
                Some(truth) if truth == (op == "&&") && index != last => {
                    self.lower_dead(|compiler| compiler.expression(operand, statement))?;
                }
                Some(_) => {
                    kept.push(operand);
                    // A constant that decides the result, or the last operand.
                    done = true;
                }
                None => kept.push(operand),
            }
        }
        Ok(kept)
    }
}
