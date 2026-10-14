//! Variable-member reflection uses current selection facts, without receiver evaluation.
use super::*;
impl Compiler<'_> {
    pub(super) fn admit_nameof_member(
        &self,
        object: &Expr,
        selector: &str,
        operator: &str,
        statement: &str,
    ) -> Result<(), LowerError> {
        let Some(lookup) = self.lookup else {
            return Ok(());
        };
        let reference = match &object.kind {
            ExprKind::TypePath(path) => format!("{path}{operator}{selector}"),
            ExprKind::Ident(name) => format!("{name}{operator}{selector}"),
            _ => selector.to_owned(),
        };
        let owner = match &object.kind {
            ExprKind::TypePath(path) => {
                let query = dm_ir::ResolveQuery::Type(SymbolId::of(path));
                match self.semantic(lookup.answer(query))? {
                    dm_ir::ResolvedMeaning::Symbol(actual) if actual == SymbolId::of(path) => {
                        Some(path.clone())
                    }
                    dm_ir::ResolvedMeaning::Missing => {
                        return Err(LowerError {
                            kind: LowerErrorKind::SourceError,
                            ..error(statement, &format!("{path}: undefined type path"))
                        })
                    }
                    _ => {
                        return self
                            .semantic(Err(lookup
                                .error(query, "nameof receiver type is not positively captured")))
                    }
                }
            }
            ExprKind::Ident(name) if name == "type" => self.bindings.current_type_path.clone(),
            // Reflection requires semantic existence, not a runtime class operand.
            _ => dm_ir::receiver_resolution::infer_receiver_type(
                &receiver_resolution::ReceiverContext(self, true),
                object,
            )?,
        };
        let Some(owner) = owner else {
            // Successful inference with no static type is not an opaque host answer:
            // pinned untyped dot/colon reference controls have no variable namespace.
            return Err(LowerError {
                kind: LowerErrorKind::SourceError,
                ..error(statement, &format!("{reference}: undefined var"))
            });
        };
        let owner = SymbolId::of(&owner);
        let name = SymbolId::of(selector);
        let query = dm_ir::ResolveQuery::HasMemberVar { owner, name };
        if !self.semantic(lookup.presence(query))? {
            return Err(LowerError {
                kind: LowerErrorKind::SourceError,
                ..error(statement, &format!("{reference}: undefined var"))
            });
        }
        self.validate_variable_type(
            &dm_ir::SelectedMeaning::InstanceField {
                owner: Some(owner),
                name,
            },
            selector,
            statement,
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Host {
        opaque: bool,
    }
    impl dm_ir::Resolver for Host {
        fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
            if self.opaque {
                return dm_ir::ResolvedMeaning::Unsupported(query);
            }
            match query {
                dm_ir::ResolveQuery::Type(path) => dm_ir::ResolvedMeaning::Symbol(path),
                dm_ir::ResolveQuery::RuntimeType(_) => dm_ir::ResolvedMeaning::Unsupported(query),
                dm_ir::ResolveQuery::HasMemberVar { name, .. } => {
                    dm_ir::ResolvedMeaning::Presence(name == SymbolId::of("known"))
                }
                dm_ir::ResolveQuery::DeclaredVarType { .. } => {
                    dm_ir::ResolvedMeaning::DeclaredType(None)
                }
                _ => dm_ir::ResolvedMeaning::Missing,
            }
        }
    }
    #[test]
    fn member_reflection_uses_current_variable_presence_without_value_or_proc_operands() {
        let mut symbols = dm_ir::SymbolTable::default();
        for text in ["R", "/datum/receiver", "known", "missing"] {
            symbols.intern(text).unwrap();
        }
        let bindings = LowerBindings {
            parameters: vec!["R".into()],
            parameter_types: [("R".into(), "/datum/receiver".into())]
                .into_iter()
                .collect(),
            ..Default::default()
        };
        for source in ["R.known", "/datum/receiver::known"] {
            let expression = dm_syntax::parse_expression(source).expr.unwrap();
            assert!(
                observe_reference_source_features(
                    &expression,
                    &bindings,
                    &symbols,
                    &Host { opaque: false }
                )
                .is_ok(),
                "{source}"
            );
        }
        for source in ["R.missing", "/datum/receiver::missing"] {
            let expression = dm_syntax::parse_expression(source).expr.unwrap();
            let error = observe_reference_source_features(
                &expression,
                &bindings,
                &symbols,
                &Host { opaque: false },
            )
            .unwrap_err();
            assert_eq!(
                error.kind,
                LowerErrorKind::SourceError,
                "{source}: {error:?}"
            );
            assert_eq!(error.reason, format!("{source}: undefined var"));
            let opaque = observe_reference_source_features(
                &expression,
                &bindings,
                &symbols,
                &Host { opaque: true },
            )
            .unwrap_err();
            assert_eq!(opaque.kind, LowerErrorKind::UnsupportedModel);
        }
    }
}
