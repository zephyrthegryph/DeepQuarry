use super::*;
use crate::initializer_policy::{
    CapturedInitializerEvaluator, EngineCapturedEvaluator, Evaluation, InitializerEvaluatorFactory,
    PreparedInitializerExpression,
};
use dm_ir::{InitializerValue, ResolveQuery, ResolvedMeaning, Resolver, SemanticValue, SymbolId};
use std::{
    path::Path,
    sync::atomic::{AtomicUsize, Ordering},
};

struct Empty;
impl Resolver for Empty {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        ResolvedMeaning::Unsupported(query)
    }
}
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
#[derive(Default)]
struct Recording {
    prepared: AtomicUsize,
    ast: AtomicUsize,
    fail_prepared: bool,
}
impl InitializerEvaluatorFactory for Recording {
    fn with_evaluator(
        &self,
        _: Option<&crate::engine::EngineSnapshot>,
        operation: &mut dyn FnMut(&dyn CapturedInitializerEvaluator),
    ) {
        operation(self);
    }
}
impl CapturedInitializerEvaluator for Recording {
    fn evaluate(&self, _: SymbolId, _: &dm_ir::SymbolicExpression) -> Result<Evaluation, String> {
        Err("legacy evaluator fallback was called".into())
    }
    fn evaluate_prepared_write(
        &self,
        _: &dm_ir::InitializerWrite,
        _: &dm_ir::SymbolicExpression,
    ) -> Result<(Evaluation, Option<PreparedInitializerExpression>), String> {
        self.prepared.fetch_add(1, Ordering::Relaxed);
        if self.fail_prepared {
            return Err("issued prepared evaluation error".into());
        }

        let mut ast = dm_syntax::parse_expression("runtime_call()").expr.unwrap();
        ast.span = dm_syntax::Span::new(123, 456);
        Ok((
            Evaluation::Runtime,
            Some(PreparedInitializerExpression::new(
                "already captured runtime source".into(),
                ast,
            )),
        ))
    }
    fn evaluate_ast_write(
        &self,
        _: &dm_ir::InitializerWrite,
        _: &dm_syntax::Expr,
        _: &str,
        _: &dm_ir::SymbolTable,
    ) -> Result<Evaluation, String> {
        self.ast.fetch_add(1, Ordering::Relaxed);
        Ok(Evaluation::Scalar(SemanticValue::NumberBits(
            21f32.to_bits(),
        )))
    }
}

#[test]
fn worker_startup_and_engine_wrappers_preserve_issued_prepared_syntax_and_ast_calls() {
    let frontend = dm_tree::frontend::build(
        Path::new("probe.dme"),
        &Source("var/value = runtime_call()\n"),
        &Default::default(),
        1,
    )
    .unwrap();
    let startup = capture(&frontend).unwrap();
    let write = &startup.plan().writes[0];
    let InitializerValue::Expression(expression) = &write.value else {
        panic!("expression");
    };
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap();
    let factory = Recording::default();
    factory.with_evaluator(None, &mut |worker| {
        let evaluator = StartupEvaluator {
            ordinary: worker, resolver: &Empty, symbols: &startup.plan().symbols,
            resource_search_context: None,
        };
        let wrapped = EngineCapturedEvaluator { engine: &engine, evaluator: &evaluator };
        let (value, prepared) = wrapped.evaluate_prepared_write(write, expression).unwrap();
        assert!(matches!(value, Evaluation::Runtime));
        let prepared = prepared.unwrap();
        assert_eq!(prepared.source(), "already captured runtime source");
        assert_eq!(prepared.ast().span, dm_syntax::Span::new(123, 456));
        assert!(matches!(wrapped.evaluate_ast_write(
            write, &prepared.ast(), &prepared.source(), &startup.plan().symbols,
        ).unwrap(), Evaluation::Scalar(SemanticValue::NumberBits(bits)) if bits == 21f32.to_bits()));
    });
    assert_eq!(factory.prepared.load(Ordering::Relaxed), 1);
    assert_eq!(factory.ast.load(Ordering::Relaxed), 1);
    let failing = Recording {
        fail_prepared: true,
        ..Default::default()
    };
    let evaluator = StartupEvaluator {
        ordinary: &failing,
        resolver: &Empty,
        symbols: &startup.plan().symbols,
        resource_search_context: None,
    };
    let wrapped = EngineCapturedEvaluator {
        engine: &engine,
        evaluator: &evaluator,
    };
    match wrapped.evaluate_prepared_write(write, expression) {
        Err(error) => assert_eq!(error, "issued prepared evaluation error"),
        Ok(_) => panic!("captured error must not be converted to fallback/runtime"),
    }
    assert_eq!(failing.prepared.load(Ordering::Relaxed), 1);
}

#[test]
fn procedure_static_prepared_and_ast_evaluation_use_captured_lexical_resolver() {
    let frontend = dm_tree::frontend::build(
        Path::new("probe.dme"),
        &Source("/proc/work()\n    var/static/const/base = 7\n    var/static/result = base\n    return result\n"),
        &Default::default(), 1,
    ).unwrap();
    let startup = capture(&frontend).unwrap();
    let resolver = startup.resolver(&frontend, &Empty).unwrap();
    let ordinary = Recording::default();
    let evaluator = StartupEvaluator {
        ordinary: &ordinary,
        resolver: &resolver,
        symbols: &startup.plan().symbols,
        resource_search_context: None,
    };
    let write = startup
        .plan()
        .writes
        .iter()
        .find(|write| {
            matches!(write.target, dm_ir::InitializerTarget::ProcedureStatic(identity)
            if identity.name == SymbolId::of("result"))
        })
        .unwrap();
    let InitializerValue::Expression(expression) = &write.value else {
        panic!("expression");
    };
    let (value, prepared) = evaluator
        .evaluate_prepared_write(write, expression)
        .unwrap();
    assert!(
        matches!(value, Evaluation::Scalar(SemanticValue::NumberBits(bits)) if bits == 7f32.to_bits())
    );
    let prepared = prepared.unwrap();
    assert_eq!(prepared.source(), "base");
    assert!(matches!(evaluator.evaluate_ast_write(
        write, &prepared.ast(), &prepared.source(), &startup.plan().symbols,
    ).unwrap(), Evaluation::Scalar(SemanticValue::NumberBits(bits)) if bits == 7f32.to_bits()));
    assert_eq!(ordinary.prepared.load(Ordering::Relaxed), 0);
    assert_eq!(ordinary.ast.load(Ordering::Relaxed), 0);
}
