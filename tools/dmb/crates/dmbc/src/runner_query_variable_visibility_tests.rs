use super::*;
fn fixture(source: &str, config: Option<&[u8]>) -> SourceSnapshot {
    super::super::named_policy::visibility_test_fixture(source, config)
}
fn row(source: &str, config: Option<&[u8]>) -> serde_json::Value {
    let snapshot = fixture(source, config);
    let mut out = Vec::new();
    let environment = std::env::current_dir()
        .unwrap()
        .join("named-policy-provider/project.dme");
    snapshot
        .write_native_configured_variable_visibility(&environment, None, &snapshot.tree, &mut out)
        .unwrap();
    serde_json::from_slice(&out).unwrap()
}
const MIX:&str="/datum/base\n    var/SpacemanDMM_private/p=null\n/datum/base/child\n    p=null\n/proc/test(datum/base/B)\n    var/SpacemanDMM_private/local\n    B.p\n";
#[test]
fn complete_visibility_categories_keep_source_then_global_then_field_order_and_defaults() {
    let v = row(MIX, None);
    let ds = v["diagnostics"].as_array().unwrap();
    assert_eq!(ds.len(), 3);
    assert_eq!(
        ds.iter()
            .map(|d| d["severity"].as_str().unwrap())
            .collect::<Vec<_>>(),
        ["warning", "error", "warning"]
    );
    assert_eq!(ds[0]["origin"]["line"], 6);
    assert_eq!(ds[1]["origin"]["line"], 4);
    assert_eq!(ds[2]["origin"]["line"], 7);
    assert_eq!(ds[1]["notes"][0]["source"]["line"], 2);
    assert_eq!(
        v["producer_categories"],
        serde_json::json!(["parser_locals", "global_declarations", "evaluated_fields"])
    );
    assert_eq!(v["all_source_contexts_supported"], false);
}
#[test]
fn visibility_display_threshold_distinguishes_defaults_but_named_override_changes_each_site() {
    let errors = row(MIX, Some(b"[display]\nerror_level='error'\n"));
    let ds = errors["diagnostics"].as_array().unwrap();
    assert_eq!(ds.len(), 1);
    assert!(ds[0]["message"]
        .as_str()
        .unwrap()
        .contains("overrides private"));
    let hints = row(MIX, Some(b"[diagnostics]\nprivate_var='hint'\n"));
    let ds = hints["diagnostics"].as_array().unwrap();
    assert_eq!(ds.len(), 3);
    assert!(ds.iter().all(|d| d["severity"] == "hint"));
}
#[test]
fn visibility_untagged_redeclaration_requires_original_native_diagnostic_preparation() {
    // SAME independently pinned old-positive case; do not replace it with a
    // legal value-only override. The strict native compiler must still reject
    // inherited var redeclarations, so the checker-only preparation domain is
    // explicitly unavailable until its original-builder receipt lands.
    let source =
        "/datum/base\n    var/SpacemanDMM_private/p=null\n/datum/base/child\n    var/p=null\n";
    let result = super::super::named_policy::visibility_test_fixture_result(
        source,
        Some(b"[diagnostics]\nprivate_var='off'\nvariable_redeclaration='off'\n"),
    );
    let errors = match result {
        Ok(_) => {
            panic!("inherited-var diagnostic domain requires an explicit checker-only receipt")
        }
        Err(errors) => errors,
    };
    assert_eq!(
        errors.len(),
        2,
        "do not swallow other native source failures"
    );
    let expected = [
        (4, "p: duplicate definition"),
        (2, "p: previous definition"),
    ];
    for (error, (line, message)) in errors.iter().zip(expected) {
        assert_eq!(error.kind, dm_tree::frontend::DiagnosticKind::SourceError);
        assert_eq!(error.message, message);
        let origin = error
            .location
            .as_ref()
            .expect("actual original declaration origin");
        assert_eq!(origin.line, line);
        assert!(origin.path.ends_with("named-policy-provider/project.dme"));
    }
    assert!(!dm_analysis::checks_variable_visibility::COVERAGE.all_source_contexts_supported);
    // No successful checker row, no omitted old diagnostic, no parity claim.
}
#[test]
fn visibility_middle_value_override_does_not_hide_grandparent_private_error() {
    let v=row("/datum/base\n    var/SpacemanDMM_private/p=null\n/datum/base/middle\n    p=null\n/datum/base/middle/child\n    p=null\n",None);
    let ds = v["diagnostics"].as_array().unwrap();
    assert_eq!(ds.len(), 2);
    assert!(ds.iter().all(|d| d["family"] == "private_var"));
    assert!(ds.iter().all(|d| d["notes"][0]["source"]["line"] == 2));
}
#[test]
fn visibility_parser_locals_include_unreachable_but_not_catch_modifier_warnings() {
    let v=row("/proc/test()\n    var/SpacemanDMM_private/SpacemanDMM_protected/a\n    try\n        throw 1\n    catch(var/SpacemanDMM_private/e)\n        return\n    return\n    var/SpacemanDMM_private/b\n",None);
    let ds = v["diagnostics"].as_array().unwrap();
    assert_eq!(ds.len(), 3);
    assert_eq!(
        ds.iter()
            .map(|d| d["origin"]["line"].as_u64().unwrap())
            .collect::<Vec<_>>(),
        [2, 2, 8]
    );
}
#[test]
fn visibility_rejects_equal_but_foreign_semantic_owner() {
    let a = fixture(MIX, None);
    let b = fixture(MIX, None);
    assert_eq!(a.tree.identity(), b.tree.identity());
    let environment = std::env::current_dir()
        .unwrap()
        .join("named-policy-provider/project.dme");
    assert!(a
        .write_native_configured_variable_visibility(&environment, None, &b.tree, &mut Vec::new())
        .is_err());
}

#[test]
fn visibility_rejects_uncaptured_env_and_config_before_body_queries() {
    let snapshot = fixture(MIX, Some(b"[diagnostics]\nprivate_var='warning'\n"));
    let root = std::env::current_dir()
        .unwrap()
        .join("named-policy-provider");
    let db = snapshot.native_raw_queries.as_ref().unwrap();
    let before = db.db().stats(dm_query::Kind(4)).computed;
    for (environment, explicit, expected) in [
        (
            root.join("uncaptured.dme"),
            None,
            "not an original compiled source",
        ),
        (
            root.join("project.dme"),
            Some(root.join("uncaptured.toml")),
            "configuration",
        ),
    ] {
        let mut output = Vec::new();
        let error = snapshot
            .write_native_configured_variable_visibility(
                &environment,
                explicit.as_deref(),
                &snapshot.tree,
                &mut output,
            )
            .unwrap_err();
        assert!(error.to_string().contains(expected), "{error}");
        assert!(output.is_empty());
        assert_eq!(db.db().stats(dm_query::Kind(4)).computed, before);
    }
    let mut allowed = Vec::new();
    snapshot
        .write_native_configured_variable_visibility(
            &root.join("project.dme"),
            Some(&root.join("SpacemanDMM.toml")),
            &snapshot.tree,
            &mut allowed,
        )
        .unwrap();
    assert!(!allowed.is_empty());
    assert!(db.db().stats(dm_query::Kind(4)).computed > before);
}
