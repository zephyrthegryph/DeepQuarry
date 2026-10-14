use super::*;
use std::path::Path;
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn frontend(
    state: &mut RetainedSemanticTree,
    source: &'static str,
) -> crate::frontend::ColdFrontend {
    let pool = dm_exec::BuildExecutor::new(1).unwrap();
    crate::frontend::build_with_executor_and_semantic_state(
        Path::new("lifecycle.dme"),
        &Source(source),
        &Default::default(),
        crate::frontend::FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
        None,
        &pool,
        Some(state),
    )
    .unwrap()
}
#[test]
fn replacement_discards_foreign_roster_before_next_body_binding_and_same_tree_preserves_it() {
    let mut state = RetainedSemanticTree::new();
    let first = frontend(&mut state, "/proc/p()\n    return 1\n");
    let roster = Arc::clone(first.callable_roster().unwrap());
    state.discard_foreign_callable_roster(&first.snapshot.tree);
    assert!(Arc::ptr_eq(
        state.callable_roster.as_ref().unwrap(),
        &roster
    ));
    let mut other = RetainedSemanticTree::new();
    let candidate = frontend(
        &mut other,
        "/proc/p()\n    return 1\n/proc/q()\n    return 2\n",
    );
    let weak_roster = Arc::downgrade(&roster);
    drop(roster);
    drop(first);
    // Exercise the production post-tree/pre-body-index boundary directly: no
    // new body roster is issued, as when following body collection fails.
    state.discard_foreign_callable_roster(&candidate.snapshot.tree);
    assert!(state.callable_roster.is_none());
    assert!(weak_roster.upgrade().is_none());
}
