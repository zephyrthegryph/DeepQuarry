//! Immutable semantic index ownership across retained tree consumers.
use super::*;
use dm_ir::{ResolveQuery, Resolver};
fn tree() -> SemanticTree {
    let ast = dm_syntax::parse("/datum/base\n    var/value = 1\n    proc/read()\n        return value\n/datum/base/child\n");
    let adapted = adapter::from_ast(&ast, SymbolTable::default(), dm_ir::FileId(0), 0, 0).unwrap();
    build(adapted.symbols, &adapted.skeletons).unwrap()
}
#[test]
fn cloned_semantic_consumers_share_indexes_then_release_final_owner() {
    let original = tree();
    let paths = Arc::downgrade(&original.by_path);
    let direct = Arc::downgrade(&original.direct);
    let inventory = Arc::downgrade(&original.inventory);
    let retained = original.clone();
    assert!(Arc::ptr_eq(&original.by_path, &retained.by_path));
    assert!(Arc::ptr_eq(&original.direct, &retained.direct));
    assert!(Arc::ptr_eq(&original.inventory, &retained.inventory));
    let query = ResolveQuery::Ancestry(SymbolId::of("/datum/base/child"));
    let expected = Resolver::resolve(&original, query);
    drop(original);
    assert_eq!(Resolver::resolve(&retained, query), expected);
    assert!(paths.upgrade().is_some());
    assert!(direct.upgrade().is_some());
    assert!(inventory.upgrade().is_some());
    drop(retained);
    assert!(paths.upgrade().is_none());
    assert!(direct.upgrade().is_none());
    assert!(inventory.upgrade().is_none());
}
#[test]
fn attaching_inventory_detaches_only_changed_owner_and_preserves_previous_snapshot() {
    let original = tree();
    let hierarchy = resolver::EngineHierarchy {
        schema: 1,
        parents: original
            .types
            .iter()
            .map(|node| {
                (
                    node.path,
                    node.parent.map(|id| original.types[id.index()].path),
                )
            })
            .collect(),
    };
    let before = original.identity();
    let changed = original
        .clone()
        .with_complete_intrinsics(
            hierarchy,
            vec![resolver::IntrinsicMember {
                owner: SymbolId::of("/datum/base"),
                name: SymbolId::of("native"),
                kind: MemberKind::Var,
                shared_owner: None,
                instance_storage_proven: true,
            }],
        )
        .unwrap();
    assert!(Arc::ptr_eq(&original.by_path, &changed.by_path));
    assert!(Arc::ptr_eq(&original.direct, &changed.direct));
    assert!(!Arc::ptr_eq(&original.inventory, &changed.inventory));
    assert!(!original.inventory.complete);
    assert!(changed.inventory.complete);
    assert_eq!(original.identity(), before);
    assert_ne!(changed.identity(), before);
    let query = ResolveQuery::Var {
        owner: SymbolId::of("/datum/base/child"),
        name: SymbolId::of("value"),
    };
    assert_eq!(Resolver::resolve(&original, query), Resolver::resolve(&changed, query));
}
