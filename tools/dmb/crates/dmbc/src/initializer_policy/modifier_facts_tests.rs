use super::*;
use dm_ir::{ReadDomain, ResolvedMeaning};
use std::sync::atomic::AtomicU32;
struct Dependency(AtomicU32);
impl Resolver for Dependency {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        match query {
            ResolveQuery::Constant { .. } => {
                ResolvedMeaning::Value(SemanticValue::NumberBits(self.0.load(Ordering::Relaxed)))
            }
            _ => ResolvedMeaning::Unsupported(query),
        }
    }
    fn domain_version(&self, _: ReadDomain) -> Option<u128> {
        None
    }
}
struct Worker<'a> {
    resolver: &'a dyn Resolver,
    captures: &'a AtomicU64,
}
impl CapturedInitializerEvaluator for Worker<'_> {
    fn evaluate(&self, _: SymbolId, _: &SymbolicExpression) -> Result<Evaluation, String> {
        Err("modifier admission must not evaluate initializer values".into())
    }
    fn binding_knowledge(
        &self,
        write: &InitializerWrite,
    ) -> Result<Option<BindingKnowledge>, String> {
        self.captures.fetch_add(1, Ordering::Relaxed);
        match self.resolver.resolve(ResolveQuery::Constant {
            owner: write.lexical_owner,
            name: SymbolId::of("flags"),
        }) {
            ResolvedMeaning::Value(SemanticValue::NumberBits(flags)) => {
                Ok(Some(BindingKnowledge::Modifiers(flags)))
            }
            _ => Err("modifier dependency unsupported".into()),
        }
    }
}
impl InitializerEvaluatorFactory for Worker<'_> {
    fn recording_policy_identity(&self) -> Option<u128> {
        Some(42)
    }
    fn with_recording_evaluator(
        &self,
        _: Option<&crate::engine::EngineSnapshot>,
        resolver: &dyn Resolver,
        operation: &mut dyn FnMut(&dyn CapturedInitializerEvaluator),
    ) -> bool {
        operation(&Worker {
            resolver,
            captures: self.captures,
        });
        true
    }
    fn with_evaluator(
        &self,
        _: Option<&crate::engine::EngineSnapshot>,
        operation: &mut dyn FnMut(&dyn CapturedInitializerEvaluator),
    ) {
        operation(self);
    }
}
fn write(symbols: &mut SymbolTable) -> InitializerWrite {
    let owner = symbols.intern("/").unwrap();
    let name = symbols.intern("output").unwrap();
    InitializerWrite {
        target: InitializerTarget::Shared {
            slot: SymbolId::of("output.slot"),
            owner,
            name,
        },
        lexical_owner: owner,
        lexical_procedure: None,
        value: InitializerValue::NoAuthoredValue,
        declared_array: None,
        declaration_flags: None,
    }
}
#[test]
fn modifier_receipts_revalidate_current_answers_and_preserve_global_error_ordinals() {
    let mut symbols = SymbolTable::default();
    let write = write(&mut symbols);
    let dependency = Dependency(AtomicU32::new(8));
    let captures = AtomicU64::new(0);
    let worker = Worker {
        resolver: &dependency,
        captures: &captures,
    };
    let factory = ParallelEvaluator {
        factory: &worker,
        engine: None,
    };
    let store = InitializerArtifacts::default();
    let reuse = InitializerReuse {
        store: &store,
        resolver: &dependency,
        policy: 1,
        resource_search_context: None,
    };
    let roster = vec![write.clone()];
    let first_keys = keys(&roster, factory, reuse).unwrap();
    let first = modifier_facts_reused(
        roster.iter(),
        &symbols,
        &worker,
        &[0],
        factory,
        reuse,
        &first_keys,
    )
    .unwrap();
    assert!(matches!(first.as_slice(), [ModifierFact::Known(8)]));
    assert_eq!(captures.load(Ordering::Relaxed), 1);
    let unchanged = modifier_facts_reused(
        roster.iter(),
        &symbols,
        &worker,
        &[0],
        factory,
        reuse,
        &first_keys,
    )
    .unwrap();
    assert!(matches!(unchanged.as_slice(), [ModifierFact::Known(8)]));
    assert_eq!(captures.load(Ordering::Relaxed), 1);
    dependency.0.store(2, Ordering::Relaxed);
    let changed = modifier_facts_reused(
        roster.iter(),
        &symbols,
        &worker,
        &[0],
        factory,
        reuse,
        &first_keys,
    )
    .unwrap();
    assert!(matches!(changed.as_slice(), [ModifierFact::Known(2)]));
    assert_eq!(captures.load(Ordering::Relaxed), 2);
    dependency.0.store(16, Ordering::Relaxed);
    let large_roster = vec![write.clone(); 4];
    let keys = keys(&large_roster, factory, reuse).unwrap();
    let errors = match modifier_facts_reused(
        std::iter::once(&write),
        &symbols,
        &worker,
        &[3],
        factory,
        reuse,
        &keys,
    ) {
        Ok(_) => panic!("unknown modifiers must reject"),
        Err(errors) => errors,
    };
    assert_eq!(errors.issues.len(), 1);
    assert_eq!(errors.issues[0].source_ordinal, 3);
    assert_eq!(errors.issues[0].reason, "unknown initializer modifiers");
}
