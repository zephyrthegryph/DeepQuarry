//! Current source-neutral scheduling and locator layout on the token roster.
//! Modifier and value semantics still pass their existing artifact admissions.
use super::*;
pub(crate) struct Bucket {
    pub(crate) ordinals: Arc<[usize]>,
}
pub(crate) struct Preparation {
    pub(crate) owners: Arc<[SymbolId]>,
    pub(crate) buckets: Arc<[Bucket]>,
    locations: std::sync::Mutex<Option<Arc<Locations>>>,
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub(in crate::initializer_policy) struct Policy {
    pub(in crate::initializer_policy) classification: u128,
    pub(in crate::initializer_policy) factory: u128,
    pub(in crate::initializer_policy) resource: Option<u128>,
    pub(in crate::initializer_policy) engine: Option<u128>,
}
pub(crate) struct Locations {
    policy: Policy,
    pub(crate) inputs: Arc<[Arc<InitializerWrite>]>,
    pub(crate) facts: Arc<[ModifierFact]>,
    pub(crate) keys: Arc<Vec<Arc<[u8]>>>,
}
impl Preparation {
    pub(in crate::initializer_policy) fn new(writes: &[InitializerWrite]) -> Arc<Self> {
        let mut indexes = std::collections::HashMap::new();
        let mut ordinals: Vec<Vec<usize>> = Vec::new();
        for (ordinal, write) in writes.iter().enumerate() {
            let index = *indexes.entry(write.lexical_owner).or_insert_with(|| {
                let index = ordinals.len();
                ordinals.push(Vec::new());
                index
            });
            ordinals[index].push(ordinal);
        }
        Arc::new(Self {
            owners: writes.iter().map(|write| write.lexical_owner).collect(),
            buckets: ordinals
                .into_iter()
                .map(|ordinals| Bucket {
                    ordinals: ordinals.into(),
                })
                .collect(),
            locations: Default::default(),
        })
    }
    pub(in crate::initializer_policy) fn matches(&self, writes: &[InitializerWrite]) -> bool {
        self.owners.len() == writes.len()
            && self
                .owners
                .iter()
                .zip(writes)
                .all(|(owner, write)| *owner == write.lexical_owner)
    }
    pub(in crate::initializer_policy) fn admitted_locations(
        &self,
        inputs: &[crate::initializer_policy::modifier_facts::ModifierKey],
        facts: &[Vec<ModifierFact>],
        policy: Policy,
    ) -> Option<Arc<Locations>> {
        let previous = self
            .locations
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone()?;
        if previous.policy != policy
            || previous.inputs.len() != inputs.len()
            || self.buckets.len() != facts.len()
            || !previous.inputs.iter().zip(inputs).all(|(old, current)| {
                let current = current.shared_input();
                Arc::ptr_eq(old, current) || old == current
            })
        {
            return None;
        }
        for (bucket, facts) in self.buckets.iter().zip(facts) {
            if bucket.ordinals.len() != facts.len()
                || !bucket
                    .ordinals
                    .iter()
                    .zip(facts)
                    .all(|(&ordinal, fact)| previous.facts.get(ordinal) == Some(fact))
            {
                return None;
            }
        }
        Some(previous)
    }
    pub(in crate::initializer_policy) fn remember_locations(
        &self,
        inputs: &[crate::initializer_policy::modifier_facts::ModifierKey],
        facts: Vec<ModifierFact>,
        keys: Arc<Vec<Arc<[u8]>>>,
        policy: Policy,
    ) {
        *self.locations.lock().unwrap_or_else(|e| e.into_inner()) = Some(Arc::new(Locations {
            inputs: inputs
                .iter()
                .map(|key| key.shared_input().clone())
                .collect(),
            facts: facts.into(),
            keys,
            policy,
        }));
    }
    pub(crate) fn visit_locations(&self, visit: impl FnOnce(&Arc<Locations>)) {
        let locations = self.locations.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(locations) = locations.as_ref() {
            visit(locations);
        }
    }
}
