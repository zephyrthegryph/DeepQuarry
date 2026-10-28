use super::*;
use serde_json::json;

fn checker(ordinal: u32, severity: &str) -> SourceQuery {
    SourceQuery::NativeCheckerFixture {
        ordinal,
        severity: severity.into(),
    }
}
fn untyped(root: &str) -> SourceQuery {
    SourceQuery::NativeUntypedFixture { root: root.into() }
}
fn checker_row(ordinal: u32, policy: &str) -> Value {
    json!({"row":"source_native_checker_fixture", "schema":"dm-session-source-query-v1", "source_revision":"source", "semantic_revision":"semantic", "ordinal":ordinal, "family":"ambiguous_not_bitwise", "policy":policy, "full_checker_parity":false, "diagnostics":[]})
}
fn untyped_row(root: &str) -> Value {
    json!({"row":"source_native_untyped_fixture", "schema":"dm-session-source-query-v1", "source_revision":"source", "semantic_revision":"semantic", "root":root, "full_policy_parity":false, "raw_marker_scope":"captured_compiled_sources", "admission":"raw_findings", "findings":[{"rule":"typed", "file":"code/a.dm", "line":1, "message":"untyped value", "identity":"a"}]})
}
fn diagnostic() -> Value {
    json!({"family":"ambiguous_not_bitwise", "severity":"warning", "expanded_span":[1,5], "expression_span":[2,4], "file":"a.dm", "line":1, "include_occurrence":0, "include_chain":[0], "message":"warning", "notes":["detail"]})
}
fn reply(rows: &[Value], source_query_count: usize) -> QueryReply {
    QueryReply {
        schema: "unused-outer-schema".into(),
        revision: "semantic".into(),
        complete: false,
        coverage: "partial".into(),
        query_count: 0,
        source_query_count,
        source_revision: Some("source".into()),
        snapshot_outcome: "analyzed".into(),
        last_request_outcome: "analyzed".into(),
        publication_pair: None,
        jsonl: rows.iter().map(|v| format!("{v}\n")).collect(),
    }
}

#[test]
fn validates_mixed_exact_request_roster_without_model_exports() {
    let mut row = checker_row(7, "warning");
    row["diagnostics"] = json!([diagnostic()]);
    let queries = [
        untyped("root"),
        SourceQuery::Occurrence { ordinal: 3 },
        checker(7, "warning"),
        checker(8, "disabled"),
    ];
    let rows = [
        untyped_row("root"),
        json!({"row":"source_occurrence"}),
        row,
        checker_row(8, "disabled"),
    ];
    validate_requested(&reply(&rows, 4), &queries).unwrap();
    validate_requested(&reply(&[], 0), &[]).unwrap();
}

#[test]
fn missing_extra_and_reordered_rows_are_rejected() {
    let queries = [untyped("root"), checker(7, "warning")];
    let a = untyped_row("root");
    let b = checker_row(7, "warning");
    for rows in [
        vec![a.clone()],
        vec![a.clone(), b.clone(), b.clone()],
        vec![b.clone(), a.clone()],
    ] {
        assert!(validate_requested(&reply(&rows, 2), &queries).is_err());
    }
    assert!(validate_requested(&reply(&[a, b], 3), &queries).is_err());
    assert!(validate_requested(&reply(&[checker_row(1, "error")], 0), &[]).is_err());
}

#[test]
fn root_ordinal_policy_schema_and_revision_are_exact() {
    for (key, value) in [
        ("root", json!("other")),
        ("schema", json!("other")),
        ("source_revision", json!("old")),
        ("semantic_revision", json!("old")),
        ("raw_marker_scope", json!("workspace")),
        ("admission", json!("accepted")),
    ] {
        let mut row = untyped_row("root");
        row[key] = value;
        assert!(
            validate_requested(&reply(&[row], 1), &[untyped("root")]).is_err(),
            "{key}"
        );
    }
    for (key, value) in [
        ("ordinal", json!(8)),
        ("policy", json!("error")),
        ("family", json!("other")),
    ] {
        let mut row = checker_row(7, "warning");
        row[key] = value;
        assert!(
            validate_requested(&reply(&[row], 1), &[checker(7, "warning")]).is_err(),
            "{key}"
        );
    }
}

#[test]
fn full_claims_missing_partial_flags_and_model_payloads_are_rejected() {
    for key in ["full_policy_parity", "full_checker_parity"] {
        let (mut row, query) = if key == "full_policy_parity" {
            (untyped_row("root"), untyped("root"))
        } else {
            (checker_row(7, "warning"), checker(7, "warning"))
        };
        row[key] = json!(true);
        assert!(validate_requested(&reply(&[row.clone()], 1), &[query.clone()]).is_err());
        row.as_object_mut().unwrap().remove(key);
        assert!(validate_requested(&reply(&[row], 1), &[query]).is_err());
    }
    let mut row = untyped_row("root");
    row["model"] = json!({});
    assert!(validate_requested(&reply(&[row], 1), &[untyped("root")]).is_err());
    let mut row = checker_row(7, "warning");
    row["typed_jsonl"] = json!("model");
    assert!(validate_requested(&reply(&[row], 1), &[checker(7, "warning")]).is_err());
}

#[test]
fn malformed_finding_arrays_and_fields_are_rejected() {
    for finding in [
        json!({}),
        json!({"rule":"typed","file":"a","line":true,"message":"m","identity":"i"}),
        json!({"rule":"new_rule","file":"a","line":1,"message":"m","identity":"i"}),
        json!({"rule":"typed","file":"a","line":0,"message":"m","identity":"i"}),
        json!({"rule":"typed","file":"a","line":1,"message":"m","identity":"i","model":{}}),
    ] {
        let mut row = untyped_row("root");
        row["findings"] = json!([finding]);
        assert!(validate_requested(&reply(&[row], 1), &[untyped("root")]).is_err());
    }
    for (key, value) in [
        ("expanded_span", json!([5, 1])),
        ("expression_span", json!([1])),
        ("notes", json!([{}])),
        ("include_chain", json!([false])),
        ("severity", json!("error")),
        ("line", json!(0)),
    ] {
        let mut finding = diagnostic();
        finding[key] = value;
        let mut row = checker_row(7, "warning");
        row["diagnostics"] = json!([finding]);
        assert!(
            validate_requested(&reply(&[row], 1), &[checker(7, "warning")]).is_err(),
            "{key}"
        );
    }
    let mut row = checker_row(7, "disabled");
    row["diagnostics"] = json!([diagnostic()]);
    assert!(validate_requested(&reply(&[row], 1), &[checker(7, "disabled")]).is_err());
}
