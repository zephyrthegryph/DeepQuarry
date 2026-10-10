//! Generic exact observations shared by authored and resolved semantic queries.
//! Ordering is canonical by query; absent answers are ordinary recorded values.
mod receipt;
mod receipt_pool;
pub use receipt::{Receipt, ReceiptIter, ReceiptStorageView};
pub use receipt_pool::ReceiptGroupPool;
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Mutex,
};
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Observation<Q, A, D> {
    pub domain: D,
    pub query: Q,
    pub answer: A,
}
struct State<Q, A, D> {
    reads: BTreeMap<Q, Vec<Observation<Q, A, D>>>,
    versions: BTreeMap<D, Option<u128>>,
}
pub struct ObservationLedger<Q, A, D> {
    state: Mutex<State<Q, A, D>>,
}
impl<Q, A, D> Default for ObservationLedger<Q, A, D> {
    fn default() -> Self {
        Self {
            state: Mutex::new(State {
                reads: BTreeMap::new(),
                versions: BTreeMap::new(),
            }),
        }
    }
}
impl<Q: Ord + Clone, A: Eq + Clone, D: Ord + Clone> ObservationLedger<Q, A, D> {
    /// Host evaluation occurs outside this lock. Inconsistent issuer versions
    /// permanently decline the domain shortcut for this recording session.
    pub fn record(&self, query: Q, answer: A, domain: D, version: Option<u128>) {
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        state
            .versions
            .entry(domain.clone())
            .and_modify(|previous| {
                if *previous != version {
                    *previous = None;
                }
            })
            .or_insert(version);
        let answers = state.reads.entry(query.clone()).or_default();
        if !answers
            .iter()
            .any(|read| read.domain == domain && read.answer == answer)
        {
            answers.push(Observation {
                domain,
                query,
                answer,
            });
        }
    }
    /// Distinguishes an unobserved domain from a known unversioned issuer.
    pub fn domain_receipt(&self, domain: &D) -> Option<Option<u128>> {
        self.state
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .versions
            .get(domain)
            .copied()
    }
    pub fn reads(&self) -> Vec<Observation<Q, A, D>> {
        self.state
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .reads
            .values()
            .flatten()
            .cloned()
            .collect()
    }
    pub fn domain_receipts(&self) -> Vec<(D, u128)> {
        self.state
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .versions
            .iter()
            .filter_map(|(domain, version)| version.map(|version| (domain.clone(), version)))
            .collect()
    }
}
/// Only complete immutable issuer receipts can bypass exact replay.
pub fn certified_domains<D: Ord + Clone>(
    versions: &[(D, u128)],
    mut current: impl FnMut(&D) -> Option<u128>,
) -> BTreeSet<D> {
    versions
        .iter()
        .filter_map(|(domain, version)| (current(domain) == Some(*version)).then(|| domain.clone()))
        .collect()
}
/// Equality is explicit so adapters retain their original canonical semantics.
pub fn first_changed<'a, Q, A, D: Ord>(
    reads: &'a [Observation<Q, A, D>],
    certified: &BTreeSet<D>,
    resolve: impl FnMut(&Q) -> A,
    equivalent: impl FnMut(&A, &A) -> bool,
) -> Option<&'a Q> {
    first_changed_iter(reads.iter(), certified, resolve, equivalent)
}
/// Replay the same exact admission rule over flat or shared canonical leaves.
pub fn first_changed_iter<'a, Q: 'a, A: 'a, D: Ord + 'a>(
    reads: impl IntoIterator<Item = &'a Observation<Q, A, D>>,
    certified: &BTreeSet<D>,
    mut resolve: impl FnMut(&Q) -> A,
    mut equivalent: impl FnMut(&A, &A) -> bool,
) -> Option<&'a Q> {
    reads
        .into_iter()
        .find(|read| {
            !certified.contains(&read.domain) && !equivalent(&resolve(&read.query), &read.answer)
        })
        .map(|read| &read.query)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn authored_store_uses_the_same_negative_replay_and_owner_lifetime() {
        struct Host(bool);
        impl ObservationHost<&'static str, Option<u32>, &'static str> for Host {
            fn answer(&self, _: &&'static str) -> Option<u32> {
                self.0.then_some(7)
            }
        }
        let store = crate::ObservedArtifactStore::<usize, &'static str, Option<u32>, &'static str>::current_revision();
        let key: std::sync::Arc<[u8]> = std::sync::Arc::from(b"owner".as_slice());
        store.insert_with(
            key.clone(),
            vec![Observation {
                domain: "authored",
                query: "absent",
                answer: None,
            }],
            Vec::new(),
            32,
            || 9,
        );
        let admitted = store.lookup(&key, &Host(false)).unwrap();
        assert_eq!(*admitted, 9);
        assert_eq!(store.lookup_explained(&key, &Host(true)).1, Some("absent"));
        store.retain_current_keys(std::iter::empty::<&[u8]>());
        assert!(store.lookup(&key, &Host(false)).is_none());
        assert_eq!(*admitted, 9);
    }
    #[test]
    fn negative_and_changed_answers_share_exact_replay() {
        let ledger = ObservationLedger::default();
        ledger.record("name", None::<u32>, "source", None);
        ledger.record("name", None::<u32>, "source", None);
        assert_eq!(ledger.reads().len(), 1);
        assert_eq!(
            first_changed(
                &ledger.reads(),
                &BTreeSet::new(),
                |_| Some(3),
                |a, b| a == b
            ),
            Some(&"name")
        );
        assert!(
            first_changed(&ledger.reads(), &BTreeSet::new(), |_| None, |a, b| a == b).is_none()
        );
    }
    #[test]
    fn inconsistent_versions_decline_shortcut_and_queries_are_ordered() {
        let ledger = ObservationLedger::default();
        ledger.record(2, 9, "source", Some(1));
        ledger.record(1, 8, "source", Some(2));
        ledger.record(3, 7, "source", Some(2));
        assert!(ledger.domain_receipts().is_empty());
        assert_eq!(
            ledger
                .reads()
                .iter()
                .map(|read| read.query)
                .collect::<Vec<_>>(),
            vec![1, 2, 3]
        );
    }
}

/// Immutable current host for either authored or resolved observations.
pub trait ObservationHost<Q, A: Eq, D> {
    fn answer(&self, query: &Q) -> A;
    fn version(&self, _domain: &D) -> Option<u128> {
        None
    }
    fn equivalent(&self, current: &A, previous: &A) -> bool {
        current == previous
    }
}
impl<R: dm_ir::Resolver>
    ObservationHost<dm_ir::ResolveQuery, dm_ir::ResolvedMeaning, dm_ir::ReadDomain> for R
{
    fn answer(&self, query: &dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        self.resolve(*query)
    }
    fn version(&self, domain: &dm_ir::ReadDomain) -> Option<u128> {
        self.domain_version(*domain)
    }
    fn equivalent(
        &self,
        current: &dm_ir::ResolvedMeaning,
        previous: &dm_ir::ResolvedMeaning,
    ) -> bool {
        current.canonical_bytes() == previous.canonical_bytes()
    }
}
