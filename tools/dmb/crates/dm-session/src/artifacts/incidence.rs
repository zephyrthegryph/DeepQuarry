//! Scheduling incidence only. Exact receipt admission remains mandatory.
use crate::{Observation, Receipt, ReceiptStorageView};
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};
type LeafId = (usize, usize);
struct Leaf<Q, A, D> {
    owner: Arc<[Observation<Q, A, D>]>,
    subscribers: BTreeSet<u64>,
    domains: BTreeSet<D>,
}
struct Variant<D> {
    bucket: u128,
    leaves: BTreeSet<LeafId>,
    certificates: BTreeSet<(D, u128)>,
    uncovered: BTreeSet<D>,
}
/// SAME live scheduling index. Addresses identify allocations, never validity.
pub(super) struct Incidence<Q, A, D> {
    leaves: BTreeMap<LeafId, Leaf<Q, A, D>>,
    variants: BTreeMap<u64, Variant<D>>,
    domains: BTreeMap<D, BTreeSet<LeafId>>,
    certificates: BTreeMap<(D, u128), BTreeSet<u64>>,
    uncovered: BTreeMap<D, BTreeSet<u64>>,
    conflicting: BTreeSet<u64>,
    // Drop of generic artifact owners has no domain trait bounds. Only the
    // Ord+Clone insertion path can populate this index and installs its exact
    // monomorphized removal operation; no callback or external policy is accepted.
    remove_ordered: Option<fn(&mut Self, u64)>,
    #[cfg(test)]
    pub(super) removal_visits: usize,
}
impl<Q, A, D> Default for Incidence<Q, A, D> {
    fn default() -> Self {
        Self {
            leaves: BTreeMap::new(),
            variants: BTreeMap::new(),
            domains: BTreeMap::new(),
            certificates: BTreeMap::new(),
            uncovered: BTreeMap::new(),
            conflicting: BTreeSet::new(),
            remove_ordered: None,
            #[cfg(test)]
            removal_visits: 0,
        }
    }
}
impl<Q, A, D> Incidence<Q, A, D> {
    pub(super) fn visit_storage(&self, mut visit: impl FnMut(&Arc<[Observation<Q, A, D>]>)) {
        for leaf in self.leaves.values() {
            visit(&leaf.owner);
        }
    }
    pub(super) fn counts(&self) -> (usize, usize, usize, usize) {
        (
            self.leaves.len(),
            self.variants.len(),
            self.domains.len(),
            self.leaves
                .values()
                .map(|leaf| leaf.subscribers.len())
                .sum(),
        )
    }
    pub(super) fn remove(&mut self, variant: u64) {
        if let Some(remove) = self.remove_ordered {
            remove(self, variant);
        }
    }
}
impl<Q, A, D: Ord + Clone> Incidence<Q, A, D> {
    fn remove_exact(&mut self, variant: u64) {
        let Some(previous) = self.variants.remove(&variant) else {
            return;
        };
        self.conflicting.remove(&variant);
        for domain in previous.uncovered {
            #[cfg(test)]
            {
                self.removal_visits += 1;
            }
            let members = self
                .uncovered
                .get_mut(&domain)
                .expect("indexed uncovered domain");
            members.remove(&variant);
            if members.is_empty() {
                self.uncovered.remove(&domain);
            }
        }
        for certificate in previous.certificates {
            #[cfg(test)]
            {
                self.removal_visits += 1;
            }
            let members = self
                .certificates
                .get_mut(&certificate)
                .expect("indexed certificate");
            members.remove(&variant);
            if members.is_empty() {
                self.certificates.remove(&certificate);
            }
        }
        for id in previous.leaves {
            let leaf = self.leaves.get_mut(&id).expect("indexed receipt leaf");
            leaf.subscribers.remove(&variant);
            if !leaf.subscribers.is_empty() {
                continue;
            }
            let leaf = self.leaves.remove(&id).expect("indexed receipt leaf");
            for domain in leaf.domains {
                let members = self.domains.get_mut(&domain).expect("indexed leaf domain");
                members.remove(&id);
                if members.is_empty() {
                    self.domains.remove(&domain);
                }
            }
        }
    }
    pub(super) fn insert(
        &mut self,
        variant: u64,
        bucket: u128,
        receipt: &Receipt<Q, A, D>,
        versions: &[(D, u128)],
    ) {
        if self.remove_ordered.is_none() {
            self.remove_ordered = Some(Self::remove_exact);
        }
        self.remove(variant);
        let mut ids = BTreeSet::new();
        receipt.visit_storage(|view| {
            let ReceiptStorageView::Flat(owner) = view else {
                return;
            };
            if owner.is_empty() {
                return;
            }
            let id = (owner.as_ptr() as usize, owner.len());
            if !ids.insert(id) {
                return;
            }
            let leaf = self.leaves.entry(id).or_insert_with(|| {
                let domains: BTreeSet<_> = owner.iter().map(|read| read.domain.clone()).collect();
                for domain in &domains {
                    self.domains.entry(domain.clone()).or_default().insert(id);
                }
                Leaf {
                    owner: owner.clone(),
                    subscribers: BTreeSet::new(),
                    domains,
                }
            });
            debug_assert!(Arc::ptr_eq(owner, &leaf.owner));
            leaf.subscribers.insert(variant);
        });
        let mut supplied = BTreeMap::new();
        for (domain, version) in versions {
            supplied
                .entry(domain.clone())
                .and_modify(|value: &mut Option<u128>| {
                    if *value != Some(*version) {
                        *value = None;
                    }
                })
                .or_insert(Some(*version));
        }
        let mut row = Variant {
            bucket,
            leaves: ids,
            certificates: BTreeSet::new(),
            uncovered: BTreeSet::new(),
        };
        let domains: BTreeSet<_> = receipt.iter().map(|read| read.domain.clone()).collect();
        for domain in domains {
            match supplied.get(&domain) {
                None => {
                    self.uncovered
                        .entry(domain.clone())
                        .or_default()
                        .insert(variant);
                    row.uncovered.insert(domain);
                }
                Some(None) => {
                    self.conflicting.insert(variant);
                }
                Some(Some(version)) => {
                    let certificate = (domain, *version);
                    self.certificates
                        .entry(certificate.clone())
                        .or_default()
                        .insert(variant);
                    row.certificates.insert(certificate);
                }
            }
        }
        self.variants.insert(variant, row);
    }
    pub(super) fn certificate_domains(&self) -> Vec<D> {
        self.certificates
            .keys()
            .map(|(domain, _)| domain.clone())
            .collect::<BTreeSet<_>>()
            .into_iter()
            .collect()
    }
    pub(super) fn certified(&self, current: &[(D, Option<u128>)]) -> BTreeSet<u64> {
        self.certified_with_local(current, None)
    }
    pub(super) fn certified_with_local(
        &self,
        current: &[(D, Option<u128>)],
        local: Option<&D>,
    ) -> BTreeSet<u64> {
        // Preserve the existing first-occurrence rule for duplicate current
        // domains, but index the request roster once instead of rescanning it.
        let mut versions = BTreeMap::new();
        for (domain, version) in current {
            versions.entry(domain.clone()).or_insert(*version);
        }
        let mut rejected = self.conflicting.clone();
        for (domain, members) in &self.uncovered {
            if local != Some(domain) {
                rejected.extend(members);
            }
        }
        for ((domain, version), members) in &self.certificates {
            if local != Some(domain) && versions.get(domain).copied().flatten() != Some(*version) {
                rejected.extend(members);
            }
        }
        self.variants
            .keys()
            .filter(|id| !rejected.contains(id))
            .copied()
            .collect()
    }
    pub(super) fn affected_buckets(&self, affected: &BTreeSet<u64>) -> BTreeSet<u128> {
        affected
            .iter()
            .filter_map(|id| self.variants.get(id).map(|row| row.bucket))
            .collect()
    }
    pub(super) fn affected<'a>(&self, domains: impl IntoIterator<Item = &'a D>) -> BTreeSet<u64>
    where
        D: 'a,
    {
        domains
            .into_iter()
            .filter_map(|domain| self.domains.get(domain))
            .flat_map(|ids| ids.iter())
            .flat_map(|id| self.leaves[id].subscribers.iter().copied())
            .collect()
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn shared_leaf_subscriptions_release_with_last_live_variant() {
        let leaf: Arc<[Observation<u8, bool, u8>]> = Arc::from([Observation {
            query: 1,
            answer: false,
            domain: 3,
        }]);
        let weak = Arc::downgrade(&leaf);
        let receipt = Receipt::from(leaf.clone());
        let mut index = Incidence::default();
        index.insert(1, 10, &receipt, &[(3, 0)]);
        index.insert(2, 20, &receipt, &[(3, 0)]);
        assert_eq!(index.leaves.len(), 1);
        assert_eq!(index.affected([&3]), BTreeSet::from([1, 2]));
        assert_eq!(
            index.affected_buckets(&index.affected([&3])),
            BTreeSet::from([10, 20])
        );
        index.remove(1);
        assert_eq!(index.affected([&3]), BTreeSet::from([2]));
        assert_eq!(
            index.affected_buckets(&index.affected([&3])),
            BTreeSet::from([20])
        );
        drop(receipt);
        drop(leaf);
        assert!(weak.upgrade().is_some());
        index.remove(2);
        assert!(weak.upgrade().is_none());
        assert!(index.domains.is_empty());
    }
}
