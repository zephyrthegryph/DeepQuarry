use super::*;
use dm_ir::{ResolveQuery, Resolver};

#[test]
fn inherited_demands_reuse_only_exact_selected_ancestor_inputs() {
    let mut symbols = SymbolTable::default();
    let base = symbols.intern("/datum/base").unwrap();
    let child = symbols.intern("/datum/child").unwrap();
    let name = symbols.intern("callback").unwrap();
    let sibling = symbols.intern("sibling").unwrap();
    let retained = crate::owner_normalization::RetainedNormalization::default();
    let rows = vec![
        Skeleton::Type {
            path: base,
            explicit_parent: None,
        },
        Skeleton::Type {
            path: child,
            explicit_parent: Some(base),
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
    let query = ResolveQuery::Proc {
        owner: child,
        name,
        verb: false,
    };
    let first = build(&rows);
    let token = first.domain_version(query.domain()).unwrap();
    let mut body_edit = rows.clone();
    if let Skeleton::Member { content, .. } = &mut body_edit[2] {
        *content = 9;
    }
    body_edit.push(Skeleton::Member {
        owner: base,
        name: sibling,
        kind: MemberKind::Proc,
        mode: DefinitionMode::Declare,
        metadata: Arc::new(MemberMetadata::default()),
        content: 7,
    });
    let second = build(&body_edit);
    assert_eq!(second.domain_version(query.domain()), Some(token));
    assert_eq!(first.domain_version(query.domain()), Some(token));
    let mut signature_edit = body_edit.clone();
    if let Skeleton::Member { metadata, .. } = &mut signature_edit[2] {
        Arc::make_mut(metadata).flags = 4;
    }
    let third = build(&signature_edit);
    assert_ne!(third.domain_version(query.domain()), Some(token));
    let mut shadow = rows.clone();
    shadow.push(Skeleton::Member {
        owner: child,
        name,
        kind: MemberKind::Proc,
        mode: DefinitionMode::Declare,
        metadata: Arc::new(MemberMetadata::default()),
        content: 1,
    });
    let shadowed = build(&shadow);
    assert_ne!(shadowed.domain_version(query.domain()), Some(token));
    let mut removed = rows.clone();
    removed.pop();
    let absent = build(&removed);
    assert_ne!(absent.domain_version(query.domain()), Some(token));
    let mut reparented = rows.clone();
    if let Skeleton::Type {
        explicit_parent, ..
    } = &mut reparented[1]
    {
        *explicit_parent = None;
    }
    let mut reparented = build(&reparented);
    assert_ne!(reparented.domain_version(query.domain()), Some(token));
    let child_id = reparented.lookup_type(child).unwrap();
    Arc::make_mut(&mut reparented.types)[child_id.index()].parent = Some(child_id);
    assert_eq!(
        retained
            .metadata
            .demanded_selection(&reparented, (child, sibling, true)),
        None
    );
    let before = reparented
        .owner_callable_demands
        .tokens
        .lock()
        .unwrap()
        .len();
    let old_unqueried = (child, sibling, false);
    assert_eq!(
        retained.metadata.demanded_selection(&first, old_unqueried),
        None
    );
    assert_eq!(
        reparented
            .owner_callable_demands
            .tokens
            .lock()
            .unwrap()
            .len(),
        before
    );
}
