//! Complete the current declaration-issued procedure allocation roster.
//! Only generated helpers/initializers may be appended; ordinary methods
//! cannot silently fall back to symbolic hash ordering.
use dm_link::{Key, LinkInventory, Table};
use std::collections::BTreeSet;

pub(super) fn complete(inventory: &mut LinkInventory) -> Result<(), String> {
    let Some(mut order) = inventory.append_orders.remove(&Table::Procedure) else {
        return Ok(());
    };
    let fixed: BTreeSet<_> = inventory.fixed.iter().map(|(key, _)| *key).collect();
    let fresh: BTreeSet<_> = inventory
        .entries
        .iter()
        .map(|entry| entry.key)
        .filter(|key| key.table() == Table::Procedure && !fixed.contains(key))
        .collect();
    let mut seen = BTreeSet::new();
    for key in &order {
        if !matches!(key, Key::Proc { .. } | Key::Verb { .. })
            || !fresh.contains(key)
            || !seen.insert(*key)
        {
            return Err("invalid current procedure declaration allocation roster".into());
        }
    }
    for entry in &inventory.entries {
        let key = entry.key;
        if key.table() != Table::Procedure || fixed.contains(&key) || seen.contains(&key) {
            continue;
        }
        if !matches!(key, Key::ArgumentSource { .. } | Key::Initializer(_)) {
            return Err("procedure declaration omitted from current allocation roster".into());
        }
        seen.insert(key);
        order.push(key);
    }
    if seen != fresh {
        return Err("current procedure allocation roster is incomplete".into());
    }
    inventory.append_orders.insert(Table::Procedure, order);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_ir::SymbolId;
    use dm_link::{Entry, InitializerIdentity, LinkTables};
    fn method(name: &str) -> Key {
        Key::Proc {
            owner: SymbolId::of("/datum/order"),
            name: SymbolId::of(name),
            occurrence: 0,
        }
    }
    fn entry(key: Key) -> Entry {
        Entry {
            key,
            content: Vec::<u8>::new().into(),
        }
    }
    #[test]
    fn current_method_order_precedes_generated_domains_and_survives_hash_order() {
        let keys = [method("zebra"), method("alpha"), method("middle")];
        let generated = Key::Initializer(InitializerIdentity::Global);
        let mut inventory = LinkInventory::default();
        for name in ["/datum/order", "zebra", "alpha", "middle"] {
            inventory.spellings.push((SymbolId::of(name), std::sync::Arc::from(name.as_bytes())));
        }
        inventory.entries = vec![
            entry(keys[2]),
            entry(generated),
            entry(keys[0]),
            entry(keys[1]),
        ];
        inventory.reserved_prefixes.insert(Table::Procedure, 20);
        inventory
            .append_orders
            .insert(Table::Procedure, keys.to_vec());
        complete(&mut inventory).unwrap();
        let tables = LinkTables::build(inventory).unwrap();
        for (offset, key) in keys.iter().enumerate() {
            assert_eq!(tables.index(*key), Some(20 + offset as u32));
        }
        assert_eq!(tables.index(generated), Some(23));
    }
    #[test]
    fn missing_method_declines_instead_of_hash_ordering() {
        let mut inventory = LinkInventory::default();
        inventory.entries.push(entry(method("omitted")));
        inventory.append_orders.insert(Table::Procedure, vec![]);
        assert!(complete(&mut inventory).unwrap_err().contains("omitted"));
    }
}
