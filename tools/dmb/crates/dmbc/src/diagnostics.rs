//! CLI presentation of frontend diagnostics; semantic classification stays in
//! the frontend. Preserve encounter order rather than sorting by filename.

use dm_tree::frontend::{Diagnostic, DiagnosticKind};
#[path="diagnostics_original_preprocess.rs"]mod original_preprocess;
pub use original_preprocess::write_original_preprocess_notices;
pub(crate) use original_preprocess::write_named_image_dir_notices;
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
    // `path:line:error: ...`: the path keeps DreamMaker's separator.
    match diagnostic.split_once(':') {
        Some((path, rest)) => writeln!(output, "{}:{rest}", display_path(path))?,
        None => writeln!(output, "{diagnostic}")?,
    }
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
                display_path(&note.origin.semantic_path), note.origin.line, note.message
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
    let classification = match kind {
        DiagnosticKind::SourceError | DiagnosticKind::OriginalFatalInput{..} | DiagnosticKind::OriginalFatalParameter{..} | DiagnosticKind::OriginalFatalDeclaration{..} => "error",
        DiagnosticKind::OriginalFormalNotice{notice,..} => match notice.registration().1{dm_tree::OriginalFormalNoticeLevel::Error=>"error",dm_tree::OriginalFormalNoticeLevel::Warning=>"warning",dm_tree::OriginalFormalNoticeLevel::Hint=>"hint"},
        DiagnosticKind::UnsupportedModel => "native unsupported",
        DiagnosticKind::Internal => "internal compiler error",
    };
    // A message may move to a later line of its statement and may carry
    // further same-line diagnostics (`dm_codegen_byond` syntax failures).
    let (shift, message) = match message
        .strip_prefix('\u{1}')
        .and_then(|rest| rest.split_once('\u{1}'))
        .and_then(|(shift, rest)| Some((shift.strip_prefix('+')?.parse::<usize>().ok()?, rest)))
    {
        Some((shift, rest)) => (shift, rest),
        None => (0, message),
    };
    for line in message.split('\n') {
        if let Some(location) = location {
            write!(
                output,
                "{}:{}:",
                display_path(&location.semantic_path),
                location.line + shift
            )?;
        }
        match kind {
            DiagnosticKind::OriginalFormalNotice{notice,..}=>match notice.registration().1{
                dm_tree::OriginalFormalNoticeLevel::Error=>count_error(),
                dm_tree::OriginalFormalNoticeLevel::Warning=>count_warning(notice.registration().0),
                dm_tree::OriginalFormalNoticeLevel::Hint=>(),
            },
            _=>count_error(),
        }
        // DreamMaker prints no space before a goto label diagnostic.
        if kind == DiagnosticKind::SourceError && line.starts_with("goto ") {
            writeln!(output, "{classification}:{line}")?;
        } else {
            writeln!(output, "{classification}: {line}")?;
        }
    }
    Ok(())
}

/// Paths as DreamMaker prints them: with the host's separator.
pub fn display_path(path: &str) -> std::borrow::Cow<'_, str> {
    if cfg!(windows) && path.contains('/') {
        std::borrow::Cow::Owned(path.replace('/', "\\"))
    } else {
        std::borrow::Cow::Borrowed(path)
    }
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

/// Warnings DreamMaker still prints when compilation stops with errors.
pub fn write_local_warnings(
    output: &mut impl Write,
    frontend: &dm_tree::frontend::ColdFrontend,
) -> io::Result<()> {
    match crate::local_warnings::capture(frontend) {
        Ok(warnings) => crate::initializer_policy::warnings::write_warnings(output, &warnings),
        Err(_) => Ok(()),
    }
}

/// Reclassify frontend failures DreamMaker reports as source errors, at the
/// authored line DreamMaker names. Reads the failing file only on this path.
pub fn refine(diagnostics: &mut [Diagnostic]) {
    for diagnostic in diagnostics {
        let Some(location) = diagnostic.location.as_mut() else {
            continue;
        };
        // `set frobnicate = 1`: DreamMaker's settings are a closed set.
        let (needle, message) = if let Some(name) = diagnostic
            .message
            .strip_prefix("unknown procedure setting: ")
        {
            (format!("set {name}"), format!("{name}: undefined var"))
        } else if diagnostic.message.ends_with(": invalid parent type") {
            ("parent_type".to_owned(), diagnostic.message.clone())
        } else {
            continue;
        };
        if let Ok(text) = std::fs::read_to_string(location.path.as_ref()) {
            if let Some(offset) = text
                .lines()
                .skip(location.line.saturating_sub(1))
                .take(64)
                .position(|line| line.trim_start().starts_with(&needle))
            {
                location.line += offset;
            }
        }
        diagnostic.kind = DiagnosticKind::SourceError;
        diagnostic.message = message;
    }
}

#[cfg(test)]
#[path="diagnostics_original_fatal_tests.rs"]
mod original_fatal_tests;

/// The native public error borrows its actual funded source message from the
/// returned report. No Vec/String extraction can outlive the report credit.
struct RetainedPreparationFailure{report:dm_tree::frontend::FrontendDiagnostics,classification:crate::request_failure::RequestFailure,source_message:bool,fallback:&'static str,_credit:dm_syntax::SettingRootLease}
impl std::fmt::Debug for RetainedPreparationFailure{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("RetainedPreparationFailure").field("report",&self.report).field("classification",&self.classification).finish()}}
impl RetainedPreparationFailure{fn actual_message(&self)->&str{if self.source_message&&self.classification.kind==crate::request_failure::FailureKind::Source{if let Some(row)=self.report.iter().find(|row|row.kind.is_source_error()){return &row.message}}self.fallback}}
impl std::fmt::Display for RetainedPreparationFailure{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{self.actual_message().fmt(f)}}
impl std::error::Error for RetainedPreparationFailure{fn source(&self)->Option<&(dyn std::error::Error+'static)>{Some(&self.classification)}}
pub fn retained_preparation_failure(report:dm_tree::frontend::FrontendDiagnostics,kind:crate::request_failure::FailureKind,source_message:bool,fallback:&'static str,host:&dyn dm_tree::frontend::SettingExpressionQueries)->Result<Box<dyn std::error::Error+Send+Sync>,dm_tree::frontend::BodySyntaxFailure>{
 let mut credit=None;host.with_declaration_admission(&mut|a|{if credit.is_some()||!report.is_admitted_by(a){return Err(dm_tree::frontend::BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"returned diagnostic report belongs to another actual native output domain")))}let actual=a.reserve(std::mem::size_of::<RetainedPreparationFailure>()).map_err(|error|dm_tree::frontend::BodySyntaxFailure::Operational(a.take_operational_error().unwrap_or(error)))?;credit=Some(actual);Ok(())})?;
 let credit=credit.ok_or_else(||dm_tree::frontend::BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"actual terminal report admission callback was omitted")))?;
 Ok(Box::new(RetainedPreparationFailure{report,classification:crate::request_failure::RequestFailure{kind,message:String::new()},source_message,fallback,_credit:credit}))
}

/// Borrow only the concrete retained public failure's actual display fields.
/// Other error types keep their existing presentation/transport path.
pub(crate) fn retained_preparation_failure_parts<'a>(error:&'a(dyn std::error::Error+'static))->Option<(crate::request_failure::FailureKind,&'a str)>{let actual=error.downcast_ref::<RetainedPreparationFailure>()?;Some((actual.classification.kind,actual.actual_message()))}
