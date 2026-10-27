//! Exact admission shared only within one immutable host request.
use super::{Observation, ObservationHost, Receipt, ReceiptStorageView};
use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
};

struct Verdict<Q, A, D> {
    owner: Arc<[Observation<Q, A, D>]>,
    changed: Option<Q>,
}
/// Private proof bound to the SAME current admission host. It is issued only
/// after every observation in this leaf passed exact or qualified admission.
struct AdmittedLeaf<'a, Q, A, D, H> {
    host: &'a H,
    owner: &'a Arc<[Observation<Q, A, D>]>,
}
impl<Q, A: Eq, D, H: ObservationHost<Q, A, D>> AdmittedLeaf<'_, Q, A, D, H> {
    fn deliver(self) {
        if self.host.supports_admitted_observation() {
            for read in self.owner.iter() {
                self.host.observe_admitted(read);
            }
        }
    }
}
/// The borrowed host has the existing ObservationHost immutable-current contract.
/// Never retain this owner across a source/resolver revision. Cached verdicts
/// identify strongly retained immutable leaf storage, not semantic pointer keys.
pub struct ReceiptAdmission<'host, Q, A, D, H> {
    host: &'host H,
    oracle: Option<&'host dyn super::AnswerOracle<Q, A>>,
    leaves: Mutex<BTreeMap<(usize, usize), Verdict<Q, A, D>>>,
}
impl<'host, Q: Clone, A: Eq, D, H: ObservationHost<Q, A, D>>
    ReceiptAdmission<'host, Q, A, D, H>
{
    pub fn host(&self) -> &'host H {
        self.host
    }
    /// Whether receipts are proven by an answer table (`with_oracle`) rather than by replaying each answer.
    pub fn has_oracle(&self) -> bool {
        self.oracle.is_some() && self.allows_certificate_reuse()
    }
    pub fn allows_certificate_reuse(&self) -> bool {
        !self.host.observes_answers() || self.host.supports_admitted_observation()
    }
    pub fn new(host: &'host H) -> Self {
        Self::with_oracle(host, None)
    }
    /// Receipts are proven by `oracle`'s current answers instead of replaying them through the host.
    pub fn with_oracle(
        host: &'host H,
        oracle: Option<&'host dyn super::AnswerOracle<Q, A>>,
    ) -> Self {
        Self {
            host,
            oracle,
            leaves: Mutex::new(BTreeMap::new()),
        }
    }
    /// The ordinary artifact admission rule: every recorded answer is proven, by the oracle when the request has one
    /// and holds it, else by replaying it through the host, in canonical order. A partial success never seeds the
    /// full-answer leaf verdict cache used by `first_changed`.
    pub fn first_changed_receipted(
        &self,
        receipt: &Receipt<Q, A, D>,
        mut admitted: impl FnMut(&Arc<[Observation<Q, A, D>]>),
    ) -> Option<Q> {
        static ITERATE: dm_profile::Accumulator = dm_profile::Accumulator::new("admission.iterate");
        static DELIVER: dm_profile::Accumulator = dm_profile::Accumulator::new("admission.deliver");
        // An observing host must see every answer it is asked for unless it accepts admitted leaves.
        let oracle = self.oracle.filter(|_| self.allows_certificate_reuse());
        let mut changed = None;
        receipt.visit_storage(|view| {
            if changed.is_some() {
                return;
            }
            if let ReceiptStorageView::Flat(leaf) = view {
                let iterate_timer = ITERATE.time();
                changed = match oracle {
                    Some(oracle) => leaf
                        .iter()
                        .find(|read| match oracle.unchanged(&read.query, &read.answer) {
                            Some(unchanged) => !unchanged,
                            // Not an answer the oracle holds (a producer input): compare it.
                            None => !self.host.equivalent(
                                &self.host.answer_for_admission(&read.query),
                                &read.answer,
                            ),
                        })
                        .map(|read| read.query.clone()),
                    None => super::first_changed_iter(
                        leaf.iter(),
                        |query| self.host.answer_for_admission(query),
                        |current, previous| self.host.equivalent(current, previous),
                    )
                    .cloned(),
                };
                drop(iterate_timer);
                if changed.is_none() {
                    let _deliver = DELIVER.time();
                    AdmittedLeaf {
                        host: self.host,
                        owner: leaf,
                    }
                    .deliver();
                    admitted(leaf);
                }
            }
        });
        changed
    }
    /// Every accepted leaf reaches the observer, including memo hits. A recording
    /// adapter can preserve the shared leaf directly without dropping read edges.
    /// No resolver or observer callback runs under the admission lock. Concurrent
    /// first readers may validate twice; immutable answers make both equivalent.
    pub fn first_changed(
        &self,
        receipt: &Receipt<Q, A, D>,
        mut admitted: impl FnMut(&Arc<[Observation<Q, A, D>]>),
    ) -> Option<Q> {
        let mut changed = None;
        receipt.visit_storage(|view| {
            if changed.is_some() {
                return;
            }
            if let ReceiptStorageView::Flat(leaf) = view {
                changed = self.leaf_changed(leaf);
                if changed.is_none() {
                    AdmittedLeaf {
                        host: self.host,
                        owner: leaf,
                    }
                    .deliver();
                    admitted(leaf);
                }
            }
        });
        changed
    }
    fn leaf_changed(&self, leaf: &Arc<[Observation<Q, A, D>]>) -> Option<Q> {
        let key = (leaf.as_ptr() as usize, leaf.len());
        {
            let leaves = self
                .leaves
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            if let Some(verdict) = leaves.get(&key) {
                debug_assert!(Arc::ptr_eq(&verdict.owner, leaf));
                return verdict.changed.clone();
            }
        }
        let changed = super::first_changed_iter(
            leaf.iter(),
            |query| self.host.answer_for_admission(query),
            |current, previous| self.host.equivalent(current, previous),
        )
        .cloned();
        self.leaves
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .entry(key)
            .or_insert_with(|| Verdict {
                owner: Arc::clone(leaf),
                changed: changed.clone(),
            });
        changed
    }
    /// Borrowed diagnostic access. Private BTree node capacity is not exposed.
    pub fn visit_storage(&self, mut visit: impl FnMut(&Arc<[Observation<Q, A, D>]>)) {
        let owners: Vec<_> = self
            .leaves
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .values()
            .map(|value| Arc::clone(&value.owner))
            .collect();
        for owner in &owners {
            visit(owner);
        }
    }
}

#[cfg(test)]
#[path = "receipt_admission_tests.rs"]
mod tests;

