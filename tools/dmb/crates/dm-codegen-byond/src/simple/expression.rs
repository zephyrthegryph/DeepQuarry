//! Expression lowering over the shared compiler context.
use super::*;

impl Compiler<'_> {
    pub(super) fn expression(&mut self, expr: &Expr, statement: &str) -> Result<(), LowerError> {
        if let Some(number) = fold_number(expr) {
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
                    self.input_call(args, types, None, statement)?;
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
                    self.input_call(args, types, Some(rhs), statement)?;
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
                    self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
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
                    if let Some(bits) = self.numeric_constant(name)? {
                        self.record_selection(
                            expr,
                            name,
                            dm_ir::SelectedMeaning::NumericConstant(bits),
                        );
                        let number = f32::from_bits(bits);
                        if number >= 0.0 && number <= u16::MAX as f32 && number.fract() == 0.0 {
                            self.emit(opcode::PUSH_INT, vec![Word::Immediate(number as u32)]);
                        } else {
                            self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Number(bits))]);
                        }
                        return Ok(());
                    }
                    if let Some(value) = self.string_constant(name)? {
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
                }
                let var = self.variable_for_node(expr, name, statement)?;
                self.emit(opcode::GET_VAR, vec![Word::Variable(var)]);
            }
            ExprKind::Member { .. } => {
                let mut safe_labels = Vec::new();
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
            ExprKind::SafeMember { object, selector } => {
                self.expression(object, statement)?;
                let end = self.label();
                self.emit(317, vec![Word::Branch(end)]);
                let variable = self
                    .expression_member_global(object, selector)?
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
                    "+" => return Ok(()),
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
                    if self.variable_expr(object, statement).is_err() {
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
                    let mut tails = vec![rhs.as_ref()];
                    let mut first = lhs.as_ref();
                    while let ExprKind::Binary {
                        op: inner_op,
                        lhs: inner_lhs,
                        rhs: inner_rhs,
                    } = &first.kind
                    {
                        if inner_op != op {
                            break;
                        }
                        tails.push(inner_rhs);
                        first = inner_lhs;
                    }
                    self.expression(first, statement)?;
                    let end = self.label();
                    for next in tails.into_iter().rev() {
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
                self.expression(lhs, statement)?;
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
