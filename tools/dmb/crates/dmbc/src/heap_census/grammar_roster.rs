//! Opt-in accounting of retained joined-grammar descriptors and observations.
use super::*;
use dm_session::ObservedArtifactStorageView as View;
use dm_tree::frontend::RetainedSemanticTree;

pub(super) fn inspect(census: &mut HeapCensus, state: &RetainedSemanticTree) {
    state.visit_grammar_storage(|view| match view {
        View::Store { buckets, entries } => {
            census.owner("retained_grammar.index").observed_items += entries as u64;
            if buckets != 0 {
                census.unknown("retained_grammar.index", "private observed-store BTree nodes and Arc control blocks are not exposed; accessible payload capacities counted separately");
            }
        }
        View::Bucket { address, len, capacity, element_size } => {
            census.buffer("retained_grammar.buckets", address, len.saturating_mul(element_size), capacity.saturating_mul(element_size));
        }
        View::Entry { key, reads, versions, value } => {
            census.slice("retained_grammar.keys", key, true);
            census.receipt("retained_grammar.reads", reads);
            census.slice("retained_grammar.versions", versions, true);
            if census.arc_object("retained_grammar.descriptors", value) {
                census.vec_payload("retained_grammar.descriptors", value.spans());
                census.vec_payload("retained_grammar.checkpoints", value.checkpoints());
            }
            for read in reads.iter() {
                if let Some(pieces) = read.answer.pieces() {
                    if census.slice("retained_grammar.pieces", pieces, true) {
                        for piece in pieces.iter() {
                            census.source_text("retained_grammar.output_text", piece);
                        }
                    }
                }
            }
        }
    });
}
