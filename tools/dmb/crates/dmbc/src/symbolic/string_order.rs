//! Expand current source registration events before ordinary StringID assignment.
use super::{unit_key, FrozenUnit};
use dm_ir::{RelocationEncoding, SymRef, SymbolId};
use dm_link::{
    Key, LinkInventory, StringRegistrationEvent as Event, StringRegistrationSource, Table,
};
use std::collections::{BTreeSet, HashSet};

pub(super) fn complete(inventory: &mut LinkInventory, units: &[FrozenUnit]) -> Result<(), String> {
    complete_with(inventory, |key, declaration, source| {
        let unit = units
            .iter()
            .find(|unit| unit_key(unit.lowered.identity) == key)
            .ok_or("first root string registration has no current frozen callable")?;
        let origin = &unit.lowered.origin;
        if origin.declaration.0 != declaration
            || origin.expanded_span.start != source.expanded_start
            || origin.expanded_span.end != source.expanded_end
        {
            return Err("first root string registration differs from current frozen source".into());
        }
        let mut strings = Vec::new();
        // The chronological source roster is authoritative for formal/local
        // names and literal leaves, including folded/unreachable ones. Frozen
        // frame names only supplement names absent from that roster;
        // code reachability can never remove a captured registration.
        for name in unit
            .lowered
            .frame
            .argument_names
            .iter()
            .chain(&unit.lowered.frame.local_names)
        {
            strings.push(SymbolId::of(name));
        }
        // A field reference is resolved against declaration-allocated strings,
        // not registered as an early lexical string. In the pinned member
        // control, holder.z_first leaves a_second/type_value/z_first in their
        // declaration order. Literal leaves already occur in the source roster.
        // Packed string values also cover generated constants: BYOND registers
        // "z_" + "first" as z_first before subsequent field declarations.
        // Direct string operands (fields, dynamic names, debug paths) are not
        // evidence of lexical value registration.
        strings.extend(value_string_registrations(unit.frozen.code()));
        Ok(strings)
    })
}

pub(in crate::symbolic) fn value_string_registrations(code: &dm_ir::SymbolicCode) -> impl Iterator<Item = SymbolId> + '_ {
    code.relocations().into_iter().filter_map(|relocation| {
        match (relocation.reference, relocation.encoding) {
            (SymRef::String(id), RelocationEncoding::PackedValue24 { tag: 6 }) => Some(id),
            _ => None,
        }
    })
}

fn complete_with(
    inventory: &mut LinkInventory,
    mut callable_strings: impl FnMut(
        Key,
        u32,
        StringRegistrationSource,
    ) -> Result<Vec<SymbolId>, String>,
) -> Result<(), String> {
    let Some(registration) = inventory.string_registration.as_ref() else {
        return Ok(());
    };
    if inventory.orders.contains_key(&Table::String)
        || inventory.append_orders.contains_key(&Table::String)
    {
        return Err(
            "source string registrations conflict with a supplied String table order".into(),
        );
    }
    let names: HashSet<_> = registration
        .events
        .iter()
        .filter_map(|event| match event {
            Event::FieldName { name, .. } => Some(*name),
            _ => None,
        })
        .collect();
    let fixed: BTreeSet<_> = inventory.fixed.iter().map(|(key, _)| *key).collect();
    let present: BTreeSet<_> = inventory
        .entry_iter()
        .filter_map(|entry| match entry.key {
            Key::String(_) => Some(entry.key),
            _ => None,
        })
        .collect();
    let mut seen = BTreeSet::new();
    let mut order = Vec::new();
    let mut add = |id: SymbolId| -> Result<(), String> {
        let key = Key::String(id);
        if !present.contains(&key) {
            return Err("source string registration has no current String inventory entry".into());
        }
        if !fixed.contains(&key) && seen.insert(key) {
            order.push(key);
        }
        Ok(())
    };
    let mut first_root = false;
    let mut previous_encounter = None;
    for event in &registration.events {
        let source = match event {
            Event::FieldName { source, .. }
            | Event::DeclarationStrings { source, .. }
            | Event::FirstRootCallable { source, .. } => *source,
        };
        if source.expanded_start > source.expanded_end
            || previous_encounter.is_some_and(|previous| previous > source.encounter_order)
        {
            return Err("source string registration encounter order is invalid".into());
        }
        previous_encounter = Some(source.encounter_order);
        match event {
            Event::FieldName { name, .. } => add(*name)?,
            Event::DeclarationStrings { strings, .. } => {
                for &id in strings.iter() {
                    if !names.contains(&id) {
                        return Err("declaration string registration is not a current source field spelling".into());
                    }
                    add(id)?;
                }
            }
            Event::FirstRootCallable {
                callable,
                declaration,
                strings,
                ..
            } => {
                if first_root
                    || !matches!(callable, Key::Proc { owner, .. } if *owner == SymbolId::of("/"))
                {
                    return Err(
                        "source string registration must identify exactly the first root proc"
                            .into(),
                    );
                }
                first_root = true;
                // Validate even an empty lexical roster against its current
                // frozen occurrence; later overrides cannot stand in for it.
                let supplemental = callable_strings(*callable, *declaration, source)?;
                for &id in strings.iter() {
                    if !names.contains(&id) {
                        return Err(
                            "root callable literal is not a current source field spelling".into(),
                        );
                    }
                    add(id)?;
                }
                for id in supplemental {
                    if names.contains(&id) {
                        add(id)?;
                    }
                }
            }
        }
    }
    drop(add);
    // Complete coverage follows the existing ordered symbolic replay. Duplicate
    // payload rows and fixed engine strings remain validated by LinkTables.
    for entry in inventory.entry_iter() {
        let key = entry.key;
        if matches!(key, Key::String(_)) && !fixed.contains(&key) && seen.insert(key) {
            order.push(key);
        }
    }
    inventory.append_orders.insert(Table::String, order);
    inventory.string_registration = None;
    Ok(())
}

#[cfg(test)]
mod tests;
