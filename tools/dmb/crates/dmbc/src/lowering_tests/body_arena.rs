use super::*;

#[test]
fn shared_startup_body_arena_lowers_same_words_and_releases_every_body() {
    let frontend = frontend(
        "/proc/first()\n    var/static/unused = 1\n    return 7\n/proc/second()\n    return 2\n",
    );
    let executor = dm_exec::BuildExecutor::new(2).unwrap();
    let bodies = dm_tree::frontend::BodyArena::new(&frontend);
    let startup =
        crate::startup::capture_with_executor_and_bodies(&frontend, &[], &executor, &bodies)
            .unwrap();
    let first = &frontend.bodies[0];
    let inspected = bodies
        .with_parsed(first, |parsed| {
            parsed.item() as *const dm_syntax::Item as usize
        })
        .unwrap();
    let again = bodies
        .with_parsed(first, |parsed| {
            parsed.item() as *const dm_syntax::Item as usize
        })
        .unwrap();
    assert_eq!(inspected, again);
    let host = startup
        .resolver(&frontend, frontend.snapshot.tree.as_ref())
        .unwrap();
    let shared = lower_frontend_with_statics_on_executor_and_bodies(
        &frontend,
        &host,
        &NoParameters,
        LoweringConfig {
            workers: 2,
            max_chunk: 1,
        },
        &startup,
        LoweringExecution::new(&executor, &bodies),
    );
    let reference = lower_frontend_with_statics_on_executor(
        &frontend,
        &host,
        &NoParameters,
        LoweringConfig {
            workers: 2,
            max_chunk: 1,
        },
        &startup,
        &executor,
    );
    assert!(shared.diagnostics.is_empty(), "{:?}", shared.diagnostics);
    assert!(
        reference.diagnostics.is_empty(),
        "{:?}",
        reference.diagnostics
    );
    assert_eq!(shared.units.len(), reference.units.len());
    for (actual, expected) in shared.units.iter().zip(&reference.units) {
        assert_eq!(actual.identity, expected.identity);
        assert_eq!(actual.code.procedure, expected.code.procedure);
        assert_eq!(actual.debug_origins, expected.debug_origins);
    }
    for body in frontend.bodies.iter() {
        assert!(bodies.with_parsed(body, |_| ()).is_err());
    }
}

#[test]
fn foreign_body_arena_produces_source_ordered_internal_diagnostics() {
    let first = frontend("/proc/first()\n    return 7\n/proc/second()\n    return 2\n");
    let foreign = frontend("/proc/first()\n    return 7\n/proc/second()\n    return 2\n");
    let executor = dm_exec::BuildExecutor::new(2).unwrap();
    let bodies = dm_tree::frontend::BodyArena::new(&foreign);
    let startup = crate::startup::capture(&first).unwrap();
    let host = startup
        .resolver(&first, first.snapshot.tree.as_ref())
        .unwrap();
    let result = lower_frontend_with_statics_on_executor_and_bodies(
        &first,
        &host,
        &NoParameters,
        LoweringConfig {
            workers: 2,
            max_chunk: 1,
        },
        &startup,
        LoweringExecution::new(&executor, &bodies),
    );
    assert!(result.units.is_empty());
    assert_eq!(result.diagnostics.len(), first.bodies.len());
    for (diagnostic, body) in result.diagnostics.iter().zip(first.bodies.iter()) {
        assert_eq!(diagnostic.kind, DiagnosticKind::Internal);
        assert_eq!(diagnostic.origin.path, body.source.path);
        assert_eq!(diagnostic.origin.line, body.source.line);
        assert_eq!(diagnostic.origin.span, body.source.span);
        assert_eq!(diagnostic.origin.include_chain, body.source.include_chain);
        assert!(diagnostic.message.contains("issuance"));
    }
}

#[test]
fn resident_replay_discards_request_body_slots_and_keeps_output_parity() {
    let frontend = frontend("/proc/first()\n    return 7\n/proc/second()\n    return 2\n");
    let executor = dm_exec::BuildExecutor::new(2).unwrap();
    let startup = crate::startup::capture(&frontend).unwrap();
    let host = startup
        .resolver(&frontend, frontend.snapshot.tree.as_ref())
        .unwrap();
    let memo = crate::lowering_memo::ProcedureMemo::new(42);
    let cold_bodies = dm_tree::frontend::BodyArena::new(&frontend);
    let cold = lower_frontend_with_memo_on_executor_and_bodies(
        &frontend,
        &host,
        &NoParameters,
        LoweringConfig::default(),
        &startup,
        &memo,
        LoweringExecution::new(&executor, &cold_bodies),
    );
    let warm_bodies = dm_tree::frontend::BodyArena::new(&frontend);
    let warm = lower_frontend_with_memo_on_executor_and_bodies(
        &frontend,
        &host,
        &NoParameters,
        LoweringConfig::default(),
        &startup,
        &memo,
        LoweringExecution::new(&executor, &warm_bodies),
    );
    assert!(cold.diagnostics.is_empty(), "{:?}", cold.diagnostics);
    assert!(warm.diagnostics.is_empty(), "{:?}", warm.diagnostics);
    assert_eq!(
        memo.counts
            .resident_hits
            .load(std::sync::atomic::Ordering::Relaxed),
        2
    );
    for (actual, expected) in warm.units.iter().zip(&cold.units) {
        assert_eq!(actual.code.procedure, expected.code.procedure);
    }
    for body in frontend.bodies.iter() {
        assert!(warm_bodies.with_parsed(body, |_| ()).is_err());
    }
}
