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
            .any(|arg| dm_syntax::named_argument(arg).is_some());
        let arglist_argument = dm_syntax::arglist_argument(args);
        let target_kind = dm_syntax::call_target(callee);
        if let dm_syntax::CallTarget::Dynamic {
            dispatcher,
            targets: target,
        } = target_kind
        {
            if !(1..=2).contains(&target.len()) || named_arguments {
                return Err(error(
                    statement,
                    "dynamic call requires target, name, and positional arguments",
                ));
            }
            self.record_selection(
                callee,
                dispatcher,
                dm_ir::SelectedMeaning::DynamicCall {
                    dispatcher: SymbolId::of(dispatcher),
                    target_count: target.len() as u8,
                },
            );
            for target in target {
                self.expression(target, statement)?;
            }
            if let Some(list) = arglist_argument {
                self.expression(list, statement)?;
                self.emit(
                    match (dispatcher, target.len()) {
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
                match (dispatcher, target.len()) {
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
        if let dm_syntax::CallTarget::SafeMember {
            object,
            selector,
            via_colon,
        } = target_kind
        {
            let proc_selector = if via_colon {
                self.member_call_selector(object, selector, true, statement)?
            } else {
                self.safe_member_call_selector(object, selector, statement)?
            };
            self.record_call_selection(callee, selector, &proc_selector, true);
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
        if let dm_syntax::CallTarget::GlobalNamed(name) = target_kind {
            return self.explicit_global_call(
                expr,
                callee,
                name,
                args,
                statement,
                named_arguments,
                arglist_argument,
            );
        }
        if let dm_syntax::CallTarget::Member { object, selector } = target_kind {
            if dm_syntax::is_global_receiver(object) {
                return self.explicit_global_call(
                    expr,
                    callee,
                    selector,
                    args,
                    statement,
                    named_arguments,
                    arglist_argument,
                );
            }
            let via_colon = matches!(
                &callee.kind,
                ExprKind::Member {
                    via_colon: true,
                    ..
                }
            );
            let proc_selector =
                self.member_call_selector(object, selector, via_colon, statement)?;
            self.record_call_selection(callee, selector, &proc_selector, false);
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
        let dm_syntax::CallTarget::Named(name) = target_kind else {
            if matches!(&callee.kind, ExprKind::Literal(_)) {
                // `5()`: a literal is never callable.
                return Err(source_error(
                    statement,
                    &format!("{}missing expression", super::helpers::AT_END),
                ));
            }
            return Err(error(statement, "only simple src proc calls are supported"));
        };
        if self.intrinsic_call(name, args, statement, named_arguments, arglist_argument)? {
            self.record_selection(
                callee,
                name,
                dm_ir::SelectedMeaning::IntrinsicCall(SymbolId::of(name)),
            );
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
    fn explicit_global_call(
        &mut self,
        expr: &Expr,
        callee: &Expr,
        selector: &str,
        args: &[Expr],
        statement: &str,
        named_arguments: bool,
        arglist_argument: Option<&Expr>,
    ) -> Result<(), LowerError> {
        // Authored declarations and executable/native proc identities are
        // different namespaces. A builtin such as abs intentionally has an
        // opaque GlobalProc answer, but the existing source-only query proves
        // whether a captured authored root declaration wins before builtin
        // lowering. Do not convert opaque source membership into absence.
        let authored = if let Some(lookup) = self.lookup {
            let query = dm_ir::ResolveQuery::SourceDeclarationChain {
                owner: SymbolId::of("/"),
                name: SymbolId::of(selector),
                verb: false,
            };
            match self.semantic(lookup.answer(query))? {
                dm_ir::ResolvedMeaning::Missing => false,
                dm_ir::ResolvedMeaning::Members(rows)
                    if matches!(rows.first(),
                    Some(dm_ir::ResolvedMeaning::Declaration { identity, .. })
                    if identity.owner==SymbolId::of("/") && identity.name==SymbolId::of(selector) && !identity.verb) =>
                {
                    true
                }
                _ => {
                    return Err(error(
                        statement,
                        "authored global procedure membership is unavailable",
                    ))
                }
            }
        } else {
            self.has_global_proc(selector)?
        };
        if !authored {
            // Intrinsics have no root procedure reference to fabricate. Reuse
            // existing builtin emission, while forbidding member fallback.
            if self.intrinsic_call(selector, args, statement, named_arguments, arglist_argument)? {
                self.record_selection(
                    callee,
                    selector,
                    dm_ir::SelectedMeaning::IntrinsicCall(SymbolId::of(selector)),
                );
                return Ok(());
            }
            return self.named_call_scoped(
                expr,
                selector,
                args,
                statement,
                named_arguments,
                arglist_argument,
                true,
            );
        }
        if named_arguments || arglist_argument.is_some() {
            if named_arguments {
                self.named_arguments(args, statement)?;
            } else if let Some(list) = arglist_argument {
                self.expression(list, statement)?;
            }
            let reference = self.global_proc(selector)?;
            self.record_selection(
                callee,
                selector,
                dm_ir::SelectedMeaning::ProcedureCall {
                    reference,
                    safe: false,
                },
            );
            self.emit(0xcd, vec![Word::Reference(reference)]);
        } else {
            for arg in args {
                self.expression(arg, statement)?;
            }
            let reference = self.global_proc(selector)?;
            self.record_selection(
                callee,
                selector,
                dm_ir::SelectedMeaning::ProcedureCall {
                    reference,
                    safe: false,
                },
            );
            self.emit(
                opcode::CALL_GLOB,
                vec![
                    Word::Immediate(args.len() as u32),
                    Word::Reference(reference),
                ],
            );
        }
        return Ok(());
    }
}

#[cfg(test)]
mod global_scope_call_tests {
    use super::*;
    fn lower(source: &str) -> SimpleProc {
        let text = format!("/proc/probe()\n    return {source}\n");
        let ast = dm_syntax::parse(&text);
        let mut bindings = LowerBindings::default();
        bindings.global_procs.insert(
            "chosen".into(),
            SymRef::Proc {
                owner: SymbolId::of("/"),
                name: SymbolId::of("chosen"),
                occurrence: 0,
            },
        );
        compile_simple_proc_with_bindings(&ast.items[0].children, &bindings).unwrap()
    }
    #[test]
    fn explicit_scope_dispatch_uses_existing_global_codegen_for_args_and_named_args() {
        for arguments in ["1", "value = 1", "arglist(list(1))"] {
            let scope = lower(&format!("::chosen({arguments})"));
            let member = lower(&format!("global.chosen({arguments})"));
            assert_eq!(scope.code, member.code);
            assert_eq!(scope.strings, member.strings);
            if arguments.starts_with("arglist") {
                let bare = lower(&format!("chosen({arguments})"));
                assert_eq!(scope.code,bare.code,"explicit global must expand arglist exactly like existing bare global dispatch");
                assert_eq!(scope.strings, bare.strings);
            }
        }
    }
}

#[cfg(test)]
mod explicit_global_builtin_tests {
    use super::*;
    fn lower(source: &str, bindings: &LowerBindings) -> Result<SimpleProc, Vec<LowerError>> {
        let text = format!("/proc/probe()\n    return {source}\n");
        let ast = dm_syntax::parse(&text);
        compile_simple_proc_with_bindings(&ast.items[0].children, bindings)
    }
    #[test]
    fn explicit_global_builtins_reuse_bare_emission_without_root_proc_fabrication() {
        let bindings = LowerBindings::default();
        for expression in ["length(\"abc\")", "abs(-2)", "sqrt(4)"] {
            let bare = lower(expression, &bindings).unwrap();
            let explicit = lower(&format!("::{expression}"), &bindings).unwrap();
            assert_eq!(explicit.code, bare.code, "{expression}");
            let receiver = lower(&format!("global.{expression}"), &bindings).unwrap();
            assert_eq!(receiver.code, bare.code, "global receiver {expression}");
            assert_eq!(explicit.strings, bare.strings);
        }
        assert!(lower("::missing()", &bindings).is_err());
        let member = SymRef::Proc {
            owner: SymbolId::of("/datum"),
            name: SymbolId::of("length"),
            occurrence: 0,
        };
        let mut shadowed = LowerBindings {
            current_type_path: Some("/datum".into()),
            ..Default::default()
        };
        shadowed.globals.insert("abs".into());
        shadowed.fields.insert("length".into());
        let mut shared = SharedLowerBindings::default();
        shared.member_procs.insert(
            "/datum".into(),
            std::collections::HashMap::from([
                ("length".into(), member),
                (
                    "abs".into(),
                    SymRef::Proc {
                        owner: SymbolId::of("/datum"),
                        name: SymbolId::of("abs"),
                        occurrence: 0,
                    },
                ),
                (
                    "member_only".into(),
                    SymRef::Proc {
                        owner: SymbolId::of("/datum"),
                        name: SymbolId::of("member_only"),
                        occurrence: 0,
                    },
                ),
            ]),
        );
        shadowed.shared = Some(std::sync::Arc::new(shared));
        for expression in ["length(\"abc\")", "abs(-2)"] {
            let bare = lower(expression, &bindings).unwrap();
            let explicit = lower(&format!("::{expression}"), &shadowed).unwrap();
            assert_eq!(
                explicit.code, bare.code,
                "member/global variable names cannot capture explicit builtin {expression}"
            );
        }
        assert!(lower("::member_only()", &shadowed).is_err());
    }
    #[test]
    fn opaque_global_membership_does_not_fall_through_to_builtin_emission() {
        struct Opaque;
        impl dm_ir::Resolver for Opaque {
            fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
                dm_ir::ResolvedMeaning::Unsupported(query)
            }
        }
        let source = dm_syntax::parse("/proc/probe()\n    return ::abs(-2)\n");
        let body = dm_syntax::parse_body_items(&source.items[0].children);
        let errors = compile_statement_view_with_resolver(
            dm_syntax::StatementView::all(&body.statements),
            &crate::ProcedureInputs::default(),
            &dm_ir::SymbolTable::default(),
            &Opaque,
            None,
        )
        .err()
        .expect("opaque root lookup must remain unsupported");
        assert!(errors
            .iter()
            .all(|error| error.kind != LowerErrorKind::SourceError));
    }
}
