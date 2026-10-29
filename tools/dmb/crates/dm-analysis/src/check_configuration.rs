//! Complete pinned checker TOML schema over host-captured bytes, with no I/O.
//!
//! Adapted from SpacemanDMM dreammaker config.rs/error.rs at commit
//! 0290db5c752fa292f9824521515b603a2afd11dc (GPL-3.0). The pinned TOML parser
//! dependency is intentional: a newer TOML grammar/error contract is not proof
//! of accepting the same configuration. Unknown fields retain serde's ignored
//! field behavior, while every known non-policy section is still validated.
//!
//! The host must bind the selected path and its captured bytes/read failure/
//! autodetect-absence receipt into the input revision. AnalyzeRaw text is NOT
//! sufficient: pinned configuration reading is strict UTF-8, not UTF-8-lossy.
//! This module performs no existence probes, directory scans, DM parsing, or
//! environment selection from the config's `environment` field. The pinned CLI
//! chooses its DME before reading configuration; that field is only retained.
//! On Configuration failure the caller retains its previously installed Config
//! and registers CONFIGURATION_ERROR_MESSAGE plus the captured cause through
//! that previous policy, as pinned Context::force_config does. A failed parse
//! never installs a partially deserialized policy or suppresses its own error.

use crate::check_policy::{configuration_path, CheckerPolicy};
use serde::Deserialize;
use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
};

pub const CONFIGURATION_ERROR_MESSAGE: &str = "Error reading configuration file";

#[derive(Deserialize, Default, Debug, Clone, PartialEq)]
#[serde(default)]
pub struct Config {
    pub environment: Option<PathBuf>,
    display: WarningDisplay,
    diagnostics: BTreeMap<String, WarningLevel>,
    pub code_standards: CodeStandards,
    pub langserver: Langserver,
    pub dmdoc: DMDoc,
    pub debugger: Debugger,
    pub map_renderer: MapRenderer,
}
#[derive(Deserialize, Default, Debug, Clone, PartialEq)]
pub struct WarningDisplay {
    #[serde(default)]
    error_level: WarningLevel,
}
#[derive(Deserialize, Default, Debug, Clone, PartialEq)]
pub struct Langserver {
    pub dreamchecker: bool,
}
#[derive(Deserialize, Default, Debug, Clone, PartialEq)]
#[serde(default)]
pub struct CodeStandards {
    pub disallow_relative_proc_definitions: bool,
    pub disallow_relative_type_definitions: bool,
}
#[derive(Deserialize, Default, Debug, Clone, PartialEq)]
#[serde(default)]
pub struct DMDoc {
    pub use_typepath_names: bool,
    pub index_file: Option<String>,
    pub module_directories: Vec<String>,
}
#[derive(Deserialize, Default, Debug, Clone, PartialEq)]
pub struct Debugger {
    #[serde(default)]
    pub engine: DebugEngine,
}
#[derive(Deserialize, Default, Debug, Clone, Copy, PartialEq)]
#[serde(rename_all(deserialize = "lowercase"))]
enum WarningLevel {
    #[serde(alias = "errors")]
    Error,
    #[serde(alias = "warnings")]
    Warning,
    #[serde(alias = "infos")]
    Info,
    #[serde(alias = "hints")]
    Hint,
    #[serde(alias = "false", alias = "off")]
    Disabled,
    #[default]
    Unset,
}
#[derive(Deserialize, Default, Debug, Clone, Copy, PartialEq)]
pub enum DebugEngine {
    #[default]
    #[serde(alias = "extools")]
    Extools,
    #[serde(alias = "auxtools")]
    Auxtools,
}
#[derive(Deserialize, Default, Debug, Clone, PartialEq)]
#[serde(default)]
pub struct MapRenderer {
    pub render_passes: BTreeMap<String, bool>,
    pub fancy_layers: BTreeMap<String, f32>,
    pub hide_invisible: Vec<String>,
}
impl WarningLevel {
    fn normalized(self) -> &'static str {
        match self {
            Self::Error => "error",
            Self::Warning => "warning",
            Self::Info => "info",
            Self::Hint => "hint",
            Self::Disabled => "disabled",
            Self::Unset => "unset",
        }
    }
}
impl Config {
    pub fn policy(&self) -> CheckerPolicy {
        let display = serde_json::json!({"error_level":self.display.error_level.normalized()});
        let diagnostics = serde_json::Value::Object(
            self.diagnostics
                .iter()
                .map(|(name, level)| (name.clone(), serde_json::json!(level.normalized())))
                .collect(),
        );
        CheckerPolicy::from_sections(Some(&display), Some(&diagnostics))
            .expect("validated pinned levels normalize to checker policy")
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Selection {
    pub path: PathBuf,
    pub explicit: bool,
}
pub fn select(environment: &Path, explicit: Option<&Path>) -> Selection {
    Selection {
        path: configuration_path(environment, explicit),
        explicit: explicit.is_some(),
    }
}
#[derive(Clone, Copy, Debug)]
pub enum CapturedRead<'a> {
    /// Authoritative false result of pinned autodetection's exists() probe.
    /// An explicit -c request instead needs bytes or an actual read failure.
    AutodetectAbsent,
    ReadFailure {
        cause: &'a str,
    },
    Bytes(&'a [u8]),
}
#[derive(Clone, Copy, Debug)]
pub struct Capture<'a> {
    pub path: &'a Path,
    pub read: CapturedRead<'a>,
}
#[derive(Clone, Debug, PartialEq)]
pub struct Loaded {
    pub selected: Selection,
    pub present: bool,
    pub config: Config,
    pub policy: CheckerPolicy,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum LoadError {
    ForeignCapture {
        selected: PathBuf,
        captured: PathBuf,
    },
    ExplicitWithoutReadResult(PathBuf),
    Configuration {
        path: PathBuf,
        line: u32,
        column: u16,
        cause: String,
    },
}
impl std::fmt::Display for LoadError {
    fn fmt(&self, out: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Configuration {
                path,
                line,
                column,
                cause,
            } => write!(
                out,
                "{}, line {line}, column {column}: Error reading configuration file: {cause}",
                path.display()
            ),
            other => write!(out, "invalid captured checker configuration: {other:?}"),
        }
    }
}
impl std::error::Error for LoadError {}

pub fn load(selected: &Selection, capture: Capture<'_>) -> Result<Loaded, LoadError> {
    if capture.path != selected.path.as_path() {
        return Err(LoadError::ForeignCapture {
            selected: selected.path.clone(),
            captured: capture.path.into(),
        });
    }
    let failure = |cause: String, line: u32, column: u16| LoadError::Configuration {
        path: selected.path.clone(),
        line,
        column,
        cause,
    };
    let (present, config) = match capture.read {
        CapturedRead::AutodetectAbsent if !selected.explicit => (false, Config::default()),
        CapturedRead::AutodetectAbsent => {
            return Err(LoadError::ExplicitWithoutReadResult(selected.path.clone()))
        }
        CapturedRead::ReadFailure { cause } => return Err(failure(cause.into(), 1, 1)),
        CapturedRead::Bytes(bytes) => {
            // Match std::io::Read::read_to_string's invalid-data cause; never
            // repair invalid bytes with the source-code legacy decoder.
            let source = std::str::from_utf8(bytes)
                .map_err(|_| failure("stream did not contain valid UTF-8".into(), 1, 1))?;
            let config = toml_checker::from_str::<Config>(source).map_err(|error| {
                let (line, column) = error.line_col().map_or((1, 1), |(line, column)| {
                    (
                        (line as u32).wrapping_add(1),
                        (column as u16).wrapping_add(1),
                    )
                });
                failure(error.to_string(), line, column)
            })?;
            (true, config)
        }
    };
    let policy = config.policy();
    Ok(Loaded {
        selected: selected.clone(),
        present,
        config,
        policy,
    })
}

#[cfg(test)]
#[path = "check_configuration_tests.rs"]
mod tests;
