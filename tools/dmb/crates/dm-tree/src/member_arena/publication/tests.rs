use super::*;
use crate::frontend::{
    build_with_executor_and_semantic_state, FrontendConfig, RetainedSemanticTree,
};
use crate::*;
use std::{collections::BTreeMap, path::Path};
struct Source(String);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.clone())
    }
}
fn build(
    source: &str,
    state: &mut RetainedSemanticTree,
    executor: &dm_exec::BuildExecutor,
) -> crate::frontend::ColdFrontend {
    build_with_executor_and_semantic_state(
        Path::new("publication.dme"),
        &Source(source.into()),
        &BTreeMap::new(),
        FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
        None,
        executor,
        Some(state),
    )
    .unwrap()
}
fn same_current(a: &SemanticTree, b: &SemanticTree) {
    assert_eq!(
        a.members().iter().collect::<Vec<_>>(),
        b.members().iter().collect::<Vec<_>>()
    );
    assert_eq!(a.declarations(), b.declarations());
    assert_eq!(a.types().len(), b.types().len());
    for (a, b) in a.types().iter().zip(b.types().iter()) {
        assert_eq!(
            (
                a.path,
                a.parent,
                a.explicit_parent,
                a.synthetic,
                a.members.as_ref()
            ),
            (
                b.path,
                b.parent,
                b.explicit_parent,
                b.synthetic,
                b.members.as_ref()
            )
        );
    }
}
#[test]
fn structural_append_reuses_exact_final_owner_chunks_and_preserves_cow() {
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let mut state = RetainedSemanticTree::default();
    let original =
        "/obj/base\n    var/value = 1\n/obj/child\n    parent_type = /obj/base\n    value = 2\n";
    let first = build(original, &mut state, &executor);
    let edited = format!("{original}/obj/base/proc/added()\n    return 7\n");
    let next = build(&edited, &mut state, &executor);
    let fresh = build(&edited, &mut RetainedSemanticTree::default(), &executor);
    same_current(&next.snapshot.tree, &fresh.snapshot.tree);
    let old = first.snapshot.tree.members();
    let current = next.snapshot.tree.members();
    assert_eq!(old.chunks().len(), 2);
    assert!(Arc::ptr_eq(&old.chunks()[0], &current.chunks()[0]));
    assert!(Arc::ptr_eq(&old.chunks()[1], &current.chunks()[1]));
    let mut mutable = current.clone();
    mutable[0].content ^= 1;
    assert_ne!(mutable[0].content, current[0].content);
    assert!(!Arc::ptr_eq(&mutable.chunks()[0], &current.chunks()[0]));
    assert!(Arc::ptr_eq(&mutable.chunks()[1], &current.chunks()[1]));
    assert_eq!(
        current.iter().rev().map(|n| n.name).collect::<Vec<_>>(),
        (0..current.len())
            .rev()
            .map(|i| current[i].name)
            .collect::<Vec<_>>()
    );
    let mut iter = current.iter();
    assert_eq!(iter.next().unwrap(), &current[0]);
    assert_eq!(iter.next_back().unwrap(), &current[current.len() - 1]);
    assert_eq!(iter.len(), current.len() - 2);
}
#[test]
fn changed_dense_previous_and_owner_bindings_decline_old_chunks() {
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let mut state = RetainedSemanticTree::default();
    let original =
        "/obj/base\n    var/value = 1\n/obj/child\n    parent_type = /obj/base\n    value = 2\n";
    let first = build(original, &mut state, &executor);
    let edited = format!("/obj/earlier\n    var/other = 3\n{original}");
    let next = build(&edited, &mut state, &executor);
    let fresh = build(&edited, &mut RetainedSemanticTree::default(), &executor);
    same_current(&next.snapshot.tree, &fresh.snapshot.tree);
    for old in first.snapshot.tree.members().chunks() {
        assert!(next
            .snapshot
            .tree
            .members()
            .chunks()
            .iter()
            .all(|new| !Arc::ptr_eq(old, new)));
    }
    let owner = next
        .snapshot
        .tree
        .lookup_type(dm_ir::SymbolId::of("/obj/child"))
        .unwrap();
    let selected = next
        .snapshot
        .tree
        .resolve(owner, dm_ir::SymbolId::of("value"), MemberKind::Var)
        .unwrap();
    assert_eq!(
        next.snapshot.tree.members()[selected.index()].previous,
        Some(MemberId(1))
    );
    // Parent changes must be recomputed through the ordinary resolver before
    // any exact final chunk is selected.
    let reparented = "/obj/base\n    var/value = 1\n/obj/other\n    var/value = 5\n/obj/child\n    parent_type = /obj/other\n    value = 2\n";
    let next = build(reparented, &mut state, &executor);
    let fresh = build(reparented, &mut RetainedSemanticTree::default(), &executor);
    same_current(&next.snapshot.tree, &fresh.snapshot.tree);
    let owner = next
        .snapshot
        .tree
        .lookup_type(dm_ir::SymbolId::of("/obj/child"))
        .unwrap();
    let selected = next
        .snapshot
        .tree
        .resolve(owner, dm_ir::SymbolId::of("value"), MemberKind::Var)
        .unwrap();
    assert_eq!(
        next.snapshot.tree.members()[selected.index()].previous,
        Some(MemberId(1))
    );
    let removed = "/obj/base\n    var/value = 1\n/obj/child\n    parent_type = /obj/base\n";
    let next = build(removed, &mut state, &executor);
    let fresh = build(removed, &mut RetainedSemanticTree::default(), &executor);
    same_current(&next.snapshot.tree, &fresh.snapshot.tree);
}
#[test]
fn metadata_update_releases_previous_publication_without_changing_current_tree() {
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let mut state = RetainedSemanticTree::default();
    let original = "/obj/base\n    var/value = 1\n";
    let first = build(original, &mut state, &executor);
    let mut index = None;
    state.visit_normalization_storage(|view| {
        if let NormalizationStorageView::PublicationIndex { entries } = view {
            index = Some(entries);
        }
    });
    assert_eq!(index, Some(1));
    let edited = "/obj/base\n    var/value = 4\n";
    let next = build(edited, &mut state, &executor);
    assert!(state.metadata_updates() > 0);
    let fresh = build(edited, &mut RetainedSemanticTree::default(), &executor);
    same_current(&next.snapshot.tree, &fresh.snapshot.tree);
    index = None;
    state.visit_normalization_storage(|view| {
        if let NormalizationStorageView::PublicationIndex { entries } = view {
            index = Some(entries);
        }
    });
    assert_eq!(index, None);
    assert_ne!(
        first.snapshot.tree.members()[0],
        next.snapshot.tree.members()[0]
    );
}
