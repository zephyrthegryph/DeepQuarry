//! Request-local control unions borrow the existing primary query value. No
//! retained borrowed-event cache can survive primary eviction or source edits.
use super::*;
use dm_analysis::{check_policy::CheckerPolicy, checks_configured_control::Plan};
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn build(source: &'static str, db: &Arc<QueryDb>) -> dm_tree::frontend::ColdFrontend {
    dm_tree::frontend::build(
        std::path::Path::new("control.dme"),
        &Source(source),
        &Default::default(),
        1,
    )
    .unwrap()
    .with_body_queries(db.clone())
}
fn plan() -> Plan {
    Plan::new(
        &[
            "if_condition_determinate".into(),
            "control_condition_static".into(),
        ],
        &CheckerPolicy::default(),
    )
    .unwrap()
}
#[test]
fn exact_union_survives_primary_eviction_and_retracts_after_body_edit() {
    let db = Arc::new(QueryDb::default());
    let before = build("/proc/p(a)\n    if(1)\n        return\n", &db);
    let archive = before.body_archive().unwrap();
    let first = archive.parse(0).unwrap();
    let first_rows = plan().archived(&first).unwrap();
    assert_eq!(first_rows.len(), 2);
    // Keep the old owner live while evicting the DB value: subsequent projection
    // must borrow a freshly issued cached value, not stale pointers/selfrefs.
    db.db.evict_values(&[body_syntax::BODY_SYNTAX]);
    let after_eviction = archive.parse(0).unwrap();
    assert!(!std::ptr::eq(
        first.statement_body(),
        after_eviction.statement_body()
    ));
    let rebuilt = plan().archived(&after_eviction).unwrap();
    assert_eq!(
        rebuilt
            .iter()
            .map(|row| (&row.diagnostic.family, row.diagnostic.span, row.severity))
            .collect::<Vec<_>>(),
        first_rows
            .iter()
            .map(|row| (&row.diagnostic.family, row.diagnostic.span, row.severity))
            .collect::<Vec<_>>()
    );
    let edited = build("/proc/p(a)\n    if(a)\n        return\n", &db);
    assert_eq!(
        before.snapshot.tree.identity(),
        edited.snapshot.tree.identity()
    );
    let edited_archive = edited.body_archive().unwrap();
    let body = edited_archive.parse(0).unwrap();
    assert!(plan().archived(&body).unwrap().is_empty());
    // Historical captures remain valid explicit owners; no current result may
    // accidentally reuse their positive control facts after the source changes.
    assert_eq!(plan().archived(&first).unwrap().len(), 2);
}
