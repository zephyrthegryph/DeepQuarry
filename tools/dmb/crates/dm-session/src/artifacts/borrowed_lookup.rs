//! Borrowed locator admission in the existing ordered variant bucket.
use super::*;
impl<T: Send + Sync, Q: Clone + Ord, A: Clone + Eq, D: Clone + Ord>
    ObservedArtifactStore<T, Q, A, D>
{
    /// Digest selects a bucket only. The producer must compare the complete
    /// current key before receipt validation; callbacks execute outside locks.
    /// The accepted key is the SAME immutable stored owner, never caller bytes.
    pub fn visit_borrowed_receipted_with_value(
        &self,
        digest: u128,
        matches_key: &dyn Fn(&[u8]) -> bool,
        validate: &mut dyn FnMut(&Receipt<Q, A, D>, &[(D, u128)], &Arc<T>) -> Option<Q>,
        accept: &mut dyn FnMut(&Arc<T>) -> bool,
    ) -> (Option<(Arc<[u8]>, ObservedArtifact<T, Q, A, D>)>, Option<Q>) {
        let candidates = {
            let state = self.state.lock().unwrap_or_else(|error| error.into_inner());
            state
                .buckets
                .get(&digest)
                .into_iter()
                .flatten()
                .map(|entry| {
                    (
                        Arc::clone(&entry.key),
                        entry.reads.clone(),
                        Arc::clone(&entry.versions),
                        Arc::clone(&entry.value),
                        entry.weight,
                    )
                })
                .collect::<Vec<_>>()
        };
        let mut changed = None;
        for (key, reads, versions, value, weight) in candidates.into_iter().rev() {
            if !matches_key(&key) {
                continue;
            }
            if let Some(query) = validate(&reads, &versions, &value) {
                changed = Some(query);
            } else if accept(&value) {
                return (
                    Some((
                        key,
                        ObservedArtifact {
                            value,
                            reads,
                            versions,
                            weight,
                        },
                    )),
                    None,
                );
            }
        }
        (None, changed)
    }
}
#[cfg(test)]
#[path = "borrowed_lookup_tests.rs"]
mod tests;
