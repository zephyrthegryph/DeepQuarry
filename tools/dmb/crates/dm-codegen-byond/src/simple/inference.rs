//! Inference lowering over the shared compiler context.
use super::*;

impl Compiler<'_> {
    pub(super) fn inferred_expression_type(
        &self,
        expr: &Expr,
    ) -> Result<Option<String>, LowerError> {
        let inferred = match &expr.kind {
            ExprKind::TypePath(path) => Some(path.clone()),
            ExprKind::Ident(name) => {
                if name == "src" {
                    return match self.bindings.current_type_path.as_deref() {
                        Some(path) => self.normalize_inferred_type(path).map(Some),
                        None => Ok(None),
                    };
                }
                if name == "usr" {
                    return self.normalize_inferred_type("/mob").map(Some);
                }
                // Match variable() binding precedence. A nearer lexical binding
                // with no declared type is proven untyped, not an outer lookup.
                if self.local_slots.contains_key(name) {
                    return self
                        .local_types
                        .get(name)
                        .map(|path| self.normalize_inferred_type(&runtime_declaration_path(path)))
                        .transpose();
                }
                if self
                    .bindings
                    .parameters
                    .iter()
                    .any(|parameter| parameter == name)
                {
                    return self
                        .bindings
                        .parameter_types
                        .get(name)
                        .map(|path| self.normalize_inferred_type(&runtime_declaration_path(path)))
                        .transpose();
                }
                {
                    if let Some(lookup) = self.lookup {
                        if let Some(declaration) = self.semantic(
                            lookup.procedure_static(self.bindings.procedure_identity, name),
                        )? {
                            return declaration
                                .declared_type
                                .map(|id| {
                                    self.semantic(lookup.text(
                                        dm_ir::ResolveQuery::ProcedureStatic {
                                            procedure: declaration.identity.procedure,
                                            name: declaration.identity.name,
                                        },
                                        id,
                                    ))
                                })
                                .transpose();
                        }
                    }
                    if name == "world" {
                        return self.normalize_inferred_type("/world").map(Some);
                    }
                    if name == "args" {
                        return self.normalize_inferred_type("/list").map(Some);
                    }
                    if matches!(name.as_str(), "caller" | "callee") {
                        return self.normalize_inferred_type("/callee").map(Some);
                    }
                    if name == "." {
                        // The return-value register has no declared receiver
                        // type. It is not an outer member/global identifier.
                        return Ok(None);
                    }
                    if let (Some(lookup), Some(owner)) =
                        (self.lookup, self.bindings.current_type_path.as_deref())
                    {
                        if self.semantic(lookup.presence(dm_ir::ResolveQuery::HasMemberVar {
                            owner: dm_ir::SymbolId::of(owner),
                            name: dm_ir::SymbolId::of(name),
                        }))? {
                            // Proven untyped is an answer, not permission to look
                            // through the nearer field into the global namespace.
                            return self
                                .field_type(name)?
                                .map(|path| self.normalize_inferred_type(&path))
                                .transpose();
                        }
                        return self
                            .global_type(name)?
                            .map(|path| self.normalize_inferred_type(&path))
                            .transpose();
                    }
                    match self.field_type(name)? {
                        Some(path) => Some(path),
                        None => self.global_type(name)?,
                    }
                }
            }
            ExprKind::Group(inner) => self.inferred_expression_type(inner)?,
            ExprKind::Member {
                object,
                selector,
                via_colon,
            } => {
                // A colon selector intentionally carries no static receiver
                // field contract, even when its receiver has an authored type.
                if *via_colon {
                    return Ok(None);
                }
                if matches!(&object.kind, ExprKind::Ident(name) if name == "global") {
                    return self
                        .global_type(selector)?
                        .map(|path| self.normalize_inferred_type(&path))
                        .transpose();
                }
                if matches!(&object.kind, ExprKind::Ident(name) if name == "src") {
                    return self
                        .field_type(selector)?
                        .map(|path| self.normalize_inferred_type(&path))
                        .transpose();
                }
                match self.inferred_expression_type(object)? {
                    Some(owner) => self.member_type(&owner, selector)?,
                    None => None,
                }
            }
            ExprKind::SafeMember { object, selector } => {
                match self.inferred_expression_type(object)? {
                    Some(owner) => self.member_type(&owner, selector)?,
                    None => None,
                }
            }
            ExprKind::Call { callee, .. } if self.lookup.is_some() => {
                let lookup = self.lookup.unwrap();
                match &callee.kind {
                    ExprKind::Ident(name) => {
                        if crate::builtin_catalog::lookup(name).is_some() {
                            return Ok(None);
                        }
                        if let Some(owner) = self.bindings.current_type_path.as_deref() {
                            if self.has_declared_member_proc(owner, name)? {
                                return self.semantic(lookup.procedure_return_type(
                                    dm_ir::ResolveQuery::Proc {
                                        owner: dm_ir::SymbolId::of(owner),
                                        name: dm_ir::SymbolId::of(name),
                                        verb: false,
                                    },
                                ));
                            }
                        }
                        self.semantic(lookup.procedure_return_type(
                            dm_ir::ResolveQuery::GlobalProc(dm_ir::SymbolId::of(name)),
                        ))?
                    }
                    ExprKind::Member {
                        object,
                        selector,
                        via_colon: false,
                    }
                    | ExprKind::SafeMember { object, selector } => {
                        match self.inferred_expression_type(object)? {
                            Some(owner) => self.semantic(lookup.procedure_return_type(
                                dm_ir::ResolveQuery::Proc {
                                    owner: dm_ir::SymbolId::of(&owner),
                                    name: dm_ir::SymbolId::of(selector),
                                    verb: false,
                                },
                            ))?,
                            None => None,
                        }
                    }
                    _ => None,
                }
            }
            _ => None,
        };
        let Some(path) = inferred else {
            return Ok(None);
        };
        self.normalize_inferred_type(&path).map(Some)
    }
    pub(super) fn normalize_inferred_type(&self, path: &str) -> Result<String, LowerError> {
        if let Some(lookup) = self.lookup {
            return self.semantic(lookup.runtime_type(path));
        }
        Ok(self
            .bindings
            .shared
            .as_ref()
            .and_then(|shared| shared.modified_instances.get(path))
            .cloned()
            .unwrap_or_else(|| path.to_owned()))
    }
    pub(super) fn expression_member_global(
        &self,
        object: &Expr,
        name: &str,
    ) -> Result<Option<String>, LowerError> {
        match self.inferred_expression_type(object)? {
            Some(owner) => self.member_global(&owner, name),
            None => Ok(None),
        }
    }
    pub(super) fn expression_member_proc(
        &self,
        object: &Expr,
        name: &str,
    ) -> Result<Option<String>, LowerError> {
        match self.inferred_expression_type(object)? {
            Some(owner) => self.member_proc(&owner, name),
            None => Ok(None),
        }
    }
    pub(super) fn current_member_proc(&self, name: &str) -> Result<Option<String>, LowerError> {
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
            if self.seen_classes.insert(path.clone()) {
                self.result.class_paths.push(path.clone());
            }
            self.emit(
                opcode::PUSH_VAL,
                vec![Word::Value(ValueWord::ClassPath { path, tag: 40 })],
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
            if let ExprKind::Binary { op, lhs, rhs } = &arg.kind {
                if op == "=" {
                    if let ExprKind::Ident(name) = &lhs.kind {
                        self.intern_string(name);
                        self.emit(
                            opcode::PUSH_VAL,
                            vec![Word::Value(ValueWord::String(name.clone()))],
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
        if let Some(choices) = choices {
            self.expression(choices, statement)?;
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
                Word::Immediate(0),
                Word::Immediate(if choices.is_some() { 64 } else { 0 }),
            ],
        );
        self.emit(0xba, vec![]);
        Ok(())
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
