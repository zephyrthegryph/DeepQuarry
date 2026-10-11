//! Typed constructor-reference diagnostics use the same current resolver facts
//! as ordinary evaluation. No source locations are retained or invented here.
use super::*;

impl DriverEvaluator<'_> {
    pub(super) fn declared_constructor_type(
        &self,
        write: &dm_ir::InitializerWrite,
    ) -> Result<Option<SymbolId>, String> {
        let query = match write.target {
            dm_ir::InitializerTarget::Shared { owner, name, .. } if owner == SymbolId::of("/") => {
                ResolveQuery::GlobalVar(name)
            }
            dm_ir::InitializerTarget::Shared { owner, name, .. }
            | dm_ir::InitializerTarget::Instance {
                receiver_owner: owner,
                name,
                ..
            } => ResolveQuery::DeclaredVarType { owner, name },
            dm_ir::InitializerTarget::ProcedureStatic(identity) => ResolveQuery::ProcedureStatic {
                procedure: identity.procedure,
                name: identity.name,
            },
        };
        match self.resolver.resolve(query) {
            ResolvedMeaning::DeclaredType(value) => Ok(value),
            ResolvedMeaning::Member { data, .. } if data.inherited_opaque.is_none() => {
                Ok(data.declared_type)
            }
            ResolvedMeaning::ProcedureStatic(declaration) => Ok(declaration.declared_type),
            _ => Err("initializer constructor declared type is not captured".into()),
        }
    }

    pub(super) fn constructor_reference_error(
        &self,
        write: &dm_ir::InitializerWrite,
        ast: &dm_syntax::Expr,
    ) -> Option<String> {
        fn modified(evaluator: &DriverEvaluator<'_>, node: &dm_syntax::Expr) -> Option<String> {
            if let dm_syntax::ExprKind::ObjectInitializer { object, .. } = &node.kind {
                if let dm_syntax::ExprKind::TypePath(path) = &object.kind {
                    // The object of a modified instance is necessarily a type;
                    // ordinary expressions/proc paths aren't reclassified here.
                    if matches!(
                        evaluator
                            .resolver
                            .resolve(ResolveQuery::RuntimeType(SymbolId::of(
                                path.trim_end_matches('/')
                            ))),
                        ResolvedMeaning::Missing
                    ) {
                        return Some(format!("{path}: undefined type"));
                    }
                }
            }
            let mut failure = None;
            dm_syntax::for_each_expression_child(node, |_, child| {
                if failure.is_none() {
                    failure = modified(evaluator, child);
                }
            });
            failure
        }
        if let Some(failure) = modified(self, ast) {
            return Some(failure);
        }
        let mut root = ast;
        while let dm_syntax::ExprKind::Group(value) = &root.kind {
            root = value;
        }
        let inferred = match &root.kind {
            dm_syntax::ExprKind::Ident(name) => name == "new",
            dm_syntax::ExprKind::Call { callee, .. } => {
                matches!(&callee.kind, dm_syntax::ExprKind::Ident(name) if name == "new")
            }
            _ => false,
        };
        if !inferred {
            return None;
        }
        // Only the root initializer owns this write's declared type. Nested
        // implicit constructors need their own field/argument context authority.
        let path = self.declared_constructor_type(write).ok().flatten()?;
        let name = match write.target {
            dm_ir::InitializerTarget::Shared { name, .. }
            | dm_ir::InitializerTarget::Instance { name, .. } => name,
            dm_ir::InitializerTarget::ProcedureStatic(identity) => identity.name,
        };
        let spelling = self.symbols.text(name)?;
        matches!(
            self.resolver.resolve(ResolveQuery::RuntimeType(path)),
            ResolvedMeaning::Missing
        )
        .then(|| format!("{spelling}: unknown variable type"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Host {
        runtime: ResolvedMeaning,
        reads: std::sync::Mutex<Vec<ResolveQuery>>,
    }
    impl Resolver for Host {
        fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
            self.reads.lock().unwrap().push(query);
            match query {
                ResolveQuery::DeclaredVarType { .. } => {
                    ResolvedMeaning::DeclaredType(Some(SymbolId::of("/datum/missing")))
                }
                ResolveQuery::RuntimeType(_) => self.runtime.clone(),
                _ => ResolvedMeaning::Unsupported(query),
            }
        }
    }
    fn write() -> dm_ir::InitializerWrite {
        let owner = SymbolId::of("/datum/probe");
        dm_ir::InitializerWrite {
            source_site: dm_ir::InitializerSite::Declaration,
            target: dm_ir::InitializerTarget::Instance {
                declaring_owner: owner,
                receiver_owner: owner,
                name: SymbolId::of("value"),
            },
            lexical_owner: owner,
            lexical_procedure: None,
            value: dm_ir::InitializerValue::NoAuthoredValue,
            declared_array: None,
            declaration_flags: Some(0),
        }
    }
    #[test]
    fn definite_missing_modified_and_implied_types_are_typed_source_errors() {
        let mut symbols = dm_ir::SymbolTable::default();
        symbols.intern("/datum/missing").unwrap();
        symbols.intern("value").unwrap();
        let host = Host {
            runtime: ResolvedMeaning::Missing,
            reads: Default::default(),
        };
        let evaluator = DriverEvaluator {
            pure_calls: None,
            resource_search_context: None,
            resolver: &host,
            symbols: &symbols,
        };
        for source in [
            "/datum/missing{amount=1}",
            "new",
            "new(1)",
            "list(/datum/missing{amount=1})",
        ] {
            let parsed = dm_syntax::parse_expression(source);
            assert!(
                parsed.diagnostics.is_empty(),
                "{source}: {:?}",
                parsed.diagnostics
            );
            let result = evaluator
                .evaluate_ast_write(&write(), parsed.expr.as_ref().unwrap(), source, &symbols)
                .unwrap();
            let expected = if source.starts_with("new") {
                "value: unknown variable type"
            } else {
                "/datum/missing: undefined type"
            };
            assert!(
                matches!(result, Evaluation::SourceError(ref reason) if reason == expected),
                "{source}"
            );
        }
        assert!(host
            .reads
            .lock()
            .unwrap()
            .contains(&ResolveQuery::RuntimeType(SymbolId::of("/datum/missing"))));
    }
    #[test]
    fn opaque_types_decline_and_positive_aliases_keep_current_runtime_mapping() {
        let mut symbols = dm_ir::SymbolTable::default();
        symbols.intern("/datum/missing").unwrap();
        symbols.intern("value").unwrap();
        let runtime_query = ResolveQuery::RuntimeType(SymbolId::of("/datum/missing"));
        for runtime in [
            ResolvedMeaning::Unsupported(runtime_query),
            ResolvedMeaning::Symbol(SymbolId::of("/datum/current")),
        ] {
            let host = Host {
                runtime: runtime.clone(),
                reads: Default::default(),
            };
            let evaluator = DriverEvaluator {
                pure_calls: None,
                resource_search_context: None,
                resolver: &host,
                symbols: &symbols,
            };
            for source in ["new", "/datum/missing{amount=1}"] {
                let parsed = dm_syntax::parse_expression(source);
                assert_eq!(
                    evaluator.constructor_reference_error(&write(), parsed.expr.as_ref().unwrap()),
                    None
                );
            }
            let actual = evaluator.initializer_constructor_type(&write());
            match runtime {
                ResolvedMeaning::Symbol(path) => assert_eq!(actual.unwrap(), Some(path)),
                _ => assert!(actual.is_err()),
            }
        }
    }
    #[test]
    fn nested_implicit_new_does_not_borrow_enclosing_write_type() {
        let symbols = dm_ir::SymbolTable::default();
        let host = Host {
            runtime: ResolvedMeaning::Missing,
            reads: Default::default(),
        };
        let evaluator = DriverEvaluator {
            pure_calls: None,
            resource_search_context: None,
            resolver: &host,
            symbols: &symbols,
        };
        // Explicit empty arguments terminate the nested implied constructor;
        // bare `new` is only recognized at the expression input's end.
        let parsed = dm_syntax::parse_expression("list(new())");
        assert!(parsed.diagnostics.is_empty());
        assert_eq!(
            evaluator.constructor_reference_error(&write(), parsed.expr.as_ref().unwrap()),
            None
        );
        assert!(host.reads.lock().unwrap().is_empty());
    }
}
