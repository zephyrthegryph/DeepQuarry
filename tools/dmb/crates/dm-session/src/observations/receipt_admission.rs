//! Exact admission shared only within one immutable host request.
use super::{Observation, ObservationHost, Receipt, ReceiptStorageView};
use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex, OnceLock, RwLock},
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
    current_version: &'a dyn Fn(&D) -> Option<u128>,
}
impl<Q, A: Eq, D, H: ObservationHost<Q, A, D>> AdmittedLeaf<'_, Q, A, D, H> {
    fn deliver(self) {
        if self.host.supports_admitted_observation() {
            for read in self.owner.iter() {
                self.host
                    .observe_admitted(read, (self.current_version)(&read.domain));
            }
        }
    }
}
/// The borrowed host has the existing ObservationHost immutable-current contract.
/// Never retain this owner across a source/resolver revision. Cached verdicts
/// identify strongly retained immutable leaf storage, not semantic pointer keys.
pub struct ReceiptAdmission<'host, Q, A, D, H> {
    host: &'host H,
    leaves: Mutex<BTreeMap<(usize, usize), Verdict<Q, A, D>>>,
    /// Read-mostly: every receipt check reads here from all workers at once.
    versions: RwLock<BTreeMap<D, Arc<OnceLock<Option<u128>>>>>,
    /// Per-thread first-level copies of issued versions (shard = thread), so
    /// workers do not contend on the shared map's lock word for hits.
    local: Box<[Mutex<BTreeMap<D, Option<u128>>>]>,
}
const LOCAL_SHARDS: usize = 64;
fn local_shard() -> usize {
    use std::hash::{Hash, Hasher};
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    std::thread::current().id().hash(&mut hasher);
    (hasher.finish() as usize) % LOCAL_SHARDS
}
impl<'host, Q: Clone, A: Eq, D: Ord, H: ObservationHost<Q, A, D>>
    ReceiptAdmission<'host, Q, A, D, H>
{
    pub fn allows_certificate_reuse(&self) -> bool {
        !self.host.observes_answers() || self.host.supports_admitted_observation()
    }
    pub fn new(host: &'host H) -> Self {
        Self {
            host,
            leaves: Mutex::new(BTreeMap::new()),
            versions: RwLock::new(BTreeMap::new()),
            local: (0..LOCAL_SHARDS).map(|_| Mutex::new(BTreeMap::new())).collect(),
        }
    }
    /// Memoize only the immutable host's current certificate, not a candidate's
    /// accepted verdict. Unavailable certificates are equally request-local.
    /// Host callbacks run outside the map lock; each domain's cell is initialized
    /// once even when workers concurrently visit different artifact candidates.
    pub fn certified_domains(&self, versions: &[(D, u128)]) -> std::collections::BTreeSet<D>
    where
        D: Clone,
    {
        super::certified_domains(versions, |domain| self.current_version(domain))
    }
    /// The same request-bound immutable issuer answer used by certificate admission.
    pub fn current_version(&self, domain: &D) -> Option<u128>
    where
        D: Clone,
    {
        let local = &self.local[local_shard()];
        if let Some(version) = local
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .get(domain)
            .copied()
        {
            return version;
        }
        let known = self
            .versions
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .get(domain)
            .and_then(|cell| cell.get().copied());
        if let Some(version) = known {
            local
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .insert(domain.clone(), version);
            return version;
        }
        let cell = self
            .versions
            .write()
            .unwrap_or_else(|e| e.into_inner())
            .entry(domain.clone())
            .or_insert_with(|| Arc::new(OnceLock::new()))
            .clone();
        *cell.get_or_init(|| self.host.version_for_admission(domain))
    }

    /// [`Self::current_version`] for a whole roster, split across scoped threads.
    /// Every answer still goes through the same per-domain once-cell; only the
    /// order of host callbacks changes, and results keep the input order.
    pub fn current_versions(&self, domains: Vec<D>) -> Vec<(D, Option<u128>)>
    where
        D: Clone + Send + Sync,
        Self: Sync,
    {
        const MIN_CHUNK: usize = 4096;
        let threads = std::thread::available_parallelism()
            .map_or(1, |n| n.get())
            .min(8)
            .min(domains.len().div_ceil(MIN_CHUNK).max(1));
        if threads <= 1 {
            return domains
                .into_iter()
                .map(|domain| {
                    let version = self.current_version(&domain);
                    (domain, version)
                })
                .collect();
        }
        let chunk = domains.len().div_ceil(threads);
        let versions: Vec<Vec<Option<u128>>> = std::thread::scope(|scope| {
            let handles: Vec<_> = domains
                .chunks(chunk)
                .map(|part| {
                    scope.spawn(move || {
                        part.iter()
                            .map(|domain| self.current_version(domain))
                            .collect::<Vec<_>>()
                    })
                })
                .collect();
            handles
                .into_iter()
                .map(|handle| handle.join().expect("domain version worker"))
                .collect()
        });
        domains
            .into_iter()
            .zip(versions.into_iter().flatten())
            .collect()
    }

    /// The ordinary artifact admission rule with request-shared certificate
    /// checks. Every uncertified answer is replayed in canonical order, including
    /// observable hosts. Partial or certificate-only success never seeds the
    /// full-answer leaf verdict cache used by `first_changed`.
    pub fn first_changed_receipted(
        &self,
        receipt: &Receipt<Q, A, D>,
        versions: &[(D, u128)],
        mut admitted: impl FnMut(&Arc<[Observation<Q, A, D>]>),
    ) -> Option<Q>
    where
        D: Clone,
    {
        static CERTIFY: dm_profile::Accumulator = dm_profile::Accumulator::new("admission.certify");
        static ITERATE: dm_profile::Accumulator = dm_profile::Accumulator::new("admission.iterate");
        static DELIVER: dm_profile::Accumulator = dm_profile::Accumulator::new("admission.deliver");
        let certify_timer = CERTIFY.time();
        let certified = self.certified_domains(versions);
        drop(certify_timer);
        let mut changed = None;
        receipt.visit_storage(|view| {
            if changed.is_some() {
                return;
            }
            if let ReceiptStorageView::Flat(leaf) = view {
                let iterate_timer = ITERATE.time();
                changed = super::first_changed_iter(
                    leaf.iter(),
                    &certified,
                    |query| self.host.answer_for_admission(query),
                    |current, previous| self.host.equivalent(current, previous),
                )
                .cloned();
                drop(iterate_timer);
                if changed.is_none() {
                    let _deliver = DELIVER.time();
                    AdmittedLeaf {
                        host: self.host,
                        owner: leaf,
                        current_version: &|domain| self.current_version(domain),
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
                        current_version: &|domain| self.host.version_for_admission(domain),
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
        // No domain shortcut: sharing an exact leaf does not prove two artifacts
        // carried the same issuer-version roster. Resolve through the common core.
        let changed = super::first_changed_iter(
            leaf.iter(),
            &Default::default(),
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

#[cfg(test)]
#[path = "request_certificate_tests.rs"]
mod request_certificate_tests;
