use super::*;
use dm_ir::{ReadDomain, ResolveQuery, Resolver};

#[test]
fn callable_certificates_reuse_local_inputs_and_propagate_parent_changes() {
    let mut symbols = SymbolTable::default();
    let datum = symbols.intern("/datum").unwrap();
    let base = symbols.intern("/datum/base").unwrap();
    let child = symbols.intern("/datum/child").unwrap();
    let other = symbols.intern("/datum/other").unwrap();
    let name = symbols.intern("callback").unwrap();
    let variable = symbols.intern("value").unwrap();
    let sibling = symbols.intern("sibling").unwrap();
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
        Skeleton::Type {
            path: other,
            explicit_parent: None,
        },
        Skeleton::Member {
            owner: base,
            name,
            kind: MemberKind::Proc,
            mode: DefinitionMode::Declare,
            metadata: Arc::new(MemberMetadata::default()),
            content: 1,
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
    let query = ResolveQuery::Proc {
        owner: base,
        name,
        verb: false,
    };
    let version = first.domain_version(query.domain()).unwrap();
    let mut unrelated = initial.clone();
    unrelated.push(Skeleton::Member {
        owner: other,
        name: variable,
        kind: MemberKind::Var,
        mode: DefinitionMode::Declare,
        metadata: Arc::new(MemberMetadata::default()),
        content: 77,
    });
    let second = build(&unrelated);
    assert_ne!(first.identity(), second.identity());
    assert_eq!(second.domain_version(query.domain()), Some(version));
    assert_eq!(
        Resolver::resolve(&first, query),
        Resolver::resolve(&second, query)
    );
    unrelated.push(Skeleton::Member {
        owner: base,
        name: sibling,
        kind: MemberKind::Proc,
        mode: DefinitionMode::Declare,
        metadata: Arc::new(MemberMetadata::default()),
        content: 9,
    });
    let sibling_added = build(&unrelated);
    assert_eq!(sibling_added.domain_version(query.domain()), Some(version));
    assert_eq!(
        Resolver::resolve(&sibling_added, query),
        Resolver::resolve(&first, query)
    );
    unrelated[4] = Skeleton::Member {
        owner: base,
        name,
        kind: MemberKind::Proc,
        mode: DefinitionMode::Declare,
        metadata: Arc::new(MemberMetadata::default()),
        content: 2,
    };
    let changed = build(&unrelated);
    assert_eq!(changed.domain_version(query.domain()), Some(version));
    assert_eq!(
        Resolver::resolve(&first, query),
        Resolver::resolve(&changed, query)
    );
    let chain = ResolveQuery::OverrideChain {
        owner: child,
        name,
        verb: false,
    };
    assert_ne!(
        first.domain_version(chain.domain()),
        changed.domain_version(chain.domain())
    );
    let mut metadata_changed = unrelated.clone();
    if let Skeleton::Member { metadata, .. } = &mut metadata_changed[4] {
        Arc::make_mut(metadata).flags = 4;
    }
    let changed_metadata = build(&metadata_changed);
    assert_ne!(
        changed_metadata.domain_version(query.domain()),
        Some(version)
    );
    let mut shadowed = unrelated.clone();
    shadowed.push(Skeleton::Member {
        owner: child,
        name,
        kind: MemberKind::Proc,
        mode: DefinitionMode::Declare,
        metadata: Arc::new(MemberMetadata::default()),
        content: 1,
    });
    let shadow_query = ResolveQuery::Proc {
        owner: child,
        name,
        verb: false,
    };
    assert_ne!(
        build(&shadowed).domain_version(shadow_query.domain()),
        first.domain_version(shadow_query.domain())
    );
    let mut reparented = unrelated.clone();
    reparented[2] = Skeleton::Type {
        path: child,
        explicit_parent: Some(other),
    };
    let inherited_query = ResolveQuery::Proc {
        owner: child,
        name,
        verb: false,
    };
    assert_ne!(
        build(&reparented).domain_version(inherited_query.domain()),
        first.domain_version(inherited_query.domain())
    );
    assert_eq!(
        ResolveQuery::HasMemberProc { owner: child, name }.domain(),
        ReadDomain::OwnerCallable(ResolveQuery::HasMemberProc { owner: child, name })
    );
    assert_eq!(
        ResolveQuery::GlobalProc(name).domain(),
        ReadDomain::OwnerCallable(ResolveQuery::GlobalProc(name))
    );
    assert_eq!(
        ResolveQuery::Var {
            owner: child,
            name: variable
        }
        .domain(),
        ReadDomain::OwnerScalar(ResolveQuery::Var {
            owner: child,
            name: variable
        })
    );
    assert_eq!(
        first.domain_version(
            ResolveQuery::Var {
                owner: child,
                name: variable
            }
            .domain()
        ),
        None
    );
    assert!(!query.domain().persistent_version());
}
#[test]
fn global_selection_excludes_body_but_preserves_signature_and_formal_identity() {
    let mut symbols = SymbolTable::default();
    let root = symbols.intern("/").unwrap();
    let name = symbols.intern("global_callback").unwrap();
    let signature_path = symbols.intern("/proc/global_callback").unwrap();
    let missing_path = symbols.intern("/proc/absent_callback").unwrap();
    let malformed_path = symbols.intern("not_a_procedure_path").unwrap();
    let metadata = Arc::new(MemberMetadata {
        procedure: Some(Arc::new(dm_ir::ProcedureMetadata {
            signature: dm_ir::ProcedureSignature {
                parameters: Arc::from([]),
                variadic: false,
                return_annotation: None,
            },
            settings: Arc::from([]),
        })),
        ..Default::default()
    });
    let retained = crate::owner_normalization::RetainedNormalization::default();
    let build = |content, metadata: Arc<MemberMetadata>| {
        let rows = vec![Skeleton::Member {
            owner: root,
            name,
            kind: MemberKind::Proc,
            mode: DefinitionMode::Declare,
            metadata,
            content,
        }];
        let (index, _) =
            crate::declaration_contributions::KeyedDeclarations::capture(None, &rows).unwrap();
        crate::build_with_intrinsic_members_indexed(
            symbols.clone(),
            rows.as_slice().into(),
            &[],
            &[],
            false,
            Some((&index, &retained)),
        )
        .unwrap()
    };
    let first = build(1, Arc::clone(&metadata));
    for query in [
        ResolveQuery::Signature(signature_path),
        ResolveQuery::GlobalProc(name),
        ResolveQuery::MethodProcedureValue {
            owner: root,
            name,
            verb: false,
        },
    ] {
        assert!(first.domain_version(query.domain()).is_some());
    }

    let body_changed = build(2, Arc::clone(&metadata));
    for query in [
        ResolveQuery::Signature(signature_path),
        ResolveQuery::GlobalProc(name),
        ResolveQuery::MethodProcedureValue {
            owner: root,
            name,
            verb: false,
        },
    ] {
        assert_eq!(
            first.domain_version(query.domain()),
            body_changed.domain_version(query.domain())
        );
        assert_eq!(
            Resolver::resolve(&first, query),
            Resolver::resolve(&body_changed, query)
        );
    }
    let mut changed = metadata.as_ref().clone();
    Arc::make_mut(changed.procedure.as_mut().unwrap())
        .signature
        .variadic = true;
    let signature_changed = build(2, Arc::new(changed));
    let signature_query = ResolveQuery::Signature(signature_path);
    assert_ne!(
        first.domain_version(signature_query.domain()),
        signature_changed.domain_version(signature_query.domain())
    );
    assert_ne!(
        Resolver::resolve(&first, signature_query),
        Resolver::resolve(&signature_changed, signature_query)
    );
    for query in [
        ResolveQuery::Signature(missing_path),
        ResolveQuery::Signature(malformed_path),
        ResolveQuery::Signature(SymbolId::of("unissued_path")),
    ] {
        assert_eq!(signature_changed.domain_version(query.domain()), None);
        assert!(matches!(
            Resolver::resolve(&signature_changed, query),
            dm_ir::ResolvedMeaning::Unsupported(_)
        ));
    }
    let query = ResolveQuery::GlobalProc(name);
    assert_ne!(
        first.domain_version(query.domain()),
        signature_changed.domain_version(query.domain())
    );
    assert_ne!(
        Resolver::resolve(&first, query),
        Resolver::resolve(&signature_changed, query)
    );
    let unknown = ResolveQuery::GlobalProc(SymbolId::of("not_declared"));
    // Conservative root receipt still permits exact replay; the engine wrapper
    // independently declines Unsupported negative answers.
    assert!(signature_changed.domain_version(unknown.domain()).is_some());
}
