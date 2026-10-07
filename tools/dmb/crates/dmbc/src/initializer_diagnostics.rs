//! Error origins for the initializer compiler's local write coordinates.
//! These spans contain ordinals, never expanded-source byte offsets. Only the
//! producer's aligned captured source sidecar can turn them into diagnostics.
use crate::lowering::LoweringDiagnostic;
use dm_codegen_byond::{LowerError, LowerErrorKind};
use dm_tree::frontend::{DiagnosticKind, SourceLocation};
use dm_tree::{
    frontend::ColdFrontend,
    initializers::{InitializerOriginKind, InitializerPlan},
};

#[derive(Debug)]
pub enum InitializerLoweringError {
    Unsupported(String),
    Invariant(String),
    Diagnostics(Vec<LoweringDiagnostic>),
}
impl std::fmt::Display for InitializerLoweringError {
    fn fmt(&self, output: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Unsupported(message) | Self::Invariant(message) => output.write_str(message),
            Self::Diagnostics(errors) => {
                write!(output, "{} initializer lowering diagnostics", errors.len())
            }
        }
    }
}
impl std::error::Error for InitializerLoweringError {}
impl From<String> for InitializerLoweringError {
    fn from(message: String) -> Self {
        // Unclassified legacy strings must not be labelled invalid user code.
        Self::Unsupported(message)
    }
}
impl From<&str> for InitializerLoweringError {
    fn from(message: &str) -> Self {
        Self::Unsupported(message.into())
    }
}

/// Resolve only the failing assignments. Declaration provenance is projected
/// through the captured expansion records; local write ordinals never enter
/// `ColdFrontend::location` as source offsets.
pub fn map_captured_lower_errors(
    errors: Vec<LowerError>,
    frontend: &ColdFrontend,
    plan: &InitializerPlan,
    write_ordinals: &[usize],
) -> Result<Vec<LoweringDiagnostic>, InitializerLoweringError> {
    errors
        .into_iter()
        .map(|error| {
            let local = error
                .span
                .ok_or_else(|| {
                    InitializerLoweringError::Unsupported(format!(
                        "initializer lowering has no assignment coordinate: {}",
                        error.reason
                    ))
                })?
                .start;
            let ordinal = *write_ordinals.get(local).ok_or_else(|| {
                InitializerLoweringError::Invariant(format!(
                    "initializer local write coordinate {local} is outside its unit"
                ))
            })?;
            let origin = plan.origins.get(ordinal).ok_or_else(|| {
                InitializerLoweringError::Invariant(format!(
                    "initializer source write coordinate {ordinal} is outside captured plan"
                ))
            })?;
            let location = match origin.kind {
                InitializerOriginKind::ProcedureStatic { expanded_span, .. } => {
                    frontend.location(expanded_span.start)
                }
                InitializerOriginKind::Declaration(_) => {
                    let source = frontend
                        .source(origin.provenance.span.file)
                        .ok_or_else(|| {
                            InitializerLoweringError::Invariant(
                                "initializer source file absent".into(),
                            )
                        })?;
                    frontend.expanded.origins.iter().find_map(|expanded| {
                        if expanded.source_span.start != origin.provenance.span.start as usize
                            || expanded.source_span.end != origin.provenance.span.end as usize
                            || expanded.origin.path.as_ref() != source.path.as_ref()
                            || frontend.plan.regions[expanded.region].occurrence
                                != origin.provenance.include_occurrence as usize
                        {
                            return None;
                        }
                        let location = frontend.location(expanded.output_span.start)?;
                        let definitions = location
                            .macro_expansions
                            .iter()
                            .filter_map(|expansion| expansion.definition.as_ref())
                            .filter_map(|definition| {
                                let file = frontend
                                    .files
                                    .iter()
                                    .find(|file| file.path.as_ref() == definition.path.as_ref())?;
                                dm_ir::Span::new(
                                    file.id,
                                    u32::try_from(definition.source_span.start).ok()?,
                                    u32::try_from(definition.source_span.end).ok()?,
                                )
                                .ok()
                            })
                            .collect::<Vec<_>>();
                        (definitions.as_slice() == origin.provenance.expansion_stack.as_ref())
                            .then_some(location)
                    })
                }
            }
            .ok_or_else(|| {
                InitializerLoweringError::Invariant(
                    "initializer diagnostic has no matching captured source projection".into(),
                )
            })?;
            // The generic mapper sees a one-entry sidecar; rebasing the local
            // coordinate is explicit, after the original ordinal was validated.
            let mut rebound = error;
            rebound.span = Some(dm_codegen_byond::LowerSpan { start: 0, end: 0 });
            Ok(map_lower_errors(vec![rebound], &[location])?.remove(0))
        })
        .collect()
}

/// `sources[i]` is the exact captured location of assignment `i` in this one
/// grouped VM unit. No source sorting or filesystem lookup occurs here.
pub fn map_lower_errors(
    errors: Vec<LowerError>,
    sources: &[SourceLocation],
) -> Result<Vec<LoweringDiagnostic>, InitializerLoweringError> {
    errors.into_iter().map(|error| {
        let ordinal = error.span.ok_or_else(|| InitializerLoweringError::Unsupported(
            format!("initializer lowering has no assignment coordinate: {}", error.reason)
        ))?.start;
        let origin = sources.get(ordinal).ok_or_else(|| InitializerLoweringError::Invariant(
            format!("initializer assignment coordinate {ordinal} exceeds captured sidecar length {}", sources.len())
        ))?.clone();
        Ok(LoweringDiagnostic {
            kind: match error.kind {
                LowerErrorKind::SourceError => DiagnosticKind::SourceError,
                LowerErrorKind::UnsupportedModel => DiagnosticKind::UnsupportedModel,
                LowerErrorKind::Internal => DiagnosticKind::Internal,
            },
            identity: None,
            origin,
            message: if error.statement.is_empty() { error.reason }
                else { format!("{}: {}", error.statement, error.reason) },
        })
    }).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_codegen_byond::LowerSpan;
    use std::{path::PathBuf, sync::Arc};
    fn source(path: &str, line: usize, occurrence: usize) -> SourceLocation {
        SourceLocation {
            span: dm_ir::Span::new(dm_ir::FileId(occurrence as u32), 100, 120).unwrap(),
            path: Arc::new(PathBuf::from(path)),
            semantic_path: path.into(),
            line,
            encounter_ordinal: occurrence,
            include_occurrence: occurrence,
            include_chain: [0, occurrence].into(),
            macro_expansions: Arc::new(Vec::new()),
        }
    }
    #[test]
    fn local_write_coordinates_select_exact_captured_sources() {
        let sources = [source("class.dm", 90, 4), source("static.dm", 12, 9)];
        let errors = vec![
            LowerError {
                reason: "unsupported meaning".into(),
                span: Some(LowerSpan { start: 1, end: 1 }),
                ..Default::default()
            },
            LowerError {
                reason: "bad label".into(),
                kind: LowerErrorKind::SourceError,
                span: Some(LowerSpan { start: 0, end: 0 }),
                ..Default::default()
            },
        ];
        let diagnostics = map_lower_errors(errors, &sources).unwrap();
        assert_eq!(diagnostics[0].origin.semantic_path.as_ref(), "static.dm");
        assert_eq!(diagnostics[0].origin.line, 12);
        assert_eq!(diagnostics[0].origin.include_occurrence, 9);
        assert_eq!(diagnostics[0].kind, DiagnosticKind::UnsupportedModel);
        assert_eq!(diagnostics[1].origin.line, 90);
        assert_eq!(diagnostics[1].kind, DiagnosticKind::SourceError);
    }
    #[test]
    fn captured_plan_maps_declaration_and_static_ordinals_to_included_lines() {
        struct Included;
        impl dm_preprocess::SourceProvider for Included {
            fn read(&self, path: &std::path::Path) -> Result<String, String> {
                match path.file_name().and_then(|name| name.to_str()) {
                    Some("project.dme") => Ok("#include \"body.dm\"\n".into()),
                    Some("body.dm") => Ok("var/one = 1\n/proc/p()\n    var/static/counter = 2\n    return counter\nvar/two = 3\n".into()),
                    _ => Err("unexpected file".into()),
                }
            }
        }
        let frontend = dm_tree::frontend::build(
            std::path::Path::new("project.dme"),
            &Included,
            &Default::default(),
            1,
        )
        .unwrap();
        let startup = crate::startup::capture(&frontend).unwrap();
        assert_eq!(startup.plan().writes.len(), 3);
        let errors = [1, 0, 2]
            .into_iter()
            .map(|ordinal| LowerError {
                reason: "unsupported assignment".into(),
                span: Some(LowerSpan {
                    start: ordinal,
                    end: ordinal,
                }),
                ..Default::default()
            })
            .collect();
        let diagnostics =
            map_captured_lower_errors(errors, &frontend, startup.plan(), &[0, 1, 2]).unwrap();
        assert_eq!(
            diagnostics
                .iter()
                .map(|error| error.origin.line)
                .collect::<Vec<_>>(),
            [3, 1, 5]
        );
        assert!(diagnostics
            .iter()
            .all(|error| error.origin.semantic_path.ends_with("body.dm")));
    }
    #[test]
    fn missing_or_invalid_coordinates_never_fall_back_to_first_write() {
        assert!(matches!(
            map_lower_errors(vec![LowerError::default()], &[source("a.dm", 2, 1)]),
            Err(InitializerLoweringError::Unsupported(_))
        ));
        assert!(matches!(
            map_lower_errors(
                vec![LowerError {
                    span: Some(LowerSpan { start: 9, end: 9 }),
                    ..Default::default()
                }],
                &[source("a.dm", 2, 1)]
            ),
            Err(InitializerLoweringError::Invariant(_))
        ));
    }
}
