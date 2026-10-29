//! Exact control_condition_static findings over pinned checker traversal facts.
//! Policy/wording adapted from SpacemanDMM dreamchecker lib.rs at commit
//! 0290db5c752fa292f9824521515b603a2afd11dc (GPL-3.0). This is one bounded
//! family; it does not establish full checker/configuration/source parity.

use crate::{
    checker_constant_shape::{classify, ControlConstant},
    checker_reachable::{self, Event, Walk},
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

fn findings(walk: Walk<'_>, severity: Severity) -> Result<Vec<Diagnostic>, String> {
    walk.events
        .into_iter()
        .filter_map(|event| diagnostic(event, severity).transpose())
        .collect()
}
pub(crate) fn diagnostic(
    event: Event<'_>,
    severity: Severity,
) -> Result<Option<Diagnostic>, String> {
    let Event::ControlCondition { expression, at, .. } = event else {
        return Ok(None);
    };
    let message = match classify(expression)? {
        Some(ControlConstant::ConstantEvaluation) => {
            "control flow condition is a constant evalutation"
        }
        Some(ControlConstant::StaticTerm) => "control flow condition is a static term",
        None => return Ok(None),
    };
    Ok(Some(Diagnostic {
        family: "control_condition_static",
        severity,
        span: at,
        expression_span: expression.span,
        message: message.into(),
        notes: Vec::new(),
    }))
}

#[cfg(test)]
#[path = "checks_control_static_tests.rs"]
mod tests;
