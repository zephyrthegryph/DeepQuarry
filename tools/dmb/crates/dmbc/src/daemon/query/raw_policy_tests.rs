use super::*;
use serde_json::json;
fn fixture() -> (QueryReply, Vec<SourceQuery>, Value) {
    let root = std::env::current_dir().unwrap().join("raw-envelope");
    let config = root.join("lint_scopes.toml");
    let queries = vec![SourceQuery::NativeRawPolicyFixture {
        root: root.clone(),
        configuration: config.clone(),
        lints: vec!["scheduler".into()],
    }];
    let row = json!({"row":"source_native_raw_policy_fixture","schema":"dm-session-source-query-v1","source_revision":"s","policy_revision":"p","semantic_revision":"r","root":root,"configuration":config,"requested_lints":["scheduler"],"lint_whitelist":dq_analyze::captured_raw_policy::RAW_FILE_LINTS,"scope":"explicit_captured_files","full_policy_parity":false,"baseline_applied":false,"admission":"raw_findings","configuration_scope":"captured_configuration_bytes","fixture_limits":{"per_file_bytes":dq_analyze::captured_raw_policy::MAX_FIXTURE_FILE_BYTES,"total_bytes":dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES,"sites":dq_analyze::captured_raw_policy::MAX_FIXTURE_SITES,"contract":"fixture_admission_not_cpu_or_rss"},"results":[{"name":"scheduler","sites":[{"rule":"sleep","rel":"code/a.dm","line":2,"msg":"","key":"","ident":""}],"allow_used":[{"rel":"code/a.dm","line":3,"name":"scheduler","code":""}],"notes":[]}]});
    let reply = QueryReply {
        schema: "unused".into(),
        revision: "r".into(),
        complete: false,
        coverage: "partial".into(),
        query_count: 0,
        source_query_count: 1,
        source_revision: Some("s".into()),
        policy_revision: Some("p".into()),
        snapshot_outcome: "analyzed".into(),
        last_request_outcome: "analyzed".into(),
        publication_pair: None,
        jsonl: format!("{row}\n"),
    };
    (reply, queries, row)
}
#[test]
fn exact_raw_results_preserve_findings_allow_and_bounded_scope() {
    let (reply, queries, _) = fixture();
    validate_requested(&reply, &queries).unwrap();
}
#[test]
fn claims_foreign_pins_and_extra_fields_are_rejected() {
    for (key, value) in [
        ("policy_revision", json!("foreign")),
        ("full_policy_parity", json!(true)),
        ("baseline_applied", json!(true)),
        ("scope", json!("workspace")),
        ("extra", json!(1)),
    ] {
        let (mut reply, queries, mut row) = fixture();
        row[key] = value;
        reply.jsonl = format!("{row}\n");
        assert!(validate_requested(&reply, &queries).is_err(), "{key}");
    }
    let (mut reply, queries, _) = fixture();
    reply.policy_revision = None;
    assert!(validate_requested(&reply, &queries).is_err());
}
#[test]
fn malformed_sites_allow_rows_missing_results_and_extra_rows_are_rejected() {
    for fault in 0..5 {
        let (mut reply, queries, mut row) = fixture();
        match fault {
            0 => row["results"][0]["sites"][0]["line"] = json!(false),
            1 => row["results"][0]["sites"][0]["rule"] = json!("invented"),
            2 => row["results"][0]["allow_used"][0]["name"] = json!("foreign"),
            3 => row["results"] = json!([]),
            _ => row["results"][0]["notes"] = json!([1]),
        }
        reply.jsonl = format!("{row}\n");
        assert!(
            validate_requested(&reply, &queries).is_err(),
            "fault {fault}"
        );
    }
    let (mut reply, queries, row) = fixture();
    reply.jsonl = format!("{row}\n{row}\n");
    assert!(validate_requested(&reply, &queries).is_err());
    let (mut reply, queries, _) = fixture();
    reply.jsonl.clear();
    assert!(validate_requested(&reply, &queries).is_err());
}
