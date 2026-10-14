//! Exact local input differences are independent of semantic read coverage.
//! This conservative producer never certifies any resolver domain unchanged.
use std::collections::BTreeMap;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DependencyCoverage {
    UncoveredAll,
}

#[derive(Debug, PartialEq, Eq)]
pub struct InputDelta<K> {
    added: Vec<K>,
    removed: Vec<K>,
    changed: Vec<K>,
}
impl<K: Ord + Clone> InputDelta<K> {
    /// Compare complete producer inputs, not hashes or arena identifiers.
    /// Duplicate keys decline rather than silently replacing an input.
    pub fn between<I: Eq>(
        previous: impl IntoIterator<Item = (K, I)>,
        current: impl IntoIterator<Item = (K, I)>,
    ) -> Result<Self, K> {
        fn collect<K: Ord + Clone, I>(
            rows: impl IntoIterator<Item = (K, I)>,
        ) -> Result<BTreeMap<K, I>, K> {
            let mut result = BTreeMap::new();
            for (key, value) in rows {
                if result.insert(key.clone(), value).is_some() {
                    return Err(key);
                }
            }
            Ok(result)
        }
        let previous = collect(previous)?;
        let current = collect(current)?;
        Ok(Self {
            added: current
                .keys()
                .filter(|key| !previous.contains_key(*key))
                .cloned()
                .collect(),
            removed: previous
                .keys()
                .filter(|key| !current.contains_key(*key))
                .cloned()
                .collect(),
            changed: current
                .iter()
                .filter(|(key, value)| previous.get(*key).is_some_and(|old| old != *value))
                .map(|(key, _)| key.clone())
                .collect(),
        })
    }
    pub fn added(&self) -> &[K] {
        &self.added
    }
    pub fn removed(&self) -> &[K] {
        &self.removed
    }
    pub fn changed(&self) -> &[K] {
        &self.changed
    }
    pub fn dependency_coverage(&self) -> DependencyCoverage {
        DependencyCoverage::UncoveredAll
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn exact_input_changes_do_not_certify_negative_or_external_reads() {
        let delta = InputDelta::between(
            [(1, "same"), (2, "old"), (4, "removed")],
            [(1, "same"), (2, "new"), (3, "added")],
        )
        .unwrap();
        assert_eq!(delta.added(), &[3]);
        assert_eq!(delta.removed(), &[4]);
        assert_eq!(delta.changed(), &[2]);
        assert_eq!(
            delta.dependency_coverage(),
            DependencyCoverage::UncoveredAll
        );
        assert!(InputDelta::between([(1, "a"), (1, "b")], []).is_err());
    }
}
