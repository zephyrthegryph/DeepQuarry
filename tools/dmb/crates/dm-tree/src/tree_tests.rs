use super::*;
fn symbols() -> SymbolTable {
    let mut symbols = SymbolTable::default();
    for text in ["/", "/obj", "/obj/base", "/obj/child", "value", "chain"] {
        symbols.intern(text).unwrap();
    }
    symbols
}
fn member(owner: &str, name: &str, mode: DefinitionMode, content: u128) -> Skeleton {
    Skeleton::Member {
        owner: SymbolId::of(owner),
        name: SymbolId::of(name),
        kind: MemberKind::Proc,
        mode,
        metadata: MemberMetadata::default(),
        content,
    }
}
#[test]
fn source_relocation_does_not_change_semantic_identity() {
    let tree = build(
        symbols(),
        &[member("/obj/base", "chain", DefinitionMode::Declare, 1)],
    )
    .unwrap();
    let origin = |start| Provenance {
        span: Span {
            file: dm_ir::FileId(0),
            start,
            end: start + 1,
        },
        include_occurrence: 0,
        region: 4,
        expansion_stack: Arc::from([]),
    };
    let a = OccurrenceTable::build(&tree, vec![origin(1)]).unwrap();
    let b = OccurrenceTable::build(&tree, vec![origin(99)]).unwrap();
    assert_eq!(a.tree_identity(), b.tree_identity());
    assert_ne!(
        a.source_order()[0].provenance,
        b.source_order()[0].provenance
    );
}
#[test]
fn cycles_and_duplicate_declarations_are_errors() {
    assert!(matches!(
        build(
            symbols(),
            &[
                Skeleton::Type {
                    path: SymbolId::of("/obj/base"),
                    explicit_parent: Some(SymbolId::of("/obj/child"))
                },
                Skeleton::Type {
                    path: SymbolId::of("/obj/child"),
                    explicit_parent: Some(SymbolId::of("/obj/base"))
                },
            ]
        ),
        Err(TreeError::InheritanceCycle(_))
    ));
    assert!(matches!(
        build(
            symbols(),
            &[
                member("/obj/base", "chain", DefinitionMode::Declare, 1),
                member("/obj/base", "chain", DefinitionMode::Declare, 2)
            ]
        ),
        Err(TreeError::Duplicate { .. })
    ));
}
