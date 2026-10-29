use super::*;
use serde_json::json;
fn root() -> std::path::PathBuf {
    std::env::current_dir().unwrap().join("visibility-wire")
}
fn question() -> SourceQuery {
    SourceQuery::NativeConfiguredVariableVisibility {
        environment: root().join("p.dme"),
        configuration: None,
    }
}
fn request() -> QueryRequest {
    serde_json::from_value(json!({"project":root().join("p.dme"),"defines":{},"engine_template":null,"bootstrap_catalog":false,"expected_revision":"1".repeat(32),"expected_source_revision":"2".repeat(32),"expected_policy_revision":"3".repeat(32),"queries":[],"source_queries":[question()]})).unwrap()
}
fn row() -> Value {
    json!({"row":"source_native_configured_variable_visibility","schema":"dm-session-source-query-v1","semantic_revision":"semantic","source_revision":"source","policy_revision":"policy","environment":root().join("p.dme"),"configuration":root().join("SpacemanDMM.toml"),"configuration_explicit":false,"configuration_present":true,"configuration_schema":"complete_pinned_checker_schema","declaration_profile":"strict-native-declarations","native_declaration_error_count":0,"producer_categories":["parser_locals","global_declarations","evaluated_fields"],"families":["private_var","protected_var","final_var"],"untagged_companions":["variable_redeclaration"],"ordering":"parser_encounter_then_lexical_declarations_then_evaluated_checker_order","full_checker_parity":false,"all_source_contexts_supported":false,"diagnostics":[]})
}
fn reply(row: &Value) -> QueryReply {
    serde_json::from_value(json!({"schema":"dm-session-query-v1","revision":"semantic","complete":false,"coverage":"partial","query_count":0,"source_query_count":1,"source_revision":"source","policy_revision":"policy","snapshot_outcome":"analyzed","last_request_outcome":"analyzed","publication_pair":null,"jsonl":format!("{row}\n")})).unwrap()
}
#[test]
fn visibility_whole_archive_requires_policy_pin_and_caller_absolute_config() {
    let mut r = request();
    validate_request(&r).unwrap();
    r.expected_policy_revision = None;
    assert!(validate_request(&r).is_err());
    let mut r = request();
    if let SourceQuery::NativeConfiguredVariableVisibility { environment, .. } =
        &mut r.source_queries[0]
    {
        *environment = "relative.dme".into();
    }
    assert!(validate_request(&r).is_err());
}
#[test]
fn visibility_wire_refuses_false_coverage_missing_category_and_fake_untagged_identity() {
    let good = row();
    validate_requested(&reply(&good), &[question()]).unwrap();
    for (k, v) in [
        ("policy_revision", json!("foreign")),
        ("all_source_contexts_supported", json!(true)),
        ("producer_categories", json!(["evaluated_fields"])),
        ("full_checker_parity", json!(true)),
    ] {
        let mut bad = good.clone();
        bad[k] = v;
        assert!(validate_requested(&reply(&bad), &[question()]).is_err());
    }
    let mut actual = good.clone();
    actual["declaration_profile"] = json!("native-diagnostic-inherited-variable-v1");
    actual["native_declaration_error_count"] = json!(1);
    actual["diagnostics"] = json!([{"family":"variable_redeclaration","registration_tag":null,"severity":"error","origin":{"file":root().join("probe.dm"),"line":4,"column":11},"expanded_span":[1,1],"expression_span":[1,1],"message":"redeclares","notes":[{"message":"declared here","source":{"file":root().join("base.dm"),"line":2,"column":31}}]}]);
    validate_requested(&reply(&actual), &[question()]).unwrap();
    actual["diagnostics"][0]["registration_tag"] = json!("variable_redeclaration");
    assert!(validate_requested(&reply(&actual), &[question()]).is_err());
    assert!(validate_requested(&reply(&good), &[]).is_err());
}

#[test]
fn diagnostic_reply_profile_rejects_unknown_mismatched_and_unissued_domains() {
    let good = row();
    validate_requested(&reply(&good), &[question()]).unwrap();
    let mut diagnostic = good.clone();
    diagnostic["declaration_profile"] = json!("native-diagnostic-inherited-variable-v1");
    diagnostic["native_declaration_error_count"] = json!(1);
    validate_requested(&reply(&diagnostic), &[question()]).unwrap();
    for (profile, count) in [
        (json!("foreign"), json!(1)),
        (json!("strict-native-declarations"), json!(1)),
        (json!("native-diagnostic-inherited-variable-v1"), json!(0)),
        (json!("native-diagnostic-inherited-variable-v1"), json!("1")),
        (json!("native-diagnostic-inherited-variable-v1"), json!(-1)),
        (json!("native-diagnostic-inherited-variable-v1"), json!(1.5)),
    ] {
        let mut bad = good.clone();
        bad["declaration_profile"] = profile;
        bad["native_declaration_error_count"] = count;
        assert!(validate_requested(&reply(&bad), &[question()]).is_err());
    }
    for key in ["declaration_profile", "native_declaration_error_count"] {
        let mut bad = good.clone();
        bad.as_object_mut().unwrap().remove(key);
        assert!(validate_requested(&reply(&bad), &[question()]).is_err());
    }
}
