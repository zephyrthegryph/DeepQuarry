use super::*;
use crate::daemon::query::{evaluate_snapshot, QueryRequest, SourceQuery};
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn build(text: &'static str) -> ColdFrontend {
    dm_tree::frontend::build_with_config(
        std::path::Path::new("fixture.dme"),
        &Source(text),
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
    )
    .unwrap()
}
#[test]
fn body_context_pages_share_current_owner_and_reject_semantic_stable_source_edits() {
    let original = build("/proc/read()\n    set waitfor = 0\n    return 1\n");
    let shifted =
        build("// current source shift\n/proc/read()\n    set waitfor = 0\n    return 2\n");
    assert_eq!(
        original.snapshot.tree.identity(),
        shifted.snapshot.tree.identity()
    );
    let snapshot = SourceSnapshot::capture(&original);
    assert!(snapshot
        .source_mapping
        .as_ref()
        .unwrap()
        .locations_if_issued()
        .is_none());
    assert!(Arc::ptr_eq(
        snapshot.bodies.as_ref().unwrap(),
        &original.bodies
    ));
    let state = Arc::new(Mutex::new(QueryState::default()));
    let mut attempt = QueryAttempt::new(Arc::clone(&state), true);
    attempt.capture(&original);
    attempt.finish_analyzed();
    drop(attempt);
    let mut request = QueryRequest {
        timeout_seconds: None,
        project: "fixture.dme".into(),
        defines: Default::default(),
        engine_template: None,
        bootstrap_catalog: false,
        expected_revision: Some(format!("{:032x}", original.snapshot.tree.identity())),
        expected_source_revision: Some(format!("{:032x}", snapshot.source_revision)),
        queries: vec![],
        source_queries: vec![SourceQuery::BodyContextsPage { start: 0, limit: 1 }],
    };
    let first =
        evaluate_snapshot(&request, &original.snapshot.tree, &state.lock().unwrap()).unwrap();
    let old: serde_json::Value = serde_json::from_str(first.jsonl.trim()).unwrap();
    assert_eq!(old["items"][0]["row"], "body");
    assert_eq!(old["items"][0]["executable_facts_included"], false);
    let mut attempt = QueryAttempt::new(Arc::clone(&state), true);
    attempt.capture(&shifted);
    attempt.finish_analyzed();
    drop(attempt);
    assert!(evaluate_snapshot(&request, &shifted.snapshot.tree, &state.lock().unwrap()).is_err());
    request.expected_source_revision = Some(format!(
        "{:032x}",
        dm_analysis::tree_export::source_revision(&shifted)
    ));
    let reply =
        evaluate_snapshot(&request, &shifted.snapshot.tree, &state.lock().unwrap()).unwrap();
    let current: serde_json::Value = serde_json::from_str(reply.jsonl.trim()).unwrap();
    assert_ne!(old["items"][0]["source"], current["items"][0]["source"]);
    let expected =
        dm_analysis::tree_export::source_body_row(&shifted.snapshot.tree, &shifted.bodies[0])
            .unwrap();
    for (field, value) in expected.as_object().unwrap() {
        assert_eq!(&current["items"][0][field], value);
    }
    let mut replaced = build("/proc/read()\n    return 1\n");
    replaced.bodies = Arc::from(replaced.bodies.to_vec());
    let forged = SourceSnapshot::capture(&replaced);
    assert!(forged.bodies.is_none());
    assert!(forged
        .write_body_contexts_page(0, 1, &replaced.snapshot.tree, &mut Vec::new())
        .is_err());
}
