use super::*;
use dm_ir::{ReadDomain, ResolveQuery, Resolver};
#[test]
fn local_variable_receipts_reuse_unrelated_changes_and_reject_changed_declarations() {
    let mut symbols = SymbolTable::default();
    let root = symbols.intern("/").unwrap();
    let owner = symbols.intern("/datum/owner").unwrap();
    let name = symbols.intern("value").unwrap();
    let callback = symbols.intern("callback").unwrap();
    let retained = crate::owner_normalization::RetainedNormalization::default();
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
    let mut rows = vec![
        Skeleton::Type {
            path: owner,
            explicit_parent: Some(root),
        },
        Skeleton::Member {
            owner,
            name,
            kind: MemberKind::Var,
            mode: DefinitionMode::Declare,
            metadata: Arc::new(MemberMetadata::default()),
            content: 1,
        },
    ];
    let first = build(&rows);
    let queries = [
        ResolveQuery::HasMemberVar { owner, name },
        ResolveQuery::DeclaredVarType { owner, name },
        ResolveQuery::VarStorage { owner, name },
        ResolveQuery::StaticVar { owner, name },
    ];
    let mut before_demand = 0;
    retained.metadata.store.visit_storage(|view| {
        if let dm_session::ObservedArtifactStorageView::Entry { reads, .. } = view {
            before_demand += reads
                .iter()
                .filter(|read| matches!(read.answer, MetadataAnswer::VariableLocal(_)))
                .count();
        }
    });
    assert_eq!(
        before_demand, 0,
        "unused names must not allocate variable receipts"
    );
    for query in queries {
        assert!(first.domain_version(query.domain()).is_some());
    }

    let mut local_receipts = 0;
    retained.metadata.store.visit_storage(|view| {
        if let dm_session::ObservedArtifactStorageView::Entry { reads, .. } = view {
            for read in reads.iter() {
                if let MetadataAnswer::VariableLocal(inputs) = &read.answer {
                    local_receipts += 1;
                    assert_eq!(inputs.ancestors.len(), 1);
                    assert!(inputs
                        .members
                        .iter()
                        .all(|member| member.owner == inputs.ancestors[0]));
                }
            }
        }
    });
    assert!(local_receipts > 0);
    rows.push(Skeleton::Member {
        owner,
        name: callback,
        kind: MemberKind::Proc,
        mode: DefinitionMode::Declare,
        metadata: Arc::new(MemberMetadata::default()),
        content: 17,
    });
    let second = build(&rows);
    let unqueried_old = ResolveQuery::HasMemberVar {
        owner,
        name: SymbolId::of("never_requested"),
    };
    assert_eq!(first.domain_version(unqueried_old.domain()), None);
    assert!(second.domain_version(unqueried_old.domain()).is_some());
    assert_eq!(
        first.domain_version(unqueried_old.domain()),
        None,
        "old snapshots cannot adopt current negative receipts"
    );

    for query in queries {
        assert!(first.domain_version(query.domain()).is_some());
        assert_eq!(
            first.domain_version(query.domain()),
            second.domain_version(query.domain())
        );
        assert_eq!(
            Resolver::resolve(&first, query),
            Resolver::resolve(&second, query)
        );
    }
    if let Skeleton::Member { metadata, .. } = &mut rows[1] {
        Arc::make_mut(metadata).declared_type = Some(owner);
    }
    let changed = build(&rows);
    for query in queries {
        assert_ne!(
            first.domain_version(query.domain()),
            changed.domain_version(query.domain())
        );
    }
    for query in [
        ResolveQuery::Var { owner, name },
        ResolveQuery::GlobalVar(name),
        ResolveQuery::Constant { owner, name },
    ] {
        assert_eq!(query.domain(), ReadDomain::OwnerScalar(query));
        assert_eq!(changed.domain_version(query.domain()), None);
    }
    let missing = ResolveQuery::HasMemberVar {
        owner,
        name: SymbolId::of("unknown"),
    };
    assert!(changed.domain_version(missing.domain()).is_some());
    assert!(!queries[0].domain().persistent_version());
}

#[test]
fn source_variable_scalar_certificate_tracks_declaration_chain_and_content() {
    let mut symbols = SymbolTable::default();
    let root = symbols.intern("/").unwrap();
    let owner = symbols.intern("/datum/owner").unwrap();
    let name = symbols.intern("value").unwrap();
    let other = symbols.intern("other").unwrap();
    let retained = crate::owner_normalization::RetainedNormalization::default();
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
    let certificate = |tree: &SemanticTree| {
        let id = tree.resolve(tree.lookup_type(owner)?, name, MemberKind::Var)?;
        crate::constant_resolution::ScalarSnapshot::source_variable_certificate(
            tree,
            owner,
            name,
            tree.member(id)?,
        )
    };
    let member = |content: u128, declared_type: Option<SymbolId>| Skeleton::Member {
        owner,
        name,
        kind: MemberKind::Var,
        mode: DefinitionMode::Declare,
        metadata: Arc::new(MemberMetadata {
            declared_type,
            ..MemberMetadata::default()
        }),
        content,
    };
    let ty = Skeleton::Type {
        path: owner,
        explicit_parent: Some(root),
    };
    let first = build(&[ty.clone(), member(1, None)]);
    let base = certificate(&first).expect("current source variable is certified");
    assert_ne!(base & (1 << 63), 0, "disjoint from constant certificates");
    // An unrelated declaration leaves the certificate unchanged.
    let unrelated = build(&[
        ty.clone(),
        member(1, None),
        Skeleton::Member {
            owner,
            name: other,
            kind: MemberKind::Var,
            mode: DefinitionMode::Declare,
            metadata: Arc::new(MemberMetadata::default()),
            content: 9,
        },
    ]);
    assert_eq!(certificate(&unrelated), Some(base));
    // Content and metadata are both inputs of the scalar member answer.
    assert_ne!(certificate(&build(&[ty.clone(), member(2, None)])), Some(base));
    assert_ne!(certificate(&build(&[ty, member(1, Some(owner))])), Some(base));
}
