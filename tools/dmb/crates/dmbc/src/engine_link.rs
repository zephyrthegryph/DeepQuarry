//! Positively captured engine bindings and reserved physical table domains.
//! Unnamed rows and duplicate strings occupy space without invented symbols.
use crate::{engine::EngineSnapshot, symbolic::ReferenceBindings};
use byond_dmb::{dmb::Dmb, ids::NONE};
use dm_codegen_byond::{Symbol, Table as OperandTable};
use dm_ir::{SymRef, SymbolId};
use dm_link::{Entry, Key, LinkInventory, Table};
use std::{collections::BTreeMap, sync::Arc};

pub struct EngineLinkFacts {
    pub inventory: LinkInventory,
    pub references: ReferenceBindings,
}

/// The engine snapshot and its exact captured bytes must have the same pin.
/// Capture does not derive source defaults or named meanings for anonymous rows.
pub fn capture(bytes: &[u8], engine: &EngineSnapshot) -> Result<EngineLinkFacts, String> {
    if !engine.matches_template(bytes, engine.interpretation_schema()) {
        return Err("engine link input differs from its pinned snapshot".into());
    }
    let dmb = Dmb::from_bytes(bytes).map_err(|error| error.to_string())?;
    dmb.validate_references()
        .map_err(|error| error.to_string())?;
    let mut inventory = LinkInventory::default();
    for (table, length) in [
        (Table::String, dmb.strings.len()),
        (Table::Type, dmb.classes.len()),
        (Table::Procedure, dmb.procs.len()),
        (Table::VariableRecord, dmb.variables.len()),
        (Table::Instance, dmb.instances.len()),
        (Table::List, dmb.lists.len()),
        (Table::Resource, dmb.resources.len()),
    ] {
        inventory.reserved_prefixes.insert(
            table,
            u32::try_from(length).map_err(|_| "engine table exceeds u32")?,
        );
    }
    let mut indexes = BTreeMap::new();
    let mut references = ReferenceBindings::default();
    for (index, string) in dmb.strings.iter().enumerate() {
        let bytes = string.data.as_slice();
        let id = SymbolId::of_bytes(bytes);
        inventory.spellings.push((id, Arc::from(bytes)));
        // Exact equal strings select their first physical spelling. All other
        // physical rows remain reserved; no fake identities are introduced.
        if indexes.contains_key(&Key::String(id)) {
            continue;
        }
        bind(
            &mut inventory,
            &mut indexes,
            Key::String(id),
            index,
            Arc::from(bytes),
        )?;
    }
    for (index, class) in dmb.classes.iter().enumerate() {
        let path = dmb
            .string(class.path_string_id())
            .ok_or("engine class path missing")?;
        let path = std::str::from_utf8(path).map_err(|_| "engine class path is not UTF-8")?;
        let id = spelling(&mut inventory, path);
        bind(
            &mut inventory,
            &mut indexes,
            Key::Type(id),
            index,
            retained_identity(engine, Table::Type, index),
        )?;
        references
            .references
            .insert(Symbol::new(OperandTable::Class, path), SymRef::Type(id));
    }
    for layout in engine.procedure_layouts() {
        let Some(name) = layout.name else {
            continue;
        };
        let owner_text = engine
            .symbols()
            .text(layout.owner)
            .ok_or("engine proc owner spelling missing")?;
        let name_text = engine
            .symbols()
            .text(name)
            .ok_or("engine proc spelling missing")?;
        spelling(&mut inventory, owner_text);
        spelling(&mut inventory, name_text);
        let (key, reference, namespace) = match layout.kind {
            dm_tree::MemberKind::Proc => (
                Key::Proc {
                    owner: layout.owner,
                    name,
                    occurrence: 0,
                },
                SymRef::Proc {
                    owner: layout.owner,
                    name,
                    occurrence: 0,
                },
                "proc",
            ),
            dm_tree::MemberKind::Verb => (
                Key::Verb {
                    owner: layout.owner,
                    name,
                    occurrence: 0,
                },
                SymRef::Verb {
                    owner: layout.owner,
                    name,
                    occurrence: 0,
                },
                "verb",
            ),
            dm_tree::MemberKind::Var => return Err("variable in captured procedure layout".into()),
        };
        bind(
            &mut inventory,
            &mut indexes,
            key,
            layout.wire_proc as usize,
            retained_identity(engine, Table::Procedure, layout.wire_proc as usize),
        )?;
        let path = format!(
            "{}/{namespace}/{name_text}",
            owner_text.trim_end_matches('/')
        );
        references
            .references
            .insert(Symbol::new(OperandTable::Proc, path), reference);
    }
    let footer = if dmb.variable_footer == NONE {
        Vec::new()
    } else {
        dmb.global_variable_flags()
            .ok_or("invalid engine shared footer")?
    };
    inventory.reserved_prefixes.insert(
        Table::Variable,
        u32::try_from(footer.len()).map_err(|_| "shared footer exceeds u32")?,
    );
    let mut owners = BTreeMap::new();
    for (index, class) in dmb.classes.iter().enumerate() {
        if class.defining_variable_list_id() == NONE {
            continue;
        }
        let owner = SymbolId::of_bytes(
            dmb.string(class.path_string_id())
                .ok_or("missing engine class path")?,
        );
        for (record, flags) in dmb
            .class_variable_declarations(index)
            .ok_or("invalid class declarations")?
        {
            if flags & 1 == 0 {
                continue;
            }
            if owners.insert(record, owner).is_some_and(|old| old != owner) {
                return Err("shared engine record has ambiguous declaring owner".into());
            }
        }
    }
    let root = spelling(&mut inventory, "/");
    for (slot, (record, _)) in footer.iter().enumerate() {
        let record = dmb
            .variables
            .get(*record as usize)
            .ok_or("missing shared engine record")?;
        let name = dmb
            .string(record.name)
            .ok_or("missing engine variable name")?;
        let name = std::str::from_utf8(name).map_err(|_| "engine variable name is not UTF-8")?;
        let name = spelling(&mut inventory, name);
        let owner = owners.get(&footer[slot].0).copied().unwrap_or(root);
        bind(
            &mut inventory,
            &mut indexes,
            Key::Variable { owner, name },
            slot,
            retained_identity(engine, Table::Variable, slot),
        )?;
    }
    let builtin = dmb.variables.iter().position(|record| {
        record.kind == 82
            && record.value == 0
            && dmb.string(record.name) == Some(b"vars".as_slice())
    });
    let key = Key::BuiltinGlobalVars;
    if let Some(index) = builtin {
        bind(
            &mut inventory,
            &mut indexes,
            key,
            index,
            retained_identity(engine, Table::VariableRecord, index),
        )?;
    } else {
        inventory.entries.push(Entry {
            key,
            content: Arc::from(b"builtin-global-vars-kind82-v1".as_slice()),
        });
    }
    Ok(EngineLinkFacts {
        inventory,
        references,
    })
}

fn spelling(inventory: &mut LinkInventory, text: &str) -> SymbolId {
    let id = SymbolId::of(text);
    inventory.spellings.push((id, Arc::from(text.as_bytes())));
    id
}
fn retained_identity(engine: &EngineSnapshot, table: Table, index: usize) -> Arc<[u8]> {
    let mut bytes = b"retained-engine-record-v1\0".to_vec();
    bytes.extend_from_slice(&engine.template_identity().to_le_bytes());
    bytes.push(table as u8);
    bytes.extend_from_slice(&(index as u64).to_le_bytes());
    bytes.into()
}
fn bind(
    inventory: &mut LinkInventory,
    indexes: &mut BTreeMap<Key, u32>,
    key: Key,
    index: usize,
    content: Arc<[u8]>,
) -> Result<(), String> {
    let index = u32::try_from(index).map_err(|_| "engine index exceeds u32")?;
    if let Some(previous) = indexes.insert(key, index) {
        if previous == index {
            return Ok(());
        }
        return Err(format!("ambiguous retained engine binding {key:?}"));
    }
    inventory.entries.push(Entry { key, content });
    inventory.fixed.push((key, index));
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn pinned_inventory_preserves_physical_prefixes_without_named_hole_fabrication() {
        let bytes = include_bytes!("../../../fixtures/native_template.bin");
        let engine = EngineSnapshot::from_bytes(bytes, 1).unwrap();
        let facts = capture(bytes, &engine).unwrap();
        let original = Dmb::from_bytes(bytes).unwrap();
        let linked = dm_link::LinkTables::build(facts.inventory.clone()).unwrap();
        assert_eq!(facts.inventory.reserved_prefixes[&Table::Procedure], original.procs.len() as u32);
        assert_eq!(facts.inventory.reserved_prefixes[&Table::VariableRecord], original.variables.len() as u32);
        for (index, class) in original.classes.iter().enumerate() {
            let symbol = SymbolId::of_bytes(original.string(class.path_string_id()).unwrap());
            assert_eq!(linked.index(Key::Type(symbol)), Some(index as u32));
        }
    }
}
