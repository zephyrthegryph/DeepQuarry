use super::*;
#[test]
fn compact_classification_retains_exact_receipts_and_rebinds_current_ordinal() {
    let mut symbols = SymbolTable::default();
    let write = write("dependency", &mut symbols);
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
    let reuse = InitializerReuse {
        store: &store,
        resolver: &host,
        policy: 1,
        resource_search_context: None,
    };
    let lower = |ordinal| {
        classify_one(
            &write,
            &symbols,
            &evaluator,
            ModifierFact::Known(8),
            ordinal,
            factory,
            reuse,
        )
        .unwrap()
    };
    let first = lower(0);
    let mut inspected = 0;
    store.visit_storage(|view| {
        if let dm_session::ArtifactStorageView::Entry {
            key,
            reads,
            versions,
            value,
        } = view
        {
            let allocations = crate::heap_census::initializer_artifacts::compact_allocations(
                key,
                reads,
                versions,
                value,
                usize::MAX,
            )
            .expect("actual scalar classification is fully exposed");
            let payload: usize = allocations.iter().map(|item| item.bytes).sum();
            assert!(payload > std::mem::size_of::<SemanticClassification>());
            assert!(
                crate::heap_census::initializer_artifacts::compact_allocations(
                    key,
                    reads,
                    versions,
                    value,
                    payload - 1
                )
                .is_none()
            );
            inspected += 1;
        }
    });
    assert_eq!(inspected, 1);
    let report = store.compact_for_pressure(1024 * 1024);
    assert_eq!(report.retained_entries, 1);
    assert!(report.charged_bytes > std::mem::size_of::<SemanticClassification>());
    let shifted = lower(83);
    assert_eq!(store.hits.load(Ordering::Relaxed), 1);
    assert_eq!(first.write.default, shifted.write.default);
    assert_eq!(shifted.write.source_ordinal, 83);
    assert!(Arc::ptr_eq(
        first.accepted.as_ref().unwrap(),
        shifted.accepted.as_ref().unwrap()
    ));
    host.value.store(9f32.to_bits(), Ordering::Relaxed);
    host.version.store(2, Ordering::Relaxed);
    let changed = lower(84);
    assert_ne!(changed.write.default, shifted.write.default);
    assert_eq!(store.hits.load(Ordering::Relaxed), 1);
    let removed = store.compact_for_pressure(0);
    assert_eq!(removed.retained_entries, 0);
    assert_eq!(removed.evicted_entries, 1);
}
