//! The daemon-wide store of immutable values (lane `compiler/shared-store`).
//!
//! Sharing used to exist only on disk (the content-addressed dm-cache): every retained session, one per project root and
//! variant, decoded and owned a private copy of every record it read. This is the in-memory half. One `SharedStore` lives in
//! the daemon (`Shared`) and every `BuildHost` borrows it, so identical values (the same file in two worktrees, the game and
//! the test variant of one tree) are decoded and held once. A session owns only its inputs and its dirty query state.
//!
//! Rules every value kept here follows:
//! * Immutable and content-defined: equal content, one allocation. Nothing here is a session's answer about its own tree.
//! * Authority stays with the consumer: a shared candidate is validated against the asking session's own inputs exactly as a
//!   candidate read from the disk cache is (exact key, exact read replay against the asker's resolver, the consumer's own
//!   local-input acceptance), so sharing can change memory, never output.
//! * One global budget per owner, refcounted by handles and leases; a session releasing its state clears an owner only when
//!   it is the last holder.
//!
//! Owners: the decoded memo `records` (preprocessor), and the artifact `cores`, the `ObservedArtifactStore` behind every
//! `PublicationStore` (class projection, initializer classification, modifier facts, startup, required types, lowering
//! records, ...). A core is shared and each session keeps its own `ObservedArtifactLease` on it: the lease is that session's
//! claim roster (what it currently uses), and a variant lives while any session's lease claims it.
use crate::runner_host::SharedRecords;
use dm_session::{ObservedArtifactStore, ReceiptGroupPool};
use std::{
    any::{Any, TypeId},
    collections::HashMap,
    sync::{Arc, Mutex, OnceLock},
};

#[derive(Default)]
pub(crate) struct SharedStore {
    /// Decoded preprocessor memo records (expansion, directive plan, fragment).
    pub(crate) records: Arc<SharedRecords>,
    /// Derived per-leaf read lists of the unit proofs (`query_db`), interned with the read leaves they come from.
    pub(crate) leaf_proofs: Arc<crate::query_db::LeafProofs>,
    /// Answer values (query, answer hash, positivity) of every session's answer table, interned by query id.
    pub(crate) answer_values: Arc<crate::query_db::AnswerValues>,
    /// Artifact cores by purpose name and exact store type.
    cores: Mutex<HashMap<(&'static str, TypeId), Core>>,
    /// Read-ledger interning pools by purpose name and exact pool type (weak: nothing is kept alive by a pool).
    pools: Mutex<HashMap<(&'static str, TypeId), Arc<dyn Any + Send + Sync>>>,
}
struct Core {
    store: Arc<dyn Any + Send + Sync>,
    /// (variants held, admitted bytes) of the core, type-erased for the report.
    usage: Box<dyn Fn() -> (usize, usize) + Send + Sync>,
}
impl SharedStore {
    /// The one core named `name` for this artifact type; `limit` is the aggregate charge cap of the first creation.
    pub(crate) fn core<T, Q, A, D>(
        &self,
        name: &'static str,
        limit: Option<usize>,
    ) -> Arc<ObservedArtifactStore<T, Q, A, D>>
    where
        T: Send + Sync + 'static,
        Q: Send + Sync + 'static,
        A: Send + Sync + 'static,
        D: Send + Sync + 'static,
    {
        let mut cores = self.cores.lock().unwrap_or_else(|e| e.into_inner());
        let core = cores
            .entry((name, TypeId::of::<ObservedArtifactStore<T, Q, A, D>>()))
            .or_insert_with(|| {
                let store = match limit {
                    Some(limit) => {
                        ObservedArtifactStore::<T, Q, A, D>::shared_current_rosters_with_limit(limit)
                    }
                    None => ObservedArtifactStore::<T, Q, A, D>::shared_current_rosters(),
                };
                let observed = Arc::clone(&store);
                Core {
                    store,
                    usage: Box::new(move || {
                        let mut entries = 0;
                        observed.visit_storage(|view| {
                            if let dm_session::ObservedArtifactStorageView::Store { entries: held, .. } = view {
                                entries = held;
                            }
                        });
                        (entries, observed.admitted_bytes())
                    }),
                }
            });
        Arc::clone(&core.store)
            .downcast::<ObservedArtifactStore<T, Q, A, D>>()
            .unwrap_or_else(|_| unreachable!("a core is registered under its exact store type"))
    }
    /// The one interning pool named `name`: equal read groups of every session are one allocation.
    pub(crate) fn receipt_pool<Q, A, D>(&self, name: &'static str) -> Arc<ReceiptGroupPool<Q, A, D>>
    where
        Q: Send + Sync + 'static,
        A: Send + Sync + 'static,
        D: Send + Sync + 'static,
    {
        let mut pools = self.pools.lock().unwrap_or_else(|e| e.into_inner());
        let pool = pools
            .entry((name, TypeId::of::<ReceiptGroupPool<Q, A, D>>()))
            .or_insert_with(|| Arc::new(ReceiptGroupPool::<Q, A, D>::default()));
        Arc::clone(pool)
            .downcast::<ReceiptGroupPool<Q, A, D>>()
            .unwrap_or_else(|_| unreachable!("a pool is registered under its exact type"))
    }
    /// One line per owner: what the daemon-wide store holds (`DMB_MEM_MARKS=1`, after every request).
    pub(crate) fn report(&self) -> String {
        let (record_bytes, records) = self.records.usage();
        let mut line = format!("dmbd shared store: memo records={records} ({record_bytes} B)");
        let cores = self.cores.lock().unwrap_or_else(|e| e.into_inner());
        let mut rows: Vec<_> = cores
            .iter()
            .map(|((name, _), core)| (*name, (core.usage)()))
            .collect();
        rows.sort();
        for (name, (entries, bytes)) in rows {
            line.push_str(&format!("; {name}={entries} variants ({bytes} B charged)"));
        }
        line
    }
    /// Number of cores created (diagnostic and tests).
    pub(crate) fn core_count(&self) -> usize {
        self.cores.lock().unwrap_or_else(|e| e.into_inner()).len()
    }
}

/// `DMB_SHARED_STORE=0` keeps every session's values private (the pre-sharing behaviour), for A/B measurement and bisection.
pub(crate) fn enabled() -> bool {
    static ENABLED: OnceLock<bool> = OnceLock::new();
    *ENABLED.get_or_init(|| std::env::var("DMB_SHARED_STORE").map_or(true, |value| value != "0"))
}

/// `DMB_SHARED_STORE_PRIVATE=name,name` keeps the named owners private (a core name or a name prefix, `records`, `pools`,
/// `proofs`) while the rest stay shared: bisection of a difference between a shared and a private run.
fn private(name: &str) -> bool {
    static LIST: OnceLock<Vec<String>> = OnceLock::new();
    LIST.get_or_init(|| {
        std::env::var("DMB_SHARED_STORE_PRIVATE")
            .map(|list| list.split(',').filter(|part| !part.is_empty()).map(str::to_owned).collect())
            .unwrap_or_default()
    })
    .iter()
    .any(|prefix| name.starts_with(prefix.as_str()))
}
/// Whether the decoded memo records are shared (see [`private`]).
pub(crate) fn records_shared() -> bool {
    enabled() && !private("records")
}

static ACTIVE: OnceLock<Arc<SharedStore>> = OnceLock::new();
/// Make `store` the process's store: artifact owners created from now on take their cores from it. The daemon calls this once
/// at start; unit tests and one-shot compiles never do, and their owners keep private cores.
pub(crate) fn activate(store: &Arc<SharedStore>) {
    if enabled() {
        let _ = ACTIVE.set(Arc::clone(store));
        if !private("images") {
            byond_dmb::dmb::set_image_interner(crate::output_pool::intern);
        }
        if !private("expansion") {
            dm_preprocess::regions::share_expansion_inputs();
        }
    }
}
pub(crate) fn active() -> Option<&'static Arc<SharedStore>> {
    ACTIVE.get()
}
/// The per-leaf proof lists a session's unit proofs share: the daemon-wide ones, else private.
pub(crate) fn leaf_proofs() -> Arc<crate::query_db::LeafProofs> {
    match active().filter(|_| !private("proofs")) {
        Some(store) => Arc::clone(&store.leaf_proofs),
        None => Arc::default(),
    }
}
/// The answer values a session's answer table shares: the daemon-wide ones, else private.
pub(crate) fn answer_values() -> Arc<crate::query_db::AnswerValues> {
    match active().filter(|_| !private("answers")) {
        Some(store) => Arc::clone(&store.answer_values),
        None => Arc::default(),
    }
}
/// The interning pool a read-ledger producer of this purpose uses: the daemon-wide one, else a private one.
pub(crate) fn receipt_pool<Q, A, D>(name: &'static str) -> Arc<ReceiptGroupPool<Q, A, D>>
where
    Q: Send + Sync + 'static,
    A: Send + Sync + 'static,
    D: Send + Sync + 'static,
{
    match active().filter(|_| !private("pools") && !private(name)) {
        Some(store) => store.receipt_pool(name),
        None => Arc::default(),
    }
}
/// The daemon-wide core of this purpose, or `None` when the store is inactive (tests, one-shot compiles) or the purpose is
/// kept private: for owners whose private form is a different kind of store.
pub(crate) fn shared_core<T, Q, A, D>(name: &'static str) -> Option<Arc<ObservedArtifactStore<T, Q, A, D>>>
where
    T: Send + Sync + 'static,
    Q: Send + Sync + 'static,
    A: Send + Sync + 'static,
    D: Send + Sync + 'static,
{
    active()
        .filter(|_| !private(name))
        .map(|store| store.core(name, None))
}
/// The core an artifact owner of this purpose uses: the daemon-wide one, else a private one.
pub(crate) fn artifact_core<T, Q, A, D>(
    name: &'static str,
    limit: Option<usize>,
) -> Arc<ObservedArtifactStore<T, Q, A, D>>
where
    T: Send + Sync + 'static,
    Q: Send + Sync + 'static,
    A: Send + Sync + 'static,
    D: Send + Sync + 'static,
{
    match active().filter(|_| !private(name)) {
        Some(store) => store.core(name, limit),
        None => match limit {
            Some(limit) => ObservedArtifactStore::shared_current_rosters_with_limit(limit),
            None => ObservedArtifactStore::shared_current_rosters(),
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn one_core_per_purpose_and_type() {
        let store = SharedStore::default();
        let first = store.core::<u32, (), u32, ()>("purpose.a", None);
        let again = store.core::<u32, (), u32, ()>("purpose.a", None);
        let other = store.core::<u32, (), u32, ()>("purpose.b", None);
        let typed = store.core::<u64, (), u32, ()>("purpose.a", None);
        assert_eq!(typed.admitted_bytes(), 0);
        assert!(Arc::ptr_eq(&first, &again));
        assert!(!Arc::ptr_eq(&first, &other));
        assert_eq!(store.core_count(), 3);
        assert!(store.report().contains("purpose.a=0 variants"));
    }
    #[test]
    fn leases_of_two_sessions_share_one_variant() {
        use dm_session::{Observation, ObservationHost};
        struct Host;
        impl ObservationHost<(), u32, ()> for Host {
            fn answer(&self, _: &()) -> u32 {
                7
            }
        }
        let store = SharedStore::default();
        let core = store.core::<u32, (), u32, ()>("purpose.shared", None);
        let first = core.lease();
        let second = core.lease();
        let key: Arc<[u8]> = Arc::from(&b"key"[..]);
        let made = first
            .insert_with_owned(
                Arc::clone(&key),
                vec![Observation { query: (), answer: 7, domain: () }],
                vec![],
                8,
                || 41,
            )
            .unwrap();
        // The second session finds the first one's allocation by exact key and read replay, and claims it.
        let (found, _) = second.visit_explained(&key, &Host, &mut |_| true);
        assert!(Arc::ptr_eq(&made, &found.unwrap()));
        assert_eq!(store.report().matches("1 variants").count(), 1);
        // Dropping one session's lease keeps the variant for the other; the last one frees it.
        drop(first);
        assert!(second.visit_explained(&key, &Host, &mut |_| true).0.is_some());
        drop(second);
        let third = core.lease();
        assert!(third.visit_explained(&key, &Host, &mut |_| true).0.is_none());
    }
}
