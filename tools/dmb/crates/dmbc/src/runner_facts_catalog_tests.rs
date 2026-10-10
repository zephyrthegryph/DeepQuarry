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
        "/datum/probe\n    var/const/value = 3\n    var/extra = 1\n    proc/read_value()\n        return value\n",
        "/datum/probe\n    var/const/value = 4\n    var/extra = 1\n    proc/read_value()\n        return value\n    proc/new_proc()\n        return 2\n",
    ];
    for (index, text) in cases.into_iter().enumerate() {
        let frontend = build(text);
        let (actual, scalar) = prepare_retained(&frontend, &engine, Some(&retained)).unwrap();
        let (fresh, fresh_scalar) = prepare(&frontend, &engine.snapshot).unwrap();
        assert_eq!(scalar.identity, fresh_scalar.identity);
        assert_eq!(scalar.outcomes, fresh_scalar.outcomes);
        assert_eq!(
            actual.configuration_identity(),
            fresh.configuration_identity()
        );
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
            assert_eq!(entries, 3);
        }
    });
}
