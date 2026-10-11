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
impl<T: Send + Sync, Q: Clone + Ord, A: Clone + Eq, D: Clone + Ord>
    ObservedArtifactStore<T, Q, A, D>
{
    /// No resolver or local-input callback runs under the store lock. Missing or
    /// conflicting producer versions remain uncovered. This only proves reads;
    /// current source/ABI/config and output bindings are separate mandatory guards.
    pub fn unchanged_candidates<'request, 'host, H: ObservationHost<Q, A, D>>(
        &self,
        request: &'request ReceiptAdmission<'host, Q, A, D, H>,
    ) -> Vec<UnchangedCandidate<'request, 'host, T, Q, A, D, H>> {
        if !request.allows_certificate_reuse() {
            return Vec::new();
        }
        let domains = {
            let state = self.state.lock().unwrap_or_else(|e| e.into_inner());
            let Some(index) = &state.incidence else {
                return Vec::new();
            };
            index.certificate_domains()
        };
        let current: Vec<_> = domains
            .into_iter()
            .map(|domain| {
                let version = request.current_version(&domain);
                (domain, version)
            })
            .collect();
        let state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        let Some(index) = &state.incidence else {
            return Vec::new();
        };
        let certified = index.certified(&current);
        let mut candidates = Vec::new();
        for bucket in index.affected_buckets(&certified) {
            for entry in state.buckets.get(&bucket).into_iter().flatten() {
                if !certified.contains(&(Arc::as_ptr(&entry.value) as usize as u64)) {
                    continue;
                }
                candidates.push(UnchangedCandidate {
                    key: Arc::clone(&entry.key),
                    artifact: Some(ObservedArtifact {
                        value: Arc::clone(&entry.value),
                        reads: entry.reads.clone(),
                        versions: Arc::clone(&entry.versions),
                        weight: entry.weight,
                    }),
                    _request: request,
                });
            }
        }
        candidates
    }
}

/// A request-local snapshot, not retained history or another artifact cache.
/// Taken candidates keep their exact locator slot; unrelated workers can consume
/// different keys without reconstructing the store's canonical read ledgers.
pub struct UnchangedCandidates<'request, 'host, T, Q, A: Eq, D, H> {
    candidates: Vec<UnchangedCandidate<'request, 'host, T, Q, A, D, H>>,
}
impl<'request, 'host, T, Q, A: Eq, D, H> UnchangedCandidates<'request, 'host, T, Q, A, D, H> {
    /// Prefix selection is routing only. Every selected token still requires
    /// complete current key/local-input licensing before exposing its value.
    pub fn take_prefix(
        &mut self,
        prefix: &[u8],
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
impl<T: Send + Sync, Q: Clone + Ord, A: Clone + Eq, D: Clone + Ord>
    ObservedArtifactStore<T, Q, A, D>
{
    pub fn unchanged_candidate_roster<'request, 'host, H: ObservationHost<Q, A, D>>(
        &self,
        request: &'request ReceiptAdmission<'host, Q, A, D, H>,
    ) -> UnchangedCandidates<'request, 'host, T, Q, A, D, H> {
        let mut candidates = self.unchanged_candidates(request);
        candidates.sort_by(|a, b| a.key.cmp(&b.key));
        UnchangedCandidates { candidates }
    }
}
