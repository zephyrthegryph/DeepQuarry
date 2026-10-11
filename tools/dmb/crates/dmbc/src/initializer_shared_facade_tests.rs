//! Standalone memo callers execute the same shared initializer producers.
use super::*;
use std::path::Path;
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
#[test]
fn standalone_memo_shared_initializer_matches_cold_oracle_without_spooling() {
    let frontend = dm_tree::frontend::build(
        Path::new("shared.dme"),
        &Source("/datum/example\n    var/list/value = list(7)\n"),
        &Default::default(),
        1,
    )
    .unwrap();
    let declarations = dm_tree::initializers::capture_declaration_plan(
        &frontend.snapshot,
        &frontend.emission_order,
    )
    .unwrap();
    let plan = declarations.plan();
    let host = frontend.snapshot.tree.as_ref();
    let evaluator = crate::driver_facts::DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: host,
        symbols: plan.symbols.as_ref(),
    };
    let cold = lower(&frontend, plan, &evaluator, host, None).unwrap();
    let memo = crate::lowering_memo::ProcedureMemo::new(37).with_all_procedure_verification();
    let shared = lower_plan(
        (&frontend, plan),
        &evaluator,
        host,
        None,
        true,
        LowerOptions {
            allocation: None,
            classification: None,
            observer: None,
            memo: Some(&memo),
            executor: None,
            parallel: None,
        },
    )
    .unwrap();
    assert_eq!(cold.units.len(), shared.units.len());
    for (cold, shared) in cold.units.iter().zip(&shared.units) {
        assert_eq!(cold.write_ordinals, shared.write_ordinals);
        assert!(crate::lowering_memo_wire::verification_code_equal(
            cold.code.as_ref(),
            shared.code.as_ref()
        ));
    }
    assert!(memo.take_pending().is_empty());
}
#[test]
fn standalone_memo_shared_initializer_failure_keeps_current_primary_and_related_diagnostics() {
    struct MissingCall<'a>(&'a dm_tree::SemanticTree);
    impl Resolver for MissingCall<'_> {
        fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
            match query {
                dm_ir::ResolveQuery::GlobalProc(name)
                | dm_ir::ResolveQuery::Proc {
                    owner: _,
                    name,
                    verb: _,
                } if name == dm_ir::SymbolId::of("missing_call") => dm_ir::ResolvedMeaning::Missing,
                dm_ir::ResolveQuery::HasMemberProc { owner: _, name }
                    if name == dm_ir::SymbolId::of("missing_call") =>
                {
                    dm_ir::ResolvedMeaning::Presence(false)
                }
                _ => dm_ir::Resolver::resolve(self.0, query),
            }
        }
    }
    let frontend = dm_tree::frontend::build(
        Path::new("failure.dme"),
        &Source("var/value = missing_call()\n"),
        &Default::default(),
        1,
    )
    .unwrap();
    let declarations = dm_tree::initializers::capture_declaration_plan(
        &frontend.snapshot,
        &frontend.emission_order,
    )
    .unwrap();
    let plan = declarations.plan();
    let host = MissingCall(frontend.snapshot.tree.as_ref());
    let evaluator = crate::driver_facts::DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: &host,
        symbols: plan.symbols.as_ref(),
    };
    let invoke = |memo| {
        super::lower_plan(
            (&frontend, plan),
            &evaluator,
            &host,
            None,
            true,
            super::LowerOptions {
                allocation: None,
                classification: None,
                observer: None,
                memo: Some(memo),
                executor: None,
                parallel: None,
            },
        )
    };
    let writer = crate::lowering_memo::ProcedureMemo::new(37);
    let initial = invoke(&writer)
        .err()
        .expect("actual producer must reject the fixture's certified missing call");
    let InitializerLoweringError::Diagnostics(initial) = initial else {
        panic!("expected source-bound producer diagnostics, got {initial:?}");
    };
    assert!(
        writer.take_pending().is_empty(),
        "standalone API has no authenticated portable transport"
    );
    let reader = crate::lowering_memo::ProcedureMemo::new(37).with_all_procedure_verification();
    let replay = invoke(&reader).err().expect("failure stays a failure");
    let InitializerLoweringError::Diagnostics(replay) = replay else {
        panic!("verified failure must preserve current diagnostics");
    };
    assert!(crate::initializer_diagnostics::verification_diagnostics_equal(&initial, &replay));
    let shifted = dm_tree::frontend::build(
        Path::new("failure.dme"),
        &Source("\n\n\nvar/value = missing_call()\n"),
        &Default::default(),
        2,
    )
    .unwrap();
    let shifted_declarations =
        dm_tree::initializers::capture_declaration_plan(&shifted.snapshot, &shifted.emission_order)
            .unwrap();
    let shifted_plan = shifted_declarations.plan();
    let shifted_host = MissingCall(shifted.snapshot.tree.as_ref());
    let shifted_evaluator = crate::driver_facts::DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: &shifted_host,
        symbols: shifted_plan.symbols.as_ref(),
    };
    let cold = lower(
        &shifted,
        shifted_plan,
        &shifted_evaluator,
        &shifted_host,
        None,
    )
    .err()
    .expect("shifted cold source fails");
    let shared = lower_plan(
        (&shifted, shifted_plan),
        &shifted_evaluator,
        &shifted_host,
        None,
        true,
        LowerOptions {
            allocation: None,
            classification: None,
            observer: None,
            memo: Some(&reader),
            executor: None,
            parallel: None,
        },
    )
    .err()
    .expect("shifted shared source fails");
    let (
        InitializerLoweringError::Diagnostics(cold),
        InitializerLoweringError::Diagnostics(shared),
    ) = (cold, shared)
    else {
        panic!("both paths must preserve typed current source diagnostics");
    };
    assert!(crate::initializer_diagnostics::verification_diagnostics_equal(&cold, &shared));
    assert!(!crate::initializer_diagnostics::verification_diagnostics_equal(&initial, &shared));
    let mut changed = replay.clone();
    let origin = changed[0].origin.clone();
    changed[0].related.push(crate::lowering::RelatedDiagnostic {
        origin,
        message: "unexpected old note".into(),
    });
    assert!(!crate::initializer_diagnostics::verification_diagnostics_equal(&replay, &changed));
}
