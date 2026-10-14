//! Exact engine payloads share the existing stage store; no old source tree is kept.
use super::*;
pub(super) const KEY: &[u8] = b"native-pinned-engine-providers-v1";
impl RetainedHostFacts {
    pub(super) fn engine_providers(
        &self,
        current: &Current<'_>,
    ) -> Result<Arc<crate::engine_host::PinnedEngineProviders>, String> {
        if let Some(previous) = self.values.lookup(KEY, current) {
            if let Artifact::EngineProviders(value) = previous.as_ref() {
                return Ok(Arc::clone(value));
            }
        }
        let value = crate::engine_host::PinnedEngineProviders::capture(&current.engine.snapshot)?;
        self.insert_stage(
            KEY,
            current,
            &[Query::Engine],
            Artifact::EngineProviders(Arc::clone(&value)),
        );
        Ok(value)
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
    fn captured(owner: &RetainedHostFacts) -> Arc<crate::engine_host::PinnedEngineProviders> {
        let mut result = None;
        owner.values.visit_storage(|view| {
            if let dm_session::ObservedArtifactStorageView::Entry { key, value, .. } = view {
                if key.as_ref() == KEY {
                    if let Artifact::EngineProviders(value) = value.as_ref() {
                        result = Some(Arc::clone(value));
                    }
                }
            }
        });
        result.expect("engine provider stage retained")
    }
    #[test]
    fn engine_only_providers_share_across_source_changes_and_reject_other_engine_owner() {
        let mut host = crate::runner_host::BuildHost::default();
        let engine = host
            .engine(
                "providers.dme".into(),
                Default::default(),
                true,
                include_bytes!("../../../fixtures/native_template.bin").to_vec(),
            )
            .unwrap();
        let owner = host.host_facts().unwrap();
        let build = |text| {
            dm_tree::frontend::build_with_config(
                std::path::Path::new("providers.dme"),
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
        let mut previous = None;
        for text in ["/datum/probe\n    var/const/value = 3\n", "/datum/probe\n    var/const/value = 4\n    var/extra = 2\n    proc/new_callable()\n        return 1\n", "/datum/probe\n    var/const/value = 4\n/datum/new_type\n"] {
            let frontend=build(text);
            let (actual,scalars)=prepare_retained(&frontend,&engine,Some(&owner)).unwrap();
            let (fresh,fresh_scalars)=prepare(&frontend,&engine.snapshot).unwrap();
            assert_eq!(actual.configuration_identity(),fresh.configuration_identity());
            assert_eq!(scalars.identity,fresh_scalars.identity);
            for query in [dm_ir::ResolveQuery::HasMemberVar {owner:dm_ir::SymbolId::of("/datum/probe"),name:dm_ir::SymbolId::of("extra")},dm_ir::ResolveQuery::HasMemberProc {owner:dm_ir::SymbolId::of("/datum/probe"),name:dm_ir::SymbolId::of("new_callable")},dm_ir::ResolveQuery::MethodProcedureValue {owner:dm_ir::SymbolId::of("/atom/movable"),name:dm_ir::SymbolId::of("Move"),verb:false}] {
                assert_eq!(actual.resolve(query),fresh.resolve(query));
            }
            let providers=captured(&owner);
            if let Some(previous)=&previous {assert!(Arc::ptr_eq(previous,&providers));}
            previous=Some(providers);
        }
        let mut other_host = crate::runner_host::BuildHost::default();
        let other = other_host
            .engine(
                "providers.dme".into(),
                Default::default(),
                true,
                include_bytes!("../../../fixtures/native_template.bin").to_vec(),
            )
            .unwrap();
        assert_eq!(engine.snapshot.identity(), other.snapshot.identity());
        assert!(!Arc::ptr_eq(&engine, &other));
        let frontend = build("/datum/probe\n    var/const/value = 3\n");
        let (actual, scalars) = prepare_retained(&frontend, &other, Some(&owner)).unwrap();
        let (fresh, fresh_scalars) = prepare(&frontend, &other.snapshot).unwrap();
        assert_eq!(
            actual.configuration_identity(),
            fresh.configuration_identity()
        );
        assert_eq!(scalars.identity, fresh_scalars.identity);
        assert!(!Arc::ptr_eq(previous.as_ref().unwrap(), &captured(&owner)));
    }
}
