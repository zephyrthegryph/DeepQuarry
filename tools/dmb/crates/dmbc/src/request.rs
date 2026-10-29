//! Typed host-independent request boundary. Paths are resolved by the runner.
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::PathBuf;

pub(crate) fn client_cache_root() -> Result<PathBuf, Box<dyn std::error::Error>> {
    let root = dm_cache::Cache::default_root()?;
    Ok(if root.is_absolute() {
        root
    } else {
        std::env::current_dir()?.join(root)
    })
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum BuildCommand {
    Analyze,
    /// Explicitly emit executable syntax and lexical facts for analysis clients.
    AnalyzeBodies,
    /// Explicit compiler-selected references with current ABI and source issuance.
    AnalyzeResolved,
    /// Explicit nonpublishing current source/host preparation for pinned queries.
    PrepareQuery,
    Compile,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct BuildRequest {
    pub command: BuildCommand,
    /// Explicit checker-only inherited-variable diagnostic preparation profile.
    /// False preserves ordinary strict compilation/preparation admission.
    #[serde(default)]
    pub diagnostic_declarations: bool,

    /// Cooperative execution budget only; never a semantic/cache identity input.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub timeout_seconds: Option<u16>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub policy_inputs: Option<crate::policy_request::PolicyInputRequest>,
    pub project: PathBuf,
    pub defines: BTreeMap<String, String>,
    pub workers: usize,
    pub engine_template: Option<PathBuf>,
    pub bootstrap_catalog: bool,
    pub progress_enabled: bool,
    pub output_store: Option<PathBuf>,
    pub exact_inputs: bool,
    pub no_cache: bool,
    /// Client-resolved disk namespace; never changes the server environment.
    #[serde(default)]
    pub cache_root: Option<PathBuf>,
    pub record_inputs: Option<PathBuf>,
    pub replay_inputs: Option<PathBuf>,
    pub artifact_directory: Option<PathBuf>,
    /// Force the shared request pipeline to use a one-shot host.
    pub no_daemon: bool,
    /// Profiling lifecycle belongs to the host, not reusable build execution.
    pub trace_path: Option<PathBuf>,
    /// Reporting policy only; never part of build identity or reuse.
    #[serde(default)]
    pub warnings: crate::diagnostics::WarningPolicy,
}

pub(crate) fn validate_timeout_seconds(value: Option<u16>) -> std::io::Result<()> {
    if value.is_some_and(|seconds| !(1..=300).contains(&seconds)) {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "request timeout_seconds must be an integer in 1..300",
        ));
    }
    Ok(())
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Command {
    Query {
        request: PathBuf,
        jsonl: bool,
    },
    /// Export only facts already present in an explicitly pinned retained session.
    QueryExport {
        request: PathBuf,
        limits: crate::daemon::query::semantic_client::ExportLimits,
    },
    Help,
    Gc {
        project: PathBuf,
    },
    Stats {
        project: PathBuf,
    },
    Explain {
        project: PathBuf,
        target: String,
    },
    Verify(Vec<String>),
    Build(Box<BuildRequest>),
}

#[derive(Debug, Serialize, Deserialize)]
pub enum BuildOutcome {
    QueryPrepared {
        semantic_revision: String,
        source_revision: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        policy_revision: Option<String>,
        retained: bool,
    },
    Published {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        publication_proof: Option<crate::publication_proof::NativePublicationProof>,
        pair: crate::publish::OutputPair,
        store: PathBuf,
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

pub(crate) fn validate_diagnostic_declarations(request: &BuildRequest) -> std::io::Result<()> {
    if request.diagnostic_declarations
        && (request.command != BuildCommand::PrepareQuery
            || request.no_daemon
            || request
                .policy_inputs
                .as_ref()
                .is_none_or(|policy| policy.workspace.is_some()))
    {
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"diagnostic_declarations requires retained PrepareQuery and explicit non-workspace policy inputs"));
    }
    Ok(())
}
