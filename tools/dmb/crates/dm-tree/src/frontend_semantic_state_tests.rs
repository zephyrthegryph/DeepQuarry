use super::*;
use crate::frontend::{
    build_with_executor_and_semantic_state, BodyArena, FrontendConfig, FrontendRevision,
};
use std::{collections::BTreeMap, path::Path};
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn build(state: &mut RetainedSemanticTree, source: &'static str) -> crate::frontend::ColdFrontend {
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    build_with_executor_and_semantic_state(
        Path::new("project.dme"),
        &Source(source),
        &BTreeMap::new(),
        FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
        None,
        &executor,
        Some(state),
    )
    .unwrap()
}
#[test]
fn body_edit_shares_semantics_but_issues_new_source_occurrences_and_body() {
    let mut state = RetainedSemanticTree::new();
    let first = FrontendRevision::new(build(
        &mut state,
        "/proc/p()\n    return 1\n/proc/q()\n    return 2\n",
    ));
    let original_issuance = first.issuance();
    let second = FrontendRevision::new(build(
        &mut state,
        "/proc/p()\n    return 12345\n/proc/q()\n    return 2\n",
    ));
    assert!(Arc::ptr_eq(&first.snapshot.tree, &second.snapshot.tree));
    assert!(!Arc::ptr_eq(
        &first.snapshot.occurrences,
        &second.snapshot.occurrences
    ));
    assert!(!original_issuance.matches(&second));
    assert_ne!(
        first.bodies[1].expanded_span.start,
        second.bodies[1].expanded_span.start
    );
    let arena = BodyArena::new(&second);
    assert!(arena.with_parsed(&first.bodies[0], |_| ()).is_err());
    let parsed = arena.take_parsed(&second.bodies[0]).unwrap();
    assert_eq!(parsed.item().children[0].header, "return 12345");
    assert_eq!((state.hits(), state.rebuilds()), (1, 1));
}
#[test]
fn ordered_declarations_and_defaults_invalidate_tree_and_match_fresh_result() {
    let mut state = RetainedSemanticTree::new();
    let first = build(&mut state, "var/a = 1\nvar/b = 2\n");
    let reordered = build(&mut state, "var/b = 2\nvar/a = 1\n");
    assert!(!Arc::ptr_eq(&first.snapshot.tree, &reordered.snapshot.tree));
    let changed = build(&mut state, "var/b = 2\nvar/a = 3\n");
    assert!(!Arc::ptr_eq(
        &reordered.snapshot.tree,
        &changed.snapshot.tree
    ));
    let fresh = build(&mut RetainedSemanticTree::new(), "var/b = 2\nvar/a = 3\n");
    assert_eq!(
        changed.snapshot.tree.identity(),
        fresh.snapshot.tree.identity()
    );
    assert_eq!(
        changed.snapshot.tree.declarations(),
        fresh.snapshot.tree.declarations()
    );
    assert_eq!((state.hits(), state.rebuilds()), (0, 3));
}
#[test]
fn invalid_current_declaration_reports_current_origin_without_poisoning_retained_tree() {
    let mut state = RetainedSemanticTree::new();
    let valid = build(&mut state, "var/a = 1\n");
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let result = build_with_executor_and_semantic_state(
        Path::new("project.dme"),
        &Source("\n\nvar/a = 1\nvar/a = 2\n"),
        &BTreeMap::new(),
        FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
        None,
        &executor,
        Some(&mut state),
    );
    let errors = match result {
        Err(errors) => errors,
        Ok(_) => panic!("duplicate declaration accepted"),
    };
    assert!(errors.iter().any(|error| error
        .location
        .as_ref()
        .is_some_and(|location| location.line == 4)));
    let repeated = build(&mut state, "var/a = 1\n");
    assert!(Arc::ptr_eq(&valid.snapshot.tree, &repeated.snapshot.tree));
    assert_eq!((state.hits(), state.rebuilds()), (1, 1));
}
