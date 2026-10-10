//! Inference lowering over the shared compiler context.
use super::*;
#[path = "input_warnings.rs"]
mod input_warnings;

impl Compiler<'_> {
    pub(super) fn inferred_expression_type(
        &self,
        expr: &Expr,
    ) -> Result<Option<String>, LowerError> {
        dm_ir::receiver_resolution::infer_receiver_type(
            &receiver_resolution::ReceiverContext(self),
            expr,
        )
    }
    pub(super) fn normalize_inferred_type(&self, path: &str) -> Result<String, LowerError> {
        if let Some(lookup) = self.lookup {
            let query = dm_ir::ResolveQuery::RuntimeType(SymbolId::of(path));
            let id = self.semantic(lookup.runtime_type(path))?;
            return self.semantic(lookup.text(query, id));
        }
        if let Some(shared) = &self.bindings.shared {
            if let Some(id) = shared.modified_instances.get(path) {
                if *id == SymbolId::of(path) {
                    return Ok(path.to_owned());
                }
                for candidate in shared
                    .member_types
                    .keys()
                    .chain(shared.parent_types.keys())
                    .chain(shared.known_member_fields.keys())
                {
                    if SymbolId::of(candidate) == *id {
                        return Ok(candidate.clone());
                    }
                }
                return Err(error(
                    path,
                    "modified runtime type spelling is not captured",
                ));
            }
        }
        Ok(path.to_owned())
    }
    pub(super) fn expression_member_global(
        &self,
        object: &Expr,
        name: &str,
    ) -> Result<Option<SymRef>, LowerError> {
        match self.inferred_expression_type(object)? {
            Some(owner) => self.member_global(&owner, name),
            None => Ok(None),
        }
    }
    pub(super) fn expression_member_proc(
        &self,
        object: &Expr,
        name: &str,
    ) -> Result<Option<SymRef>, LowerError> {
        match self.inferred_expression_type(object)? {
            Some(owner) => self.member_proc(&owner, name),
            None => Ok(None),
        }
    }
    pub(super) fn current_member_proc(&self, name: &str) -> Result<Option<SymRef>, LowerError> {
        match self.bindings.current_type_path.as_deref() {
            Some(owner) => self.member_proc(owner, name),
            None => Ok(None),
        }
    }
    pub(super) fn current_has_declared_member_proc(&self, name: &str) -> Result<bool, LowerError> {
        match self.bindings.current_type_path.as_deref() {
            Some(owner) => self.has_declared_member_proc(owner, name),
            None => Ok(false),
        }
    }
    pub(super) fn local_array(
        &mut self,
        dimensions: &[&str],
        statement: &str,
    ) -> Result<(), LowerError> {
        if dimensions.len() > 1 {
            let path = "/list".to_owned();
            if self.seen_classes.insert(SymbolId::of(&path)) {
                self.result.class_paths.push(SymbolId::of(&path));
            }
            self.emit(
                opcode::PUSH_VAL,
                vec![Word::Value(ValueWord::ClassPath {
                    path: SymbolId::of(&path),
                    tag: 40,
                })],
            );
        }
        for size in dimensions {
            self.expression_text(size, statement)?;
        }
        self.emit(
            if dimensions.len() == 1 {
                opcode::EMPTY_LIST
            } else {
                opcode::NEW
            },
            if dimensions.len() == 1 {
                vec![]
            } else {
                vec![Word::Immediate(dimensions.len() as u32)]
            },
        );
        Ok(())
    }

    pub(super) fn named_arguments(
        &mut self,
        args: &[Expr],
        statement: &str,
    ) -> Result<(), LowerError> {
        for (index, arg) in args.iter().enumerate() {
            if let Some(dm_syntax::NamedArgument {
                key: lhs,
                value: rhs,
            }) = dm_syntax::named_argument(arg)
            {
                if let ExprKind::Ident(name) = &lhs.kind {
                    self.intern_string(name);
                    self.emit(
                        opcode::PUSH_VAL,
                        vec![Word::Value(ValueWord::String(SymbolId::of(name)))],
                    );
                } else {
                    self.expression(lhs, statement)?;
                }
                if matches!(&rhs.kind, ExprKind::Literal(value) if value == "null") {
                    self.emit(opcode::GET_VAR, vec![Word::Variable(VariableWord::Null)]);
                } else {
                    self.expression(rhs, statement)?;
                }
                continue;
            }
            self.emit(opcode::PUSH_INT, vec![Word::Immediate(index as u32 + 1)]);
            self.expression(arg, statement)?;
        }
        self.emit(0xc8, vec![Word::Immediate(args.len() as u32)]);
        Ok(())
    }

    pub(super) fn input_call(
        &mut self,
        args: &[Expr],
        types: &[String],
        choices: Option<&Expr>,
        statement: &str,
    ) -> Result<(), LowerError> {
        if args.len() > 4 {
            return Err(error(
                statement,
                "input() accepts at most four prompt arguments",
            ));
        }
        let source_ordinal = self.debug_current;
        let mut mask = 0u32;
        let mut special = 0u32;
        for ty in types {
            mask |= match ty.as_str() {
                "mob" => 1,
                "obj" => 2,
                "text" => 4,
                "num" => 8,
                "file" => 16,
                "turf" => 32,
                "null" => 128,
                "area" => 256,
                "icon" => 512,
                "sound" => 1024,
                "message" => 2048,
                "anything" => 4096,
                "password" => 32768,
                "color" => {
                    special |= 131072;
                    0
                }
                _ => return Err(error(statement, "unsupported input type")),
            };
        }
        if special != 0 {
            self.emit(
                opcode::PUSH_VAL,
                vec![Word::Value(ValueWord::Number(
                    ((special | mask) as f32).to_bits(),
                ))],
            );
        }
        let (radius, selection, evaluate_choices) = if special == 0 {
            self.input_selection(choices, statement)?
        } else {
            (0, if choices.is_some() { 64 } else { 0 }, choices.is_some())
        };
        if evaluate_choices {
            self.expression(choices.expect("selection expression exists"), statement)?;
        }
        for arg in args {
            if matches!(&arg.kind, ExprKind::Binary { op, .. } if op == "=") {
                return Err(error(statement, "named input arguments are not lowered"));
            }
            self.expression(arg, statement)?;
        }
        for _ in args.len()..4 {
            self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
        }
        self.emit(
            if special != 0 { 0xc6 } else { 0xc1 },
            vec![
                Word::Immediate(if special != 0 { 0 } else { mask }),
                Word::Immediate(radius),
                Word::Immediate(selection),
            ],
        );
        self.emit(0xba, vec![]);
        self.input_filter_warning(types, choices.is_some(), mask, source_ordinal);
        Ok(())
    }

    // Native 516.1687 distinguishes reserved selection forms from evaluated lists.
    // Radius 125 means the default view; 127 accompanies world/usr selection.
    fn input_selection(
        &mut self,
        choices: Option<&Expr>,
        statement: &str,
    ) -> Result<(u32, u32, bool), LowerError> {
        let Some(choices) = choices else {
            return Ok((0, 0, false));
        };
        if let ExprKind::Ident(name) = &choices.kind {
            if matches!(name.as_str(), "world" | "usr") {
                match self.variable_for_node(choices, name, statement)? {
                    VariableWord::World => return Ok((127, 16, false)),
                    VariableWord::Usr => return Ok((127, 8, false)),
                    _ => {} // A current lexical binding remains an evaluated choice.
                }
            }
        }
        if let ExprKind::Call { callee, args } = &choices.kind {
            if let ExprKind::Ident(name) = &callee.kind {
                // These are reserved builtin names, not authored callable selectors.
                if matches!(name.as_str(), "view" | "oview") && args.len() == 2 {
                    for (radius, center) in [(&args[0], &args[1]), (&args[1], &args[0])] {
                        let (ExprKind::Literal(text), ExprKind::Ident(center_name)) =
                            (&radius.kind, &center.kind)
                        else {
                            continue;
                        };
                        let Some(radius) = text.parse::<u32>().ok().filter(|value| *value <= 127)
                        else {
                            continue;
                        };
                        if center_name == "usr"
                            && matches!(
                                self.variable_for_node(center, center_name, statement)?,
                                VariableWord::Usr
                            )
                        {
                            self.record_selection(
                                callee,
                                name,
                                dm_ir::SelectedMeaning::IntrinsicCall(SymbolId::of(name)),
                            );
                            return Ok((radius, if name == "view" { 1 } else { 2 }, false));
                        }
                        // Literal radius metadata survives an evaluated dynamic center.
                        // The entire original call still runs, in its authored argument order.
                        return Ok((radius, 64, true));
                    }
                }
                if matches!(name.as_str(), "view" | "oview") && args.len() <= 1 {
                    let radius = if args.is_empty() {
                        Some(125)
                    } else {
                        match &args[0].kind {
                            ExprKind::Literal(text) => {
                                text.parse::<u32>().ok().filter(|value| *value <= 127)
                            }
                            _ => None,
                        }
                    };
                    if let Some(radius) = radius {
                        self.record_selection(
                            callee,
                            name,
                            dm_ir::SelectedMeaning::IntrinsicCall(SymbolId::of(name)),
                        );
                        return Ok((radius, if name == "view" { 1 } else { 2 }, false));
                    }
                    // A dynamic view is evaluated normally, retaining native default-radius metadata.
                    if matches!(&args[0].kind, ExprKind::Ident(_)) {
                        return Ok((125, 64, true));
                    }
                }
            }
        }
        Ok((0, 64, true))
    }

    pub(super) fn input_form<'b>(&self, expr: &'b Expr) -> Option<(&'b [Expr], &'b [String])> {
        match &expr.kind {
            ExprKind::Call { callee, args } if matches!(&callee.kind, ExprKind::Ident(name) if name == "input") => {
                Some((args, &[]))
            }
            ExprKind::TypeFilter { value, types } => {
                let ExprKind::Call { callee, args } = &value.kind else {
                    return None;
                };
                matches!(&callee.kind, ExprKind::Ident(name) if name == "input")
                    .then_some((args, types))
            }
            _ => None,
        }
    }

    pub(super) fn condition(&mut self, expr: &Expr, statement: &str) -> Result<(), LowerError> {
        if let ExprKind::Binary { op, lhs, rhs } = &expr.kind {
            if op == "==" {
                self.expression(lhs, statement)?;
                self.expression(rhs, statement)?;
                self.emit(opcode::TEQ, vec![]);
                self.emit(opcode::POP, vec![]);
                return Ok(());
            }
        }
        self.expression(expr, statement)?;
        self.emit(opcode::TEST, vec![]);
        Ok(())
    }

    pub(super) fn defer_safe_postfix_labels(&mut self, expr: &Expr) -> Vec<CodeItem> {
        fn is_safe_chain(expr: &Expr) -> bool {
            match &expr.kind {
                ExprKind::SafeMember { .. } | ExprKind::SafeIndex { .. } => true,
                ExprKind::Member { object, .. }
                | ExprKind::StaticMember { object, .. }
                | ExprKind::Index { object, .. } => is_safe_chain(object),
                ExprKind::Call { callee, .. } => is_safe_chain(callee),
                _ => false,
            }
        }
        let mut labels = Vec::new();
        if is_safe_chain(expr) {
            while matches!(self.result.code.items.last(), Some(CodeItem::Label(_))) {
                labels.push(self.result.code.items.pop().unwrap());
            }
            labels.reverse();
        }
        labels
    }
}
