//! Request-bound proof over the same live artifact and subscription owners.
use super::*;
use crate::ReceiptAdmission;

/// Strong candidate storage prevents address recycling; the borrowed request
/// prevents transferring this proof to another immutable resolver revision.
/// The value remains private until exact key and current local inputs are licensed.
pub struct UnchangedCandidate<'request, 'host, T, Q, A: Eq, D, H> {
    key: Arc<[u8]>,
    artifact: ObservedArtifact<T, Q, A, D>,
    _request: &'request ReceiptAdmission<'host, Q, A, D, H>,
}
impl<T, Q, A: Eq, D, H> UnchangedCandidate<'_, '_, T, Q, A, D, H> {
    pub fn admit(
        self,
        key: &[u8],
        locally_current: impl FnOnce(&Arc<T>) -> bool,
        mut observed: impl FnMut(&Arc<[Observation<Q, A, D>]>),
    ) -> Option<ObservedArtifact<T, Q, A, D>> {
        if self.key.as_ref() != key || !locally_current(&self.artifact.value) {
            return None;
        }
        self.artifact.reads.visit_storage(|view| {
            if let crate::ReceiptStorageView::Flat(leaf) = view {
                observed(leaf);
            }
        });
        Some(self.artifact)
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
                    artifact: ObservedArtifact {
                        value: Arc::clone(&entry.value),
                        reads: entry.reads.clone(),
                        versions: Arc::clone(&entry.versions),
                        weight: entry.weight,
                    },
                    _request: request,
                });
            }
        }
        candidates
    }
}
