//! Transactional allocation union for one idle pressure pass, on the same core.
use super::*;
use std::sync::Weak;

/// Exposed live backing identity and conservative logical bytes. Addresses are
/// ephemeral accounting facts, never semantic keys or serialized authority.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct PressureAllocation {
    pub address: usize,
    pub bytes: usize,
}
struct Footprint<T> {
    witness: Weak<T>,
    allocations: Vec<PressureAllocation>,
    standalone: usize,
}
fn additions(
    ledger: &BTreeMap<usize, usize>,
    allocations: &[PressureAllocation],
) -> Option<(usize, BTreeMap<usize, usize>)> {
    let mut pending = BTreeMap::new();
    let mut bytes = 0usize;
    for allocation in allocations {
        if allocation.bytes == 0 {
            continue;
        }
        if allocation.address == 0 {
            return None;
        }
        if let Some(old) = ledger
            .get(&allocation.address)
            .or_else(|| pending.get(&allocation.address))
        {
            if *old != allocation.bytes {
                return None;
            }
        } else {
            bytes = bytes.checked_add(allocation.bytes)?;
            pending.insert(allocation.address, allocation.bytes);
        }
    }
    Some((bytes, pending))
}
impl<T, Q: Clone, A: Clone, D: Copy + Ord> ObservedArtifactStore<T, Q, A, D> {
    /// Deduplicate shared exposed allocations transactionally. Unknown footprints
    /// decline. Callback walks one borrowed current payload outside the lock.
    /// The callback must expose immutable backing whose identity and size cannot
    /// change while its current payload/receipt remains resident. Interior-
    /// mutable or otherwise unproven backing must decline with `None`.
    /// Allocation-vector capacity is bounded by `limit`; weak roster and tree
    /// bookkeeping add scratch overhead. This is not a physical scratch bound
    /// and does not retain a whole strong payload roster.
    /// Entry weights remain standalone conservative charges, so subsequent
    /// ordinary eviction cannot leave surviving shared backing undercharged.
    pub fn prune_for_pressure_shared(
        &self,
        limit: usize,
        mut footprint: impl FnMut(
            &Arc<[u8]>,
            &Receipt<Q, A, D>,
            &Arc<[(D, u128)]>,
            &Arc<T>,
            usize,
        ) -> Option<Vec<PressureAllocation>>,
    ) -> PressurePrune {
        let snapshot: Vec<_> = {
            let state = self.state.lock().unwrap_or_else(|e| e.into_inner());
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
        let mut retained: BTreeMap<usize, Footprint<T>> = BTreeMap::new();
        let mut ledger = BTreeMap::new();
        let mut total = 0usize;
        let mut charged_buckets = std::collections::BTreeSet::new();
        let mut scratch = 0usize;
        let mut evicted = 0usize;
        for (hash, weak) in &snapshot {
            let candidate = {
                let state = self.state.lock().unwrap_or_else(|e| e.into_inner());
                state
                    .buckets
                    .get(hash)
                    .and_then(|bucket| {
                        bucket
                            .iter()
                            .position(|entry| {
                                std::ptr::eq(Arc::as_ptr(&entry.value), weak.as_ptr())
                            })
                            .map(|position| (position, &bucket[position]))
                    })
                    .map(|(position, entry)| {
                        (
                            entry.key.clone(),
                            entry.reads.clone(),
                            entry.versions.clone(),
                            entry.value.clone(),
                            total
                                .checked_add(shared_index_charge(
                                    &state,
                                    *hash,
                                    position,
                                    charged_buckets.contains(hash),
                                ))
                                .is_some_and(|next| next <= limit),
                        )
                    })
            };
            let Some((key, reads, versions, value, index_fits)) = candidate else {
                continue;
            };
            let allocations = if index_fits {
                footprint(&key, &reads, &versions, &value, limit)
            } else {
                None
            };
            let detached = {
                let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
                let position = state.buckets.get(hash).and_then(|bucket| {
                    bucket
                        .iter()
                        .position(|entry| std::ptr::eq(Arc::as_ptr(&entry.value), weak.as_ptr()))
                });
                if let Some(position) = position {
                    let index = shared_index_charge(
                        &state,
                        *hash,
                        position,
                        charged_buckets.contains(hash),
                    );
                    let accepted = allocations.and_then(|allocations| {
                        let next_scratch = scratch.checked_add(
                            allocations
                                .capacity()
                                .checked_mul(std::mem::size_of::<PressureAllocation>())?,
                        )?;
                        if next_scratch > limit {
                            return None;
                        }
                        let (delta, pending) = additions(&ledger, &allocations)?;
                        let next = total.checked_add(index)?.checked_add(delta)?;
                        if next > limit {
                            return None;
                        }
                        let (standalone, _) = additions(&BTreeMap::new(), &allocations)?;
                        standalone.checked_add(index)?;
                        Some((allocations, next_scratch, next, pending, standalone))
                    });
                    if let Some((allocations, next_scratch, next, pending, standalone)) = accepted {
                        // Commit only after exact current identity/index validation.
                        ledger.extend(pending);
                        charged_buckets.insert(*hash);
                        total = next;
                        scratch = next_scratch;
                        retained.insert(
                            weak.as_ptr() as usize,
                            Footprint {
                                witness: weak.clone(),
                                allocations,
                                standalone,
                            },
                        );
                        None
                    } else {
                        evicted += 1;
                        detach(&mut state, *hash, position)
                    }
                } else {
                    None
                }
            };
            drop(detached);
        }
        drop(snapshot);
        drop(ledger);
        // Rebuild membership under the same lock from surviving exact records.
        // Outside-lock drops can add rows/claims or remove the first shared owner;
        // every wave transfers charges to the next actual survivor naturally.
        loop {
            let (victims, complete) = {
                let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
                let mut ledger = BTreeMap::new();
                let mut charged_buckets = std::collections::BTreeSet::new();
                let mut report = PressurePrune {
                    evicted_entries: evicted,
                    ..Default::default()
                };
                let mut victims = Vec::new();
                for (hash, bucket) in &state.buckets {
                    for (position, entry) in bucket.iter().enumerate() {
                        let pointer = Arc::as_ptr(&entry.value) as usize;
                        let index = shared_index_charge(
                            &state,
                            *hash,
                            position,
                            charged_buckets.contains(hash),
                        );
                        let accepted = retained
                            .get(&pointer)
                            .filter(|item| {
                                std::ptr::eq(item.witness.as_ptr(), Arc::as_ptr(&entry.value))
                            })
                            .and_then(|item| additions(&ledger, &item.allocations))
                            .and_then(|(delta, pending)| {
                                report
                                    .charged_bytes
                                    .checked_add(index)?
                                    .checked_add(delta)
                                    .filter(|total| *total <= limit)
                                    .map(|total| (delta, pending, total))
                            });
                        if let Some((delta, pending, total)) = accepted {
                            ledger.extend(pending);
                            charged_buckets.insert(*hash);
                            report.charged_bytes = total;
                            report.payload_bytes += delta;
                            report.index_logical_bytes += index;
                            report.retained_entries += 1;
                        } else {
                            victims.push((*hash, Arc::downgrade(&entry.value)));
                        }
                    }
                }
                if victims.is_empty() {
                    let mut weights = Vec::new();
                    let mut standalone_total = 0usize;
                    for (hash, bucket) in &state.buckets {
                        for (position, entry) in bucket.iter().enumerate() {
                            let charge = retained[&(Arc::as_ptr(&entry.value) as usize)]
                                .standalone
                                .saturating_add(entry_index_charge(&state, *hash, position));
                            standalone_total = standalone_total.saturating_add(charge);
                            weights.push((*hash, position, charge));
                        }
                    }
                    for (hash, position, weight) in weights {
                        state.buckets.get_mut(&hash).unwrap()[position].weight = weight;
                    }
                    state.bytes = standalone_total;
                    (victims, Some(report))
                } else {
                    (victims, None)
                }
            };
            if let Some(report) = complete {
                return report;
            }
            for (hash, weak) in victims {
                let detached = {
                    let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
                    detach_weak(&mut state, hash, &weak)
                };
                if detached.is_some() {
                    evicted += 1;
                }
                drop(detached);
            }
            // No allocation address from a detached owner remains authoritative.
            let state = self.state.lock().unwrap_or_else(|e| e.into_inner());
            let current: std::collections::BTreeSet<_> = state
                .buckets
                .values()
                .flat_map(|bucket| {
                    bucket
                        .iter()
                        .map(|entry| Arc::as_ptr(&entry.value) as usize)
                })
                .collect();
            retained.retain(|pointer, _| current.contains(pointer));
        }
    }
}

fn shared_index_charge<T, Q, A, D: Copy + Ord>(
    state: &Resident<T, Q, A, D>,
    hash: u128,
    position: usize,
    bucket_already_charged: bool,
) -> usize {
    let full = entry_index_charge(state, hash, position);
    if !bucket_already_charged {
        return full;
    }
    let bucket = &state.buckets[&hash];
    let envelope = bucket
        .capacity()
        .saturating_mul(std::mem::size_of::<Variant<T, Q, A, D>>())
        .saturating_add(scalar_slot::<u128, Vec<Variant<T, Q, A, D>>>());
    full.saturating_sub(envelope)
}
#[cfg(test)]
#[path = "pressure_shared_tests.rs"]
mod tests;
