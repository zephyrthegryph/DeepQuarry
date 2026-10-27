use super::*;
use crate::frontend::{
    build_with_executor_and_semantic_state, ColdFrontend, FrontendConfig, RetainedSemanticTree,
};
use std::path::Path;

struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn build(state: &mut RetainedSemanticTree, source: &'static str) -> ColdFrontend {
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    build_with_executor_and_semantic_state(
        Path::new("member_names.dme"),
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
fn retained_member_name_inventory_tracks_add_delete_and_keeps_old_readers() {
    let mut state = RetainedSemanticTree::default();
    let first = build(
        &mut state,
        "/proc/root_only()\n    return 1\n/datum/a/proc/member()\n    return 1\n",
    );
    let original = first.snapshot.tree.member_callable_name_storage();
    assert_eq!(original.len(), 1);
    assert!(original.contains_key(&SymbolId::of("member")));
    assert!(!original.contains_key(&SymbolId::of("root_only")));

    let shifted = build(
        &mut state,
        "// source shift\n/proc/root_only()\n    return 2\n/datum/a/proc/member()\n    return 3\n",
    );
    assert!(Arc::ptr_eq(
        original,
        shifted.snapshot.tree.member_callable_name_storage()
    ));

    let added = build(&mut state,
        "/proc/root_only()\n    return 1\n/datum/a/proc/member()\n    return 1\n/datum/b/proc/new_member()\n    return 2\n");
    let additions = added.snapshot.tree.member_callable_name_storage();
    assert!(!Arc::ptr_eq(original, additions));
    assert!(additions.contains_key(&SymbolId::of("new_member")));
    assert!(!original.contains_key(&SymbolId::of("new_member")));

    let deleted = build(
        &mut state,
        "/proc/root_only()\n    return 1\n/datum/b/proc/new_member()\n    return 2\n",
    );
    let current = deleted.snapshot.tree.member_callable_name_storage();
    assert!(!current.contains_key(&SymbolId::of("member")));
    assert!(current.contains_key(&SymbolId::of("new_member")));
    assert!(original.contains_key(&SymbolId::of("member")));
    assert!(additions.contains_key(&SymbolId::of("member")));
}

#[test]
fn source_verbs_issue_member_name_availability_without_admitting_globals() {
    let mut state = RetainedSemanticTree::default();
    let output = build(
        &mut state,
        "/proc/root_only()\n    return 1\n/datum/a/verb/verb_only()\n    return 1\n",
    );
    let tree = &output.snapshot.tree;
    assert_eq!(
        tree.source_member_callable_name(SymbolId::of("verb_only")),
        Some(true)
    );
    assert_eq!(
        tree.source_member_callable_name(SymbolId::of("root_only")),
        None
    );
    assert_eq!(
        tree.source_member_callable_name(SymbolId::of("absent")),
        None
    );
}

#[test]
fn stable_roster_metadata_edits_preserve_authenticated_member_name_owner() {
    let mut state = RetainedSemanticTree::default();
    let first = build(
        &mut state,
        "/datum/a\n    var/value = 1\n    proc/member(arg = 2)\n        return arg\n",
    );
    let changed = build(
        &mut state,
        "/datum/a\n    var/value = 3\n    proc/member(arg = 4)\n        return arg\n",
    );
    let fresh = build(
        &mut RetainedSemanticTree::default(),
        "/datum/a\n    var/value = 3\n    proc/member(arg = 4)\n        return arg\n",
    );
    assert!(!Arc::ptr_eq(&first.snapshot.tree, &changed.snapshot.tree));
    assert!(Arc::ptr_eq(
        first.snapshot.tree.member_callable_name_storage(),
        changed.snapshot.tree.member_callable_name_storage()
    ));
    assert_eq!(
        changed.snapshot.tree.member_callable_name_storage(),
        fresh.snapshot.tree.member_callable_name_storage()
    );
    assert_eq!(
        changed
            .snapshot
            .tree
            .member_callable_name_storage()
            .get(&SymbolId::of("member")),
        Some(&1)
    );
    // The semantic update is real, even though declaration-name authority stays
    // unchanged. Exact query replay must observe the new default.
    let query = dm_ir::ResolveQuery::Var {
        owner: SymbolId::of("/datum/a"),
        name: SymbolId::of("value"),
    };
    assert_ne!(
        dm_ir::Resolver::resolve(first.snapshot.tree.as_ref(), query),
        dm_ir::Resolver::resolve(changed.snapshot.tree.as_ref(), query)
    );
}
