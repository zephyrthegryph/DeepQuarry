//! Calls intrinsics lowering over the shared compiler context.
use super::*;

impl Compiler<'_> {
    pub(super) fn intrinsic_call(
        &mut self,
        name: &str,
        args: &[Expr],
        statement: &str,
        named_arguments: bool,
        arglist_argument: Option<&Expr>,
    ) -> Result<bool, LowerError> {
        if matches!(name, "cmptext" | "cmptextEx") {
            if args.len() < 2 || named_arguments || arglist_argument.is_some() {
                return Err(error(
                    statement,
                    "text comparison requires at least two positional arguments",
                ));
            }
            self.expression(&args[0], statement)?;
            self.expression(&args[1], statement)?;
            let comparison = if name == "cmptext" { 0x71 } else { 0x37 };
            self.emit(comparison, vec![]);
            let end = self.label();
            for argument in &args[2..] {
                self.emit(opcode::JZ, vec![Word::Branch(end.clone())]);
                self.expression(argument, statement)?;
                self.emit(comparison, vec![]);
            }
            self.result.code.items.push(CodeItem::Label(end));
            self.emit(opcode::POP, vec![]);
            self.emit(0x36, vec![]);
            return Ok(true);
        }
        if name == "vector" {
            if !(1..=3).contains(&args.len()) || named_arguments || arglist_argument.is_some() {
                return Err(error(
                    statement,
                    "vector expects one to three positional arguments",
                ));
            }
            for argument in args {
                self.expression(argument, statement)?;
            }
            self.emit(0x180, vec![Word::Immediate(args.len() as u32)]);
            return Ok(true);
        }
        if name == "gradient" {
            if args.len() < 2 && arglist_argument.is_none() {
                return Err(error(statement, "gradient expects at least two arguments"));
            }
            if named_arguments {
                self.named_arguments(args, statement)?;
            } else if let Some(list) = arglist_argument {
                self.expression(list, statement)?;
            } else {
                for arg in args {
                    self.expression(arg, statement)?;
                }
                self.emit(opcode::NEW_LIST, vec![Word::Immediate(args.len() as u32)]);
            }
            self.emit(0x164, vec![]);
            return Ok(true);
        }
        if name == "statpanel" && args.len() == 1 && !named_arguments && arglist_argument.is_none()
        {
            self.expression(&args[0], statement)?;
            self.emit(0xa2, vec![]);
            self.emit(0x36, vec![]);
            return Ok(true);
        }
        if name == "new" {
            return Err(error(
                statement,
                "inferred new requires a typed declaration",
            ));
        }
        if name == "text" {
            let Some(Expr {
                kind: ExprKind::Literal(template),
                ..
            }) = args.first()
            else {
                return Err(error(statement, "text() requires a literal template"));
            };
            if !template.starts_with('"') || !template.ends_with('"') {
                return Err(error(statement, "text() requires a quoted template"));
            }
            let (template, expressions) = parse_text_template(&template[1..template.len() - 1])
                .map_err(|reason| error(statement, &reason))?;
            let slots = expressions
                .iter()
                .filter(|expression| expression.is_none())
                .count();
            if slots != args.len() - 1 {
                return Err(error(
                    statement,
                    "text() placeholder count differs from arguments",
                ));
            }
            let mut supplied = args[1..].iter();
            for expression in &expressions {
                self.expression(
                    expression
                        .as_ref()
                        .unwrap_or_else(|| supplied.next().unwrap()),
                    statement,
                )?;
            }
            let key = self.intern_format_template(template);
            self.emit(
                2,
                vec![
                    Word::Reference(crate::Symbol::new(crate::Table::String, key)),
                    Word::Immediate(expressions.len() as u32),
                ],
            );
            return Ok(true);
        }
        if name == "alist" {
            for arg in args {
                if let ExprKind::Binary { op, lhs, rhs } = &arg.kind {
                    if op == "=" {
                        self.expression(lhs, statement)?;
                        self.expression(rhs, statement)?;
                        continue;
                    }
                }
                self.expression(arg, statement)?;
                self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
            }
            self.emit(0x17c, vec![Word::Immediate(args.len() as u32)]);
            return Ok(true);
        }
        if name == "generator" {
            if args.is_empty() {
                return Err(error(statement, "generator() requires an argument"));
            }
            self.intern_string("/generator");
            self.emit(
                opcode::PUSH_VAL,
                vec![Word::Value(ValueWord::String("/generator".into()))],
            );
            if named_arguments {
                self.named_arguments(args, statement)?;
                self.emit(0xcf, vec![]);
            } else if let Some(list) = arglist_argument {
                self.expression(list, statement)?;
                self.emit(0xcf, vec![]);
            } else {
                for arg in args {
                    self.expression(arg, statement)?;
                }
                self.emit(opcode::NEW, vec![Word::Immediate(args.len() as u32)]);
            }
            return Ok(true);
        }
        if name == "filter" {
            if let Some(list) = arglist_argument {
                self.expression(list, statement)?;
            } else {
                self.named_arguments(args, statement)?;
            }
            self.emit(0x13b, vec![]);
            return Ok(true);
        }
        if name == "image" {
            if args.is_empty() {
                return Err(error(statement, "image() requires at least one argument"));
            }
            if named_arguments {
                self.named_arguments(args, statement)?;
                self.emit(0xd3, vec![]);
            } else {
                for arg in args {
                    self.expression(arg, statement)?;
                }
                self.emit(0xd4, vec![Word::Immediate(args.len() as u32)]);
            }
            return Ok(true);
        }
        if name == "orange" {
            if args.len() > 2 {
                return Err(error(statement, "orange() accepts at most two arguments"));
            }
            for arg in args {
                self.expression(arg, statement)?;
            }
            for _ in args.len()..2 {
                self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
            }
            self.emit(0xad, vec![Word::Immediate(0xae)]);
            return Ok(true);
        }
        if name == "animate" {
            if named_arguments {
                self.named_arguments(args, statement)?;
                self.emit(0x128, vec![]);
            } else if let Some(target) = args.first() {
                self.expression(target, statement)?;
                self.emit(0x129, vec![]);
            } else {
                return Err(error(statement, "animate() requires a target"));
            }
            return Ok(true);
        }
        if name == "pick" {
            if let Some(list) = arglist_argument {
                self.expression(list, statement)?;
                self.emit(0xd2, vec![]);
                return Ok(true);
            }
            if let [arg] = args {
                if !matches!(&arg.kind, ExprKind::Binary { op, .. } if op == ";") {
                    self.expression(arg, statement)?;
                    self.emit(0xd2, vec![]);
                    return Ok(true);
                }
            }
            if args.is_empty() {
                return Err(error(statement, "pick() requires at least one choice"));
            }
            let mut choices = Vec::with_capacity(args.len());
            let mut total = 0.0_f64;
            let mut dynamic = false;
            for arg in args {
                let (weight_expr, value) = match &arg.kind {
                    ExprKind::Binary { op, lhs, rhs } if op == ";" => {
                        (Some(lhs.as_ref()), rhs.as_ref())
                    }
                    _ => (None, arg),
                };
                let weight_expr = weight_expr.map(|weight| {
                    if let ExprKind::Call { callee, args } = &weight.kind {
                        if matches!(&callee.kind, ExprKind::Ident(name) if name == "prob")
                            && args.len() == 1
                        {
                            return &args[0];
                        }
                    }
                    weight
                });
                let weight = weight_expr.and_then(fold_number).map(f64::from);
                dynamic |= weight_expr.is_some() && weight.is_none();
                let weight = weight.unwrap_or(100.0);
                if !weight.is_finite() || weight < 0.0 {
                    return Err(error(
                        statement,
                        "pick weight must be finite and nonnegative",
                    ));
                }
                total += weight;
                choices.push((weight_expr, weight, value, self.label()));
            }
            if !dynamic && total <= 0.0 {
                return Err(error(statement, "pick weights sum to zero"));
            }
            let mut words = vec![Word::Immediate(if dynamic {
                choices.len() as u32
            } else {
                (choices.len() - 1) as u32
            })];
            if dynamic {
                for (weight_expr, _, _, _) in &choices {
                    if let Some(weight_expr) = weight_expr {
                        self.expression(weight_expr, statement)?;
                    } else {
                        self.emit(opcode::PUSH_INT, vec![Word::Immediate(100)]);
                    }
                }
                for (_, _, _, label) in &choices {
                    words.push(Word::Branch(label.clone()));
                }
                self.emit(0xb1, words);
            } else {
                let mut cumulative = 0.0;
                for (_, weight, _, label) in choices.iter().take(choices.len() - 1) {
                    cumulative += weight;
                    words.push(Word::Immediate(
                        ((cumulative / total) * 65535.0_f64).floor() as u32,
                    ));
                    words.push(Word::Branch(label.clone()));
                }
                words.push(Word::Branch(choices.last().unwrap().3.clone()));
                self.emit(0x79, words);
            }
            let end = self.label();
            for (index, (_, _, value, label)) in choices.iter().enumerate() {
                self.result.code.items.push(CodeItem::Label(label.clone()));
                self.expression(value, statement)?;
                if index + 1 != choices.len() {
                    self.emit(opcode::JMP, vec![Word::Branch(end.clone())]);
                }
            }
            self.result.code.items.push(CodeItem::Label(end));
            return Ok(true);
        }
        if name == "initial" {
            let [target] = args else {
                return Err(error(
                    statement,
                    "initial() requires one variable reference",
                ));
            };
            let direct = match &target.kind {
                ExprKind::Ident(name) => self.variable(name, statement).ok().filter(|variable| {
                    matches!(
                        variable,
                        VariableWord::Arg(_) | VariableWord::Local(_) | VariableWord::Global(_)
                    )
                }),
                ExprKind::Member { object, .. } if matches!(&object.kind, ExprKind::Ident(name) if name == "global") => {
                    Some(self.variable_expr(target, statement)?)
                }
                _ => None,
            };
            if let Some(variable) = direct {
                self.emit(
                    opcode::GET_VAR,
                    vec![Word::Variable(VariableWord::Initial(Box::new(variable)))],
                );
                return Ok(true);
            }
            if matches!(&target.kind, ExprKind::Index { .. }) {
                let variable = self.assignment_variable(target, statement)?;
                self.emit(
                    opcode::GET_VAR,
                    vec![Word::Variable(VariableWord::Initial(Box::new(variable)))],
                );
                return Ok(true);
            }
            if let ExprKind::StaticMember { object, selector } = &target.kind {
                let ExprKind::TypePath(path) = &object.kind else {
                    return Err(error(
                        statement,
                        "qualified initial() requires a captured type path",
                    ));
                };
                if let Some(lookup) = self.lookup {
                    if !self.semantic(lookup.presence(dm_ir::ResolveQuery::HasMemberVar {
                        owner: dm_ir::SymbolId::of(path),
                        name: dm_ir::SymbolId::of(selector),
                    }))? {
                        return Err(error(statement, "qualified initial() field is absent"));
                    }
                }
                // The pinned compiler uses the same static-reference
                // selector as /type::field, rather than Initial(Global).
                self.expression(target, statement)?;
                return Ok(true);
            }
            let (owner, selector) = match &target.kind {
                ExprKind::Ident(field) if self.has_field(field)? => {
                    (Some(VariableWord::Src), field.clone())
                }
                ExprKind::Member {
                    object,
                    selector,
                    via_colon: _,
                } => (self.variable_expr(object, statement).ok(), selector.clone()),
                _ => return Err(error(statement, "initial() requires a field reference")),
            };
            self.intern_string(&selector);
            if let Some(owner) = owner {
                self.emit(
                    opcode::GET_VAR,
                    vec![Word::Variable(VariableWord::SetCache(
                        Box::new(owner),
                        Box::new(VariableWord::StaticField(selector)),
                    ))],
                );
            } else if let ExprKind::Member { object, .. } = &target.kind {
                self.expression(object, statement)?;
                self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                self.emit(
                    opcode::GET_VAR,
                    vec![Word::Variable(VariableWord::StaticField(selector))],
                );
            }
            return Ok(true);
        }
        if name == "issaved" {
            let [target] = args else {
                return Err(error(
                    statement,
                    "issaved() requires one variable reference",
                ));
            };
            let variable = self.assignment_variable(target, statement)?;
            let variable = match variable {
                VariableWord::SetCache(owner, field) => {
                    VariableWord::SetCache(owner, Box::new(VariableWord::IsSaved(field)))
                }
                other => VariableWord::IsSaved(Box::new(other)),
            };
            self.emit(opcode::GET_VAR, vec![Word::Variable(variable)]);
            return Ok(true);
        }
        if name == "arglist" {
            return Err(error(
                statement,
                "built-in reference form is not lowered in this context",
            ));
        }
        if name == "istype" {
            let target_type = match args {
                [value, path] => {
                    self.expression(value, statement)?;
                    self.expression(path, statement)?;
                    self.emit(0x7d, vec![]);
                    return Ok(true);
                }
                [value] => self.inferred_expression_type(value)?,
                _ => return Err(error(statement, "istype() requires one or two arguments")),
            }
            .ok_or_else(|| error(statement, "istype() cannot infer a declared type"))?;
            self.expression(&args[0], statement)?;
            let tag = self
                .class_tag(&target_type)?
                .ok_or_else(|| error(statement, "istype() inferred unsupported type"))?;
            if self.seen_classes.insert(target_type.clone()) {
                self.result.class_paths.push(target_type.clone());
            }
            self.emit(
                opcode::PUSH_VAL,
                vec![Word::Value(ValueWord::ClassPath {
                    path: target_type,
                    tag,
                })],
            );
            self.emit(0x7d, vec![]);
            return Ok(true);
        }
        if name == "del" {
            return Err(error(statement, "del() requires statement context"));
        }
        Ok(false)
    }
}
