//! Source-error continuation uses the common body producer and cannot publish.
use super::{initializer_lowering_error, ColdError, LoweringDiagnostic};
use crate::initializer_diagnostics::InitializerLoweringError;
use dm_tree::frontend::DiagnosticKind;

pub(super) fn collect(
    error: InitializerLoweringError,
    lower_bodies: impl FnOnce() -> Vec<LoweringDiagnostic>,
) -> ColdError {
    match error {
        InitializerLoweringError::Diagnostics(mut diagnostics)
            if !diagnostics.is_empty()
                && diagnostics
                    .iter()
                    .all(|error| error.kind == DiagnosticKind::SourceError) =>
        {
            // Preserve initializer ordering and actual current producer origins.
            // Unsupported/internal body results do not become source diagnostics.
            diagnostics.extend(
                lower_bodies()
                    .into_iter()
                    .filter(|error| error.kind == DiagnosticKind::SourceError),
            );
            ColdError::Lowering(diagnostics)
        }
        other => initializer_lowering_error(other),
    }
}
#[cfg(test)]
mod tests;
