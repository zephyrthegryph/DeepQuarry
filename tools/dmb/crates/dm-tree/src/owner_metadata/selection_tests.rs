use super::*;
use dm_ir::{ResolveQuery, Resolver};

#[test]
fn root_selection_demands_preserve_issued_tokens_and_decline_unqueried_old_snapshots() {
    let mut symbols = SymbolTable::default();
    let root = symbols.intern("/").unwrap();
    let name = symbols.intern("callback").unwrap();
    let unused = symbols.intern("unused").unwrap();
    let retained = crate::owner_normalization::RetainedNormalization::default();
    let build = |content| {
        let rows = vec![Skeleton::Member {
            owner: root,
            name,
            kind: MemberKind::Proc,
            mode: DefinitionMode::Declare,
            metadata: Arc::new(MemberMetadata::default()),
            content,
        }];
        let (index, _) =
            crate::declaration_contributions::KeyedDeclarations::capture(None, &rows).unwrap();
        let tree = crate::build_with_intrinsic_members_indexed(
            symbols.clone(),
            rows.as_slice().into(),
            &[],
            &[],
            false,
            Some((&index, &retained)),
        )
        .unwrap();
        let absent = ResolveQuery::GlobalProc(unused);
        assert_eq!(
            Resolver::resolve(&tree, absent),
            dm_ir::ResolvedMeaning::Unsupported(absent),
            "incomplete intrinsic coverage cannot certify absence"
        );
        tree
    };
    let first = build(1);
    assert!(first.owner_callable_selections.is_empty());
    let mut eager = 0;
    retained.metadata.store.visit_storage(|view| {
        if let dm_session::ObservedArtifactStorageView::Entry { key, .. } = view {
            eager += usize::from(key.starts_with(b"callable-selection-v1"));
        }
    });
    assert_eq!(eager, 0);
    let query = ResolveQuery::GlobalProc(name);
    let token = first.domain_version(query.domain()).unwrap();
    assert!(matches!(
        Resolver::resolve(&first, query),
        dm_ir::ResolvedMeaning::Member { .. }
    ));
    let second = build(2);
    assert_eq!(second.domain_version(query.domain()), Some(token));
    assert_eq!(first.domain_version(query.domain()), Some(token));
    assert_eq!(
        Resolver::resolve(&first, query),
        Resolver::resolve(&second, query)
    );
    let unqueried = ResolveQuery::GlobalProc(unused);
    assert_eq!(
        first.domain_version(unqueried.domain()),
        None,
        "an old snapshot with no name receipt must fail closed"
    );
    assert!(second.domain_version(unqueried.domain()).is_some());
    assert_eq!(first.domain_version(unqueried.domain()), None);
    assert_eq!(
        Resolver::resolve(&second, unqueried),
        dm_ir::ResolvedMeaning::Unsupported(unqueried)
    );
    let hierarchy = crate::EngineHierarchy {
        schema: 19,
        parents: second
            .types()
            .iter()
            .map(|node| {
                (
                    node.path,
                    node.parent.map(|id| second.types()[id.index()].path),
                )
            })
            .collect(),
    };
    let complete = second
        .clone()
        .with_complete_intrinsics(hierarchy, Vec::new())
        .unwrap();
    assert_eq!(
        Resolver::resolve(&complete, unqueried),
        dm_ir::ResolvedMeaning::Missing
    );
}
