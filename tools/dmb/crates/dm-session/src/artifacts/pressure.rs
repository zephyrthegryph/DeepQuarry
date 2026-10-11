//! Explicit performance-cache pruning, independent of publication identity.
use super::*;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct PressurePrune {
    /// Conservative logical charge, not physical process private bytes.
    pub charged_bytes: usize,
    pub payload_bytes: usize,
    /// Exposed bucket capacity plus modeled occupied scalar index slots.
    /// Private allocator/node capacity remains unmeasured.
    pub index_logical_bytes: usize,
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
            .insert_with_owned(Arc::from(b"known".as_slice()), vec![], vec![], 1, || {
                vec![7; 90]
            })
            .unwrap();
        let unknown = lease
            .insert_with_owned(Arc::from(b"unknown".as_slice()), vec![], vec![], 1, || {
                vec![8]
            })
            .unwrap();
        let report = store.prune_for_pressure(usize::MAX, |key, _, _, value| {
            let _ = store.admitted_bytes(); // callback must not hold the core lock
            (key.as_ref() == b"known").then_some(value.capacity())
        });
        assert_eq!(report.payload_bytes, 90);
        assert!(report.index_logical_bytes > 0);
        assert_eq!(
            report.charged_bytes,
            report.payload_bytes + report.index_logical_bytes
        );
        assert_eq!(report.retained_entries, 1);
        assert_eq!(report.evicted_entries, 1);
        assert_eq!(store.admitted_bytes(), report.charged_bytes);
        assert_eq!(unknown.as_slice(), &[8]);
        let rejected = store.prune_for_pressure(report.charged_bytes - 1, |_, _, _, value| {
            Some(value.capacity())
        });
        assert_eq!(rejected.retained_entries, 0);
        assert_eq!(rejected.evicted_entries, 1);
        assert_eq!(known.len(), 90);
        drop(lease); // pruned claims/rosters must not produce stale-drop panics
        assert_eq!(store.admitted_bytes(), 0);
    }

    #[test]
    fn pressure_cap_rechecks_claims_added_during_unlocked_payload_charge() {
        let store = ObservedArtifactStore::<Vec<u8>, u8, u8, u8>::shared_current_rosters();
        store.enable_incidence();
        let first = store.lease();
        let escaped = first
            .insert_with_owned(Arc::from(b"key".as_slice()), vec![], vec![], 1, || {
                vec![1; 8]
            })
            .unwrap();
        let original =
            store.prune_for_pressure(usize::MAX, |_, _, _, value| Some(value.capacity()));
        let second = store.lease();
        let rejected = store.prune_for_pressure(original.charged_bytes, |_, _, _, value| {
            let (accepted, changed) =
                second.visit_receipted_with(b"key", &mut |_, _| None, &mut |_| true);
            assert!(accepted.is_some());
            assert!(changed.is_none());
            Some(value.capacity())
        });
        assert_eq!(rejected.retained_entries, 0);
        assert_eq!(rejected.evicted_entries, 1);
        assert_eq!(store.admitted_bytes(), 0);
        assert_eq!(escaped.as_slice(), &[1; 8]);
        drop((first, second));
    }
}

impl<T, Q: Clone, A: Clone, D: Copy + Ord> ObservedArtifactStore<T, Q, A, D> {
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
            let charges = index_charges(&state);
            let charges_ref = &charges;
            state
                .buckets
                .values()
                .flat_map(|bucket| {
                    bucket.iter().map(move |entry| {
                        let pointer = Arc::as_ptr(&entry.value) as usize;
                        let index = charges_ref[&pointer];
                        (
                            Arc::clone(&entry.key),
                            entry.reads.clone(),
                            Arc::clone(&entry.versions),
                            Arc::clone(&entry.value),
                            index,
                        )
                    })
                })
                .collect()
        };
        let mut remaining = limit;
        let mut kept = BTreeMap::new();
        for (key, reads, versions, value, index) in &snapshot {
            if let Some(payload) = charge(key, reads, versions, value) {
                if let Some(weight) = payload
                    .checked_add(*index)
                    .filter(|weight| *weight <= remaining)
                {
                    remaining -= weight;
                    kept.insert(Arc::as_ptr(value) as usize, (payload, *index));
                }
            }
        }
        let mut detached = Vec::new();
        let mut report = PressurePrune::default();
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        // A callback may admit another lease or concurrent entry. Recheck the
        // current scalar backing before retaining any previously charged value.
        let current_charges = index_charges(&state);
        let mut remaining = limit;
        state.buckets.retain(|_, bucket| {
            let mut index = 0;
            while index < bucket.len() {
                let pointer = Arc::as_ptr(&bucket[index].value) as usize;
                let admitted = kept.get(&pointer).and_then(|(payload, _)| {
                    let bookkeeping = current_charges[&pointer];
                    let weight = payload.checked_add(bookkeeping)?;
                    (weight <= remaining).then_some((*payload, bookkeeping, weight))
                });
                if let Some((payload, bookkeeping, weight)) = admitted {
                    remaining -= weight;
                    bucket[index].weight = weight;
                    report.payload_bytes = report.payload_bytes.saturating_add(payload);
                    report.index_logical_bytes =
                        report.index_logical_bytes.saturating_add(bookkeeping);
                    report.charged_bytes =
                        report.charged_bytes.saturating_add(bucket[index].weight);
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

/// Occupied scalar slot plus a modeled link/control envelope. This deliberately
/// does not claim private BTree node or allocator capacity as measured bytes.
pub(super) fn scalar_slot<K, V>() -> usize {
    std::mem::size_of::<(K, V)>().saturating_add(2 * std::mem::size_of::<usize>())
}

fn index_charges<T, Q, A, D: Copy + Ord>(state: &Resident<T, Q, A, D>) -> BTreeMap<usize, usize> {
    let mut claims = BTreeMap::<usize, usize>::new();
    let mut lease_controls = BTreeMap::<usize, usize>::new();
    for roster in state.leases.values() {
        for pointer in roster.values() {
            *claims.entry(*pointer).or_default() += 1;
            let total = lease_controls.entry(*pointer).or_default();
            *total = total.saturating_add(scalar_slot::<u64, BTreeMap<Arc<[u8]>, usize>>());
        }
    }
    let mut charges = BTreeMap::new();
    for bucket in state.buckets.values() {
        // Charge shared scalar backing conservatively for every retained entry.
        // Removing other subscribers must not reduce this entry's coverage.
        let bucket_bytes = bucket
            .capacity()
            .saturating_mul(std::mem::size_of::<Variant<T, Q, A, D>>())
            .saturating_add(scalar_slot::<u128, Vec<Variant<T, Q, A, D>>>());
        for entry in bucket {
            let pointer = Arc::as_ptr(&entry.value) as usize;
            let mut index = bucket_bytes;
            index = index.saturating_add(
                claims
                    .get(&pointer)
                    .copied()
                    .unwrap_or(0)
                    .saturating_mul(scalar_slot::<Arc<[u8]>, usize>()),
            );
            index = index.saturating_add(lease_controls.get(&pointer).copied().unwrap_or(0));
            if state.claims.contains_key(&pointer) {
                index = index.saturating_add(scalar_slot::<usize, (u128, usize)>());
            }
            if let Some(incidence) = &state.incidence {
                index = index.saturating_add(incidence.pressure_charge(pointer as u64));
            }
            charges.insert(pointer, index);
        }
    }
    charges
}
