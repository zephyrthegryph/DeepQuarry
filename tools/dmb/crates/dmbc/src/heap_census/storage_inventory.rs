//! Exact exposed retained storage-fact owners; private index bytes stay unknown.
use super::*;
use dm_session::ObservedArtifactStorageView as View;
use dm_tree::{frontend::RetainedSemanticTree, StorageAnswer, StorageInput, StorageOwner};

fn answer(census: &mut HeapCensus, value: &StorageAnswer) {
    match value {
        StorageAnswer::Unique(_) => (),
        StorageAnswer::Owner(Some(rows)) => {
            census.slice("retained_storage.inputs", rows, true);
            for row in rows.iter() {
                let StorageInput {
                    key: _,
                    definition: _,
                    flags: _,
                    opaque,
                    previous: _,
                } = row;
                if let Some(dm_ir::OpaqueFieldBase {
                    owner: _,
                    name: _,
                    declared_type,
                }) = opaque
                {
                    match declared_type {
                        dm_ir::DeclaredTypeKnowledge::Known(_)
                        | dm_ir::DeclaredTypeKnowledge::KnownUntyped
                        | dm_ir::DeclaredTypeKnowledge::Unsupported => (),
                    }
                }
            }
        }
        StorageAnswer::Predecessor(Some(fact)) => {
            let dm_tree::StorageFact {
                name: _,
                slot: _,
                instance: _,
            } = fact;
        }
        StorageAnswer::Intrinsic(Some(member)) => {
            let dm_tree::IntrinsicMember {
                owner: _,
                name: _,
                kind: _,
                shared_owner: _,
                instance_storage_proven: _,
            } = member;
        }
        StorageAnswer::Owner(None)
        | StorageAnswer::Predecessor(None)
        | StorageAnswer::Intrinsic(None) => (),
    }
}
pub(super) fn inspect(census: &mut HeapCensus, state: &RetainedSemanticTree) {
    state.visit_storage_owner_storage(|view| match view {
        View::Store { buckets, entries } => {
            census.owner("retained_storage.index").observed_items += entries as u64;
            if buckets != 0 { census.unknown("retained_storage.index", "private ArtifactStore BTree nodes and Arc control blocks excluded; exposed immutable payload capacities counted"); }
        }
        View::Bucket { address, len, capacity, element_size } => {
            census.buffer("retained_storage.buckets", address, len.saturating_mul(element_size), capacity.saturating_mul(element_size));
        }
        View::Entry { key, reads, versions, value } => {
            census.slice("retained_storage.keys", key, true);
            census.receipt("retained_storage.reads", reads);
            census.slice("retained_storage.versions", versions, true);
            if census.arc_object("retained_storage.values", value) {
                let StorageOwner { facts, unique_token: _ } = value.as_ref();
                census.slice("retained_storage.facts", facts, true);
            }
            for read in reads.iter() { answer(census, &read.answer); }
        }
    });
}
