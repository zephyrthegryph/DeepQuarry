//! Position-independent stored-declaration syntax. Every use is bound to an
//! authenticated current body before this immutable payload may be borrowed.
use dm_ir::{ProcedureIdentity, ResolveQuery, ResolvedMeaning, Resolver};
use dm_tree::frontend::{IssuedStaticPlan, RelativeStaticPlan};
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc,
};

pub struct StartupArtifacts {
    values: dm_session::ArtifactStore<Arc<RelativeStaticPlan>>,
    pub hits: AtomicU64,
    pub recomputed: AtomicU64,
    pub declined: AtomicU64,
}
impl Default for StartupArtifacts {
    fn default() -> Self {
        Self {
            values: dm_session::ArtifactStore::current_revision(),
            hits: AtomicU64::new(0),
            recomputed: AtomicU64::new(0),
            declined: AtomicU64::new(0),
        }
    }
}
// Static capture has no resolved reads: its complete input is the current
// expanded syntax plus exact normalized declaration identity and parser policy.
struct SyntaxInputs;
impl Resolver for SyntaxInputs {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        ResolvedMeaning::Unsupported(query)
    }
}
pub(super) fn key(identity: ProcedureIdentity, source: &str) -> Vec<u8> {
    let mut key = b"dmbc-startup-static-syntax-v1\0".to_vec();
    key.extend_from_slice(&identity.owner.bits().to_le_bytes());
    key.extend_from_slice(&identity.name.bits().to_le_bytes());
    key.push(u8::from(identity.verb));
    key.extend_from_slice(&identity.occurrence.to_le_bytes());
    key.extend_from_slice(&(source.len() as u64).to_le_bytes());
    key.extend_from_slice(source.as_bytes());
    key
}
impl StartupArtifacts {
    pub(super) fn retain_keys<'a>(&self, keys: impl IntoIterator<Item = &'a [u8]>) {
        self.values.retain_current_keys(keys);
    }
    pub(super) fn lookup(&self, key: &[u8]) -> Option<Arc<RelativeStaticPlan>> {
        let value = self.values.lookup(key, &SyntaxInputs)?;
        self.hits.fetch_add(1, Ordering::Relaxed);
        Some(Arc::clone(value.as_ref()))
    }
    pub(super) fn remember(&self, key: Vec<u8>, receipt: &Arc<IssuedStaticPlan>) {
        let Ok(payload) = receipt.relative_payload() else {
            self.declined.fetch_add(1, Ordering::Relaxed);
            self.recomputed.fetch_add(1, Ordering::Relaxed);
            return;
        };
        if let Some(weight) = crate::heap_census::resident_startup_weight(&payload, &key) {
            self.values
                .insert_with(key.into(), Vec::new(), Vec::new(), weight, || payload);
        } else {
            self.declined.fetch_add(1, Ordering::Relaxed);
        }
        self.recomputed.fetch_add(1, Ordering::Relaxed);
    }
}
