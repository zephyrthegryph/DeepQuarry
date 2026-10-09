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
