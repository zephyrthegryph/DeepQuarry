//! Reference admission for nameof, without evaluating receivers or emitting operands.
#[path = "nameof_member_admission.rs"]
mod members;
use super::*;
/// Recovery stage for a rejected reference, issued from the same language-role
/// policy as admission. This does not classify opaque resolver failures.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NameofDiagnosticRecovery {
    ReferenceRejected,
    ReferenceRequired,
}
pub fn nameof_diagnostic_recovery(expression: &Expr) -> NameofDiagnosticRecovery {
    match &expression.kind {
        ExprKind::Group(inner) => nameof_diagnostic_recovery(inner),
        ExprKind::TypePath(path)
            if reflective_type_role(path) == ReflectiveTypeRole::BuiltinListValue =>
        {
            NameofDiagnosticRecovery::ReferenceRequired
        }
        ExprKind::Ident(_)
        | ExprKind::TypePath(_)
        | ExprKind::Member { .. }
        | ExprKind::StaticMember { .. } => NameofDiagnosticRecovery::ReferenceRejected,
        _ => NameofDiagnosticRecovery::ReferenceRequired,
    }
}
impl Compiler<'_> {
    fn admit_nameof_lexical_type(
        &self,
        meaning: &dm_ir::SelectedMeaning,
        name: &str,
        statement: &str,
    ) -> Result<(), LowerError> {
        let path = match meaning {
            dm_ir::SelectedMeaning::Local(_) => self.local_types.get(name).map(String::as_str),
            dm_ir::SelectedMeaning::Argument(_) => {
                self.bindings.parameter_types.get(name).map(String::as_str)
            }
            _ => None,
        };
        let (Some(path), Some(lookup)) = (path, self.lookup) else {
            return Ok(());
        };
        let query = dm_ir::ResolveQuery::Type(SymbolId::of(path));
        match self.semantic(lookup.answer(query))? {
            dm_ir::ResolvedMeaning::Symbol(actual) if actual == SymbolId::of(path) => Ok(()),
            dm_ir::ResolvedMeaning::Missing => Err(LowerError {
                kind: LowerErrorKind::SourceError,
                ..error(
                    statement,
                    &crate::lower_diagnostics::undefined_type_message(statement, name, path),
                )
            }),
            _ => self.semantic(Err(
                lookup.error(query, "nameof lexical type is not positively captured")
            )),
        }
    }
    pub(super) fn admit_nameof_reference(
        &mut self,
        expression: &Expr,
        statement: &str,
    ) -> Result<(), LowerError> {
        match &expression.kind {
            ExprKind::Group(inner) => return self.admit_nameof_reference(inner, statement),
            ExprKind::Ident(name) => {
                let meaning = self.variable_meaning(name, statement)?;
                self.admit_nameof_lexical_type(&meaning, name, statement)?;
            }
            ExprKind::TypePath(path) => {
                let Some(lookup) = self.lookup else {
                    // Compatibility callers without a current resolver cannot issue
                    // an absence proof. Their existing spelling behavior is unchanged.
                    if reflective_type_role(path) == ReflectiveTypeRole::BuiltinListValue {
                        return Err(LowerError {
                            kind: LowerErrorKind::SourceError,
                            ..error(
                                statement,
                                "nameof: requires a var, proc reference, or type path",
                            )
                        });
                    }
                    return self.source_feature_reference(expression, true, statement);
                };
                let query =
                    reflective_procedure_query(path, self.bindings.current_type_path.as_deref())
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
                    (
                        dm_ir::ResolveQuery::MethodProcedureValue { owner, name, verb },
                        dm_ir::ResolvedMeaning::Value(dm_ir::SemanticValue::Procedure(identity)),
                    ) if identity.name == name && identity.verb == verb => {
                        let ancestry_query = dm_ir::ResolveQuery::Ancestry(owner);
                        match self.semantic(lookup.answer(ancestry_query))? {
                            dm_ir::ResolvedMeaning::Symbols(ancestry)
                                if ancestry.contains(&identity.owner) =>
                            {
                                ()
                            }
                            _ => return self.semantic(Err(lookup.error(
                                ancestry_query,
                                "nameof formal declaration is outside current receiver ancestry",
                            ))),
                        }
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
            ExprKind::Member {
                object,
                selector,
                via_colon,
            } => {
                self.admit_nameof_member(
                    object,
                    selector,
                    if *via_colon { ":" } else { "." },
                    statement,
                )?;
            }
            ExprKind::StaticMember { object, selector } => {
                self.admit_nameof_member(object, selector, "::", statement)?;
            }
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

/// Dot-formal paths select the current receiver's actual formal anchor,
/// including inheritance. Relative `.proc` is issued in lexical type scope;
/// it is never a semantic type named `.proc/name`.
fn reflective_procedure_query(
    path: &str,
    current_type: Option<&str>,
) -> Option<dm_ir::ResolveQuery> {
    let selection = path
        .rsplit_once(".proc/")
        .map(|(owner, name)| (owner, name, false))
        .or_else(|| {
            path.rsplit_once(".verb/")
                .map(|(owner, name)| (owner, name, true))
        });
    if let Some((owner, name, verb)) = selection {
        if name.is_empty() || name.contains('/') {
            return None;
        }
        let owner = if owner.is_empty() || owner == "type" {
            current_type?
        } else {
            owner
        };
        return Some(dm_ir::ResolveQuery::MethodProcedureValue {
            owner: SymbolId::of(owner),
            name: SymbolId::of(name),
            verb,
        });
    }
    if let Some(tail) = path.strip_prefix("type/") {
        let path = format!("{}/{}", current_type?, tail);
        return dm_ir::procedure_value_query(&path);
    }
    dm_ir::procedure_value_query(path)
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
    #[test]
    fn nameof_recovery_category_uses_reference_role_not_error_text() {
        for (source, expected) in [
            ("missing", NameofDiagnosticRecovery::ReferenceRejected),
            (
                "/datum/missing",
                NameofDiagnosticRecovery::ReferenceRejected,
            ),
            ("R.missing", NameofDiagnosticRecovery::ReferenceRejected),
            ("/list", NameofDiagnosticRecovery::ReferenceRequired),
            ("(/list)", NameofDiagnosticRecovery::ReferenceRequired),
            ("1", NameofDiagnosticRecovery::ReferenceRequired),
        ] {
            let expression = dm_syntax::parse_expression(source).expr.unwrap();
            assert_eq!(
                nameof_diagnostic_recovery(&expression),
                expected,
                "{source}"
            );
        }
    }
    struct Host {
        opaque: bool,
        queries: std::sync::Mutex<Vec<dm_ir::ResolveQuery>>,
    }
    impl dm_ir::Resolver for Host {
        fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
            self.queries.lock().unwrap().push(query);
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
    fn issued_lexical_locals_shadow_globals_and_require_current_declared_type() {
        let mut symbols = dm_ir::SymbolTable::default();
        for name in ["local", "/datum/actually_absent"] {
            symbols.intern(name).unwrap();
        }
        let expression = dm_syntax::parse_expression("local").expr.unwrap();
        let host = Host {
            opaque: false,
            queries: Default::default(),
        };
        let bindings = LowerBindings::default();
        assert!(observe_reference_source_features_with_lexical_locals(
            &expression,
            &bindings,
            &symbols,
            &host,
            &[("local".into(), None)]
        )
        .is_ok());
        assert!(host.queries.lock().unwrap().is_empty());
        let error = observe_reference_source_features_with_lexical_locals(
            &expression,
            &bindings,
            &symbols,
            &host,
            &[("local".into(), Some("/datum/actually_absent".into()))],
        )
        .unwrap_err();
        assert_eq!(error.kind, LowerErrorKind::SourceError);
        assert_eq!(
            *host.queries.lock().unwrap(),
            [dm_ir::ResolveQuery::Type(SymbolId::of(
                "/datum/actually_absent"
            ))]
        );
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
            .lock()
            .unwrap()
            .iter()
            .any(|q| matches!(q, dm_ir::ResolveQuery::RuntimeType(_))));
        host.queries.lock().unwrap().clear();
        let local = dm_syntax::parse_expression("present").expr.unwrap();
        assert!(observe_reference_source_features(&local, &bindings, &symbols, &host).is_ok());
        assert!(host.queries.lock().unwrap().is_empty());
        let opaque = Host {
            opaque: true,
            queries: Default::default(),
        };
        let error =
            observe_reference_source_features(&icon, &bindings, &symbols, &opaque).unwrap_err();
        assert_eq!(error.kind, LowerErrorKind::UnsupportedModel);
    }
}
