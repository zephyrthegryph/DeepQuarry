//! DreamMaker-style closing summary and warning policy for compile requests.
use crate as dmbc;
use crate::request::BuildOutcome;
use std::io::Write;

/// DreamMaker's closing summary, and the warnings-as-errors policy. A
/// cancelled request reports nothing; a failure always counts one error.
pub(super) fn finish_report(
    project: &std::path::Path,
    result: Result<BuildOutcome, Box<dyn std::error::Error>>,
) -> Result<BuildOutcome, Box<dyn std::error::Error>> {
    let tally = dmbc::diagnostics::tally();
    let failed = match &result {
        Ok(_) => false,
        Err(error) => {
            if dmbc::request_failure::classify(error.as_ref())
                == dmbc::request_failure::FailureKind::Cancelled
            {
                return result;
            }
            true
        }
    };
    let warnings_fail = !failed && tally.warnings_fail();
    let mut output = dmbc::daemon::stderr_writer();
    if warnings_fail {
        writeln!(
            output,
            "error: {} warning{} treated as errors (--warnings-as-errors)",
            tally.failing_warnings,
            if tally.failing_warnings == 1 { "" } else { "s" }
        )?;
    }
    let errors = if failed { tally.errors.max(1) } else { tally.errors };
    writeln!(output, "{}", dmbc::diagnostics::summary_line(project, errors, tally.warnings))?;
    if warnings_fail {
        return Err(dmbc::request_failure::RequestFailure::source("").into());
    }
    result
}
