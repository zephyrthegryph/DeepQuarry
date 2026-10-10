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
                census.vec_payload("retained_grammar.checkpoints", value.checkpoints());
            }
            for read in reads.iter() {
                if let Some(records) = read.answer.records() {
                    if census.slice("retained_grammar.records", records, true) {
                        for record in records.iter() {
                            if census.arc_object("retained_grammar.expansions", record) {
                                record.visit_storage(|storage| match storage {
                                    dm_preprocess::regions::ExpansionStorageView::Buffer { address, payload_bytes, capacity_bytes } => {
                                        census.buffer("retained_grammar.expansion_buffers", address, payload_bytes, capacity_bytes);
                                    }
                                    dm_preprocess::regions::ExpansionStorageView::Source(source) => census.source_text("retained_grammar.expansion_source", source),
                                    dm_preprocess::regions::ExpansionStorageView::Text(text) => census.arc_text("retained_grammar.expansion_text", text),
                                    dm_preprocess::regions::ExpansionStorageView::Macro(definition) => {
                                        let owner = "retained_grammar.expansion_macros";
                                        if census.arc_object(owner, definition) {
                                            census.string(owner, &definition.replacement);
                                            if let Some(parameters) = &definition.parameters { census.strings(owner, parameters); }
                                        }
                                    }
                                    dm_preprocess::regions::ExpansionStorageView::Index { entries } => {
                                        census.owner("retained_grammar.expansion_index").observed_items += entries as u64;
                                        if entries != 0 { census.unknown("retained_grammar.expansion_index", "private index nodes excluded; accessible buffers counted separately"); }
                                    }
                                });
                                census.unknown("retained_grammar.expansions", "Arc control blocks and allocator overhead excluded; all accessible record payload owners visited");
                            }
                        }
                    }
                }
            }
        }
    });
}
