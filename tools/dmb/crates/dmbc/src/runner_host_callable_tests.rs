use super::*;
use std::path::Path;
struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok("/proc/p()\n    return 1\n".into())
    }
}
#[test]
fn clear_regions_releases_callable_tree_without_replacing_static_artifact_owner() {
    let mut host = BuildHost::default();
    let memo = host.procedure_memo(3, None).unwrap();
    let store = Arc::clone(memo.startup.as_ref().unwrap());
    let revision = dm_tree::frontend::FrontendRevision::new(
        dm_tree::frontend::build(Path::new("callable.dme"), &Source, &Default::default(), 1)
            .unwrap(),
    );
    let weak = Arc::downgrade(&revision.snapshot.tree);
    let pool = dm_exec::BuildExecutor::new(1).unwrap();
    {
        let arena = dm_tree::frontend::BodyArena::new(&revision);
        let facts = crate::startup::capture_revision_facts_with_executor_and_bodies_and_artifacts(
            &revision,
            &[],
            &pool,
            &arena,
            Some(&store),
        )
        .unwrap();
        drop(facts);
    }
    drop(revision);
    assert!(
        weak.upgrade().is_some(),
        "the observed callable answer owns the old tree"
    );
    host.clear_regions();
    assert!(
        weak.upgrade().is_none(),
        "output-only clearing must release the detached tree"
    );
    assert!(
        Arc::ptr_eq(&store, &host.startup.as_ref().unwrap().1),
        "clear only the callable index, preserving static artifacts"
    );
}
