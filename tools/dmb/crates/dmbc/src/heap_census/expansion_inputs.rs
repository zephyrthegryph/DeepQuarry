//! Exact borrowed expansion-input backing, separate from process/private memory.
use super::*;
use dm_preprocess::regions::{ExpansionInputs, ExpansionStorageView};
pub(crate) fn inspect(inputs: &ExpansionInputs) -> HeapCensusReport {
    let mut census = HeapCensus::new("retained_expansion_inputs");
    census.expansion_inputs(inputs);
    census.finish()
}
impl HeapCensus {
    pub(crate) fn expansion_inputs(&mut self, inputs: &ExpansionInputs) {
        let owner = "retained_expansion_inputs";
        inputs.visit_storage(|view| match view {
            ExpansionStorageView::Buffer { address,payload_bytes,capacity_bytes } => {
                self.buffer("retained_expansion_inputs.buffers",address,payload_bytes,capacity_bytes);
            }
            ExpansionStorageView::Source(source) => self.source_text("retained_expansion_inputs.source",source),
            ExpansionStorageView::Text(text) => self.arc_text("retained_expansion_inputs.text",text),
            ExpansionStorageView::Macro(definition) => {
                let owner = "retained_expansion_inputs.macros";
                if self.arc_object(owner,definition) {
                    self.string(owner,&definition.replacement);
                    if let Some(parameters)=&definition.parameters { self.strings(owner,parameters); }
                }
            }
            ExpansionStorageView::Index { entries } => {
                self.owner(owner).observed_items+=entries as u64;
                if entries!=0 {
                    self.unknown(owner,"private BTree index nodes, Arc control blocks and allocator overhead excluded; exposed buffers are counted by allocation identity");
                }
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_preprocess::regions::{ExpansionMemo, ExpansionRecord};
    use std::{collections::BTreeMap, path::Path, sync::Mutex};
    #[derive(Default)]
    struct Memo {
        inputs: ExpansionInputs,
        records: Mutex<BTreeMap<u128, Vec<Arc<ExpansionRecord>>>>,
    }
    impl ExpansionMemo for Memo {
        fn input_admissions(&self) -> Option<&ExpansionInputs> {
            Some(&self.inputs)
        }
        fn candidates(&self, key: u128) -> Vec<Arc<ExpansionRecord>> {
            self.records
                .lock()
                .unwrap()
                .get(&key)
                .cloned()
                .unwrap_or_default()
        }
        fn insert(&self, record: Arc<ExpansionRecord>) {
            self.records
                .lock()
                .unwrap()
                .entry(record.key())
                .or_default()
                .push(record);
        }
    }
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("#define X(a) a + 4\n/proc/probe()\n    return X(3) + ABSENT + __LINE__\n".into())
        }
    }
    #[test]
    fn retained_inputs_census_deduplicates_shared_owners_and_reports_index_unknowns() {
        let memo = Memo::default();
        let plan = dm_preprocess::regions::plan_regions(
            Path::new("project.dme"),
            &Source,
            &BTreeMap::new(),
        );
        let output = dm_preprocess::regions::expand_regions_text_with_memo(&plan, 1, &memo);
        assert!(output.diagnostics.is_empty());
        let mut once = HeapCensus::new("once");
        once.expansion_inputs(&memo.inputs);
        let once = once.finish();
        let mut twice = HeapCensus::new("twice");
        twice.expansion_inputs(&memo.inputs);
        twice.expansion_inputs(&memo.inputs);
        let twice = twice.finish();
        assert!(once.unique_known_capacity_bytes > 0);
        assert_eq!(
            once.unique_known_capacity_bytes,
            twice.unique_known_capacity_bytes
        );
        let owner = twice
            .owners
            .iter()
            .find(|owner| owner.owner == "retained_expansion_inputs")
            .unwrap();
        assert!(twice.owners.iter().any(|owner| owner.shared_encounters > 0));
        assert!(owner
            .unknown
            .iter()
            .any(|reason| reason.contains("private BTree")));
    }
}
