use super::*;
fn member(owner: SymbolId, name: SymbolId) -> Skeleton {
    Skeleton::Member {
        owner,
        name,
        kind: MemberKind::Var,
        mode: DefinitionMode::Declare,
        metadata: Arc::new(MemberMetadata::default()),
        content: 0,
    }
}
#[test]
fn negative_name_receipt_replays_and_rejects_changed_catalog() {
    let mut symbols = SymbolTable::default();
    let owner = symbols.intern("/obj").unwrap();
    let name = SymbolId::of("missing");
    let skeletons = vec![member(owner, name)];
    let (declarations, _) = KeyedDeclarations::capture(None, &skeletons).unwrap();
    let tree = crate::build(symbols.clone(), &[]).unwrap();
    let store = RetainedOwnerShapes::default();
    let kinds = callable_namespace::CallableKinds::default();
    let first = store.prepare(&tree, &declarations, &kinds);
    assert!(matches!(first[&owner].first_failure,
        Some((_, LocalValidationFailure::UnknownSymbol(actual))) if actual == name));
    let repeated = store.prepare(&tree, &declarations, &kinds);
    assert!(Arc::ptr_eq(&first[&owner], &repeated[&owner]));
    symbols.intern("missing").unwrap();
    let changed = crate::build(symbols, &[]).unwrap();
    let repaired = store.prepare(&changed, &declarations, &kinds);
    assert!(repaired[&owner].first_failure.is_none());
    assert!(!Arc::ptr_eq(&repeated[&owner], &repaired[&owner]));
}
