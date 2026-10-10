//! Explicit diagnostic traversal of shared immutable local namespace shapes.
use super::*;
use dm_tree::{frontend::RetainedSemanticTree, owner_local_shape::LocalShapeStorageView};

pub(super) fn inspect(census: &mut HeapCensus, state: &RetainedSemanticTree) {
    state.visit_local_shape_storage(|view| match view {
        LocalShapeStorageView::Store { buckets, entries } => {
            census.owner("retained_local_shape.index").observed_items += entries as u64;
            if buckets != 0 {
                census.unknown("retained_local_shape.index", "private ArtifactStore BTree nodes and Arc control blocks excluded; exposed immutable payload capacities counted");
            }
        }
        LocalShapeStorageView::Buffer { address, length, capacity } => {
            census.buffer("retained_local_shape.buffers", address, length, capacity);
        }
        LocalShapeStorageView::Entry { key, reads, versions, address, size } => {
            census.slice("retained_local_shape.keys", key, true);
            census.receipt("retained_local_shape.reads", reads);
            census.slice("retained_local_shape.versions", versions, true);
            census.buffer("retained_local_shape.values", address, size, size);
            for read in reads.iter() {
                super::retained_normalization::answer(census, &read.answer);
            }
        }
        LocalShapeStorageView::Payload { rows, selectors } => {
            census.slice("retained_local_shape.rows", rows, true);
            census.slice("retained_local_shape.selectors", selectors, true);
            // Exhaustive destructuring certifies these records have no nested
            // owners; adding a field requires revisiting this accounting.
            for row in rows.iter().flatten() {
                let dm_tree::owner_local_shape::LocalMember {
                    key: _, kind: _, previous: _,
                } = row;
            }
        }
    });
}
