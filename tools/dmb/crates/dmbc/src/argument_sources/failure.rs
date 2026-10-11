//! Preserve typed helper emitter failures while binding their synthetic syntax
//! coordinates to the exact current captured signature expression.
use super::*;
use crate::lowering::{LoweringDiagnostic, RelatedDiagnostic};
use dm_tree::frontend::DiagnosticKind;
use dm_codegen_byond::{DiagnosticAnchor, LowerError, LowerErrorKind, LowerSpan};

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
    let map_offset = |offset: usize| {
        offset
            .checked_sub(SYNTAX_PREFIX.len())
            .filter(|offset| *offset <= expression.len())
            .and_then(|offset| absolute.checked_add(offset))
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
    fn helper_failure_preserves_kind_and_rebinds_current_signature_and_related_parameter() {
        for padding in ["", "\n\n"] {
            let text = format!("{padding}/proc/probe(x in list(1, 2))\n    return x\n");
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
        }
    }
}
