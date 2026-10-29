use super::*;
use serde_json::json;
fn root() -> std::path::PathBuf {
    std::env::current_dir().unwrap().join("named-policy-wire")
}
fn named() -> SourceQuery {
    SourceQuery::NativeNamedRule {
        root: root(),
        lint: "base_vars".into(),
        rule: "records_data_only".into(),
        configuration: root().join("scopes.toml"),
    }
}
fn request() -> QueryRequest {
    QueryRequest {
        timeout_seconds: None,
        project: root().join("p.dme"),
        defines: Default::default(),
        engine_template: None,
        bootstrap_catalog: false,
        expected_revision: Some("1".repeat(32)),
        expected_source_revision: Some("2".repeat(32)),
        expected_policy_revision: Some("3".repeat(32)),
        queries: vec![],
        source_queries: vec![named()],
    }
}
fn row() -> Value {
    json!({"row":"source_native_named_rule","schema":"dm-session-source-query-v1","semantic_revision":"semantic","source_revision":"source","policy_revision":"policy",
    "root":root(),"lint":"base_vars","rule":"records_data_only","configuration":root().join("scopes.toml"),"coverage":"captured_compiled_declarations","admission":"raw_findings","full_lint_parity":false,"findings":[]})
}
fn reply(row: &Value) -> QueryReply {
    QueryReply {
        schema: "dm-session-query-v1".into(),
        revision: "semantic".into(),
        complete: false,
        coverage: "partial".into(),
        query_count: 0,
        source_query_count: 1,
        source_revision: Some("source".into()),
        policy_revision: Some("policy".into()),
        snapshot_outcome: "analyzed".into(),
        last_request_outcome: "analyzed".into(),
        publication_pair: None,
        jsonl: format!("{row}\n"),
    }
}
#[test]
fn named_requests_require_exact_policy_pin_and_supported_absolute_scope() {
    let mut r = request();
    validate_request(&r).unwrap();
    r.expected_policy_revision = None;
    assert!(validate_request(&r).is_err());
    r = request();
    if let SourceQuery::NativeNamedRule { rule, .. } = &mut r.source_queries[0] {
        *rule = "whole_lint".into();
    }
    assert!(validate_request(&r).is_err());
    r = request();
    if let SourceQuery::NativeNamedRule { configuration, .. } = &mut r.source_queries[0] {
        *configuration = "relative.toml".into();
    }
    assert!(validate_request(&r).is_err());
}
#[test]
fn named_findings_reject_foreign_policy_config_and_false_full_coverage() {
    let good = row();
    validate_requested(&reply(&good), &[named()]).unwrap();
    for (field, value) in [
        ("policy_revision", json!("foreign")),
        ("configuration", json!(root().join("other.toml"))),
        ("full_lint_parity", json!(true)),
        ("coverage", json!("workspace_complete")),
    ] {
        let mut bad = good.clone();
        bad[field] = value;
        assert!(
            validate_requested(&reply(&bad), &[named()]).is_err(),
            "{field}"
        );
    }
    assert!(validate_requested(&reply(&good), &[]).is_err());
    let mut duplicate = reply(&good);
    duplicate.jsonl += &duplicate.jsonl.clone();
    assert!(validate_requested(&duplicate, &[named()]).is_err());
}
#[test]
fn configured_checker_metadata_binds_autodetection_and_complete_schema_claim() {
    let environment = root().join("p.dme");
    let question = SourceQuery::NativeConfiguredChecker {
        ordinal: 0,
        family: "ambiguous_not_bitwise".into(),
        environment: environment.clone(),
        configuration: None,
    };
    let good = json!({"row":"source_native_configured_checker","schema":"dm-session-source-query-v1","semantic_revision":"semantic","source_revision":"source","policy_revision":"policy",
        "ordinal":0,"family":"ambiguous_not_bitwise","environment":environment,"configuration":root().join("SpacemanDMM.toml"),"configuration_explicit":false,"configuration_present":false,
        "configuration_schema":"complete_pinned_checker_schema","full_checker_parity":false,"diagnostics":[]});
    validate_requested(&reply(&good), std::slice::from_ref(&question)).unwrap();
    let mut bad = good.clone();
    bad["configuration_explicit"] = true.into();
    assert!(validate_requested(&reply(&bad), std::slice::from_ref(&question)).is_err());
    let mut bad = good;
    bad["full_checker_parity"] = true.into();
    assert!(validate_requested(&reply(&bad), &[question]).is_err());
}

#[test]
fn semantic_checker_admission_and_partial_reply_metadata_are_exact() {
    for family in [
        "proc_has_no_parent",
        "undefined_proc",
        "undefined_variable",
        "field_access_static_type",
        "no_typehint_implicit_new",
    ] {
        let environment = root().join("p.dme");
        let question = SourceQuery::NativeConfiguredChecker {
            ordinal: 4,
            family: family.into(),
            environment: environment.clone(),
            configuration: None,
        };
        let mut r = request();
        r.source_queries = vec![question.clone()];
        validate_request(&r).unwrap();
        let good = json!({"row":"source_native_configured_checker","schema":"dm-session-source-query-v1",
            "semantic_revision":"semantic","source_revision":"source","policy_revision":"policy",
            "ordinal":4,"family":family,"environment":environment,"configuration":root().join("SpacemanDMM.toml"),
            "configuration_explicit":false,"configuration_present":false,
            "configuration_schema":"complete_pinned_checker_schema","full_checker_parity":false,
            "diagnostics":[{"family":family,"severity":"error","file":"p.dm","line":2,
                "expanded_span":[10,12],"expression_span":[10,14],"message":"specific refusal","notes":[]}]});
        validate_requested(&reply(&good), std::slice::from_ref(&question)).unwrap();
        for (key, value) in [
            ("full_checker_parity", json!(true)),
            ("ordinal", json!(3)),
            ("family", json!("other")),
        ] {
            let mut bad = good.clone();
            bad[key] = value;
            assert!(validate_requested(&reply(&bad), std::slice::from_ref(&question)).is_err());
        }
    }
}
