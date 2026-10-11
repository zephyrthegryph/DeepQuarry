//! Explicit performance-cache pruning, independent of publication identity.
use super::*;

#[cfg(test)]
#[path = "pressure_lifecycle_tests.rs"]
mod lifecycle_tests;

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
    fn rejected_payload_is_dropped_before_next_charge_callback() {
        use std::sync::atomic::{AtomicUsize, Ordering};
        struct Payload(Arc<AtomicUsize>);
        impl Drop for Payload {
            fn drop(&mut self) {
                self.0.fetch_add(1, Ordering::SeqCst);
            }
        }
        let drops = Arc::new(AtomicUsize::new(0));
        let store = ObservedArtifactStore::<Payload, u8, u8, u8>::shared_current_rosters();
        let lease = store.lease();
        for key in [b"first".as_slice(), b"second".as_slice()] {
            drop(
                lease
                    .insert_with_owned(Arc::from(key), vec![], vec![], 1, || {
                        Payload(Arc::clone(&drops))
                    })
                    .unwrap(),
            );
        }
        let mut calls = 0;
        let report = store.prune_for_pressure(0, |_, _, _, _| {
            assert_eq!(drops.load(Ordering::SeqCst), calls);
            calls += 1;
            None
        });
        assert_eq!(calls, 2);
        assert_eq!(drops.load(Ordering::SeqCst), 2);
        assert_eq!(report.evicted_entries, 2);
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
        // Weak identities prevent allocator-address reuse without pinning payloads.
        // This scalar roster is the only whole-store temporary allocation; receipt
        // and payload owners are borrowed one candidate at a time.
        let snapshot: Vec<_> = {
            let state = self.state.lock().unwrap_or_else(|error| error.into_inner());
            state
                .buckets
                .iter()
                .flat_map(|(hash, bucket)| {
                    bucket
                        .iter()
                        .map(move |entry| (*hash, Arc::downgrade(&entry.value)))
                })
                .collect()
        };
        let mut remaining = limit;
        let mut retained = BTreeMap::new();
        let mut evicted = 0;
        for (hash, weak) in &snapshot {
            let pointer = weak.as_ptr() as usize;
            let candidate = {
                let state = self.state.lock().unwrap_or_else(|error| error.into_inner());
                state
                    .buckets
                    .get(hash)
                    .and_then(|bucket| {
                        bucket
                            .iter()
                            .find(|entry| Arc::as_ptr(&entry.value) as usize == pointer)
                    })
                    .map(|entry| {
                        (
                            Arc::clone(&entry.key),
                            entry.reads.clone(),
                            Arc::clone(&entry.versions),
                            Arc::clone(&entry.value),
                        )
                    })
            };
            let Some((key, reads, versions, value)) = candidate else {
                continue;
            };
            let payload = charge(&key, &reads, &versions, &value);
            let detached = {
                let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
                let position = state.buckets.get(hash).and_then(|bucket| {
                    bucket
                        .iter()
                        .position(|entry| Arc::as_ptr(&entry.value) as usize == pointer)
                });
                if let Some(position) = position {
                    // Recheck current claim/index backing after the unlocked callback.
                    let index = entry_index_charge(&state, *hash, position);
                    if let Some(weight) = payload
                        .and_then(|payload| payload.checked_add(index))
                        .filter(|weight| *weight <= remaining)
                    {
                        remaining -= weight;
                        let entry = &mut state.buckets.get_mut(hash).unwrap()[position];
                        let old_weight = entry.weight;
                        entry.weight = weight;
                        state.bytes = state
                            .bytes
                            .saturating_sub(old_weight)
                            .saturating_add(weight);
                        retained.insert(pointer, payload.unwrap());
                        None
                    } else {
                        evicted += 1;
                        detach(&mut state, *hash, position)
                    }
                } else {
                    None
                }
            };
            // Release this payload, its receipt and detached index ownership now,
            // rather than accumulating all evicted payloads until traversal ends.
            drop(detached);
        }
        // A single scalar cursor walks buckets without restarting at the first
        // retained row for each removal. Destruction remains outside the lock.
        let mut cursor = None;
        let mut position = 0;
        let mut remaining = limit;
        let mut report = PressurePrune {
            evicted_entries: evicted,
            ..PressurePrune::default()
        };
        loop {
            let (done, detached) = {
                let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
                let hash = match cursor {
                    None => state.buckets.keys().next().copied(),
                    Some(hash) => state.buckets.range(hash..).next().map(|(hash, _)| *hash),
                };
                if let Some(hash) = hash {
                    if cursor != Some(hash) {
                        position = 0;
                        cursor = Some(hash);
                    }
                    if position >= state.buckets[&hash].len() {
                        cursor = hash.checked_add(1);
                        position = 0;
                        (hash == u128::MAX, None)
                    } else {
                        let pointer = Arc::as_ptr(&state.buckets[&hash][position].value) as usize;
                        let index = entry_index_charge(&state, hash, position);
                        let admitted = retained.get(&pointer).and_then(|payload| {
                            payload
                                .checked_add(index)
                                .filter(|weight| *weight <= remaining)
                                .map(|weight| (*payload, weight))
                        });
                        if let Some((payload, weight)) = admitted {
                            remaining -= weight;
                            let entry = &mut state.buckets.get_mut(&hash).unwrap()[position];
                            let old_weight = entry.weight;
                            entry.weight = weight;
                            state.bytes = state
                                .bytes
                                .saturating_sub(old_weight)
                                .saturating_add(weight);
                            report.charged_bytes = report.charged_bytes.saturating_add(weight);
                            report.index_logical_bytes =
                                report.index_logical_bytes.saturating_add(index);
                            report.payload_bytes = report.payload_bytes.saturating_add(payload);
                            report.retained_entries += 1;
                            position += 1;
                            (false, None)
                        } else {
                            report.evicted_entries += 1;
                            (false, detach(&mut state, hash, position))
                        }
                    }
                } else {
                    (true, None)
                }
            };
            drop(detached);
            if done {
                break;
            }
        }
        report
    }
}

/// Occupied scalar slot plus a modeled link/control envelope. This deliberately
/// does not claim private BTree node or allocator capacity as measured bytes.
pub(super) fn scalar_slot<K, V>() -> usize {
    std::mem::size_of::<(K, V)>().saturating_add(2 * std::mem::size_of::<usize>())
}

fn entry_index_charge<T, Q, A, D: Copy + Ord>(
    state: &Resident<T, Q, A, D>,
    hash: u128,
    position: usize,
) -> usize {
    let bucket = &state.buckets[&hash];
    let pointer = Arc::as_ptr(&bucket[position].value) as usize;
    let mut bytes = bucket
        .capacity()
        .saturating_mul(std::mem::size_of::<Variant<T, Q, A, D>>())
        .saturating_add(scalar_slot::<u128, Vec<Variant<T, Q, A, D>>>());
    if let Some((_, claims)) = state.claims.get(&pointer) {
        bytes = bytes
            .saturating_add(
                claims.saturating_mul(
                    scalar_slot::<Arc<[u8]>, usize>()
                        .saturating_add(scalar_slot::<u64, BTreeMap<Arc<[u8]>, usize>>()),
                ),
            )
            .saturating_add(scalar_slot::<usize, (u128, usize)>());
    }
    if let Some(incidence) = &state.incidence {
        bytes = bytes.saturating_add(incidence.pressure_charge(pointer as u64));
    }
    bytes
}

fn detach<T, Q, A, D>(
    state: &mut Resident<T, Q, A, D>,
    hash: u128,
    position: usize,
) -> Option<Variant<T, Q, A, D>> {
    let bucket = state.buckets.get_mut(&hash)?;
    let entry = bucket.remove(position);
    if bucket.is_empty() {
        state.buckets.remove(&hash);
    }
    let pointer = Arc::as_ptr(&entry.value) as usize;
    for roster in state.leases.values_mut() {
        if roster.get(&entry.key) == Some(&pointer) {
            roster.remove(&entry.key);
        }
    }
    state.claims.remove(&pointer);
    if let Some(index) = &mut state.incidence {
        index.remove(pointer as u64);
    }
    state.bytes = state.bytes.saturating_sub(entry.weight);
    Some(entry)
}
