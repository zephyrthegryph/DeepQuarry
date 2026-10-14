use super::*;

#[test]
fn completion_consumes_units_and_preserves_authenticated_source_order() {
    let frontend = frontend(
        "/proc/first()\n    return 1\n/proc/second()\n    return 2\n/proc/third()\n    return 3\n",
    );
    let expected = source_unit_roster(&frontend).unwrap();
    let executor = dm_exec::BuildExecutor::new(2).unwrap();
    let bodies = dm_tree::frontend::BodyArena::new(&frontend);
    let worker_ids = std::sync::Mutex::new(std::collections::HashSet::new());
    let batch = lower_frontend_completed_on_execution(
        &frontend,
        &Host,
        &NoParameters,
        LoweringConfig {
            workers: 2,
            max_chunk: 1,
        },
        None,
        None,
        LoweringExecution::new(&executor, &bodies),
        &|unit| {
            worker_ids
                .lock()
                .unwrap()
                .insert(std::thread::current().id());
            assert!(unit.require_production_abi().is_err());
            Ok::<_, String>(unit.code.procedure.code.items.len())
        },
    );
    assert!(batch.diagnostics.is_empty(), "{:?}", batch.diagnostics);
    assert!(batch.completion_errors.is_empty());
    assert_eq!(batch.units.len(), expected.len());
    assert!(batch.identity_index().is_ok());
    for (actual, expected) in batch.units.iter().zip(expected) {
        assert_eq!(actual.identity, expected.identity);
        assert_eq!(actual.effective, expected.effective);
        assert!(actual.value > 0);
    }
    let worker_ids = worker_ids.into_inner().unwrap();
    assert!(!worker_ids.contains(&std::thread::current().id()));
    assert!(worker_ids.len() <= 2);
    for body in frontend.bodies.iter() {
        assert!(bodies.with_parsed(body, |_| ()).is_err());
    }
}

#[test]
fn completion_errors_keep_source_order_and_do_not_drop_successful_siblings() {
    let frontend = frontend(
        "/proc/first()\n    return 1\n/proc/second()\n    return 2\n/proc/third()\n    return 3\n",
    );
    let expected = source_unit_roster(&frontend).unwrap();
    let executor = dm_exec::BuildExecutor::new(3).unwrap();
    let bodies = dm_tree::frontend::BodyArena::new(&frontend);
    let batch = lower_frontend_completed_on_execution(
        &frontend,
        &Host,
        &NoParameters,
        LoweringConfig {
            workers: 3,
            max_chunk: 1,
        },
        None,
        None,
        LoweringExecution::new(&executor, &bodies),
        &|unit| {
            if unit.identity.name == SymbolId::of("second") {
                Ok(unit.identity)
            } else {
                Err(unit.identity)
            }
        },
    );
    assert!(batch.diagnostics.is_empty(), "{:?}", batch.diagnostics);
    assert_eq!(batch.units.len(), 1);
    assert_eq!(batch.units[0].identity, expected[1].identity);
    assert_eq!(batch.completion_errors.len(), 2);
    assert_eq!(batch.completion_errors[0].1, expected[0].identity);
    assert_eq!(batch.completion_errors[1].1, expected[2].identity);
    assert!(
        batch.completion_errors[0].0.expanded_span.start
            < batch.completion_errors[1].0.expanded_span.start
    );
}
