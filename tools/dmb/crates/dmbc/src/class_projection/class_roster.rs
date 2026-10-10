//! Canonical class identities issued by successful type materialization.
use dm_ir::SymbolId;
use std::collections::HashMap;
/// Shared borrowed capability for subsequent record writers. No path decoding,
/// alias normalization, ID reassignment or mutable model access is exposed.
pub(crate) struct MaterializedClassRoster {
    pub(super) ids: HashMap<SymbolId, u32>,
    owners: Vec<(u32, SymbolId)>,
}
impl MaterializedClassRoster {
    pub(super) fn issued(ids: HashMap<SymbolId, u32>) -> Self {
        let mut owners: Vec<_> = ids.iter().map(|(&path, &id)| (id, path)).collect();
        owners.sort_unstable_by_key(|&(id, _)| id);
        Self { ids, owners }
    }
    pub(super) fn owner(&self, index: usize) -> Option<SymbolId> {
        self.owners
            .get(index)
            .and_then(|&(id, owner)| (id as usize == index).then_some(owner))
    }
}

#[cfg(test)]
mod tests {
    use super::super::*;
    fn projection() -> ClassProjection {
        ClassProjection {
            field_placements: Default::default(),
            shared_slot_order: Arc::from([]),
            procedure_statics: Arc::from([]),
            runtime_writes: Arc::from([]),
            tree_identity: 0,
            occurrence_count: 0,
            types: Arc::from([]),
            fields: Arc::from([]),
            chains: Arc::from([]),
        procedure_membership: Arc::from([]),
            procedure_declarations: Default::default(),
        }
    }
    #[test]
    fn indexed_and_compatibility_type_writers_preserve_malformed_error_order() {
        let bytes = include_bytes!("../../../../fixtures/native_template.bin");
        let source = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
        let symbols = crate::engine::EngineSnapshot::from_bytes(bytes, 1)
            .unwrap()
            .symbols()
            .clone();
        let tables = dm_link::LinkTables::build(dm_link::LinkInventory::default()).unwrap();
        for mode in 0..3 {
            let mut image = source.clone();
            if mode == 0 {
                image.classes[0].initial_ids[0] = u32::MAX;
            }
            if mode == 1 {
                image.classes.push(image.classes[0].clone());
            }
            if mode == 2 {
                let path = image.classes[0].path_string_id() as usize;
                image.strings[path].data = vec![0xff];
            }
            let mut legacy = image.clone();
            let mut index = crate::composition::StringIndex::build(&image).unwrap();
            let old = materialize_types(&mut legacy, &projection(), &tables, &symbols)
                .err()
                .unwrap();
            let new = materialize_types_with_roster(
                &mut image,
                &projection(),
                &tables,
                &symbols,
                &mut index,
            )
            .err()
            .unwrap();
            assert_eq!(format!("{old:?}"), format!("{new:?}"));
        }
    }
    #[test]
    fn roster_is_canonical_despite_hashmap_insertion_order() {
        let a = SymbolId::of("/a");
        let b = SymbolId::of("/b");
        let first = MaterializedClassRoster::issued([(a, 0), (b, 1)].into_iter().collect());
        let second = MaterializedClassRoster::issued([(b, 1), (a, 0)].into_iter().collect());
        assert_eq!(first.owner(0), second.owner(0));
        assert_eq!(first.owner(1), second.owner(1));
        assert_eq!(first.ids, second.ids);
        assert_eq!(first.owner(2), None);
    }
}
