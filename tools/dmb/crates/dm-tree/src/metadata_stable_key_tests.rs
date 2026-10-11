use super::*;
use crate::{build, MemberMetadata};
use std::sync::Arc;
#[test]
fn inheritance_noop_preserves_shared_metadata_but_divergence_detaches() {
    let (tree, _) = captured(false);
    let id = tree
        .members
        .iter()
        .enumerate()
        .find(|(_, member)| member.kind == MemberKind::Var && member.previous.is_some())
        .map(|(index, _)| MemberId(index as u32))
        .unwrap();
    let original = Arc::clone(&tree.members[id.index()].metadata);
    let mut members = tree.members.clone();
    resolve_metadata(&tree, &mut members, &[id]);
    assert!(Arc::ptr_eq(&members[id.index()].metadata, &original));
    Arc::make_mut(&mut members[id.index()].metadata).flags ^= 1;
    let changed = Arc::clone(&members[id.index()].metadata);
    resolve_metadata(&tree, &mut members, &[id]);
    assert!(!Arc::ptr_eq(&members[id.index()].metadata, &changed));
    assert_eq!(members[id.index()].metadata, original);
    assert_ne!(changed.flags, original.flags);
}
fn captured(extra: bool) -> (SemanticTree, MetadataDependencies) {
    let (tree, index) = captured_inputs(extra, false);
    let graph = MetadataDependencies::capture(&tree, &index).unwrap();
    (tree, graph)
}
fn captured_inputs(extra: bool, reparent: bool) -> (SemanticTree, KeyedDeclarations) {
    let mut symbols = dm_ir::SymbolTable::default();
    let root = symbols.intern("/").unwrap();
    let base = symbols.intern("/datum/base").unwrap();
    let child = symbols.intern("/datum/base/child").unwrap();
    let name = symbols.intern("value").unwrap();
    let other = symbols.intern("other").unwrap();
    let alternate = symbols.intern("/datum/alternate").unwrap();
    let mut rows = vec![
        Skeleton::Type {
            path: root,
            explicit_parent: None,
        },
        Skeleton::Type {
            path: base,
            explicit_parent: None,
        },
        Skeleton::Type {
            path: child,
            explicit_parent: reparent.then_some(alternate),
        },
    ];
    if reparent {
        rows.push(Skeleton::Type {
            path: alternate,
            explicit_parent: None,
        });
        rows.push(Skeleton::Member {
            owner: alternate,
            name,
            kind: MemberKind::Var,
            mode: DefinitionMode::Declare,
            metadata: Arc::new(MemberMetadata::default()),
            content: 0,
        });
    }
    if extra {
        rows.push(Skeleton::Member {
            owner: root,
            name: other,
            kind: MemberKind::Var,
            mode: DefinitionMode::Declare,
            metadata: Arc::new(MemberMetadata::default()),
            content: 0,
        });
    }
    if extra {
        let proc_name = symbols.intern("new_run").unwrap();
        rows.push(Skeleton::Member {
            owner: base,
            name: proc_name,
            kind: MemberKind::Proc,
            mode: DefinitionMode::Declare,
            metadata: Arc::new(MemberMetadata::default()),
            content: 0,
        });
    }
    for (owner, mode) in [
        (base, DefinitionMode::Declare),
        (child, DefinitionMode::Override),
    ] {
        rows.push(Skeleton::Member {
            owner,
            name,
            kind: MemberKind::Var,
            mode,
            metadata: Arc::new(MemberMetadata::default()),
            content: 0,
        });
    }
    let tree = build(symbols, &rows).unwrap();
    let (index, _) = KeyedDeclarations::capture(None, &rows).unwrap();
    (tree, index)
}
#[test]
fn dependency_edges_use_stable_source_keys_after_unrelated_dense_id_insertion() {
    let (_, before) = captured(false);
    let (_, after) = captured(true);
    let base = dm_ir::SymbolId::of("/datum/base");
    let old = before
        .nodes
        .iter()
        .find(|node| node.key.owner == base)
        .unwrap();
    let new = after.nodes.iter().find(|node| node.key == old.key).unwrap();
    assert_ne!(old.member, new.member);
    assert_eq!(old.key, new.key);
    assert_eq!(old.dependants, new.dependants);
    assert_eq!(old.dependants.as_ref().unwrap().len(), 1);
    let child = old.dependants.as_ref().unwrap()[0];
    assert_eq!(before.nodes[before.slot(child).unwrap()].key, child);
    assert_eq!(after.nodes[after.slot(child).unwrap()].key, child);
    assert_ne!(
        before.nodes[before.slot(child).unwrap()].member,
        after.nodes[after.slot(child).unwrap()].member
    );
}

#[test]
fn structural_capture_rebases_ids_and_shares_only_current_exact_edges() {
    let (before_tree, before_index) = captured_inputs(false, false);
    let before = MetadataDependencies::capture(&before_tree, &before_index).unwrap();
    let (after_tree, after_index) = captured_inputs(true, false);
    let delta = after_index.delta_since(&before_index);
    assert!(delta.order_changed);
    assert_eq!(delta.changes.len(), 2);
    assert!(delta.changes[0].previous.is_none());
    let after = MetadataDependencies::capture_rebased(
        &after_tree,
        &after_index,
        Some((&before, &before_index)),
    )
    .unwrap();
    let fresh = MetadataDependencies::capture(&after_tree, &after_index).unwrap();
    for node in &after.nodes {
        let fresh_node = &fresh.nodes[fresh.slot(node.key).unwrap()];
        assert_eq!(node.member, fresh_node.member);
        assert_eq!(node.dependants, fresh_node.dependants);
    }
    let base = dm_ir::SymbolId::of("/datum/base");
    let old = before
        .nodes
        .iter()
        .find(|node| node.key.owner == base)
        .unwrap();
    let new = &after.nodes[after.slot(old.key).unwrap()];
    assert_ne!(old.member, new.member);
    assert!(Arc::ptr_eq(
        old.dependants.as_ref().unwrap(),
        new.dependants.as_ref().unwrap()
    ));
    let (parent_tree, parent_index) = captured_inputs(true, true);
    let parent_delta = parent_index.delta_since(&after_index);
    assert!(parent_delta.changes.iter().any(|change| change.key.owner
        == dm_ir::SymbolId::of("/datum/base/child")
        && change.key.family == crate::declaration_contributions::DeclarationFamily::Type));
    let parent = MetadataDependencies::capture_rebased(
        &parent_tree,
        &parent_index,
        Some((&after, &after_index)),
    )
    .unwrap();
    let new_base = &parent.nodes[parent.slot(old.key).unwrap()];
    assert!(new_base.dependants.is_none());
    assert!(new.dependants.is_some());
    // Removal remaps back to the current tree without resurrecting inserted IDs.
    let removed = MetadataDependencies::capture_rebased(
        &before_tree,
        &before_index,
        Some((&parent, &parent_index)),
    )
    .unwrap();
    for node in &removed.nodes {
        let original = &before.nodes[before.slot(node.key).unwrap()];
        assert_eq!(node.member, original.member);
        assert_eq!(node.dependants, original.dependants);
    }
}

#[test]
fn structural_partial_metadata_resolves_only_current_dirty_cone() {
    use crate::member_binding::{CurrentProjection, MemberWrite};
    let (before_tree, before_index) = captured_inputs(false, false);
    let before = MetadataDependencies::capture(&before_tree, &before_index).unwrap();
    let (after_tree, after_index) = captured_inputs(true, false);
    let projection = CurrentProjection::new(&after_index, after_tree.members.len()).unwrap();
    let order = resolution_order(after_tree.members.len(), |id| {
        after_tree.members[id].previous
    });
    let mut members = after_tree.members.clone();
    for row in after_index.ordered() {
        if let Skeleton::Member { metadata, .. } = &row.skeleton {
            members.set_metadata(projection.ids[&row.key].index(), Arc::clone(metadata));
        }
    }
    let prior = StructuralMetadata {
        tree: &before_tree,
        declarations: &before_index,
        graph: &before,
    };
    let dirty = prior
        .apply(&after_tree, &after_index, &mut members, &projection, &order)
        .unwrap();
    assert_eq!(
        dirty.len(),
        2,
        "new var and proc only; current old rows remain admitted"
    );
    let dirty_ids: Vec<_> = order
        .iter()
        .copied()
        .filter(|id| dirty.contains(&projection.keys[id.index()]))
        .collect();
    resolve_metadata(&after_tree, &mut members, &dirty_ids);
    assert_eq!(members.len(), after_tree.members.len());
    for (actual, fresh) in members.iter().zip(after_tree.members.iter()) {
        assert_eq!(actual, fresh);
    }
    let base = dm_ir::SymbolId::of("/datum/base");
    let old = before
        .nodes
        .iter()
        .find(|node| node.key.owner == base)
        .unwrap();
    assert!(!dirty.contains(&old.key));
    // MemberWrite deliberately keeps an existing exact-equal current Arc;
    // structural admission guarantees skipped resolution and exact metadata,
    // rather than replacement of an already equal current owner.
    assert_eq!(
        members[projection.ids[&old.key].index()].metadata,
        before_tree.members[old.member.index()].metadata
    );
    let (parent_tree, parent_index) = captured_inputs(true, true);
    let parent_projection =
        CurrentProjection::new(&parent_index, parent_tree.members.len()).unwrap();
    let parent_order = resolution_order(parent_tree.members.len(), |id| {
        parent_tree.members[id].previous
    });
    let mut parent_members = parent_tree.members.clone();
    let parent_dirty = prior
        .apply(
            &parent_tree,
            &parent_index,
            &mut parent_members,
            &parent_projection,
            &parent_order,
        )
        .unwrap();
    assert!(parent_dirty
        .iter()
        .any(|key| key.owner == dm_ir::SymbolId::of("/datum/base/child")));
}

#[test]
fn inherited_typed_array_metadata_structural_edit_matches_fresh() {
    use crate::frontend::{
        build_with_executor_and_semantic_state, FrontendConfig, RetainedSemanticTree,
    };
    use std::{collections::BTreeMap, path::Path};
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
        let executor = dm_exec::BuildExecutor::new(1).unwrap();
        build_with_executor_and_semantic_state(
            Path::new("typed-array.dme"),
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
    let before = "/datum/item_a\n/datum/item_b\n/datum/base\n    var/unaffected=11\n    var/datum/item_a/value = null\n    var/list/datum/item_a/values[2]\n/datum/child\n    parent_type=/datum/base\n    value=null\n    values=list(1)\n/datum/grandchild\n    parent_type=/datum/child\n    value=null\n    values=list(2)\n";
    let after = "/datum/item_a\n/datum/item_b\n/datum/base\n    var/unaffected=11\n    var/unrelated=7\n    var/datum/item_b/value = null\n    var/list/datum/item_b/values[4]\n/datum/child\n    parent_type=/datum/base\n    value=null\n    values=list(1)\n/datum/grandchild\n    parent_type=/datum/child\n    value=null\n    values=list(2)\n";
    let mut state = RetainedSemanticTree::new();
    let old = frontend(&mut state, before);
    let old_stats = state.metadata_resolution_stats();
    let actual = frontend(&mut state, after);
    let current_stats = state.metadata_resolution_stats();
    assert_eq!(
        current_stats.structurally_reused_members - old_stats.structurally_reused_members,
        1,
        "unchanged field in changed owner is admitted without inheritance resolution"
    );
    assert_eq!(
        current_stats.structurally_dirty_members - old_stats.structurally_dirty_members,
        7,
        "new field plus both changed ancestor fields and their two override levels"
    );
    assert_eq!(
        current_stats.common_resolved_members - old_stats.common_resolved_members,
        7,
        "every dirty inherited field reaches the common resolver, unchanged field does not"
    );
    let fresh = frontend(&mut RetainedSemanticTree::new(), after);
    assert_eq!(
        state.rebuilds(),
        2,
        "insertion must enter structural constructor"
    );
    assert_eq!(
        actual.snapshot.tree.members().len(),
        fresh.snapshot.tree.members().len()
    );
    for (actual, fresh) in actual
        .snapshot
        .tree
        .members()
        .iter()
        .zip(fresh.snapshot.tree.members().iter())
    {
        assert_eq!(actual, fresh);
    }
    for path in ["/datum/base", "/datum/child", "/datum/grandchild"] {
        let field = |tree: &SemanticTree, name: &str| {
            let owner = tree.lookup_type(dm_ir::SymbolId::of(path)).unwrap();
            let id = tree
                .resolve(owner, dm_ir::SymbolId::of(name), MemberKind::Var)
                .unwrap();
            Arc::clone(&tree.member(id).unwrap().metadata)
        };
        let value = field(&actual.snapshot.tree, "value");
        assert_eq!(
            value.declared_type,
            Some(dm_ir::SymbolId::of("/datum/item_b"))
        );
        assert_eq!(value, field(&fresh.snapshot.tree, "value"));
        assert_ne!(
            value.declared_type,
            field(&old.snapshot.tree, "value").declared_type
        );
        let values = field(&actual.snapshot.tree, "values");
        assert_eq!(values.declared_type, Some(dm_ir::SymbolId::of("/list")));
        assert_eq!(
            values.list_element_type,
            Some(dm_ir::SymbolId::of("/datum/item_b"))
        );
        assert_eq!(values, field(&fresh.snapshot.tree, "values"));
        assert_ne!(values.array, field(&old.snapshot.tree, "values").array);
        assert_eq!(values.array.as_ref().unwrap().dimensions.len(), 1);
        if path != "/datum/base" {
            let owner = actual
                .snapshot
                .tree
                .lookup_type(dm_ir::SymbolId::of(path))
                .unwrap();
            for name in ["value", "values"] {
                let id = actual
                    .snapshot
                    .tree
                    .resolve(owner, dm_ir::SymbolId::of(name), MemberKind::Var)
                    .unwrap();
                assert!(actual.snapshot.tree.member(id).unwrap().previous.is_some());
            }
        }
    }
}

#[test]
fn reopened_typed_array_formal_reorder_and_override_removal_match_fresh() {
    use crate::frontend::{
        build_with_executor_and_semantic_state, FrontendConfig, RetainedSemanticTree,
    };
    use std::{collections::BTreeMap, path::Path};
    struct Source(&'static str);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok(self.0.into())
        }
    }
    fn frontend(
        state: &mut RetainedSemanticTree,
        text: &'static str,
    ) -> crate::frontend::ColdFrontend {
        let executor = dm_exec::BuildExecutor::new(1).unwrap();
        build_with_executor_and_semantic_state(
            Path::new("reopened-array.dme"),
            &Source(text),
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
    let sources = [
        "/datum/item\n/datum/base\n    values=list(1)\n/datum/base\n    var/tmp/list/datum/item/values[2]\n/datum/base\n    values=list(2)\n/datum/child\n    parent_type=/datum/base\n    values=list(3)\n",
        "/datum/item\n/datum/base\n    var/tmp/list/datum/item/values[4]\n/datum/base\n    values=list(1)\n/datum/base\n    values=list(2)\n/datum/child\n    parent_type=/datum/base\n    values=list(3)\n",
        "/datum/item\n/datum/base\n    var/tmp/list/datum/item/values[4]\n/datum/base\n    values=list(2)\n/datum/child\n    parent_type=/datum/base\n    values=list(3)\n",
    ];
    let mut state = RetainedSemanticTree::new();
    for source in sources {
        let actual = frontend(&mut state, source);
        let fresh = frontend(&mut RetainedSemanticTree::new(), source);
        assert_eq!(
            actual.snapshot.tree.members().len(),
            fresh.snapshot.tree.members().len()
        );
        for (actual, fresh) in actual
            .snapshot
            .tree
            .members()
            .iter()
            .zip(fresh.snapshot.tree.members().iter())
        {
            assert_eq!(
                actual, fresh,
                "formal/override ordering must rebind the entire current chain"
            );
        }
        let tree = &actual.snapshot.tree;
        let owner = tree
            .lookup_type(dm_ir::SymbolId::of("/datum/child"))
            .unwrap();
        let mut id = tree
            .resolve(owner, dm_ir::SymbolId::of("values"), MemberKind::Var)
            .unwrap();
        let mut depth = 0;
        loop {
            let member = tree.member(id).unwrap();
            assert_eq!(
                member.metadata.declared_type,
                Some(dm_ir::SymbolId::of("/list"))
            );
            assert_eq!(
                member.metadata.list_element_type,
                Some(dm_ir::SymbolId::of("/datum/item"))
            );
            assert_eq!(member.metadata.flags & 4, 4);
            assert!(member.metadata.array.is_some());
            depth += 1;
            let Some(previous) = member.previous else {
                break;
            };
            id = previous;
        }
        assert_eq!(
            depth,
            tree.members().len(),
            "one formal plus every current reopened/inherited override"
        );
    }
}

#[test]
fn symbol_only_update_replaces_lexical_authority_and_shares_semantic_owners() {
    let (tree, declarations) = captured_inputs(false, false);
    let graph = MetadataDependencies::capture(&tree, &declarations).unwrap();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let mut symbols = tree.symbols().clone();
    let added = symbols.intern("new_body_spelling").unwrap();
    let updated = graph
        .update(
            &tree,
            declarations.skeletons(),
            declarations.skeletons(),
            symbols,
            &executor,
        )
        .unwrap();
    assert!(updated.symbols().text(added).is_some());
    assert!(tree.symbols().text(added).is_none());
    assert!(Arc::ptr_eq(&tree.types, &updated.types));
    assert!(Arc::ptr_eq(&tree.inventory, &updated.inventory));
    assert!(Arc::ptr_eq(
        &tree.owner_callable_demands,
        &updated.owner_callable_demands
    ));
    for (a, b) in tree.members.iter().zip(updated.members.iter()) {
        assert_eq!(a, b);
        assert!(Arc::ptr_eq(&a.metadata, &b.metadata));
    }
    let removed = graph
        .update(
            &updated,
            declarations.skeletons(),
            declarations.skeletons(),
            tree.symbols().clone(),
            &executor,
        )
        .unwrap();
    assert!(removed.symbols().text(added).is_none());
    assert!(
        updated.symbols().text(added).is_some(),
        "old snapshot stays immutable"
    );
    let fresh = build(
        tree.symbols().clone(),
        &declarations.skeletons().cloned().collect::<Vec<_>>(),
    )
    .unwrap();
    assert_eq!(removed.members.len(), fresh.members.len());
    for (a, b) in removed.members.iter().zip(fresh.members.iter()) {
        assert_eq!(a, b);
    }
}

#[test]
fn structural_adjacency_binds_current_order_before_allocating_changed_edges() {
    fn input(siblings: &[&str]) -> (SemanticTree, KeyedDeclarations) {
        let (base, index) = captured_inputs(false, false);
        let mut symbols = base.symbols().clone();
        let mut rows: Vec<_> = index.skeletons().cloned().collect();
        let parent = dm_ir::SymbolId::of("/datum/base");
        let name = dm_ir::SymbolId::of("value");
        for spelling in siblings {
            let path = symbols.intern(spelling).unwrap();
            rows.push(Skeleton::Type {
                path,
                explicit_parent: Some(parent),
            });
            rows.push(Skeleton::Member {
                owner: path,
                name,
                kind: MemberKind::Var,
                mode: DefinitionMode::Override,
                metadata: Arc::new(MemberMetadata::default()),
                content: 0,
            });
        }
        let tree = build(symbols, &rows).unwrap();
        let (index, _) = KeyedDeclarations::capture(None, &rows).unwrap();
        (tree, index)
    }
    let (old_tree, old_index) = input(&["/datum/sibling_a", "/datum/sibling_b"]);
    let old = MetadataDependencies::capture(&old_tree, &old_index).unwrap();
    let parent = old
        .nodes
        .iter()
        .find(|node| node.key.owner == dm_ir::SymbolId::of("/datum/base"))
        .unwrap();
    let old_edges = parent.dependants.as_ref().unwrap();
    assert_eq!(old_edges.len(), 3);
    for siblings in [
        vec!["/datum/sibling_a", "/datum/sibling_b"],
        vec!["/datum/sibling_a", "/datum/sibling_c", "/datum/sibling_b"],
        vec!["/datum/sibling_b", "/datum/sibling_a"],
        vec!["/datum/sibling_b"],
    ] {
        let (tree, index) = input(&siblings);
        let actual =
            MetadataDependencies::capture_rebased(&tree, &index, Some((&old, &old_index))).unwrap();
        let fresh = MetadataDependencies::capture(&tree, &index).unwrap();
        assert!(actual.roster == fresh.roster);
        assert_eq!(actual.members_at_declaration, fresh.members_at_declaration);
        assert_eq!(actual.projection, fresh.projection);
        assert_eq!(actual.order, fresh.order);
        for node in &actual.nodes {
            let expected = &fresh.nodes[fresh.slot(node.key).unwrap()];
            assert_eq!(node.member, expected.member);
            assert_eq!(node.dependants, expected.dependants);
        }
        let edges = actual.nodes[actual.slot(parent.key).unwrap()]
            .dependants
            .as_ref()
            .unwrap();
        assert_eq!(
            Arc::ptr_eq(edges, old_edges),
            siblings == ["/datum/sibling_a", "/datum/sibling_b"]
        );
    }
}
