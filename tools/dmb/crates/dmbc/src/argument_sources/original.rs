//! Explicit original-root consumers. No default producer switch is made here.
use super::*;
use dm_tree::frontend::{BodyOccurrence, OriginalHeaderExpressionHandle};
fn symbolic_matches(
    expression: &dm_ir::SymbolicExpression,
    text: &str,
    symbols: &SymbolTable,
) -> bool {
    let mut rest = text;
    let mut previous = None;
    for token in expression.tokens.iter() {
        if previous.is_some_and(|end| end != token.relative_span.start) {
            let Some(tail) = rest.strip_prefix(' ') else {
                return false;
            };
            rest = tail;
        }
        let Some(spelling) = symbols.text(token.text) else {
            return false;
        };
        let Some(tail) = rest.strip_prefix(spelling) else {
            return false;
        };
        rest = tail;
        previous = Some(token.relative_span.end);
    }
    rest.is_empty()
}
fn validate_original_defaults(
    frontend: &ColdFrontend,
    occurrence: &BodyOccurrence,
    header: &OriginalHeaderExpressionHandle<'_>,
    metadata: &ProcedureMetadata,
    inputs: &ProcedureInputs,
    symbols: &SymbolTable,
) -> Result<(), String> {
    header.require_for(frontend, occurrence, metadata)?;
    let view = header.view()?;
    if inputs.parameters.len() != metadata.signature.parameters.len()
        || (!inputs.parameter_defaults.is_empty()
            && inputs.parameter_defaults.len() != inputs.parameters.len())
    {
        return Err("original formal frame count differs from prepared ABI".into());
    }
    for (index, parameter) in metadata.signature.parameters.iter().enumerate() {
        if symbols.text(parameter.name) != Some(inputs.parameters[index].as_str()) {
            return Err("original formal name differs from prepared ABI".into());
        }
        view.default(index)?;
        match (
            parameter.default.as_ref(),
            inputs
                .parameter_defaults
                .get(index)
                .and_then(Option::as_deref),
        ) {
            (None, None) => {}
            (Some(expression), Some(text)) if symbolic_matches(expression, text, symbols) => {}
            _ => return Err("original default tokens differ from prepared ABI".into()),
        }
    }
    Ok(())
}
/// Borrowed invocation context only, not a parameter/semantic model or cache.
pub(crate) struct OriginalBodyInputs<'a, 'frontend> {
    pub frontend: &'a ColdFrontend,
    pub occurrence: &'a BodyOccurrence,
    pub header: &'a OriginalHeaderExpressionHandle<'frontend>,
    pub metadata: &'a ProcedureMetadata,
    pub inputs: &'a ProcedureInputs,
    pub symbols: &'a SymbolTable,
}
#[derive(Debug)]
pub(crate) enum OriginalBodyFailure {
    Admission(String),
    Lowering(Vec<dm_codegen_byond::LowerError>),
}
pub(crate) fn compile_body_original<R: Resolver>(
    context: OriginalBodyInputs<'_, '_>,
    view: dm_syntax::StatementView<'_>,
    host: &R,
    debug: Option<&dyn dm_codegen_byond::DebugSourceProvider>,
) -> Result<ResolverProc, OriginalBodyFailure> {
    validate_original_defaults(
        context.frontend,
        context.occurrence,
        context.header,
        context.metadata,
        context.inputs,
        context.symbols,
    )
    .map_err(OriginalBodyFailure::Admission)?;
    dm_codegen_byond::compile_statement_view_with_original_defaults(
        view,
        context.header.storage(),
        &context.frontend.expanded.text,
        context.inputs,
        context.symbols,
        host,
        debug,
    )
    .map_err(OriginalBodyFailure::Lowering)
}
pub(crate) fn compile_body_original_with_references<R: Resolver>(
    context: OriginalBodyInputs<'_, '_>,
    view: dm_syntax::StatementView<'_>,
    host: &R,
    debug: Option<&dyn dm_codegen_byond::DebugSourceProvider>,
) -> Result<(ResolverProc, dm_ir::SelectedReferences), OriginalBodyFailure> {
    validate_original_defaults(
        context.frontend,
        context.occurrence,
        context.header,
        context.metadata,
        context.inputs,
        context.symbols,
    )
    .map_err(OriginalBodyFailure::Admission)?;
    dm_codegen_byond::compile_statement_view_with_original_defaults_and_references_at(
        view,
        context.header.storage(),
        &context.frontend.expanded.text,
        context.inputs,
        context.symbols,
        host,
        debug,
        context.occurrence.expanded_span,
    )
    .map_err(OriginalBodyFailure::Lowering)
}
pub(crate) fn compile_lossless_body_original<R: Resolver>(
    context: OriginalBodyInputs<'_, '_>,
    body: &[Item],
    already_typed: bool,
    host: &R,
    debug: Option<&dyn dm_codegen_byond::DebugSourceProvider>,
) -> Result<ResolverProc, OriginalBodyFailure> {
    validate_original_defaults(
        context.frontend,
        context.occurrence,
        context.header,
        context.metadata,
        context.inputs,
        context.symbols,
    )
    .map_err(OriginalBodyFailure::Admission)?;
    let result = if already_typed {
        dm_codegen_byond::compile_preparsed_lossless_with_original_defaults(
            body,
            context.header.storage(),
            &context.frontend.expanded.text,
            context.inputs,
            context.symbols,
            host,
            debug,
        )
    } else {
        dm_codegen_byond::compile_simple_proc_with_original_defaults(
            body,
            context.header.storage(),
            &context.frontend.expanded.text,
            context.inputs,
            context.symbols,
            host,
            debug,
        )
    };
    result.map_err(OriginalBodyFailure::Lowering)
}
pub(crate) fn lower_helpers_original<R: Resolver>(
    context: HelperInputs<'_>,
    occurrence: &BodyOccurrence,
    header: &OriginalHeaderExpressionHandle<'_>,
    host: &R,
) -> Result<Vec<LoweredHelper>, HelperFailure> {
    validate_original_defaults(
        context.frontend,
        occurrence,
        header,
        context.metadata,
        context.inputs,
        context.symbols,
    )?;
    if crate::lowering::source_unit_identity(context.frontend, occurrence)?.identity
        != context.owner
    {
        return Err("original helper owner differs from captured occurrence".into());
    }
    let view = header.view()?;
    if context.parsed.header_span != header.storage().header()
        || context
            .frontend
            .expanded
            .text
            .get(context.parsed.header_span.range())
            != Some(context.parsed.header)
    {
        return Err("original helper header differs from current parser receipt".into());
    }
    let mut result = Vec::with_capacity(context.helpers.len());
    for helper in context.helpers {
        if helper.frame_parameters != context.inputs.parameters {
            return Err("argument source frame differs from owning procedure".into());
        }
        let native = context
            .metadata
            .signature
            .parameters
            .get(helper.argument)
            .and_then(|parameter| parameter.source_expression.as_ref())
            .ok_or("original helper metadata absent")?;
        if &helper.expression != native {
            return Err("helper expression differs from selected original metadata".into());
        }
        let root = view
            .in_source(helper.argument)?
            .ok_or("original helper source root unavailable")?;
        let expression = native
            .source_text(context.symbols)
            .ok_or("argument source expression spelling unavailable")?;
        // Diagnostic context only, NEVER parsed or retained as syntax.
        let diagnostic = format!("return {expression}");
        let mut frame = context.inputs.clone();
        frame.parameter_defaults.clear();
        frame.parameter_value_sources.clear();
        let mut code = visible_formals::compile_original(
            root,
            &diagnostic,
            helper.argument,
            context.metadata,
            &frame,
            context.symbols,
            host,
        )
        .map_err(|errors| {
            failure::lowered_original(
                context.frontend,
                context.owner,
                context.parsed.header_span,
                root.span,
                errors,
            )
        })?;
        code.procedure.argument_names.clear();
        code.procedure.argument_type_flags.clear();
        code.procedure.argument_value_sources.clear();
        let origin = context
            .frontend
            .location(root.span.start)
            .ok_or("original helper source origin missing")?;
        result.push(LoweredHelper {
            owner: context.owner,
            argument: u32::try_from(helper.argument)
                .map_err(|_| "source helper argument exceeds u32")?,
            code,
            debug_origins: DebugOrigins {
                entries: vec![DebugOrigin {
                    semantic_path: origin.semantic_path,
                    line: u32::try_from(origin.line)
                        .map_err(|_| "source helper line exceeds u32")?,
                }],
            },
            original_root: Some(root.span),
        });
    }
    Ok(result)
}

pub(crate) fn rebase_cached_helper_original(
    context: HelperInputs<'_>,
    parsed: &dm_tree::frontend::ParsedBody<'_>,
    argument: u32,
    code: ResolverProc,
) -> Result<LoweredHelper, String> {
    context
        .frontend
        .validate_parsed_body(parsed, parsed.occurrence())
        .map_err(|e| e.message)?;
    let header = parsed.share_header_expressions()?;
    validate_original_defaults(
        context.frontend,
        parsed.occurrence(),
        &header,
        context.metadata,
        context.inputs,
        context.symbols,
    )?;
    let helper = context
        .helpers
        .iter()
        .find(|helper| helper.argument == argument as usize)
        .ok_or("cached original helper argument absent")?;
    if helper.frame_parameters != context.inputs.parameters
        || !code.procedure.argument_names.is_empty()
        || !code.procedure.argument_type_flags.is_empty()
        || !code.procedure.argument_value_sources.is_empty()
    {
        return Err("cached original helper frame differs from preparation".into());
    }
    let symbolic = context
        .metadata
        .signature
        .parameters
        .get(argument as usize)
        .and_then(|p| p.source_expression.as_ref())
        .ok_or("original helper metadata absent")?;
    if &helper.expression != symbolic {
        return Err("cached original helper tokens differ".into());
    }
    visible_formals::validate_cached_prefix(
        argument,
        visible_formals::typed_prefix(&code.procedure.code)?,
        context.inputs.parameters.len(),
    )?;
    let view = header.view()?;
    let root = view
        .in_source(argument as usize)?
        .ok_or("current original helper root absent")?;
    let origin = context
        .frontend
        .location(root.span.start)
        .ok_or("current original helper origin unavailable")?;
    Ok(LoweredHelper {
        owner: context.owner,
        argument,
        code,
        original_root: Some(root.span),
        debug_origins: DebugOrigins {
            entries: vec![DebugOrigin {
                semantic_path: origin.semantic_path,
                line: u32::try_from(origin.line).map_err(|_| "original helper line exceeds u32")?,
            }],
        },
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{path::Path, sync::Arc};
    struct Source(dm_preprocess::AcquiredSource);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Err("original acquisition required".into())
        }
        fn acquired_source(
            &self,
            _: &Path,
        ) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
            Ok(Some(self.0.clone()))
        }
        fn source_acquisition(
            &self,
            _: &Path,
            text: &dm_preprocess::SourceText,
        ) -> Option<dm_preprocess::AcquiredSource> {
            self.0
                .lease()
                .source_text()
                .same_view(text)
                .then(|| self.0.clone())
        }
    }
    fn frontend(source: &str) -> ColdFrontend {
        let source = Source(dm_preprocess::AcquiredSource::from_original_bytes(
            source.as_bytes().to_vec(),
            (),
        ));
        dm_tree::frontend::build(
            Path::new("original-helpers.dme"),
            &source,
            &Default::default(),
            1,
        )
        .unwrap()
        .with_body_queries(Arc::new(crate::query_db::QueryDb::default()))
    }
    struct Host(bool);
    impl Resolver for Host {
        fn resolve(&self, q: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
            match q {
                dm_ir::ResolveQuery::GlobalProc(_) if self.0 => dm_ir::ResolvedMeaning::Missing,
                _ => dm_ir::ResolvedMeaning::Unsupported(q),
            }
        }
    }
    fn inputs(metadata: &ProcedureMetadata, symbols: &SymbolTable) -> ProcedureInputs {
        ProcedureInputs {
            parameters: metadata
                .signature
                .parameters
                .iter()
                .map(|p| symbols.text(p.name).unwrap().into())
                .collect(),
            parameter_defaults: metadata
                .signature
                .parameters
                .iter()
                .map(|p| p.default.as_ref().map(|e| e.source_text(symbols).unwrap()))
                .collect(),
            ..Default::default()
        }
    }
    fn owner() -> UnitIdentity {
        UnitIdentity {
            owner: dm_ir::SymbolId::of("/"),
            name: dm_ir::SymbolId::of("p"),
            namespace: crate::lowering::Namespace::Proc,
            occurrence: 0,
        }
    }
    #[test]
    fn actual_same_db_original_defaults_survive_abi_consumption_and_match_compatibility_words() {
        let frontend = frontend("/proc/p(x=1+2,y=x+4)\n    return y\n");
        let occurrence = &frontend.bodies[0];
        let arena = dm_tree::frontend::BodyArena::new_typed(
            &frontend,
            dm_codegen_byond::typed_statements_supported_for_capture,
        );
        let parsed = arena.take_parsed(occurrence).unwrap();
        let header = parsed.share_header_expressions().unwrap();
        let original = header.storage().clone();
        let metadata = frontend
            .snapshot
            .tree
            .member(occurrence.member)
            .unwrap()
            .metadata
            .procedure
            .as_deref()
            .unwrap();
        let symbols = frontend.snapshot.tree.symbols();
        let frame = inputs(metadata, symbols);
        let (_, statements) = parsed.into_parts();
        let statements = statements.unwrap();
        validate_original_defaults(&frontend, occurrence, &header, metadata, &frame, symbols)
            .unwrap();
        let expected = match dm_codegen_byond::compile_statement_view_with_resolver(
            statements.view(),
            &frame,
            symbols,
            &Host(false),
            None,
        ) {
            Ok(v) => v,
            Err(e) => panic!("compatibility {e:?}"),
        };
        let context = || OriginalBodyInputs {
            frontend: &frontend,
            occurrence,
            header: &header,
            metadata,
            inputs: &frame,
            symbols,
        };
        let actual = match compile_body_original(context(), statements.view(), &Host(false), None) {
            Ok(value) => value,
            Err(error) => panic!("original {error:?}"),
        };
        let (captured, references) =
            compile_body_original_with_references(context(), statements.view(), &Host(false), None)
                .unwrap();
        assert_eq!(captured.procedure, actual.procedure);
        assert!(
            references.unbound_selections > 0,
            "default references remain explicitly partial"
        );
        assert_eq!(actual.procedure, expected.procedure);
        let warm = frontend.parse_body(occurrence).unwrap();
        assert!(original.same_owner(warm.parameter_storage()));
        let mut wrong = frame.clone();
        wrong.parameter_defaults[0] = Some("99".into());
        assert!(validate_original_defaults(
            &frontend, occurrence, &header, metadata, &wrong, symbols
        )
        .is_err());
        let bad = OriginalBodyInputs {
            frontend: &frontend,
            occurrence,
            header: &header,
            metadata,
            inputs: &wrong,
            symbols,
        };
        assert!(matches!(
            compile_body_original(bad, statements.view(), &Host(false), None),
            Err(OriginalBodyFailure::Admission(_))
        ));
        let cloned = metadata.clone();
        assert!(validate_original_defaults(
            &frontend, occurrence, &header, &cloned, &frame, symbols
        )
        .is_err());
    }
    #[test]
    fn actual_original_helper_words_and_full_diagnostics_match_independent_compatibility_route() {
        for parameters in [
            "x,y in x+y",
            "x in y,y",
            "x in formerly_missing_helper()",
            "x,y in /*original*/(x+1)",
        ] {
            for padding in ["", "\n\n"] {
                let source = format!("{padding}/proc/p({parameters})\n    return 1\n");
                let frontend = frontend(&source);
                let occurrence = &frontend.bodies[0];
                let parsed = frontend.parse_body(occurrence).unwrap();
                let header = parsed.share_header_expressions().unwrap();
                let metadata = frontend
                    .snapshot
                    .tree
                    .member(occurrence.member)
                    .unwrap()
                    .metadata
                    .procedure
                    .as_deref()
                    .unwrap();
                let symbols = frontend.snapshot.tree.symbols();
                let frame = inputs(metadata, symbols);
                let helpers = metadata
                    .signature
                    .parameters
                    .iter()
                    .enumerate()
                    .filter_map(|(argument, p)| {
                        p.source_expression
                            .as_ref()
                            .map(|expression| ArgumentSourceHelper {
                                argument,
                                expression: expression.clone(),
                                frame_parameters: frame.parameters.clone(),
                            })
                    })
                    .collect::<Vec<_>>();
                let context = || HelperInputs {
                    frontend: &frontend,
                    parsed: parsed.item().into(),
                    metadata,
                    owner: owner(),
                    inputs: &frame,
                    helpers: &helpers,
                    symbols,
                };
                let old = lower_helpers(context(), &Host(true));
                let new = lower_helpers_original(context(), occurrence, &header, &Host(true));
                match (old, new) {
                    (Ok(old), Ok(new)) => {
                        assert_eq!(old.len(), new.len());
                        for (old, new) in old.iter().zip(&new) {
                            assert_eq!(old.code.procedure, new.code.procedure);
                            assert_eq!(old.debug_origins, new.debug_origins);
                            assert!(new.original_root.is_some());
                        }
                    }
                    (
                        Err(HelperFailure::Diagnostics(old)),
                        Err(HelperFailure::Diagnostics(new)),
                    ) => assert_eq!(format!("{new:?}"), format!("{old:?}")),
                    _ => panic!("original/compatibility helper outcome differs for {parameters}"),
                }
            }
        }
    }
}
