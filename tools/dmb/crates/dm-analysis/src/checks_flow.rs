//! Exact pinned checker flow families over primary syntax, not runtime CFG.
//! Policy and wording adapted from SpacemanDMM 0290db5c752fa292f9824521515b603a2afd11dc
//! (GPL-3.0). This does not claim complete checker/configuration parity.
use crate::{
    checker_reachable::{self, Event, UnreachableKind},
    checks::{BodyView, Diagnostic, Severity},
};
use dm_tree::frontend::ArchivedBody;
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Family {
    Unreachable,
    LoopDeterminate,
    IfDeterminate,
}
impl Family {
    pub fn name(self) -> &'static str {
        match self {
            Self::Unreachable => "unreachable_code",
            Self::LoopDeterminate => "loop_condition_determinate",
            Self::IfDeterminate => "if_condition_determinate",
        }
    }
}
pub fn check(
    view: &BodyView<'_>,
    family: Family,
    severity: Severity,
) -> Result<Vec<Diagnostic>, String> {
    if severity == Severity::Disabled {
        return Ok(Vec::new());
    }
    findings(checker_reachable::analyze(view)?, family, severity)
}
pub fn archived(
    body: &ArchivedBody<'_>,
    family: Family,
    severity: Severity,
) -> Result<Vec<Diagnostic>, String> {
    if !body.statement_body().syntax_complete() {
        return Err("body has unsupported or malformed native syntax".into());
    }
    if severity == Severity::Disabled {
        return Ok(Vec::new());
    }
    findings(checker_reachable::archived(body)?, family, severity)
}
fn findings(
    walk: checker_reachable::Walk<'_>,
    family: Family,
    severity: Severity,
) -> Result<Vec<Diagnostic>, String> {
    walk.events
        .into_iter()
        .filter_map(|event| diagnostic(event, family, severity).transpose())
        .collect()
}
pub(crate) fn diagnostic(
    event: Event<'_>,
    family: Family,
    severity: Severity,
) -> Result<Option<Diagnostic>, String> {
    let (at, expression_span, message) = match (family, event) {
        (Family::Unreachable, Event::Unreachable { kind, at }) => (
            at,
            at,
            match kind {
                UnreachableKind::Sibling => "possible unreachable code here",
                UnreachableKind::IfArm => {
                    "unreachable if block, preceeding if/elseif condition(s) are always true"
                }
                UnreachableKind::ElseArm => {
                    "unreachable else block, preceeding if/elseif condition(s) are always true"
                }
            }
            .to_owned(),
        ),
        (Family::LoopDeterminate, Event::LoopCondition { expression, at }) => {
            let Some(value) = checker_reachable::truthy(expression)? else {
                return Ok(None);
            };
            (
                at,
                expression.span,
                format!(
                    "loop condition is always {}",
                    if value { "true" } else { "false" }
                ),
            )
        }
        (
            Family::IfDeterminate,
            Event::IfDeterminate {
                expression,
                at,
                value,
            },
        ) => (
            at,
            expression.span,
            format!(
                "if condition is always {}",
                if value { "true" } else { "false" }
            ),
        ),
        _ => return Ok(None),
    };
    Ok(Some(Diagnostic {
        family: family.name(),
        severity,
        span: at,
        expression_span,
        message,
        notes: Vec::new(),
    }))
}

#[cfg(test)]
#[path = "checks_flow_tests.rs"]
mod tests;
