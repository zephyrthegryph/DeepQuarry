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

#[test]
fn checked_completion_body_operation_returns_no_batch_and_same_source_recovers() {
    use std::sync::atomic::{AtomicUsize, Ordering};
    let db = Arc::new(crate::query_db::QueryDb::default());
    let frontend = frontend("/proc/probe()\n    return 7\n").with_body_queries(db.clone());
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let bodies = dm_tree::frontend::BodyArena::new(&frontend);
    let completed = AtomicUsize::new(0);
    let complete = |input: CompletedInput| {
        completed.fetch_add(1, Ordering::Relaxed);
        Ok::<_, String>(input.into_lowered().code.procedure)
    };
    // The genuine Kind4 fault hook is test-thread-local. Install it on the
    // actual single executor worker which performs the original body demand,
    // rather than silently scheduling a coordinator-only hook.
    let coordinator = std::thread::current().id();
    let error = executor.install(|| {
        assert_ne!(std::thread::current().id(), coordinator);
        let _scheduled =
            db.fail_body_syntax_after_for_test(0, std::io::Error::from_raw_os_error(1450));
        lower_frontend_completed_input_checked_on_execution(
            &frontend,
            &Host,
            &NoParameters,
            LoweringConfig {
                workers: 1,
                max_chunk: 1,
            },
            None,
            None,
            LoweringExecution::new(&executor, &bodies),
            false,
            &complete,
        )
        .err()
        .expect("actual original body IO")
    });
    assert_eq!(error.raw_os_error(), Some(1450));
    assert_eq!(completed.load(Ordering::Relaxed), 0);
    let batch = lower_frontend_completed_input_checked_on_execution(
        &frontend,
        &Host,
        &NoParameters,
        LoweringConfig {
            workers: 1,
            max_chunk: 1,
        },
        None,
        None,
        LoweringExecution::new(&executor, &bodies),
        false,
        &complete,
    )
    .unwrap();
    assert!(batch.diagnostics.is_empty());
    assert!(batch.completion_errors.is_empty());
    assert_eq!(batch.units.len(), 1);
    assert_eq!(completed.load(Ordering::Relaxed), 1);
    let legacy_bodies = dm_tree::frontend::BodyArena::new(&frontend);
    let legacy = lower_frontend_completed_input_on_execution(
        &frontend,
        &Host,
        &NoParameters,
        LoweringConfig {
            workers: 1,
            max_chunk: 1,
        },
        None,
        None,
        LoweringExecution::new(&executor, &legacy_bodies),
        false,
        &|input| Ok::<_, String>(input.into_lowered().code.procedure),
    );
    assert_eq!(batch.units[0].value, legacy.units[0].value);
}
#[test]
fn checked_completion_genuine_source_rejection_stays_ordered_diagnostics() {
    let frontend = frontend("/proc/probe()\n    var/value=1\n    var/value=2\n");
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let checked = dm_tree::frontend::BodyArena::new(&frontend);
    let legacy = dm_tree::frontend::BodyArena::new(&frontend);
    let complete = |_: CompletedInput| Ok::<_, String>(());
    let actual = lower_frontend_completed_input_checked_on_execution(
        &frontend,
        &Host,
        &NoParameters,
        LoweringConfig {
            workers: 1,
            max_chunk: 1,
        },
        None,
        None,
        LoweringExecution::new(&executor, &checked),
        false,
        &complete,
    )
    .unwrap();
    let old = lower_frontend_completed_input_on_execution(
        &frontend,
        &Host,
        &NoParameters,
        LoweringConfig {
            workers: 1,
            max_chunk: 1,
        },
        None,
        None,
        LoweringExecution::new(&executor, &legacy),
        false,
        &complete,
    );
    assert!(!actual.diagnostics.is_empty());
    assert!(actual.units.is_empty());
    assert!(
        crate::initializer_diagnostics::verification_diagnostics_equal(
            &actual.diagnostics,
            &old.diagnostics
        )
    );
}
#[test]
fn checked_completion_cancelled_empty_input_refuses_and_new_request_recovers() {
    let frontend = frontend("");
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let bodies = dm_tree::frontend::BodyArena::new(&frontend);
    let token = crate::daemon::control::Cancellation::default();
    let binding = crate::daemon::control::bind_with_deadline(
        token.clone(),
        std::time::Instant::now() + std::time::Duration::from_secs(300),
    );
    token.cancel();
    let error = lower_frontend_completed_input_checked_on_execution(
        &frontend,
        &Host,
        &NoParameters,
        LoweringConfig {
            workers: 1,
            max_chunk: 1,
        },
        None,
        None,
        LoweringExecution::new(&executor, &bodies),
        false,
        &|_| Ok::<_, String>(()),
    )
    .err()
    .expect("empty request still checks actual cancellation");
    assert_eq!(error.kind(), std::io::ErrorKind::Interrupted);
    drop(binding);
    let batch = lower_frontend_completed_input_checked_on_execution(
        &frontend,
        &Host,
        &NoParameters,
        LoweringConfig {
            workers: 1,
            max_chunk: 1,
        },
        None,
        None,
        LoweringExecution::new(&executor, &bodies),
        false,
        &|_| Ok::<_, String>(()),
    )
    .unwrap();
    assert!(
        batch.units.is_empty()
            && batch.diagnostics.is_empty()
            && batch.completion_errors.is_empty()
    );
}
#[test]
fn checked_completion_late_callback_cancel_never_returns_completed_batch() {
    use std::sync::atomic::{AtomicUsize, Ordering};
    let frontend = frontend("/proc/probe()\n    return 7\n");
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let bodies = dm_tree::frontend::BodyArena::new(&frontend);
    let token = crate::daemon::control::Cancellation::default();
    let binding = crate::daemon::control::bind_with_deadline(
        token.clone(),
        std::time::Instant::now() + std::time::Duration::from_secs(300),
    );
    let completed = AtomicUsize::new(0);
    let error = lower_frontend_completed_input_checked_on_execution(
        &frontend,
        &Host,
        &NoParameters,
        LoweringConfig {
            workers: 1,
            max_chunk: 1,
        },
        None,
        None,
        LoweringExecution::new(&executor, &bodies),
        false,
        &|_| {
            completed.fetch_add(1, Ordering::Relaxed);
            token.cancel();
            Ok::<_, String>(())
        },
    )
    .err()
    .expect("cancellation after actual completion must precede returning success");
    assert_eq!(error.kind(), std::io::ErrorKind::Interrupted);
    assert_eq!(completed.load(Ordering::Relaxed), 1);
    drop(binding);
    let retry = dm_tree::frontend::BodyArena::new(&frontend);
    let batch = lower_frontend_completed_input_checked_on_execution(
        &frontend,
        &Host,
        &NoParameters,
        LoweringConfig {
            workers: 1,
            max_chunk: 1,
        },
        None,
        None,
        LoweringExecution::new(&executor, &retry),
        false,
        &|_| Ok::<_, String>(()),
    )
    .unwrap();
    assert_eq!(batch.units.len(), 1);
    assert!(batch.diagnostics.is_empty() && batch.completion_errors.is_empty());
}
