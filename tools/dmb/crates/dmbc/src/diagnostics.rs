//! CLI presentation of frontend diagnostics; semantic classification stays in
//! the frontend. Preserve encounter order rather than sorting by filename.

use dm_tree::frontend::{Diagnostic, DiagnosticKind};
use std::io::{self, Write};

/// DreamMaker's source diagnostic shape is `file:line:error: message`.
/// Unsupported native semantics and compiler faults remain visibly distinct
/// from errors in the user's source, even when they carry a source location.
pub fn write_diagnostics(output: &mut impl Write, diagnostics: &[Diagnostic]) -> io::Result<()> {
    for diagnostic in diagnostics {
        if let Some(location) = &diagnostic.location {
            write!(output, "{}:{}:", location.semantic_path, location.line)?;
        }
        let classification = match diagnostic.kind {
            DiagnosticKind::SourceError => "error",
            DiagnosticKind::UnsupportedModel => "native unsupported",
            DiagnosticKind::Internal => "internal compiler error",
        };
        writeln!(output, "{classification}: {}", diagnostic.message)?;
    }
    Ok(())
}
