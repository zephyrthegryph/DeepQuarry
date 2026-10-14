use super::*;
use dm_link::{Entry, LinkTables, StringRegistration};
use std::sync::Arc;

fn source(encounter_order: usize) -> StringRegistrationSource {
    StringRegistrationSource {
        encounter_order,
        expanded_start: encounter_order,
        expanded_end: encounter_order + 1,
    }
}
fn field(name: &str, ordinal: usize) -> Event {
    Event::FieldName {
        owner: SymbolId::of("/datum/orderholder"),
        name: SymbolId::of(name),
        source: source(ordinal),
    }
}
fn first(strings: &[&str]) -> Event {
    Event::FirstRootCallable {
        callable: Key::Proc {
            owner: SymbolId::of("/"),
            name: SymbolId::of("first"),
            occurrence: 0,
        },
        declaration: 7,
        strings: strings
            .iter()
            .map(|text| SymbolId::of(text))
            .collect::<Vec<_>>()
            .into(),
        source: source(1),
    }
}
fn inventory(events: Vec<Event>) -> LinkInventory {
    let mut inventory = LinkInventory::default();
    // Deliberately neither declaration nor lexical order.
    for text in [
        "type_value",
        "tail",
        "a_second",
        "z_first",
        "before",
        "engine",
    ] {
        let id = SymbolId::of(text);
        let bytes: Arc<[u8]> = Arc::from(text.as_bytes());
        inventory.spellings.push((id, Arc::clone(&bytes)));
        inventory.entries.push(Entry {
            key: Key::String(id),
            content: bytes.into(),
        });
    }
    inventory
        .fixed
        .push((Key::String(SymbolId::of("engine")), 2));
    inventory.reserved_prefixes.insert(Table::String, 40);
    inventory.string_registration = Some(StringRegistration { events });
    inventory
}
fn assigned_order(mut inventory: LinkInventory) -> Vec<&'static str> {
    complete_with(&mut inventory, |key, declaration, _| {
        assert!(matches!(key, Key::Proc { occurrence: 0, .. }));
        assert_eq!(declaration, 7);
        // No frozen reference: the captured folded literal must still win.
        Ok(Vec::new())
    })
    .unwrap();
    let tables = LinkTables::build(inventory).unwrap();
    assert_eq!(tables.index(Key::String(SymbolId::of("engine"))), Some(2));
    let mut names = ["before", "z_first", "type_value", "a_second", "tail"];
    names.sort_by_key(|name| tables.index(Key::String(SymbolId::of(name))).unwrap());
    names.to_vec()
}

#[test]
fn string_allocation_first_root_literal_changes_field_ids_without_moving_prior_names() {
    assert_eq!(
        assigned_order(inventory(vec![
            field("before", 0),
            first(&["a_second"]),
            field("z_first", 2),
            field("type_value", 3),
            field("a_second", 4),
        ])),
        ["before", "a_second", "z_first", "type_value", "tail"]
    );
    assert_eq!(
        assigned_order(inventory(vec![
            field("before", 0),
            first(&[]),
            field("z_first", 2),
            field("type_value", 3),
            field("a_second", 4),
        ])),
        ["before", "z_first", "type_value", "a_second", "tail"]
    );
}

#[test]
fn string_allocation_initializer_registration_obeys_own_field_encounter_order() {
    assert_eq!(
        assigned_order(inventory(vec![
            field("before", 0),
            Event::DeclarationStrings {
                owner: SymbolId::of("/"),
                name: SymbolId::of("before"),
                strings: vec![SymbolId::of("a_second")].into(),
                source: source(0),
            },
            first(&[]),
            field("z_first", 2),
            field("type_value", 3),
            field("a_second", 4),
        ])),
        ["before", "a_second", "z_first", "type_value", "tail"]
    );
}

#[test]
fn string_allocation_rejects_unbound_first_occurrence_and_supplied_order_conflict() {
    let mut current = inventory(vec![first(&[]), field("z_first", 2)]);
    assert!(complete_with(&mut current, |_, _, _| Err(
        "foreign source occurrence".into()
    ))
    .is_err());
    assert!(current.string_registration.is_some());
    current.append_orders.insert(Table::String, vec![]);
    assert!(complete_with(&mut current, |_, _, _| Ok(Vec::new()))
        .unwrap_err()
        .contains("conflict"));
}

#[test]
fn string_allocation_generated_values_supplement_without_direct_member_operands() {
    let code = dm_ir::SymbolicCode::new(
        vec![0; 3],
        vec![
            dm_ir::Relocation {
                offset: 0,
                reference: SymRef::String(SymbolId::of("type_value")),
                encoding: RelocationEncoding::Direct,
            },
            dm_ir::Relocation {
                offset: 1,
                reference: SymRef::String(SymbolId::of("z_first")),
                encoding: RelocationEncoding::PackedValue24 { tag: 6 },
            },
        ],
    )
    .unwrap();
    let mut current = inventory(vec![
        first(&[]),
        field("a_second", 2),
        field("type_value", 3),
        field("z_first", 4),
    ]);
    complete_with(&mut current, |_, _, _| {
        Ok(value_string_registrations(&code).collect())
    })
    .unwrap();
    let tables = LinkTables::build(current).unwrap();
    let at = |name| tables.index(Key::String(SymbolId::of(name))).unwrap();
    assert!(at("z_first") < at("a_second"));
    assert!(at("a_second") < at("type_value"));
}
#[test]
fn string_allocation_member_reference_keeps_declaration_name_order() {
    // BYOND 516.1687 compile-only initializer_member_order control:
    // the first root body returns holder.z_first, but the holder names have
    // StringIDs a_second=439, type_value=440, z_first=441. A member operand
    // contributes no lexical registration; its eventual relocation uses the
    // declaration-allocated StringID.
    let order = assigned_order(inventory(vec![
        first(&[]),
        field("a_second", 2),
        field("type_value", 3),
        field("z_first", 4),
    ]));
    let at = |name| order.iter().position(|item| *item == name).unwrap();
    assert!(at("a_second") < at("type_value"));
    assert!(at("type_value") < at("z_first"));
}
#[test]
fn string_allocation_supplements_only_current_field_spellings_and_keeps_literals_first() {
    let mut current = inventory(vec![
        first(&["a_second"]),
        field("z_first", 2),
        field("type_value", 3),
        field("a_second", 4),
    ]);
    complete_with(&mut current, |_, _, _| {
        Ok(vec![SymbolId::of("type_value"), SymbolId::of("tail")])
    })
    .unwrap();
    let tables = LinkTables::build(current).unwrap();
    let id = |name| tables.index(Key::String(SymbolId::of(name))).unwrap();
    assert!(id("a_second") < id("type_value"));
    assert!(id("type_value") < id("z_first"));
    assert!(id("z_first") < id("tail"));
}
