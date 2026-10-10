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

#[test]
fn inherited_variable_demands_preserve_exact_local_and_parent_storage_facts() {
    let mut symbols = SymbolTable::default();
    let base = symbols.intern("/datum/base").unwrap();
    let child = symbols.intern("/datum/child").unwrap();
    let name = symbols.intern("value").unwrap();
    let other = symbols.intern("other").unwrap();
    let absent_name = symbols.intern("absent").unwrap();
    let retained = crate::owner_normalization::RetainedNormalization::default();
    let mut rows = vec![
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
            kind: MemberKind::Var,
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
    let query = ResolveQuery::DeclaredVarType { owner: child, name };
    let first = build(&rows);
    let token = first.domain_version(query.domain()).unwrap();
    rows.push(Skeleton::Member {
        owner: base,
        name: other,
        kind: MemberKind::Var,
        mode: DefinitionMode::Declare,
        metadata: Arc::new(MemberMetadata::default()),
        content: 2,
    });
    let unrelated = build(&rows);
    assert_eq!(unrelated.domain_version(query.domain()), Some(token));
    assert_eq!(
        Resolver::resolve(&first, query),
        Resolver::resolve(&unrelated, query)
    );
    if let Skeleton::Member { metadata, .. } = &mut rows[2] {
        Arc::make_mut(metadata).declared_type = Some(base);
    }
    let changed = build(&rows);
    assert_ne!(changed.domain_version(query.domain()), Some(token));
    let missing = ResolveQuery::HasMemberVar {
        owner: child,
        name: absent_name,
    };
    let negative = changed.domain_version(missing.domain()).unwrap();
    rows.push(Skeleton::Member {
        owner: base,
        name: absent_name,
        kind: MemberKind::Var,
        mode: DefinitionMode::Declare,
        metadata: Arc::new(MemberMetadata::default()),
        content: 0,
    });
    let present = build(&rows);
    assert_ne!(present.domain_version(missing.domain()), Some(negative));
    assert_eq!(changed.domain_version(missing.domain()), Some(negative));
    rows.push(Skeleton::Member {
        owner: child,
        name,
        kind: MemberKind::Var,
        mode: DefinitionMode::Declare,
        metadata: Arc::new(MemberMetadata::default()),
        content: 0,
    });
    let shadow = build(&rows);
    assert_ne!(
        shadow.domain_version(query.domain()),
        changed.domain_version(query.domain())
    );
    rows.pop();
    rows.remove(2);
    let removed = build(&rows);
    assert_ne!(removed.domain_version(query.domain()), Some(token));
    if let Skeleton::Type {
        explicit_parent, ..
    } = &mut rows[1]
    {
        *explicit_parent = None;
    }
    let reparented = build(&rows);
    assert_ne!(
        reparented.domain_version(missing.domain()),
        present.domain_version(missing.domain())
    );
}

#[test]
fn callable_presence_observes_both_namespaces_and_negative_ancestors() {
    let mut symbols = SymbolTable::default();
    let base = symbols.intern("/datum/base").unwrap();
    let child = symbols.intern("/datum/child").unwrap();
    let name = symbols.intern("action").unwrap();
    let other = symbols.intern("other").unwrap();
    let retained = crate::owner_normalization::RetainedNormalization::default();
    let mut rows = vec![
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
    let query = ResolveQuery::HasMemberProc { owner: child, name };
    let absent = build(&rows);
    let negative = absent.domain_version(query.domain()).unwrap();
    rows.push(Skeleton::Member {
        owner: base,
        name: other,
        kind: MemberKind::Proc,
        mode: DefinitionMode::Declare,
        metadata: Arc::new(MemberMetadata::default()),
        content: 1,
    });
    let unrelated = build(&rows);
    assert_eq!(unrelated.domain_version(query.domain()), Some(negative));
    rows.push(Skeleton::Member {
        owner: base,
        name,
        kind: MemberKind::Verb,
        mode: DefinitionMode::Declare,
        metadata: Arc::new(MemberMetadata::default()),
        content: 2,
    });
    let verb = build(&rows);
    let positive = verb.domain_version(query.domain()).unwrap();
    assert_ne!(positive, negative);
    assert_eq!(
        Resolver::resolve(&verb, query),
        dm_ir::ResolvedMeaning::Presence(true)
    );
    if let Skeleton::Member { content, .. } = &mut rows[3] {
        *content = 42;
    }
    let body = build(&rows);
    assert_eq!(body.domain_version(query.domain()), Some(positive));
    rows.pop();
    rows.push(Skeleton::Member {
        owner: base,
        name,
        kind: MemberKind::Proc,
        mode: DefinitionMode::Declare,
        metadata: Arc::new(MemberMetadata::default()),
        content: 2,
    });
    let procedure = build(&rows);
    assert_ne!(procedure.domain_version(query.domain()), Some(positive));
    assert_eq!(
        Resolver::resolve(&procedure, query),
        dm_ir::ResolvedMeaning::Presence(true)
    );
}

#[test]
fn provisional_selection_owner_cannot_prune_or_replace_current_issuer() {
    let mut symbols = SymbolTable::default();
    let root = symbols.intern("/").unwrap();
    let name = symbols.intern("callback").unwrap();
    let renamed = symbols.intern("renamed").unwrap();
    let before = symbols.intern("before_publish").unwrap();
    let after = symbols.intern("after_publish").unwrap();
    let retained = crate::owner_normalization::RetainedNormalization::default();
    let build = |name, deferred| {
        let rows = [Skeleton::Member {
            owner: root,
            name,
            kind: MemberKind::Proc,
            mode: DefinitionMode::Declare,
            metadata: Arc::new(MemberMetadata::default()),
            content: 1,
        }];
        let (index, _) =
            crate::declaration_contributions::KeyedDeclarations::capture(None, &rows).unwrap();
        crate::build_with_intrinsic_members_indexed_publication(
            symbols.clone(),
            rows.as_slice().into(),
            &[],
            &[],
            false,
            Some((&index, &retained)),
            deferred,
        )
        .unwrap()
    };
    let old = build(name, false);
    let query = ResolveQuery::GlobalProc(name);
    let token = old.domain_version(query.domain()).unwrap();
    let mut pending = build(renamed, true);
    assert_eq!(pending.domain_version(query.domain()), None);
    assert_eq!(old.domain_version(query.domain()), Some(token));
    assert!(
        old.domain_version(ResolveQuery::GlobalProc(before).domain())
            .is_some(),
        "unpublished candidate cannot detach actual current immutable issuer"
    );
    // Abandon another provisional candidate without admitting it.
    drop(build(name, true));
    assert_eq!(old.domain_version(query.domain()), Some(token));
    pending.publish_selection_owner();
    assert_ne!(pending.domain_version(query.domain()), Some(token));
    assert_eq!(
        old.domain_version(ResolveQuery::GlobalProc(after).domain()),
        None,
        "only final publication detaches the old unqueried issuer"
    );
    assert_eq!(
        old.domain_version(query.domain()),
        Some(token),
        "old-issued token remains immutable"
    );
}
