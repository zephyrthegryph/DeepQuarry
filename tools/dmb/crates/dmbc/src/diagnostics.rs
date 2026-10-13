//! CLI presentation of frontend diagnostics; semantic classification stays in
//! the frontend. Preserve encounter order rather than sorting by filename.

use dm_tree::frontend::{Diagnostic, DiagnosticKind};
use std::cell::RefCell;
use std::io::{self, Write};

/// DreamMaker build policy for warnings, applied by the native compiler.
/// `ignored` codes are still printed but never fail a warnings-as-errors build
/// (the same contract as the build tool's DreamMaker check).
#[derive(Clone, Debug, Default, Eq, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct WarningPolicy {
    #[serde(default)]
    pub as_errors: bool,
    #[serde(default)]
    pub ignored: Vec<String>,
}

/// Diagnostics issued by the current request, for DreamMaker's summary line.
#[derive(Clone, Debug, Default)]
pub struct Tally {
    pub errors: usize,
    pub warnings: usize,
    /// Warnings not covered by an ignored code.
    pub failing_warnings: usize,
    policy: WarningPolicy,
}

thread_local! {
    // Request output is bound per thread (`daemon::stderr_writer`), so the
    // tally of what that output reported is per thread too.
    static TALLY: RefCell<Tally> = RefCell::new(Tally::default());
}

/// Start counting for one build attempt.
pub fn begin(policy: WarningPolicy) {
    TALLY.with(|tally| {
        *tally.borrow_mut() = Tally {
            policy,
            ..Tally::default()
        }
    });
}
pub fn tally() -> Tally {
    TALLY.with(|tally| tally.borrow().clone())
}
fn count_error() {
    TALLY.with(|tally| tally.borrow_mut().errors += 1);
}
/// Count one printed warning; `code` is the parenthesized warning code.
pub fn count_warning(code: Option<&str>) {
    TALLY.with(|tally| {
        let mut tally = tally.borrow_mut();
        tally.warnings += 1;
        let ignored = code.is_some_and(|code| tally.policy.ignored.iter().any(|ignored| ignored == code));
        if !ignored {
            tally.failing_warnings += 1;
        }
    });
}
/// Count a rendered `file:line:warning (code): ...` line replayed from a record.
pub fn count_rendered_warning(line: &str) {
    let code = line
        .split_once("warning (")
        .and_then(|(_, rest)| rest.split_once(')'))
        .map(|(code, _)| code);
    count_warning(code);
}
impl Tally {
    /// Whether the policy turns this build's warnings into a failure.
    pub fn warnings_fail(&self) -> bool {
        self.policy.as_errors && self.failing_warnings > 0
    }
}
/// Marks a confirmed `file:line:error: ...` source diagnostic carried through
/// a string-typed stage error, so it is reported as the author's error.
pub const CARRIED_SOURCE_ERROR: &str = "\u{1}dm-source-error\u{1}";

/// Report a carried source diagnostic; false when `message` is not one.
pub fn write_carried_source_error(output: &mut impl Write, message: &str) -> io::Result<bool> {
    let Some(diagnostic) = message.strip_prefix(CARRIED_SOURCE_ERROR) else {
        return Ok(false);
    };
    count_error();
    writeln!(output, "{diagnostic}")?;
    Ok(true)
}

/// DreamMaker's closing line, `NAME.dmb - 1 error, 2 warnings`.
pub fn summary_line(output_project: &std::path::Path, errors: usize, warnings: usize) -> String {
    let name = output_project
        .file_stem()
        .map(|stem| stem.to_string_lossy().into_owned())
        .unwrap_or_else(|| "output".into());
    let plural = |count: usize, word: &str| {
        format!("{count} {word}{}", if count == 1 { "" } else { "s" })
    };
    format!("{name}.dmb - {}, {}", plural(errors, "error"), plural(warnings, "warning"))
}

#[path = "diagnostic_failure.rs"]
mod failure;
pub use failure::failure_kind;

/// DreamMaker's source diagnostic shape is `file:line:error: message`.
/// Unsupported native semantics and compiler faults remain visibly distinct
/// from errors in the user's source, even when they carry a source location.
pub fn write_diagnostics(output: &mut impl Write, diagnostics: &[Diagnostic]) -> io::Result<()> {
    let mut output = io::BufWriter::with_capacity(64 * 1024, output);
    let mut previous: Option<&Diagnostic> = None;
    for diagnostic in diagnostics {
        // One lexical failure can surface from both expansion and parsing.
        let repeated = previous.is_some_and(|previous| {
            previous.kind == diagnostic.kind
                && previous.message == diagnostic.message
                && previous.location.as_ref().map(|at| (&at.semantic_path, at.line))
                    == diagnostic.location.as_ref().map(|at| (&at.semantic_path, at.line))
        });
        previous = Some(diagnostic);
        if repeated {
            continue;
        }
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
            count_error();
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
    count_error();
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
