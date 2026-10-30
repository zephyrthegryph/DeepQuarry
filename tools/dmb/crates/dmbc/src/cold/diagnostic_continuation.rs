//! Source-error continuation uses the common body producer and cannot publish.
use super::{initializer_lowering_error, ColdError, LoweringDiagnostic};
use crate::initializer_diagnostics::InitializerLoweringError;
use dm_tree::frontend::DiagnosticKind;

pub(super) fn collect(
    error: InitializerLoweringError,
    lower_bodies: impl FnOnce() -> Vec<LoweringDiagnostic>,
) -> ColdError {
    match collect_with(error,||Ok::<_,std::convert::Infallible>(lower_bodies())){
        Ok(value)=>value,Err(never)=>match never {},
    }
}
pub(super) fn collect_checked(
    error: InitializerLoweringError,
    lower_bodies: impl FnOnce() -> std::io::Result<Vec<LoweringDiagnostic>>,
) -> ColdError {
    collect_with(error,lower_bodies).unwrap_or_else(ColdError::Operational)
}
fn collect_with<E>(
    error: InitializerLoweringError,
    lower_bodies: impl FnOnce() -> Result<Vec<LoweringDiagnostic>,E>,
) -> Result<ColdError,E> {
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
                lower_bodies()?
                    .into_iter()
                    .filter(|error| error.kind == DiagnosticKind::SourceError),
            );
            Ok(ColdError::Lowering(diagnostics))
        }
        other => Ok(initializer_lowering_error(other)),
    }
}
#[cfg(test)]
mod tests;
