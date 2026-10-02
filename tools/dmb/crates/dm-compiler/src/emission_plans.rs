//! Immutable output binding plans. Semantic candidates and concrete assignments
//! have separate identities, so retaining a plan never hides semantic changes.
use std::collections::HashMap;
use std::sync::Arc;
use dm_codegen_byond::Ledger;
use serde::{Serialize, Deserialize};
use std::collections::BTreeSet;

#[derive(Serialize, Deserialize)]
struct Plan {
    descriptor: crate::ProcDescriptor,
    skeleton: String,
    resources: String,
    strings: Vec<u32>,
    ledger: Arc<Ledger>,
    #[serde(skip)]
    charge: usize,
}
#[derive(Default)]
pub(super) struct EmissionPlans {
    plans: HashMap<crate::ProcKey, Plan>,
    bytes: usize,
    dirty: BTreeSet<crate::ProcKey>,
    store: Option<dm_store::Store>,
    namespace: String,
}
impl EmissionPlans {
    pub fn open(root: &std::path::Path, identity: &str) -> Self {
        let Ok(store) = dm_store::Store::open(root.join("emission-plans.redb")) else { return Self::default(); };
        let namespace = format!("emission-plans-v1-{}-{}", env!("DM_EMISSION_FINGERPRINT"),
            crate::incremental::digest(identity.as_bytes()));
        let cache = Self { store: Some(store.clone()), namespace: namespace.clone(), ..Self::default() };
        cache
    }
    pub fn flush(&mut self) {
        let Some(store) = self.store.as_ref() else { return; };
        while !self.dirty.is_empty() {
            let keys: Vec<_> = self.dirty.iter().take(1024).cloned().collect();
            let changes: Vec<_> = keys.iter().filter_map(|key| {
                let plan = self.plans.get(key)?;
                let bytes = serde_json::to_vec(&(key, plan)).ok()?;
                Some(dm_store::Change::Put(dm_store::Key::new(&self.namespace,
                    crate::lower_cache::shared_binding_fingerprint(key)), bytes))
            }).collect();
            if store.commit(&[], &changes, None).is_err() { return; }
            for key in keys { self.dirty.remove(&key); }
        }
    }
    pub fn resident_bytes(&self) -> usize { self.bytes }
    pub fn clear(&mut self) { self.flush(); self.plans.clear(); self.dirty.clear(); self.bytes = 0; }
    pub fn candidate(&self, key: &crate::ProcKey, descriptor: &crate::ProcDescriptor,
        strings: &[u32]) -> Option<Arc<Ledger>> {
        self.plans.get(key).filter(|plan| plan.descriptor == *descriptor && plan.strings == strings)
            .map(|plan| Arc::clone(&plan.ledger))
    }
    pub fn get(&self, key: &crate::ProcKey, descriptor: &crate::ProcDescriptor,
        skeleton: &str, resources: &str, strings: &[u32]) -> Option<Arc<Ledger>> {
        self.plans.get(key).filter(|plan| plan.descriptor == *descriptor
            && plan.skeleton == skeleton && plan.resources == resources && plan.strings == strings)
            .map(|plan| Arc::clone(&plan.ledger))
    }
    pub fn retain(&mut self, key: crate::ProcKey, descriptor: crate::ProcDescriptor,
        skeleton: &str, resources: &str, strings: Vec<u32>, ledger: Arc<Ledger>) {
        if let Some(old) = self.plans.remove(&key) { self.bytes = self.bytes.saturating_sub(old.charge); }
        let charge = ledger.resident_bytes() + strings.capacity() * 4 + key.path.capacity()
            + descriptor.body_digest.capacity() + descriptor.frame_digest.capacity()
            + skeleton.len() + resources.len() + 192;
        if self.bytes.saturating_add(charge) > 32 * 1024 * 1024 { return; }
        self.bytes += charge;
        self.dirty.insert(key.clone());
        self.plans.insert(key, Plan { descriptor, skeleton: skeleton.to_owned(),
            resources: resources.to_owned(), strings, ledger, charge });
    }
    pub fn finish(&mut self, active: &std::collections::BTreeSet<crate::ProcKey>) {
        self.plans.retain(|key, _| active.contains(key));
        self.bytes = self.plans.values().map(|plan| plan.charge).sum();
        self.dirty.retain(|key| active.contains(key));
    }
}
