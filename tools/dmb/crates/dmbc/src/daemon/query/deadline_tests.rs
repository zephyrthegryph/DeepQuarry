use super::*;

#[test]
fn legacy_query_budget_and_explicit_demand_limit() {
    let json = r#"{"project":"probe.dme","defines":{},"engine_template":null,"bootstrap_catalog":false,"expected_revision":null,"queries":[]}"#;
    let mut request: QueryRequest = serde_json::from_str(json).unwrap();
    assert_eq!(request.timeout().unwrap().as_secs(), 20);
    request.timeout_seconds = Some(300);
    assert_eq!(request.timeout().unwrap().as_secs(), 300);
    request.validate().unwrap();
    for invalid in [0, 301, u16::MAX] {
        request.timeout_seconds = Some(invalid);
        assert_eq!(
            request.validate().unwrap_err().kind(),
            io::ErrorKind::InvalidInput
        );
    }
}

#[test]
fn cancelled_current_body_query_preserves_pinned_snapshot_for_retry() {
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok("/proc/read()\n    return 7\n".into())
        }
    }
    let frontend = dm_tree::frontend::build(
        std::path::Path::new("probe.dme"),
        &Source,
        &Default::default(),
        1,
    )
    .unwrap();
    let state = std::sync::Arc::new(std::sync::Mutex::new(
        crate::runner_host::query_snapshot::QueryState::default(),
    ));
    let mut capture =
        crate::runner_host::query_snapshot::QueryAttempt::new(std::sync::Arc::clone(&state), true);
    capture.capture(&frontend);
    capture.finish_analyzed();
    drop(capture);
    let request = QueryRequest {
        timeout_seconds: Some(20),
        project: "probe.dme".into(),
        defines: Default::default(),
        engine_template: None,
        bootstrap_catalog: false,
        expected_revision: Some(format!("{:032x}", frontend.snapshot.tree.identity())),
        expected_source_revision: Some(format!(
            "{:032x}",
            dm_analysis::tree_export::source_revision(&frontend)
        )),
        queries: vec![],
        source_queries: vec![SourceQuery::BodyModel { ordinal: 0 }],
    };
    let token = crate::daemon::control::Cancellation::default();
    token.cancel();
    let binding = crate::daemon::control::bind(token);
    assert_eq!(
        evaluate_snapshot(&request, &frontend.snapshot.tree, &state.lock().unwrap())
            .unwrap_err()
            .kind(),
        io::ErrorKind::Interrupted
    );
    drop(binding);
    let answer =
        evaluate_snapshot(&request, &frontend.snapshot.tree, &state.lock().unwrap()).unwrap();
    assert!(answer.jsonl.contains("source_body_model"));
    assert_eq!(state.lock().unwrap().last_request_outcome, "analyzed");
    let mut stale = request.clone();
    stale.expected_source_revision = Some("00000000000000000000000000000000".into());
    assert_eq!(
        evaluate_snapshot(&stale, &frontend.snapshot.tree, &state.lock().unwrap())
            .unwrap_err()
            .kind(),
        io::ErrorKind::InvalidInput
    );
}
