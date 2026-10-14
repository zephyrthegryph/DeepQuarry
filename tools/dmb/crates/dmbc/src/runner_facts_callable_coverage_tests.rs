use super::*;
use dm_ir::{ResolveQuery as Q, Resolver, SymbolId};
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
#[test]
fn callable_coverage_owner_reuses_default_and_source_moves_and_replaces_names() {
    let mut build_host = crate::runner_host::BuildHost::default();
    let engine = build_host
        .engine(
            "coverage.dme".into(),
            Default::default(),
            true,
            include_bytes!("../../../fixtures/native_template.bin").to_vec(),
        )
        .unwrap();
    let retained = build_host.host_facts().unwrap();
    let mut previous = None;
    for (text, reuse) in [
        ("/datum/probe\n    var/value = 1\n    proc/member_only()\n        return 1\n", false),
        ("/datum/probe\n    var/value = 2\n    proc/member_only()\n        return 1\n", true),
        ("// moved source lines\n\n/datum/probe\n    var/value = 2\n    var/added = 3\n    proc/member_only()\n        return 1\n", true),
        ("/datum/probe/proc/renamed()\n    return 1\n", false),
        ("/datum/probe/proc/renamed()\n    return 1\n/datum/probe/proc/another()\n    return 2\n", false),
        ("/datum/probe\n", false),
    ] {
        let front = dm_tree::frontend::build_with_config(std::path::Path::new("coverage.dme"), &Source(text),
            &Default::default(), dm_tree::frontend::FrontendConfig {workers: 1, engine: Some(engine.frontend_seed()), observer: None}).unwrap();
        let (host, _) = prepare_retained(&front, &engine, Some(&retained)).unwrap();
        let (fresh, _) = prepare(&front, &engine.snapshot).unwrap();
        for name in ["member_only", "renamed", "another", "never_authored"] {
            for query in [Q::GlobalProc(SymbolId::of(name)), Q::HasMemberProc {owner: SymbolId::of("/datum/probe"), name: SymbolId::of(name)}] {
                assert_eq!(host.resolve(query), fresh.resolve(query));
            }
        }
        let current = host.callable_exclusions().unwrap().clone();
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
}
