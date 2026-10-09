//! Daemon-wide immutable engine content. Host configuration and source issuers
//! are deliberately absent. The store retains at most eight engine payloads;
//! this is a count bound, not a decoded heap or process-private byte estimate.
use crate::{engine::EngineSnapshot, engine_link::EngineLinkFacts};
use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver};
use std::{
    collections::VecDeque,
    sync::{Arc, Mutex, OnceLock},
};

const MAX_PAYLOADS: usize = 8;
pub(crate) struct EnginePayload {
    pub(crate) bytes: Arc<[u8]>,
    pub(crate) snapshot: EngineSnapshot,
    schema: u128,
    bootstrap: bool,
    compiler: u128,
    pub(super) links: Mutex<Option<EngineLinkFacts>>,
    seed: OnceLock<dm_tree::frontend::EngineSeed>,
}
impl EnginePayload {
    pub(crate) fn capture(
        bytes: Vec<u8>,
        schema: u128,
        bootstrap: bool,
        compiler: u128,
    ) -> Result<Arc<Self>, String> {
        let snapshot = EngineSnapshot::from_bytes(&bytes, schema)
            .map_err(|error| format!("engine template: {error:?}"))?;
        let snapshot = if bootstrap {
            snapshot
                .with_bootstrap_catalog()
                .map_err(|error| format!("engine catalog: {error:?}"))?
        } else {
            snapshot
        };
        Ok(Arc::new(Self {
            bytes: bytes.into(),
            snapshot,
            schema,
            bootstrap,
            compiler,
            links: Mutex::new(None),
            seed: OnceLock::new(),
        }))
    }
    pub(crate) fn frontend_seed(&self) -> &dm_tree::frontend::EngineSeed {
        self.seed.get_or_init(|| self.snapshot.frontend_seed())
    }
    pub(crate) fn link_overlay(&self) -> Result<EngineLinkFacts, String> {
        let mut retained = self
            .links
            .lock()
            .map_err(|_| "retained engine links poisoned")?;
        if retained.is_none() {
            *retained = Some(crate::engine_link::capture(&self.bytes, &self.snapshot)?);
        }
        let baseline = retained.as_ref().expect("captured engine links");
        Ok(EngineLinkFacts {
            inventory: baseline.inventory.clone(),
            references: baseline.references.clone(),
        })
    }
}
struct Inputs;
impl Resolver for Inputs {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        ResolvedMeaning::Unsupported(query)
    }
}
pub(crate) struct EnginePayloads {
    values: dm_session::ArtifactStore<Arc<EnginePayload>>,
    // Also serializes first decoding, so simultaneous worktrees decode once.
    roster: Mutex<VecDeque<Arc<[u8]>>>,
}
impl Default for EnginePayloads {
    fn default() -> Self {
        Self {
            values: dm_session::ArtifactStore::current_revision(),
            roster: Mutex::new(VecDeque::new()),
        }
    }
}
impl EnginePayloads {
    pub(crate) fn capture(
        &self,
        bytes: Vec<u8>,
        schema: u128,
        bootstrap: bool,
        compiler: u128,
    ) -> Result<Arc<EnginePayload>, String> {
        let mut key = b"dmbc-shared-engine-v1\0".to_vec();
        key.extend_from_slice(&xxhash_rust::xxh3::xxh3_128(&bytes).to_le_bytes());
        key.extend_from_slice(&schema.to_le_bytes());
        key.push(u8::from(bootstrap));
        key.extend_from_slice(&compiler.to_le_bytes());
        self.capture_at(key.into(), bytes, schema, bootstrap, compiler)
    }
    fn capture_at(
        &self,
        key: Arc<[u8]>,
        bytes: Vec<u8>,
        schema: u128,
        bootstrap: bool,
        compiler: u128,
    ) -> Result<Arc<EnginePayload>, String> {
        let mut roster = self
            .roster
            .lock()
            .map_err(|_| "shared engine roster poisoned")?;
        // The locator digest is only an index: every admitted candidate must
        // match all interpretation parameters and the full captured byte image.
        let (hit, _) = self.values.visit_explained(&key, &Inputs, &mut |value| {
            value.schema == schema
                && value.bootstrap == bootstrap
                && value.compiler == compiler
                && value.bytes.as_ref() == bytes
        });
        if let Some(hit) = hit {
            return Ok(Arc::clone(hit.as_ref()));
        }
        let payload = EnginePayload::capture(bytes, schema, bootstrap, compiler)?;
        roster.retain(|previous| previous.as_ref() != key.as_ref());
        roster.push_back(Arc::clone(&key));
        while roster.len() > MAX_PAYLOADS {
            roster.pop_front();
        }
        self.values
            .retain_current_keys(roster.iter().map(AsRef::as_ref));
        // Count-bound storage: zero is not presented as a retained heap charge.
        self.values
            .insert_with(key, Vec::new(), Vec::new(), 0, || Arc::clone(&payload));
        Ok(payload)
    }
    /// Release store-only payloads after host expiry/pressure, outside slot locks.
    pub(crate) fn prune_idle(&self) {
        let mut roster = self
            .roster
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let mut live = Vec::new();
        self.values.visit_storage(|view| {
            if let dm_session::ArtifactStorageView::Entry { key, value, .. } = view {
                if Arc::strong_count(value.as_ref()) > 1 {
                    live.push(Arc::clone(key));
                }
            }
        });
        roster.retain(|key| live.iter().any(|candidate| candidate == key));
        self.values
            .retain_current_keys(roster.iter().map(AsRef::as_ref));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn bytes() -> Vec<u8> {
        include_bytes!("../../../fixtures/native_template.bin").to_vec()
    }
    #[test]
    fn exact_payload_shares_seed_and_configuration_mismatch_never_admits() {
        let store = EnginePayloads::default();
        let first = store.capture(bytes(), 1, true, 7).unwrap();
        let second = store.capture(bytes(), 1, true, 7).unwrap();
        assert!(Arc::ptr_eq(&first, &second));
        assert!(std::ptr::eq(first.frontend_seed(), second.frontend_seed()));
        let forced_key: Arc<[u8]> = Arc::from(&b"forced locator collision"[..]);
        let a = store
            .capture_at(forced_key.clone(), bytes(), 1, true, 7)
            .unwrap();
        assert!(store
            .capture_at(forced_key.clone(), b"not a DMB".to_vec(), 1, true, 7)
            .is_err());
        let b = store.capture_at(forced_key, bytes(), 1, true, 8).unwrap();
        assert!(!Arc::ptr_eq(&a, &b));
    }
    #[test]
    fn idle_pruning_preserves_live_hosts_and_releases_store_only_payloads() {
        let store = EnginePayloads::default();
        let live = store.capture(bytes(), 1, true, 7).unwrap();
        let obsolete = store.capture(bytes(), 1, true, 8).unwrap();
        let weak = Arc::downgrade(&obsolete);
        drop(obsolete);
        store.prune_idle();
        assert!(weak.upgrade().is_none());
        assert!(Arc::ptr_eq(
            &live,
            &store.capture(bytes(), 1, true, 7).unwrap()
        ));
    }
}
