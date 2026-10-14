use super::*;
use std::{path::Path, sync::Arc};
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn revision(source: &'static str) -> dm_tree::frontend::FrontendRevision {
    dm_tree::frontend::FrontendRevision::new(
        dm_tree::frontend::build(
            Path::new("startup.dme"),
            &Source(source),
            &Default::default(),
            1,
        )
        .unwrap(),
    )
}
#[test]
fn prepared_startup_matches_fresh_after_shift_body_and_static_layout_changes() {
    let executor = dm_exec::BuildExecutor::new(2).unwrap();
    let store = StartupArtifacts::default();
    let mut previous = None;
    for source in [
        "/proc/p()\n    var/static/cache = 3\n    return cache\n/proc/q()\n    return 1\n",
        "// shifted\n/proc/p()\n    var/static/cache = 3\n    return cache + 1\n/proc/q()\n    return 2\n",
        "// shifted\n/proc/p()\n    var/static/cache = 4\n    return cache + 1\n/proc/q()\n    var/static/new_cache = 5\n    return new_cache\n",
    ].into_iter().enumerate() {
        let (index, source) = source;
        let frontend = revision(source);
        let roster = crate::lowering::PreparedBodyRoster::issue(&frontend).ok().unwrap();
        for row in roster.ordered() {
            assert!(std::ptr::eq(roster.current(row.body()).unwrap().input(), row.input()));
            assert!(roster.current(&row.body().clone()).is_none());
        }
        let arena = dm_tree::frontend::BodyArena::new(&frontend);
        let actual = capture_with_prepared_bodies(&frontend, Some(&frontend), &[], &executor,
            &arena, Some(&store), &roster).unwrap();
        let fresh_arena = dm_tree::frontend::BodyArena::new(&frontend);
        let fresh = capture_revision_facts_with_executor_and_bodies(&frontend, &[], &executor,
            &fresh_arena).unwrap();
        assert_eq!(actual.plan.writes, fresh.plan.writes);
        assert_eq!(actual.plan.origins, fresh.plan.origins);
        assert_eq!(actual.procedure_index, fresh.procedure_index);
        assert_eq!(actual.procedures().map(|(_, plan)| plan.procedure).collect::<Vec<_>>(),
            fresh.procedures.iter().map(|(_, plan)| plan.procedure).collect::<Vec<_>>());
        assert!(actual.validate_for(&frontend).is_ok());
        if let Some(old) = previous.as_ref() {
            assert_eq!(Arc::ptr_eq(old, &actual.static_inventory), index == 1);
        }
        previous = Some(Arc::clone(&actual.static_inventory));
    }
}
#[test]
fn foreign_prepared_roster_uses_current_capture_and_foreign_revision_declines() {
    let original = revision("/proc/p()\n    var/static/cache = 3\n    return cache\n");
    let current = revision("\n/proc/p()\n    var/static/cache = 4\n    return cache\n");
    let roster = crate::lowering::PreparedBodyRoster::issue(&original)
        .ok()
        .unwrap();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let arena = dm_tree::frontend::BodyArena::new(&current);
    let actual = capture_with_prepared_bodies(
        &current,
        Some(&current),
        &[],
        &executor,
        &arena,
        None,
        &roster,
    )
    .unwrap();
    let fresh =
        capture_revision_facts_with_executor_and_bodies(&current, &[], &executor, &arena).unwrap();
    assert_eq!(actual.plan.writes, fresh.plan.writes);
    assert_eq!(actual.plan.origins, fresh.plan.origins);
    assert!(capture_with_prepared_bodies(
        &current,
        Some(&original),
        &[],
        &executor,
        &arena,
        None,
        &roster
    )
    .is_err());
}
