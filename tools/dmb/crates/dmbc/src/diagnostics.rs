//! CLI presentation of frontend diagnostics; semantic classification stays in
//! the frontend. Preserve encounter order rather than sorting by filename.

use dm_tree::frontend::{Diagnostic, DiagnosticKind};
use std::io::{self, Write};

#[path = "diagnostic_failure.rs"]
mod failure;
pub use failure::failure_kind;

/// DreamMaker's source diagnostic shape is `file:line:error: message`.
/// Unsupported native semantics and compiler faults remain visibly distinct
/// from errors in the user's source, even when they carry a source location.
pub fn write_diagnostics(output: &mut impl Write, diagnostics: &[Diagnostic]) -> io::Result<()> {
    let mut output = io::BufWriter::with_capacity(64 * 1024, output);
    for diagnostic in diagnostics {
        write_one(
            &mut output,
            diagnostic.kind,
            diagnostic.location.as_ref(),
            &diagnostic.message,
        )?;
    }
    output.flush()
}

/// Lowering already returns diagnostics in authored encounter order. Present
/// them through the same source/error contract as frontend diagnostics.
pub fn write_lowering_diagnostics(
    output: &mut impl Write,
    diagnostics: &[crate::lowering::LoweringDiagnostic],
) -> io::Result<()> {
    let mut output = io::BufWriter::with_capacity(64 * 1024, output);
    for diagnostic in diagnostics {
        write_one(
            &mut output,
            diagnostic.kind,
            Some(&diagnostic.origin),
            &diagnostic.message,
        )?;
        for note in &diagnostic.related {
            writeln!(
                output,
                "{}:{}:error: {}",
                note.origin.semantic_path, note.origin.line, note.message
            )?;
        }
    }
    output.flush()
}

fn write_one(
    output: &mut impl Write,
    kind: DiagnosticKind,
    location: Option<&dm_tree::frontend::SourceLocation>,
    message: &str,
) -> io::Result<()> {
    if let Some(location) = location {
        write!(output, "{}:{}:", location.semantic_path, location.line)?;
    }
    let classification = match kind {
        DiagnosticKind::SourceError => "error",
        DiagnosticKind::UnsupportedModel => "native unsupported",
        DiagnosticKind::Internal => "internal compiler error",
    };
    writeln!(output, "{classification}: {message}")
}

/// Preserve the shared current source presentation and typed CLI/daemon status.
pub fn report_source_error(
    diagnostic: crate::lowering::LoweringDiagnostic,
) -> io::Result<crate::request_failure::RequestFailure> {
    if diagnostic.kind != DiagnosticKind::SourceError {
        return Ok(crate::request_failure::RequestFailure::internal(
            "projection source error has an invalid classification",
        ));
    }
    write_lowering_diagnostics(&mut crate::daemon::stderr_writer(), &[diagnostic])?;
    Ok(crate::request_failure::RequestFailure::source(
        "native compilation rejected invalid source",
    ))
}
