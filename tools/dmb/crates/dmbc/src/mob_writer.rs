//! Mob-table allocation is distinct from semantic class-table allocation.
//! Records inherit pinned parent ABI and follow an explicit observable order.
use byond_dmb::{
    dmb::{Dmb, MobType},
    ids::NONE,
};
use dm_ir::SymbolId;
use dm_link::{Key, LinkTables};
use std::collections::{HashMap, HashSet};

pub fn materialize(
    dmb: &mut Dmb,
    tables: &LinkTables,
    order: &[SymbolId],
) -> Result<HashMap<SymbolId, u32>, String> {
    let mut known = HashMap::new();
    for (index, record) in dmb.mobs.iter().enumerate() {
        if record.class as usize >= dmb.classes.len()
            || known.insert(record.class, index as u32).is_some()
        {
            return Err("invalid or duplicated retained mob class".into());
        }
    }
    let mut admitted = HashSet::new();
    let mut result = HashMap::new();
    for &path in order {
        if !admitted.insert(path) {
            return Err("duplicate observable mob order entry".into());
        }
        let class = tables
            .index(Key::Type(path))
            .ok_or("mob type linker binding missing")?;
        let mut chain = Vec::new();
        let mut visited = HashSet::new();
        let mut current = class;
        while !known.contains_key(&current) {
            if !visited.insert(current) {
                return Err("cyclic mob ancestry".into());
            }
            let record = dmb
                .classes
                .get(current as usize)
                .ok_or("mob class missing")?;
            chain.push(current);
            if dmb.string(record.path_string_id()) == Some(b"/mob".as_slice()) {
                break;
            }
            current = record.parent_class_id();
            if current == NONE {
                return Err("requested mob table entry is outside mob hierarchy".into());
            }
        }
        while let Some(class) = chain.pop() {
            let parent = dmb.classes[class as usize].parent_class_id();
            let mut record = match known.get(&parent) {
                Some(parent_index) => dmb.mobs[*parent_index as usize].clone(),
                None if dmb.string(dmb.classes[class as usize].path_string_id())
                    == Some(b"/mob".as_slice()) =>
                {
                    MobType {
                        class,
                        key: NONE,
                        sight: 0,
                        extended_sight: None,
                    }
                }
                None => return Err("mob parent ABI record absent".into()),
            };
            record.class = class;
            let index = u32::try_from(dmb.mobs.len()).map_err(|_| "mob table overflow")?;
            dmb.mobs.push(record);
            known.insert(class, index);
        }
        result.insert(path, *known.get(&class).ok_or("mob allocation missing")?);
    }
    Ok(result)
}

/// Shared encounter-order mob domain allocation for code and scalar defaults.
pub(crate) fn materialize_projection(
    dmb: &mut Dmb,
    tables: &LinkTables,
    projection: &crate::class_projection::ClassProjection,
) -> Result<HashMap<SymbolId, u32>, String> {
    let mut mob_order = Vec::new();
    for ty in projection.types.iter() {
        let Some(mut class) = tables.index(Key::Type(ty.path)) else {
            continue;
        };
        let mut visited = HashSet::new();
        while visited.insert(class) {
            let Some(record) = dmb.classes.get(class as usize) else {
                break;
            };
            if dmb.string(record.path_string_id()) == Some(b"/mob".as_slice()) {
                mob_order.push(ty.path);
                break;
            }
            class = record.parent_class_id();
            if class == NONE {
                break;
            }
        }
    }
    mob_order.sort_by_key(|path| tables.index(Key::Type(*path)));
    materialize(dmb, tables, &mob_order)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn retained_mob_domains_keep_their_exact_table_identity() {
        let bytes = include_bytes!(
            "../../../fixtures/translation/client_header_probe/feature_load_ext.native.bin"
        );
        let mut dmb = Dmb::from_bytes(bytes).unwrap();
        let mut inventory = dm_link::LinkInventory::default();
        let mut order = Vec::new();
        let mut expected = HashMap::new();
        for (index, mob) in dmb.mobs.iter().enumerate() {
            let path = dmb
                .string(dmb.classes[mob.class as usize].path_string_id())
                .unwrap();
            let symbol = SymbolId::of_bytes(path);
            inventory.entries.push(dm_link::Entry {
                key: Key::Type(symbol),
                content: path.into(),
            });
            inventory.spellings.push((symbol, path.into()));
            inventory.fixed.push((Key::Type(symbol), mob.class));
            order.push(symbol);
            expected.insert(symbol, index as u32);
        }
        let tables = LinkTables::build(inventory).unwrap();
        let count = dmb.mobs.len();
        assert_eq!(materialize(&mut dmb, &tables, &order).unwrap(), expected);
        assert_eq!(dmb.mobs.len(), count);
        for (&path, &mob_index) in &expected {
            let class = tables.index(Key::Type(path)).unwrap();
            let code = dm_ir::SymbolicCode::new(
                vec![0, 0],
                vec![dm_ir::Relocation {
                    offset: 0,
                    reference: dm_ir::SymRef::Type(path),
                    encoding: dm_ir::RelocationEncoding::PackedValue24 { tag: 8 },
                }],
            )
            .unwrap();
            let mut words = code.link(|_| Some(class)).unwrap();
            dm_link::admit_type_path_words(&mut words, &code, &tables, &expected).unwrap();
            let emitted = ((words[0] >> 8) << 16) | words[1];
            assert_eq!(emitted, mob_index);
            assert_eq!(dmb.mobs[emitted as usize].class, class);
        }
        if let Some(&first) = order.first() {
            assert!(materialize(&mut dmb, &tables, &[first, first]).is_err());
        }
    }
}

/// Replay already validated authored writes after allocation, so descendants
/// inherit the final parent settings even when their records were allocated first.
pub(crate) fn apply_settings(
    dmb: &mut Dmb,
    writes: &std::collections::BTreeMap<u32, Vec<(u8, u32)>>,
) -> Result<(), String> {
    if writes.is_empty() {
        return Ok(());
    }
    let indexes: HashMap<_, _> = dmb
        .mobs
        .iter()
        .enumerate()
        .map(|(index, record)| (record.class, index))
        .collect();
    let mut finished = HashSet::new();
    let mut changed = HashSet::new();
    for start in 0..dmb.mobs.len() {
        let mut chain = Vec::new();
        let mut visiting = HashSet::new();
        let mut next = Some(start);
        while let Some(index) = next {
            if finished.contains(&index) {
                break;
            }
            if !visiting.insert(index) {
                return Err("cyclic mob ancestry".into());
            }
            chain.push(index);
            let parent = dmb
                .classes
                .get(dmb.mobs[index].class as usize)
                .ok_or("mob class missing")?
                .parent_class_id();
            next = indexes.get(&parent).copied();
        }
        while let Some(index) = chain.pop() {
            let class = dmb.mobs[index].class;
            let parent = dmb.classes[class as usize].parent_class_id();
            if let Some(&parent_index) = indexes.get(&parent) {
                if changed.contains(&parent_index) {
                    dmb.mobs[index].sight = dmb.mobs[parent_index].sight;
                    dmb.mobs[index].extended_sight = dmb.mobs[parent_index].extended_sight;
                    changed.insert(index);
                }
            }
            if let Some(settings) = writes.get(&class) {
                let record = &mut dmb.mobs[index];
                for &(setting, value) in settings {
                    let mut flags = record.sight_bits();
                    let mut dark = record.see_in_dark_setting().unwrap_or(2);
                    let mut invisible = record.see_invisible_setting().unwrap_or(0);
                    match setting {
                        0 => flags = value,
                        1 => dark = value as u8,
                        2 => invisible = value as u8,
                        _ => return Err("invalid mob setting selector".into()),
                    }
                    if record.extended_sight.is_some() || setting != 0 || flags > 0x7f {
                        record.sight = 0x80;
                        record.extended_sight = Some((flags | 0x80, dark, invisible));
                    } else {
                        record.sight = flags as u8;
                    }
                }
                changed.insert(index);
            }
            finished.insert(index);
        }
    }
    Ok(())
}
