use super::*;
use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver};
struct Host;
impl Resolver for Host {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning { ResolvedMeaning::Unsupported(query) }
}
struct Policy(Option<&'static [u8]>);
impl InitializerEvaluatorFactory for Policy {
    fn immutable_initializer_policy_bytes(&self) -> Option<std::sync::Arc<[u8]>> {
        self.0.map(std::sync::Arc::from)
    }
    fn with_evaluator(&self, _: Option<&crate::engine::EngineSnapshot>,
        _: &mut dyn FnMut(&dyn CapturedInitializerEvaluator)) {}
}
#[test]
fn startup_factory_preserves_complete_ordinary_policy_and_declines_unknown() {
    let host = Host;
    let symbols = dm_ir::SymbolTable::default();
    let ordinary = Policy(Some(b"complete ordinary policy"));
    let mut factory = StartupParallelFactory {
        ordinary: ParallelEvaluator { factory: &ordinary, engine: None },
        resolver: &host, symbols: &symbols, resource_search_context: None,
    };
    let proof = factory.immutable_initializer_policy_bytes().unwrap();
    assert!(proof.ends_with(b"complete ordinary policy"));
    assert_ne!(&*proof, b"complete ordinary policy");
    let changed = Policy(Some(b"changed ordinary policy"));
    factory.ordinary.factory = &changed;
    assert_ne!(proof, factory.immutable_initializer_policy_bytes().unwrap());
    let unknown = Policy(None);
    factory.ordinary.factory = &unknown;
    assert!(factory.immutable_initializer_policy_bytes().is_none());
}
