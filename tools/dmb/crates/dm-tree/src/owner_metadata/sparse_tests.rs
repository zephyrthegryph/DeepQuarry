use super::*;

#[test]
fn sparse_metadata_replays_locals_and_invalidates_changed_inherited_base() {
    let mut symbols = SymbolTable::default();
    let base = symbols.intern("/datum/base").unwrap();
    let child = symbols.intern("/datum/base/child").unwrap();
    let name = symbols.intern("value").unwrap();
    let retained = crate::owner_normalization::RetainedNormalization::default();
    let rows = |flags| {
        let mut base_metadata = MemberMetadata::default();
        base_metadata.flags = flags;
        vec![
            Skeleton::Type {
                path: base,
                explicit_parent: None,
            },
            Skeleton::Type {
                path: child,
                explicit_parent: None,
            },
            Skeleton::Member {
                owner: base,
                name,
                kind: MemberKind::Var,
                mode: DefinitionMode::Declare,
                metadata: Arc::new(base_metadata),
                content: 0,
            },
            Skeleton::Member {
                owner: child,
                name,
                kind: MemberKind::Var,
                mode: DefinitionMode::Override,
                metadata: Arc::new(MemberMetadata::default()),
                content: 0,
            },
        ]
    };
    let build = |rows: &[Skeleton]| {
        let (index, _) =
            crate::declaration_contributions::KeyedDeclarations::capture(None, rows).unwrap();
        crate::build_with_intrinsic_members_indexed(
            symbols.clone(),
            rows.into(),
            &[],
            &[],
            false,
            Some((&index, &retained)),
        )
        .unwrap()
    };
    let original = rows(8);
    let first = build(&original);
    let second = build(&original);
    let field = |tree: &SemanticTree| {
        tree.members
            .iter()
            .find(|member| tree.types[member.owner.index()].path == child && member.name == name)
            .unwrap()
            .metadata
            .flags
    };
    assert_eq!(field(&first), 8);
    assert_eq!(field(&second), 8);
    let mut delta_rows = 0;
    retained.metadata.visit_storage(|view| {
        if let MetadataStorageView::Values(values) = view {
            delta_rows += values.len();
        }
    });
    assert_eq!(delta_rows, 1, "only the inherited override needs a delta");
    let third = build(&rows(16));
    assert_eq!(field(&third), 16);
    let ordinary = crate::build(symbols.clone(), &rows(16)).unwrap();
    assert_eq!(field(&third), field(&ordinary));
    assert!(retained.metadata.hits() > 0);
}
