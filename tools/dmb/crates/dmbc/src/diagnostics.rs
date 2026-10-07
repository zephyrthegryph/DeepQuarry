//! CLI presentation of frontend diagnostics; semantic classification stays in
//! the frontend. Preserve encounter order rather than sorting by filename.

use dm_tree::frontend::{Diagnostic, DiagnosticKind};
use std::io::{self, Write};

/// DreamMaker's source diagnostic shape is `file:line:error: message`.
/// Unsupported native semantics and compiler faults remain visibly distinct
/// from errors in the user's source, even when they carry a source location.
pub fn write_diagnostics(output: &mut impl Write, diagnostics: &[Diagnostic]) -> io::Result<()> {
    for diagnostic in diagnostics {
        write_one(
            output,
            diagnostic.kind,
            diagnostic.location.as_ref(),
            &diagnostic.message,
        )?;
    }
    Ok(())
}

/// Lowering already returns diagnostics in authored encounter order. Present
/// them through the same source/error contract as frontend diagnostics.
pub fn write_lowering_diagnostics(
    output: &mut impl Write,
    diagnostics: &[crate::lowering::LoweringDiagnostic],
) -> io::Result<()> {
    for diagnostic in diagnostics {
        write_one(
            output,
            diagnostic.kind,
            Some(&diagnostic.origin),
            &diagnostic.message,
        )?;
    }
    Ok(())
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
