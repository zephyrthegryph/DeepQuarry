//! Scheduling incidence only. Exact receipt admission remains mandatory.
use crate::{Observation, Receipt, ReceiptStorageView};
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};
type LeafId = (usize, usize);
/// Dense id of one interned read domain. A domain (a resolver query) is tens of bytes and every leaf,
/// variant and reverse map used to hold its own clone: about 1.4 GB for the DeepQuarry lowering store.
/// The tables below hold 4-byte ids and this interner holds the one clone of each domain.
type DomainId = u32;
struct Interner<D> {
    ids: BTreeMap<Arc<D>, DomainId>,
    table: Vec<Arc<D>>,
}
impl<D> Default for Interner<D> {
    fn default() -> Self {
        Self {
            ids: BTreeMap::new(),
            table: Vec::new(),
        }
    }
}
impl<D: Ord + Clone> Interner<D> {
    fn id(&mut self, domain: &D) -> DomainId {
        if let Some(id) = self.ids.get(domain) {
            return *id;
        }
        let id = DomainId::try_from(self.table.len()).expect("fewer than 2^32 read domains");
        let shared = Arc::new(domain.clone());
        self.ids.insert(Arc::clone(&shared), id);
        self.table.push(shared);
        id
    }
    fn get(&self, domain: &D) -> Option<DomainId> {
        self.ids.get(domain).copied()
    }
    fn domain(&self, id: DomainId) -> &D {
        self.table[id as usize].as_ref()
    }
}
/// A distinct set of variant ids. Most sets here hold a handful of ids, where a `BTreeSet` still allocates a full node, so a
/// small set is a sorted `Vec`; a set past `SMALL_IDS` (a domain read by thousands of variants) becomes a `BTreeSet` so a
/// removal never moves a long tail.
#[derive(Clone)]
enum Ids {
    Small(Vec<u64>),
    Large(BTreeSet<u64>),
}
const SMALL_IDS: usize = 32;
impl Default for Ids {
    fn default() -> Self {
        Self::Small(Vec::new())
    }
}
impl Ids {
    fn insert(&mut self, id: u64) {
        match self {
            Self::Small(ids) => {
                if let Err(at) = ids.binary_search(&id) {
                    if ids.len() < SMALL_IDS {
                        ids.insert(at, id);
                    } else {
                        let mut large: BTreeSet<u64> = ids.drain(..).collect();
                        large.insert(id);
                        *self = Self::Large(large);
                    }
                }
            }
            Self::Large(ids) => {
                ids.insert(id);
            }
        }
    }
    fn remove(&mut self, id: &u64) {
        match self {
            Self::Small(ids) => {
                if let Ok(at) = ids.binary_search(id) {
                    ids.remove(at);
                }
            }
            Self::Large(ids) => {
                ids.remove(id);
            }
        }
    }
    fn is_empty(&self) -> bool {
        self.len() == 0
    }
    fn len(&self) -> usize {
        match self {
            Self::Small(ids) => ids.len(),
            Self::Large(ids) => ids.len(),
        }
    }
    fn iter(&self) -> Box<dyn Iterator<Item = &u64> + '_> {
        match self {
            Self::Small(ids) => Box::new(ids.iter()),
            Self::Large(ids) => Box::new(ids.iter()),
        }
    }
}
impl<'a> IntoIterator for &'a Ids {
    type Item = &'a u64;
    type IntoIter = Box<dyn Iterator<Item = &'a u64> + 'a>;
    fn into_iter(self) -> Self::IntoIter {
        self.iter()
    }
}
struct Leaf<Q, A, D> {
    owner: Arc<[Observation<Q, A, D>]>,
    subscribers: Ids,
}
/// A variant's rows never change after insertion (an update removes and reinserts it), so they are sorted boxed slices: a
/// `BTreeSet` node is allocated for even one element (hundreds of bytes per set, three sets per variant, 87k+ variants).
struct Variant {
    bucket: u128,
    leaves: Box<[LeafId]>,
    certificates: Box<[(DomainId, u128)]>,
    uncovered: Box<[DomainId]>,
}
/// SAME live scheduling index. Addresses identify allocations, never validity.
pub(super) struct Incidence<Q, A, D> {
    interner: Interner<D>,
    leaves: BTreeMap<LeafId, Leaf<Q, A, D>>,
    variants: BTreeMap<u64, Variant>,
    certificates: BTreeMap<(DomainId, u128), Ids>,
    uncovered: BTreeMap<DomainId, Ids>,
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
            interner: Interner::default(),
            leaves: BTreeMap::new(),
            variants: BTreeMap::new(),
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
    pub(super) fn pressure_charge(&self, variant: u64) -> usize
    where
        D: Ord,
    {
        use super::pressure::scalar_slot;
        let Some(row) = self.variants.get(&variant) else {
            return 0;
        };
        let mut bytes = scalar_slot::<u64, Variant>()
            .saturating_add(row.leaves.len().saturating_mul(std::mem::size_of::<LeafId>()))
            .saturating_add(
                row.certificates
                    .len()
                    .saturating_mul(std::mem::size_of::<(DomainId, u128)>()),
            )
            .saturating_add(
                row.uncovered
                    .len()
                    .saturating_mul(std::mem::size_of::<DomainId>()),
            );
        for id in &row.leaves {
            if let Some(leaf) = self.leaves.get(id) {
                let _ = leaf;
                bytes = bytes
                    .saturating_add(scalar_slot::<LeafId, Leaf<Q, A, D>>())
                    .saturating_add(scalar_slot::<u64, ()>());
            }
        }
        for certificate in &row.certificates {
            if self.certificates.contains_key(certificate) {
                bytes = bytes
                    .saturating_add(scalar_slot::<(DomainId, u128), Ids>())
                    .saturating_add(scalar_slot::<u64, ()>());
            }
        }
        for domain in &row.uncovered {
            if self.uncovered.contains_key(domain) {
                bytes = bytes
                    .saturating_add(scalar_slot::<DomainId, Ids>())
                    .saturating_add(scalar_slot::<u64, ()>());
            }
        }
        if self.conflicting.contains(&variant) {
            bytes = bytes.saturating_add(scalar_slot::<u64, ()>());
        }
        bytes
    }
    pub(super) fn visit_storage(&self, mut visit: impl FnMut(&Arc<[Observation<Q, A, D>]>)) {
        for leaf in self.leaves.values() {
            visit(&leaf.owner);
        }
    }
    pub(super) fn counts(&self) -> (usize, usize, usize, usize) {
        // The third value is the number of distinct domains referenced by live variants (certified or uncovered).
        let mut domains: BTreeSet<DomainId> = self.uncovered.keys().copied().collect();
        domains.extend(self.certificates.keys().map(|(domain, _)| *domain));
        (
            self.leaves.len(),
            self.variants.len(),
            domains.len(),
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
        for domain in previous.uncovered.into_vec() {
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
        for certificate in previous.certificates.into_vec() {
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
        for id in previous.leaves.into_vec() {
            let leaf = self.leaves.get_mut(&id).expect("indexed receipt leaf");
            leaf.subscribers.remove(&variant);
            if !leaf.subscribers.is_empty() {
                continue;
            }
            self.leaves.remove(&id).expect("indexed receipt leaf");
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
            let leaf = self.leaves.entry(id).or_insert_with(|| Leaf {
                owner: owner.clone(),
                subscribers: Ids::default(),
            });
            debug_assert!(Arc::ptr_eq(owner, &leaf.owner));
            leaf.subscribers.insert(variant);
        });
        let domains: BTreeSet<DomainId> = receipt
            .iter()
            .map(|read| self.interner.id(&read.domain))
            .collect();
        // Every receipt domain is interned above; a supplied version for any other domain cannot matter.
        let mut supplied: BTreeMap<DomainId, Option<u128>> = BTreeMap::new();
        for (domain, version) in versions {
            let Some(domain) = self.interner.get(domain) else {
                continue;
            };
            supplied
                .entry(domain)
                .and_modify(|value: &mut Option<u128>| {
                    if *value != Some(*version) {
                        *value = None;
                    }
                })
                .or_insert(Some(*version));
        }
        let mut certificates = Vec::new();
        let mut uncovered = Vec::new();
        // `domains` is a BTreeSet, so both lists come out sorted and distinct.
        for domain in domains {
            match supplied.get(&domain) {
                None => {
                    self.uncovered.entry(domain).or_default().insert(variant);
                    uncovered.push(domain);
                }
                Some(None) => {
                    self.conflicting.insert(variant);
                }
                Some(Some(version)) => {
                    let certificate = (domain, *version);
                    self.certificates
                        .entry(certificate)
                        .or_default()
                        .insert(variant);
                    certificates.push(certificate);
                }
            }
        }
        let row = Variant {
            bucket,
            leaves: ids.into_iter().collect(),
            certificates: certificates.into_boxed_slice(),
            uncovered: uncovered.into_boxed_slice(),
        };
        self.variants.insert(variant, row);
    }
    pub(super) fn certificate_domains(&self) -> Vec<D> {
        self.certificates
            .keys()
            .map(|(domain, _)| *domain)
            .collect::<BTreeSet<_>>()
            .into_iter()
            .map(|domain| self.interner.domain(domain).clone())
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
        // A current domain that was never interned matches no stored certificate.
        let mut versions = BTreeMap::new();
        for (domain, version) in current {
            if let Some(domain) = self.interner.get(domain) {
                versions.entry(domain).or_insert(*version);
            }
        }
        let local = local.and_then(|domain| self.interner.get(domain));
        let mut rejected = self.conflicting.clone();
        for (domain, members) in &self.uncovered {
            if local != Some(*domain) {
                rejected.extend(members);
            }
        }
        for ((domain, version), members) in &self.certificates {
            if local != Some(*domain) && versions.get(domain).copied().flatten() != Some(*version)
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
    /// Diagnostic only: which domains keep variants out of the unchanged roster.
    /// Returns (description, member count) for uncovered domains and for
    /// versioned domains whose current version differs, largest first.
    pub(super) fn rejection_summary(&self, current: &[(D, Option<u128>)]) -> Vec<(String, usize)>
    where
        D: std::fmt::Debug,
    {
        let mut versions = BTreeMap::new();
        for (domain, version) in current {
            if let Some(domain) = self.interner.get(domain) {
                versions.entry(domain).or_insert(*version);
            }
        }
        let mut rows: Vec<(String, usize)> = Vec::new();
        rows.push(("conflicting".into(), self.conflicting.len()));
        for (domain, members) in &self.uncovered {
            rows.push((
                format!("uncovered {:?}", self.interner.domain(*domain)),
                members.len(),
            ));
        }
        for ((domain, version), members) in &self.certificates {
            if versions.get(domain).copied().flatten() != Some(*version) {
                rows.push((
                    format!("version-changed {:?}", self.interner.domain(*domain)),
                    members.len(),
                ));
            }
        }
        rows.sort_by(|a, b| b.1.cmp(&a.1));
        rows
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
        // Scheduling-only and unused outside tests, so no reverse domain index is kept: scan the leaves.
        let wanted: BTreeSet<&D> = domains.into_iter().collect();
        self.leaves
            .values()
            .filter(|leaf| leaf.owner.iter().any(|read| wanted.contains(&read.domain)))
            .flat_map(|leaf| leaf.subscribers.iter().copied())
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
        assert!(index.leaves.is_empty());
    }
}
