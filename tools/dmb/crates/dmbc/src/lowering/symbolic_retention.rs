//! Explicit retained-owner telemetry; no traversal on ordinary lookup/hit paths.
use super::SessionSymbolicMemo;
use crate::heap_census::{HeapCensus, HeapCensusReport};
use serde::Serialize;
use std::sync::atomic::Ordering;

#[derive(Serialize)]
pub struct SymbolicRetentionStats {
    pub records: usize,
    pub successful_admissions: u64,
    pub successful_reuses: u64,
    pub pruned_members: u64,
    /// Exact exposed container capacity. Excludes opaque index nodes and allocator metadata.
    pub known_capacity_bytes: u64,
    /// Exposed immutable payload where allocation capacity is unavailable.
    pub unknown_capacity_payload_bytes: u64,
    pub owners: HeapCensusReport,
}
impl SessionSymbolicMemo {
    pub(crate) fn retention_stats(&self) -> SymbolicRetentionStats {
        let records = self
            .records
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let mut census = HeapCensus::new("session_symbolic.retained");
        for record in records.values() {
            if !census.arc_object("session_symbolic.records", record) {
                continue;
            }
            census.vec_payload("session_symbolic.keys", &record.key);
            census.retained_symbolic_ledger(&record.reads, &record.versions);
            crate::symbolic::ReusableProcedureArtifact::retained_census(
                &record.artifact,
                &mut census,
            );
            census.vec_payload("session_symbolic.debug_offsets", &record.relative_debug);
            census.vec_payload("session_symbolic.required_types", &record.required_types);
            if census.vec_payload(
                "session_symbolic.modified_recipes",
                &record.modified_recipes,
            ) {
                for recipe in &record.modified_recipes {
                    recipe.retained_census(&mut census);
                }
            }
        }
        census.unknown("session_symbolic.records", "BTreeMap index node capacity, Arc control blocks, allocator overhead and freed pages are not exposed; this is not private-memory measurement");
        let owners = census.finish();
        SymbolicRetentionStats {
            records: records.len(),
            successful_admissions: self.admitted.load(Ordering::Relaxed),
            successful_reuses: self.reused.load(Ordering::Relaxed),
            pruned_members: self.pruned.load(Ordering::Relaxed),
            known_capacity_bytes: owners.unique_known_capacity_bytes,
            unknown_capacity_payload_bytes: owners.unknown_capacity_payload_bytes,
            owners,
        }
    }
}

#[cfg(test)]
#[path = "symbolic_retention_tests.rs"]
mod tests;
