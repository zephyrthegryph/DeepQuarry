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
            census.slice("retained_grammar.reads", reads, true);
            census.slice("retained_grammar.versions", versions, true);
            if census.arc_object("retained_grammar.descriptors", value) {
                census.vec_payload("retained_grammar.descriptors", value.spans());
            }
            for read in reads.iter() {
                if let Some(records) = read.answer.records() {
                    if census.slice("retained_grammar.records", records, true) {
                        for record in records.iter() {
                            if census.arc_object("retained_grammar.expansions", record) {
                                let text = record.text();
                                census.buffer("retained_grammar.expansion_text", text.as_ptr() as usize, text.len(), text.len());
                                census.unknown("retained_grammar.expansions", "ExpansionRecord exposes exact Arc text but private source/control/read/location/trace/diagnostic/parser-fragment backing capacities are not exposed; these nested owners excluded");
                            }
                        }
                    }
                }
            }
        }
    });
}
