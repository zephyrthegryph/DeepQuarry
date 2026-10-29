//! Keep catalog issuer authority while releasing request-sized host preparation.
use super::*;

impl RetainedHostFacts {
    pub(crate) fn release_prepared_for_pressure(&self) {
        // No source tree, scalar graph, provider or negative-query scope survives
        // through this owner. Escaped immutable hosts may retain their own Arcs.
        // Existing records include the exact engine owner and, for runtime types,
        // complete type-path vector. Ordinary catalogs() replays those receipts;
        // keeping their issuers never licenses a changed dependency.
        self.values
            .retain_current_keys([catalogs::CONSTANTS_KEY, catalogs::RUNTIME_KEY]);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_ir::Resolver;

    struct Source(&'static str);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok(self.0.into())
        }
    }
    #[test]
    fn pressure_retains_catalog_issuers_but_replays_exact_engine_and_type_paths() {
        let mut session = crate::runner_host::BuildHost::default();
        let engine = session
            .engine(
                "catalog-pressure.dme".into(),
                Default::default(),
                true,
                include_bytes!("../../../fixtures/native_template.bin").to_vec(),
            )
            .unwrap();
        let owner = session.host_facts().unwrap();
        let build = |text| {
            dm_tree::frontend::build_with_config(
                std::path::Path::new("catalog-pressure.dme"),
                &Source(text),
                &Default::default(),
                dm_tree::frontend::FrontendConfig {
                    workers: 1,
                    engine: Some(engine.frontend_seed()),
                    observer: None,
                },
            )
            .unwrap()
        };
        let first = build("/datum/catalog_probe\n/proc/p()\n    return 7\n");
        let (host, _) = prepare_retained(&first, &engine, Some(&owner)).unwrap();
        let query = dm_ir::ResolveQuery::RuntimeType(dm_ir::SymbolId::of("/datum/catalog_probe"));
        let original_answer = dm_ir::Resolver::resolve(&host, query);
        let mut prepared = None;
        owner.values.visit_storage(|view| {
            if let dm_session::ObservedArtifactStorageView::Entry { value, .. } = view {
                if matches!(value.as_ref(), Artifact::Prepared(_)) {
                    prepared = Some(Arc::downgrade(value));
                }
            }
        });
        drop(host);
        owner.release_prepared_for_pressure();
        assert!(prepared.unwrap().upgrade().is_none());
        let mut remaining = 0;
        owner.values.visit_storage(|view| {
            if let dm_session::ObservedArtifactStorageView::Entry { value, .. } = view {
                assert!(matches!(
                    value.as_ref(),
                    Artifact::Constants(_) | Artifact::Runtime(_)
                ));
                remaining += 1;
            }
        });
        assert_eq!(remaining, 2);
        let (same, _) = prepare_retained(&first, &engine, Some(&owner)).unwrap();
        assert_eq!(dm_ir::Resolver::resolve(&same, query), original_answer);
        owner.release_prepared_for_pressure();
        let changed = build("/datum/catalog_probe\n/datum/new_type\n/proc/p()\n    return 7\n");
        let (changed_host, _) = prepare_retained(&changed, &engine, Some(&owner)).unwrap();
        // A member's runtime-catalog answer names its own membership: another type joining the
        // catalog leaves it alone, while the joining type's own answer changes.
        assert_eq!(dm_ir::Resolver::resolve(&changed_host, query), original_answer);
        let joined = dm_ir::ResolveQuery::RuntimeType(dm_ir::SymbolId::of("/datum/new_type"));
        assert_ne!(
            dm_ir::Resolver::resolve(&changed_host, joined),
            host_before_join_answer(&first, &engine, &owner, joined)
        );
        owner.release_prepared_for_pressure();
        let other_engine = session
            .engine(
                "different-engine-configuration.dme".into(),
                Default::default(),
                true,
                include_bytes!("../../../fixtures/native_template.bin").to_vec(),
            )
            .unwrap();
        let (other, _) = prepare_retained(&changed, &other_engine, Some(&owner)).unwrap();
        // The same template gives the same catalog schema and membership, so the same answer.
        assert_eq!(
            dm_ir::Resolver::resolve(&other, query),
            dm_ir::Resolver::resolve(&changed_host, query)
        );
    }

    fn host_before_join_answer(
        frontend: &ColdFrontend,
        engine: &Arc<crate::runner_host::RetainedEngine>,
        owner: &RetainedHostFacts,
        query: dm_ir::ResolveQuery,
    ) -> dm_ir::ResolvedMeaning {
        let (host, _) = prepare_retained(frontend, engine, Some(owner)).unwrap();
        dm_ir::Resolver::resolve(&host, query)
    }
}
