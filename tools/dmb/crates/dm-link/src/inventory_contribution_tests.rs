use super::*;
fn name(inventory: &mut LinkInventory, text: &str) -> SymbolId {
    let id = SymbolId::of(text);
    inventory.spellings.push((id, Arc::from(text.as_bytes())));
    id
}
#[test]
fn shared_chunks_preserve_encounter_order_and_validate_current_contents() {
    let mut shared = LinkInventory::default();
    let a = name(&mut shared, "a");
    let b = name(&mut shared, "b");
    let c = name(&mut shared, "c");
    let entry = |id, value: &[u8]| Entry {
        key: Key::String(id),
        content: value.to_vec().into(),
    };
    shared.entries.push(entry(a, b"a"));
    let owner = Arc::new(InventoryContribution::new(
        Key::String(b),
        b"b".to_vec().into(),
        Vec::new(),
    ));
    shared.append_shared(Arc::clone(&owner));
    shared.entries.push(entry(c, b"c"));
    assert!(Arc::ptr_eq(&shared.shared[0].owner, &owner));
    assert_eq!(
        shared.entry_iter().map(|e| e.key).collect::<Vec<_>>(),
        [Key::String(a), Key::String(b), Key::String(c)]
    );
    let mut flat = shared.clone();
    flat.entries = shared.entry_iter().collect();
    flat.shared.clear();
    let ordinary = LinkTables::build(flat).unwrap();
    let retained = RetainedBindings::default();
    let first = retained.build(shared.clone()).unwrap();
    assert_eq!(first.assignments(), ordinary.assignments());
    let next = retained.build(shared.clone()).unwrap();
    assert!(first.binding_tables().same_owner(&next.binding_tables()));
    assert_eq!(next.content(Key::String(b)), Some(&b"b"[..]));
    shared.entries.push(entry(b, b"changed"));
    assert!(
        matches!(retained.build(shared), Err(LinkError::ContentCollision(Key::String(id))) if id == b)
    );
}
#[test]
fn shared_slots_and_invalid_layout_cannot_bypass_ordinary_validation() {
    let mut inventory = LinkInventory::default();
    let owner = name(&mut inventory, "/datum/a");
    let name_id = name(&mut inventory, "field");
    let alias = SlotAlias {
        symbol: SymbolId::of("alias"),
        owner,
        name: name_id,
    };
    let chunk = Arc::new(InventoryContribution::new(
        Key::Variable {
            owner,
            name: name_id,
        },
        vec![0].into(),
        vec![alias],
    ));
    inventory.append_shared(Arc::clone(&chunk));
    inventory.slots.push(alias);
    assert_eq!(
        inventory.slot_iter().copied().collect::<Vec<_>>(),
        [alias, alias]
    );
    let first = LinkTables::build(inventory.clone()).unwrap();
    let mut flat = inventory.clone();
    flat.entries = inventory.entry_iter().collect();
    flat.slots = inventory.slot_iter().copied().collect();
    flat.shared.clear();
    let second = LinkTables::build(flat).unwrap();
    assert_eq!(first.assignments(), second.assignments());
    inventory.slots.push(SlotAlias {
        name: SymbolId::of("other"),
        ..alias
    });
    assert!(
        matches!(LinkTables::build(inventory.clone()), Err(LinkError::SlotCollision(id)) if id == alias.symbol)
    );
    inventory.shared[0].entries_before = usize::MAX;
    assert!(matches!(
        LinkTables::build(inventory),
        Err(LinkError::InvalidContributionOrder)
    ));
}

#[test]
fn immutable_strings_share_bytes_in_two_phases_and_keep_current_conflicts() {
    let a = dm_ir::StringPayload {
        id: SymbolId::of("a"),
        bytes: Arc::from(&b"a"[..]),
    };
    let binary = dm_ir::StringPayload {
        id: SymbolId::of_bytes(&[255, 22, b'X']),
        bytes: Arc::from(&[255, 22, b'X'][..]),
    };
    let key = Key::BuiltinGlobalVars;
    let owner = Arc::new(
        InventoryContribution::new(key, vec![0].into(), Vec::new())
            .with_strings(vec![a.clone(), binary.clone()]),
    );
    assert!(Arc::ptr_eq(&owner.strings()[0].bytes, &a.bytes));
    let mut inventory = LinkInventory::default();
    inventory.append_shared_strings(Arc::clone(&owner));
    // Current debug spelling/content belongs between immutable strings and code.
    let debug = name(&mut inventory, "current.dm");
    inventory.entries.push(Entry {
        key: Key::String(debug),
        content: b"current.dm".to_vec().into(),
    });
    inventory.append_shared(Arc::clone(&owner));
    assert!(Arc::ptr_eq(
        &inventory.shared[0].owner,
        &inventory.shared[1].owner
    ));
    assert_eq!(
        inventory.entry_iter().map(|e| e.key).collect::<Vec<_>>(),
        [
            Key::String(a.id),
            Key::String(binary.id),
            Key::String(debug),
            key
        ]
    );
    assert_eq!(
        inventory
            .spelling_iter()
            .map(|(id, _)| id)
            .collect::<Vec<_>>(),
        [a.id, binary.id, debug]
    );
    let mut flat = LinkInventory::default();
    flat.entries = inventory.entry_iter().collect();
    flat.spellings = inventory
        .spelling_iter()
        .map(|(id, bytes)| (id, Arc::clone(bytes)))
        .collect();
    let ordinary = LinkTables::build(flat).unwrap();
    let retained = RetainedBindings::default();
    let current = retained.build(inventory.clone()).unwrap();
    assert_eq!(current.assignments(), ordinary.assignments());
    assert_eq!(
        current.content(Key::String(binary.id)),
        Some(binary.bytes.as_ref())
    );
    inventory.entries.push(Entry {
        key: Key::String(a.id),
        content: b"changed".to_vec().into(),
    });
    assert!(
        matches!(retained.build(inventory), Err(LinkError::ContentCollision(Key::String(id))) if id == a.id)
    );
    let forged = Arc::new(
        InventoryContribution::new(key, vec![0].into(), Vec::new()).with_strings(vec![
            dm_ir::StringPayload {
                id: a.id,
                bytes: Arc::from(&b"forged"[..]),
            },
        ]),
    );
    let mut invalid = LinkInventory::default();
    invalid.append_shared_strings(forged);
    assert!(matches!(retained.build(invalid), Err(LinkError::InvalidSymbol(id)) if id == a.id));
}
