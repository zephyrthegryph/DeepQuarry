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
        owner: child,
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
    unrelated[4] = Skeleton::Member {
        owner: base,
        name,
        kind: MemberKind::Proc,
        mode: DefinitionMode::Declare,
        metadata: Arc::new(MemberMetadata::default()),
        content: 2,
    };
    let changed = build(&unrelated);
    assert_ne!(changed.domain_version(query.domain()), Some(version));
    assert_ne!(
        Resolver::resolve(&first, query),
        Resolver::resolve(&changed, query)
    );
    assert_eq!(
        ResolveQuery::HasMemberProc { owner: child, name }.domain(),
        ReadDomain::Tree
    );
    assert_eq!(ResolveQuery::GlobalProc(name).domain(), ReadDomain::Tree);
    assert_eq!(
        ResolveQuery::Var {
            owner: child,
            name: variable
        }
        .domain(),
        ReadDomain::Tree
    );
    assert!(!query.domain().persistent_version());
}
