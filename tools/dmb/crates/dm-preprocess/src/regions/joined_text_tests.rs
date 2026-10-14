use super::super::{
    expand_regions_text, expand_regions_text_with_memo, plan_regions, ExpansionInputs,
    ExpansionMemo, ExpansionRecord,
};
use super::*;
use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
    sync::Mutex,
};
struct Source(BTreeMap<PathBuf, String>);
impl crate::SourceProvider for Source {
    fn read(&self, path: &Path) -> Result<String, String> {
        self.0
            .get(path)
            .cloned()
            .ok_or_else(|| "missing source".into())
    }
}
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
fn plan(files: &[(&str, &str)]) -> DirectivePlan {
    plan_regions(
        Path::new("project.dme"),
        &Source(
            files
                .iter()
                .map(|(path, text)| (PathBuf::from(path), text.to_string()))
                .collect(),
        ),
        &BTreeMap::new(),
    )
}
#[test]
fn joined_owner_reuses_only_exact_current_emission_and_rebinds_origins() {
    let original = plan(&[("project.dme", "/proc/probe()\n    return 7\n")]);
    let memo = Memo::default();
    let first = expand_regions_text_with_memo(&original, 1, &memo);
    let second = expand_regions_text_with_memo(&original, 1, &memo);
    assert!(first.text.same_view(&second.text));
    let mut shifted = original.clone();
    for region in &mut shifted.regions {
        for segment in &mut region.segments {
            for line in &mut segment.lines {
                line.source_line += 20;
            }
        }
    }
    let rebound = expand_regions_text_with_memo(&shifted, 1, &memo);
    assert!(first.text.same_view(&rebound.text));
    assert_eq!(
        rebound.origins.get(0).unwrap().origin.source_line,
        first.origins.get(0).unwrap().origin.source_line + 20
    );
    let changed = plan(&[("project.dme", "/proc/probe()\n    return 9\n")]);
    let edited = expand_regions_text_with_memo(&changed, 1, &memo);
    assert!(!first.text.same_view(&edited.text));
    assert_eq!(edited.text, expand_regions_text(&changed, 1).text);
}
#[test]
fn piece_order_and_empty_emission_preserve_fresh_join_semantics() {
    let files = [
        (
            "project.dme",
            "#include \"first.dm\"\n#include \"empty.dm\"\n#include \"second.dm\"\n",
        ),
        ("first.dm", "/proc/first()\n    return 1\n"),
        ("empty.dm", ""),
        ("second.dm", "/proc/second()\n    return 2\n"),
    ];
    let first = plan(&files);
    let memo = Memo::default();
    let before = expand_regions_text_with_memo(&first, 1, &memo);
    let mut reversed = files;
    reversed[0].1 = "#include \"second.dm\"\n#include \"empty.dm\"\n#include \"first.dm\"\n";
    let after_plan = plan(&reversed);
    let after = expand_regions_text_with_memo(&after_plan, 1, &memo);
    assert!(!before.text.same_view(&after.text));
    assert_eq!(after.text, expand_regions_text(&after_plan, 1).text);
    let empty = plan(&[("project.dme", "")]);
    let empty_first = expand_regions_text_with_memo(&empty, 1, &memo);
    let empty_second = expand_regions_text_with_memo(&empty, 1, &memo);
    assert_eq!(empty_first.text.as_str(), "");
    assert!(empty_first.text.same_view(&empty_second.text));
}
