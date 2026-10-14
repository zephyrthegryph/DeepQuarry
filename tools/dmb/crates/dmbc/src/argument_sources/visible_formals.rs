//! Later formal rejection from the same checked lexical selections as codegen.
use super::*;
use dm_codegen_byond::{LowerError, LowerErrorKind, LowerSpan};

pub(super) fn typed_prefix(code: &dm_codegen_byond::SymbolicProc) -> Result<u32, String> {
    use dm_codegen_byond::{Item, VariableWord as V, Word};
    fn variable(value: &V) -> Result<u32, String> {
        match value {
            V::Arg(index) => index
                .checked_add(1)
                .ok_or_else(|| "cached helper argument index overflow".into()),
            V::Initial(inner) | V::IsSaved(inner) => variable(inner),
            V::SetCache(a, b) => Ok(variable(a)?.max(variable(b)?)),
            V::Local(_)
            | V::Src
            | V::Usr
            | V::World
            | V::Args
            | V::Caller
            | V::Callee
            | V::Null
            | V::Dot
            | V::Cache
            | V::CacheKey
            | V::CacheIndex
            | V::Field(_)
            | V::StaticField(_)
            | V::Global(_)
            | V::DynamicProc(_)
            | V::StaticProc(_)
            | V::StaticVerb(_)
            | V::DynamicVerb(_) => Ok(0),
        }
    }
    let mut prefix = 0;
    for item in &code.items {
        if let Item::Instruction(instruction) = item {
            for word in &instruction.operands {
                if let Word::Variable(value) = word {
                    prefix = prefix.max(variable(value)?);
                }
            }
        }
    }
    Ok(prefix)
}

pub(super) fn validate_cached_prefix(
    argument: u32,
    prefix: u32,
    frame_len: usize,
) -> Result<(), String> {
    let ordinal = usize::try_from(argument).map_err(|_| "cached helper ordinal exceeds usize")?;
    let visible = argument
        .checked_add(1)
        .ok_or("cached helper ordinal overflow")?;
    if ordinal >= frame_len
        || prefix > visible
        || usize::try_from(prefix).map_err(|_| "cached helper prefix exceeds usize")? > frame_len
    {
        return Err("cached helper reads a later formal or differs from current frame".into());
    }
    Ok(())
}

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
    use dm_ir::SymbolId;
    #[test]
    fn cached_typed_and_restored_argument_receipts_preserve_visibility_bounds() {
        use dm_codegen_byond::{Instruction, Item, SymbolicProc, VariableWord as V, Word};
        for (variable, prefix, accepted) in [
            (V::Arg(0), 1, true),
            (V::Arg(1), 2, true),
            (V::Arg(2), 3, false),
            (V::Args, 0, true),
            (V::Initial(Box::new(V::Arg(2))), 3, false),
        ] {
            let code = SymbolicProc {
                items: vec![Item::Instruction(Instruction {
                    opcode: byond_dmb::bytecode::opcode::GET_VAR,
                    operands: vec![Word::Variable(variable)],
                })],
            };
            assert_eq!(typed_prefix(&code).unwrap(), prefix);
            assert_eq!(validate_cached_prefix(1, prefix, 3).is_ok(), accepted);
            let frozen = dm_codegen_byond::freeze_proc(&code).unwrap();
            let restored = dm_codegen_byond::FrozenProc::restore(
                frozen.code().clone(),
                frozen.labels().to_vec(),
            )
            .unwrap();
            for fact in [
                frozen.referenced_argument_prefix(),
                restored.referenced_argument_prefix(),
            ] {
                assert_eq!(fact, prefix);
                assert_eq!(validate_cached_prefix(1, fact, 3).is_ok(), accepted);
            }
        }
        assert!(validate_cached_prefix(u32::MAX, 0, usize::MAX).is_err());
        assert!(validate_cached_prefix(3, 0, 3).is_err());
    }
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
