//! Explicit idle diagnostic; category reports overlap and must never be summed.
use super::BuildHost;
use std::io::{self, Write};

impl BuildHost {
    pub(super) fn emit_idle_census(&self, boundary: &str) {
        let Some(path) = std::env::var_os("DMB_IDLE_CENSUS_PATH").filter(|path| !path.is_empty())
        else {
            return;
        };
        let result = (|| -> io::Result<()> {
            // Each existing visitor deduplicates live owners within its own report.
            // Different categories can share allocations; no total is calculated.
            let mut file = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(path)?;
            let mut emit =
                |category: &str, report: serde_json::Value| -> io::Result<()> {
                    serde_json::to_writer(&mut file, &serde_json::json!({
                    "schema": 1, "boundary": boundary, "category": category,
                    "session": self.session_id,
                    "scope": "opt_in_independent_owner_reports_not_additive_or_private_memory",
                    "report": report
                })).map_err(io::Error::other)?;
                    file.write_all(b"\n")
                };
            emit(
                "declarations",
                serde_json::to_value(self.declaration_retention_census())
                    .map_err(io::Error::other)?,
            )?;
            emit(
                "symbolic",
                serde_json::to_value(self.symbolic_retention_stats()).map_err(io::Error::other)?,
            )?;
            emit(
                "expansion_inputs",
                serde_json::to_value(self.expansion_input_retention_census())
                    .map_err(io::Error::other)?,
            )?;
            emit(
                "prepared_inputs",
                serde_json::to_value(self.prepared_source_retention_census())
                    .map_err(io::Error::other)?,
            )?;
            emit(
                "projections",
                serde_json::to_value(self.owner_projection_retention_census())
                    .map_err(io::Error::other)?,
            )?;
            emit(
                "initializer_assemblies",
                serde_json::to_value(self.initializer_assembly_retention_census())
                    .map_err(io::Error::other)?,
            )?;
            emit(
                "generation",
                serde_json::to_value(self.generation_retention_census())
                    .map_err(io::Error::other)?,
            )?;
            emit(
                "host_facts",
                serde_json::to_value(self.host_facts_retention_census())
                    .map_err(io::Error::other)?,
            )?;
            Ok(())
        })();
        if let Err(error) = result {
            crate::daemon::emit_stderr(format_args!(
                "dmbd idle census failed boundary={boundary}: {error}"
            ));
        }
    }
}
