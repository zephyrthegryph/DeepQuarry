//! One exact current engine/declaration-owner preparation, with fresh source issuance.
use super::*;
use std::sync::atomic::{AtomicU64, Ordering};
pub(crate) struct RetainedHostFacts {
    values: dm_session::ObservedArtifactStore<Artifact, Query, Answer, Domain>,
    hits: AtomicU64,
    recomputed: AtomicU64,
    constant_hits: AtomicU64,
    runtime_hits: AtomicU64,
    scalar_hits: AtomicU64,
}
struct Entry {
    constants: ConstantCatalog,
    runtime: RuntimeAliasCatalog,
    pinned: Arc<PinnedHostFacts>,
    source: EngineResolverHost<dm_tree::SemanticTree>,
    scalar: dm_tree::constant_resolution::ScalarFacts,
}
#[path = "runner_facts_catalogs.rs"]
mod catalogs;
#[path = "runner_facts_engine_providers.rs"]
mod engine_providers;
#[path = "runner_facts_scalars.rs"]
mod scalars;
enum Artifact {
    Constants(Arc<catalogs::Constants>),
    Runtime(RuntimeAliasCatalog),
    Prepared(Entry),
    EngineProviders(Arc<crate::engine_host::PinnedEngineProviders>),
    Scalar(Arc<dm_tree::constant_resolution::ScalarArtifact>),
}
const KEY: &[u8] = b"dmbc-native-host-preparation-v1";
#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
enum Query {
    Engine,
    Source,
    TypePaths,
    Scalar(dm_tree::constant_resolution::ScalarReadQuery),
}
#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
enum Domain {
    ExactOwners,
}
#[derive(Clone)]
enum Answer {
    Engine(Arc<crate::runner_host::RetainedEngine>),
    Source(Arc<dm_tree::SemanticTree>),
    TypePaths(Arc<Vec<dm_ir::SymbolId>>),
    Scalar(dm_tree::constant_resolution::ScalarReadAnswer),
}
impl PartialEq for Answer {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (Self::Engine(a), Self::Engine(b)) => Arc::ptr_eq(a, b),
            (Self::Source(a), Self::Source(b)) => Arc::ptr_eq(a, b),
            (Self::TypePaths(a), Self::TypePaths(b)) => a == b,
            (Self::Scalar(a), Self::Scalar(b)) => a == b,
            _ => false,
        }
    }
}
impl Eq for Answer {}
struct Current<'a> {
    frontend: &'a ColdFrontend,
    engine: &'a Arc<crate::runner_host::RetainedEngine>,
    paths: std::sync::OnceLock<Arc<Vec<dm_ir::SymbolId>>>,
}
impl Current<'_> {
    fn type_paths(&self) -> &Arc<Vec<dm_ir::SymbolId>> {
        self.paths.get_or_init(|| {
            let mut paths: Vec<_> = self
                .frontend
                .snapshot
                .tree
                .types()
                .iter()
                .map(|ty| ty.path)
                .collect();
            paths.sort_unstable();
            paths.dedup();
            Arc::new(paths)
        })
    }
}
impl dm_session::ObservationHost<Query, Answer, Domain> for Current<'_> {
    fn answer(&self, query: &Query) -> Answer {
        match query {
            Query::Engine => Answer::Engine(Arc::clone(self.engine)),
            Query::Source => Answer::Source(Arc::clone(&self.frontend.snapshot.tree)),
            Query::TypePaths => Answer::TypePaths(Arc::clone(self.type_paths())),
            Query::Scalar(_) => unreachable!("scalar reads require current evaluator host"),
        }
    }
}
impl Default for RetainedHostFacts {
    fn default() -> Self {
        Self {
            values: dm_session::ObservedArtifactStore::current_revision(),
            hits: AtomicU64::new(0),
            recomputed: AtomicU64::new(0),
            constant_hits: AtomicU64::new(0),
            runtime_hits: AtomicU64::new(0),
            scalar_hits: AtomicU64::new(0),
        }
    }
}
impl RetainedHostFacts {
    pub(super) fn prepare(
        &self,
        frontend: &ColdFrontend,
        engine: &Arc<crate::runner_host::RetainedEngine>,
    ) -> Result<PreparedHost, String> {
        let current = Current {
            frontend,
            engine,
            paths: Default::default(),
        };
        if let Some(previous) = self.values.lookup(KEY, &current) {
            if let Artifact::Prepared(previous) = previous.as_ref() {
                self.admit_constant_spellings(&current)?;
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
        }
        // A failed preparation must not preserve an inapplicable latest owner.
        self.retain_catalog_stages();
        let (constants, runtime) = self.catalogs(&current)?;
        let engine_providers = self.engine_providers(&current)?;
        let Components {
            constants,
            runtime,
            pinned,
            source,
            scalar,
        } = prepare_from_catalogs_with_artifacts(
            frontend,
            &engine.snapshot,
            constants,
            runtime,
            Some(&scalars::CurrentScalars {
                owner: self,
                engine,
            }),
            Some(&engine_providers),
        )?;
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
            self.insert_stage(
                KEY,
                &current,
                &[Query::Engine, Query::Source],
                Artifact::Prepared(entry),
            );
        }
        self.recomputed.fetch_add(1, Ordering::Relaxed);
        Ok((host, scalar))
    }
    fn insert_stage(&self, key: &[u8], current: &Current<'_>, queries: &[Query], value: Artifact) {
        use dm_session::ObservationHost;
        let ledger = dm_session::ObservationLedger::default();
        for query in queries {
            ledger.record(
                query.clone(),
                current.answer(query),
                Domain::ExactOwners,
                None,
            );
        }
        // Inline charge only; current-stage retention has no byte admission budget.
        let charge = std::mem::size_of::<Artifact>().saturating_add(key.len());
        self.values.insert_with(
            Arc::from(key),
            ledger.reads(),
            ledger.domain_receipts(),
            charge,
            || value,
        );
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
                for read in reads.iter() {
                    if let Answer::Scalar(answer) = &read.answer {
                        scalars::inspect_answer(answer, &mut census);
                    }
                    if let Answer::TypePaths(paths) = &read.answer {
                        if census.arc_object("host.runtime.type_paths", paths) {
                            census.vec_payload("host.runtime.type_paths", paths);
                        }
                    }
                }
                census.slice("host.facts.versions", versions, true);
                if census.arc_object("host.facts.value", value) {
                    match value.as_ref() {
                        Artifact::Prepared(entry) => inspect_entry(entry, &mut census),
                        Artifact::EngineProviders(value) => value.census(&mut census),
                        Artifact::Scalar(value) => scalars::inspect(value, &mut census),
                        Artifact::Constants(constants) => {
                            census.arc_object("host.constants", constants);
                            census.unknown(
                                "host.constants",
                                "shared catalog and spelling-map backing/control layout excluded",
                            );
                        }
                        Artifact::Runtime(_) => census.unknown(
                            "host.runtime",
                            "shared alias/membership map backing/control layout excluded",
                        ),
                    }
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
    if census.arc_object("host.scalar.certificates", facts.certificates()) {
        census.collection_entries::<(ScalarQuery, u64)>(
            "host.scalar.certificates",
            facts.certificates().as_ref() as *const _ as usize,
            facts.certificates().len(),
        );
    }
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

#[cfg(test)]
#[path = "runner_facts_catalog_tests.rs"]
mod catalog_tests;
