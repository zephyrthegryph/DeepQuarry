//! Exact exposed backing of the retained inheritance dependency graph.
use super::*;
use dm_tree::frontend::RetainedSemanticTree;

pub(super) fn inspect(census: &mut HeapCensus, state: &RetainedSemanticTree) {
    state.visit_metadata_dependency_edges(|edges| {
        if census.arc_object("retained_metadata_dependencies.edges", edges) {
            census.vec_payload("retained_metadata_dependencies.edges", edges.as_ref());
        }
    });
    state.visit_metadata_dependency_storage(|address, length, capacity| {
        census.buffer("retained_metadata_dependencies", address, length, capacity);
    });
}
