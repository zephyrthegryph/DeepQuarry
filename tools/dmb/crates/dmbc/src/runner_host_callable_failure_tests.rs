//! Callable owner pruning after a frontend successor, before startup capture.
use super::*;
use std::path::Path;
struct Text(&'static str);
impl dm_preprocess::SourceProvider for Text {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn frontend(
    host: &mut BuildHost,
    pool: &dm_exec::BuildExecutor,
    text: &'static str,
) -> dm_tree::frontend::FrontendRevision {
    dm_tree::frontend::FrontendRevision::new(
        dm_tree::frontend::build_with_executor_and_semantic_state(
            Path::new("callable-failure.dme"),
            &Text(text),
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: None,
                observer: None,
            },
            None,
            pool,
            host.semantic.as_mut(),
        )
        .unwrap(),
    )
}
#[test]
fn post_frontend_pruning_keeps_current_callable_owner_and_releases_detached_predecessor() {
    let mut host = BuildHost::default();
    let memo = host.procedure_memo(3, None, true).unwrap();
    let store = Arc::clone(memo.startup.as_ref().unwrap());
    let pool = dm_exec::BuildExecutor::new(1).unwrap();
    let old = frontend(&mut host, &pool, "/proc/p()\n    return 1\n");
    let weak_old = Arc::downgrade(&old.snapshot.tree);
    {
        let arena = dm_tree::frontend::BodyArena::new(&old);
        let facts = crate::startup::capture_revision_facts_with_executor_and_bodies_and_artifacts(
            &old,
            &[],
            &pool,
            &arena,
            Some(&store),
        )
        .unwrap();
        drop(facts);
    }
    let mut first = None;
    store.visit_callable_storage(|view| {
        if let dm_session::ObservedArtifactStorageView::Entry { value, .. } = view {
            first = Some(Arc::clone(value));
        }
    });
    host.prune_foreign_callable_index();
    let mut same = None;
    store.visit_callable_storage(|view| {
        if let dm_session::ObservedArtifactStorageView::Entry { value, .. } = view {
            same = Some(Arc::clone(value));
        }
    });
    assert!(Arc::ptr_eq(first.as_ref().unwrap(), same.as_ref().unwrap()));
    // A request can fail after the new semantic owner is installed and before
    // startup capture. Do not insert a successor callable entry in this fixture.
    let successor = frontend(
        &mut host,
        &pool,
        "/proc/p()\n    return 1\n/proc/q()\n    return 2\n",
    );
    drop(old);
    assert!(weak_old.upgrade().is_some());
    host.prune_foreign_callable_index();
    assert!(weak_old.upgrade().is_none());
    assert!(Arc::ptr_eq(&store, &host.startup.as_ref().unwrap().1));
    assert!(Arc::ptr_eq(
        &successor.snapshot.tree,
        host.query_tree().unwrap()
    ));
    host.prune_foreign_callable_index();
    let mut entries = 0;
    store.visit_callable_storage(|view| {
        if matches!(view, dm_session::ObservedArtifactStorageView::Entry { .. }) {
            entries += 1;
        }
    });
    assert_eq!(entries, 0);
}
