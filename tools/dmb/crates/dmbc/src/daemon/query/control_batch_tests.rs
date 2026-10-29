use super::*;
use serde_json::json;
fn root() -> std::path::PathBuf {
    std::env::current_dir().unwrap().join("control-batch-wire")
}
fn question() -> SourceQuery {
    SourceQuery::NativeConfiguredControlBatch {
        ordinal: 0,
        families: vec![
            "if_condition_determinate".into(),
            "control_condition_static".into(),
        ],
        environment: root().join("p.dme"),
        configuration: None,
    }
}
fn request() -> QueryRequest {
    serde_json::from_value(json!({"project":root().join("p.dme"),"defines":{},"engine_template":null,"bootstrap_catalog":false,"expected_revision":"1".repeat(32),"expected_source_revision":"2".repeat(32),"expected_policy_revision":"3".repeat(32),"queries":[],"source_queries":[question()]})).unwrap()
}
fn row() -> Value {
    json!({"row":"source_native_configured_control_batch","schema":"dm-session-source-query-v1","semantic_revision":"semantic","source_revision":"source","policy_revision":"policy","ordinal":0,"families":["if_condition_determinate","control_condition_static"],"environment":root().join("p.dme"),"configuration":root().join("SpacemanDMM.toml"),"configuration_explicit":false,"configuration_present":true,"configuration_schema":"complete_pinned_checker_schema","full_checker_parity":false,"ordering":"primary_control_event_order","flow_reuse":"request_local_union","diagnostics":[]})
}
fn reply(row: &Value) -> QueryReply {
    serde_json::from_value(json!({"schema":"dm-session-query-v1","revision":"semantic","complete":false,"coverage":"partial","query_count":0,"source_query_count":1,"source_revision":"source","policy_revision":"policy","snapshot_outcome":"analyzed","last_request_outcome":"analyzed","publication_pair":null,"jsonl":format!("{row}\n")})).unwrap()
}
#[test]
fn exact_union_requires_policy_pin_and_rejects_duplicate_or_unknown_family() {
    let mut r = request();
    validate_request(&r).unwrap();
    r.expected_policy_revision = None;
    assert!(validate_request(&r).is_err());
    r = request();
    if let SourceQuery::NativeConfiguredControlBatch { families, .. } = &mut r.source_queries[0] {
        families.push("if_condition_determinate".into());
    }
    assert!(validate_request(&r).is_err());
    r = request();
    if let SourceQuery::NativeConfiguredControlBatch { families, .. } = &mut r.source_queries[0] {
        families[0] = "invalid_set_value".into();
    }
    assert!(validate_request(&r).is_err());
}
#[test]
fn exact_union_reply_rejects_foreign_pin_false_cache_claim_and_unrequested_rows() {
    let good = row();
    validate_requested(&reply(&good), &[question()]).unwrap();
    for (key, value) in [
        ("policy_revision", json!("foreign")),
        ("flow_reuse", json!("global_cached_ast")),
        ("ordering", json!("sorted_by_family")),
        ("full_checker_parity", json!(true)),
    ] {
        let mut bad = good.clone();
        bad[key] = value;
        assert!(validate_requested(&reply(&bad), &[question()]).is_err());
    }
    assert!(validate_requested(&reply(&good), &[]).is_err());
}
