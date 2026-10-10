//! Rebind secondary diagnostics only within the issued current procedure body.
use super::*;
pub(super) fn bind_related(
    frontend: &ColdFrontend,
    body: &BodyOccurrence,
    related: Vec<dm_codegen_byond::LowerRelated>,
    relative: bool,
) -> Option<Vec<RelatedDiagnostic>> {
    related
        .into_iter()
        .map(|note| {
            let base = if relative {
                body.expanded_span.start
            } else {
                0
            };
            let start = base.checked_add(note.span.start)?;
            let end = base.checked_add(note.span.end)?;
            if start > end || start < body.expanded_span.start || end > body.expanded_span.end {
                return None;
            }
            Some(RelatedDiagnostic {
                origin: frontend.location(start)?,
                message: note.message,
            })
        })
        .collect()
}

/// Fresh signature notes require the current parser-issued parameter span.
/// They remain outside the body-relative memo format and decline capture.
pub(super) fn bind_current_related(
    frontend: &ColdFrontend,
    body: &BodyOccurrence,
    parameters: Option<&crate::argument_sources::ParameterDiagnosticSource<'_>>,
    related: Vec<dm_codegen_byond::LowerRelated>,
) -> Option<Vec<RelatedDiagnostic>> {
    related
        .into_iter()
        .map(|note| {
            let inside_body = note.span.start <= note.span.end
                && note.span.start >= body.expanded_span.start
                && note.span.end <= body.expanded_span.end;
            if !inside_body && !parameters.is_some_and(|source| source.authenticates(&note.span)) {
                return None;
            }
            Some(RelatedDiagnostic {
                origin: frontend.location(note.span.start)?,
                message: note.message,
            })
        })
        .collect()
}
