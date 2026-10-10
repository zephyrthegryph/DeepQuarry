use super::*;
use dm_ir::{ResolveQuery as Q, Resolver, SymbolId};
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
#[test]
fn variable_coverage_owner_reuses_defaults_and_invalidates_inherited_names() {
    let mut build_host = crate::runner_host::BuildHost::default();
    let engine = build_host
        .engine(
            "variable-coverage.dme".into(),
            Default::default(),
            true,
            include_bytes!("../../../fixtures/native_template.bin").to_vec(),
        )
        .unwrap();
    let retained = build_host.host_facts().unwrap();
    let mut previous = None;
    for (text, reuse) in [
        ("/datum/base\n    var/value = 1\n/datum/base/child\n", false),
        ("/datum/base\n    var/value = 2\n/datum/base/child\n", true),
        ("// moved source\n/datum/base\n    var/const/value = 2\n    proc/added()\n        return 1\n/datum/base/child\n", true),
        ("/datum/base\n    var/renamed = 2\n/datum/base/child\n", false),
        ("/datum/base\n    var/renamed = 2\n    var/another = 3\n/datum/base/child\n", false),
        ("/datum/base\n/datum/base/child\n    var/renamed = 2\n", false),
        ("/datum/base\n/datum/base/child\n", false),
    ] {
        let front = dm_tree::frontend::build_with_config(std::path::Path::new("variable-coverage.dme"), &Source(text),
            &Default::default(), dm_tree::frontend::FrontendConfig {workers: 1, engine: Some(engine.frontend_seed()), observer: None}).unwrap();
        let (host, _) = prepare_retained(&front, &engine, Some(&retained)).unwrap();
        let (fresh, _) = prepare(&front, &engine.snapshot).unwrap();
        for name in ["value", "renamed", "another", "never_authored"] {
            for query in [Q::GlobalVar(SymbolId::of(name)), Q::HasMemberVar {owner: SymbolId::of("/datum/base/child"), name: SymbolId::of(name)}] {
                assert_eq!(host.resolve(query), fresh.resolve(query));
            }
        }
        let current = host.variable_coverage_owner().unwrap().clone();
        if let Some(previous) = &previous {
            assert_eq!(Arc::ptr_eq(previous, &current), reuse);
        }
        previous = Some(current);
        let mut stages = 0;
        retained.values.visit_storage(|view| {
            if let dm_session::ObservedArtifactStorageView::Entry {key, ..} = view {if key.as_ref() == KEY { stages += 1; }}
        });
        assert_eq!(stages, 1, "current-revision stage has no historical coverage owners");
    }
    let mut other_build_host = crate::runner_host::BuildHost::default();
    let other_engine = other_build_host
        .engine(
            "variable-coverage.dme".into(),
            Default::default(),
            true,
            include_bytes!("../../../fixtures/native_template.bin").to_vec(),
        )
        .unwrap();
    assert_eq!(engine.snapshot.identity(), other_engine.snapshot.identity());
    assert!(!Arc::ptr_eq(&engine, &other_engine));
    let front = dm_tree::frontend::build_with_config(
        std::path::Path::new("variable-coverage.dme"),
        &Source("/datum/base\n/datum/base/child\n"),
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(other_engine.frontend_seed()),
            observer: None,
        },
    )
    .unwrap();
    let (host, _) = prepare_retained(&front, &other_engine, Some(&retained)).unwrap();
    assert!(
        !Arc::ptr_eq(
            previous.as_ref().unwrap(),
            host.variable_coverage_owner().unwrap()
        ),
        "independently captured equal engine/catalog owners must decline old coverage"
    );
}
