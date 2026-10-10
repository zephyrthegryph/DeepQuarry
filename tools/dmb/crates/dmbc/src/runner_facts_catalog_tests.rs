use super::*;
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
#[test]
fn catalog_stages_reuse_for_member_edits_and_type_membership_invalidates_runtime_only() {
    let mut session = crate::runner_host::BuildHost::default();
    let engine = session
        .engine(
            "facts.dme".into(),
            Default::default(),
            true,
            include_bytes!("../../../fixtures/native_template.bin").to_vec(),
        )
        .unwrap();
    let retained = session.host_facts().unwrap();
    let build = |text| {
        dm_tree::frontend::build_with_config(
            std::path::Path::new("facts.dme"),
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
    let cases = [
        "/datum/probe\n    var/const/value = 3\n    proc/read_value()\n        return value\n",
        "/datum/probe\n    var/const/value = 3\n    var/extra = 1\n    proc/read_value()\n        return value\n    proc/unrelated_added()\n        return 2\n",
        "/datum/probe\n    var/const/value = 4\n    var/extra = 1\n    proc/read_value()\n        return value\n    proc/new_proc()\n        return 2\n",
    ];
    let mut previous_tree = None;
    let mut previous_scalar_artifact = None;
    let mut previous_certificate = None;
    let meaning = dm_ir::ResolveQuery::Constant {
        owner: dm_ir::SymbolId::of("/datum/probe"),
        name: dm_ir::SymbolId::of("value"),
    };
    let value_key = scalars::key(dm_tree::constant_resolution::ScalarQuery::Const {
        owner: dm_ir::SymbolId::of("/datum/probe"),
        name: dm_ir::SymbolId::of("value"),
    });
    for (index, text) in cases.into_iter().enumerate() {
        let frontend = build(text);
        if let Some(previous) = &previous_tree {
            assert!(!Arc::ptr_eq(previous, &frontend.snapshot.tree));
        }
        previous_tree = Some(Arc::clone(&frontend.snapshot.tree));
        let (actual, scalar) = prepare_retained(&frontend, &engine, Some(&retained)).unwrap();
        let (fresh, fresh_scalar) = prepare(&frontend, &engine.snapshot).unwrap();
        assert_eq!(scalar.identity, fresh_scalar.identity);
        assert_eq!(scalar.outcomes, fresh_scalar.outcomes);
        assert_eq!(
            actual.configuration_identity(),
            fresh.configuration_identity()
        );
        let mut value_artifact = None;
        retained.values.visit_storage(|view| {
            if let dm_session::ObservedArtifactStorageView::Entry { key, value, .. } = view {
                if key.as_ref() == value_key.as_slice() {
                    if let Artifact::Scalar(value) = value.as_ref() {
                        value_artifact = Some(Arc::clone(value));
                    }
                }
            }
        });
        let value_artifact = value_artifact.expect("production scalar artifact populated");
        use dm_ir::Resolver;
        let certificate = actual
            .domain_version(meaning.domain())
            .expect("actual engine-qualified scalar receipt");
        assert_eq!(actual.resolve(meaning), fresh.resolve(meaning));
        assert_eq!(
            scalar.domain_version(meaning.domain()),
            value_artifact.certificate().map(u128::from)
        );
        if index == 1 {
            assert_eq!(previous_certificate, Some(certificate));
        }
        if index == 2 {
            assert_ne!(previous_certificate, Some(certificate));
        }
        previous_certificate = Some(certificate);
        if index == 1 {
            assert!(retained.scalar_hits.load(Ordering::Relaxed) > 0);
            assert!(Arc::ptr_eq(
                previous_scalar_artifact.as_ref().unwrap(),
                &value_artifact
            ));
        }
        if index == 2 {
            assert!(!Arc::ptr_eq(
                previous_scalar_artifact.as_ref().unwrap(),
                &value_artifact
            ));
        }
        previous_scalar_artifact = Some(value_artifact);
        assert!(Arc::ptr_eq(
            &scalar.source.occurrences,
            &frontend.snapshot.occurrences
        ));
        assert_eq!(retained.constant_hits.load(Ordering::Relaxed), index as u64);
        assert_eq!(retained.runtime_hits.load(Ordering::Relaxed), index as u64);
    }
    let added = build("/datum/probe\n    var/const/value = 4\n/datum/added_type\n");
    let (_, scalar) = prepare_retained(&added, &engine, Some(&retained)).unwrap();
    let (_, fresh) = prepare(&added, &engine.snapshot).unwrap();
    assert_eq!(scalar.identity, fresh.identity);
    assert_eq!(retained.constant_hits.load(Ordering::Relaxed), 3);
    assert_eq!(retained.runtime_hits.load(Ordering::Relaxed), 2);
    let removed = build("/datum/probe\n    var/const/value = 4\n");
    prepare_retained(&removed, &engine, Some(&retained)).unwrap();
    assert_eq!(retained.constant_hits.load(Ordering::Relaxed), 4);
    assert_eq!(retained.runtime_hits.load(Ordering::Relaxed), 2);
    retained.values.visit_storage(|view| {
        if let dm_session::ObservedArtifactStorageView::Store { entries, .. } = view {
            assert_eq!(
                entries,
                4 + prepare(&removed, &engine.snapshot)
                    .unwrap()
                    .1
                    .outcomes
                    .len()
            );
        }
    });
}
