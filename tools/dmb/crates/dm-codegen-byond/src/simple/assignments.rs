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
        self.assign_expr_ordered(target, op, value, statement, false)
    }

    /// `null_first` pushes the value before a safe receiver's guard, which is how DreamMaker lowers the
    /// clearing store of `del(a?.b)`. An authored `a?.b = const` pushes it after the guard instead, so the
    /// short-circuit path leaves nothing on the stack.
    pub(super) fn assign_expr_ordered(
        &mut self,
        target: &Expr,
        op: &str,
        value: &Expr,
        statement: &str,
        null_first: bool,
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
        if !null_first {
            if let Some(chain) = safe_member_chain(target) {
                return self.assign_through_safe_chain(target, &chain, op, value, statement);
            }
        }
        if let ExprKind::SafeMember {
            object,
            selector,
            via_colon,
        } = &target.kind
        {
            self.source_feature_reference(target, true, statement)?;
            if null_first {
                self.expression(value, statement)?;
            }
            self.expression(object, statement)?;
            let end = self.label();
            self.emit(318, vec![Word::Branch(end)]);
            if !null_first {
                // The value follows the guard, as in DreamMaker: a null receiver skips the write
                // with nothing pushed, so the short-circuit path leaves the stack balanced.
                self.emit(opcode::PUSH_CACHE, vec![]);
                self.expression(value, statement)?;
                self.emit(opcode::POP_CACHE, vec![]);
            }
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
            if null_first {
                self.expression(value, statement)?;
            }
            self.expression(object, statement)?;
            let end = self.label();
            self.emit(318, vec![Word::Branch(end)]);
            if !null_first {
                // The value follows the guard, as in DreamMaker: a null receiver skips the write
                // with nothing pushed, so the short-circuit path leaves the stack balanced.
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
                // `a?.f()[i] = v`: DreamMaker tests the receiver first, so `v` is not evaluated for a null receiver.
                if let ExprKind::Call { callee, args } =
                    &super::expression::peel_groups(object).kind
                {
                    if let (
                        true,
                        ExprKind::SafeMember {
                            object: receiver,
                            selector,
                            via_colon: false,
                        },
                    ) = (args.is_empty(), &callee.kind)
                    {
                        let proc_selector =
                            self.safe_member_call_selector(receiver, selector, statement)?;
                        self.record_call_selection(callee, selector, &proc_selector, true);
                        self.expression(receiver, statement)?;
                        let end = self.label();
                        self.emit(318, vec![Word::Branch(end)]);
                        self.emit(opcode::PUSH_CACHE, vec![]);
                        self.expression(value, statement)?;
                        self.emit(
                            opcode::CALL,
                            vec![Word::Variable(proc_selector), Word::Immediate(0)],
                        );
                        self.expression(index, statement)?;
                        self.emit(opcode::LIST_SET, vec![]);
                        self.emit(opcode::POP_CACHE, vec![]);
                        self.result.code.items.push(CodeItem::Label(end));
                        return Ok(());
                    }
                }
                self.expression(value, statement)?;
                self.expression(object, statement)?;
                self.expression(index, statement)?;
                self.emit(opcode::LIST_SET, vec![]);
                return Ok(());
            }
            if let ExprKind::Member {
                object,
                selector,
                via_colon,
            } = &target.kind
            {
                self.validate_member_var(target, statement)?;
                if self.variable_expr(target, statement).is_err() {
                    self.expression(value, statement)?;
                    self.expression(object, statement)?;
                    self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                    let variable =
                        match self.fallback_member_global(object, selector, *via_colon)? {
                            Some(symbol) => VariableWord::Global(symbol),
                            None => {
                                self.intern_string(selector);
                                VariableWord::Field(SymbolId::of(selector))
                            }
                        };
                    self.emit(opcode::SET_VAR, vec![Word::Variable(variable)]);
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
        self.validate_member_var(target, statement)?;
        let variable = match self.variable_expr(target, statement) {
            Ok(variable) => variable,
            Err(_) => {
                let ExprKind::Member {
                    object,
                    selector,
                    via_colon,
                } = &target.kind
                else {
                    return Err(error(statement, "unsupported assignment target"));
                };
                self.expression(object, statement)?;
                self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                match self.fallback_member_global(object, selector, *via_colon)? {
                    Some(symbol) => VariableWord::Global(symbol),
                    None => {
                        self.intern_string(selector);
                        VariableWord::Field(SymbolId::of(selector))
                    }
                }
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
            return Err(syntax_failure(statement, &parsed.diagnostics));
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
    /// `a?.b.c = v` and `f()?.b?.c = v`: DreamMaker tests each `?.` receiver in turn, saving the cache register at every
    /// guard, evaluates `v` once the last receiver passed and stores through the members that follow it. A receiver that
    /// is null skips the store and restores the registers saved so far.
    fn assign_through_safe_chain(
        &mut self,
        target: &Expr,
        chain: &SafeChain,
        op: &str,
        value: &Expr,
        statement: &str,
    ) -> Result<(), LowerError> {
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
        self.source_feature_reference(target, true, statement)?;
        let mut ends = Vec::new();
        for (index, receiver) in chain.receivers.iter().enumerate() {
            match receiver {
                GuardReceiver::Expression(receiver) => self.expression(receiver, statement)?,
                // A later receiver is read from the cache register the previous guard set.
                GuardReceiver::FromCache(path) => {
                    let variable = self.field_chain(path);
                    self.emit(opcode::GET_VAR, vec![Word::Variable(variable)]);
                }
            }
            debug_assert!(index == 0 || matches!(receiver, GuardReceiver::FromCache(_)));
            let end = self.label();
            self.emit(318, vec![Word::Branch(end)]);
            self.emit(opcode::PUSH_CACHE, vec![]);
            ends.push(end);
        }
        self.expression(value, statement)?;
        self.emit(opcode::POP_CACHE, vec![]);
        let variable = self.field_chain(&chain.path);
        self.emit(assignment_opcode, vec![Word::Variable(variable)]);
        // The null path of guard i has i - 1 saved registers to restore.
        for end in ends.iter().skip(1).rev() {
            self.result.code.items.push(CodeItem::Label(*end));
            self.emit(opcode::POP_CACHE, vec![]);
        }
        self.result.code.items.push(CodeItem::Label(ends[0]));
        Ok(())
    }
    /// The members `path` read from the cache register: one field, or the fields nested as DreamMaker encodes a
    /// multi-hop operand.
    fn field_chain(&mut self, path: &[String]) -> VariableWord {
        let mut fields = path
            .iter()
            .map(|selector| {
                self.intern_string(selector);
                VariableWord::Field(SymbolId::of(selector.as_str()))
            })
            .collect::<Vec<_>>();
        let mut variable = fields
            .pop()
            .expect("a member chain has at least one member");
        while let Some(owner) = fields.pop() {
            variable = VariableWord::SetCache(Box::new(owner), Box::new(variable));
        }
        variable
    }
    pub(super) fn variable_expr(
        &mut self,
        expr: &Expr,
        statement: &str,
    ) -> Result<VariableWord, LowerError> {
        self.validate_member_var(expr, statement)?;
        let word = self.variable_expr_inner(expr, statement)?;
        self.source_feature_reference(
            expr,
            self.discarded_call_root != Some(expr as *const Expr),
            statement,
        )?;
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
                // A shared variable needs no receiver, but a receiver that runs code (a call) is still evaluated, as
                // DreamMaker does (`Call ...; SetVar cache; GetVar global:x`): that path leaves here as an error.
                if let Some(owner) = if *via_colon || !is_reference_chain(object) {
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
            ExprKind::Call { .. } => Err(source_error(statement, ": bad assignment")),
            ExprKind::Binary { op, .. } if op == "/" && path_like_target(statement) => {
                // `vra/a = 1`: a misspelled `var/` reads as division by DM too.
                Err(source_error(
                    statement,
                    &format!("{}: undefined var", assignment_target_text(statement)),
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
        self.validate_member_var(target, statement)?;
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
        self.validate_member_var(target, statement)?;
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
            ExprKind::Unary { op, value } if op == "new" => match &value.kind {
                ExprKind::Ident(name) => name == "__IMPLIED_TYPE__",
                ExprKind::Call { callee, .. } => {
                    matches!(&callee.kind, ExprKind::Ident(name) if name == "__IMPLIED_TYPE__")
                }
                _ => false,
            },
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
        if let ExprKind::Binary { op, .. } = &expr.kind {
            if op == "||" || op == "&&" {
                let operands = self.short_circuit_operands(expr, op, statement)?;
                let Some((first, tails)) = operands.split_first() else {
                    return Err(error(statement, "empty short-circuit chain"));
                };
                self.local_initializer(first, declaration, statement)?;
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
                    self.local_initializer(next, declaration, statement)?;
                }
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
            // A constant condition keeps one branch (DreamMaker 516.1687); the other is still checked.
            if let Some(value) = super::expression::constant_truth(condition) {
                let (kept, dead) = if value {
                    (then_value, else_value)
                } else {
                    (else_value, then_value)
                };
                self.lower_dead(|compiler| {
                    compiler.local_initializer(dead, declaration, statement)
                })?;
                return self.local_initializer(kept, declaration, statement);
            }
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
        // Explicit implied-type construction uses the same target-type producer
        // as bare new. Lexical locals, parameters, fields and globals still win.
        let implied_args = match &expr.kind {
            ExprKind::Unary { op, value } if op == "new" => match &value.kind {
                ExprKind::Ident(name) if name == "__IMPLIED_TYPE__" => Some(&[][..]),
                ExprKind::Call { callee, args } if matches!(&callee.kind, ExprKind::Ident(name) if name == "__IMPLIED_TYPE__") => {
                    Some(args.as_slice())
                }
                _ => None,
            },
            _ => None,
        };
        let implied_args = if implied_args.is_some()
            && !self.local_slots.contains_key("__IMPLIED_TYPE__")
            && !self
                .bindings
                .parameters
                .iter()
                .any(|name| name == "__IMPLIED_TYPE__")
            && !self.has_field("__IMPLIED_TYPE__")?
            && !self.has_visible_global("__IMPLIED_TYPE__")?
        {
            implied_args
        } else {
            None
        };
        let inferred_new_args: Option<&[Expr]> = match &expr.kind {
            ExprKind::Ident(name) if name == "new" => Some(&[]),
            ExprKind::Call { callee, args } if matches!(&callee.kind, ExprKind::Ident(name) if name == "new") => {
                Some(args)
            }
            _ => None,
        };
        if let Some(args) = inferred_new_args.or(implied_args) {
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
            } else if let [Expr {
                kind:
                    ExprKind::Call {
                        callee,
                        args: list_args,
                    },
                ..
            }] = args
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

/// Assignment target as authored: the statement text before its first `=`.
fn assignment_target_text(statement: &str) -> &str {
    statement
        .split_once('=')
        .map_or(statement, |(target, _)| target)
        .trim()
}

/// `name/name...` with no spaces: a misspelled `var/` declaration.
fn path_like_target(statement: &str) -> bool {
    let target = assignment_target_text(statement);
    target.contains('/')
        && target.split('/').all(|part| {
            !part.is_empty() && part.chars().all(|ch| ch.is_alphanumeric() || ch == '_')
        })
}

/// A receiver that only names things (identifiers and member reads, possibly parenthesised): evaluating it has no effect,
/// so a shared (`global`) variable behind it can be read or written without evaluating it.
pub(super) fn is_reference_chain(expr: &Expr) -> bool {
    match &expr.kind {
        ExprKind::Ident(_) | ExprKind::TypePath(_) | ExprKind::Literal(_) => true,
        ExprKind::Group(inner) => is_reference_chain(inner),
        ExprKind::Member { object, .. } => is_reference_chain(object),
        _ => false,
    }
}

/// The `?.` receivers of an assignment target and the members stored through after the last of them.
struct SafeChain {
    /// Receivers to test in order.
    receivers: Vec<GuardReceiver>,
    /// The members from the last tested receiver to the stored member, in order.
    path: Vec<String>,
}

/// What a `?.` is applied to.
enum GuardReceiver {
    /// The first receiver: the expression itself, with the members before it read as plain `.`.
    Expression(Expr),
    /// Every later receiver: the members after the previous receiver, read from the cache register it set.
    FromCache(Vec<String>),
}

/// A member chain with its `?.` read as `.`.
fn without_safe_access(expr: &Expr) -> Expr {
    match &expr.kind {
        ExprKind::SafeMember {
            object,
            selector,
            via_colon,
        }
        | ExprKind::Member {
            object,
            selector,
            via_colon,
        } => Expr {
            span: expr.span,
            kind: ExprKind::Member {
                object: Box::new(without_safe_access(object)),
                selector: selector.clone(),
                via_colon: *via_colon,
            },
        },
        ExprKind::Group(inner) => without_safe_access(inner),
        _ => expr.clone(),
    }
}

/// Splits a member chain with a `?.` before its stored member into guards (`None` when it has none).
fn safe_member_chain(target: &Expr) -> Option<SafeChain> {
    // The chain's nodes from the stored member in.
    let mut nodes: Vec<&Expr> = Vec::new();
    let mut at = super::expression::peel_groups(target);
    while let ExprKind::Member { object, .. } | ExprKind::SafeMember { object, .. } = &at.kind {
        nodes.push(at);
        at = super::expression::peel_groups(object);
    }
    nodes.reverse();
    let selector_of = |node: &Expr| match &node.kind {
        ExprKind::Member { selector, .. } | ExprKind::SafeMember { selector, .. } => {
            selector.clone()
        }
        _ => unreachable!("chain nodes are members"),
    };
    let safe = |node: &Expr| matches!(node.kind, ExprKind::SafeMember { .. });
    let inner_safe = nodes
        .iter()
        .take(nodes.len().saturating_sub(1))
        .any(|node| safe(node));
    let colon = nodes.iter().any(|node| {
        matches!(
            node.kind,
            ExprKind::Member {
                via_colon: true,
                ..
            } | ExprKind::SafeMember {
                via_colon: true,
                ..
            }
        )
    });
    if !inner_safe || colon {
        return None;
    }
    let mut receivers = Vec::new();
    let mut last_guard = None;
    for (index, node) in nodes.iter().enumerate() {
        if safe(node) {
            let (ExprKind::SafeMember { object, .. } | ExprKind::Member { object, .. }) =
                &node.kind
            else {
                unreachable!("chain nodes are members")
            };
            receivers.push(match last_guard {
                None => GuardReceiver::Expression(without_safe_access(object)),
                Some(previous) => GuardReceiver::FromCache(
                    nodes[previous..index]
                        .iter()
                        .map(|node| selector_of(node))
                        .collect(),
                ),
            });
            last_guard = Some(index);
        }
    }
    let last_guard = last_guard.expect("a chain with an inner `?.` has a guard");
    Some(SafeChain {
        receivers,
        path: nodes[last_guard..]
            .iter()
            .map(|node| selector_of(node))
            .collect(),
    })
}
