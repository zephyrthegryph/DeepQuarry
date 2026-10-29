//! One configured union of the five control policies, borrowing one primary walk.
//! This is a request-local plan, not a sibling memo/cache or an owned syntax tree.
//! Each call borrows the exact compiler-issued body, runs the union once, and
//! drops every borrowed event before returning compact owned diagnostics.
use crate::{
    check_policy::{CheckerPolicy, DiagnosticSeverity},
    checks::{BodyView, Diagnostic, Severity},
    checks_control_policies::{self, Family},
};
use dm_tree::frontend::ArchivedBody;
#[derive(Clone, Debug)]
pub struct Finding {
    /// Producer fact; `severity` below is the authoritative configured level.
    pub diagnostic: Diagnostic,
    pub severity: DiagnosticSeverity,
}
#[derive(Clone, Debug)]
pub struct Plan {
    entries: Vec<(Family, Option<DiagnosticSeverity>)>,
}
impl Plan {
    pub fn new(names: &[String], policy: &CheckerPolicy) -> Result<Self, String> {
        if names.is_empty() || names.len() > 5 {
            return Err("configured control batch requires 1..5 distinct families".into());
        }
        let mut entries = Vec::with_capacity(names.len());
        for name in names {
            let family = match name.as_str() {
                "control_condition_static" => Family::Static,
                "unreachable_code" => Family::Unreachable,
                "loop_condition_determinate" => Family::LoopDeterminate,
                "if_condition_determinate" => Family::IfDeterminate,
                "set_has_no_effect" => Family::SettingPlacement,
                _ => return Err("unsupported configured control family".into()),
            };
            if entries.iter().any(|(seen, _)| *seen == family) {
                return Err("duplicate configured control family".into());
            }
            entries.push((
                family,
                policy.register(Some(name), DiagnosticSeverity::Error),
            ));
        }
        Ok(Self { entries })
    }
    pub fn enabled(&self) -> bool {
        self.entries.iter().any(|(_, level)| level.is_some())
    }
    pub fn check(&self, view: &BodyView<'_>) -> Result<Vec<Finding>, String> {
        self.run(|policies| checks_control_policies::check(view, policies))
    }
    pub fn archived(&self, body: &ArchivedBody<'_>) -> Result<Vec<Finding>, String> {
        self.run(|policies| checks_control_policies::archived(body, policies))
    }
    fn run(
        &self,
        walk: impl FnOnce(&[(Family, Severity)]) -> Result<Vec<Diagnostic>, String>,
    ) -> Result<Vec<Finding>, String> {
        if !self.enabled() {
            return Ok(Vec::new());
        }
        let policies: Vec<_> = self
            .entries
            .iter()
            .map(|(family, level)| {
                (
                    *family,
                    if level.is_some() {
                        Severity::Error
                    } else {
                        Severity::Disabled
                    },
                )
            })
            .collect();
        // Exactly one invocation; producer event order is preserved, never sorted
        // by requested family order or independently recomputed for projections.
        let mut out = Vec::new();
        for diagnostic in walk(&policies)? {
            let severity = self
                .entries
                .iter()
                .find(|(family, _)| family.name() == diagnostic.family)
                .and_then(|(_, level)| *level)
                .ok_or("control union emitted an unrequested/disabled family")?;
            out.push(Finding {
                diagnostic,
                severity,
            });
        }
        Ok(out)
    }
}
#[cfg(test)]
#[path = "checks_configured_control_tests.rs"]
mod tests;
