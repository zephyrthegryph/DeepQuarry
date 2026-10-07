//! Exact symbolic map descriptor inventory and DMB record attachment.
//! All semantic classification/defaults are inputs; DMB reads only validate
//! output references and do not answer source/type/initializer queries.
use crate::map_projection::{Instance, InstanceKind, Projection};
use byond_dmb::{
    dmb::{Dmb, GridRun, MapObject},
    ids::NONE,
};
use dm_ir::SymbolId;
use dm_link::{Entry, InitializerIdentity, Key, LinkInventory, LinkTables};
use dm_tree::maps::MapPlan;
use std::{collections::BTreeMap, sync::Arc};

pub struct DescriptorPlan {
    pub keys: Arc<[Key]>,
    pub initializers: Arc<[Option<InitializerIdentity>]>,
    pub entries: Vec<Entry>,
}
#[derive(Debug)]
pub enum Error {
    InvalidSource,
    Collision,
    Missing(Key),
    NonContiguous,
    InvalidReference,
    Unsupported(String),
}
fn kind(kind: InstanceKind) -> u8 {
    match kind {
        InstanceKind::Mob => 8,
        InstanceKind::Object => 9,
        InstanceKind::Turf => 10,
        InstanceKind::Area => 11,
    }
}
fn canonical(instance: &Instance) -> Vec<u8> {
    let mut bytes = b"byond-map-descriptor-v1\0".to_vec();
    bytes.push(kind(instance.kind));
    bytes.extend_from_slice(&instance.atom.type_path.bits().to_le_bytes());
    bytes.push(u8::from(instance.atom.initializer_present));
    bytes.extend_from_slice(&(instance.atom.assignments.len() as u64).to_le_bytes());
    for assignment in instance.atom.assignments.iter() {
        bytes.extend_from_slice(&assignment.name.bits().to_le_bytes());
        let value = assignment.value.canonical_bytes();
        bytes.extend_from_slice(&(value.len() as u64).to_le_bytes());
        bytes.extend_from_slice(&value);
    }
    bytes
}
pub fn descriptors(
    frontend: &dm_tree::frontend::ColdFrontend,
    projection: &Projection,
    maps: &[MapPlan],
) -> Result<DescriptorPlan, Error> {
    let mut documents = BTreeMap::<u128, Vec<u8>>::new();
    let mut starts = Vec::with_capacity(maps.len());
    let mut executable_documents = BTreeMap::new();
    let mut executable_ids = Vec::with_capacity(maps.len());
    for map in maps {
        let document = crate::map_identity::capture(frontend, map).map_err(Error::Unsupported)?;
        if let Some(previous) = executable_documents.get(&document.identity) {
            if previous != &document {
                return Err(Error::Collision);
            }
        }
        executable_ids.push(document.identity);
        executable_documents.insert(document.identity, document);
        let bytes = map.model.canonical_bytes();
        if xxhash_rust::xxh3::xxh3_128(&bytes) != map.semantic_identity {
            return Err(Error::InvalidSource);
        }
        if let Some(previous) = documents.get(&map.semantic_identity) {
            if previous != &bytes {
                return Err(Error::Collision);
            }
        } else {
            documents.insert(map.semantic_identity, bytes);
        }
        let mut ordinal = 0u32;
        let mut offsets = Vec::with_capacity(map.model.templates.len());
        for template in map.model.templates.iter() {
            offsets.push(ordinal);
            ordinal = ordinal
                .checked_add(u32::try_from(template.atoms.len()).map_err(|_| Error::InvalidSource)?)
                .ok_or(Error::InvalidSource)?;
        }
        starts.push(offsets);
    }
    let mut keys = Vec::with_capacity(projection.instances.len());
    let mut initializers = Vec::with_capacity(keys.capacity());
    let mut entries = Vec::with_capacity(keys.capacity());
    for instance in projection.instances.iter() {
        let (key, initializer) = if let Some(origin) = instance.origin {
            let map = maps.get(origin.map).ok_or(Error::InvalidSource)?;
            let atom = map
                .model
                .templates
                .get(origin.template)
                .and_then(|template| template.atoms.get(origin.atom))
                .ok_or(Error::InvalidSource)?;
            if atom != &instance.atom {
                return Err(Error::InvalidSource);
            }
            let descriptor = starts[origin.map][origin.template]
                .checked_add(u32::try_from(origin.atom).map_err(|_| Error::InvalidSource)?)
                .ok_or(Error::InvalidSource)?;
            let identity = InitializerIdentity::Map {
                source: executable_ids[origin.map],
                descriptor,
            };
            (
                Key::MapInstance {
                    source: if instance.atom.initializer_present {
                        executable_ids[origin.map]
                    } else {
                        map.semantic_identity
                    },
                    descriptor,
                },
                instance.atom.initializer_present.then_some(identity),
            )
        } else {
            if instance.atom.initializer_present || !instance.atom.assignments.is_empty() {
                return Err(Error::InvalidSource);
            }
            (
                Key::DefaultMapInstance {
                    kind: kind(instance.kind),
                    owner: instance.atom.type_path,
                },
                None,
            )
        };
        keys.push(key);
        initializers.push(initializer);
        entries.push(Entry {
            key,
            content: canonical(instance).into(),
        });
    }
    Ok(DescriptorPlan {
        keys: keys.into(),
        initializers: initializers.into(),
        entries,
    })
}
impl DescriptorPlan {
    pub fn extend_inventory(
        &self,
        projection: &Projection,
        inventory: &mut LinkInventory,
    ) -> Result<(), Error> {
        if self.keys.len() != projection.instances.len() {
            return Err(Error::InvalidSource);
        }
        inventory.entries.extend(self.entries.iter().cloned());
        for instance in projection
            .instances
            .iter()
            .filter(|instance| instance.origin.is_none())
        {
            // The caller's shared source/map symbol ledger supplies exact spelling.
            let expected = match instance.kind {
                InstanceKind::Turf => "/turf",
                InstanceKind::Area => "/area",
                _ => return Err(Error::InvalidSource),
            };
            if instance.atom.type_path == SymbolId::of(expected) {
                inventory
                    .spellings
                    .push((instance.atom.type_path, Arc::from(expected.as_bytes())));
            }
        }
        Ok(())
    }
}
/// Mob descriptor mapping is supplied by class projection. Mob descriptors are
/// a distinct namespace from classes even when their integers happen to agree.
pub fn attach(
    dmb: &mut Dmb,
    projection: &Projection,
    plan: &DescriptorPlan,
    tables: &LinkTables,
    mob_descriptors: &BTreeMap<SymbolId, u32>,
) -> Result<(), Error> {
    if projection.instances.len() != plan.keys.len()
        || plan.keys.len() != plan.initializers.len()
        || plan.entries.len() != plan.keys.len()
    {
        return Err(Error::InvalidSource);
    }
    let mut records = BTreeMap::new();
    let mut indexes = Vec::with_capacity(plan.keys.len());
    for (ordinal, instance) in projection.instances.iter().enumerate() {
        let key = plan.keys[ordinal];
        let index = tables.index(key).ok_or(Error::Missing(key))?;
        if tables.content(key) != Some(plan.entries[ordinal].content.as_ref())
            || plan.entries[ordinal].key != key
            || canonical(instance) != plan.entries[ordinal].content.as_ref()
        {
            return Err(Error::Collision);
        }
        let class_key = Key::Type(instance.atom.type_path);
        let class = tables.index(class_key).ok_or(Error::Missing(class_key))?;
        if dmb.classes.get(class as usize).is_none() {
            return Err(Error::InvalidReference);
        }
        let wire_class = if instance.kind == InstanceKind::Mob {
            let descriptor = *mob_descriptors
                .get(&instance.atom.type_path)
                .ok_or_else(|| {
                    Error::Unsupported("map mob requires certified descriptor projection".into())
                })?;
            if dmb
                .mobs
                .get(descriptor as usize)
                .is_none_or(|mob| mob.class != class)
            {
                return Err(Error::InvalidReference);
            }
            descriptor
        } else {
            class
        };
        let initializer = match plan.initializers[ordinal] {
            None => NONE,
            Some(identity) => {
                let key = Key::Initializer(identity);
                let proc = tables.index(key).ok_or(Error::Missing(key))?;
                if dmb.procs.get(proc as usize).is_none() {
                    return Err(Error::InvalidReference);
                }
                proc
            }
        };
        let record = byond_dmb::dmb::Instance {
            kind: kind(instance.kind),
            class: wire_class,
            initializer,
        };
        if records
            .insert(index, record.clone())
            .is_some_and(|previous| previous != record)
        {
            return Err(Error::Collision);
        }
        indexes.push(index);
    }
    for (position, (index, _)) in records.iter().enumerate() {
        if usize::try_from(*index).ok() != dmb.instances.len().checked_add(position) {
            return Err(Error::NonContiguous);
        }
    }
    let volume = projection
        .dimensions
        .iter()
        .map(|axis| u64::from(*axis))
        .product::<u64>();
    if volume == 0
        || projection
            .grid
            .iter()
            .map(|run| u64::from(run.copies))
            .sum::<u64>()
            != volume
    {
        return Err(Error::InvalidReference);
    }
    let mut grid = Vec::with_capacity(projection.grid.len());
    for run in projection.grid.iter() {
        if run.copies == 0
            || projection
                .instances
                .get(run.turf)
                .is_none_or(|instance| instance.kind != InstanceKind::Turf)
            || projection
                .instances
                .get(run.area)
                .is_none_or(|instance| instance.kind != InstanceKind::Area)
        {
            return Err(Error::InvalidReference);
        }
        grid.push(GridRun {
            turf: *indexes.get(run.turf).ok_or(Error::InvalidReference)?,
            area: *indexes.get(run.area).ok_or(Error::InvalidReference)?,
            contents: 0xffff,
            copies: run.copies,
        });
    }
    let mut objects = Vec::with_capacity(projection.objects.len());
    let mut position = 0u64;
    for object in projection.objects.iter() {
        position += u64::from(object.offset);
        if position >= volume
            || projection
                .instances
                .get(object.instance)
                .is_none_or(|instance| {
                    !matches!(instance.kind, InstanceKind::Mob | InstanceKind::Object)
                })
        {
            return Err(Error::InvalidReference);
        }
        objects.push(MapObject {
            offset: object.offset,
            instance: *indexes
                .get(object.instance)
                .ok_or(Error::InvalidReference)?,
        });
    }
    dmb.instances.extend(records.into_values());
    dmb.dimensions = projection.dimensions;
    dmb.grid = grid;
    dmb.map_objects = objects;
    if dmb.instances.len() > usize::from(u16::MAX) || dmb.map_objects.len() > usize::from(u16::MAX)
    {
        dmb.header.flags |= 0x4000_0000;
    }
    Ok(())
}
