use super::*;
use std::sync::atomic::{AtomicUsize, Ordering};

struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Ok("var/static/value=1+2\n".into())
    }
}
fn front(db: &Arc<crate::query_db::QueryDb>) -> dm_tree::frontend::ColdFrontend {
    let host = Arc::clone(db) as Arc<dyn dm_tree::frontend::SettingExpressionQueries>;
    dm_tree::frontend::build(std::path::Path::new("scoped-checked-initializer.dme"), &Source, &Default::default(), 1)
        .unwrap().with_setting_expression_queries(&host).unwrap()
}
fn engine() -> crate::engine::EngineSnapshot {
    crate::engine::EngineSnapshot::from_bytes(include_bytes!("../../../../fixtures/native_template.bin"), 1).unwrap()
}
fn original_failure(error: dm_tree::frontend::BodySyntaxFailure) -> InitializerFailure {
    match error {
        dm_tree::frontend::BodySyntaxFailure::Operational(actual) => InitializerFailure::Operational(actual),
        dm_tree::frontend::BodySyntaxFailure::Syntax(source) => InitializerFailure::Unsupported(source.message),
    }
}
struct Original;
impl CapturedInitializerEvaluator for Original {
    fn evaluate(&self, _: SymbolId, _: &SymbolicExpression) -> Result<Evaluation, String> {
        panic!("original checked hook cannot select a String evaluator")
    }
    fn evaluate_prepared_write_checked(&self, _: &InitializerWrite, _: &SymbolicExpression)
        -> Result<(Evaluation, Option<PreparedInitializerExpression>), InitializerFailure> {
        panic!("engine must forward original ordinal hook, not choose owned fallback")
    }
    fn evaluate_original_write_checked<'source>(
        &self, input: &dm_tree::frontend::OriginalInitializerExpressionInput<'source>, _: &InitializerWrite,
    ) -> Result<(Evaluation, Option<ScopedPreparedInitializerExpression<'source>>), InitializerFailure> {
        let root = input.expression().map_err(original_failure)?;
        Ok((Evaluation::Scalar(SemanticValue::Null), Some(ScopedPreparedInitializerExpression::from_original(root))))
    }
}
fn through_temporary_worker<'source>(
    input: &dm_tree::frontend::OriginalInitializerExpressionInput<'source>, engine: &crate::engine::EngineSnapshot,
) -> Result<ScopedPreparedInitializerExpression<'source>, InitializerFailure> {
    let worker = Original;
    let wrapper = EngineCapturedEvaluator { engine, evaluator: &worker };
    Ok(wrapper.evaluate_original_write_checked(input, input.original_write())?.1.expect("genuine original root"))
}
#[test]
fn original_checked_initializer_source_outlives_temporary_input_and_worker_without_copy() {
    let db = Arc::new(crate::query_db::QueryDb::default());
    let front = front(&db);
    let plan = dm_tree::initializers::capture_declaration_plan(&front.snapshot, &front.emission_order).unwrap();
    let engine = engine();
    let prepared = {
        let context = front.original_initializer_context(&plan).unwrap();
        let input = context.input(0).unwrap();
        through_temporary_worker(&input, &engine).unwrap()
    };
    let warm = front.original_initializer_input(&plan, 0).unwrap().expression().unwrap();
    assert!(prepared.original().unwrap().same_root(&warm));
    assert!(std::ptr::eq(prepared.ast(), warm.ast()));
    assert_eq!(&prepared.source()[prepared.ast().span.range()], "1+2");
    assert_eq!(db.db().stats(dm_query::Kind(4)).computed, 0);
}
#[test]
fn scoped_and_original_defaults_keep_exact_owned_custom_checked_hook() {
    struct Owned(AtomicUsize);
    impl CapturedInitializerEvaluator for Owned {
        fn evaluate(&self, _: SymbolId, _: &SymbolicExpression) -> Result<Evaluation, String> { panic!("owned checked override") }
        fn evaluate_prepared_write_checked(&self, _: &InitializerWrite, value: &SymbolicExpression)
            -> Result<(Evaluation, Option<PreparedInitializerExpression>), InitializerFailure> {
            assert!(!value.tokens.is_empty(), "original hook derives its authenticated row RHS");
            self.0.fetch_add(1, Ordering::Relaxed);
            Ok((Evaluation::SourceError("unchanged custom source result".into()), Some(PreparedInitializerExpression::parse("9".into()).unwrap())))
        }
    }
    let db = Arc::new(crate::query_db::QueryDb::default());let front = front(&db);
    let plan = dm_tree::initializers::capture_declaration_plan(&front.snapshot, &front.emission_order).unwrap();
    let input = front.original_initializer_input(&plan, 0).unwrap();
    let InitializerValue::Expression(value) = &input.original_write().value else { panic!("authored fixture") };
    let owned = Owned(AtomicUsize::new(0));let engine = engine();
    let wrapper = EngineCapturedEvaluator { engine: &engine, evaluator: &owned };
    for (result, prepared) in [wrapper.evaluate_scoped_write_checked(input.original_write(), value).unwrap(), wrapper.evaluate_original_write_checked(&input, input.original_write()).unwrap()] {
        assert!(matches!(result, Evaluation::SourceError(ref reason) if reason == "unchanged custom source result"));
        let prepared = prepared.unwrap();assert_eq!(prepared.source(), "9");assert!(prepared.original().is_none());
    }
    assert_eq!(owned.0.load(Ordering::Relaxed), 2);
}
#[test]
fn original_checked_engine_keeps_actual_root_cancellation_and_same_input_recovery() {
    let db = Arc::new(crate::query_db::QueryDb::default());let front = front(&db);
    let plan = dm_tree::initializers::capture_declaration_plan(&front.snapshot, &front.emission_order).unwrap();
    let input = front.original_initializer_input(&plan, 0).unwrap();let engine = engine();
    let token = crate::daemon::control::Cancellation::default();
    let binding = crate::daemon::control::bind_with_deadline(token.clone(), std::time::Instant::now() + std::time::Duration::from_secs(300));
    let schedule = db.cancel_settings_after_checkpoints_for_test(0, token);
    let error = through_temporary_worker(&input, &engine).err().expect("real original scalar producer cancellation").into_operational().unwrap();
    assert_eq!(error.kind(), std::io::ErrorKind::Interrupted);drop(schedule);drop(binding);
    let recovered = through_temporary_worker(&input, &engine).unwrap();
    assert!(recovered.original().unwrap().same_root(&input.expression().unwrap()));
    assert_eq!(db.db().stats(dm_query::Kind(4)).computed, 0);
}
