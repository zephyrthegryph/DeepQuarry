//! Explicit performance-cache pruning, independent of publication identity.
use super::*;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct PressurePrune {
    /// Conservative logical charge, not physical process private bytes.
    pub charged_bytes: usize,
    pub retained_entries: usize,
    pub evicted_entries: usize,
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn pressure_prune_recharges_same_core_and_detaches_claims_outside_callback_lock() {
        let store = ObservedArtifactStore::<Vec<u8>, u8, u8, u8>::shared_current_rosters();
        store.enable_incidence();
        let lease = store.lease();
        let known = lease
            .insert_with(Arc::from(b"known".as_slice()), vec![], vec![], 1, || {
                vec![7; 90]
            })
            .unwrap();
        let unknown = lease
            .insert_with(Arc::from(b"unknown".as_slice()), vec![], vec![], 1, || {
                vec![8]
            })
            .unwrap();
        let report = store.prune_for_pressure(100, |key, _, _, value| {
            let _ = store.admitted_bytes(); // callback must not hold the core lock
            (key.as_ref() == b"known").then_some(value.capacity())
        });
        assert_eq!(
            report,
            PressurePrune {
                charged_bytes: 90,
                retained_entries: 1,
                evicted_entries: 1
            }
        );
        assert_eq!(store.admitted_bytes(), 90);
        assert_eq!(unknown.as_slice(), &[8]);
        let rejected = store.prune_for_pressure(89, |_, _, _, value| Some(value.capacity()));
        assert_eq!(rejected.retained_entries, 0);
        assert_eq!(rejected.evicted_entries, 1);
        assert_eq!(known.len(), 90);
        drop(lease); // pruned claims/rosters must not produce stale-drop panics
        assert_eq!(store.admitted_bytes(), 0);
    }
}

impl<T, Q: Clone, A: Clone, D: Clone> ObservedArtifactStore<T, Q, A, D> {
    /// Charge complete payloads outside the core lock, then prune the SAME
    /// entries and lease incidence. Unknown/oversized/new concurrent entries
    /// decline retention. Call at an idle boundary; escaped readers remain valid.
    /// Shared backing may be charged repeatedly across entries conservatively.
    pub fn prune_for_pressure(
        &self,
        limit: usize,
        mut charge: impl FnMut(
            &Arc<[u8]>,
            &Receipt<Q, A, D>,
            &Arc<[(D, u128)]>,
            &Arc<T>,
        ) -> Option<usize>,
    ) -> PressurePrune {
        // Receipt::clone shares immutable Flat/Groups Arc backing; no answer or
        // query array is copied here. Only per-entry handles are allocated.
        let snapshot: Vec<_> = {
            let state = self.state.lock().unwrap_or_else(|error| error.into_inner());
            state
                .buckets
                .values()
                .flatten()
                .map(|entry| {
                    (
                        Arc::clone(&entry.key),
                        entry.reads.clone(),
                        Arc::clone(&entry.versions),
                        Arc::clone(&entry.value),
                    )
                })
                .collect()
        };
        let mut remaining = limit;
        let mut kept = BTreeMap::new();
        for (key, reads, versions, value) in &snapshot {
            if let Some(weight) =
                charge(key, reads, versions, value).filter(|weight| *weight <= remaining)
            {
                remaining -= weight;
                kept.insert(Arc::as_ptr(value) as usize, weight);
            }
        }
        let mut detached = Vec::new();
        let mut report = PressurePrune::default();
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        state.buckets.retain(|_, bucket| {
            let mut index = 0;
            while index < bucket.len() {
                let pointer = Arc::as_ptr(&bucket[index].value) as usize;
                if let Some(weight) = kept.get(&pointer) {
                    bucket[index].weight = *weight;
                    report.charged_bytes = report.charged_bytes.saturating_add(*weight);
                    report.retained_entries += 1;
                    index += 1;
                } else {
                    detached.push(bucket.remove(index));
                    report.evicted_entries += 1;
                }
            }
            !bucket.is_empty()
        });
        let removed: std::collections::BTreeSet<_> = detached
            .iter()
            .map(|entry| Arc::as_ptr(&entry.value) as usize)
            .collect();
        for roster in state.leases.values_mut() {
            roster.retain(|_, claimed| !removed.contains(claimed));
        }
        for entry in &detached {
            let pointer = Arc::as_ptr(&entry.value) as usize;
            state.claims.remove(&pointer);
            if let Some(index) = &mut state.incidence {
                index.remove(pointer as u64);
            }
        }
        state.bytes = report.charged_bytes;
        drop(state);
        drop(detached);
        drop(snapshot);
        report
    }
}
