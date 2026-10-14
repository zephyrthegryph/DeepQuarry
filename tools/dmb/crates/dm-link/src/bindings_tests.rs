use super::*;
fn inventory(content: &[u8]) -> LinkInventory {
    let id = SymbolId::of("name");
    LinkInventory {
        entries: vec![Entry {
            key: Key::String(id),
            content: content.to_vec().into(),
        }],
        spellings: vec![(id, Arc::from(&b"name"[..]))],
        ..Default::default()
    }
}
#[test]
fn changed_content_reuses_only_exact_bindings_and_keeps_current_contents() {
    let first = LinkTables::build(inventory(b"before")).unwrap();
    let owner = first.binding_tables();
    let next = LinkTables::build_with_bindings(inventory(b"after"), Some(&owner)).unwrap();
    assert!(owner.same_owner(&next.binding_tables()));
    assert_eq!(
        first.content(Key::String(SymbolId::of("name"))),
        Some(&b"before"[..])
    );
    assert_eq!(
        next.content(Key::String(SymbolId::of("name"))),
        Some(&b"after"[..])
    );
    let mut changed = inventory(b"after");
    let id = SymbolId::of("new");
    changed.entries.push(Entry {
        key: Key::String(id),
        content: b"new".to_vec().into(),
    });
    changed.spellings.push((id, Arc::from(&b"new"[..])));
    let structural = LinkTables::build_with_bindings(changed, Some(&owner)).unwrap();
    assert!(!owner.same_owner(&structural.binding_tables()));
}
#[test]
fn prior_owner_never_hides_current_collision_or_allocator_errors() {
    let prior = LinkTables::build(inventory(b"before"))
        .unwrap()
        .binding_tables();
    let mut invalid = inventory(b"before");
    invalid.entries.push(Entry {
        key: Key::String(SymbolId::of("name")),
        content: b"different".to_vec().into(),
    });
    assert!(matches!(
        LinkTables::build_with_bindings(invalid, Some(&prior)),
        Err(LinkError::ContentCollision(_))
    ));
    let mut invalid = inventory(b"before");
    invalid.fixed = vec![
        (Key::String(SymbolId::of("name")), 1),
        (Key::String(SymbolId::of("name")), 1),
    ];
    assert!(matches!(
        LinkTables::build_with_bindings(invalid, Some(&prior)),
        Err(LinkError::DuplicateFixed(_))
    ));
}

#[test]
fn retained_assignment_recipe_reuses_after_current_validation_and_rejects_policy_changes() {
    let retained = RetainedBindings::default();
    let first = retained.build(inventory(b"before")).unwrap();
    let body = retained.build(inventory(b"after")).unwrap();
    assert_eq!(retained.assignment_reuses(), 1);
    assert!(first.binding_tables().same_owner(&body.binding_tables()));
    assert_eq!(
        body.content(Key::String(SymbolId::of("name"))),
        Some(&b"after"[..])
    );
    let mut conflict = inventory(b"after");
    conflict.entries.push(Entry {
        key: Key::String(SymbolId::of("name")),
        content: b"conflict".to_vec().into(),
    });
    assert!(matches!(
        retained.build(conflict),
        Err(LinkError::ContentCollision(_))
    ));
    assert_eq!(retained.assignment_reuses(), 1);
    let mut invalid = inventory(b"after");
    invalid.orders.insert(Table::String, vec![]);
    assert_eq!(
        retained.build(invalid).err(),
        Some(LinkError::IncompleteOrder(Table::String))
    );
    assert_eq!(retained.assignment_reuses(), 1);
    let mut fixed = inventory(b"after");
    fixed.fixed.push((Key::String(SymbolId::of("name")), 7));
    let fresh = LinkTables::build(fixed.clone()).unwrap();
    let changed = retained.build(fixed).unwrap();
    assert_eq!(changed.assignments(), fresh.assignments());
    assert!(!changed.binding_tables().same_owner(&body.binding_tables()));
    assert_eq!(retained.assignment_reuses(), 1);
    let mut added = inventory(b"after");
    let name = SymbolId::of("added");
    added.entries.push(Entry {
        key: Key::String(name),
        content: b"added".to_vec().into(),
    });
    added.spellings.push((name, Arc::from(&b"added"[..])));
    let fresh = LinkTables::build(added.clone()).unwrap();
    let current = retained.build(added).unwrap();
    assert_eq!(current.assignments(), fresh.assignments());
    assert_eq!(retained.assignment_reuses(), 1);
    let removed = retained.build(inventory(b"current")).unwrap();
    assert_eq!(
        removed.assignments(),
        LinkTables::build(inventory(b"current"))
            .unwrap()
            .assignments()
    );
    assert_eq!(retained.assignment_reuses(), 1);
    retained.build(inventory(b"last")).unwrap();
    assert_eq!(retained.assignment_reuses(), 2);
}

#[test]
fn unpublished_link_binding_changes_cannot_replace_published_recipe() {
    let owner = RetainedBindings::default();
    let first = owner.for_request(true);
    let original = first.build(inventory(b"before")).unwrap().binding_tables();
    assert!(first.publish_successful());
    let changed_inventory = || {
        let mut value = inventory(b"changed");
        value.fixed.push((Key::String(SymbolId::of("name")), 7));
        value
    };
    let failed = owner.for_request(true);
    let changed = failed.build(changed_inventory()).unwrap();
    assert!(!original.same_owner(&changed.binding_tables()));
    drop(failed);
    let build = owner.for_request(true);
    let current = build.build(inventory(b"after")).unwrap();
    assert!(original.same_owner(&current.binding_tables()));
    assert_eq!(build.assignment_reuses(), 1);
    let analysis = owner.for_request(false);
    analysis.build(changed_inventory()).unwrap();
    assert!(!analysis.publish_successful());
    assert!(build.publish_successful());
    let next = owner.for_request(true);
    assert!(original.same_owner(&next.build(inventory(b"current")).unwrap().binding_tables()));
    let structural = owner.for_request(true);
    let fresh = LinkTables::build(changed_inventory()).unwrap();
    let current = structural.build(changed_inventory()).unwrap();
    assert_eq!(current.assignments(), fresh.assignments());
    assert!(structural.publish_successful());
    let replaced = owner.for_request(true);
    assert!(current.binding_tables().same_owner(
        &replaced
            .build(changed_inventory())
            .unwrap()
            .binding_tables()
    ));
    // A sealed request remains usable as a fresh builder but never mutates its publication.
    first.build(changed_inventory()).unwrap();
    assert!(original.same_owner(&first.current.lock().unwrap().as_ref().unwrap().bindings));
}
