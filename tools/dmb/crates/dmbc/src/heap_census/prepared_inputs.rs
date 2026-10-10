//! Opt-in retained lexical owners. Private preparation/index nodes stay explicit.
use super::*;
use dm_session::ArtifactStorageView as View;

pub(crate) fn inspect(store: &crate::input_snapshot::PreparedInputArtifacts) -> HeapCensusReport {
    let mut census = HeapCensus::new("retained_prepared_inputs");
    store.visit_storage(|view| match view {
        View::Store { buckets, entries } => {
            census.owner("prepared_inputs.index").observed_items += entries as u64;
            if buckets != 0 {
                census.unknown("prepared_inputs.index", "private ArtifactStore BTree nodes and Arc control blocks excluded");
            }
        }
        View::Bucket { address, len, capacity, element_size } => {
            census.buffer("prepared_inputs.buckets",address,len.saturating_mul(element_size),capacity.saturating_mul(element_size));
        }
        View::Entry { key, reads, versions, value } => {
            census.slice("prepared_inputs.key",key,true);
            census.slice("prepared_inputs.reads",reads,true);
            census.slice("prepared_inputs.versions",versions,true);
            if census.arc_object("prepared_inputs.payload",value) {
                let source=value.source();
                if census.arc_object("prepared_inputs.source",source) {
                    census.source_text("prepared_inputs.text",source.original());
                    census.slice("prepared_inputs.line_starts",source.line_starts(),true);
                    for line in source.lines() {
                        census.source_text("prepared_inputs.logical_text",line.text);
                    }
                    census.unknown("prepared_inputs.source", "private compact/wide PreparedLine descriptors and directive syntax/index backing excluded; text owners and line-start backing counted exactly");
                }
                let proof=value.inputs();
                census.owner("prepared_inputs.proof").observed_items+=proof.files().count() as u64;
                for file in proof.files() { census.path("prepared_inputs.proof_paths", &file.path); }
                census.unknown("prepared_inputs.proof", "private one-file InputSnapshot BTree node allocation excluded; path payload counted exactly");
            }
        }
    });
    census.finish()
}
