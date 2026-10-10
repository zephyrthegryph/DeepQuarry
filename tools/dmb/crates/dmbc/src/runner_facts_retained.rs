//! One exact current engine/declaration-owner preparation, with fresh source issuance.
use super::*;
use std::sync::atomic::{AtomicU64, Ordering};
pub(crate) struct RetainedHostFacts {
    values: dm_session::ObservedArtifactStore<Entry, Query, Answer, Domain>,
    hits: AtomicU64,
    recomputed: AtomicU64,
}
struct Entry {
    constants: ConstantCatalog,
    runtime: RuntimeAliasCatalog,
    pinned: Arc<PinnedHostFacts>,
    source: EngineResolverHost<dm_tree::SemanticTree>,
    scalar: dm_tree::constant_resolution::ScalarFacts,
}
const KEY: &[u8] = b"dmbc-native-host-preparation-v1";
#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
enum Query {
    Engine,
    Source,
}
#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
enum Domain {
    ExactOwners,
}
#[derive(Clone)]
enum Answer {
    Engine(Arc<crate::runner_host::RetainedEngine>),
    Source(Arc<dm_tree::SemanticTree>),
}
impl PartialEq for Answer {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (Self::Engine(a), Self::Engine(b)) => Arc::ptr_eq(a, b),
            (Self::Source(a), Self::Source(b)) => Arc::ptr_eq(a, b),
            _ => false,
        }
    }
}
impl Eq for Answer {}
struct Current<'a> {
    frontend: &'a ColdFrontend,
    engine: &'a Arc<crate::runner_host::RetainedEngine>,
}
impl dm_session::ObservationHost<Query, Answer, Domain> for Current<'_> {
    fn answer(&self, query: &Query) -> Answer {
        match query {
            Query::Engine => Answer::Engine(Arc::clone(self.engine)),
            Query::Source => Answer::Source(Arc::clone(&self.frontend.snapshot.tree)),
        }
    }
}
impl Default for RetainedHostFacts {
    fn default() -> Self {
        Self {
            values: dm_session::ObservedArtifactStore::current_revision(),
            hits: AtomicU64::new(0),
            recomputed: AtomicU64::new(0),
        }
    }
}
impl RetainedHostFacts {
    pub(super) fn prepare(
        &self,
        frontend: &ColdFrontend,
        engine: &Arc<crate::runner_host::RetainedEngine>,
    ) -> Result<PreparedHost, String> {
        let current = Current { frontend, engine };
        if let Some(previous) = self.values.lookup(KEY, &current) {
            if let Some(scalar) = previous.scalar.bind_current(&frontend.snapshot) {
                let scalar = Arc::new(scalar);
                let host = EngineResolverHost::new(
                    Arc::clone(&scalar),
                    previous.constants.clone(),
                    previous.runtime.clone(),
                )
                .with_pinned_facts(
                    &engine.snapshot,
                    frontend,
                    Arc::clone(&previous.pinned),
                )?;
                self.hits.fetch_add(1, Ordering::Relaxed);
                return Ok((host, scalar));
            }
        }
        // A failed preparation must not preserve an inapplicable latest owner.
        self.values.retain_current_keys(std::iter::empty::<&[u8]>());
        let Components {
            constants,
            runtime,
            pinned,
            source,
            scalar,
        } = prepare_components(frontend, &engine.snapshot)?;
        let host = EngineResolverHost::new(Arc::clone(&scalar), constants.clone(), runtime.clone())
            .with_pinned_facts(&engine.snapshot, frontend, Arc::clone(&pinned))?;
        if let Some(facts) = scalar.retain_facts() {
            let entry = Entry {
                constants,
                runtime,
                pinned,
                source,
                scalar: facts,
            };
            let ledger = dm_session::ObservationLedger::default();
            for query in [Query::Engine, Query::Source] {
                use dm_session::ObservationHost;
                ledger.record(
                    query.clone(),
                    current.answer(&query),
                    Domain::ExactOwners,
                    None,
                );
            }
            // Current-revision retention is key-scoped, not byte-budget admission.
            // This charge covers only the accessible inline entry and locator;
            // it is not a resident-heap estimate. Full census remains opt-in.
            let inline_charge = std::mem::size_of::<Entry>().saturating_add(KEY.len());
            self.values.insert_with(
                Arc::from(KEY),
                ledger.reads(),
                ledger.domain_receipts(),
                inline_charge,
                || entry,
            );
        }
        self.recomputed.fetch_add(1, Ordering::Relaxed);
        Ok((host, scalar))
    }
    pub(crate) fn census(&self) -> crate::heap_census::HeapCensusReport {
        let mut census = crate::heap_census::HeapCensus::new("retained.host_facts");
        self.values.visit_storage(|view| match view {
            dm_session::ObservedArtifactStorageView::Store { buckets, entries } => {
                census.observe_items("host.facts.index", entries);
                if buckets != 0 {
                    census.unknown(
                        "host.facts.index",
                        "private generic store index/control layout excluded",
                    );
                }
            }
            dm_session::ObservedArtifactStorageView::Bucket {
                address,
                len,
                capacity,
                element_size,
            } => {
                census.exposed_buffer(
                    "host.facts.buckets",
                    address,
                    len.saturating_mul(element_size),
                    capacity.saturating_mul(element_size),
                );
            }
            dm_session::ObservedArtifactStorageView::Entry {
                key,
                reads,
                versions,
                value,
            } => {
                census.slice("host.facts.keys", key, true);
                census.slice("host.facts.reads", reads, true);
                census.slice("host.facts.versions", versions, true);
                if census.arc_object("host.facts.value", value) {
                    inspect_entry(value, &mut census);
                }
            }
        });
        census.finish()
    }
}
fn inspect_entry(entry: &Entry, census: &mut crate::heap_census::HeapCensus) {
    use dm_tree::constant_resolution::{PredefinedOutcome, ScalarOutcome, ScalarQuery};
    entry.source.census(census);
    let facts = &entry.scalar;
    census.slice("host.scalar.requested", facts.requested(), true);
    if census.arc_object("host.scalar.outcomes", facts.outcomes()) {
        census.collection_entries::<(ScalarQuery, ScalarOutcome)>(
            "host.scalar.outcomes",
            facts.outcomes().as_ref() as *const _ as usize,
            facts.outcomes().len(),
        );
        for outcome in facts.outcomes().values() {
            match outcome {
                ScalarOutcome::Value(value) => census.semantic_value("host.scalar.values", value),
                ScalarOutcome::Cycle(cycle) => {
                    census.slice("host.scalar.cycles", cycle, true);
                }
                _ => (),
            }
        }
    }
    if census.arc_object("host.scalar.dependencies", facts.dependencies()) {
        census.collection_entries::<(ScalarQuery, Arc<[ScalarQuery]>)>(
            "host.scalar.dependencies",
            facts.dependencies().as_ref() as *const _ as usize,
            facts.dependencies().len(),
        );
        for edges in facts.dependencies().values() {
            census.slice("host.scalar.dependencies", edges, true);
        }
    }
    if census.arc_object("host.scalar.predefined", facts.predefined_reads()) {
        census.collection_entries::<(dm_ir::SymbolId, PredefinedOutcome)>(
            "host.scalar.predefined",
            facts.predefined_reads().as_ref() as *const _ as usize,
            facts.predefined_reads().len(),
        );
        for value in facts.predefined_reads().values() {
            if let PredefinedOutcome::Value(value) = value {
                census.semantic_value("host.scalar.predefined", value);
            }
        }
    }
    census.unknown("host.facts", "shared semantic tree, engine payload and catalog private indexes are retained; backing/control layout excluded");
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Source(&'static str);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok(self.0.into())
        }
    }
    #[test]
    fn exact_host_owners_share_scalar_facts_but_bind_current_occurrences() {
        let mut host = crate::runner_host::BuildHost::default();
        let engine = host
            .engine(
                std::path::PathBuf::from("E:/fixture/facts.dme"),
                Default::default(),
                true,
                include_bytes!("../../../fixtures/native_template.bin").to_vec(),
            )
            .unwrap();
        let retained = host.host_facts().unwrap();
        let executor = dm_exec::BuildExecutor::new(1).unwrap();
        let mut semantic = dm_tree::frontend::RetainedSemanticTree::new();
        let build = |source, semantic: &mut dm_tree::frontend::RetainedSemanticTree| {
            dm_tree::frontend::build_with_executor_and_semantic_state(
                std::path::Path::new("facts.dme"),
                &Source(source),
                &Default::default(),
                dm_tree::frontend::FrontendConfig {
                    workers: 1,
                    engine: Some(engine.frontend_seed()),
                    observer: None,
                },
                None,
                &executor,
                Some(semantic),
            )
            .unwrap()
        };
        let first = build(
            "/datum/probe\n    var/const/value = 3\n    proc/read_value()\n        return value\n",
            &mut semantic,
        );
        let (_, original) = prepare_retained(&first, &engine, Some(&retained)).unwrap();
        let second = build("\n/datum/probe\n    var/const/value = 3\n    proc/read_value()\n        return value + 1\n", &mut semantic);
        assert!(Arc::ptr_eq(&first.snapshot.tree, &second.snapshot.tree));
        let (resolver, rebound) = prepare_retained(&second, &engine, Some(&retained)).unwrap();
        let (fresh, fresh_scalar) = prepare(&second, &engine.snapshot).unwrap();
        assert!(Arc::ptr_eq(&original.outcomes, &rebound.outcomes));
        assert!(Arc::ptr_eq(
            &rebound.source.occurrences,
            &second.snapshot.occurrences
        ));
        assert!(!Arc::ptr_eq(
            &rebound.source.occurrences,
            &first.snapshot.occurrences
        ));
        assert_eq!(rebound.identity, fresh_scalar.identity);
        use dm_ir::Resolver;
        let query = dm_ir::ResolveQuery::Constant {
            owner: dm_ir::SymbolId::of("/datum/probe"),
            name: dm_ir::SymbolId::of("value"),
        };
        assert_eq!(resolver.resolve(query.clone()), fresh.resolve(query));
        assert_eq!(retained.hits.load(Ordering::Relaxed), 1);
        let changed = build(
            "/datum/probe\n    var/const/value = 4\n    proc/read_value()\n        return value\n",
            &mut semantic,
        );
        let (_, changed_scalar) = prepare_retained(&changed, &engine, Some(&retained)).unwrap();
        assert!(!Arc::ptr_eq(&rebound.outcomes, &changed_scalar.outcomes));
        assert_eq!(retained.recomputed.load(Ordering::Relaxed), 2);
        assert!(
            host.host_facts_retention_census()
                .unwrap()
                .unique_known_capacity_bytes
                > 0
        );
        let mut independent = crate::runner_host::BuildHost::default();
        let other_engine = independent
            .engine(
                std::path::PathBuf::from("E:/fixture/facts.dme"),
                Default::default(),
                true,
                include_bytes!("../../../fixtures/native_template.bin").to_vec(),
            )
            .unwrap();
        let (_, independent_scalar) =
            prepare_retained(&changed, &other_engine, Some(&retained)).unwrap();
        assert!(!Arc::ptr_eq(
            &changed_scalar.outcomes,
            &independent_scalar.outcomes
        ));
        assert_eq!(retained.recomputed.load(Ordering::Relaxed), 3);
        assert!(crate::runner_host::BuildHost::one_shot()
            .host_facts()
            .is_none());
    }
}
