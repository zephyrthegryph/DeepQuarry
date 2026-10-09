use super::*;
use crate::driver_facts::{prepare_pinned_source_abi, FrozenPreparedPolicy};

#[test]
fn selected_reference_capture_reuses_admitted_facts_and_preserves_normal_words() {
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap();
    let seed = engine.frontend_seed();
    let frontend = dm_tree::frontend::build_with_config(
        Path::new("project.dme"),
        &Source("/proc/p()\n    var/x = 2\n    return x\n"),
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
    let abi = prepare_pinned_source_abi(&frontend, &engine, &host, None, 1).unwrap();
    let policy = FrozenPreparedPolicy::new(&frontend, &abi.prepared).unwrap();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let memo = crate::lowering_memo::ProcedureMemo::new(99);
    let run = |capture| {
        let bodies = dm_tree::frontend::BodyArena::new_typed(&frontend, |_| true);
        let mut execution = LoweringExecution::new(&executor, &bodies);
        if capture {
            execution = execution.with_reference_capture();
        }
        lower_frontend_with_memo_on_executor_and_bodies(
            &frontend,
            &host,
            &policy,
            LoweringConfig::default(),
            &startup,
            &memo,
            execution,
        )
    };
    let normal = run(false);
    let first = run(true);
    let second = run(true);
    for batch in [&normal, &first, &second] {
        assert!(batch.diagnostics.is_empty(), "{:?}", batch.diagnostics);
        assert_eq!(batch.units.len(), 1);
    }
    assert!(normal.units[0].selected_references.is_none());
    assert_eq!(
        normal.units[0].code.procedure.code,
        first.units[0].code.procedure.code
    );
    let first = first.units[0].selected_references.as_ref().unwrap();
    let second = second.units[0].selected_references.as_ref().unwrap();
    assert!(!first.complete);
    assert!(first
        .references
        .iter()
        .any(|reference| reference.name == dm_ir::SymbolId::of("x")
            && matches!(reference.meaning, dm_ir::SelectedMeaning::Local(_))));
    assert!(
        Arc::ptr_eq(first, second),
        "admitted current facts should share immutable backing"
    );
    let selected = [&frontend.bodies[0]];
    let bodies = dm_tree::frontend::BodyArena::new_typed(&frontend, |_| true);
    let queried = lower_frontend_with_memo_on_executor_and_bodies(
        &frontend,
        &host,
        &policy,
        LoweringConfig::default(),
        &startup,
        &memo,
        LoweringExecution::new(&executor, &bodies)
            .with_reference_capture()
            .with_selected_bodies(&selected),
    );
    assert!(queried.diagnostics.is_empty(), "{:?}", queried.diagnostics);
    assert_eq!(queried.units.len(), 1);
    assert!(Arc::ptr_eq(
        first,
        queried.units[0].selected_references.as_ref().unwrap()
    ));
    let query_bodies = dm_tree::frontend::BodyArena::new_typed(&frontend, |_| true);
    let current = crate::selected_query::query(
        &frontend,
        &host,
        &policy,
        LoweringConfig::default(),
        &startup,
        &memo,
        LoweringExecution::new(&executor, &query_bodies).with_selected_bodies(&selected),
    )
    .unwrap();
    assert_eq!(current.len(), 1);
    assert!(!current[0].complete());
    assert_eq!(current[0].unavailable_coordinates(), 0);
    assert!(current[0].references().iter().any(|reference| {
        reference.name == dm_ir::SymbolId::of("x")
            && matches!(reference.meaning, dm_ir::SelectedMeaning::Local(_))
            && reference.expanded_span.start >= frontend.bodies[0].expanded_span.start
            && reference.expanded_span.end <= frontend.bodies[0].expanded_span.end
    }));
    let mut export = Vec::new();
    assert!(current[0].write_jsonl(&mut export).unwrap() > 0);
    assert!(std::str::from_utf8(&export).unwrap().lines().all(|line| {
        serde_json::from_str::<serde_json::Value>(line).unwrap()["semantic_resolution_complete"]
            != true
    }));
    let duplicate = [&frontend.bodies[0], &frontend.bodies[0]];
    let foreign = super::frontend("/proc/foreign()\n    return 5\n");
    let foreign_selection = [&foreign.bodies[0]];
    for selection in [&duplicate[..], &foreign_selection[..]] {
        let bodies = dm_tree::frontend::BodyArena::new_typed(&frontend, |_| true);
        let result = lower_frontend_with_memo_on_executor_and_bodies(
            &frontend,
            &host,
            &policy,
            LoweringConfig::default(),
            &startup,
            &memo,
            LoweringExecution::new(&executor, &bodies)
                .with_reference_capture()
                .with_selected_bodies(selection),
        );
        assert!(result.units.is_empty());
        assert!(!result.diagnostics.is_empty());
        assert!(result
            .diagnostics
            .iter()
            .all(|diagnostic| diagnostic.message.contains("unique current body issuance")));
    }
}
