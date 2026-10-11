//! Idle-only logical payload pruning in the existing observed artifact core.
use super::*;

impl SessionSymbolicMemo {
    pub(crate) fn compact_for_pressure(&self, limit: usize) -> dm_session::PressurePrune {
        self.release_bound_images();
        if let Some(pool) = &self.shared_code_pool {
            pool.release_for_pressure();
        }
        let Some(owner) = &self.publication else {
            // Standalone legacy maps have no lease-aware pressure publication.
            let mut records = self.records.lock().unwrap_or_else(|e| e.into_inner());
            let evicted_entries = records.len();
            let detached = std::mem::take(&mut *records);
            drop(records);
            drop(detached);
            return dm_session::PressurePrune {
                evicted_entries,
                ..Default::default()
            };
        };
        owner
            .values
            .prune_for_pressure(limit, |key, _, _, record| charge(key, record))
    }
}

fn charge(
    key: &std::sync::Arc<[u8]>,
    record: &std::sync::Arc<super::super::Record>,
) -> Option<usize> {
    let mut census = HeapCensus::new("compact_symbolic_charge");
    census.slice("compact_symbolic.locator", key, true);
    census_record(record, &mut census);
    // This one annotation concerns allocator/control bookkeeping only, not
    // omitted nested payload. Charge each encountered owner conservatively below.
    census
        .owner("procedure_metadata.recipe")
        .unknown
        .remove("Arc control block and allocator overhead are unavailable");
    let encounters = census.buffer_encounters;
    let report = census.finish();
    if report.unknown_capacity_payload_bytes != 0
        || report.owners.iter().any(|owner| !owner.unknown.is_empty())
    {
        return None;
    }
    usize::try_from(report.unique_known_capacity_bytes)
        .ok()?
        .checked_add(encounters.checked_mul(64)?)?
        // Per-record logical index/lease bookkeeping allowance. Private BTree
        // and incidence backing is not a measured allocation or a physical cap.
        .checked_add(4096)
}

#[cfg(test)]
#[path = "symbolic_pressure_tests.rs"]
mod tests;
