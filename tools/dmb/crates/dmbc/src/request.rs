//! Typed host-independent request boundary. Paths are resolved by the runner.
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::PathBuf;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum BuildCommand {
    Analyze,
    Compile,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct BuildRequest {
    pub command: BuildCommand,
    pub project: PathBuf,
    pub defines: BTreeMap<String, String>,
    pub workers: usize,
    pub engine_template: Option<PathBuf>,
    pub bootstrap_catalog: bool,
    pub progress_enabled: bool,
    pub output_store: Option<PathBuf>,
    pub exact_inputs: bool,
    pub no_cache: bool,
    pub record_inputs: Option<PathBuf>,
    pub replay_inputs: Option<PathBuf>,
    pub artifact_directory: Option<PathBuf>,
    /// Accepted today; execution remains one-shot until the daemon lands.
    pub no_daemon: bool,
    /// Profiling lifecycle belongs to the host, not reusable build execution.
    pub trace_path: Option<PathBuf>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Command {
    Help,
    Gc { project: PathBuf },
    Stats { project: PathBuf },
    Explain { project: PathBuf, target: String },
    Verify(Vec<String>),
    Build(Box<BuildRequest>),
}

#[derive(Debug, Serialize, Deserialize)]
pub enum BuildOutcome {
    Published {
        pair: crate::publish::OutputPair,
        output_project: PathBuf,
        session_hit: bool,
        seconds: f64,
    },
    Analyzed {
        semantic_rows: usize,
        occurrence_rows: usize,
        body_rows: usize,
        seconds: f64,
    },
}

#[derive(Debug)]
pub enum CommandOutcome {
    Completed,
    Build(BuildOutcome),
}
