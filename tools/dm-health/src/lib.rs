//! Dream Maker health checks backed by an OpenDream AST export.
pub mod ast;
pub mod cache;
pub mod contracts;
pub mod metrics;
pub mod provenance;
pub mod server;
pub mod suite;
pub mod symbols;
pub mod typing;

use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct Finding {
    pub rule: &'static str,
    pub path: String,
    pub line: usize,
    pub severity: &'static str,
    pub message: String,
}

impl Finding {
    pub fn fingerprint(&self) -> String {
        format!("{}:{}:{}", self.rule, self.path, self.message)
    }
}

/// Physical file metrics and comment contracts need raw source; all syntax
/// and control-flow findings come from `ast::analyze_reader`.
pub fn load_source_contracts(
    root: &Path,
    files: &[PathBuf],
) -> std::io::Result<(Vec<contracts::Contract>, Vec<Finding>)> {
    let mut findings = Vec::new();
    let mut sources = Vec::new();
    let mut all_contracts = Vec::new();
    for path in files {
        let source = String::from_utf8_lossy(&fs::read(path)?).into_owned();
        let relative = path
            .strip_prefix(root)
            .unwrap_or(path)
            .to_string_lossy()
            .replace('\\', "/");
        for (line, message) in contracts::invalid_annotations(&source) {
            findings.push(Finding {
                rule: "invalid-contract",
                path: relative.clone(),
                line,
                severity: "error",
                message,
            });
        }
        all_contracts.extend(contracts::collect(&source));
        sources.push((relative, source));
    }
    for (relative, source) in sources {
        let lines = source.lines().count();
        if lines > 2500 {
            findings.push(Finding {
                rule: "large-file",
                path: relative.clone(),
                line: 1,
                severity: "info",
                message: format!("{lines} lines; threshold 2500"),
            });
        }
        if !relative.starts_with("code/__defines/") {
            for (index, line) in source.lines().enumerate() {
                let trimmed = line.trim_start();
                if trimmed.starts_with("//") || trimmed.starts_with("#define") {
                    continue;
                }
                if trimmed.contains("var/global/") {
                    findings.push(Finding { rule: "raw-global-state", path: relative.clone(), line: index + 1, severity: "info", message: "direct var/global state bypasses the GLOB holder; document why its lifetime or scope is needed".into() });
                }
                if trimmed.contains("GLOBAL_REAL(")
                    && ![
                        "code/_global_vars/configuration.dm",
                        "code/controllers/master.dm",
                        "code/controllers/globals.dm",
                        "code/controllers/failsafe.dm",
                        "code/modules/logging/log_holder.dm",
                        "code/modules/debugging/tracy.dm",
                        "code/modules/debugging/debugger.dm",
                        "code/ATMOSPHERICS/tg_infra_compat.dm",
                    ]
                    .contains(&relative.as_str())
                {
                    findings.push(Finding { rule: "raw-global-declaration", path: relative.clone(), line: index + 1, severity: "warning", message: "GLOBAL_REAL creates writable global state outside the approved bootstrap and singleton declarations".into() });
                }
            }
        }
    }
    Ok((all_contracts, findings))
}
