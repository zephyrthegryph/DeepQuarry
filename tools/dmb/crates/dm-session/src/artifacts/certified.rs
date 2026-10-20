//! Request-bound proof over the same live artifact and subscription owners.
use super::*;
use crate::ReceiptAdmission;

/// Strong candidate storage prevents address recycling; the borrowed request
/// prevents transferring this proof to another immutable resolver revision.
/// The value remains private until exact key and current local inputs are licensed.
pub struct UnchangedCandidate<'request, 'host, T, Q, A: Eq, D, H> {
    key: Arc<[u8]>,
    artifact: Option<ObservedArtifact<T, Q, A, D>>,
    _request: &'request ReceiptAdmission<'host, Q, A, D, H>,
}
impl<T, Q, A: Eq, D, H> UnchangedCandidate<'_, '_, T, Q, A, D, H> {
    pub fn admit(
        self,
        key: &[u8],
        locally_current: impl FnOnce(&Arc<T>) -> bool,
        mut observed: impl FnMut(&Arc<[Observation<Q, A, D>]>),
    ) -> Option<ObservedArtifact<T, Q, A, D>> {
        self.admit_current(
            |actual, value| actual == key && locally_current(value),
            &mut observed,
        )
        .map(|(_, artifact)| artifact)
    }
    /// The caller must license the complete current local inputs for this exact
    /// producer key; a prefix alone is never admission authority.
    pub fn admit_current(
        mut self,
        locally_current: impl FnOnce(&[u8], &Arc<T>) -> bool,
        mut observed: impl FnMut(&Arc<[Observation<Q, A, D>]>),
    ) -> Option<(Arc<[u8]>, ObservedArtifact<T, Q, A, D>)> {
        let artifact = self.artifact.take()?;
        if !locally_current(&self.key, &artifact.value) {
            return None;
        }
        artifact.reads.visit_storage(|view| {
            if let crate::ReceiptStorageView::Flat(leaf) = view {
                observed(leaf);
            }
        });
        Some((self.key, artifact))
    }
}
impl<T, Q: Clone, A: Clone, D> ObservedArtifactStore<T, Q, A, D> {
    /// Every stored variant with its recorded reads, for an external validity proof
    /// (the query database's answer comparison). Strong owners are cloned under the
    /// read lock; no host callback runs under it.
    pub fn variant_snapshot(&self) -> Vec<(Arc<[u8]>, ObservedArtifact<T, Q, A, D>)> {
        let state = self.state.read().unwrap_or_else(|e| e.into_inner());
        state
            .buckets
            .values()
            .flatten()
            .map(|entry| {
                (
                    Arc::clone(&entry.key),
                    ObservedArtifact {
                        value: Arc::clone(&entry.value),
                        reads: entry.reads.clone(),
                        versions: Arc::clone(&entry.versions),
                        weight: entry.weight,
                    },
                )
            })
            .collect()
    }
}
/// A request-local snapshot, not retained history or another artifact cache.
/// Taken candidates keep their exact locator slot; unrelated workers can consume
/// different keys without reconstructing the store's canonical read ledgers.
pub struct UnchangedCandidates<'request, 'host, T, Q, A: Eq, D, H> {
    candidates: Vec<UnchangedCandidate<'request, 'host, T, Q, A, D, H>>,
}
impl<'request, 'host, T, Q, A: Eq, D, H> UnchangedCandidates<'request, 'host, T, Q, A, D, H> {
    /// Candidates proven unchanged by the caller (every recorded answer equals the
    /// current answer of `request`'s host), in key order. The same exact-key and
    /// local-input admission still applies to each before its value is exposed.
    pub fn from_proven(
        request: &'request ReceiptAdmission<'host, Q, A, D, H>,
        proven: Vec<(Arc<[u8]>, ObservedArtifact<T, Q, A, D>)>,
    ) -> Self {
        let mut candidates: Vec<_> = proven
            .into_iter()
            .map(|(key, artifact)| UnchangedCandidate {
                key,
                artifact: Some(artifact),
                _request: request,
            })
            .collect();
        candidates.sort_by(|a, b| a.key.cmp(&b.key));
        Self { candidates }
    }
    /// Prefix selection is routing only. Every selected token still requires
    /// complete current key/local-input licensing before exposing its value.
    pub fn take_prefix(
        &mut self,
        prefix: &[u8],
    ) -> Vec<UnchangedCandidate<'request, 'host, T, Q, A, D, H>> {
        self.take_prefix_if(prefix, |_| true)
    }
    /// Values of the still-present candidates under `prefix`, with their slots,
    /// in key order. Lets a caller run its routing predicate without holding
    /// whatever lock guards this roster, then consume the chosen slots with
    /// [`take_slots`](Self::take_slots).
    /// Partition into `count` key-ordered rosters by `shard(key)`, so callers that
    /// route every lookup by the same shard function stop sharing one lock.
    pub fn split_by(self, count: usize, shard: impl Fn(&[u8]) -> usize) -> Vec<Self> {
        let mut parts: Vec<Vec<_>> = (0..count.max(1)).map(|_| Vec::new()).collect();
        let total = parts.len();
        for candidate in self.candidates {
            let index = shard(&candidate.key) % total;
            parts[index].push(candidate);
        }
        parts.into_iter().map(|candidates| Self { candidates }).collect()
    }
    pub fn prefix_values(&self, prefix: &[u8]) -> Vec<(usize, Arc<T>)> {
        let start = self
            .candidates
            .partition_point(|candidate| candidate.key.as_ref() < prefix);
        self.candidates[start..]
            .iter()
            .take_while(|candidate| candidate.key.starts_with(prefix))
            .enumerate()
            .filter_map(|(offset, candidate)| {
                Some((start + offset, Arc::clone(&candidate.artifact.as_ref()?.value)))
            })
            .collect()
    }
    /// Consume the given slots, in the order given. A slot already consumed by
    /// another caller is skipped, exactly like a declined `take_prefix_if` row.
    pub fn take_slots(
        &mut self,
        slots: &[usize],
    ) -> Vec<UnchangedCandidate<'request, 'host, T, Q, A, D, H>> {
        slots
            .iter()
            .filter_map(|&slot| {
                let candidate = self.candidates.get_mut(slot)?;
                Some(UnchangedCandidate {
                    key: Arc::clone(&candidate.key),
                    artifact: Some(candidate.artifact.take()?),
                    _request: candidate._request,
                })
            })
            .collect()
    }
    /// Borrow a local routing predicate without consuming declined tokens.
    /// This exposes no admitted output: selected tokens still require the same
    /// exact-key/local-input admission and pending lease claim.
    pub fn take_prefix_if(
        &mut self,
        prefix: &[u8],
        mut qualify: impl FnMut(&Arc<T>) -> bool,
    ) -> Vec<UnchangedCandidate<'request, 'host, T, Q, A, D, H>> {
        let start = self
            .candidates
            .partition_point(|candidate| candidate.key.as_ref() < prefix);
        let end = start
            + self.candidates[start..]
                .iter()
                .take_while(|candidate| candidate.key.starts_with(prefix))
                .count();
        self.candidates[start..end]
            .iter_mut()
            .rev()
            .filter_map(|candidate| {
                if !qualify(&candidate.artifact.as_ref()?.value) {
                    return None;
                }
                Some(UnchangedCandidate {
                    key: Arc::clone(&candidate.key),
                    artifact: Some(candidate.artifact.take()?),
                    _request: candidate._request,
                })
            })
            .collect()
    }
    pub fn take(&mut self, key: &[u8]) -> Vec<UnchangedCandidate<'request, 'host, T, Q, A, D, H>> {
        let start = self
            .candidates
            .partition_point(|candidate| candidate.key.as_ref() < key);
        let end = self
            .candidates
            .partition_point(|candidate| candidate.key.as_ref() <= key);
        self.candidates[start..end]
            .iter_mut()
            .rev()
            .filter_map(|candidate| {
                Some(UnchangedCandidate {
                    key: Arc::clone(&candidate.key),
                    artifact: Some(candidate.artifact.take()?),
                    _request: candidate._request,
                })
            })
            .collect()
    }
}
