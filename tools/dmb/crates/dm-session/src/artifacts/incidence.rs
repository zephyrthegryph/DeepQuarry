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
}
/// Owned by Resident, under its existing lock. Variant addresses identify only
/// live store allocations; removal precedes destruction. They are not proof.
pub(super) struct Incidence<Q, A, D> {
    leaves: BTreeMap<LeafId, Leaf<Q, A, D>>,
    variants: BTreeMap<u64, (u128, BTreeSet<LeafId>)>,
    domains: Vec<(D, BTreeSet<LeafId>)>,
    certificates: Vec<(D, u128, BTreeSet<u64>)>,
    uncovered: BTreeSet<u64>,
}
impl<Q, A, D> Default for Incidence<Q, A, D> {
    fn default() -> Self {
        Self {
            leaves: BTreeMap::new(),
            variants: BTreeMap::new(),
            domains: Vec::new(),
            certificates: Vec::new(),
            uncovered: BTreeSet::new(),
        }
    }
}
impl<Q, A, D> Incidence<Q, A, D> {
    pub(super) fn visit_storage(&self, mut visit: impl FnMut(&Arc<[Observation<Q, A, D>]>)) {
        for leaf in self.leaves.values() {
            visit(&leaf.owner);
        }
    }
    pub(super) fn domain_buffer(&self) -> (usize, usize, usize) {
        let size = std::mem::size_of::<(D, BTreeSet<LeafId>)>();
        (
            self.domains.as_ptr() as usize,
            self.domains.len() * size,
            self.domains.capacity() * size,
        )
    }
    pub(super) fn certificate_buffer(&self) -> (usize, usize, usize) {
        let size = std::mem::size_of::<(D, u128, BTreeSet<u64>)>();
        (
            self.certificates.as_ptr() as usize,
            self.certificates.len() * size,
            self.certificates.capacity() * size,
        )
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
        self.uncovered.remove(&variant);
        self.certificates.retain_mut(|(_, _, members)| {
            members.remove(&variant);
            !members.is_empty()
        });
        let Some((_, ids)) = self.variants.remove(&variant) else {
            return;
        };
        for id in ids {
            let leaf = self.leaves.get_mut(&id).expect("indexed receipt leaf");
            leaf.subscribers.remove(&variant);
            if !leaf.subscribers.is_empty() {
                continue;
            }
            let _leaf = self.leaves.remove(&id).expect("indexed receipt leaf");
            self.domains.retain_mut(|(_, members)| {
                members.remove(&id);
                !members.is_empty()
            });
        }
    }
}
impl<Q, A, D: Ord + Clone> Incidence<Q, A, D> {
    pub(super) fn insert(
        &mut self,
        variant: u64,
        bucket: u128,
        receipt: &Receipt<Q, A, D>,
        versions: &[(D, u128)],
    ) {
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
                    match self
                        .domains
                        .binary_search_by(|(current, _)| current.cmp(domain))
                    {
                        Ok(position) => {
                            self.domains[position].1.insert(id);
                        }
                        Err(position) => {
                            self.domains
                                .insert(position, (domain.clone(), BTreeSet::from([id])));
                        }
                    }
                }
                Leaf {
                    owner: owner.clone(),
                    subscribers: BTreeSet::new(),
                }
            });
            // The retained owner prevents address recycling while indexed.
            debug_assert!(Arc::ptr_eq(owner, &leaf.owner));
            leaf.subscribers.insert(variant);
        });
        self.variants.insert(variant, (bucket, ids));
        let domains: BTreeSet<_> = receipt.iter().map(|read| read.domain.clone()).collect();
        for domain in domains {
            let mut supplied = versions
                .iter()
                .filter(|(d, _)| d == &domain)
                .map(|(_, v)| *v);
            let Some(version) = supplied.next() else {
                self.uncovered.insert(variant);
                continue;
            };
            if supplied.any(|other| other != version) {
                self.uncovered.insert(variant);
                continue;
            }
            match self
                .certificates
                .binary_search_by(|(d, v, _)| (d, *v).cmp(&(&domain, version)))
            {
                Ok(position) => {
                    self.certificates[position].2.insert(variant);
                }
                Err(position) => self
                    .certificates
                    .insert(position, (domain, version, BTreeSet::from([variant]))),
            }
        }
    }
    pub(super) fn certificate_domains(&self) -> Vec<D> {
        self.certificates
            .iter()
            .map(|(domain, _, _)| domain.clone())
            .collect::<BTreeSet<_>>()
            .into_iter()
            .collect()
    }
    // Current versions are supplied by the existing immutable request admission.
    pub(super) fn certified(&self, current: &[(D, Option<u128>)]) -> BTreeSet<u64> {
        let mut rejected = self.uncovered.clone();
        for (domain, version, members) in &self.certificates {
            if current
                .iter()
                .find(|(d, _)| d == domain)
                .and_then(|(_, v)| *v)
                != Some(*version)
            {
                rejected.extend(members);
            }
        }
        self.variants
            .keys()
            .filter(|id| !rejected.contains(id))
            .copied()
            .collect()
    }
    /// Route live variants into their existing store buckets. Hashes locate only;
    /// callers still check live allocation identity and perform exact admission.
    pub(super) fn affected_buckets(&self, affected: &BTreeSet<u64>) -> BTreeSet<u128> {
        affected
            .iter()
            .filter_map(|id| self.variants.get(id).map(|(bucket, _)| *bucket))
            .collect()
    }
    /// Each supplied domain includes all its subscribed variants. Callers must
    /// include every unversioned/unproved domain, not just known changed ones.
    /// This result cannot authorize replay omission or return producer values.
    pub(super) fn affected<'a>(&self, domains: impl IntoIterator<Item = &'a D>) -> BTreeSet<u64>
    where
        D: 'a,
    {
        domains
            .into_iter()
            .filter_map(|domain| {
                self.domains
                    .binary_search_by(|(current, _)| current.cmp(domain))
                    .ok()
                    .map(|position| &self.domains[position].1)
            })
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
        index.insert(1, 10, &receipt);
        index.insert(2, 20, &receipt);
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
