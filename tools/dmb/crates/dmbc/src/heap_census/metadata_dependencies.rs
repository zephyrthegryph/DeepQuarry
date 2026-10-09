//! Exact exposed backing of the retained inheritance dependency graph.
use super::*;
use dm_tree::frontend::RetainedSemanticTree;

pub(super) fn inspect(census: &mut HeapCensus, state: &RetainedSemanticTree) {
    state.visit_metadata_dependency_storage(|address, length, capacity| {
        census.buffer("retained_metadata_dependencies", address, length, capacity);
    });
}
