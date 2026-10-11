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
            .prune_for_pressure_with_budget(limit, |key, _, _, record, allowance| {
                charge(key, record, allowance)
            })
    }
}

fn charge(
    key: &std::sync::Arc<[u8]>,
    record: &std::sync::Arc<super::super::Record>,
    limit: usize,
) -> Option<usize> {
    let mut census = HeapCensus::compact_symbolic_charge(limit);
    census.slice("compact_symbolic.locator", key, true);
    census_record(record, &mut census);
    census.finish_compact_symbolic_charge()
}

#[cfg(test)]
#[path = "symbolic_pressure_tests.rs"]
mod tests;
