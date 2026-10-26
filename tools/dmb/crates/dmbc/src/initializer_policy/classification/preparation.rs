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
    modifier_locations: std::sync::Mutex<Option<Arc<ModifierLocations>>>,
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
pub(crate) struct ModifierLocator {
    pub(crate) bytes: Arc<[u8]>,
    pub(crate) input: Arc<InitializerWrite>,
}
pub(crate) struct ModifierLocations {
    policy: Policy,
    pub(crate) rows: Arc<[ModifierLocator]>,
}
/// Modifier locators by exact content, process-wide. A locator is a pure function of the policy and one write, so two
/// sessions holding the same write (two worktrees, the game and the test variant of one tree) share its key bytes and its
/// input instead of each holding a copy. Weak: the pool keeps nothing alive.
pub(in crate::initializer_policy) fn shared_locator(bytes: Vec<u8>, write: &InitializerWrite) -> ModifierLocator {
    const SHARDS: usize = 32;
    struct Shard {
        locators: std::collections::HashMap<u128, (std::sync::Weak<[u8]>, std::sync::Weak<InitializerWrite>)>,
        prune_at: usize,
    }
    static POOL: std::sync::OnceLock<Box<[std::sync::Mutex<Shard>]>> = std::sync::OnceLock::new();
    let pool = POOL.get_or_init(|| {
        (0..SHARDS)
            .map(|_| {
                std::sync::Mutex::new(Shard {
                    locators: Default::default(),
                    prune_at: 4096,
                })
            })
            .collect()
    });
    let digest = xxhash_rust::xxh3::xxh3_128(&bytes);
    let mut shard = pool[(digest as usize) % SHARDS]
        .lock()
        .unwrap_or_else(|e| e.into_inner());
    if let Some((held_bytes, held_input)) = shard.locators.get(&digest) {
        if let (Some(held_bytes), Some(held_input)) = (held_bytes.upgrade(), held_input.upgrade()) {
            // The digest names the locator; the bytes and the input themselves decide.
            if held_bytes[..] == bytes[..] && held_input.as_ref() == write {
                return ModifierLocator {
                    bytes: held_bytes,
                    input: held_input,
                };
            }
        }
    }
    let locator = ModifierLocator {
        bytes: bytes.into(),
        input: Arc::new(write.clone()),
    };
    shard
        .locators
        .insert(digest, (Arc::downgrade(&locator.bytes), Arc::downgrade(&locator.input)));
    if shard.locators.len() >= shard.prune_at {
        shard
            .locators
            .retain(|_, (bytes, input)| bytes.strong_count() > 0 && input.strong_count() > 0);
        shard.prune_at = (shard.locators.len() * 2).max(4096);
    }
    locator
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
            modifier_locations: Default::default(),
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
    pub(in crate::initializer_policy) fn modifier_locations(
        &self,
        writes: &[InitializerWrite],
        policy: Policy,
        produce: impl FnOnce() -> Vec<ModifierLocator>,
    ) -> Arc<ModifierLocations> {
        let previous = self
            .modifier_locations
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone();
        if let Some(previous) = previous.filter(|old| {
            old.policy == policy
                && old.rows.len() == writes.len()
                && old
                    .rows
                    .iter()
                    .zip(writes)
                    .all(|(row, write)| row.input.as_ref() == write)
        }) {
            return previous;
        }
        let current = Arc::new(ModifierLocations {
            policy,
            rows: produce().into(),
        });
        *self
            .modifier_locations
            .lock()
            .unwrap_or_else(|e| e.into_inner()) = Some(current.clone());
        current
    }
    pub(crate) fn visit_modifier_locations(&self, visit: impl FnOnce(&Arc<ModifierLocations>)) {
        let current = self
            .modifier_locations
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone();
        if let Some(current) = current {
            visit(&current);
        }
    }
}
