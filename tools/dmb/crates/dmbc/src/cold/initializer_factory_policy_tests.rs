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

#[test]
fn startup_portable_stack_requires_exact_authenticated_inner_engine() {
    let host = Host;
    let symbols = dm_ir::SymbolTable::default();
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"), 1).unwrap();
    let foreign = engine.clone();
    let ordinary = crate::driver_facts::DriverEvaluator {
        pure_calls: None, resource_search_context: None, resolver: &host, symbols: &symbols,
    };
    let mut factory = StartupParallelFactory {
        ordinary: ParallelEvaluator { factory: &ordinary, engine: Some(&engine) },
        resolver: &host, symbols: &symbols, resource_search_context: None,
    };
    assert!(factory.immutable_initializer_policy_bytes().is_none());
    assert!(factory.immutable_initializer_policy_bytes_for_engine(Some(&foreign)).is_none());
    let same = factory.immutable_initializer_policy_bytes_for_engine(Some(&engine)).unwrap();
    factory.ordinary.engine = None;
    let absent = factory.immutable_initializer_policy_bytes_for_engine(Some(&engine)).unwrap();
    assert_ne!(same, absent, "inner-engine presence changes wrapper semantics");
    let opaque = Policy(Some(b"opaque exact policy"));
    factory.ordinary.factory = &opaque;
    factory.ordinary.engine = Some(&engine);
    assert!(factory.immutable_initializer_policy_bytes_for_engine(Some(&engine)).is_none());
}
