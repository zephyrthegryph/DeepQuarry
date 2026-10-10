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
