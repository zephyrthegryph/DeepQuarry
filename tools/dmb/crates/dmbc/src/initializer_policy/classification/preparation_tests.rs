use super::*;
fn preparation(
    store: &InitializerArtifacts,
) -> Arc<super::super::super::token_roster::preparation::Preparation> {
    let mut owner = None;
    store.visit_preparation(|current| owner = Some(current.clone()));
    owner.unwrap()
}
fn keys(store: &InitializerArtifacts) -> Arc<Vec<Arc<[u8]>>> {
    let mut keys = None;
    store.visit_preparation(|current| {
        current.visit_locations(|locations| keys = Some(locations.keys.clone()))
    });
    keys.unwrap()
}
#[test]
fn current_preparation_shares_interleaved_buckets_and_exact_duplicate_locators() {
    let mut symbols = SymbolTable::default();
    let first = write("list(1,2)", &mut symbols);
    let mut other = first.clone();
    let owner = symbols.intern("/datum/other").unwrap();
    other.lexical_owner = owner;
    if let InitializerTarget::Shared { owner: target, .. } = &mut other.target {
        *target = owner;
    }
    let writes = vec![first.clone(), other, first];
    let host = Host {
        value: AtomicU32::new(7f32.to_bits()),
        version: AtomicU64::new(1),
    };
    let store = InitializerArtifacts::default();
    let evaluator = crate::driver_facts::DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: &host,
        symbols: &symbols,
    };
    let factory = evaluator.parallel_evaluator().unwrap();
    let executor = dm_exec::BuildExecutor::new(2).unwrap();
    let reuse = InitializerReuse {
        store: &store,
        resolver: &host,
        policy: 1,
        resource_search_context: None,
    };
    let run = |writes: &[InitializerWrite], reuse| {
        crate::initializer_policy::classify_with_reuse_on_executor(
            writes, &symbols, factory, false, &executor, reuse,
        )
        .unwrap()
    };
    run(&writes, reuse);
    let old = preparation(&store);
    let old_keys = keys(&store);
    assert_eq!(&*old.buckets[0].ordinals, &[0, 2]);
    assert_eq!(&*old.buckets[1].ordinals, &[1]);
    assert_ne!(
        old_keys[0], old_keys[2],
        "duplicate qualifiers are source-ordinal stable"
    );
    let actual = run(&writes, reuse);
    assert!(Arc::ptr_eq(&old, &preparation(&store)));
    assert!(Arc::ptr_eq(&old_keys, &keys(&store)));
    let fresh = crate::initializer_policy::classify_with_token_mode_on_executor(
        &writes, &symbols, factory, false, &executor,
    )
    .unwrap();
    for (a, b) in actual.writes.iter().zip(&fresh.writes) {
        assert_eq!(a.write, b.write);
        assert_eq!(a.default, b.default);
        assert_eq!(a.phase, b.phase);
        assert_eq!(a.runtime_value, b.runtime_value);
        assert_eq!(a.source_ordinal, b.source_ordinal);
    }
    assert_eq!(
        actual
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
    let changed_policy = InitializerReuse {
        resource_search_context: Some(4),
        ..reuse
    };
    run(&writes, changed_policy);
    assert!(
        !Arc::ptr_eq(&old_keys, &keys(&store)),
        "current configuration must reissue locators"
    );
    let reversed = vec![writes[1].clone(), writes[0].clone(), writes[2].clone()];
    run(&reversed, reuse);
    assert!(
        !Arc::ptr_eq(&old, &preparation(&store)),
        "changed owner encounter order reissues scheduling"
    );
    assert_eq!(&*preparation(&store).buckets[0].ordinals, &[0]);
}
#[test]
fn failed_current_modifier_boundary_releases_previous_preparation_inputs() {
    let mut symbols = SymbolTable::default();
    let valid = write("list(1)", &mut symbols);
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
    let factory = evaluator.parallel_evaluator().unwrap();
    let store = InitializerArtifacts::default();
    let executor = dm_exec::BuildExecutor::new(2).unwrap();
    let reuse = InitializerReuse {
        store: &store,
        resolver: &host,
        policy: 1,
        resource_search_context: None,
    };
    crate::initializer_policy::classify_with_reuse_on_executor(
        &[valid.clone()],
        &symbols,
        factory,
        false,
        &executor,
        reuse,
    )
    .unwrap();
    let old = Arc::downgrade(&preparation(&store));
    let mut invalid = valid;
    invalid.declaration_flags = None;
    let failure = crate::initializer_policy::classify_with_reuse_on_executor(
        &[invalid],
        &symbols,
        factory,
        false,
        &executor,
        reuse,
    )
    .unwrap_err();
    assert_eq!(failure.issues[0].source_ordinal, 0);
    assert!(old.upgrade().is_none());
    store.visit_preparation(|_| panic!("failed current modifier must release preparation"));
}
