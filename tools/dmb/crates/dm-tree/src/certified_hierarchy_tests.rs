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

fn assert_stream_matches_original(tree: &SemanticTree, path: SymbolId, kind: HierarchyQuestion) {
    let view = tree.certified_hierarchy().unwrap();
    let question = Q::CertifiedHierarchy { kind, path };
    let original = Resolver::resolve(tree, question);
    let borrowed = view.borrowed_answer(kind, path);
    assert_eq!(
        borrowed.positive(),
        !matches!(
            original,
            M::Missing | M::Unsupported(_) | M::Presence(false)
        )
    );
    let mut hash = xxhash_rust::xxh3::Xxh3::new();
    let mut bytes = Vec::new();
    let mut work = view.node_bound().checked_mul(2).unwrap() + 2;
    borrowed
        .write_canonical(
            &mut work,
            || Ok(()),
            |part| {
                hash.update(part);
                bytes.extend_from_slice(part);
                Ok(())
            },
        )
        .unwrap();
    assert_eq!(bytes, original.canonical_bytes(), "{question:?}");
    assert_eq!(
        hash.digest128(),
        xxhash_rust::xxh3::xxh3_128(&original.canonical_bytes()),
        "same original answer_hash algorithm"
    );
}
#[test]
fn borrowed_original_hierarchy_stream_matches_owned_hash_and_positive_all_families() {
    let original = tree();
    let proof = hierarchy(&original);
    let certified = original.with_engine_intrinsics(proof, Vec::new()).unwrap();
    for path in ["/datum/item/child", "/datum/item", "/datum", "/", "/absent"] {
        for kind in [
            HierarchyQuestion::Type,
            HierarchyQuestion::Parent,
            HierarchyQuestion::Ancestry,
        ] {
            assert_stream_matches_original(&certified, SymbolId::of(path), kind);
        }
    }
}
#[test]
fn borrowed_deep_original_parent_fallback_streams_without_rebuilding_owner_cache() {
    let mut path = String::from("/datum");
    for n in 0..128 {
        path.push_str(&format!("/step{n}"));
    }
    let source = format!("{path}\n");
    let adapted = from_ast(
        &dm_syntax::parse(&source),
        SymbolTable::default(),
        FileId(0),
        0,
        0,
    )
    .unwrap();
    let original = build(adapted.symbols, &adapted.skeletons).unwrap();
    let proof = hierarchy(&original);
    let mut certified = original.with_engine_intrinsics(proof, Vec::new()).unwrap();
    // Exercise the actual original fallback, not a second source tree/parser.
    certified.owner_ancestry = Arc::new(std::collections::BTreeMap::new());
    let cache = Arc::clone(&certified.owner_ancestry);
    assert_stream_matches_original(&certified, SymbolId::of(&path), HierarchyQuestion::Ancestry);
    assert!(Arc::ptr_eq(&cache, &certified.owner_ancestry));
    assert!(cache.is_empty());
}
#[test]
fn original_hierarchy_visit_cancellation_budget_and_foreign_tree_remain_explicit() {
    let original = tree();
    let proof = hierarchy(&original);
    let certified = original.with_engine_intrinsics(proof, Vec::new()).unwrap();
    let view = certified.certified_hierarchy().unwrap();
    assert!(!view.require_tree(&certified.clone()));
    let answer = view.borrowed_answer(
        HierarchyQuestion::Ancestry,
        SymbolId::of("/datum/item/child"),
    );
    let mut work = 0;
    let mut emits = 0;
    assert!(answer
        .write_canonical(
            &mut work,
            || Ok(()),
            |_| {
                emits += 1;
                Ok(())
            }
        )
        .is_err());
    assert_eq!(emits, 0);
    let mut work = 1000;
    let error = answer
        .write_canonical(
            &mut work,
            || {
                Err(std::io::Error::new(
                    std::io::ErrorKind::Interrupted,
                    "actual checkpoint",
                ))
            },
            |_| {
                emits += 1;
                Ok(())
            },
        )
        .unwrap_err();
    assert_eq!(error.kind(), std::io::ErrorKind::Interrupted);
    assert_eq!(emits, 0);
}
