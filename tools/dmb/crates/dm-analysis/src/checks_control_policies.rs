//! Multiple control policies consume one ordered traversal over shared syntax.
//! Family selection never sorts diagnostics after emission: pinned event order
//! (including two diagnostics at the same condition) remains authoritative.
use crate::{
    checker_reachable::{self, Event},
    checks::{BodyView, Diagnostic, Severity},
    checks_flow,
};
use dm_tree::frontend::ArchivedBody;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Family {
    Static,
    Unreachable,
    LoopDeterminate,
    IfDeterminate,
    SettingPlacement,
}
impl Family {
    pub fn name(self) -> &'static str {
        match self {
            Self::Static => "control_condition_static",
            Self::Unreachable => "unreachable_code",
            Self::LoopDeterminate => "loop_condition_determinate",
            Self::IfDeterminate => "if_condition_determinate",
            Self::SettingPlacement => "set_has_no_effect",
        }
    }
}
pub fn check(
    view: &BodyView<'_>,
    policies: &[(Family, Severity)],
) -> Result<Vec<Diagnostic>, String> {
    validate(policies)?;
    if policies
        .iter()
        .all(|(_, severity)| *severity == Severity::Disabled)
    {
        return Ok(Vec::new());
    }
    findings(checker_reachable::analyze(view)?, policies)
}
pub fn archived(
    body: &ArchivedBody<'_>,
    policies: &[(Family, Severity)],
) -> Result<Vec<Diagnostic>, String> {
    validate(policies)?;
    if policies
        .iter()
        .all(|(_, severity)| *severity == Severity::Disabled)
    {
        return Ok(Vec::new());
    }
    findings(checker_reachable::archived(body)?, policies)
}
fn validate(policies: &[(Family, Severity)]) -> Result<(), String> {
    for (i, (family, _)) in policies.iter().enumerate() {
        if policies[..i].iter().any(|(seen, _)| seen == family) {
            return Err("duplicate control policy family".into());
        }
    }
    Ok(())
}
fn findings(
    walk: checker_reachable::Walk<'_>,
    policies: &[(Family, Severity)],
) -> Result<Vec<Diagnostic>, String> {
    let mut found = Vec::new();
    for event in walk.events {
        let family = match event {
            Event::ControlCondition { .. } => Family::Static,
            Event::Unreachable { .. } => Family::Unreachable,
            Event::LoopCondition { .. } => Family::LoopDeterminate,
            Event::IfDeterminate { .. } => Family::IfDeterminate,
            Event::SettingOutsidePrefix { .. } => Family::SettingPlacement,
        };
        let Some((_, severity)) = policies.iter().find(|(selected, _)| *selected == family) else {
            continue;
        };
        if *severity == Severity::Disabled {
            continue;
        }
        let diagnostic = match family {
            Family::Static => crate::checks_control_static::diagnostic(event, *severity)?,
            Family::Unreachable => {
                checks_flow::diagnostic(event, checks_flow::Family::Unreachable, *severity)?
            }
            Family::LoopDeterminate => {
                checks_flow::diagnostic(event, checks_flow::Family::LoopDeterminate, *severity)?
            }
            Family::IfDeterminate => {
                checks_flow::diagnostic(event, checks_flow::Family::IfDeterminate, *severity)?
            }
            Family::SettingPlacement => crate::checks_set_no_effect::diagnostic(event, *severity)?,
        };
        if let Some(diagnostic) = diagnostic {
            found.push(diagnostic);
        }
    }
    Ok(found)
}
#[cfg(test)]
#[path = "checks_control_policies_tests.rs"]
mod tests;
