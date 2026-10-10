use super::*;
use dm_ir::{ReadDomain, ResolveQuery, Resolver};

#[test]
fn hierarchy_payload_storage_has_no_dummy_member_or_selection_owners() {
    let retained = RetainedMetadata::default();
    retained.store.insert_with(
        Arc::from(b"test".as_slice()),
        Vec::new(),
        Vec::new(),
        0,
        || EffectiveOwner::Hierarchy {
            paths: Arc::from([SymbolId::of("/")]),
            version: 17,
        },
    );
    let mut hierarchy = 0;
    retained.visit_storage(|view| match view {
        MetadataStorageView::Hierarchy(_) => hierarchy += 1,
        MetadataStorageView::Values(_)
        | MetadataStorageView::Selection(_)
        | MetadataStorageView::CallableLocal(_)
        | MetadataStorageView::VariableLocal(_) => panic!("certificate retained unrelated payload"),
        _ => (),
    });
    assert_eq!(hierarchy, 1);
    let value = EffectiveOwner::Hierarchy {
        paths: Arc::from([]),
        version: 17,
    };
    assert_eq!(value.callable_token(), None);
    assert_eq!(value.variable_token(), None);
}

#[test]
fn hierarchy_receipts_reuse_only_exact_current_ancestry_and_qualify_completeness() {
    let mut symbols = SymbolTable::default();
    let root = symbols.intern("/").unwrap();
    let datum = symbols.intern("/datum").unwrap();
    let base = symbols.intern("/datum/base").unwrap();
    let child = symbols.intern("/datum/child").unwrap();
    let unrelated = symbols.intern("/datum/unrelated").unwrap();
    let missing = symbols.intern("/datum/future").unwrap();
    let retained = crate::owner_normalization::RetainedNormalization::default();
    let initial = vec![
        Skeleton::Type {
            path: datum,
            explicit_parent: None,
        },
        Skeleton::Type {
            path: base,
            explicit_parent: None,
        },
        Skeleton::Type {
            path: child,
            explicit_parent: Some(base),
        },
    ];
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
    let first = build(&initial);
    let domain = ReadDomain::OwnerHierarchy(child);
    let first_version = first.domain_version(domain).unwrap();
    assert_eq!(
        first.domain_version(ReadDomain::OwnerHierarchy(missing)),
        None
    );
    let mut unrelated_edit = initial.clone();
    unrelated_edit.push(Skeleton::Type {
        path: unrelated,
        explicit_parent: None,
    });
    let second = build(&unrelated_edit);
    assert_ne!(first.identity(), second.identity());
    assert_eq!(second.domain_version(domain), Some(first_version));
    let query = ResolveQuery::Ancestry(child);
    assert_eq!(
        Resolver::resolve(&first, query),
        dm_ir::ResolvedMeaning::Unsupported(query)
    );
    let admit = |tree: &SemanticTree| {
        let hierarchy = crate::EngineHierarchy {
            schema: 19,
            parents: tree
                .types()
                .iter()
                .map(|node| {
                    (
                        node.path,
                        node.parent.map(|id| tree.types()[id.index()].path),
                    )
                })
                .collect(),
        };
        tree.clone()
            .with_complete_intrinsics(hierarchy, Vec::new())
            .unwrap()
    };
    let first_admitted = admit(&first);
    let second_admitted = admit(&second);
    let dm_ir::ResolvedMeaning::Symbols(first_paths) = Resolver::resolve(&first_admitted, query)
    else {
        panic!()
    };
    let dm_ir::ResolvedMeaning::Symbols(second_paths) = Resolver::resolve(&second_admitted, query)
    else {
        panic!()
    };
    assert!(Arc::ptr_eq(&first_paths, &second_paths));
    assert!(Arc::ptr_eq(
        &first_paths,
        first.owner_ancestry.get(&child).unwrap()
    ));
    let mut reparented = unrelated_edit.clone();
    reparented[2] = Skeleton::Type {
        path: child,
        explicit_parent: Some(datum),
    };
    let third = build(&reparented);
    assert_ne!(third.domain_version(domain), Some(first_version));
    let dm_ir::ResolvedMeaning::Symbols(third_paths) = Resolver::resolve(&admit(&third), query)
    else {
        panic!()
    };
    assert!(!Arc::ptr_eq(&first_paths, &third_paths));
    assert_eq!(third_paths.as_ref(), &[child, datum, root]);
    assert_eq!(first_paths.as_ref(), &[child, base, datum, root]);

    let mut parent_deleted = vec![initial[0].clone(), reparented[2].clone()];
    parent_deleted.push(Skeleton::Type {
        path: missing,
        explicit_parent: None,
    });
    let fourth = build(&parent_deleted);
    assert_eq!(
        fourth.domain_version(ReadDomain::OwnerHierarchy(base)),
        None
    );
    assert!(fourth
        .domain_version(ReadDomain::OwnerHierarchy(missing))
        .is_some());
    assert_eq!(
        Resolver::resolve(&fourth, ResolveQuery::Type(missing)),
        dm_ir::ResolvedMeaning::Symbol(missing)
    );
    let snapshot = crate::TreeSnapshot {
        tree: Arc::new(second.clone()),
        occurrences: Arc::new(
            crate::OccurrenceTable::build(
                &second,
                second
                    .declarations()
                    .iter()
                    .map(|_| crate::Provenance {
                        span: dm_ir::Span {
                            file: dm_ir::FileId(0),
                            start: 0,
                            end: 1,
                        },
                        include_occurrence: 0,
                        region: 0,
                        expansion_stack: Arc::from([]),
                    })
                    .collect(),
            )
            .unwrap(),
        ),
    };
    let scalar = crate::constant_resolution::resolve(
        &snapshot,
        &[],
        &crate::constant_resolution::ScalarBackend {
            identity: 123,
            decode_string: &|text| Some(text.as_bytes().to_vec()),
            nameof: &|_| None,
        },
    );
    assert_eq!(scalar.domain_version(domain), second.domain_version(domain));
    assert_eq!(
        Resolver::resolve(&scalar, ResolveQuery::Type(child)),
        Resolver::resolve(&second, ResolveQuery::Type(child))
    );
    let hierarchy = crate::EngineHierarchy {
        schema: 19,
        parents: first
            .types()
            .iter()
            .map(|node| {
                (
                    node.path,
                    node.parent.map(|id| first.types()[id.index()].path),
                )
            })
            .collect(),
    };
    assert!(hierarchy.parents.contains(&(root, None)));
    let complete = first
        .clone()
        .with_complete_intrinsics(hierarchy, Vec::new())
        .unwrap();
    assert_ne!(complete.domain_version(domain), Some(first_version));
    assert_eq!(
        Resolver::resolve(&complete, ResolveQuery::Ancestry(child)),
        dm_ir::ResolvedMeaning::Symbols(vec![child, base, datum, root].into())
    );
    assert_eq!(
        ResolveQuery::Var {
            owner: child,
            name: SymbolId::of("x")
        }
        .domain(),
        ReadDomain::OwnerScalar(ResolveQuery::Var {
            owner: child,
            name: SymbolId::of("x")
        })
    );
    assert_eq!(
        complete.domain_version(
            ResolveQuery::Var {
                owner: child,
                name: SymbolId::of("x")
            }
            .domain()
        ),
        None
    );
    assert!(!domain.persistent_version());
}
