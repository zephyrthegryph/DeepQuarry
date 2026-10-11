use super::*;

fn production_lower(source: &'static str) -> LoweringBatch {
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap()
    .with_bootstrap_catalog()
    .unwrap();
    let seed = engine.frontend_seed();
    let frontend = dm_tree::frontend::build_with_config(
        Path::new("project.dme"),
        &Source(source),
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    let startup = crate::startup::capture(&frontend).unwrap();
    let (pinned_host, _) =
        crate::request_runner::runner_facts::prepare(&frontend, &engine).unwrap();
    let host = startup.resolver(&frontend, &pinned_host).unwrap();
    let abi =
        crate::driver_facts::prepare_pinned_source_abi(&frontend, &engine, &host, None, 1).unwrap();
    assert!(
        abi.prepared.diagnostics.is_empty(),
        "{:?}",
        abi.prepared.diagnostics
    );
    let policy = crate::driver_facts::FrozenPreparedPolicy::new(&frontend, &abi.prepared).unwrap();
    lower_frontend_with_statics(
        &frontend,
        &host,
        &policy,
        LoweringConfig::default(),
        &startup,
    )
}

#[test]
fn certified_incomplete_body_is_source_error_at_current_shifted_line() {
    for (source, line) in [
        ("/proc/probe()\n    return (1 +\n", 2),
        ("// shifted source\n\n/proc/probe()\n    return (1 +\n", 4),
    ] {
        let result = production_lower(source);
        assert!(result.units.is_empty());
        assert_eq!(result.diagnostics.len(), 1, "{:?}", result.diagnostics);
        let error = &result.diagnostics[0];
        assert_eq!(error.kind, DiagnosticKind::SourceError);
        assert_eq!(error.origin.line, line);
        assert_eq!(error.origin.path.as_path(), Path::new("project.dme"));
        assert_eq!(error.message, "missing right operand for +");
    }
}

#[test]
fn missing_unary_operand_is_source_error_through_actual_lowering() {
    for (source, expected) in [
        (
            "// shifted\n/proc/probe()\n    return !\n",
            "missing operand for unary !",
        ),
        (
            "// shifted\n/proc/probe()\n    return ~\n",
            "missing operand for unary ~",
        ),
        (
            "// shifted\n/proc/probe()\n    return ++\n",
            "missing operand for prefix ++",
        ),
    ] {
        let result = production_lower(source);
        assert!(result.units.is_empty());
        assert_eq!(result.diagnostics.len(), 1, "{:?}", result.diagnostics);
        assert_eq!(result.diagnostics[0].kind, DiagnosticKind::SourceError);
        assert_eq!(result.diagnostics[0].origin.line, 3);
        assert_eq!(result.diagnostics[0].message, expected);
    }
    let result = production_lower("/proc/probe()\n    return !1\n");
    assert!(result.diagnostics.is_empty(), "{:?}", result.diagnostics);
    assert_eq!(result.units.len(), 1);
}

#[test]
fn duplicate_local_related_diagnostic_uses_current_source_and_renderer() {
    for (source, previous, current) in [
        (
            "/proc/probe()\n    var/value = 7\n    var/value = 9\n",
            2,
            3,
        ),
        (
            "// shifted\n\n/proc/probe()\n    var/value = 7\n    var/value = 9\n",
            4,
            5,
        ),
    ] {
        let result = production_lower(source);
        assert_eq!(result.diagnostics.len(), 1);
        let error = &result.diagnostics[0];
        assert_eq!(error.kind, DiagnosticKind::SourceError);
        assert_eq!(error.origin.line, current);
        assert_eq!(error.related.len(), 1);
        assert_eq!(error.related[0].origin.line, previous);
        assert_eq!(
            error.related[0].origin.path.as_path(),
            Path::new("project.dme")
        );
        assert_eq!(error.related[0].message, "value: previous definition");
        let mut text = Vec::new();
        crate::diagnostics::write_lowering_diagnostics(&mut text, &result.diagnostics).unwrap();
        let text = String::from_utf8(text).unwrap();
        assert_eq!(text.matches(":error:").count(), 2, "{text}");
        assert!(
            text.contains(&format!("project.dme:{current}:error:")),
            "{text}"
        );
        assert!(
            text.contains(&format!(
                "project.dme:{previous}:error: value: previous definition"
            )),
            "{text}"
        );
    }
}

#[test]
fn actual_parameter_rules_match_authenticated_native_capture() {
    let accepted = production_lower(include_str!(
        "../../../../fixtures/native/parameter_duplicate_diagnostics/duplicate_parameter.dm"
    ));
    assert!(
        accepted.diagnostics.is_empty(),
        "{:?}",
        accepted.diagnostics
    );
    assert_eq!(accepted.units.len(), 1);
    assert_eq!(
        accepted.units[0].code.procedure.argument_names,
        ["value", "value"]
    );
    for (source, previous, current) in [
        (
            "/proc/probe(value)\n    var/value = 7\n    return value\n",
            1,
            2,
        ),
        (
            "/proc/probe(value)\n    if(1)\n        var/value = 7\n        return value\n",
            1,
            3,
        ),
        (
            "/proc/probe(value)\n    for(var/value in list(1, 2))\n        return value\n",
            1,
            2,
        ),
        (
            "// shifted\n\n/proc/probe(value)\n    var/value = 7\n    return value\n",
            3,
            4,
        ),
    ] {
        let result = production_lower(source);
        assert!(result.units.is_empty());
        assert_eq!(result.diagnostics.len(), 1);
        let error = &result.diagnostics[0];
        assert_eq!(error.kind, DiagnosticKind::SourceError);
        assert_eq!(error.origin.line, current);
        assert_eq!(error.related.len(), 1);
        assert_eq!(error.related[0].origin.line, previous);
        assert_eq!(error.related[0].message, "value: previous definition");
        let mut text = Vec::new();
        crate::diagnostics::write_lowering_diagnostics(&mut text, &result.diagnostics).unwrap();
        let text = String::from_utf8(text).unwrap();
        assert!(
            text.contains(&format!("project.dme:{current}:error:")),
            "{text}"
        );
        assert!(
            text.contains(&format!(
                "project.dme:{previous}:error: value: previous definition"
            )),
            "{text}"
        );
        assert_eq!(text.matches(":error:").count(), 2);
    }
}

#[test]
fn duplicate_typed_formals_reject_missing_method_with_native_diagnostic() {
    for source in [
        include_str!(
            "../../../../fixtures/native/parameter_duplicate_diagnostics/duplicate_typed_first.dm"
        ),
        include_str!(
            "../../../../fixtures/native/parameter_duplicate_diagnostics/duplicate_typed_last.dm"
        ),
    ] {
        let result = production_lower(source);
        assert!(result.units.is_empty());
        assert_eq!(result.diagnostics.len(), 1);
        let error = &result.diagnostics[0];
        assert_eq!(error.kind, DiagnosticKind::SourceError);
        assert_eq!(error.origin.line, 2);
        assert_eq!(error.message, "value.formerly_missing: undefined proc");
        assert!(error.related.is_empty());
    }
}

#[test]
fn actual_untyped_receiver_matrix_matches_native_source_rejections() {
    let evidence: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../fixtures/native/untyped_receiver_diagnostics/byond_observations.json"
    ))
    .unwrap();
    assert_eq!(
        evidence["pins"]["dm"]["sha256"],
        "8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0"
    );
    let cases = [
        (
            "datum_new_colon",
            include_str!(
                "../../../../fixtures/native/untyped_receiver_diagnostics/datum_new_colon.dm"
            ),
        ),
        (
            "datum_new_dot",
            include_str!(
                "../../../../fixtures/native/untyped_receiver_diagnostics/datum_new_dot.dm"
            ),
        ),
        (
            "datum_typed_copy",
            include_str!(
                "../../../../fixtures/native/untyped_receiver_diagnostics/datum_typed_copy.dm"
            ),
        ),
        (
            "global_name_colon",
            include_str!(
                "../../../../fixtures/native/untyped_receiver_diagnostics/global_name_colon.dm"
            ),
        ),
        (
            "global_name_dot",
            include_str!(
                "../../../../fixtures/native/untyped_receiver_diagnostics/global_name_dot.dm"
            ),
        ),
        (
            "list_copy_colon",
            include_str!(
                "../../../../fixtures/native/untyped_receiver_diagnostics/list_copy_colon.dm"
            ),
        ),
        (
            "list_copy_dot",
            include_str!(
                "../../../../fixtures/native/untyped_receiver_diagnostics/list_copy_dot.dm"
            ),
        ),
        (
            "list_typed_copy",
            include_str!(
                "../../../../fixtures/native/untyped_receiver_diagnostics/list_typed_copy.dm"
            ),
        ),
        (
            "other_type_colon",
            include_str!(
                "../../../../fixtures/native/untyped_receiver_diagnostics/other_type_colon.dm"
            ),
        ),
        (
            "other_type_dot",
            include_str!(
                "../../../../fixtures/native/untyped_receiver_diagnostics/other_type_dot.dm"
            ),
        ),
        (
            "other_type_typed",
            include_str!(
                "../../../../fixtures/native/untyped_receiver_diagnostics/other_type_typed.dm"
            ),
        ),
        (
            "self_declared_dot",
            include_str!(
                "../../../../fixtures/native/untyped_receiver_diagnostics/self_declared_dot.dm"
            ),
        ),
        (
            "self_missing_colon",
            include_str!(
                "../../../../fixtures/native/untyped_receiver_diagnostics/self_missing_colon.dm"
            ),
        ),
        (
            "self_missing_dot",
            include_str!(
                "../../../../fixtures/native/untyped_receiver_diagnostics/self_missing_dot.dm"
            ),
        ),
        (
            "undefined_colon",
            include_str!(
                "../../../../fixtures/native/untyped_receiver_diagnostics/undefined_colon.dm"
            ),
        ),
        (
            "undefined_dot",
            include_str!(
                "../../../../fixtures/native/untyped_receiver_diagnostics/undefined_dot.dm"
            ),
        ),
        (
            "verb_only_dot",
            include_str!(
                "../../../../fixtures/native/untyped_receiver_diagnostics/verb_only_dot.dm"
            ),
        ),
        (
            "verb_only_colon",
            include_str!(
                "../../../../fixtures/native/untyped_receiver_diagnostics/verb_only_colon.dm"
            ),
        ),
        (
            "mixed_proc_verb_colon",
            include_str!(
                "../../../../fixtures/native/untyped_receiver_diagnostics/mixed_proc_verb_colon.dm"
            ),
        ),
        (
            "typed_source_verb",
            include_str!(
                "../../../../fixtures/native/untyped_receiver_diagnostics/typed_source_verb.dm"
            ),
        ),
        (
            "self_source_verb",
            include_str!(
                "../../../../fixtures/native/untyped_receiver_diagnostics/self_source_verb.dm"
            ),
        ),
    ];
    for (name, source) in cases {
        let actual = production_lower(source);
        let native = &evidence["byond"][name];
        let native_errors: Vec<_> = native["diagnostics"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|error| error["severity"] == "error")
            .collect();
        if native["child"]["exit"] == 0 {
            assert!(
                actual.diagnostics.is_empty(),
                "{name}: {:?}",
                actual.diagnostics
            );
            assert!(!actual.units.is_empty(), "{name}");
        } else {
            assert_eq!(
                actual.diagnostics.len(),
                native_errors.len(),
                "{name}: {:?}",
                actual.diagnostics
            );
            for (actual, native) in actual.diagnostics.iter().zip(native_errors) {
                assert_eq!(actual.kind, DiagnosticKind::SourceError, "{name}");
                assert_eq!(
                    actual.origin.line as u64,
                    native["line"].as_u64().unwrap(),
                    "{name}"
                );
                assert_eq!(
                    actual.message,
                    native["message"].as_str().unwrap(),
                    "{name}"
                );
                assert!(actual.related.is_empty(), "{name}");
            }
        }
    }
}

#[test]
fn safe_receiver_and_catch_controls_match_authenticated_native_diagnostics() {
    let evidence: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../fixtures/native/safe_receiver_catch_diagnostics/byond_observations.json"
    ))
    .unwrap();
    let cases = [
        ("safe_untyped_known", include_str!("../../../../fixtures/native/safe_receiver_catch_diagnostics/safe_untyped_known.dm")),
        ("safe_untyped_missing", include_str!("../../../../fixtures/native/safe_receiver_catch_diagnostics/safe_untyped_missing.dm")),
        ("safe_typed_datum_missing", include_str!("../../../../fixtures/native/safe_receiver_catch_diagnostics/safe_typed_datum_missing.dm")),
        ("safe_typed_list_copy", include_str!("../../../../fixtures/native/safe_receiver_catch_diagnostics/safe_typed_list_copy.dm")),
        ("safe_typed_source_known", include_str!("../../../../fixtures/native/safe_receiver_catch_diagnostics/safe_typed_source_known.dm")),
        ("catch_parameter", include_str!("../../../../fixtures/native/safe_receiver_catch_diagnostics/catch_parameter.dm")),
        ("catch_local", include_str!("../../../../fixtures/native/safe_receiver_catch_diagnostics/catch_local.dm")),
        ("catch_distinct", include_str!("../../../../fixtures/native/safe_receiver_catch_diagnostics/catch_distinct.dm")),
        ("catch_nested", include_str!("../../../../fixtures/native/safe_receiver_catch_diagnostics/catch_nested.dm")),
        ("catch_typed", include_str!("../../../../fixtures/native/safe_receiver_catch_diagnostics/catch_typed.dm")),
    ];
    for (name, source) in cases {
        let actual = production_lower(source);
        let native = &evidence["byond"][name];
        let expected: Vec<_> = native["diagnostics"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|d| d["severity"] == "error")
            .collect();
        if native["child"]["exit"] == 0 {
            assert!(
                actual.diagnostics.is_empty(),
                "{name}: {:?}",
                actual.diagnostics
            );
        } else {
            assert_eq!(
                actual.diagnostics.len(),
                1,
                "{name}: {:?}",
                actual.diagnostics
            );
            let error = &actual.diagnostics[0];
            assert_eq!(error.kind, DiagnosticKind::SourceError, "{name}: {error:?}");
            assert_eq!(
                error.message,
                expected[0]["message"].as_str().unwrap(),
                "{name}"
            );
            assert_eq!(
                error.origin.line,
                expected[0]["line"].as_u64().unwrap() as usize,
                "{name}"
            );
            assert_eq!(error.related.len(), expected.len() - 1, "{name}: {error:?}");
            for (related, expected) in error.related.iter().zip(expected.iter().skip(1)) {
                assert_eq!(
                    related.message,
                    expected["message"].as_str().unwrap(),
                    "{name}"
                );
                assert_eq!(
                    related.origin.line,
                    expected["line"].as_u64().unwrap() as usize,
                    "{name}"
                );
            }
        }
    }
}

#[test]
fn sized_local_array_receivers_use_issued_list_type_and_validate_methods() {
    for source in [
        "/proc/probe()\n    var/list/trx[0]\n    trx.Add(1)\n    return trx.Copy()\n",
        "/proc/probe()\n    var/trx[0]\n    trx.Add(1)\n    return trx.Copy()\n",
        "/proc/probe()\n    var/datum/trx[2]\n    trx.Add(null)\n    return trx.Copy()\n",
        "/proc/probe()\n    var/list/trx[1][2]\n    trx.Add(1)\n    return trx.Copy()\n",
    ] {
        let batch = production_lower(source);
        assert!(
            batch.diagnostics.is_empty(),
            "{source}: {:?}",
            batch.diagnostics
        );
        assert_eq!(batch.units.len(), 1);
    }
    let batch = production_lower(
        "/proc/probe()\n    var/list/trx[0]\n    return trx.no_such_array_method()\n",
    );
    assert!(batch.units.is_empty());
    assert_eq!(batch.diagnostics.len(), 1);
    // Complete source and reviewed native member-union absence certify this
    // negative without pretending the list namespace itself is closed.
    assert_eq!(batch.diagnostics[0].kind, DiagnosticKind::SourceError);
    assert_eq!(batch.diagnostics[0].origin.line, 3);
}
