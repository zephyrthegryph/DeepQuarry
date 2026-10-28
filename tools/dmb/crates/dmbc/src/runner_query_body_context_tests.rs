#[path = "../../dm-analysis/examples/support/reference_hierarchy.rs"]
mod reference_hierarchy;

fn seeded_source<P: dm_preprocess::SourceProvider>(
    project: &std::path::Path,
    provider: &P,
    defines: &std::collections::BTreeMap<String, String>,
    workers: usize,
) -> Result<dm_tree::frontend::ColdFrontend, Vec<dm_tree::frontend::Diagnostic>> {
    dm_tree::frontend::build_with_config(
        project,
        provider,
        defines,
        dm_tree::frontend::FrontendConfig {
            workers,
            engine: Some(&reference_hierarchy::seed()),
            observer: None,
        },
    )
}
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
            engine: Some(&reference_hierarchy::seed()),
            observer: None,
        },
    )
    .unwrap()
}

#[test]
fn native_checker_question_executes_in_process_with_explicit_partial_coverage() {
    let db = Arc::new(crate::query_db::QueryDb::default());
    let frontend = build("/proc/example(x)\n    return !x & 1\n").with_body_queries(db.clone());
    let snapshot = SourceSnapshot::capture(&frontend);
    let mut bytes = Vec::new();
    snapshot
        .write_native_checker(0, "disabled", &frontend.snapshot.tree, &mut bytes)
        .unwrap();
    let disabled: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(disabled["diagnostics"].as_array().unwrap().len(), 0);
    assert_eq!(
        db.db().stats(dm_query::Kind(4)).computed,
        0,
        "disabled policy must not parse"
    );
    bytes.clear();
    snapshot
        .write_native_checker(0, "error", &frontend.snapshot.tree, &mut bytes)
        .unwrap();
    let findings: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(findings["full_checker_parity"], false);
    assert_eq!(findings["diagnostics"].as_array().unwrap().len(), 1);
    assert_eq!(findings["diagnostics"][0]["severity"], "error");
    assert_eq!(findings["diagnostics"][0]["line"], 2);
    assert_eq!(db.db().stats(dm_query::Kind(4)).computed, 1);
    assert!(snapshot
        .write_native_checker(0, "typo", &frontend.snapshot.tree, &mut Vec::new())
        .is_err());
    let shifted = build("// shifted\n/proc/example(x)\n    return x\n");
    assert!(snapshot
        .write_native_checker(0, "warning", &shifted.snapshot.tree, &mut Vec::new())
        .is_err());
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

#[test]
fn lazy_body_model_matches_full_current_parser_after_frontend_release() {
    let frontend = build("/proc/read(value)\n    var/local = value + 1\n    return local\n/proc/unrelated()\n    return 9\n");
    let archive = frontend.body_archive().unwrap();
    archive.visit_storage(|source, syntax, bodies| {
        assert!(source.same_view(&frontend.expanded.text));
        assert!(Arc::ptr_eq(syntax, &frontend.syntax));
        assert!(Arc::ptr_eq(bodies, &frontend.bodies));
    });
    let arena = dm_tree::frontend::BodyArena::new_typed(&frontend, |_| true);
    let ordinary = arena.take_parsed(&frontend.bodies[0]).unwrap();
    let mut expected_typed = Vec::new();
    dm_analysis::typed_body_jsonl::write_jsonl(&ordinary, &mut expected_typed).unwrap();
    let lexical = dm_analysis::typed_body::lexical::analyze(&frontend, &ordinary, None).unwrap();
    let mut expected_lexical = Vec::new();
    dm_analysis::typed_body::lexical::jsonl::write_jsonl(&lexical, &mut expected_lexical).unwrap();
    drop(lexical);
    drop(ordinary);
    drop(arena);
    let source_revision = dm_analysis::tree_export::source_revision(&frontend);
    let tree = Arc::clone(&frontend.snapshot.tree);
    let state = Arc::new(Mutex::new(QueryState::default()));
    let mut attempt = QueryAttempt::new(Arc::clone(&state), true);
    attempt.capture(&frontend);
    attempt.finish_analyzed();
    drop(attempt);
    drop(frontend);
    assert_eq!(archive.len(), 2);
    let mut request = QueryRequest {
        timeout_seconds: None,
        project: "fixture.dme".into(),
        defines: Default::default(),
        engine_template: None,
        bootstrap_catalog: false,
        expected_revision: Some(format!("{:032x}", tree.identity())),
        expected_source_revision: Some(format!("{:032x}", source_revision)),
        queries: vec![],
        source_queries: vec![SourceQuery::BodyModel { ordinal: 0 }],
    };
    request.validate().unwrap();
    let answer = evaluate_snapshot(&request, &tree, &state.lock().unwrap()).unwrap();
    let row: serde_json::Value = serde_json::from_str(answer.jsonl.trim()).unwrap();
    assert_eq!(
        row["typed_jsonl"].as_str().unwrap().as_bytes(),
        expected_typed
    );
    assert_eq!(
        row["lexical_jsonl"].as_str().unwrap().as_bytes(),
        expected_lexical
    );
    assert_eq!(row["semantic_resolution_complete"], false);
    state
        .lock()
        .unwrap()
        .snapshot
        .as_mut()
        .unwrap()
        .release_body_queries();
    assert!(evaluate_snapshot(&request, &tree, &state.lock().unwrap()).is_err());
    request.source_queries = vec![SourceQuery::BodyContextsPage { start: 0, limit: 1 }];
    assert!(evaluate_snapshot(&request, &tree, &state.lock().unwrap()).is_ok());
    request.source_queries = vec![SourceQuery::BodyModel { ordinal: 0 }];
    request.expected_source_revision = None;
    assert!(request.validate().is_err());
    request.expected_source_revision = Some(format!("{:032x}", source_revision));
    request.source_queries = vec![SourceQuery::BodyModel { ordinal: 2 }];
    assert!(evaluate_snapshot(&request, &tree, &state.lock().unwrap()).is_err());
    let replacement = build(
        "// shifted\n/proc/read(value)\n    return value + 2\n/proc/unrelated()\n    return 9\n",
    );
    let mut attempt = QueryAttempt::new(Arc::clone(&state), true);
    attempt.capture(&replacement);
    attempt.finish_analyzed();
    drop(attempt);
    request.source_queries = vec![SourceQuery::BodyModel { ordinal: 0 }];
    assert!(
        evaluate_snapshot(&request, &replacement.snapshot.tree, &state.lock().unwrap()).is_err()
    );
}

#[test]
fn native_untyped_query_uses_retained_sources_and_same_syntax_graph() {
    let db = Arc::new(crate::query_db::QueryDb::default());
    let (mut snapshot, tree) = {
        let frontend = seeded_source(
            std::path::Path::new("code/probe.dm"),
            &Source(
                "/datum/probe\n    var/saved\n    proc/use(datum/value)\n        saved = value\n",
            ),
            &Default::default(),
            1,
        )
        .unwrap()
        .with_body_queries(db.clone());
        let archive = frontend.body_archive().unwrap();
        archive.parse(0).unwrap();
        (
            SourceSnapshot::capture(&frontend),
            Arc::clone(&frontend.snapshot.tree),
        )
    };
    snapshot.native_value_queries = Some(db.clone());
    let mut bytes = Vec::new();
    snapshot
        .write_native_untyped_fixture(std::path::Path::new("."), &tree, &mut bytes)
        .unwrap();
    let response: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(response["findings"].as_array().unwrap().len(), 1);
    assert_eq!(response["findings"][0]["identity"], "/datum/probe::saved");
    assert_eq!(response["findings"][0]["line"], 2);
    assert_eq!(response["findings"][0]["rule"], "typed");
    assert_eq!(response["full_policy_parity"], false);
    assert_eq!(response["raw_marker_scope"], "captured_compiled_sources");
    assert_eq!(db.db().stats(dm_query::Kind(4)).computed, 1);
    let foreign = build("/datum/other\n    var/different\n");
    assert!(snapshot
        .write_native_untyped_fixture(
            std::path::Path::new("."),
            &foreign.snapshot.tree,
            &mut Vec::new()
        )
        .is_err());
}
