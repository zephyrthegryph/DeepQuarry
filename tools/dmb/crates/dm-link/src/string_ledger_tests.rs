use super::*;

/// A program: plain string entries (debug paths, declaration strings) and units, each a strings chunk and its entry.
#[derive(Clone)]
enum Part {
    Plain(&'static str),
    Unit(&'static str, Vec<String>),
}

fn unit_key(name: &str) -> Key {
    Key::Proc {
        owner: SymbolId::of("/"),
        name: SymbolId::of(name),
        occurrence: 0,
    }
}

fn payload(text: &str) -> dm_ir::StringPayload {
    dm_ir::StringPayload {
        id: SymbolId::of(text),
        bytes: Arc::from(text.as_bytes()),
    }
}

/// A fresh link of `parts`, numbered as dmbc's `string_order` numbers it: `registered` first, then first occurrences.
fn fresh(parts: &[Part], registered: &[&str]) -> LinkTables {
    let mut inventory = LinkInventory::default();
    for text in ["/"] {
        inventory.spellings.push((SymbolId::of(text), Arc::from(text.as_bytes())));
    }
    for part in parts {
        match part {
            Part::Plain(text) => {
                inventory.spellings.push((SymbolId::of(text), Arc::from(text.as_bytes())));
                inventory.entries.push(Entry {
                    key: Key::String(SymbolId::of(text)),
                    content: text.as_bytes().to_vec().into(),
                });
            }
            Part::Unit(name, strings) => {
                inventory.spellings.push((SymbolId::of(name), Arc::from(name.as_bytes())));
                let contribution = Arc::new(
                    InventoryContribution::new(unit_key(name), name.as_bytes().to_vec().into(), Vec::new())
                        .with_strings(strings.iter().map(|text| payload(text)).collect()),
                );
                inventory.append_shared_strings(Arc::clone(&contribution));
                inventory.append_shared(contribution);
            }
        }
    }
    let mut seen = BTreeSet::new();
    let mut order = Vec::new();
    // A registered string is a declaration's (a field name): an entry of its own names it, whatever the units name.
    for text in registered {
        inventory.spellings.push((SymbolId::of(text), Arc::from(text.as_bytes())));
        inventory.entries.push(Entry {
            key: Key::String(SymbolId::of(text)),
            content: text.as_bytes().to_vec().into(),
        });
    }
    for text in registered {
        if seen.insert(Key::String(SymbolId::of(text))) {
            order.push(Key::String(SymbolId::of(text)));
        }
    }
    let count = order.len();
    for entry in inventory.entry_iter() {
        if matches!(entry.key, Key::String(_)) && seen.insert(entry.key) {
            order.push(entry.key);
        }
    }
    inventory.append_orders.insert(Table::String, order);
    inventory.string_ledger = StringLedger::build(&inventory, count);
    LinkTables::build(inventory).unwrap()
}

fn strings_of(tables: &LinkTables) -> BTreeMap<Key, u32> {
    tables
        .assignments()
        .iter()
        .filter(|(key, _)| matches!(key, Key::String(_)))
        .map(|(key, index)| (*key, *index))
        .collect()
}

fn entries(strings: &[String]) -> Vec<(Key, EntryContent)> {
    strings
        .iter()
        .map(|text| (Key::String(SymbolId::of(text)), text.as_bytes().to_vec().into()))
        .collect()
}

fn s(texts: &[&str]) -> Vec<String> {
    texts.iter().map(|text| text.to_string()).collect()
}

/// Replace `unit`'s strings in `parts`: when the ledger admits it, the result must number every string as a fresh link.
fn check(parts: &[Part], registered: &[&str], unit: &'static str, strings: Vec<String>) -> bool {
    let before = fresh(parts, registered);
    let after_parts: Vec<Part> = parts
        .iter()
        .map(|part| match part {
            Part::Unit(name, _) if *name == unit => Part::Unit(name, strings.clone()),
            other => other.clone(),
        })
        .collect();
    let after = fresh(&after_parts, registered);
    match before.replaced_unit_strings(&[(unit_key(unit), entries(&strings))]) {
        Ok((replaced, slots)) => {
            assert_eq!(strings_of(&replaced), strings_of(&after), "{unit}: {strings:?}");
            for slot in &slots {
                assert_eq!(replaced.index(slot.new), Some(slot.index));
                assert_eq!(replaced.content(slot.new), after.content(slot.new));
            }
            for (key, index) in strings_of(&before) {
                if !slots.iter().any(|slot| slot.index == index) {
                    assert_eq!(replaced.index(key), Some(index), "an unchanged slot keeps its string");
                }
            }
            // The replaced ledger answers the next edit as a fresh one would.
            let again = replaced.replaced_unit_strings(&[(unit_key(unit), entries(&strings))]);
            assert!(again.is_ok_and(|(_, slots)| slots.is_empty()));
            true
        }
        Err(_) => false,
    }
}

fn program() -> Vec<Part> {
    vec![
        Part::Plain("code/a.dm"),
        Part::Unit("first", s(&["alpha", "shared", "beta"])),
        Part::Plain("code/b.dm"),
        Part::Unit("second", s(&["shared", "gamma"])),
        Part::Unit("third", s(&["delta", "beta"])),
        Part::Plain("gamma"),
    ]
}

#[test]
fn a_replaced_literal_takes_the_old_ones_slot() {
    assert!(check(&program(), &[], "first", s(&["alpha!", "shared", "beta"])));
    assert!(check(&program(), &[], "third", s(&["epsilon", "beta"])));
    // Unchanged strings and a literal reordered among the unit's own exclusive ones.
    assert!(check(&program(), &[], "first", s(&["alpha", "shared", "beta"])));
    assert!(check(&program(), &["delta"], "third", s(&["beta", "delta"])));
}

#[test]
fn edits_that_move_other_strings_are_refused() {
    // A new literal (later strings shift), a dropped one, one first named later, one another unit names.
    assert!(!check(&program(), &[], "first", s(&["alpha", "shared", "beta", "new"])));
    assert!(!check(&program(), &[], "third", s(&["beta"])));
    assert!(!check(&program(), &[], "first", s(&["alpha", "delta", "beta"])));
    assert!(!check(&program(), &[], "first", s(&["omega", "alpha", "beta"])));
    assert!(!check(&program(), &[], "second", s(&["shared", "gamma2"])));
}

#[test]
fn every_single_unit_edit_the_ledger_admits_is_numbered_as_a_fresh_link() {
    // Small random programs over a small alphabet, every unit's strings replaced by random lists.
    let alphabet = ["a", "b", "c", "d", "e", "f", "g", "h"];
    let mut state = 0x9e37_79b9_7f4a_7c15u64;
    let mut next = |bound: usize| {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        (state % bound as u64) as usize
    };
    let units = ["u0", "u1", "u2", "u3"];
    let plains = ["a", "b", "c", "d", "e", "f", "g", "h"];
    let mut admitted = 0;
    for _ in 0..3000 {
        let mut parts = Vec::new();
        for unit in units {
            if next(3) == 0 {
                parts.push(Part::Plain(plains[next(plains.len())]));
            }
            let strings = (0..next(4)).map(|_| alphabet[next(alphabet.len())].to_string()).collect();
            parts.push(Part::Unit(unit, strings));
        }
        let registered: Vec<&str> = (0..next(2)).map(|_| alphabet[next(alphabet.len())]).collect();
        let unit = units[next(units.len())];
        let strings = (0..next(4)).map(|_| alphabet[next(alphabet.len())].to_string()).collect();
        if check(&parts, &registered, unit, strings) {
            admitted += 1;
        }
    }
    assert!(admitted > 50, "the generator must exercise admitted replacements ({admitted})");
}

#[test]
fn an_extended_or_restored_table_has_no_ledger() {
    let tables = fresh(&program(), &[]);
    assert!(tables.string_ledger().is_some());
    let starts = [(Table::String, 100)].into_iter().collect();
    let (extended, _) = tables.extended([(Key::String(SymbolId::of("z")), b"z".to_vec().into())], &starts).unwrap();
    assert!(extended.string_ledger().is_none());
    assert!(extended.replaced_unit_strings(&[]).is_err());
}
