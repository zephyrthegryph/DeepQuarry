//! Anonymous descriptor inventory and attachment over the shared linker.
use crate::{class_projection::TypeValuePolicy, symbolic::FrozenBatch};
use dm_codegen_byond::lower_resolver::CapturedModifiedInstance;
use dm_ir::{SymRef, SymbolId};
use dm_link::{Entry, InitializerIdentity, Key, LinkInventory};
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};

pub fn contribute(
    descriptors: &[(SymRef, CapturedModifiedInstance)],
    inventory: &mut LinkInventory,
) -> Result<(), String> {
    let mut seen = BTreeMap::<SymbolId, &[u8]>::new();
    for (symbol, captured) in descriptors {
        let alias = captured.descriptor.alias();
        if symbol != &SymRef::Instance(SymbolId::of(&alias)) {
            return Err("modified descriptor symbol/content mismatch".into());
        }
        let id = SymbolId::of(&alias);
        let bytes = captured.descriptor.canonical_bytes();
        if let Some(old) = seen.insert(id, bytes) {
            if old != bytes {
                return Err("modified descriptor identity collision".into());
            }
            continue;
        }
        inventory.spellings.push((id, Arc::from(alias.as_bytes())));
        inventory.entries.push(Entry {
            key: Key::Instance(id),
            content: Arc::from(bytes),
        });
    }
    Ok(())
}

/// Apply before the map stage: canonical instance domain ordering places these
/// keys before map descriptor keys. No reserved engine instance is overwritten.
pub fn attach(
    dmb: &mut byond_dmb::dmb::Dmb,
    descriptors: &[(SymRef, CapturedModifiedInstance)],
    batch: &FrozenBatch,
    types: &dyn TypeValuePolicy,
) -> Result<BTreeSet<Key>, String> {
    let mut records = BTreeMap::new();
    let mut covered = BTreeSet::new();
    for (_, captured) in descriptors {
        let alias = SymbolId::of(&captured.descriptor.alias());
        let key = Key::Instance(alias);
        let index = batch
            .tables
            .index(key)
            .ok_or("modified descriptor link index missing")?;
        if batch.tables.content(key) != Some(captured.descriptor.canonical_bytes()) {
            return Err("modified descriptor frozen content mismatch".into());
        }
        let owner = captured.descriptor.runtime_type();
        let class = batch
            .tables
            .index(Key::Type(owner))
            .ok_or("modified receiver class missing")?;
        let kind = types
            .tag(owner)
            .map_err(|error| format!("modified receiver family: {error:?}"))?;
        let class = if kind == 8 {
            let index = types
                .mob_index(owner)
                .map_err(|error| format!("modified mob descriptor: {error:?}"))?;
            if dmb
                .mobs
                .get(index as usize)
                .is_none_or(|mob| mob.class != class)
            {
                return Err("modified mob/class binding mismatch".into());
            }
            index
        } else {
            if dmb.classes.get(class as usize).is_none() {
                return Err("modified class index invalid".into());
            }
            class
        };
        let initialization = Key::Initializer(InitializerIdentity::Modified(alias));
        let initializer = batch
            .tables
            .index(initialization)
            .ok_or("modified initializer image missing")?;
        if dmb.procs.get(initializer as usize).is_none() {
            return Err("modified initializer index invalid".into());
        }
        let record = byond_dmb::dmb::Instance {
            kind,
            class,
            initializer,
        };
        if records
            .insert(index, record.clone())
            .is_some_and(|old| old != record)
        {
            return Err("modified descriptor wire collision".into());
        }
        covered.insert(key);
        covered.insert(initialization);
    }
    for (ordinal, (index, _)) in records.iter().enumerate() {
        if *index as usize != dmb.instances.len() + ordinal {
            return Err(
                "modified descriptor allocation not contiguous before map descriptors".into(),
            );
        }
    }
    dmb.instances.extend(records.into_values());
    Ok(covered)
}
