//! Exact input rejection uses the same semantic replay and current binder.
use super::*;
struct Policy<'a> {
    inner: &'a dyn InitializerEvaluatorFactory,
    value: u128,
}
impl InitializerEvaluatorFactory for Policy<'_> {
    fn recording_policy_identity(&self) -> Option<u128> {
        Some(self.value)
    }
    fn with_evaluator(
        &self,
        engine: Option<&crate::engine::EngineSnapshot>,
        operation: &mut dyn FnMut(&dyn CapturedInitializerEvaluator),
    ) {
        self.inner.with_evaluator(engine, operation)
    }
    fn with_recording_evaluator(
        &self,
        engine: Option<&crate::engine::EngineSnapshot>,
        resolver: &dyn Resolver,
        operation: &mut dyn FnMut(&dyn CapturedInitializerEvaluator),
    ) -> bool {
        self.inner
            .with_recording_evaluator(engine, resolver, operation)
    }
}
#[test]
fn short_locator_requires_full_write_fact_config_and_current_binding() {
    let mut symbols = SymbolTable::default();
    let original = write("dependency", &mut symbols);
    let mut changed = original.clone();
    if let InitializerTarget::Shared { slot, .. } = &mut changed.target {
        *slot = SymbolId::of("different.output.slot");
    }
    let host = Host {
        value: AtomicU32::new(7f32.to_bits()),
        version: AtomicU64::new(1),
    };
    let evaluator = crate::driver_facts::DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: &host,
        symbols: &symbols,
    };
    let ordinary = evaluator.parallel_evaluator().unwrap();
    let first_policy = Policy {
        inner: ordinary.factory,
        value: 11,
    };
    let other_policy = Policy {
        inner: ordinary.factory,
        value: 12,
    };
    let store = InitializerArtifacts::default();
    let base = InitializerReuse {
        store: &store,
        resolver: &host,
        policy: 1,
        resource_search_context: None,
    };
    let locator: Arc<[u8]> = b"deliberately-identical-candidate".as_slice().into();
    for (input, fact, policy, resource, factory, hit) in [
        (
            &original,
            ModifierFact::Known(8),
            1,
            None,
            &first_policy,
            false,
        ),
        (
            &original,
            ModifierFact::Known(8),
            1,
            None,
            &first_policy,
            true,
        ),
        (
            &changed,
            ModifierFact::Known(8),
            1,
            None,
            &first_policy,
            false,
        ),
        (
            &original,
            ModifierFact::Known(8),
            1,
            None,
            &first_policy,
            false,
        ),
        (
            &original,
            ModifierFact::Known(10),
            1,
            None,
            &first_policy,
            false,
        ),
        (
            &original,
            ModifierFact::Known(8),
            2,
            None,
            &first_policy,
            false,
        ),
        (
            &original,
            ModifierFact::Known(8),
            2,
            Some(9),
            &first_policy,
            false,
        ),
        (
            &original,
            ModifierFact::Known(8),
            2,
            Some(9),
            &other_policy,
            false,
        ),
    ] {
        let before = store.hits.load(Ordering::Relaxed);
        let result = classify_one_keyed(
            input,
            &symbols,
            &evaluator,
            fact,
            83,
            ParallelEvaluator {
                factory,
                engine: None,
            },
            InitializerReuse {
                policy,
                resource_search_context: resource,
                ..base
            },
            Some(&locator),
        )
        .unwrap();
        assert_eq!(store.hits.load(Ordering::Relaxed) - before, u64::from(hit));
        assert_eq!(result.write.source_ordinal, 83);
        assert_eq!(&result.write.write, input);
        let accepted = result.accepted.expect("production exact-input admission");
        assert_eq!(accepted.input_write().unwrap().as_ref(), input);
    }
    assert!(key(&original, ModifierFact::Known(8), base, 11).len() < 160);
}
