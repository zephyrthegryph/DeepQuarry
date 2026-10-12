use super::*;
use std::path::Path;
struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok("/proc/probe()\n    return 7\n".into())
    }
}
#[test]
fn optional_detachment_preserves_current_source_query_and_classification_until_last_tier() {
    let mut host = BuildHost::default();
    let engine = host
        .engine(
            PathBuf::from("optional.dme"),
            Default::default(),
            true,
            include_bytes!("../../../fixtures/native_template.bin").to_vec(),
        )
        .unwrap();
    let pool = dm_exec::BuildExecutor::new(1).unwrap();
    let frontend = dm_tree::frontend::build_with_executor_and_semantic_state(
        Path::new("optional.dme"),
        &Source,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(engine.frontend_seed()),
            observer: None,
        },
        None,
        &pool,
        host.semantic.as_mut(),
    )
    .unwrap();
    let mut query = query_snapshot::QueryAttempt::new(host.query_state(), true);
    query.capture(&frontend);
    query.finish_analyzed();
    let source_revision = host
        .query_state
        .lock()
        .unwrap()
        .snapshot
        .as_ref()
        .unwrap()
        .source_revision;
    let tree = Arc::clone(host.semantic.as_ref().unwrap().snapshot_tree().unwrap());
    let memo = host.procedure_memo(17, None, true).unwrap();
    let (resolver, _) = crate::request_runner::runner_facts::prepare(&frontend, &engine).unwrap();
    struct NoDefaults;
    impl crate::class_projection::TypeValuePolicy for NoDefaults {
        fn tag(&self, _: dm_ir::SymbolId) -> Result<u8, crate::class_projection::ProjectionError> {
            Err(crate::class_projection::ProjectionError::Unsupported(
                "fixture has no type defaults".into(),
            ))
        }
    }
    crate::compile_driver::compile_observed_with_memo(
        &frontend,
        &resolver,
        &engine.snapshot,
        &engine.bytes,
        engine.link_overlay().unwrap(),
        &NoDefaults,
        None,
        Vec::new(),
        None,
        1,
        None,
        Some(&memo),
    )
    .unwrap();
    memo.publish_successful();
    drop(memo);
    let symbolic = Arc::downgrade(&host.symbolic.as_ref().unwrap().1);
    let startup = Arc::downgrade(&host.startup.as_ref().unwrap().1);
    let abi = Arc::downgrade(&host.abi.as_ref().unwrap().1);
    let initializers = Arc::downgrade(&host.initializers.as_ref().unwrap().1);
    let state = host.query_state();
    drop(frontend);
    drop(query);
    host.release_idle_compiler_artifacts();
    assert_eq!(symbolic.upgrade().unwrap().retention_stats().records, 1);
    host.release_idle_optional_images();
    assert!(
        symbolic.upgrade().is_some(),
        "bounded symbolic core survives auxiliary images"
    );
    assert_eq!(symbolic.upgrade().unwrap().retention_stats().records, 1);
    assert!(startup.upgrade().is_none());
    assert!(abi.upgrade().is_none());
    assert!(initializers.upgrade().is_some());
    assert!(Arc::ptr_eq(
        &tree,
        host.semantic.as_ref().unwrap().snapshot_tree().unwrap()
    ));
    assert!(Arc::ptr_eq(&state, &host.query_state()));
    assert_eq!(
        state
            .lock()
            .unwrap()
            .snapshot
            .as_ref()
            .unwrap()
            .source_revision,
        source_revision
    );
    host.release_idle_compact_symbolic();
    assert!(symbolic.upgrade().is_none());
    assert!(initializers.upgrade().is_some());
    assert!(Arc::ptr_eq(
        &tree,
        host.semantic.as_ref().unwrap().snapshot_tree().unwrap()
    ));
    host.release_idle_remaining_optional();
    assert!(initializers.upgrade().is_none());
    assert!(Arc::ptr_eq(
        &tree,
        host.semantic.as_ref().unwrap().snapshot_tree().unwrap()
    ));
    assert_eq!(
        state
            .lock()
            .unwrap()
            .snapshot
            .as_ref()
            .unwrap()
            .source_revision,
        source_revision
    );
    // Final session detachment remains a separate operation, not an optional tier.
    drop(state);
    drop(tree);
    let query_state = Arc::downgrade(&host.query_state);
    drop(host);
    assert!(query_state.upgrade().is_none());
}
