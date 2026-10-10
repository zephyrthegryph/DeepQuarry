//! Explicit retained-owner telemetry; no traversal on ordinary lookup/hit paths.
use super::SessionSymbolicMemo;
use crate::heap_census::{HeapCensus, HeapCensusReport};
use serde::Serialize;
use std::sync::atomic::Ordering;

#[derive(Serialize)]
pub struct SymbolicRetentionStats {
    pub declines: SymbolicDeclineStats,
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
/// Cumulative bounded diagnostic counters, independent of the optional owner census.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize)]
pub struct SymbolicDeclineStats {
    pub source_identity: u64,
    pub record_absent: u64,
    pub key_changed: u64,
    pub read_changed: u64,
    pub debug_rebase: u64,
    pub modified_reissue: u64,
    /// All current contribution binding refusals, including ABI and helper origins.
    pub contribution_rebind: u64,
    pub capture_excluded: u64,
    pub nonreusable_completion: u64,
}
impl SessionSymbolicMemo {
    pub(crate) fn decline_stats(&self) -> SymbolicDeclineStats {
        let c = &self.declines;
        SymbolicDeclineStats {
            source_identity: c.source_identity.load(Ordering::Relaxed),
            record_absent: c.record_absent.load(Ordering::Relaxed),
            key_changed: c.key_changed.load(Ordering::Relaxed),
            read_changed: c.read_changed.load(Ordering::Relaxed),
            debug_rebase: c.debug_rebase.load(Ordering::Relaxed),
            modified_reissue: c.modified_reissue.load(Ordering::Relaxed),
            contribution_rebind: c.contribution_rebind.load(Ordering::Relaxed),
            capture_excluded: c.capture_excluded.load(Ordering::Relaxed),
            nonreusable_completion: c.nonreusable_completion.load(Ordering::Relaxed),
        }
    }
    pub(crate) fn retention_stats(&self) -> SymbolicRetentionStats {
        let mut census = HeapCensus::new("session_symbolic.retained");
        let records = self.retained_census(&mut census);
        let owners = census.finish();
        SymbolicRetentionStats {
            declines: self.decline_stats(),
            records,
            successful_admissions: self.admitted.load(Ordering::Relaxed),
            successful_reuses: self.reused.load(Ordering::Relaxed),
            pruned_members: self.pruned.load(Ordering::Relaxed),
            known_capacity_bytes: owners.unique_known_capacity_bytes,
            unknown_capacity_payload_bytes: owners.unknown_capacity_payload_bytes,
            owners,
        }
    }
    /// Borrow one quiescent record roster into the caller's allocation ledger.
    /// No materialization, decoder, resolver or callback into this store runs.
    pub(crate) fn retained_census(&self, mut census: &mut HeapCensus) -> usize {
        let records = self
            .records
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        for record in records.values() {
            if !census.arc_object("session_symbolic.records", record) {
                continue;
            }
            census.slice("session_symbolic.keys", &record.key, true);
            if let Some(recipe) = &record.recipe {
                census.procedure_metadata("session_symbolic.key_metadata", &recipe.metadata);
            }
            census.retained_symbolic_ledger(&record.reads, &record.versions);
            match &record.value {
                super::RecordValue::Executable(artifact) => {
                    crate::symbolic::ReusableProcedureArtifact::retained_census(
                        artifact,
                        &mut census,
                    );
                }
                super::RecordValue::Selections { facts, abi } => {
                    census.vec_payload("session_symbolic.selection_abi", abi);
                    if census.arc_object("session_symbolic.selections", facts)
                        && census
                            .vec_payload("session_symbolic.selection_references", &facts.references)
                    {
                        for reference in &facts.references {
                            census.vec_payload("session_symbolic.selection_paths", &reference.path);
                        }
                    }
                }
            }
            census.vec_payload("session_symbolic.debug_offsets", &record.relative_debug);
            census.slice(
                "session_symbolic.required_types",
                &record.required_types,
                true,
            );
            if census.slice(
                "session_symbolic.modified_recipes",
                &record.modified_recipes,
                true,
            ) {
                for recipe in record.modified_recipes.iter() {
                    recipe.retained_census(&mut census);
                }
            }
        }
        self.receipt_groups
            .visit_storage(|pointer, payload, capacity| {
                census.exposed_buffer("session_symbolic.receipt_pool", pointer, payload, capacity);
            });
        census.unknown(
            "session_symbolic.receipt_pool",
            "weak leaf locators retain no read payload; private BTree node layout is not exposed",
        );
        census.unknown("session_symbolic.records", "BTreeMap index node capacity, Arc control blocks, allocator overhead and freed pages are not exposed; this is not private-memory measurement");
        records.len()
    }
}

#[cfg(test)]
#[path = "symbolic_retention_tests.rs"]
mod tests;
