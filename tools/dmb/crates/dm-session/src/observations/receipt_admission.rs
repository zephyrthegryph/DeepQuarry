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
/// The borrowed host has the existing ObservationHost immutable-current contract.
/// Never retain this owner across a source/resolver revision. Cached verdicts
/// identify strongly retained immutable leaf storage, not semantic pointer keys.
pub struct ReceiptAdmission<'host, Q, A, D, H> {
    host: &'host H,
    leaves: Mutex<BTreeMap<(usize, usize), Verdict<Q, A, D>>>,
}
impl<'host, Q: Clone, A: Eq, D: Ord, H: ObservationHost<Q, A, D>>
    ReceiptAdmission<'host, Q, A, D, H>
{
    pub fn new(host: &'host H) -> Self {
        Self {
            host,
            leaves: Mutex::new(BTreeMap::new()),
        }
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
        // No domain shortcut: sharing an exact leaf does not prove two artifacts
        // carried the same issuer-version roster. Resolve through the common core.
        let changed = super::first_changed_iter(
            leaf.iter(),
            &Default::default(),
            |query| self.host.answer(query),
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
