//! Source inventory admission with explicit observable class and shared-slot
//! orders. Retained engine indexes stay fixed; hash order is never substituted.
use crate::class_projection::{ClassProjection, FieldRole};
use dm_ir::{SymbolId, SymbolTable};
use dm_link::{Entry, Key, LinkInventory, Table};
use std::{
    collections::{BTreeMap, BTreeSet, HashSet},
    sync::Arc,
};

pub fn contribute(
    plan: &ClassProjection,
    symbols: &SymbolTable,
    source_type_order: &[SymbolId],
    inventory: &mut LinkInventory,
) -> Result<(), String> {
    let retained: BTreeSet<_> = inventory.fixed.iter().map(|(key, _)| *key).collect();
    let mut source_types = HashSet::new();
    for ty in plan.types.iter() {
        let text = symbols.text(ty.path).ok_or("type spelling missing")?;
        if text == "/" || text == "/world" || retained.contains(&Key::Type(ty.path)) {
            continue;
        }
        let mut content = b"dm-class-skeleton-v1\0".to_vec();
        match ty.parent {
            None => content.push(0),
            Some(parent) => {
                content.push(1);
                content.extend_from_slice(&parent.bits().to_le_bytes());
            }
        }
        inventory.entries.push(Entry {
            key: Key::Type(ty.path),
            content: content.into(),
        });
        inventory
            .spellings
            .push((ty.path, Arc::from(text.as_bytes())));
        source_types.insert(ty.path);
    }
    if source_type_order.len() != source_types.len()
        || source_type_order.iter().copied().collect::<HashSet<_>>() != source_types
    {
        return Err(
            "source class order must explicitly cover all fresh classes exactly once".into(),
        );
    }
    let mut variable_order = Vec::new();
    for field in plan
        .fields
        .iter()
        .filter(|field| field.role == FieldRole::Declaration && field.shared)
    {
        let key = Key::Variable {
            owner: field.owner,
            name: field.name,
        };
        if retained.contains(&key) {
            continue;
        }
        let flags = field.wire_flags.ok_or("shared formal flags unknown")?;
        let mut content = b"dm-shared-slot-v1\0".to_vec();
        content.extend_from_slice(&flags.to_le_bytes());
        inventory.entries.push(Entry {
            key,
            content: content.into(),
        });
        for symbol in [field.owner, field.name] {
            inventory.spellings.push((
                symbol,
                Arc::from(
                    symbols
                        .text(symbol)
                        .ok_or("shared field spelling absent")?
                        .as_bytes(),
                ),
            ));
        }
        variable_order.push(key);
    }
    for (table, fresh) in [
        (
            Table::Type,
            source_type_order
                .iter()
                .copied()
                .map(Key::Type)
                .collect::<Vec<_>>(),
        ),
        (Table::Variable, variable_order),
    ] {
        let pinned: BTreeMap<_, _> = inventory
            .fixed
            .iter()
            .filter(|(key, _)| key.table() == table)
            .map(|(key, index)| (*index, *key))
            .collect();
        let mut order = Vec::new();
        for (index, key) in pinned {
            if index as usize != order.len() {
                return Err("retained observable table has unrepresented holes".into());
            }
            order.push(key);
        }
        order.extend(fresh);
        if inventory
            .orders
            .get(&table)
            .is_some_and(|existing| *existing != order)
        {
            return Err("source order conflicts with supplied table order".into());
        }
        inventory.orders.insert(table, order);
    }
    Ok(())
}
