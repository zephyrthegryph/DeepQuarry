use super::*;
use std::sync::atomic::AtomicU32;

struct Host {
    value: AtomicU32,
    version: AtomicU64,
}
impl Resolver for Host {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        match query {
            ResolveQuery::Constant { name, .. } if name == SymbolId::of("dependency") => {
                ResolvedMeaning::Value(SemanticValue::NumberBits(
                    self.value.load(Ordering::Relaxed),
                ))
            }
            _ => ResolvedMeaning::Missing,
        }
    }
    fn domain_version(&self, _: ReadDomain) -> Option<u128> {
        Some(self.version.load(Ordering::Relaxed).into())
    }
}
fn write(source: &str, symbols: &mut SymbolTable) -> InitializerWrite {
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
        value: InitializerValue::Expression(
            crate::initializer_policy::expression(source, symbols).unwrap(),
        ),
        declared_array: None,
        declaration_flags: Some(8),
    }
}
#[test]
fn scalar_reads_revalidate_and_current_ordinal_does_not_enter_payload() {
    let mut symbols = SymbolTable::default();
    let write = write("dependency", &mut symbols);
    let host = Host {
        value: AtomicU32::new(7f32.to_bits()),
        version: AtomicU64::new(1),
    };
    let store = InitializerArtifacts::with_limit(1024 * 1024);
    let evaluator = crate::driver_facts::DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: &host,
        symbols: &symbols,
    };
    let factory = evaluator.parallel_evaluator().unwrap();
    let reuse = InitializerReuse {
        store: &store,
        resolver: &host,
        policy: 1,
        resource_search_context: None,
    };
    let first = classify_one(
        &write,
        &symbols,
        &evaluator,
        ModifierFact::Known(8),
        0,
        factory,
        reuse,
    )
    .unwrap();
    let second = classify_one(
        &write,
        &symbols,
        &evaluator,
        ModifierFact::Known(8),
        83,
        factory,
        reuse,
    )
    .unwrap();
    assert_eq!(first.write.default, second.write.default);
    assert_eq!(second.write.source_ordinal, 83);
    assert_eq!(store.hits.load(Ordering::Relaxed), 1);
    // An unrelated structural edit changes the domain; exact same read still admits.
    host.version.store(2, Ordering::Relaxed);
    classify_one(
        &write,
        &symbols,
        &evaluator,
        ModifierFact::Known(8),
        2,
        factory,
        reuse,
    )
    .unwrap();
    assert_eq!(store.hits.load(Ordering::Relaxed), 2);
    host.value.store(9f32.to_bits(), Ordering::Relaxed);
    host.version.store(3, Ordering::Relaxed);
    let changed = classify_one(
        &write,
        &symbols,
        &evaluator,
        ModifierFact::Known(8),
        3,
        factory,
        reuse,
    )
    .unwrap();
    assert_eq!(
        changed.write.default,
        DefaultValue::Scalar(SemanticValue::NumberBits(9f32.to_bits()))
    );
    assert_eq!(store.recomputed.load(Ordering::Relaxed), 2);
}
#[test]
fn runtime_recipe_binds_fresh_syntax_and_matches_uncached_result() {
    let mut symbols = SymbolTable::default();
    let write = write("list(1,2)", &mut symbols);
    let host = Host {
        value: AtomicU32::new(0),
        version: AtomicU64::new(1),
    };
    let store = InitializerArtifacts::with_limit(1024 * 1024);
    let evaluator = crate::driver_facts::DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: &host,
        symbols: &symbols,
    };
    let factory = evaluator.parallel_evaluator().unwrap();
    let reuse = InitializerReuse {
        store: &store,
        resolver: &host,
        policy: 1,
        resource_search_context: None,
    };
    let first = classify_one(
        &write,
        &symbols,
        &evaluator,
        ModifierFact::Known(8),
        0,
        factory,
        reuse,
    )
    .unwrap();
    let second = classify_one(
        &write,
        &symbols,
        &evaluator,
        ModifierFact::Known(8),
        5,
        factory,
        reuse,
    )
    .unwrap();
    let mut ordinal = 0;
    let fresh = classify_pending(
        std::iter::once(&write),
        &symbols,
        &evaluator,
        &[ModifierFact::Known(8)],
        &mut ordinal,
    )
    .unwrap()
    .pop()
    .unwrap();
    assert_eq!(second.write.default, fresh.write.default);
    assert_eq!(second.write.phase, fresh.write.phase);
    assert_eq!(second.write.runtime_value, fresh.write.runtime_value);
    assert_eq!(second.key, fresh.key);
    let (Some(RuntimeValue::Expression(a)), Some(RuntimeValue::Expression(b))) =
        (&first.write.runtime_value, &second.write.runtime_value)
    else {
        panic!("runtime syntax required")
    };
    assert!(Arc::ptr_eq(a, b));
    assert_eq!(store.hits.load(Ordering::Relaxed), 1);
    let changed_policy = InitializerReuse { policy: 2, ..reuse };
    classify_one(
        &write,
        &symbols,
        &evaluator,
        ModifierFact::Known(8),
        0,
        factory,
        changed_policy,
    )
    .unwrap();
    assert_eq!(store.recomputed.load(Ordering::Relaxed), 2);
}

#[test]
fn ordered_roster_reassembly_preserves_tokens_groups_and_modifier_error_precedence() {
    let mut symbols = SymbolTable::default();
    let first = write("list(1,2)", &mut symbols);
    let mut second = write("dependency", &mut symbols);
    if let InitializerTarget::Shared { name, slot, .. } = &mut second.target {
        *name = symbols.intern("other").unwrap();
        *slot = SymbolId::of("other.slot");
    }
    let host = Host {
        value: AtomicU32::new(7f32.to_bits()),
        version: AtomicU64::new(1),
    };
    let store = InitializerArtifacts::with_limit(1024 * 1024);
    let evaluator = crate::driver_facts::DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: &host,
        symbols: &symbols,
    };
    let executor = dm_exec::BuildExecutor::new(2).unwrap();
    let factory = evaluator.parallel_evaluator().unwrap();
    let reuse = InitializerReuse {
        store: &store,
        resolver: &host,
        policy: 1,
        resource_search_context: None,
    };
    let roster = [first, second];
    let run = || {
        crate::initializer_policy::classify_with_reuse_on_executor(
            &roster, &symbols, factory, false, &executor, reuse,
        )
        .unwrap()
    };
    let initial = run();
    let replay = run();
    let fresh = crate::initializer_policy::classify_with_token_mode_on_executor(
        &roster, &symbols, factory, false, &executor,
    )
    .unwrap();
    for (a, b) in replay.writes.iter().zip(&fresh.writes) {
        assert_eq!(a.write, b.write);
        assert_eq!(a.default, b.default);
        assert_eq!(a.phase, b.phase);
        assert_eq!(a.runtime_value, b.runtime_value);
        assert_eq!(a.source_ordinal, b.source_ordinal);
    }
    assert_eq!(
        initial
            .groups
            .iter()
            .map(|g| (&g.receiver, &g.writes))
            .collect::<Vec<_>>(),
        fresh
            .groups
            .iter()
            .map(|g| (&g.receiver, &g.writes))
            .collect::<Vec<_>>()
    );
    assert_eq!(store.hits.load(Ordering::Relaxed), 2);
    // The later missing modifier must fail before evaluating the earlier invalid expression.
    let mut invalid = roster.clone();
    invalid[0].value = InitializerValue::Expression(
        crate::initializer_policy::expression("1 +", &mut symbols).unwrap(),
    );
    invalid[1].declaration_flags = None;
    let evaluator = crate::driver_facts::DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: &host,
        symbols: &symbols,
    };
    let factory = evaluator.parallel_evaluator().unwrap();
    let cached = crate::initializer_policy::classify_with_reuse_on_executor(
        &invalid, &symbols, factory, false, &executor, reuse,
    )
    .unwrap_err();
    let fresh = crate::initializer_policy::classify_with_token_mode_on_executor(
        &invalid, &symbols, factory, false, &executor,
    )
    .unwrap_err();
    assert_eq!(cached.issues.len(), fresh.issues.len());
    assert_eq!(
        cached.issues[0].source_ordinal,
        fresh.issues[0].source_ordinal
    );
    assert_eq!(cached.issues[0].reason, fresh.issues[0].reason);
}

#[test]
fn opaque_pure_call_provider_never_admits_unrecorded_external_answers() {
    struct External(AtomicU32);
    impl dm_tree::constants::PureCalls for External {
        fn identity(&self) -> u128 {
            1
        }
        fn accepts(&self, name: &str) -> bool {
            name == "rgb"
        }
        fn evaluate(
            &self,
            _: &str,
            _: &[Option<dm_tree::constants::Constant>],
        ) -> Result<dm_tree::constants::Constant, dm_tree::constants::PureCallError> {
            Ok(dm_tree::constants::Constant::Number(
                self.0.load(Ordering::Relaxed) as f32,
            ))
        }
    }
    let mut symbols = SymbolTable::default();
    let write = write("rgb(1,2,3)", &mut symbols);
    let host = Host {
        value: AtomicU32::new(0),
        version: AtomicU64::new(1),
    };
    let calls = External(AtomicU32::new(7));
    let store = InitializerArtifacts::default();
    let evaluator = crate::driver_facts::DriverEvaluator {
        pure_calls: Some(&calls),
        resource_search_context: None,
        resolver: &host,
        symbols: &symbols,
    };
    let factory = evaluator.parallel_evaluator().unwrap();
    let reuse = InitializerReuse {
        store: &store,
        resolver: &host,
        policy: 1,
        resource_search_context: None,
    };
    let first = classify_one(
        &write,
        &symbols,
        &evaluator,
        ModifierFact::Known(8),
        0,
        factory,
        reuse,
    )
    .unwrap();
    calls.0.store(9, Ordering::Relaxed);
    let second = classify_one(
        &write,
        &symbols,
        &evaluator,
        ModifierFact::Known(8),
        0,
        factory,
        reuse,
    )
    .unwrap();
    assert_ne!(first.write.default, second.write.default);
    assert_eq!(store.hits.load(Ordering::Relaxed), 0);
    assert_eq!(store.recomputed.load(Ordering::Relaxed), 0);
}
