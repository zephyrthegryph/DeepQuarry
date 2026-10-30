use super::*;
use dm_ir::{FileId, ResolveQuery as Q, Resolver};
fn tree() -> SemanticTree {
    let source = "/datum/item\n/datum/item/child\n";
    let adapted = from_ast(
        &dm_syntax::parse(source),
        SymbolTable::default(),
        FileId(0),
        0,
        0,
    )
    .unwrap();
    build(adapted.symbols, &adapted.skeletons).unwrap()
}
fn hierarchy(tree: &SemanticTree) -> crate::EngineHierarchy {
    crate::EngineHierarchy {
        schema: 1,
        parents: tree
            .types
            .iter()
            .map(|n| (n.path, n.parent.map(|p| tree.types[p.index()].path)))
            .collect(),
    }
}
#[test]
fn uncertified_tree_cannot_issue_hierarchy_view_or_qualified_absence() {
    let original = tree();
    assert!(original.certified_hierarchy().is_none());
    for kind in [
        HierarchyQuestion::Type,
        HierarchyQuestion::Parent,
        HierarchyQuestion::Ancestry,
    ] {
        let q = Q::CertifiedHierarchy {
            kind,
            path: SymbolId::of("/absent"),
        };
        assert_eq!(Resolver::resolve(&original, q), M::Unsupported(q));
    }
}
#[test]
fn sealed_original_hierarchy_proves_own_roots_and_absence_without_member_completeness() {
    let original = tree();
    let proof = hierarchy(&original);
    let certified = original.with_engine_intrinsics(proof, Vec::new()).unwrap();
    assert!(!certified.intrinsic_inventory_complete());
    let view = certified.certified_hierarchy().unwrap();
    let child = SymbolId::of("/datum/item/child");
    let parent = SymbolId::of("/datum/item");
    let absent = SymbolId::of("/absent");
    assert!(view.require_tree(&certified));
    assert!(!view.require_tree(&certified.clone()));
    assert_eq!(
        view.answer(HierarchyQuestion::Type, child),
        M::Symbol(child)
    );
    assert_eq!(
        view.answer(HierarchyQuestion::Parent, child),
        M::Symbol(parent)
    );
    assert_eq!(
        view.answer(HierarchyQuestion::Parent, SymbolId::of("/")),
        M::Missing
    );
    let M::Symbols(owners) = view.answer(HierarchyQuestion::Ancestry, child) else {
        panic!()
    };
    assert_eq!(owners[0], child);
    assert!(owners.contains(&parent));
    // Generic partial member/inventory contract stays unchanged.
    assert_eq!(
        Resolver::resolve(&certified, Q::Type(absent)),
        M::Unsupported(Q::Type(absent))
    );
    for kind in [
        HierarchyQuestion::Type,
        HierarchyQuestion::Parent,
        HierarchyQuestion::Ancestry,
    ] {
        let q = Q::CertifiedHierarchy { kind, path: absent };
        assert_eq!(view.answer(kind, absent), M::Missing);
        assert_eq!(Resolver::resolve(&certified, q), M::Missing);
    }
    let member = Q::Proc {
        owner: child,
        name: SymbolId::of("not_captured"),
        verb: false,
    };
    // This view does not manufacture any typed member or runtime field proof.
    assert_eq!(
        view.answer(HierarchyQuestion::Type, parent),
        M::Symbol(parent)
    );
    assert_eq!(
        Resolver::resolve(&certified, member),
        M::Unsupported(member)
    );
}
