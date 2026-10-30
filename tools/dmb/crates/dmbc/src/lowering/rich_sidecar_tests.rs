use super::*;
use std::path::Path;
struct Source {
    prefix: bool,
    changed: bool,
}
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, path: &Path) -> Result<String, String> {
        Ok(match path.file_name().unwrap().to_str().unwrap() {
            "project.dme" if self.prefix => "#include \"empty.dm\"\n#include \"probe.dm\"\n".into(),
            "project.dme" => "#include \"probe.dm\"\n".into(),
            "empty.dm" => "// empty occurrence\n".into(),
            "probe.dm" => format!("{}/obj/base\n    var/amount = 0\n/proc/p(x in list(1,{},(/obj/base{{amount=4}})))\n    return (/obj/base{{amount=1}})\n", if self.prefix { "\n\n" } else { "" }, if self.changed { 3 } else { 2 }),
            _ => return Err("unknown fixture input".into()),
        })
    }
}
fn run(
    source: &Source,
    engine: &crate::engine::EngineSnapshot,
    memo: Option<&crate::lowering_memo::ProcedureMemo>,
) -> LoweredUnit {
    let seed = engine.frontend_seed();
    let front = dm_tree::frontend::build_with_config(
        Path::new("project.dme"),
        source,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    let (host, _) = crate::request_runner::runner_facts::prepare(&front, engine).unwrap();
    let startup = crate::startup::capture(&front).unwrap();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let abi =
        crate::driver_facts::prepare_pinned_source_abi_with_startup_on_executor_with_artifacts(
            &front, engine, &host, &startup, None, &executor, None,
        )
        .unwrap();
    let policy = crate::driver_facts::FrozenPreparedPolicy::new(&front, &abi.prepared).unwrap();
    let mut batch = match memo {
        Some(memo) => crate::lowering::lower_frontend_with_memo(
            &front,
            &host,
            &policy,
            Default::default(),
            &startup,
            memo,
        ),
        None => crate::lowering::lower_frontend_with_statics(
            &front,
            &host,
            &policy,
            Default::default(),
            &startup,
        ),
    };
    assert!(batch.diagnostics.is_empty(), "{:?}", batch.diagnostics);
    assert_eq!(batch.units.len(), 1);
    batch.units.pop().unwrap()
}
fn same_current(left: &LoweredUnit, right: &LoweredUnit) {
    assert_eq!(left.code.procedure.code, right.code.procedure.code);
    assert_eq!(left.debug_origins, right.debug_origins);
    assert_eq!(left.origin.source.span, right.origin.source.span);
    assert_eq!(
        left.origin.source.semantic_path,
        right.origin.source.semantic_path
    );
    assert_eq!(left.origin.source.line, right.origin.source.line);
    assert_eq!(
        left.origin.source.include_occurrence,
        right.origin.source.include_occurrence
    );
    assert_eq!(
        left.origin.source.include_chain,
        right.origin.source.include_chain
    );
    assert_eq!(left.source_helpers.len(), right.source_helpers.len());
    for (a, b) in left.source_helpers.iter().zip(&right.source_helpers) {
        assert_eq!(a.argument, b.argument);
        assert_eq!(a.code.procedure.code, b.code.procedure.code);
        assert_eq!(a.debug_origins, b.debug_origins);
        assert_eq!(
            a.code.modified_instances.len(),
            b.code.modified_instances.len()
        );
        for (reference, a) in &a.code.modified_instances {
            let b = &b.code.modified_instances[reference];
            assert_eq!(
                a.descriptor.canonical_bytes(),
                b.descriptor.canonical_bytes()
            );
            assert_eq!(a.source_span, b.source_span);
            assert_eq!(a.field_origins, b.field_origins);
        }
    }
    assert_eq!(
        left.code.modified_instances.len(),
        right.code.modified_instances.len()
    );
    for (reference, a) in &left.code.modified_instances {
        let b = &right.code.modified_instances[reference];
        assert_eq!(
            a.descriptor.canonical_bytes(),
            b.descriptor.canonical_bytes()
        );
        assert_eq!(a.source_span, b.source_span);
        assert_eq!(a.field_origins, b.field_origins);
    }
}
#[test]
fn resident_rich_sidecars_rebind_shifted_include_occurrence_and_match_fresh() {
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap()
    .with_bootstrap_catalog()
    .unwrap();
    let memo = crate::lowering_memo::ProcedureMemo::new(1);
    let old = run(
        &Source {
            prefix: false,
            changed: false,
        },
        &engine,
        Some(&memo),
    );
    assert!(!old.code.modified_instances.is_empty());
    assert!(!old.source_helpers.is_empty());
    assert!(old
        .source_helpers
        .iter()
        .any(|helper| !helper.code.modified_instances.is_empty()));
    let mut initial_entries = 0;
    memo.values.visit_storage(|view| {
        if let dm_session::ArtifactStorageView::Store { entries, .. } = view {
            initial_entries = entries;
        }
    });
    assert!(
        initial_entries > 0,
        "first rich procedure was not populated; resident_dropped={}",
        memo.counts
            .resident_dropped
            .load(std::sync::atomic::Ordering::Relaxed)
    );
    let source = Source {
        prefix: true,
        changed: false,
    };
    let current = run(&source, &engine, Some(&memo));
    assert!(
        memo.counts
            .resident_hits
            .load(std::sync::atomic::Ordering::Relaxed)
            > 0,
        "current memo admission: {:?}",
        memo.explain()
    );
    assert_ne!(
        old.origin.source.include_occurrence,
        current.origin.source.include_occurrence
    );
    assert_ne!(old.origin.expanded_span, current.origin.expanded_span);
    same_current(&current, &run(&source, &engine, None));
    let hits = memo
        .counts
        .resident_hits
        .load(std::sync::atomic::Ordering::Relaxed);
    let changed = Source {
        prefix: true,
        changed: true,
    };
    let current = run(&changed, &engine, Some(&memo));
    assert_eq!(
        hits,
        memo.counts
            .resident_hits
            .load(std::sync::atomic::Ordering::Relaxed)
    );
    same_current(&current, &run(&changed, &engine, None));
}

#[test]
fn checked_rich_sidecar_body_operation_is_not_a_cache_miss_and_retry_preserves_current_words() {
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap()
    .with_bootstrap_catalog()
    .unwrap();
    let seed = engine.frontend_seed();
    let queries = Arc::new(crate::query_db::QueryDb::default());
    let front = dm_tree::frontend::build_with_config(
        Path::new("project.dme"),
        &Source {
            prefix: false,
            changed: false,
        },
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap()
    .with_body_queries(queries.clone());
    let (host, _) = crate::request_runner::runner_facts::prepare(&front, &engine).unwrap();
    let startup = crate::startup::capture(&front).unwrap();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let abi =
        crate::driver_facts::prepare_pinned_source_abi_with_startup_on_executor_with_artifacts(
            &front, &engine, &host, &startup, None, &executor, None,
        )
        .unwrap();
    assert!(abi.prepared.diagnostics.is_empty());
    let policy = crate::driver_facts::FrozenPreparedPolicy::new(&front, &abi.prepared).unwrap();
    let body = &front.bodies[0];
    let capture = RefCell::new(MemoCapture::default());
    let arena = dm_tree::frontend::BodyArena::new_typed(
        &front,
        dm_codegen_byond::typed_statements_supported_for_capture,
    );
    let previous = lower_one_captured(
        &front,
        body,
        &host,
        &policy,
        &arena,
        LoweringCapture {
            startup: Some(&startup),
            capture: Some(&capture),
            ready: None,
            capture_references: false,
            current: None,
        },
    )
    .unwrap();
    assert!(!previous.code.modified_instances.is_empty());
    assert!(!previous.source_helpers.is_empty());
    let debug = crate::lowering_memo::rebase_debug(&front, body, &capture.borrow().debug).unwrap();
    let prepared = &abi.prepared.units()[0].1;
    assert!(queries.db().evict_values(&[dm_query::Kind(4)]) > 0);
    let arena = dm_tree::frontend::BodyArena::new_typed(
        &front,
        dm_codegen_byond::typed_statements_supported_for_capture,
    );
    let schedule =
        queries.fail_body_syntax_after_for_test(0, std::io::Error::from_raw_os_error(1450));
    match rebind_checked(
        &previous,
        &front,
        body,
        &arena,
        &host,
        prepared,
        debug.clone(),
    )
    .err()
    .expect("actual original reissue demand failed")
    {
        LoweringFailure::Operational(error) => assert_eq!(error.raw_os_error(), Some(1450)),
        other => panic!("cache operation became miss/diagnostic: {other:?}"),
    }
    drop(schedule);
    let current = rebind_checked(&previous, &front, body, &arena, &host, prepared, debug)
        .unwrap()
        .expect("same current sidecar must recover");
    same_current(&current, &previous);
}
