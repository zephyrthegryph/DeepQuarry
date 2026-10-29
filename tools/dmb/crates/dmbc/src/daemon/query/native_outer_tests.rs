//! Exercise the OUTER client admission path, not only cohort-local validators.
use super::*;
use serde_json::{json, Value};
fn root() -> PathBuf {
    std::env::current_dir()
        .unwrap()
        .join("native-outer-fixture")
}
fn pin(c: char) -> String {
    std::iter::repeat_n(c, 32).collect()
}
fn common(tag: &str) -> Value {
    json!({"row":tag,"schema":"dm-session-source-query-v1","source_revision":pin('2'),"semantic_revision":pin('1')})
}
fn untyped(bound: bool) -> Value {
    let mut row = common("source_native_untyped_fixture");
    row["root"] = json!(root());
    row["full_policy_parity"] = false.into();
    row["raw_marker_scope"] = json!(if bound {
        "explicit_captured_files"
    } else {
        "captured_compiled_sources"
    });
    row["admission"] = "raw_findings".into();
    row["findings"] = json!([]);
    if bound {
        row["policy_revision"] = pin('3').into();
    }
    row
}
fn rows() -> Vec<Value> {
    let untyped = untyped(true);
    let mut checker = common("source_native_checker_fixture");
    checker["ordinal"] = 0.into();
    checker["family"] = "ambiguous_not_bitwise".into();
    checker["policy"] = "warning".into();
    checker["full_checker_parity"] = false.into();
    checker["diagnostics"] = json!([]);
    let mut named = common("source_native_named_rule");
    named["policy_revision"] = pin('3').into();
    named["root"] = json!(root());
    named["lint"] = "base_vars".into();
    named["rule"] = "records_data_only".into();
    named["configuration"] = json!(root().join("scopes.toml"));
    named["coverage"] = "captured_compiled_declarations".into();
    named["admission"] = "raw_findings".into();
    named["full_lint_parity"] = false.into();
    named["findings"] = json!([]);
    let mut configured = common("source_native_configured_checker");
    configured["policy_revision"] = pin('3').into();
    configured["ordinal"] = 0.into();
    configured["family"] = "ambiguous_not_bitwise".into();
    configured["environment"] = json!(root().join("p.dme"));
    configured["configuration"] = json!(root().join("SpacemanDMM.toml"));
    configured["configuration_explicit"] = false.into();
    configured["configuration_present"] = true.into();
    configured["configuration_schema"] = "complete_pinned_checker_schema".into();
    configured["full_checker_parity"] = false.into();
    configured["diagnostics"] = json!([]);
    let mut batch = common("source_native_configured_control_batch");
    batch["policy_revision"] = pin('3').into();
    batch["ordinal"] = 0.into();
    batch["families"] = json!(["control_condition_static", "if_condition_determinate"]);
    batch["environment"] = json!(root().join("p.dme"));
    batch["configuration"] = json!(root().join("SpacemanDMM.toml"));
    batch["configuration_explicit"] = false.into();
    batch["configuration_present"] = true.into();
    batch["configuration_schema"] = "complete_pinned_checker_schema".into();
    batch["full_checker_parity"] = false.into();
    batch["ordering"] = "primary_control_event_order".into();
    batch["flow_reuse"] = "request_local_union".into();
    batch["diagnostics"] = json!([]);
    let mut raw = common("source_native_raw_policy_fixture");
    raw["policy_revision"] = pin('3').into();
    raw["root"] = json!(root());
    raw["configuration"] = json!(root().join("scopes.toml"));
    raw["requested_lints"] = json!(["scheduler"]);
    raw["lint_whitelist"] = json!(dq_analyze::captured_raw_policy::RAW_FILE_LINTS);
    raw["scope"] = "explicit_captured_files".into();
    raw["full_policy_parity"] = false.into();
    raw["baseline_applied"] = false.into();
    raw["admission"] = "raw_findings".into();
    raw["configuration_scope"] = "proven_missing_configuration".into();
    raw["fixture_limits"] = json!({"per_file_bytes":dq_analyze::captured_raw_policy::MAX_FIXTURE_FILE_BYTES,"total_bytes":dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES,"sites":dq_analyze::captured_raw_policy::MAX_FIXTURE_SITES,"contract":"fixture_admission_not_cpu_or_rss"});
    raw["results"] = json!([{"name":"scheduler","sites":[],"allow_used":[],"notes":[]}]);
    vec![untyped, checker, named, configured, batch, raw]
}
fn reply(rows: &[Value], bound: bool) -> QueryReply {
    QueryReply {
        schema: "dm-session-query-v2".into(),
        revision: pin('1'),
        complete: false,
        coverage: "explicit migrated source cohorts".into(),
        query_count: 0,
        source_query_count: rows.len(),
        source_revision: Some(pin('2')),
        policy_revision: bound.then(|| pin('3')),
        snapshot_outcome: "analyzed".into(),
        last_request_outcome: "analyzed".into(),
        publication_pair: None,
        jsonl: rows.iter().map(|r| format!("{r}\n")).collect(),
    }
}
fn outer(reply: &QueryReply) -> io::Result<()> {
    validate_reply(
        reply,
        0,
        reply.source_query_count,
        Some(&pin('1')),
        Some(&pin('2')),
    )
}
#[test]
fn bound_untyped_scope_and_legacy_unbound_scope_both_pass_real_outer_admission() {
    outer(&reply(&[untyped(true)], true)).unwrap();
    outer(&reply(&[untyped(false)], false)).unwrap();
    let mut bad = untyped(true);
    bad["raw_marker_scope"] = "captured_compiled_sources".into();
    assert!(outer(&reply(&[bad], true)).is_err());
    let mut bad = untyped(false);
    bad["policy_revision"] = Value::Null;
    assert!(outer(&reply(&[bad], false)).is_err());
}
#[test]
fn all_native_cohorts_pass_outer_shape_and_existing_real_roster_validation() {
    let rows = rows();
    let reply = reply(&rows, true);
    outer(&reply).unwrap();
    let requested: Vec<_> = rows
        .iter()
        .map(|row| native_row_descriptor(row).unwrap().unwrap())
        .collect();
    native_policy::validate_requested(&reply, &requested).unwrap();
    named_policy::validate_requested(&reply, &requested).unwrap();
    control_batch::validate_requested(&reply, &requested).unwrap();
    raw_policy::validate_requested(&reply, &requested).unwrap();
}
#[test]
fn every_native_cohort_rejects_foreign_source_semantic_and_applicable_policy_pins() {
    for original in rows() {
        for field in ["source_revision", "semantic_revision"] {
            let mut bad = original.clone();
            bad[field] = pin('4').into();
            assert!(
                outer(&reply(&[bad], true)).is_err(),
                "{} {field}",
                original["row"]
            );
        }
        if original.get("policy_revision").is_some() {
            let mut bad = original.clone();
            bad["policy_revision"] = pin('4').into();
            assert!(outer(&reply(&[bad], true)).is_err());
        }
    }
}
#[test]
fn every_native_cohort_rejects_false_full_coverage_and_model_injection() {
    for original in rows() {
        let field = if original.get("full_policy_parity").is_some() {
            "full_policy_parity"
        } else if original.get("full_lint_parity").is_some() {
            "full_lint_parity"
        } else {
            "full_checker_parity"
        };
        let mut bad = original.clone();
        bad[field] = true.into();
        assert!(outer(&reply(&[bad], true)).is_err());
        let mut bad = original;
        bad["semantic_model"] = json!({"types":[]});
        assert!(outer(&reply(&[bad], true)).is_err());
    }
}
#[test]
fn missing_rows_unknown_tags_and_inconsistent_source_counts_remain_rejected() {
    let rows = rows();
    let mut missing = reply(&rows, true);
    missing.jsonl = rows[..rows.len() - 1]
        .iter()
        .map(|row| format!("{row}\n"))
        .collect();
    assert!(outer(&missing).is_err());
    let mut unknown = common("source_native_object_model");
    unknown["complete"] = false.into();
    assert!(outer(&reply(&[unknown], true)).is_err());
    let mut bad = reply(&[untyped(true)], true);
    bad.source_revision = None;
    assert!(outer(&bad).is_err());
}
#[test]
fn outer_descriptor_never_grants_authority_for_a_different_requested_root() {
    let valid = rows().remove(2);
    let question = native_row_descriptor(&valid).unwrap().unwrap();
    let mut changed = valid;
    changed["root"] = json!(root().join("different"));
    let reply = reply(&[changed], true);
    outer(&reply).unwrap();
    assert!(named_policy::validate_requested(&reply, &[question]).is_err());
}
