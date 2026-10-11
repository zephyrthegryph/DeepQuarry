use super::*;
use std::{
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
};
static NEXT: AtomicU64 = AtomicU64::new(0);
struct Temp(PathBuf);
impl Temp {
    fn new() -> Self {
        let base = if cfg!(windows) {
            PathBuf::from("E:/dq-cache/dmb-protocol-checks")
        } else {
            std::env::temp_dir()
        };
        std::fs::create_dir_all(&base).unwrap();
        let path = base.join(format!(
            "initializer-anonymous-verify-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir(&path).unwrap();
        Self(path)
    }
}
impl Drop for Temp {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn run(
    frontend: &ColdFrontend,
    plan: &InitializerPlan,
    memo: &crate::lowering_memo::ProcedureMemo,
) -> Result<LoweredInitializers, InitializerLoweringError> {
    let host = frontend.snapshot.tree.as_ref();
    let evaluator = crate::driver_facts::DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: host,
        symbols: plan.symbols.as_ref(),
    };
    super::super::lower_plan(
        (frontend, plan),
        &evaluator,
        host,
        None,
        true,
        super::super::LowerOptions {
            allocation: None,
            classification: None,
            observer: None,
            memo: Some(memo),
            executor: None,
            parallel: None,
        },
    )
}
#[test]
fn actual_one_shot_initializer_disk_hit_verifies_success_and_rejects_stale_failure() {
    let root = Temp::new();
    let cache = dm_cache::Cache::open(&root.0, dm_cache::Limits::default()).unwrap();
    let frontend = dm_tree::frontend::build(
        Path::new("verify.dme"),
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
    let writer = crate::lowering_memo::ProcedureMemo::with_disk_only(
        37,
        Arc::new(cache.snapshot().unwrap()),
    );
    let first = run(&frontend, plan, &writer).unwrap();
    assert_eq!(first.units.len(), 1);
    let records = writer.take_pending();
    assert!(
        !records.is_empty(),
        "real no-daemon producer must emit transport"
    );
    cache.publish(&records).unwrap();
    let reader = crate::lowering_memo::ProcedureMemo::with_disk_only(
        37,
        Arc::new(cache.snapshot().unwrap()),
    )
    .with_all_procedure_verification();
    let warm = run(&frontend, plan, &reader).unwrap();
    assert_eq!(reader.anonymous_initializer_verification_counts(), (1, 0));
    assert!(crate::lowering_memo_wire::verification_code_equal(
        &first.units[0].code,
        &warm.units[0].code
    ));
    assert_eq!(first.units[0].debug_origins, warm.units[0].debug_origins);
    let group = &first.classified.groups[0];
    let key = key(
        37,
        &first.classified,
        group,
        None,
        &first.units[0].debug_origins,
    )
    .unwrap();
    let host = frontend.snapshot.tree.as_ref();
    let recorder = crate::lowering_memo::RecordingResolver::new(host);
    for &index in &group.writes {
        let write = &first.classified.writes[index].write;
        recorder.resolve(dm_ir::ResolveQuery::Ancestry(write.lexical_owner));
        if let Some(identity) = write.lexical_procedure {
            recorder.record_occurrence(identity);
        }
    }
    fragments::verify::assembly(
        &first.classified,
        group,
        dm_codegen_byond::initializer::InitializerContext {
            symbols: plan.symbols.as_ref(),
            resource_search_context: None,
            debug: None,
        },
        &recorder,
    )
    .unwrap();
    // Deliberately corrupt the outcome while keeping a fully admitted current ledger.
    let errors = [dm_codegen_byond::LowerError {
        statement: "value".into(),
        reason: "stale cached rejection".into(),
        kind: dm_codegen_byond::LowerErrorKind::SourceError,
        span: Some(dm_codegen_byond::LowerSpan { start: 0, end: 0 }),
        primary_anchor: None,
        related: vec![dm_codegen_byond::LowerRelated {
            message: "stale previous definition".into(),
            span: dm_codegen_byond::LowerSpan { start: 0, end: 0 },
        }],
    }];
    let payload = crate::lowering_memo_wire::encode_failure(
        &key,
        None,
        &recorder.reads(),
        &recorder.domain_receipts(),
        &errors,
    )
    .unwrap();
    cache
        .publish(&[dm_cache::Record {
            key: crate::lowering_memo::ProcedureMemo::record_key(&key),
            symbols: Vec::new(),
            payload: dm_cache::encode_variants(&[payload]).unwrap().into(),
        }])
        .unwrap();
    let reader = crate::lowering_memo::ProcedureMemo::with_disk_only(
        37,
        Arc::new(cache.snapshot().unwrap()),
    )
    .with_all_procedure_verification();
    let error = run(&frontend, plan, &reader)
        .err()
        .expect("admitted stale failure must fail closed");
    assert!(
        matches!(error, InitializerLoweringError::Invariant(ref message) if message.contains("cached failure became current success"))
    );
    assert_eq!(reader.anonymous_initializer_verification_counts(), (1, 1));
}

#[test]
fn actual_anonymous_failure_hit_compares_current_primary_and_related_diagnostics() {
    struct MissingCall<'a>(&'a dm_tree::SemanticTree);
    impl Resolver for MissingCall<'_> {
        fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
            match query {
                dm_ir::ResolveQuery::GlobalProc(name)
                    if name == dm_ir::SymbolId::of("missing_call") =>
                {
                    dm_ir::ResolvedMeaning::Missing
                }
                dm_ir::ResolveQuery::HasMemberProc { owner: _, name }
                    if name == dm_ir::SymbolId::of("missing_call") =>
                {
                    dm_ir::ResolvedMeaning::Presence(false)
                }
                _ => dm_ir::Resolver::resolve(self.0, query),
            }
        }
    }
    let root = Temp::new();
    let cache = dm_cache::Cache::open(&root.0, dm_cache::Limits::default()).unwrap();
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
        super::super::lower_plan(
            (&frontend, plan),
            &evaluator,
            &host,
            None,
            true,
            super::super::LowerOptions {
                allocation: None,
                classification: None,
                observer: None,
                memo: Some(memo),
                executor: None,
                parallel: None,
            },
        )
    };
    let writer = crate::lowering_memo::ProcedureMemo::with_disk_only(
        37,
        Arc::new(cache.snapshot().unwrap()),
    );
    let initial = invoke(&writer)
        .err()
        .expect("actual producer must reject the fixture's certified missing call");
    let InitializerLoweringError::Diagnostics(initial) = initial else {
        panic!("expected source-bound producer diagnostics");
    };
    let records = writer.take_pending();
    assert!(
        !records.is_empty(),
        "actual failure must be persisted by ordinary producer"
    );
    cache.publish(&records).unwrap();
    let reader = crate::lowering_memo::ProcedureMemo::with_disk_only(
        37,
        Arc::new(cache.snapshot().unwrap()),
    )
    .with_all_procedure_verification();
    let replay = invoke(&reader).err().expect("failure stays a failure");
    let InitializerLoweringError::Diagnostics(replay) = replay else {
        panic!("verified failure must preserve current diagnostics");
    };
    assert!(crate::initializer_diagnostics::verification_diagnostics_equal(&initial, &replay));
    assert_eq!(reader.anonymous_initializer_verification_counts(), (1, 0));
    let mut changed = replay.clone();
    let origin = changed[0].origin.clone();
    changed[0].related.push(crate::lowering::RelatedDiagnostic {
        origin,
        message: "unexpected old note".into(),
    });
    assert!(!crate::initializer_diagnostics::verification_diagnostics_equal(&replay, &changed));
}
