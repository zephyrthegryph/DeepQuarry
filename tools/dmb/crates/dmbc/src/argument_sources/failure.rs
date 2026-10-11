//! Preserve typed helper emitter failures while binding their synthetic syntax
//! coordinates to the exact current captured signature expression.
use super::*;
use crate::lowering::{LoweringDiagnostic, RelatedDiagnostic};
use dm_codegen_byond::{DiagnosticAnchor, LowerError, LowerErrorKind, LowerSpan};
use dm_tree::frontend::DiagnosticKind;

#[derive(Debug)]
pub enum HelperFailure {
    Unsupported(String),
    Diagnostics(Vec<LoweringDiagnostic>),
}
impl From<String> for HelperFailure {
    fn from(message: String) -> Self {
        Self::Unsupported(message)
    }
}
impl From<&str> for HelperFailure {
    fn from(message: &str) -> Self {
        Self::Unsupported(message.into())
    }
}

pub(super) fn lowered(
    frontend: &ColdFrontend,
    header: ProcedureHeader<'_>,
    metadata: &ProcedureMetadata,
    owner: UnitIdentity,
    absolute: usize,
    issued_origin: &dm_tree::frontend::SourceLocation,
    expression: &str,
    errors: Vec<LowerError>,
) -> HelperFailure {
    // Helper rendering is token-equivalent, not byte-equivalent to authored
    // whitespace/comments. Bind through the exact current token sequence.
    let synthetic = dm_syntax::lex(expression);
    let current = dm_syntax::lex(
        frontend
            .expanded
            .text
            .get(absolute..header.header_span.end)
            .unwrap_or(""),
    );
    let significant = |token: &&dm_syntax::Token| {
        !matches!(
            token.kind,
            TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
        )
    };
    let synthetic_tokens: Vec<_> = synthetic.tokens.iter().filter(significant).collect();
    let current_tokens: Vec<_> = current.tokens.iter().filter(significant).collect();
    let map_offset = |offset: usize| {
        let relative = offset.checked_sub(SYNTAX_PREFIX.len())?;
        let (index, token) = synthetic_tokens
            .iter()
            .enumerate()
            .find(|(_, token)| token.span.start <= relative && relative < token.span.end)
            .or_else(|| {
                synthetic_tokens
                    .iter()
                    .enumerate()
                    .find(|(_, token)| token.span.end == relative)
            })?;
        let actual = current_tokens.get(index)?;
        if token.kind != actual.kind || token.text != actual.text {
            return None;
        }
        absolute
            .checked_add(actual.span.start)?
            .checked_add(relative.checked_sub(token.span.start)?)
    };
    let map_span = |span: LowerSpan| {
        if span.start > span.end {
            return None;
        }
        Some(LowerSpan {
            start: map_offset(span.start)?,
            end: map_offset(span.end)?,
        })
    };
    let diagnostics = errors
        .into_iter()
        .map(|error| {
            let bind = || -> Option<(dm_tree::frontend::SourceLocation, Vec<RelatedDiagnostic>)> {
                let origin = match error.primary_anchor {
                    Some(DiagnosticAnchor::AtOffset(offset)) => {
                        frontend.location(map_offset(offset)?)?
                    }
                    Some(DiagnosticAnchor::LexerCursorAfterOffset(offset)) => {
                        frontend.diagnostic_cursor_location_after(map_offset(offset)?)?
                    }
                    Some(DiagnosticAnchor::UnresolvedCursorAtOffset(_)) => return None,
                    None => frontend.location(
                        error
                            .span
                            .and_then(map_span)
                            .map_or(absolute, |span| span.start),
                    )?,
                };
                let related =
                    error
                        .related
                        .iter()
                        .map(|note| {
                            let actual_parameter =
                                metadata.signature.parameters.iter().enumerate().any(
                                    |(index, _)| {
                                        parameter_span(header, metadata, index)
                                            .is_ok_and(|span| span == note.span)
                                    },
                                );
                            let span = if actual_parameter {
                                note.span
                            } else {
                                map_span(note.span)?
                            };
                            Some(RelatedDiagnostic {
                                origin: frontend.location(span.start)?,
                                message: note.message.clone(),
                            })
                        })
                        .collect::<Option<Vec<_>>>()?;
                Some((origin, related))
            };
            match bind() {
                Some((origin, related)) => LoweringDiagnostic {
                    related,
                    identity: Some(owner),
                    origin,
                    kind: match error.kind {
                        LowerErrorKind::SourceError => DiagnosticKind::SourceError,
                        LowerErrorKind::UnsupportedModel => DiagnosticKind::UnsupportedModel,
                        LowerErrorKind::Internal => DiagnosticKind::Internal,
                    },
                    message: if error.kind == LowerErrorKind::SourceError
                        || error.statement.is_empty()
                    {
                        error.reason
                    } else {
                        format!("{}: {}", error.statement, error.reason)
                    },
                },
                None => LoweringDiagnostic {
                    related: Vec::new(),
                    identity: Some(owner),
                    origin: issued_origin.clone(),
                    kind: DiagnosticKind::Internal,
                    message:
                        "argument source diagnostic mapping is not issued by the current signature"
                            .into(),
                },
            }
        })
        .collect();
    HelperFailure::Diagnostics(diagnostics)
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_codegen_byond::LowerRelated;

    struct Source<'a>(&'a str);
    impl dm_preprocess::SourceProvider for Source<'_> {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok(self.0.into())
        }
    }

    #[test]
    fn actual_argument_source_lowering_keeps_definite_missing_call_typed_at_current_header() {
        struct Host(bool);
        impl dm_ir::Resolver for Host {
            fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
                match query {
                    dm_ir::ResolveQuery::GlobalProc(_) if !self.0 => {
                        dm_ir::ResolvedMeaning::Missing
                    }
                    _ => dm_ir::ResolvedMeaning::Unsupported(query),
                }
            }
        }
        for padding in ["", "\n\n"] {
            let text =
                format!("{padding}/proc/probe(x in formerly_missing_helper())\n    return x\n");
            let frontend = dm_tree::frontend::build(
                std::path::Path::new("project.dme"),
                &Source(&text),
                &Default::default(),
                1,
            )
            .unwrap();
            let body = &frontend.bodies[0];
            let header = frontend.compact_body(body).unwrap();
            let member = frontend.snapshot.tree.member(body.member).unwrap();
            let metadata = member.metadata.procedure.as_ref().unwrap();
            let inputs = ProcedureInputs {
                parameters: vec!["x".into()],
                ..Default::default()
            };
            let helper = ArgumentSourceHelper {
                argument: 0,
                frame_parameters: inputs.parameters.clone(),
                expression: metadata.signature.parameters[0]
                    .source_expression
                    .clone()
                    .unwrap(),
            };
            let owner = UnitIdentity {
                owner: dm_ir::SymbolId::of("/"),
                name: dm_ir::SymbolId::of("probe"),
                namespace: crate::lowering::Namespace::Proc,
                occurrence: 0,
            };
            for opaque in [false, true] {
                let failure = lower_helpers(
                    HelperInputs {
                        frontend: &frontend,
                        parsed: header.into(),
                        metadata,
                        owner,
                        inputs: &inputs,
                        helpers: std::slice::from_ref(&helper),
                        symbols: frontend.snapshot.tree.symbols(),
                    },
                    &Host(opaque),
                )
                .err()
                .expect("invalid helper");
                let HelperFailure::Diagnostics(diagnostics) = failure else {
                    panic!("emitter failure lost its type")
                };
                assert_eq!(
                    diagnostics[0].kind,
                    if opaque {
                        DiagnosticKind::UnsupportedModel
                    } else {
                        DiagnosticKind::SourceError
                    }
                );
                assert_eq!(
                    diagnostics[0].origin,
                    frontend
                        .location(source_offset(header.into(), metadata, 0).unwrap())
                        .unwrap()
                );
                if !opaque {
                    assert_eq!(
                        diagnostics[0].message,
                        "formerly_missing_helper: undefined proc"
                    );
                }
            }
        }
    }

    #[test]
    fn helper_failure_preserves_kind_and_rebinds_current_signature_and_related_parameter() {
        for (padding, authored) in [("", "list(1, 2)"), ("\n\n", "list( 1, /* current */ 2)")] {
            let text = format!("{padding}/proc/probe(x in {authored})\n    return x\n");
            let frontend = dm_tree::frontend::build(
                std::path::Path::new("project.dme"),
                &Source(&text),
                &Default::default(),
                1,
            )
            .unwrap();
            let body = &frontend.bodies[0];
            let header = frontend.compact_body(body).unwrap();
            let member = frontend.snapshot.tree.member(body.member).unwrap();
            let metadata = member.metadata.procedure.as_ref().unwrap();
            let absolute = source_offset(header.into(), metadata, 0).unwrap();
            let origin = frontend.location(absolute).unwrap();
            let owner = UnitIdentity {
                owner: dm_ir::SymbolId::of("/"),
                name: dm_ir::SymbolId::of("probe"),
                namespace: crate::lowering::Namespace::Proc,
                occurrence: 0,
            };
            for kind in [
                LowerErrorKind::SourceError,
                LowerErrorKind::UnsupportedModel,
                LowerErrorKind::Internal,
            ] {
                let error = LowerError {
                    reason: "issued failure".into(),
                    kind,
                    primary_anchor: Some(DiagnosticAnchor::AtOffset(SYNTAX_PREFIX.len())),
                    related: vec![LowerRelated {
                        span: parameter_span(header.into(), metadata, 0).unwrap(),
                        message: "current parameter".into(),
                    }],
                    ..Default::default()
                };
                let HelperFailure::Diagnostics(diagnostics) = lowered(
                    &frontend,
                    header.into(),
                    metadata,
                    owner,
                    absolute,
                    &origin,
                    "list(1, 2)",
                    vec![error],
                ) else {
                    panic!("typed failure lost")
                };
                assert_eq!(diagnostics[0].origin, origin);
                assert_eq!(diagnostics[0].related.len(), 1);
                assert_eq!(diagnostics[0].related[0].origin.line, origin.line);
                assert_eq!(
                    diagnostics[0].kind,
                    match kind {
                        LowerErrorKind::SourceError => DiagnosticKind::SourceError,
                        LowerErrorKind::UnsupportedModel => DiagnosticKind::UnsupportedModel,
                        LowerErrorKind::Internal => DiagnosticKind::Internal,
                    }
                );
                assert_eq!(diagnostics[0].message, "issued failure");
            }
            let error = LowerError {
                reason: "nested expression failure".into(),
                kind: LowerErrorKind::SourceError,
                primary_anchor: Some(DiagnosticAnchor::AtOffset(
                    SYNTAX_PREFIX.len() + "list(1, 2)".find('2').unwrap(),
                )),
                ..Default::default()
            };
            let HelperFailure::Diagnostics(diagnostics) = lowered(
                &frontend,
                header.into(),
                metadata,
                owner,
                absolute,
                &origin,
                "list(1, 2)",
                vec![error],
            ) else {
                panic!("typed failure lost")
            };
            assert_eq!(
                diagnostics[0].origin,
                frontend
                    .location(absolute + authored.find('2').unwrap())
                    .unwrap()
            );
        }
    }
}
