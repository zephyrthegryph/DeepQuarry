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
    let pool = dm_exec::BuildExecutor::new(1).unwrap();
    let frontend = dm_tree::frontend::build_with_executor_and_semantic_state(
        Path::new("optional.dme"),
        &Source,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: None,
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
    drop(memo);
    let symbolic = Arc::downgrade(&host.symbolic.as_ref().unwrap().1);
    let startup = Arc::downgrade(&host.startup.as_ref().unwrap().1);
    let abi = Arc::downgrade(&host.abi.as_ref().unwrap().1);
    let initializers = Arc::downgrade(&host.initializers.as_ref().unwrap().1);
    let state = host.query_state();
    drop(frontend);
    drop(query);
    host.release_idle_compiler_artifacts();
    host.release_idle_optional_images();
    assert!(symbolic.upgrade().is_none());
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
