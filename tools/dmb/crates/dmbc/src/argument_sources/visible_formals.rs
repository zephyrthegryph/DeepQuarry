//! Later formal rejection from the same checked lexical selections as codegen.
use super::*;
use dm_codegen_byond::{LowerError, LowerErrorKind, LowerSpan};

pub(super) fn compile<R: Resolver>(
    container: &Item,
    expression: &str,
    argument: usize,
    metadata: &ProcedureMetadata,
    frame: &ProcedureInputs,
    symbols: &SymbolTable,
    host: &R,
) -> Result<ResolverProc, Vec<LowerError>> {
    let parsed = dm_syntax::parse_body_items(&container.children);
    if !parsed.diagnostics.is_empty() {
        return dm_codegen_byond::compile_simple_proc_with_resolver_and_debug(
            &container.children,
            frame,
            symbols,
            host,
            Some(&FixedOrigin),
        );
    }
    let (code, references) =
        dm_codegen_byond::compile_statement_view_with_resolver_and_references_at(
            dm_syntax::StatementView::all(&parsed.statements),
            frame,
            symbols,
            host,
            Some(&FixedOrigin),
            dm_syntax::Span {
                start: 0,
                end: SYNTAX_PREFIX.len() + expression.len() + 1,
            },
        )?;
    let mut errors = Vec::new();
    for reference in references.references {
        let dm_ir::SelectedMeaning::Argument(index) = reference.meaning else {
            continue;
        };
        if index as usize <= argument {
            continue;
        }
        let issued = metadata
            .signature
            .parameters
            .get(index as usize)
            .is_some_and(|parameter| parameter.name == reference.name);
        let span = reference
            .relative_span
            .map(|(start, end)| LowerSpan { start, end });
        errors.push(LowerError {
            reason: if issued && span.is_some() {
                "invalid variable".into()
            } else {
                "argument source lexical selection lacks current signature provenance".into()
            },
            span,
            kind: if issued && span.is_some() {
                LowerErrorKind::SourceError
            } else {
                LowerErrorKind::Internal
            },
            ..Default::default()
        });
    }
    if errors.is_empty() {
        Ok(code)
    } else {
        Err(errors)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    struct Source<'a>(&'a str);
    impl dm_preprocess::SourceProvider for Source<'_> {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok(self.0.into())
        }
    }
    #[test]
    fn actual_helper_lexical_selection_rejects_later_formal_at_current_signature() {
        let engine = crate::engine::EngineSnapshot::from_bytes(
            include_bytes!("../../../../fixtures/native_template.bin"),
            1,
        )
        .unwrap();
        for (formals, expected_error) in [
            ("value as num in choices(value)", false),
            ("earlier, value as num in choices(earlier)", false),
            ("value as num in choices(args[1])", false),
            ("value as num in choices(later), later", true),
        ] {
            for padding in ["", "\n\n"] {
                let text = format!(
                    "{padding}/proc/choices(x)\n    return list(x)\n/proc/probe({formals})\n    return value\n"
                );
                let seed = engine.frontend_seed();
                let frontend = dm_tree::frontend::build_with_config(
                    std::path::Path::new("probe.dme"),
                    &Source(&text),
                    &Default::default(),
                    dm_tree::frontend::FrontendConfig {
                        workers: 1,
                        engine: Some(&seed),
                        observer: None,
                    },
                )
                .unwrap();
                let (host, _) =
                    crate::request_runner::runner_facts::prepare(&frontend, &engine).unwrap();
                let body = frontend
                    .bodies
                    .iter()
                    .find(|body| {
                        frontend
                            .snapshot
                            .tree
                            .member(body.member)
                            .is_some_and(|member| member.name == SymbolId::of("probe"))
                    })
                    .unwrap();
                let metadata = frontend
                    .snapshot
                    .tree
                    .member(body.member)
                    .unwrap()
                    .metadata
                    .procedure
                    .as_ref()
                    .unwrap();
                let symbols = frontend.snapshot.tree.symbols();
                let inputs = ProcedureInputs {
                    parameters: metadata
                        .signature
                        .parameters
                        .iter()
                        .map(|parameter| symbols.text(parameter.name).unwrap().to_owned())
                        .collect(),
                    ..Default::default()
                };
                let argument = metadata
                    .signature
                    .parameters
                    .iter()
                    .position(|parameter| parameter.source_expression.is_some())
                    .unwrap();
                let helper = ArgumentSourceHelper {
                    argument,
                    frame_parameters: inputs.parameters.clone(),
                    expression: metadata.signature.parameters[argument]
                        .source_expression
                        .clone()
                        .unwrap(),
                };
                let result = lower_helpers(
                    HelperInputs {
                        frontend: &frontend,
                        parsed: frontend.compact_body(body).unwrap().into(),
                        metadata,
                        owner: UnitIdentity {
                            owner: SymbolId::of("/"),
                            name: SymbolId::of("probe"),
                            namespace: crate::lowering::Namespace::Proc,
                            occurrence: 0,
                        },
                        inputs: &inputs,
                        helpers: std::slice::from_ref(&helper),
                        symbols,
                    },
                    &host,
                );
                if expected_error {
                    let HelperFailure::Diagnostics(errors) =
                        result.err().expect("later formal must be rejected")
                    else {
                        panic!("typed source error lost")
                    };
                    assert_eq!(errors.len(), 1);
                    assert_eq!(
                        errors[0].kind,
                        dm_tree::frontend::DiagnosticKind::SourceError
                    );
                    assert_eq!(errors[0].message, "invalid variable");
                    assert_eq!(errors[0].origin.line, 3 + padding.lines().count());
                } else {
                    assert!(
                        result.is_ok(),
                        "current/preceding/dynamic formal must stay legal: {:?}",
                        result.err()
                    );
                }
            }
        }
    }
}
