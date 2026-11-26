use super::*;
fn skeleton(owner: &str, name: &str) -> Skeleton {
    Skeleton::Member {
        owner: SymbolId::of(owner),
        name: SymbolId::of(name),
        kind: MemberKind::Var,
        mode: DefinitionMode::Declare,
        metadata: Arc::new(MemberMetadata::default()),
        content: 1,
    }
}
fn inputs<'a>(source: &'a [Skeleton], projection: &'a CurrentProjection) -> MemberBindings<'a> {
    let mut rows = MemberBindings::new(Some(projection));
    for row in source {
        let Skeleton::Member {
            owner,
            name,
            kind,
            mode,
            metadata,
            content,
        } = row
        else {
            unreachable!()
        };
        rows.push(MemberView {
            definition: *mode,
            owner: TypeId(if *owner == SymbolId::of("/obj/a") {
                0
            } else {
                1
            }),
            name: *name,
            kind: *kind,
            metadata,
            content: *content,
            previous: None,
        });
    }
    rows
}
#[test]
fn exact_borrowed_recipes_construct_only_changed_final_chunks() {
    let original = vec![skeleton("/obj/a", "first"), skeleton("/obj/b", "second")];
    let (declarations, _) = KeyedDeclarations::capture(None, &original).unwrap();
    let projection = CurrentProjection::new(&declarations, original.len()).unwrap();
    let rows = inputs(&original, &projection);
    let first = crate::member_arena::MemberPublication::publish(&rows, &projection, None);
    assert_eq!(rows.constructed_nodes(), 2);
    let unchanged = inputs(&original, &projection);
    let repeated =
        crate::member_arena::MemberPublication::publish(&unchanged, &projection, Some(&first));
    assert_eq!(unchanged.constructed_nodes(), 0);
    for (a, b) in first.arena().chunks().iter().zip(repeated.arena().chunks()) {
        assert!(Arc::ptr_eq(a, b));
    }
    let mut appended = original.clone();
    appended.push(skeleton("/obj/a", "added"));
    let (next, _) = KeyedDeclarations::capture(Some(&declarations), &appended).unwrap();
    let current = CurrentProjection::new(&next, appended.len()).unwrap();
    let changed = inputs(&appended, &current);
    let published =
        crate::member_arena::MemberPublication::publish(&changed, &current, Some(&repeated));
    assert_eq!(changed.constructed_nodes(), 1);
    assert_eq!(published.arena().len(), 3);
    assert!(Arc::ptr_eq(
        &published.arena().chunks()[0],
        &repeated.arena().chunks()[0]
    ));
    // Current dense previous bindings are exact recipe inputs, not reusable IDs.
    let mut altered = inputs(&appended, &current);
    altered.set_previous(1, Some(MemberId(0)));
    let rebound =
        crate::member_arena::MemberPublication::publish(&altered, &current, Some(&published));
    assert_eq!(altered.constructed_nodes(), 1);
    assert_eq!(rebound.arena()[1].previous, Some(MemberId(0)));
}
#[test]
fn admitted_namespace_is_one_shared_owner_and_sparse_metadata_is_exact() {
    let original = vec![skeleton("/obj/a", "first"), skeleton("/obj/a", "second")];
    let (declarations, _) = KeyedDeclarations::capture(None, &original).unwrap();
    let projection = CurrentProjection::new(&declarations, original.len()).unwrap();
    let mut rows = inputs(&original, &projection);
    let metadata = Arc::new(MemberMetadata {
        flags: 2,
        ..MemberMetadata::default()
    });
    let normal: Arc<[_]> = projection
        .keys
        .iter()
        .map(|&key| owner_normalization::ResolvedMember {
            key,
            definition: DefinitionMode::Declare,
            kind: MemberKind::Var,
            metadata: Arc::clone(&metadata),
            previous: None,
        })
        .collect::<Vec<_>>()
        .into();
    let before = Arc::strong_count(&metadata);
    rows.install_namespace(SymbolId::of("/obj/a"), &normal, &projection);
    assert!(Arc::ptr_eq(
        &rows.normalized[&SymbolId::of("/obj/a")],
        &normal
    ));
    assert_eq!(Arc::strong_count(&metadata), before);
    assert!(rows.deltas.is_empty());
    assert!(Arc::ptr_eq(rows.member(0).metadata, &metadata));
    let changed = Arc::new(MemberMetadata {
        flags: 6,
        ..metadata.as_ref().clone()
    });
    rows.set_metadata(1, Arc::clone(&changed));
    assert_eq!(rows.deltas.len(), 1);
    assert!(Arc::ptr_eq(rows.member(0).metadata, &metadata));
    assert!(Arc::ptr_eq(rows.member(1).metadata, &changed));
    rows.set_previous(1, Some(MemberId(0)));
    assert_eq!(rows.member(1).previous, Some(MemberId(0)));
    assert_eq!(normal[1].previous, None);
    rows.set_previous(1, None);
    assert_eq!(rows.member(1).previous, None);
    assert_eq!(rows.constructed_nodes(), 0);
}
