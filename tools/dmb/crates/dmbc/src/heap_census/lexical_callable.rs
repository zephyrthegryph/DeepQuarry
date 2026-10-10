//! Borrowed diagnostic accounting for lexical paths and callable anchors.
use super::*;
use dm_session::ObservedArtifactStorageView as View;
use dm_tree::frontend::RetainedSemanticTree;

fn index(census: &mut HeapCensus, owner: &str, buckets: usize, entries: usize) {
    census.owner(owner).observed_items += entries as u64;
    if buckets != 0 {
        census.unknown(owner, "private ArtifactStore BTree nodes and Arc control blocks excluded; exposed payload capacities counted");
    }
}
pub(super) fn inspect(census: &mut HeapCensus, state: &RetainedSemanticTree) {
    state.visit_type_path_storage(|view| match view {
        View::Store { buckets, entries } => {
            index(census, "retained_type_paths.index", buckets, entries)
        }
        View::Bucket {
            address,
            len,
            capacity,
            element_size,
        } => {
            census.buffer(
                "retained_type_paths.buckets",
                address,
                len.saturating_mul(element_size),
                capacity.saturating_mul(element_size),
            );
        }
        View::Entry {
            key,
            reads,
            versions,
            value,
        } => {
            census.slice("retained_type_paths.keys", key, true);
            census.receipt("retained_type_paths.reads", reads);
            census.slice("retained_type_paths.versions", versions, true);
            if census.arc_object("retained_type_paths.values", value) {
                let dm_tree::type_paths::LexicalPath { parent } = value.as_ref();
                if let Some(parent) = parent {
                    census.arc_text("retained_type_paths.parents", parent);
                }
            }
            for read in reads.iter() {
                if let Some(answer) = &read.answer {
                    census.string("retained_type_paths.answers", answer);
                }
            }
        }
    });
    state.visit_callable_owner_storage(|view| match view {
        View::Store { buckets, entries } => {
            index(census, "retained_callable.index", buckets, entries)
        }
        View::Bucket {
            address,
            len,
            capacity,
            element_size,
        } => {
            census.buffer(
                "retained_callable.buckets",
                address,
                len.saturating_mul(element_size),
                capacity.saturating_mul(element_size),
            );
        }
        View::Entry {
            key,
            reads,
            versions,
            value,
        } => {
            census.slice("retained_callable.keys", key, true);
            census.receipt("retained_callable.reads", reads);
            census.slice("retained_callable.versions", versions, true);
            if census.arc_object("retained_callable.values", value) {
                let dm_tree::owner_callable::CallableOwner {
                    anchors,
                    duplicate: _,
                } = value.as_ref();
                census.slice("retained_callable.anchors", anchors, true);
            }
            for read in reads.iter() {
                super::retained_normalization::answer(census, &read.answer);
            }
        }
    });
}
