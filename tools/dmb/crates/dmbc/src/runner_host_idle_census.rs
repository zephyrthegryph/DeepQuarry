//! Explicit idle diagnostic; category reports overlap and must never be summed.
use super::BuildHost;
use std::io::{self, Write};

impl BuildHost {
    fn query_snapshot_retention_census(&self) -> crate::heap_census::HeapCensusReport {
        let mut census = crate::heap_census::HeapCensus::new("retained.query_snapshot");
        census.arc_object("query_snapshot.state", &self.query_state);
        // The actual host owns this SAME QueryDb even when no snapshot/model
        // remains. Visit its existing raw input ledger once, outside state lock.
        self.query_db.raw_source_input_census(&mut census);
        {
            let state = self
                .query_state
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            if let Some(raw)=&state.raw_snapshot{raw.census(&mut census);}
            if let Some(snapshot) = &state.snapshot {
                snapshot.census(&mut census);
            }
        }
        census.finish()
    }
    fn optional_artifact_retention_census(&self) -> crate::heap_census::HeapCensusReport {
        let mut census = crate::heap_census::HeapCensus::new("retained.optional_artifacts");
        // One graph visitor deduplicates shared recipe/answer allocations. Engine
        // backing may also belong to the semantic host; this report is not an
        // estimate of reclaimable private bytes or an additive category total.
        if let Some((_, owner)) = &self.initializers {
            if census.arc_object("optional.classification_owner", owner) {
                census.initializer_artifacts(owner);
            }
        }
        if let Some((_, owner)) = &self.startup {
            if census.arc_object("optional.startup_owner", owner) {
                crate::heap_census::startup_artifacts::inspect(&mut census, owner);
            }
        }
        if let Some((_, owner)) = &self.abi {
            if census.arc_object("optional.abi_owner", owner) {
                census.abi_artifacts(owner);
            }
        }
        census.finish()
    }
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
                "optional_classification_startup_abi",
                serde_json::to_value(self.optional_artifact_retention_census())
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
            if let Some(resources) = &self.resources {
                emit(
                    "resources",
                    serde_json::to_value(resources.census()).map_err(io::Error::other)?,
                )?;
            }
            emit(
                "query_snapshot",
                serde_json::to_value(self.query_snapshot_retention_census())
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

#[cfg(test)]mod actual_native_arena_idle_census_tests{
 use super::*;use dm_preprocess::source_arena_credit::SourceArenaWork;
 #[test]fn actual_idle_census_visits_native_allocation_metadata_even_without_a_snapshot_and_never_counts_reservation_as_payload(){
  let host=BuildHost::default();let reservation=SourceArenaWork::reserve(host.query_db.as_ref(),8192).unwrap();let mut actual_metadata=0;reservation.visit_storage(&mut|_,bytes|actual_metadata+=bytes);
  let report=host.query_snapshot_retention_census();let row=report.owners.iter().find(|row|row.owner=="query_snapshot.raw_source_inputs.arena_credit").expect("existing real idle caller reached the actual input ledger");assert_eq!(row.unique_known_capacity_bytes,actual_metadata as u64);assert!(row.unique_known_capacity_bytes<8192);assert_eq!(reservation.reserved_bytes(),8192);
  drop(reservation);let report=host.query_snapshot_retention_census();let row=report.owners.iter().find(|row|row.owner=="query_snapshot.raw_source_inputs.arena_credit").unwrap();assert_eq!(row.unique_payload_bytes,0,"dead weak owner is not dereferenced or treated as live");assert_eq!(row.unique_known_capacity_bytes,actual_metadata as u64,"real dead Arc control allocation remains until actual ledger pruning");
 }
}
