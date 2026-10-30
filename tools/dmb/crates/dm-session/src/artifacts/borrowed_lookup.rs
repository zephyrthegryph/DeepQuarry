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
        validate: &mut dyn FnMut(&Receipt<Q, A, D>, &Arc<T>) -> Option<Q>,
        accept: &mut dyn FnMut(&Arc<T>) -> bool,
    ) -> (Option<(Arc<[u8]>, ObservedArtifact<T, Q, A, D>)>, Option<Q>) {
        self.try_visit_borrowed_receipted_with_value::<std::convert::Infallible>(
            digest,
            matches_key,
            &mut |reads, value| Ok(validate(reads, value)),
            &mut |value| Ok(accept(value)),
        )
        .unwrap_or_else(|impossible| match impossible {})
    }
    /// Fallible admission over the SAME exact-key candidate loop. An operation
    /// error exits before any candidate is admitted or claimed; no error/latch
    /// is retained by the store. Both callbacks still run outside core locks.
    pub fn try_visit_borrowed_receipted_with_value<E>(
        &self,
        digest: u128,
        matches_key: &dyn Fn(&[u8]) -> bool,
        validate: &mut dyn FnMut(&Receipt<Q, A, D>, &Arc<T>) -> Result<Option<Q>, E>,
        accept: &mut dyn FnMut(&Arc<T>) -> Result<bool, E>,
    ) -> Result<(Option<(Arc<[u8]>, ObservedArtifact<T, Q, A, D>)>, Option<Q>), E> {
        static LOOKUP: dm_profile::Accumulator =
            dm_profile::Accumulator::new("store.lookup_locked");
        let candidates = {
            let _lookup = LOOKUP.time();
            let state = self.state.read().unwrap_or_else(|error| error.into_inner());
            state
                .buckets
                .get(&digest)
                .into_iter()
                .flatten()
                .map(|entry| {
                    (
                        Arc::clone(&entry.key),
                        entry.reads.clone(),
                        Arc::clone(&entry.value),
                        entry.weight,
                    )
                })
                .collect::<Vec<_>>()
        };
        let mut changed = None;
        for (key, reads, value, weight) in candidates.into_iter().rev() {
            if !matches_key(&key) {
                continue;
            }
            if let Some(query) = validate(&reads, &value)? {
                changed = Some(query);
            } else if accept(&value)? {
                return Ok((
                    Some((
                        key,
                        ObservedArtifact {
                            value,
                            reads,
                            weight,
                        },
                    )),
                    None,
                ));
            }
        }
        Ok((None, changed))
    }
}
#[cfg(test)]
#[path = "borrowed_lookup_tests.rs"]
mod tests;
