use super::*;
use crate::{build, MemberMetadata};
use std::sync::Arc;
fn captured(extra: bool) -> (SemanticTree, MetadataDependencies) {
    let mut symbols = dm_ir::SymbolTable::default();
    let root = symbols.intern("/").unwrap();
    let base = symbols.intern("/datum/base").unwrap();
    let child = symbols.intern("/datum/base/child").unwrap();
    let name = symbols.intern("value").unwrap();
    let other = symbols.intern("other").unwrap();
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
            explicit_parent: None,
        },
    ];
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
    let graph = MetadataDependencies::capture(&tree, &index).unwrap();
    (tree, graph)
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
    let new = after
        .nodes
        .iter()
        .find(|node| node.key.owner == base)
        .unwrap();
    assert_ne!(old.member, new.member);
    assert_eq!(old.key, new.key);
    assert_eq!(old.dependants, new.dependants);
    assert_eq!(old.dependants.len(), 1);
    let child = old.dependants[0];
    assert_eq!(before.nodes[before.slot(child).unwrap()].key, child);
    assert_eq!(after.nodes[after.slot(child).unwrap()].key, child);
    assert_ne!(
        before.nodes[before.slot(child).unwrap()].member,
        after.nodes[after.slot(child).unwrap()].member
    );
}
