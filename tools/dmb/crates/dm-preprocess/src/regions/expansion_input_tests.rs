use super::*;
use crate::regions::{
    expand_regions_text, expand_regions_text_with_memo, plan_regions, ExpansionMemo,
};
use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicUsize, Ordering},
        Mutex,
    },
};
struct Source(String);
impl crate::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.clone())
    }
}
#[derive(Default)]
struct Memo {
    inputs: ExpansionInputs,
    records: Mutex<BTreeMap<u128, Vec<Arc<ExpansionRecord>>>>,
    ordinary_visits: AtomicUsize,
}
impl ExpansionMemo for Memo {
    fn input_admissions(&self) -> Option<&ExpansionInputs> {
        Some(&self.inputs)
    }
    fn candidates(&self, key: u128) -> Vec<Arc<ExpansionRecord>> {
        self.ordinary_visits.fetch_add(1, Ordering::Relaxed);
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
fn plan(source: &str, defines: &[(&str, &str)]) -> DirectivePlan {
    plan_regions(
        Path::new("project.dme"),
        &Source(source.into()),
        &defines
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect(),
    )
}
#[test]
fn issued_inputs_skip_control_reencoding_but_replay_positive_negative_reads() {
    let source = "/proc/probe()\n    return USED + ABSENT\n";
    let memo = Memo::default();
    let first = plan(source, &[("USED", "7")]);
    let fresh = expand_regions_text_with_memo(&first, 1, &memo);
    let visits = memo.ordinary_visits.load(Ordering::Relaxed);
    // A fresh source allocation with equal contents must pass exact equality,
    // not inherit authority merely from a hash or prior owner address.
    let same = plan(source, &[("USED", "7"), ("UNUSED", "9")]);
    let hit = expand_regions_text_with_memo(&same, 1, &memo);
    assert_eq!(memo.ordinary_visits.load(Ordering::Relaxed), visits);
    assert!(Arc::ptr_eq(
        fresh.receipts[0].record(),
        hit.receipts[0].record()
    ));
    for defines in [vec![("USED", "8")], vec![("USED", "7"), ("ABSENT", "4")]] {
        let changed = plan(source, &defines);
        assert!(memo.inputs.lookup(&changed, 0).is_none());
        let actual = expand_regions_text_with_memo(&changed, 1, &memo);
        let expected = expand_regions_text(&changed, 1);
        assert_eq!(actual.text, expected.text);
        assert_eq!(actual.diagnostics, expected.diagnostics);
    }
}
#[test]
fn current_locations_and_prepared_control_shape_cannot_inherit_admission() {
    let source = "/proc/probe()\n    return __LINE__ + USED\n";
    let memo = Memo::default();
    let original = plan(source, &[("USED", "3")]);
    expand_regions_text_with_memo(&original, 1, &memo);
    let mut shifted = original.clone();
    shifted.regions[0].segments[0].lines[1].source_line += 10;
    assert!(memo.inputs.lookup(&shifted, 0).is_none());
    let mut renamed = original.clone();
    // __FILE__ is not observed, so a semantic spelling change alone is harmless.
    renamed.occurrences[0].semantic_path = Arc::from("other.dme");
    assert!(memo.inputs.lookup(&renamed, 0).is_some());
    let mut masked = original.clone();
    masked.regions[0].segments[0].lines[1].text = "    return 99\n".into();
    assert!(memo.inputs.lookup(&masked, 0).is_none());
    let mut segmented = original.clone();
    segmented.regions[0]
        .segments
        .push(crate::regions::ExpansionSegment {
            lines: Vec::new(),
            macros: Default::default(),
        });
    assert!(memo.inputs.lookup(&segmented, 0).is_none());
}
#[test]
fn source_collision_and_removed_current_roster_decline_old_receipts() {
    let memo = Memo::default();
    let original = plan("/proc/probe()\n    return 7\n", &[]);
    let output = expand_regions_text_with_memo(&original, 1, &memo);
    let changed = plan("/proc/probe()\n    return 9\n", &[]);
    let receipt =
        ExpansionInputReceipt::capture(&original, 0, Arc::clone(output.receipts[0].record()))
            .unwrap()
            .0;
    assert!(!receipt.admits(&changed, 0));
    memo.inputs.retain_current(&changed);
    assert!(memo.inputs.lookup(&original, 0).is_none());
    // Access spelling is ordinary current plan authority, not an admission key.
    assert_eq!(
        original.occurrences[0].path.as_ref(),
        &PathBuf::from("project.dme")
    );
}
