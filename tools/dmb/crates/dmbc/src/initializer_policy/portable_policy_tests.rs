use super::*;
use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver};
use dm_tree::constants::{Constant, PureCallError, PureCalls};
struct Host;
impl Resolver for Host {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        ResolvedMeaning::Unsupported(query)
    }
}
struct Policy(Option<&'static [u8]>);
impl PureCalls for Policy {
    fn immutable_policy_identity(&self) -> Option<u128> { Some(7) }
    fn immutable_policy_bytes(&self) -> Option<&[u8]> { self.0 }
    fn identity(&self) -> u128 { 7 }
    fn accepts(&self, _: &str) -> bool { false }
    fn evaluate(&self, _: &str, _: &[Option<Constant>]) -> Result<Constant, PureCallError> {
        unreachable!("policy proof must not evaluate source")
    }
}
struct Custom;
impl InitializerEvaluatorFactory for Custom {
    fn recording_policy_identity(&self) -> Option<u128> { Some(7) }
    fn with_evaluator(&self, _: Option<&crate::engine::EngineSnapshot>,
        _: &mut dyn FnMut(&dyn CapturedInitializerEvaluator)) {}
}
#[test]
fn portable_policy_declines_opaque_identity_and_compares_full_policy_bytes() {
    assert!(Custom.immutable_initializer_policy_bytes().is_none());
    let symbols = SymbolTable::default();
    let host = Host;
    let policy = Policy(None);
    let mut evaluator = crate::driver_facts::DriverEvaluator {
        pure_calls: Some(&policy), resource_search_context: None,
        resolver: &host, symbols: &symbols,
    };
    assert!(evaluator.immutable_initializer_policy_bytes().is_none());
    let first = Policy(Some(b"exact-policy-a"));
    let second = Policy(Some(b"exact-policy-b"));
    evaluator.pure_calls = Some(&first);
    let a = evaluator.immutable_initializer_policy_bytes().unwrap();
    assert!(a.windows(14).any(|part| part == b"exact-policy-a"));
    evaluator.pure_calls = Some(&second);
    assert_ne!(a, evaluator.immutable_initializer_policy_bytes().unwrap());
    evaluator.pure_calls = None;
    assert_ne!(a, evaluator.immutable_initializer_policy_bytes().unwrap());
}
