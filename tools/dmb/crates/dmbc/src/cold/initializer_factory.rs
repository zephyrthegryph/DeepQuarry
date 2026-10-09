//! Recreate the exact startup/engine evaluator stack inside each pool worker.
use crate::initializer_policy::{
    CapturedInitializerEvaluator, EngineCapturedEvaluator, InitializerEvaluatorFactory,
    ParallelEvaluator,
};

pub(super) struct StartupParallelFactory<'a> {
    pub ordinary: ParallelEvaluator<'a>,
    pub resolver: &'a dyn dm_ir::Resolver,
    pub symbols: &'a dm_ir::SymbolTable,
    pub resource_search_context: Option<u128>,
}
impl InitializerEvaluatorFactory for StartupParallelFactory<'_> {
    fn with_evaluator(
        &self,
        engine: Option<&crate::engine::EngineSnapshot>,
        operation: &mut dyn FnMut(&dyn CapturedInitializerEvaluator),
    ) {
        self.ordinary
            .factory
            .with_evaluator(self.ordinary.engine, &mut |ordinary| {
                let startup = crate::startup::StartupEvaluator {
                    ordinary,
                    resolver: self.resolver,
                    symbols: self.symbols,
                    resource_search_context: self.resource_search_context,
                };
                match engine {
                    Some(engine) => operation(&EngineCapturedEvaluator {
                        engine,
                        evaluator: &startup,
                    }),
                    None => operation(&startup),
                }
            });
    }
}
