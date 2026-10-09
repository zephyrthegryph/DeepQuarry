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
#[test]
fn owned_declarations_reuse_with_fresh_current_file_and_source_issuance() {
    let source =
        "/obj/base\n    var/count=1\n/proc/p()\n    set name = \"Display\"\n    return 1\n";
    let mut state = RetainedSemanticTree::new();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let first = build_with_executor_and_semantic_state(
        Path::new("first.dme"),
        &Source(source),
        &BTreeMap::new(),
        FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
        None,
        &executor,
        Some(&mut state),
    )
    .unwrap();
    let second = build_with_executor_and_semantic_state(
        Path::new("second.dme"),
        &Source(source),
        &BTreeMap::new(),
        FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
        None,
        &executor,
        Some(&mut state),
    )
    .unwrap();
    assert!(state.declaration_retention_stats().hits > 0);
    assert!(Arc::ptr_eq(&first.snapshot.tree, &second.snapshot.tree));
    assert!(!Arc::ptr_eq(
        &first.snapshot.occurrences,
        &second.snapshot.occurrences
    ));
    assert_eq!(
        second.bodies[0].source.path.file_name().unwrap(),
        "second.dme"
    );
    assert_eq!(
        first.bodies[0].source.path.file_name().unwrap(),
        "first.dme"
    );
    let arena = BodyArena::new(&second);
    assert!(arena.with_parsed(&first.bodies[0], |_| ()).is_err());
    assert!(arena.with_parsed(&second.bodies[0], |_| ()).is_ok());
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
    assert_eq!(
        (state.hits(), state.rebuilds(), state.metadata_updates()),
        (0, 2, 1)
    );
}
#[test]
fn stable_metadata_updates_inherited_arrays_storage_and_selector_negatives_match_full_build() {
    use dm_ir::{ResolveQuery as Q, Resolver, SymbolId};
    let before = "/datum/base\n    var/static/shared = 1\n    var/list/data[2]\n/datum/base/child\n    shared = 2\n    data = list(1)\n/datum/other\n    var/static/unrelated = 3\n";
    let after = "/datum/base\n    var/shared = 4\n    var/list/data[4]\n/datum/base/child\n    shared = 2\n    data = list(1)\n/datum/other\n    var/static/unrelated = 3\n";
    let mut state = RetainedSemanticTree::new();
    let original = build(&mut state, before);
    let updated = build(&mut state, after);
    let full = build(&mut RetainedSemanticTree::new(), after);
    assert_eq!((state.rebuilds(), state.metadata_updates()), (1, 1));
    assert_eq!(
        updated.snapshot.tree.identity(),
        full.snapshot.tree.identity()
    );
    assert_eq!(
        updated.snapshot.tree.declarations(),
        full.snapshot.tree.declarations()
    );
    for (current, expected) in updated
        .snapshot
        .tree
        .members()
        .iter()
        .zip(full.snapshot.tree.members())
    {
        assert_eq!(current.owner, expected.owner);
        assert_eq!(current.previous, expected.previous);
        assert_eq!(current.metadata, expected.metadata);
        assert_eq!(current.content, expected.content);
    }
    for owner in ["/datum/base", "/datum/base/child", "/datum/other"] {
        let owner = SymbolId::of(owner);
        for name in ["shared", "data", "unrelated", "missing"] {
            let name = SymbolId::of(name);
            for query in [
                Q::Var { owner, name },
                Q::VarStorage { owner, name },
                Q::DeclaredVarType { owner, name },
                Q::UniqueStaticVar(name),
            ] {
                assert_eq!(
                    Resolver::resolve(updated.snapshot.tree.as_ref(), query),
                    Resolver::resolve(full.snapshot.tree.as_ref(), query)
                );
            }
        }
    }
    let unrelated = SymbolId::of("unrelated");
    let old = original
        .snapshot
        .tree
        .members()
        .iter()
        .find(|member| member.name == unrelated)
        .unwrap();
    let new = updated
        .snapshot
        .tree
        .members()
        .iter()
        .find(|member| member.name == unrelated)
        .unwrap();
    assert!(Arc::ptr_eq(&old.metadata, &new.metadata));
    assert!(!Arc::ptr_eq(
        &original.snapshot.occurrences,
        &updated.snapshot.occurrences
    ));
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
