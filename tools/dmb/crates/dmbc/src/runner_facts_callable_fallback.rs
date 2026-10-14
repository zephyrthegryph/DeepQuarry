//! Finite negative callable receipts in the existing host-facts artifact store.
use super::*;
use dm_session::ObservationHost;
use std::{
    collections::BTreeSet,
    sync::{Mutex, Weak},
};
const PREFIX: &[u8] = b"host-callable-exclusion-v1";
type Store = dm_session::ObservedArtifactStore<Artifact, Query, Answer, Domain>;
pub(super) type ScopeOwner = Arc<Mutex<Option<Arc<Scope>>>>;
pub(super) struct Scope {
    store: Arc<Store>,
    current: Weak<Mutex<Option<Arc<Scope>>>>,
    names: Arc<std::collections::HashSet<dm_ir::SymbolId>>,
    provider: Arc<crate::engine_host::PinnedEngineProviders>,
    queried: Mutex<BTreeSet<dm_ir::SymbolId>>,
}
impl std::fmt::Debug for Scope {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("CallableFallbackScope")
    }
}
fn key(name: dm_ir::SymbolId) -> Vec<u8> {
    let mut key = PREFIX.to_vec();
    key.extend_from_slice(&name.bits().to_le_bytes());
    key
}
impl ObservationHost<Query, Answer, Domain> for Scope {
    fn answer(&self, query: &Query) -> Answer {
        match query {
            Query::CallableProvider => Answer::CallableProvider(Arc::clone(&self.provider)),
            Query::CallableExclusion(name) => Answer::CallableExclusion(self.names.contains(name)),
            _ => unreachable!("only finite fallback observations"),
        }
    }
}
impl crate::engine_host::CallableFallbackReceipts for Scope {
    fn version(&self, name: dm_ir::SymbolId) -> Option<u64> {
        if !self.names.contains(&name) {
            return None;
        }
        let gate = self.current.upgrade()?;
        let current = gate.lock().unwrap_or_else(|error| error.into_inner());
        let is_current = current
            .as_ref()
            .is_some_and(|owner| std::ptr::eq(owner.as_ref(), self));
        if is_current {
            self.queried
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .insert(name);
        }
        let key = key(name);
        if let Some(owner) = self.store.lookup(&key, self) {
            if let Artifact::CallableFallback(token) = owner.as_ref() {
                return Some(*token);
            }
        }
        // Old immutable hosts may read existing exact receipts, never populate
        // or prune a newer request's store. No lock is held during host.resolve.
        if !is_current {
            return None;
        }
        let ledger = dm_session::ObservationLedger::default();
        for query in [Query::CallableProvider, Query::CallableExclusion(name)] {
            ledger.record(
                query.clone(),
                self.answer(&query),
                Domain::ExactOwners,
                None,
            );
        }
        static NEXT: AtomicU64 = AtomicU64::new(1);
        let token = NEXT
            .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |v| v.checked_add(1))
            .ok()?;
        let owner = self.store.insert_with_owned(
            Arc::from(key),
            ledger.reads(),
            ledger.domain_receipts(),
            std::mem::size_of::<Artifact>(),
            || Artifact::CallableFallback(token),
        )?;
        match owner.as_ref() {
            Artifact::CallableFallback(token) => Some(*token),
            _ => None,
        }
    }
}
impl RetainedHostFacts {
    pub(super) fn attach_fallback<R: dm_ir::Resolver>(
        &self,
        host: EngineResolverHost<R>,
        provider: &Arc<crate::engine_host::PinnedEngineProviders>,
    ) -> EngineResolverHost<R> {
        if !host.fallback_provider_issued(provider) {
            return host;
        }
        let Some(names) = host.callable_exclusions().cloned() else {
            return host;
        };
        let scope = Arc::new(Scope {
            store: Arc::clone(&self.values),
            current: Arc::downgrade(&self.fallback_scope),
            names,
            provider: Arc::clone(provider),
            queried: Default::default(),
        });
        let mut current = self
            .fallback_scope
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let retained = current
            .as_ref()
            .map(|previous| {
                previous
                    .queried
                    .lock()
                    .unwrap_or_else(|error| error.into_inner())
                    .iter()
                    .filter(|name| scope.names.contains(name))
                    .copied()
                    .map(key)
                    .collect::<BTreeSet<_>>()
            })
            .unwrap_or_default();
        let mut keys = Vec::new();
        self.values.visit_storage(|view| {
            if let dm_session::ObservedArtifactStorageView::Entry { key, .. } = view {
                if !key.starts_with(PREFIX) || retained.contains(key.as_ref()) {
                    keys.push(key.to_vec());
                }
            }
        });
        self.values
            .retain_current_keys(keys.iter().map(Vec::as_slice));
        *current = Some(Arc::clone(&scope));
        host.with_callable_fallback(scope)
    }
    pub(super) fn fallback_keys(&self) -> Vec<Vec<u8>> {
        let current = self
            .fallback_scope
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        current
            .as_ref()
            .map(|scope| {
                scope
                    .queried
                    .lock()
                    .unwrap_or_else(|error| error.into_inner())
                    .iter()
                    .copied()
                    .map(key)
                    .collect()
            })
            .unwrap_or_default()
    }
    pub(super) fn census_fallback(&self, census: &mut crate::heap_census::HeapCensus) {
        if let Some(scope) = self
            .fallback_scope
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .as_ref()
        {
            if census.arc_object("host.callable_fallback.scope", scope) {
                scope.provider.census(census);
                if census.arc_object("host.callable_fallback.names", &scope.names) {
                    census.observe_items("host.callable_fallback.names", scope.names.len());
                    census.unknown(
                        "host.callable_fallback.names",
                        "private HashSet backing excluded",
                    );
                }
                let queried = scope
                    .queried
                    .lock()
                    .unwrap_or_else(|error| error.into_inner());
                census.observe_items("host.callable_fallback.queried", queried.len());
                if !queried.is_empty() {
                    census.unknown(
                        "host.callable_fallback.queried",
                        "private BTreeSet node backing excluded",
                    );
                }
            }
        }
    }
}

#[cfg(test)]
#[path = "runner_facts_callable_fallback_tests.rs"]
mod tests;
