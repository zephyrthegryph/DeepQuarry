//! Policy metadata is validated even when callers discover current revisions.
use super::*;
fn reply() -> QueryReply {
    QueryReply {
        schema: "dm-session-query-v2".into(),
        revision: "1".repeat(32),
        complete: false,
        coverage: "partial".into(),
        query_count: 0,
        source_query_count: 0,
        source_revision: Some("2".repeat(32)),
        policy_revision: None,
        snapshot_outcome: "analyzed".into(),
        last_request_outcome: "analyzed".into(),
        publication_pair: None,
        jsonl: String::new(),
    }
}
#[test]
fn policy_pin_shape_is_checked_during_discovery_without_expected_pin() {
    let mut value = reply();
    for invalid in [
        String::new(),
        "a".repeat(31),
        "a".repeat(33),
        "g".repeat(32),
    ] {
        value.policy_revision = Some(invalid);
        assert!(validate_reply(&value, 0, 0, None, None).is_err());
    }
    for valid in ["a".repeat(32), "A".repeat(32), "0".repeat(32)] {
        value.policy_revision = Some(valid);
        validate_reply(&value, 0, 0, None, None).unwrap();
    }
}
#[test]
fn policy_pin_cannot_claim_captured_authority_without_source_revision() {
    let mut value = reply();
    value.policy_revision = Some("a".repeat(32));
    value.source_revision = None;
    assert!(validate_reply(&value, 0, 0, None, None).is_err());
}
#[test]
fn absent_policy_metadata_preserves_legacy_wire_shape() {
    let value = reply();
    let wire = serde_json::to_value(&value).unwrap();
    assert!(wire.get("policy_revision").is_none());
    let old: QueryReply = serde_json::from_value(wire).unwrap();
    assert!(old.policy_revision.is_none());
    validate_reply(&old, 0, 0, None, None).unwrap();
}
