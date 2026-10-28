//! Diagnostic policy normalization, adapted from SpacemanDMM dreammaker
//! config.rs/error.rs and dreamchecker main.rs at commit
//! 0290db5c752fa292f9824521515b603a2afd11dc (GPL-3.0).
//!
//! This module consumes already-deserialized configuration sections. It does
//! not parse TOML, DM source, preprocessors, or proc directives. The client must
//! deserialize/validate the rest of the pinned config schema independently.
//! Native integration must include configuration bytes/path in query identity.
//!
//! Inputs outside this contract: environment discovery, config I/O errors and
//! their source locations, code_standards flags, parser diagnostics, and the
//! inherited SpacemanDMM_* proc directives. Pinned #pragma handles only
//! `multiple` (include multiplicity): other names are ignored, not suppression.

use serde_json::Value;
use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
};

/// Ordering is the pinned severity ordering; lower means more severe.
#[derive(Clone, Copy, Debug, Default, Eq, Ord, PartialEq, PartialOrd)]
pub enum DiagnosticSeverity {
    #[default]
    Error,
    Warning,
    Info,
    Hint,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum WarningLevel {
    Error,
    Warning,
    Info,
    Hint,
    Disabled,
    #[default]
    Unset,
}

impl WarningLevel {
    /// Same case-sensitive names and aliases as pinned serde WarningLevel.
    pub fn parse(value: &str) -> Result<Self, String> {
        Ok(match value {
            "error" | "errors" => Self::Error,
            "warning" | "warnings" => Self::Warning,
            "info" | "infos" => Self::Info,
            "hint" | "hints" => Self::Hint,
            "disabled" | "false" | "off" => Self::Disabled,
            "unset" => Self::Unset,
            _ => return Err(format!("unknown checker warning level {value:?}")),
        })
    }

    fn severity(self) -> Option<DiagnosticSeverity> {
        match self {
            Self::Error => Some(DiagnosticSeverity::Error),
            Self::Warning => Some(DiagnosticSeverity::Warning),
            Self::Info => Some(DiagnosticSeverity::Info),
            Self::Hint => Some(DiagnosticSeverity::Hint),
            Self::Disabled | Self::Unset => None,
        }
    }

    pub fn applies_to(self, severity: DiagnosticSeverity) -> bool {
        match self {
            Self::Disabled => false,
            Self::Unset => true,
            level => severity <= level.severity().expect("concrete level"),
        }
    }
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct CheckerPolicy {
    pub display_error_level: WarningLevel,
    /// Exact, case-sensitive errortype keys. Unknown keys are legal and inert
    /// until a producer emits that name; untagged findings never match them.
    pub diagnostics: BTreeMap<String, WarningLevel>,
}

impl CheckerPolicy {
    /// Normalize only the two policy sections after TOML deserialization.
    /// Unknown display members are ignored, matching pinned serde's schema.
    /// Explicit null/non-string levels are errors, not default/disabled values.
    pub fn from_sections(
        display: Option<&Value>,
        diagnostics: Option<&Value>,
    ) -> Result<Self, String> {
        let mut policy = Self::default();
        if let Some(display) = display {
            let table = display.as_object().ok_or("display must be a table")?;
            if let Some(level) = table.get("error_level") {
                policy.display_error_level = level_value(level, "display.error_level")?;
            }
        }
        if let Some(diagnostics) = diagnostics {
            let table = diagnostics
                .as_object()
                .ok_or("diagnostics must be a table")?;
            for (name, value) in table {
                policy.diagnostics.insert(
                    name.clone(),
                    level_value(value, &format!("diagnostics.{name}"))?,
                );
            }
        }
        Ok(policy)
    }

    /// Registration ordering is significant: override/disable by family first,
    /// then apply the display threshold to the resulting severity.
    pub fn register(
        &self,
        family: Option<&str>,
        producer: DiagnosticSeverity,
    ) -> Option<DiagnosticSeverity> {
        let level = family
            .and_then(|name| self.diagnostics.get(name))
            .copied()
            .unwrap_or_default();
        let severity = match level {
            WarningLevel::Disabled => return None,
            WarningLevel::Unset => producer,
            concrete => concrete.severity().expect("concrete level"),
        };
        self.display_error_level
            .applies_to(severity)
            .then_some(severity)
    }
}

fn level_value(value: &Value, field: &str) -> Result<WarningLevel, String> {
    WarningLevel::parse(
        value
            .as_str()
            .ok_or_else(|| format!("{field} must be a warning-level string"))?,
    )
}

/// Pure config selection only. The caller checks existence for the autodetect
/// candidate; an explicit nonexistent path still causes a config I/O error.
pub fn configuration_path(environment: &Path, explicit: Option<&Path>) -> PathBuf {
    explicit.map(Path::to_path_buf).unwrap_or_else(|| {
        environment
            .parent()
            .unwrap_or_else(|| Path::new(""))
            .join("SpacemanDMM.toml")
    })
}

/// Pinned CLI prints registered Error/Warning/Info immediately; hints remain in
/// stored diagnostics/JSON counts but do not count toward its failure exit.
pub fn cli_printed(severity: DiagnosticSeverity) -> bool {
    severity <= DiagnosticSeverity::Info
}
pub fn cli_counts_as_failure(severity: DiagnosticSeverity) -> bool {
    severity <= DiagnosticSeverity::Info
}

#[cfg(test)]
#[path = "check_policy_tests.rs"]
mod tests;
