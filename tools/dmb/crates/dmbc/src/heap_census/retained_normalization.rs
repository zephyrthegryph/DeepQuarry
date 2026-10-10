//! Diagnostic graph traversal of retained source-normalization artifacts.
use super::*;
use dm_tree::{
    declaration_contributions::TypeContribution,
    declaration_observations::{SourceAnswer, SourceDomain, SourceQuery},
    frontend::{NormalizationStorageView, RetainedSemanticTree},
};

fn contribution(census: &mut HeapCensus, value: &Arc<TypeContribution>) {
    let owner = "retained_normalization.contributions";
    if !census.arc_object(owner, value) {
        return;
    }
    census.slice("retained_normalization.shapes", value.shared_shape(), true);
    if census.slice(owner, value.shared_rows(), true) {
        for row in value.rows() {
            if let dm_tree::Skeleton::Member { metadata, .. } = &row.skeleton {
                if census.arc_object("semantic_metadata", metadata) {
                    census.declaration(metadata);
                }
            }
        }
    }
}
pub(super) fn answer(census: &mut HeapCensus, value: &SourceAnswer) {
    match value {
        SourceAnswer::OwnerShape(value) => {
            if let Some(shape) = value {
                census.slice("retained_normalization.shapes", shape, true);
            }
        }
        SourceAnswer::Owner(value) => {
            if let Some(owner) = &value.0 {
                contribution(census, owner);
            }
        }
        SourceAnswer::Family(value) => {
            let (owner, rows) = value.retained_parts();
            census.slice("retained_normalization.family_rows", rows, true);
            if let Some(owner) = owner {
                contribution(census, owner);
            }
        }
        SourceAnswer::OpaqueField(value) => {
            if let Some(dm_ir::OpaqueFieldBase {
                owner: _,
                name: _,
                declared_type,
            }) = value
            {
                match declared_type {
                    dm_ir::DeclaredTypeKnowledge::Known(_)
                    | dm_ir::DeclaredTypeKnowledge::KnownUntyped
                    | dm_ir::DeclaredTypeKnowledge::Unsupported => (),
                }
            }
        }
        SourceAnswer::SelectedPredecessor(_)
        | SourceAnswer::Parent(_)
        | SourceAnswer::CallableAnchor(_) => (),
    }
}
pub(super) fn inspect(census: &mut HeapCensus, state: &RetainedSemanticTree) {
    use dm_session::ObservedArtifactStorageView as View;
    state.visit_authored_storage(|view| match view {
        View::Store { buckets, entries } => {
            census.owner("retained_authored.index").observed_items += entries as u64;
            if buckets != 0 {
                census.unknown("retained_authored.index", "private observed-store BTree nodes, lease indexes and Arc control blocks excluded");
            }
        }
        View::Bucket { address, len, capacity, element_size } => {
            census.buffer("retained_authored.buckets", address, len.saturating_mul(element_size), capacity.saturating_mul(element_size));
        }
        View::Entry { key, reads, versions, value } => {
            census.slice("retained_authored.keys", key, true);
            census.slice("retained_authored.reads", reads, true);
            census.slice("retained_authored.versions", versions, true);
            contribution(census, value);
            for read in reads.iter() {
                if let Some(rows) = &read.answer {
                    if census.slice("retained_authored.answer_rows", rows, true) {
                        for row in rows.iter() {
                            if let dm_tree::Skeleton::Member { metadata, .. } = &row.skeleton {
                                if census.arc_object("semantic_metadata", metadata) {
                                    census.declaration(metadata);
                                }
                            }
                        }
                    }
                }
            }
        }
    });
    state.visit_normalization_storage(|view| match view {
        NormalizationStorageView::Store { buckets, entries } => {
            census.owner("retained_normalization.index").observed_items += entries as u64;
            if buckets != 0 { census.unknown("retained_normalization.index", "private ArtifactStore BTree nodes and Arc control blocks excluded; all exposed payload backing is counted"); }
        }
        NormalizationStorageView::Buffer { address, length, capacity } => {
            census.buffer("retained_normalization.buffers", address, length, capacity);
        }
        NormalizationStorageView::Entry { key, reads, versions, address, size } => {
            census.slice("retained_normalization.keys", key, true);
            census.slice("retained_normalization.reads", reads, true);
            census.slice("retained_normalization.versions", versions, true);
            census.buffer("retained_normalization.values", address, size, size);
            for read in reads.iter() {
                match read.query {
                    SourceQuery::Owner { owner: _ } | SourceQuery::OwnerShape { owner: _ } | SourceQuery::SelectedPredecessor { owner: _, name: _, kind: _ }
                    | SourceQuery::Parent { path: _ } | SourceQuery::Family { owner: _, name: _, kind: _ }
                    | SourceQuery::CallableAnchor { owner: _, name: _ } | SourceQuery::OpaqueField { owner: _, name: _ } => (),
                }
                match read.domain {
                    SourceDomain::ParentGraph | SourceDomain::AuthoredDeclarations
                    | SourceDomain::CallableNamespace | SourceDomain::EngineDeclarations => (),
                }
                answer(census, &read.answer);
            }
        }
        NormalizationStorageView::Member { metadata } => {
            if census.arc_object("semantic_metadata", metadata) { census.declaration(metadata); }
        }
    });
    if let Some(index) = state.retained_declaration_index() {
        census.slice(
            "retained_normalization.current_roster",
            index.shared_roster(),
            true,
        );
        for (_, owner) in index.owners() {
            contribution(census, owner);
        }
        if !index.is_empty() {
            census.unknown("retained_normalization.current_index", "private keyed-declaration BTree node backing excluded; owner values and roster counted");
        }
    }
}
