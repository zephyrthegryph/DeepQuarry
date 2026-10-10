//! Shared immutable engine/source coverage captured once per compilation.
use super::*;

/// A resolver whose authored source allocation can be authenticated.
pub trait PinnedSource: Resolver {
    fn pinned_source(&self) -> &dm_tree::SemanticTree;
    fn pinned_source_is_issued(&self) -> bool;
    fn census_source(&self, _census: &mut crate::heap_census::HeapCensus) {}
}
impl PinnedSource for dm_tree::SemanticTree {
    fn pinned_source(&self) -> &dm_tree::SemanticTree {
        self
    }
    fn pinned_source_is_issued(&self) -> bool {
        true
    }
}
impl PinnedSource for dm_tree::constant_resolution::ScalarSnapshot {
    fn census_source(&self, census: &mut crate::heap_census::HeapCensus) {
        use dm_tree::constant_resolution::{PredefinedOutcome, ScalarOutcome, ScalarQuery};
        if census.arc_object("host.scalar.outcomes", &self.outcomes) {
            census.collection_entries::<(ScalarQuery, ScalarOutcome)>(
                "host.scalar.outcomes",
                self.outcomes.as_ref() as *const _ as usize,
                self.outcomes.len(),
            );
            for outcome in self.outcomes.values() {
                match outcome {
                    ScalarOutcome::Value(value) => {
                        census.semantic_value("host.scalar.values", value)
                    }
                    ScalarOutcome::Cycle(cycle) => {
                        census.slice("host.scalar.cycles", cycle, true);
                    }
                    _ => (),
                }
            }
        }
        if census.arc_object("host.scalar.dependencies", &self.dependencies) {
            census.collection_entries::<(ScalarQuery, Arc<[ScalarQuery]>)>(
                "host.scalar.dependencies",
                self.dependencies.as_ref() as *const _ as usize,
                self.dependencies.len(),
            );
            for edges in self.dependencies.values() {
                census.slice("host.scalar.dependencies", edges, true);
            }
        }
        census.slice("host.scalar.requested", &self.requested, true);
        if census.arc_object("host.scalar.certificates", self.certificates()) {
            census.collection_entries::<(ScalarQuery, u64)>(
                "host.scalar.certificates",
                self.certificates().as_ref() as *const _ as usize,
                self.certificates().len(),
            );
        }
        if census.arc_object("host.scalar.predefined", &self.predefined_reads) {
            census.collection_entries::<(SymbolId, PredefinedOutcome)>(
                "host.scalar.predefined",
                self.predefined_reads.as_ref() as *const _ as usize,
                self.predefined_reads.len(),
            );
            for outcome in self.predefined_reads.values() {
                if let PredefinedOutcome::Value(value) = outcome {
                    census.semantic_value("host.scalar.predefined", value);
                }
            }
        }
    }

    fn pinned_source(&self) -> &dm_tree::SemanticTree {
        &self.source.tree
    }
    fn pinned_source_is_issued(&self) -> bool {
        self.domain_version(dm_ir::ReadDomain::Tree).is_some()
    }
}

#[derive(Clone, Debug)]
pub struct PinnedHostFacts {
    engine: u128,
    source: Arc<dm_tree::SemanticTree>,
    constants: u128,
    runtime: u128,
    source_versions: Vec<u128>,
    callable_issuer: Option<u64>,
    callable_absence: Option<Arc<HashSet<SymbolId>>>,
    intrinsic_methods: Option<Arc<intrinsic_methods::IntrinsicMethods>>,
    retained_methods: Option<Arc<crate::engine::procedure_abi::RetainedMethods>>,
    variable_absence: Option<Arc<VariableAbsence>>,
}
impl PinnedHostFacts {
    pub fn capture(
        engine: &crate::engine::EngineSnapshot,
        frontend: &dm_tree::frontend::ColdFrontend,
        constants: &ConstantCatalog,
        runtime: &RuntimeAliasCatalog,
    ) -> Result<Arc<Self>, String> {
        let providers = PinnedEngineProviders::capture(engine)?;
        Self::capture_with_providers(engine, frontend, constants, runtime, &providers)
    }
    pub(crate) fn capture_with_providers(
        engine: &crate::engine::EngineSnapshot,
        frontend: &dm_tree::frontend::ColdFrontend,
        constants: &ConstantCatalog,
        runtime: &RuntimeAliasCatalog,
        providers: &PinnedEngineProviders,
    ) -> Result<Arc<Self>, String> {
        Self::capture_with_callable_coverage(
            engine, frontend, constants, runtime, providers, None, None,
        )
    }
    pub(crate) fn capture_with_callable_coverage(
        engine: &crate::engine::EngineSnapshot,
        frontend: &dm_tree::frontend::ColdFrontend,
        constants: &ConstantCatalog,
        runtime: &RuntimeAliasCatalog,
        providers: &PinnedEngineProviders,
        coverage: Option<&Arc<HashSet<SymbolId>>>,
        variables: Option<&Arc<VariableCoverage>>,
    ) -> Result<Arc<Self>, String> {
        check_provider_source(engine, frontend)?;
        if providers.engine != engine.identity() {
            return Err("engine providers belong to another capture".into());
        }
        let host = EngineResolverHost::new(
            Arc::clone(&frontend.snapshot.tree),
            constants.clone(),
            runtime.clone(),
        )
        .bind_callables_with_coverage(frontend, &providers.callables, coverage)?
        .bind_variables_with_coverage(frontend, &providers.variables, variables)?;
        Ok(Arc::new(Self {
            engine: engine.identity(),
            source: Arc::clone(&frontend.snapshot.tree),
            constants: constants.identity(),
            runtime: runtime.identity(),
            source_versions: host.source_versions,
            callable_issuer: host.callable_issuer,
            callable_absence: host.callable_absence,
            intrinsic_methods: host.intrinsic_methods,
            retained_methods: host.retained_methods,
            variable_absence: host.variable_absence,
        }))
    }
}
impl<R: PinnedSource> EngineResolverHost<R> {
    /// Observe retained provider owners without exposing mutable semantic facts.
    pub fn census(&self, census: &mut crate::heap_census::HeapCensus) {
        self.tree.census_source(census);
        census.vec_payload("host.source_versions", &self.source_versions);
        if let Some(names) = &self.callable_absence {
            if census.arc_object("host.callable_absence", names) {
                census.observe_items("host.callable_absence", names.len());
                census.unknown("host.callable_absence", "private HashSet backing excluded");
            }
        }
        if let Some(methods) = &self.intrinsic_methods {
            if census.arc_object("host.intrinsic_methods", methods) {
                methods.census(census);
            }
        }
        if let Some(methods) = &self.retained_methods {
            if census.arc_object("host.retained_methods", methods) {
                methods.census(census);
            }
        }
        if let Some(variables) = &self.variable_absence {
            if census.arc_object("host.variable_absence", variables) {
                variables.payload.census(census);
            }
        }
    }

    pub fn with_pinned_facts(
        mut self,
        engine: &crate::engine::EngineSnapshot,
        frontend: &dm_tree::frontend::ColdFrontend,
        facts: Arc<PinnedHostFacts>,
    ) -> Result<Self, String> {
        if facts.engine != engine.identity()
            || frontend.engine.as_ref().map(|status| status.identity) != Some(facts.engine)
            || !Arc::ptr_eq(&facts.source, &frontend.snapshot.tree)
            || !std::ptr::eq(self.tree.pinned_source(), facts.source.as_ref())
            || !self.tree.pinned_source_is_issued()
            || self.constants.identity() != facts.constants
            || self.runtime.identity() != facts.runtime
        {
            return Err(
                "pinned host facts belong to another engine, source, or configuration".into(),
            );
        }
        self.answer_domain = std::sync::OnceLock::new();
        self.source_versions = facts.source_versions.clone();
        self.callable_fallback = None;
        self.callable_issuer = facts.callable_issuer;
        self.callable_absence = facts.callable_absence.clone();
        self.intrinsic_methods = facts.intrinsic_methods.clone();
        self.retained_methods = facts.retained_methods.clone();
        self.variable_absence = facts.variable_absence.clone();
        Ok(self)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn captured_facts_share_providers_and_reject_other_source_allocations() {
        struct Source;
        impl dm_preprocess::SourceProvider for Source {
            fn read(&self, _: &std::path::Path) -> Result<String, String> {
                Ok("/datum/probe\n    var/value = 1\n/proc/probe()\n    return 1\n".into())
            }
        }
        let engine = crate::engine::EngineSnapshot::from_bytes(
            include_bytes!("../../../../fixtures/native_template.bin"),
            1,
        )
        .unwrap()
        .with_bootstrap_catalog()
        .unwrap();
        let seed = engine.frontend_seed();
        let frontend = dm_tree::frontend::build_with_config(
            std::path::Path::new("project.dme"),
            &Source,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(&seed),
                observer: None,
            },
        )
        .unwrap();
        let mut symbols = frontend.snapshot.tree.symbols().clone();
        let constants = ConstantCatalog::native_516_1687(&mut symbols).unwrap();
        let runtime = RuntimeAliasCatalog::new(
            engine.identity(),
            &symbols,
            Vec::new(),
            frontend
                .snapshot
                .tree
                .types()
                .iter()
                .map(|node| node.path)
                .collect(),
            Completeness::Partial,
        )
        .unwrap();
        let facts = PinnedHostFacts::capture(&engine, &frontend, &constants, &runtime).unwrap();
        let host = EngineResolverHost::new(
            Arc::clone(&frontend.snapshot.tree),
            constants.clone(),
            runtime.clone(),
        )
        .with_pinned_facts(&engine, &frontend, Arc::clone(&facts))
        .unwrap();
        assert!(Arc::ptr_eq(
            host.retained_methods.as_ref().unwrap(),
            facts.retained_methods.as_ref().unwrap()
        ));
        assert!(Arc::ptr_eq(
            host.variable_absence.as_ref().unwrap(),
            facts.variable_absence.as_ref().unwrap()
        ));
        let independent_tree = Arc::new(frontend.snapshot.tree.as_ref().clone());
        assert!(
            EngineResolverHost::new(independent_tree, constants.clone(), runtime.clone())
                .with_pinned_facts(&engine, &frontend, Arc::clone(&facts))
                .is_err()
        );
        let legacy =
            EngineResolverHost::new(Arc::clone(&frontend.snapshot.tree), constants, runtime)
                .with_pinned_callables(&engine, &frontend)
                .unwrap()
                .with_pinned_variables(&engine, &frontend)
                .unwrap();
        assert_eq!(
            host.configuration_identity(),
            legacy.configuration_identity()
        );
        assert_eq!(
            host.domain_version(dm_ir::ReadDomain::Tree),
            legacy.domain_version(dm_ir::ReadDomain::Tree)
        );
        for query in [
            Q::Var {
                owner: SymbolId::of("/datum/probe"),
                name: SymbolId::of("__TYPE__"),
            },
            Q::Proc {
                owner: SymbolId::of("/datum/probe"),
                name: SymbolId::of("probe"),
                verb: true,
            },
        ] {
            assert_eq!(host.resolve(query), legacy.resolve(query));
        }
    }
}
