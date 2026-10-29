use super::*;
use serde_json::json;
fn fixture() -> (QueryReply, Vec<SourceQuery>, Value) {
    let root = std::env::current_dir().unwrap();
    let config = root.join("tools/ci/lint_scopes.toml");
    let questions = vec![SourceQuery::NativeWorkspaceRawPolicy {
        root: root.clone(),
        configuration: config.clone(),
        lints: vec!["scheduler".into()],
        cursor: None,
        limit: 128,
    }];
    let row = json!({"row":"source_native_workspace_raw_policy","schema":"dm-session-source-query-v1","source_revision":"s","policy_revision":"p","semantic_revision":"r","snapshot_as_of":"policy_revision","root":root,"configuration":config,"recursive_roots":[root.join("code")],"requested_lints":["scheduler"],"lint_whitelist":dq_analyze::captured_raw_policy::RAW_FILE_LINTS,"scope":"typed_discovery_raw_files","full_policy_parity":false,"baseline_applied":false,"admission":"raw_findings","configuration_scope":"proven_missing_configuration","aggregate_id":"11111111111111111111111111111111","offset":0,"count":1,"total_items":1,"next_cursor":null,"items":[{"lint":"scheduler","kind":"site","site":{"rule":"sleep","rel":"code/a.dm","line":2,"msg":"message","key":"","ident":""}}]});
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
    (reply, questions, row)
}
#[test]
fn exact_workspace_pages_are_snapshot_as_of_not_live_disk_or_full_semantic_parity() {
    let (reply, questions, _) = fixture();
    validate_requested(&reply, &questions).unwrap();
}
#[test]
fn stale_foreign_extra_and_nonprogress_pages_are_refused() {
    for (key, value) in [
        ("policy_revision", json!("foreign")),
        ("snapshot_as_of", json!("live_disk")),
        ("offset", json!(1)),
        ("count", json!(0)),
        ("total_items", json!(0)),
        ("full_policy_parity", json!(true)),
        ("extra", json!(1)),
    ] {
        let (mut reply, questions, mut row) = fixture();
        row[key] = value;
        reply.jsonl = format!("{row}\n");
        assert!(validate_requested(&reply, &questions).is_err(), "{key}");
    }
    let (mut reply, questions, row) = fixture();
    reply.jsonl = format!("{row}\n{row}\n");
    assert!(validate_requested(&reply, &questions).is_err());
}
#[test]
fn record_kind_and_admitted_rule_shape_are_checked() {
    for change in 0..4 {
        let (mut reply, questions, mut row) = fixture();
        match change {
            0 => row["items"][0]["kind"] = json!("unknown"),
            1 => row["items"][0]["site"]["rule"] = json!("not_a_rule"),
            2 => row["items"][0]["site"]["line"] = json!(0),
            _ => row["items"][0]["lint"] = json!("player_link"),
        };
        reply.jsonl = format!("{row}\n");
        assert!(validate_requested(&reply, &questions).is_err());
    }
}
