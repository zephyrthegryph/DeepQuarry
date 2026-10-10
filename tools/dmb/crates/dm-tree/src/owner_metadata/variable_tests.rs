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
    rows.push(Skeleton::Member {
        owner,
        name: callback,
        kind: MemberKind::Proc,
        mode: DefinitionMode::Declare,
        metadata: Arc::new(MemberMetadata::default()),
        content: 17,
    });
    let second = build(&rows);
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
    assert_eq!(changed.domain_version(missing.domain()), None);
    assert!(!queries[0].domain().persistent_version());
}
