//! Calls dispatch lowering over the shared compiler context.
use super::*;

impl Compiler<'_> {
    pub(super) fn expression_call(
        &mut self,
        expr: &Expr,
        callee: &Expr,
        args: &[Expr],
        statement: &str,
    ) -> Result<(), LowerError> {
        let named_arguments = args
            .iter()
            .any(|arg| matches!(&arg.kind, ExprKind::Binary { op, .. } if op == "="));
        let arglist_argument = args.first().filter(|_| args.len() == 1).and_then(|arg| {
            let ExprKind::Call { callee, args } = &arg.kind else {
                return None;
            };
            (matches!(&callee.kind, ExprKind::Ident(name) if name == "arglist") && args.len() == 1)
                .then(|| &args[0])
        });
        if let ExprKind::Call {
            callee: dispatcher,
            args: target,
        } = &callee.kind
        {
            if let ExprKind::Ident(dispatcher) = &dispatcher.kind {
                if dispatcher == "call" || dispatcher == "call_ext" {
                    if !(1..=2).contains(&target.len()) || named_arguments {
                        return Err(error(
                            statement,
                            "dynamic call requires target, name, and positional arguments",
                        ));
                    }
                    for target in target {
                        self.expression(target, statement)?;
                    }
                    if let Some(list) = arglist_argument {
                        self.expression(list, statement)?;
                        self.emit(
                            match (dispatcher.as_str(), target.len()) {
                                ("call", 1) => 0xcb,
                                ("call", 2) => 0xcc,
                                ("call_ext", 1) => 0x17b,
                                ("call_ext", 2) => 0x117,
                                _ => unreachable!(),
                            },
                            vec![],
                        );
                        return Ok(());
                    }
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                    self.emit(
                        match (dispatcher.as_str(), target.len()) {
                            ("call", 1) => 0x2b,
                            ("call", 2) => 0xb5,
                            ("call_ext", 1) => 0x17a,
                            ("call_ext", 2) => 0x116,
                            _ => unreachable!(),
                        },
                        vec![Word::Immediate(args.len() as u32)],
                    );
                    return Ok(());
                }
            }
        }
        if let ExprKind::SafeMember { object, selector } = &callee.kind {
            let proc_selector = self
                .expression_member_proc(object, selector)?
                .map(member_proc_selector)
                .unwrap_or_else(|| {
                    VariableWord::DynamicProc(self.intern_string(&selector.replace('_', " ")))
                });
            self.expression(object, statement)?;
            let end = self.label();
            self.emit(317, vec![Word::Branch(end)]);
            self.emit(opcode::PUSH_CACHE, vec![]);
            if named_arguments {
                self.named_arguments(args, statement)?;
            } else if let Some(list) = arglist_argument {
                self.expression(list, statement)?;
            } else {
                for arg in args {
                    self.expression(arg, statement)?;
                }
            }
            self.emit(opcode::POP_CACHE, vec![]);
            self.emit(
                opcode::CALL,
                vec![
                    Word::Variable(proc_selector),
                    Word::Immediate(if named_arguments || arglist_argument.is_some() {
                        u16::MAX as u32
                    } else {
                        args.len() as u32
                    }),
                ],
            );
            self.result.code.items.push(CodeItem::Label(end));
            return Ok(());
        }
        if let ExprKind::Member {
            object, selector, ..
        } = &callee.kind
        {
            if matches!(&object.kind, ExprKind::Ident(name) if name == "global") {
                if !self.has_global_proc(selector)? {
                    return Err(error(
                        statement,
                        &format!("unresolved global procedure: {selector}"),
                    ));
                }
                if named_arguments {
                    self.named_arguments(args, statement)?;
                    self.emit(0xcd, vec![Word::Reference(self.global_proc(selector)?)]);
                } else {
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                    self.emit(
                        opcode::CALL_GLOB,
                        vec![
                            Word::Immediate(args.len() as u32),
                            Word::Reference(self.global_proc(selector)?),
                        ],
                    );
                }
                return Ok(());
            }
            let proc_selector = self
                .expression_member_proc(object, selector)?
                .map(member_proc_selector)
                .unwrap_or_else(|| {
                    VariableWord::DynamicProc(self.intern_string(&selector.replace('_', " ")))
                });
            let mut safe_labels = Vec::new();
            if let Ok(owner) = self.variable_expr(object, statement) {
                if named_arguments {
                    self.named_arguments(args, statement)?;
                } else if let Some(list) = arglist_argument {
                    self.expression(list, statement)?;
                } else {
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                }
                self.emit(
                    self.direct_call_opcode(expr),
                    vec![
                        Word::Variable(VariableWord::SetCache(
                            Box::new(owner),
                            Box::new(proc_selector.clone()),
                        )),
                        Word::Immediate(if named_arguments || arglist_argument.is_some() {
                            u16::MAX as u32
                        } else {
                            args.len() as u32
                        }),
                    ],
                );
            } else {
                self.expression(object, statement)?;
                safe_labels = self.defer_safe_postfix_labels(object);
                self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                self.emit(opcode::PUSH_CACHE, vec![]);
                if named_arguments {
                    self.named_arguments(args, statement)?;
                } else if let Some(list) = arglist_argument {
                    self.expression(list, statement)?;
                } else {
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                }
                self.emit(opcode::POP_CACHE, vec![]);
                self.emit(
                    opcode::CALL,
                    vec![
                        Word::Variable(proc_selector),
                        Word::Immediate(if named_arguments || arglist_argument.is_some() {
                            u16::MAX as u32
                        } else {
                            args.len() as u32
                        }),
                    ],
                );
            }
            self.result.code.items.extend(safe_labels);
            return Ok(());
        }
        let ExprKind::Ident(name) = &callee.kind else {
            return Err(error(statement, "only simple src proc calls are supported"));
        };
        if self.intrinsic_call(name, args, statement, named_arguments, arglist_argument)? {
            return Ok(());
        }
        self.named_call(
            expr,
            name,
            args,
            statement,
            named_arguments,
            arglist_argument,
        )
    }
}
