//! Assignments lowering over the shared compiler context.
use super::*;

impl Compiler<'_> {
    pub(super) fn assign_expr(
        &mut self,
        target: &Expr,
        op: &str,
        value: &Expr,
        statement: &str,
    ) -> Result<(), LowerError> {
        if op == "||=" || op == "&&=" {
            let variable = self.assignment_variable(target, statement)?;
            self.emit(opcode::GET_VAR, vec![Word::Variable(variable.clone())]);
            self.emit(opcode::TEST, vec![]);
            let end = self.label();
            self.emit(
                if op == "||=" { opcode::JNZ } else { opcode::JZ },
                vec![Word::Branch(end)],
            );
            self.assignment_value_preserving_cache(&variable, value, statement)?;
            self.emit(opcode::SET_VAR, vec![Word::Variable(variable)]);
            self.result.code.items.push(CodeItem::Label(end));
            return Ok(());
        }
        if let ExprKind::Index { object, index } = &target.kind {
            if op != "=" {
                let opcode = match op {
                    "+=" => opcode::AUG_ADD,
                    "-=" => opcode::AUG_SUB,
                    "*=" => opcode::AUG_MUL,
                    "/=" => opcode::AUG_DIV,
                    "%=" => opcode::AUG_MOD,
                    "&=" => opcode::AUG_BAND,
                    "|=" => opcode::AUG_BOR,
                    "^=" => opcode::AUG_XOR,
                    "<<=" => 0x4d,
                    ">>=" => 0x4e,
                    _ => return Err(error(statement, "unsupported indexed assignment")),
                };
                self.expression(value, statement)?;
                self.expression(object, statement)?;
                self.expression(index, statement)?;
                self.emit(
                    opcode::SET_VAR,
                    vec![Word::Variable(VariableWord::CacheKey)],
                );
                self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                self.emit(opcode, vec![Word::Variable(VariableWord::CacheIndex)]);
                return Ok(());
            }
        }
        if let ExprKind::SafeMember { object, selector } = &target.kind {
            let constant_first = op == "=" && Self::safe_assignment_constant(value);
            if constant_first {
                self.expression(value, statement)?;
            }
            self.expression(object, statement)?;
            let end = self.label();
            self.emit(318, vec![Word::Branch(end)]);
            if !constant_first {
                self.emit(opcode::PUSH_CACHE, vec![]);
                self.expression(value, statement)?;
                self.emit(opcode::POP_CACHE, vec![]);
            }
            let variable = self
                .expression_member_global(object, selector)?
                .map(VariableWord::Global)
                .unwrap_or_else(|| VariableWord::Field(SymbolId::of(selector)));
            if matches!(variable, VariableWord::Field(_)) {
                self.intern_string(selector);
            }
            let assignment_opcode = match op {
                "=" => opcode::SET_VAR,
                "+=" => opcode::AUG_ADD,
                "-=" => opcode::AUG_SUB,
                "*=" => opcode::AUG_MUL,
                "/=" => opcode::AUG_DIV,
                "%=" => opcode::AUG_MOD,
                "&=" => opcode::AUG_BAND,
                "|=" => opcode::AUG_BOR,
                "^=" => opcode::AUG_XOR,
                "<<=" => 0x4d,
                ">>=" => 0x4e,
                _ => return Err(error(statement, "unsupported safe member assignment")),
            };
            self.emit(assignment_opcode, vec![Word::Variable(variable)]);
            self.result.code.items.push(CodeItem::Label(end));
            return Ok(());
        }
        if let ExprKind::SafeIndex { object, index } = &target.kind {
            let constant_first = op == "=" && Self::safe_assignment_constant(value);
            if constant_first {
                self.expression(value, statement)?;
            }
            self.expression(object, statement)?;
            let end = self.label();
            self.emit(318, vec![Word::Branch(end)]);
            if !constant_first {
                self.emit(opcode::PUSH_CACHE, vec![]);
                self.expression(value, statement)?;
                self.emit(opcode::POP_CACHE, vec![]);
            }
            self.emit(opcode::GET_VAR, vec![Word::Variable(VariableWord::Cache)]);
            self.expression(index, statement)?;
            if op == "=" {
                self.emit(opcode::LIST_SET, vec![]);
            } else {
                let opcode = match op {
                    "+=" => opcode::AUG_ADD,
                    "-=" => opcode::AUG_SUB,
                    "*=" => opcode::AUG_MUL,
                    "/=" => opcode::AUG_DIV,
                    "%=" => opcode::AUG_MOD,
                    "&=" => opcode::AUG_BAND,
                    "|=" => opcode::AUG_BOR,
                    "^=" => opcode::AUG_XOR,
                    "<<=" => 0x4d,
                    ">>=" => 0x4e,
                    _ => return Err(error(statement, "unsupported safe indexed assignment")),
                };
                self.emit(
                    opcode::SET_VAR,
                    vec![Word::Variable(VariableWord::CacheKey)],
                );
                self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                self.emit(opcode, vec![Word::Variable(VariableWord::CacheIndex)]);
            }
            self.result.code.items.push(CodeItem::Label(end));
            return Ok(());
        }
        if op == "=" {
            if let ExprKind::Index { object, index } = &target.kind {
                self.expression(value, statement)?;
                self.expression(object, statement)?;
                self.expression(index, statement)?;
                self.emit(opcode::LIST_SET, vec![]);
                return Ok(());
            }
            if let ExprKind::Member {
                object, selector, ..
            } = &target.kind
            {
                if self.variable_expr(target, statement).is_err() {
                    self.expression(value, statement)?;
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
            let var = self.variable_expr(target, statement)?;
            self.ensure_writable(&var, statement)?;
            if Self::assignment_needs_target_type(value) {
                if let Some(path) = self.inferred_expression_type(target)? {
                    let declaration = format!("var{path}/__value");
                    self.local_initializer(value, &declaration, statement)?;
                } else {
                    self.expression(value, statement)?;
                }
            } else {
                // This RHS cannot consume the target's declared type. Preserve
                // recursive initializer emission without unrelated metadata IO.
                self.local_initializer(value, "var/__value", statement)?;
            }
            self.emit(opcode::SET_VAR, vec![Word::Variable(var)]);
            return Ok(());
        }
        let opcode = match op {
            "+=" => opcode::AUG_ADD,
            "-=" => opcode::AUG_SUB,
            "*=" => opcode::AUG_MUL,
            "/=" => opcode::AUG_DIV,
            "%=" => opcode::AUG_MOD,
            "&=" => opcode::AUG_BAND,
            "|=" => opcode::AUG_BOR,
            "^=" => opcode::AUG_XOR,
            "<<=" => 0x4d,
            ">>=" => 0x4e,
            _ => return Err(error(statement, "unsupported assignment operator")),
        };
        self.expression(value, statement)?;
        let variable = match self.variable_expr(target, statement) {
            Ok(variable) => variable,
            Err(_) => {
                let ExprKind::Member {
                    object, selector, ..
                } = &target.kind
                else {
                    return Err(error(statement, "unsupported assignment target"));
                };
                self.expression(object, statement)?;
                self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                self.intern_string(selector);
                VariableWord::Field(SymbolId::of(selector))
            }
        };
        self.ensure_writable(&variable, statement)?;
        self.emit(opcode, vec![Word::Variable(variable)]);
        Ok(())
    }

    pub(super) fn expression_text(
        &mut self,
        expression: &str,
        statement: &str,
    ) -> Result<(), LowerError> {
        let parsed = parse_expression(expression);
        if !parsed.diagnostics.is_empty() {
            return Err(error(statement, "expression syntax is unsupported"));
        }
        let expression = parsed
            .expr
            .ok_or_else(|| error(statement, "missing expression"))?;
        self.expression(&expression, statement)
    }

    pub(super) fn variable(
        &mut self,
        name: &str,
        statement: &str,
    ) -> Result<VariableWord, LowerError> {
        let meaning = self.variable_meaning(name, statement)?;
        self.variable_operand(&meaning, name, statement)
    }
    pub(super) fn variable_expr(
        &mut self,
        expr: &Expr,
        statement: &str,
    ) -> Result<VariableWord, LowerError> {
        let word = self.variable_expr_inner(expr, statement)?;
        if let ExprKind::Member { selector, .. } = &expr.kind {
            self.record_property_selection(expr, selector, &word, false);
        }
        Ok(word)
    }
    fn variable_expr_inner(
        &mut self,
        expr: &Expr,
        statement: &str,
    ) -> Result<VariableWord, LowerError> {
        match &expr.kind {
            ExprKind::Ident(name) => self.variable_for_node(expr, name, statement),
            ExprKind::Group(inner) => self.variable_expr(inner, statement),
            ExprKind::Member {
                object,
                selector,
                via_colon,
            } => {
                if dm_syntax::is_global_receiver(object) {
                    if selector == "vars" {
                        return Ok(VariableWord::Global(SymRef::BuiltinGlobalVars));
                    }
                    if self.has_global(selector)? {
                        if let Some(lookup) = self.lookup {
                            let query = dm_ir::ResolveQuery::VarStorage {
                                owner: dm_ir::SymbolId::of("/"),
                                name: dm_ir::SymbolId::of(selector),
                            };
                            let slot = self.semantic(lookup.slot(query))?.ok_or_else(|| {
                                error(statement, "global variable has no shared storage")
                            })?;
                            return Ok(VariableWord::Global(slot));
                        }
                        return Ok(VariableWord::Global(self.global_variable(selector)?));
                    }
                    return Err(error(
                        statement,
                        &format!("unresolved global variable: {selector}"),
                    ));
                }
                if let Some(owner) = if *via_colon {
                    None
                } else {
                    self.inferred_expression_type(object)?
                } {
                    if let Some(symbol) = self.member_global(&owner, selector)? {
                        return Ok(VariableWord::Global(symbol));
                    }
                }
                let owner = self.variable_expr(object, statement)?;
                self.intern_string(selector);
                Ok(VariableWord::SetCache(
                    Box::new(owner),
                    Box::new(VariableWord::Field(SymbolId::of(selector))),
                ))
            }
            _ => Err(error(statement, "unsupported variable target")),
        }
    }

    pub(super) fn assignment_value_preserving_cache(
        &mut self,
        variable: &VariableWord,
        value: &Expr,
        statement: &str,
    ) -> Result<(), LowerError> {
        let clobbers = !matches!(&value.kind, ExprKind::Ident(_) | ExprKind::TypePath(_))
            && !matches!(&value.kind, ExprKind::Literal(text) if !text.contains('['));
        let receiver =
            clobbers && matches!(variable, VariableWord::CacheIndex | VariableWord::Field(_));
        let index = clobbers && matches!(variable, VariableWord::CacheIndex);
        if receiver {
            self.emit(opcode::PUSH_CACHE, vec![]);
        }
        if index {
            self.emit(opcode::PUSH_CACHE_KEY, vec![]);
        }
        self.expression(value, statement)?;
        if index {
            self.emit(opcode::POP_CACHE_KEY, vec![]);
        }
        if receiver {
            self.emit(opcode::POP_CACHE, vec![]);
        }
        Ok(())
    }

    // Immutable RHS values cannot observe receiver evaluation or overwrite its
    // cache. Native safe writes place them before the receiver guard; dynamic
    // RHS expressions retain their guarded cache-preserving continuation.
    fn safe_assignment_constant(value: &Expr) -> bool {
        if fold_number(value).is_some() {
            return true;
        }
        match &value.kind {
            ExprKind::Group(inner) => Self::safe_assignment_constant(inner),
            ExprKind::Literal(raw) if matches!(raw.as_str(), "null" | "TRUE" | "FALSE") => true,
            ExprKind::Literal(raw) => matches!(decode_constant_string_literal(raw), Ok(Some(_))),
            _ => false,
        }
    }

    pub(super) fn assignment_variable(
        &mut self,
        target: &Expr,
        statement: &str,
    ) -> Result<VariableWord, LowerError> {
        if let ExprKind::Index { object, index } = &target.kind {
            self.expression(object, statement)?;
            self.expression(index, statement)?;
            self.emit(
                opcode::SET_VAR,
                vec![Word::Variable(VariableWord::CacheKey)],
            );
            self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
            return Ok(VariableWord::CacheIndex);
        }
        match self.variable_expr(target, statement) {
            Ok(variable) => {
                self.ensure_writable(&variable, statement)?;
                Ok(variable)
            }
            Err(_) => {
                let ExprKind::Member {
                    object, selector, ..
                } = &target.kind
                else {
                    return Err(error(statement, "unsupported assignment target"));
                };
                self.expression(object, statement)?;
                self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                if let Some(symbol) = self.fallback_member_global(
                    object,
                    selector,
                    matches!(
                        &target.kind,
                        ExprKind::Member {
                            via_colon: true,
                            ..
                        }
                    ),
                )? {
                    self.record_property_selection(
                        target,
                        selector,
                        &VariableWord::Global(symbol),
                        false,
                    );
                    return Ok(VariableWord::Global(symbol));
                }
                self.intern_string(selector);
                self.record_property_selection(
                    target,
                    selector,
                    &VariableWord::Field(SymbolId::of(selector)),
                    false,
                );
                Ok(VariableWord::Field(SymbolId::of(selector)))
            }
        }
    }

    pub(super) fn modified_fields(&mut self, fields: &[(String, Expr)]) -> Result<(), LowerError> {
        let owner = self
            .bindings
            .current_type_path
            .clone()
            .ok_or_else(|| error("modified initializer", "receiver type is missing"))?;
        for (index, (name, value)) in fields.iter().enumerate() {
            self.statement_span = Some(LowerSpan {
                start: value.span.start,
                end: value.span.end,
            });
            if let Some(debug) = self.debug {
                self.debug_current = Some(
                    debug
                        .ordinal(index)
                        .map_err(|reason| error("modified initializer", &reason))?,
                );
            }
            let lookup = self
                .lookup
                .ok_or_else(|| error("modified initializer", "immutable resolver is missing"))?;
            if !self.semantic(lookup.presence(dm_ir::ResolveQuery::HasMemberVar {
                owner: dm_ir::SymbolId::of(&owner),
                name: dm_ir::SymbolId::of(name),
            }))? {
                return Err(error("modified initializer", "modified field is absent"));
            }
            self.expression(value, "modified initializer")?;
            self.intern_string(name);
            self.emit(
                opcode::SET_VAR,
                vec![Word::Variable(VariableWord::SetCache(
                    Box::new(VariableWord::Src),
                    Box::new(VariableWord::Field(SymbolId::of(name))),
                ))],
            );
        }
        Ok(())
    }
    pub(super) fn inc_dec(
        &mut self,
        target: &Expr,
        opcode: u32,
        statement: &str,
    ) -> Result<(), LowerError> {
        if let ExprKind::Call { callee, args } = &target.kind {
            if matches!(&callee.kind, ExprKind::Ident(name) if name == "length") {
                let [list] = args.as_slice() else {
                    return Err(error(
                        statement,
                        "length increment requires one list variable",
                    ));
                };
                let variable = self.variable_expr(list, statement)?;
                self.emit(opcode, vec![Word::Variable(variable)]);
                return Ok(());
            }
        }
        if let ExprKind::Index { object, index } = &target.kind {
            self.expression(object, statement)?;
            self.expression(index, statement)?;
            self.emit(
                opcode::SET_VAR,
                vec![Word::Variable(VariableWord::CacheKey)],
            );
            self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
            self.emit(opcode, vec![Word::Variable(VariableWord::CacheIndex)]);
            return Ok(());
        }
        let variable = match self.variable_expr(target, statement) {
            Ok(variable) => variable,
            Err(_) => {
                let ExprKind::Member {
                    object, selector, ..
                } = &target.kind
                else {
                    return Err(error(statement, "increment target must be a variable"));
                };
                self.expression(object, statement)?;
                self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                self.intern_string(selector);
                VariableWord::Field(SymbolId::of(selector))
            }
        };
        self.ensure_writable(&variable, statement)?;
        self.emit(opcode, vec![Word::Variable(variable)]);
        Ok(())
    }

    pub(super) fn ensure_writable(
        &self,
        variable: &VariableWord,
        statement: &str,
    ) -> Result<(), LowerError> {
        if matches!(variable, VariableWord::Arg(slot) if self.bindings.readonly_parameters.contains(slot))
        {
            let mut failure = error(statement, "cannot change constant parameter binding");
            failure.kind = LowerErrorKind::SourceError;
            // Keep this semantic failure sticky across legacy syntax fallbacks.
            return self.semantic(Err(failure));
        }
        Ok(())
    }

    /// Mirrors contextual cases consumed by local_initializer. Nested call
    /// arguments/conditions use ordinary expression lowering, not target type.
    pub(super) fn assignment_needs_target_type(expr: &Expr) -> bool {
        match &expr.kind {
            ExprKind::Ident(name) => name == "new",
            ExprKind::Call { callee, args } => matches!(&callee.kind, ExprKind::Ident(name)
                if name == "new" || (name == "locate" && args.is_empty())),
            ExprKind::Group(inner) => Self::assignment_needs_target_type(inner),
            ExprKind::Binary { op, lhs, rhs } if op == "||" || op == "&&" => {
                Self::assignment_needs_target_type(lhs) || Self::assignment_needs_target_type(rhs)
            }
            ExprKind::Binary { op, lhs, .. } if op == "in" => {
                matches!(&lhs.kind, ExprKind::Call { callee, args }
                    if args.is_empty() && matches!(&callee.kind, ExprKind::Ident(name) if name == "locate"))
            }
            ExprKind::Conditional {
                then_value,
                else_value,
                ..
            } => {
                Self::assignment_needs_target_type(then_value)
                    || Self::assignment_needs_target_type(else_value)
            }
            _ => false,
        }
    }
    pub(super) fn local_initializer(
        &mut self,
        expr: &Expr,
        declaration: &str,
        statement: &str,
    ) -> Result<(), LowerError> {
        if let ExprKind::Group(inner) = &expr.kind {
            return self.local_initializer(inner, declaration, statement);
        }
        if let ExprKind::Binary { op, lhs, rhs } = &expr.kind {
            if op == "||" || op == "&&" {
                self.local_initializer(lhs, declaration, statement)?;
                let end = self.label();
                self.emit(
                    if op == "||" {
                        opcode::JMP_OR
                    } else {
                        opcode::JMP_AND
                    },
                    vec![Word::Branch(end)],
                );
                self.local_initializer(rhs, declaration, statement)?;
                self.result.code.items.push(CodeItem::Label(end));
                return Ok(());
            }
        }
        if matches!(&expr.kind, ExprKind::Call { callee, args }
            if args.is_empty() && matches!(&callee.kind, ExprKind::Ident(name) if name == "locate"))
        {
            let type_name = declaration
                .strip_prefix("var/")
                .and_then(|raw| raw.rsplit_once('/'))
                .map(|(path, _)| path)
                .filter(|path| !path.is_empty())
                .ok_or_else(|| error(statement, "locate() requires a typed assignment"))?;
            let path = runtime_declaration_path(type_name);
            let tag = self
                .class_tag(&path)?
                .ok_or_else(|| error(statement, "unsupported inferred locate type"))?;
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
            self.emit(0x5b, vec![]);
            return Ok(());
        }
        if let ExprKind::Binary { op, lhs, rhs } = &expr.kind {
            if op == "in"
                && matches!(&lhs.kind, ExprKind::Call { callee, args }
                    if args.is_empty() && matches!(&callee.kind, ExprKind::Ident(name) if name == "locate"))
            {
                let type_name = declaration
                    .strip_prefix("var/")
                    .and_then(|raw| raw.rsplit_once('/'))
                    .map(|(path, _)| path)
                    .filter(|path| !path.is_empty())
                    .ok_or_else(|| error(statement, "locate() requires a typed assignment"))?;
                let path = runtime_declaration_path(type_name);
                let tag = self
                    .class_tag(&path)?
                    .ok_or_else(|| error(statement, "unsupported inferred locate type"))?;
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
                self.expression(rhs, statement)?;
                self.emit(0x97, vec![]);
                return Ok(());
            }
        }
        if let ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } = &expr.kind
        {
            self.expression(condition, statement)?;
            self.emit(opcode::TEST, vec![]);
            let else_label = self.label();
            let end_label = self.label();
            self.emit(opcode::JZ, vec![Word::Branch(else_label)]);
            self.local_initializer(then_value, declaration, statement)?;
            self.emit(opcode::JMP, vec![Word::Branch(end_label)]);
            self.result.code.items.push(CodeItem::Label(else_label));
            if matches!(&else_value.kind, ExprKind::Literal(value) if value == "null") {
                self.emit(opcode::GET_VAR, vec![Word::Variable(VariableWord::Null)]);
            } else {
                self.local_initializer(else_value, declaration, statement)?;
            }
            self.result.code.items.push(CodeItem::Label(end_label));
            return Ok(());
        }
        let inferred_new_args: Option<&[Expr]> = match &expr.kind {
            ExprKind::Ident(name) if name == "new" => Some(&[]),
            ExprKind::Call { callee, args } if matches!(&callee.kind, ExprKind::Ident(name) if name == "new") => {
                Some(args)
            }
            _ => None,
        };
        if let Some(args) = inferred_new_args {
            let type_name = declaration
                .strip_prefix("var/")
                .and_then(|raw| raw.rsplit_once('/'))
                .map(|(path, _)| path)
                .filter(|path| !path.is_empty())
                .or_else(|| declaration.trim_end().ends_with("[]").then_some("list"))
                .ok_or_else(|| error(statement, "inferred new requires a typed local"))?;
            let path = runtime_declaration_path(type_name);
            let tag = self
                .class_tag(&path)?
                .ok_or_else(|| error(statement, "unsupported inferred constructor type"))?;
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
            if args
                .iter()
                .any(|arg| matches!(&arg.kind, ExprKind::Binary { op, .. } if op == "="))
            {
                self.named_arguments(args, statement)?;
                self.emit(0xcf, vec![]);
            } else if let [
                Expr {
                    kind:
                        ExprKind::Call {
                            callee,
                            args: list_args,
                        },
                    ..
                },
            ] = args
            {
                if matches!(&callee.kind, ExprKind::Ident(name) if name == "arglist")
                    && list_args.len() == 1
                {
                    self.expression(&list_args[0], statement)?;
                    self.emit(0xcf, vec![]);
                } else {
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                    self.emit(opcode::NEW, vec![Word::Immediate(args.len() as u32)]);
                }
            } else {
                for arg in args {
                    self.expression(arg, statement)?;
                }
                self.emit(opcode::NEW, vec![Word::Immediate(args.len() as u32)]);
            }
            return Ok(());
        }
        self.expression(expr, statement)
    }
}
