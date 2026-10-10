use super::*;

fn production_lower(source: &'static str) -> LoweringBatch {
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"),
        1,
    )
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
    let host = startup
        .resolver(&frontend, frontend.snapshot.tree.as_ref())
        .unwrap();
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
