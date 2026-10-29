//! Exact `set_has_no_effect` policy over authenticated primary syntax.
//! Adapted from SpacemanDMM dreamchecker lib.rs, commit
//! 0290db5c752fa292f9824521515b603a2afd11dc (GPL-3.0).
//! Compiler acceptance and inherited directive semantics are separate contracts.
use crate::{
    checker_reachable::{self, Event},
    checks::{BodyView, Diagnostic, Severity},
};
use dm_tree::frontend::ArchivedBody;
pub fn check(view: &BodyView<'_>, severity: Severity) -> Result<Vec<Diagnostic>, String> {
    if severity == Severity::Disabled {
        return Ok(Vec::new());
    }
    findings(checker_reachable::analyze(view)?, severity)
}
pub fn archived(body: &ArchivedBody<'_>, severity: Severity) -> Result<Vec<Diagnostic>, String> {
    if !body.statement_body().syntax_complete() {
        return Err("body has unsupported or malformed native syntax".into());
    }
    if severity == Severity::Disabled {
        return Ok(Vec::new());
    }
    findings(checker_reachable::archived(body)?, severity)
}
fn findings(
    walk: checker_reachable::Walk<'_>,
    severity: Severity,
) -> Result<Vec<Diagnostic>, String> {
    walk.events
        .into_iter()
        .filter_map(|event| diagnostic(event, severity).transpose())
        .collect()
}
pub(crate) fn diagnostic(
    event: Event<'_>,
    severity: Severity,
) -> Result<Option<Diagnostic>, String> {
    let Event::SettingOutsidePrefix { statement, .. } = event else {
        return Ok(None);
    };
    Ok(Some(Diagnostic {
        family: "set_has_no_effect",
        severity,
        span: statement.header_span,
        expression_span: statement.header_span,
        message: "set statement not at the top of the proc".into(),
        notes: Vec::new(),
    }))
}

#[cfg(test)]
#[path = "checks_set_no_effect_tests.rs"]
mod tests;
