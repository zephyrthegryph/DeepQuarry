//! Reference admission for nameof, without evaluating receivers or emitting operands.
use super::*;
impl Compiler<'_> {
    pub(super) fn admit_nameof_reference(
        &mut self,
        expression: &Expr,
        statement: &str,
    ) -> Result<(), LowerError> {
        match &expression.kind {
            ExprKind::Group(inner) => return self.admit_nameof_reference(inner, statement),
            ExprKind::Ident(name) => {
                self.variable_meaning(name, statement)?;
            }
            ExprKind::TypePath(path) => {
                let Some(lookup) = self.lookup else {
                    // Compatibility callers without a current resolver cannot issue
                    // an absence proof. Their existing spelling behavior is unchanged.
                    if reflective_type_role(path) == ReflectiveTypeRole::BuiltinListValue {
                        return Err(LowerError {
                            kind: LowerErrorKind::SourceError,
                            ..error(statement, "nameof: requires a var, proc reference, or type path"),
                        });
                    }
                    return self.source_feature_reference(expression, true, statement);
                };
                let query = dm_ir::procedure_value_query(path)
                    .unwrap_or(dm_ir::ResolveQuery::Type(SymbolId::of(path)));
                let answer = self.semantic(lookup.answer(query))?;
                match (query, answer) {
                    (
                        dm_ir::ResolveQuery::Type(expected),
                        dm_ir::ResolvedMeaning::Symbol(actual),
                    ) if expected == actual => (),
                    (
                        dm_ir::ResolveQuery::ProcedureValue {
                            owner, name, verb, ..
                        },
                        dm_ir::ResolvedMeaning::Value(dm_ir::SemanticValue::Procedure(identity)),
                    ) if identity.owner == owner
                        && identity.name == name
                        && identity.verb == verb =>
                    {
                        ()
                    }
                    (_, dm_ir::ResolvedMeaning::Missing) => {
                        return Err(LowerError {
                            kind: LowerErrorKind::SourceError,
                            ..error(statement, &format!("{path}: undefined type path"))
                        })
                    }
                    _ => {
                        return self.semantic(Err(
                            lookup.error(query, "nameof reference is not positively captured")
                        ))
                    }
                }
            }
            // Member references retain the existing feature/receiver authority.
            // No ordinary receiver expression is evaluated for reflection.
            _ => (),
        }
        if matches!(&expression.kind, ExprKind::TypePath(path) if reflective_type_role(path) == ReflectiveTypeRole::BuiltinListValue)
        {
            return Err(LowerError {
                kind: LowerErrorKind::SourceError,
                ..error(
                    statement,
                    "nameof: requires a var, proc reference, or type path",
                )
            });
        }
        self.source_feature_reference(expression, true, statement)
    }
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum ReflectiveTypeRole {
    OrdinaryType,
    BuiltinListValue,
}
fn reflective_type_role(path: &str) -> ReflectiveTypeRole {
    // Pinned DM 516.1687 SHA 8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0:
    // nameof_reference_diagnostics/native_list rejects /list while /icon accepts.
    // This is explicit language-role eligibility, independent of DMB allocation.
    if path == "/list" {
        ReflectiveTypeRole::BuiltinListValue
    } else {
        ReflectiveTypeRole::OrdinaryType
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Host {
        opaque: bool,
        queries: std::cell::RefCell<Vec<dm_ir::ResolveQuery>>,
    }
    impl dm_ir::Resolver for Host {
        fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
            self.queries.borrow_mut().push(query);
            if self.opaque {
                return dm_ir::ResolvedMeaning::Unsupported(query);
            }
            match query {
                dm_ir::ResolveQuery::Type(path)
                    if path == SymbolId::of("/icon") || path == SymbolId::of("/list") =>
                {
                    dm_ir::ResolvedMeaning::Symbol(path)
                }
                _ => dm_ir::ResolvedMeaning::Missing,
            }
        }
    }
    #[test]
    fn nameof_current_reference_admission_rejects_missing_and_preserves_opaque_queries() {
        let mut symbols = dm_ir::SymbolTable::default();
        for name in [
            "/icon",
            "/list",
            "/datum/actually_absent",
            "/datum",
            "actually_absent",
            "present",
        ] {
            symbols.intern(name).unwrap();
        }
        let bindings = LowerBindings {
            parameters: vec!["present".into()],
            ..Default::default()
        };
        let host = Host {
            opaque: false,
            queries: Default::default(),
        };
        for source in [
            "/datum/actually_absent",
            "/datum/proc/actually_absent",
            "actually_absent",
        ] {
            let expression = dm_syntax::parse_expression(source).expr.unwrap();
            let error = observe_reference_source_features(&expression, &bindings, &symbols, &host)
                .unwrap_err();
            assert_eq!(
                error.kind,
                LowerErrorKind::SourceError,
                "{source}: {error:?}"
            );
        }
        // Reflective type existence is independent of native runtime class tags.
        let icon = dm_syntax::parse_expression("/icon").expr.unwrap();
        assert_eq!(
            observe_reference_source_features(&icon, &bindings, &symbols, &host).unwrap(),
            SourceFeatures::default()
        );
        let list = dm_syntax::parse_expression("/list").expr.unwrap();
        let error =
            observe_reference_source_features(&list, &bindings, &symbols, &host).unwrap_err();
        assert_eq!(error.kind, LowerErrorKind::SourceError);
        assert_eq!(
            error.reason,
            "nameof: requires a var, proc reference, or type path"
        );
        assert!(!host
            .queries
            .borrow()
            .iter()
            .any(|q| matches!(q, dm_ir::ResolveQuery::RuntimeType(_))));
        host.queries.borrow_mut().clear();
        let local = dm_syntax::parse_expression("present").expr.unwrap();
        assert!(observe_reference_source_features(&local, &bindings, &symbols, &host).is_ok());
        assert!(host.queries.borrow().is_empty());
        let opaque = Host {
            opaque: true,
            queries: Default::default(),
        };
        let error =
            observe_reference_source_features(&icon, &bindings, &symbols, &opaque).unwrap_err();
        assert_eq!(error.kind, LowerErrorKind::UnsupportedModel);
    }
}
