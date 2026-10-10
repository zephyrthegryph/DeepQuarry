use super::*;
use std::sync::atomic::AtomicBool;

struct AncestryHost {
    base: Host,
    changed: AtomicBool,
}
impl Resolver for AncestryHost {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        if let ResolveQuery::Ancestry(owner) = query {
            let mut path = vec![owner];
            if self.changed.load(Ordering::Relaxed) {
                path.push(SymbolId::of("/changed_parent"));
            }
            ResolvedMeaning::Symbols(path.into())
        } else {
            self.base.resolve(query)
        }
    }
    fn domain_version(&self, domain: ReadDomain) -> Option<u128> {
        self.base.domain_version(domain)
    }
}
fn ancestry_leaves(store: &InitializerArtifacts) -> Vec<Arc<[dm_session::ResolverRead]>> {
    let mut leaves = Vec::new();
    store.visit_storage(|storage| {
        if let dm_session::ArtifactStorageView::Entry { reads, .. } = storage {
            reads.visit_storage(|storage| {
                if let dm_session::ReceiptStorageView::Flat(leaf) = storage {
                    if leaf.len() == 1 && matches!(leaf[0].query, ResolveQuery::Ancestry(_)) {
                        leaves.push(Arc::clone(leaf));
                    }
                }
            });
        }
    });
    leaves
}
#[test]
fn classification_pass_shares_exact_ancestry_and_rejects_changed_answer() {
    let mut symbols = SymbolTable::default();
    let first = write("dependency", &mut symbols);
    let mut second = write("dependency", &mut symbols);
    if let InitializerTarget::Shared { name, slot, .. } = &mut second.target {
        *name = symbols.intern("other").unwrap();
        *slot = SymbolId::of("other.slot");
    }
    let host = AncestryHost {
        base: Host {
            value: AtomicU32::new(7f32.to_bits()),
            version: AtomicU64::new(1),
        },
        changed: AtomicBool::new(false),
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
    let roster = [first, second];
    let run = || {
        crate::initializer_policy::classify_with_reuse_on_executor(
            &roster, &symbols, factory, false, &executor, reuse,
        )
        .unwrap()
    };
    run();
    let first_leaves = ancestry_leaves(&store);
    assert_eq!(first_leaves.len(), 2);
    assert!(Arc::ptr_eq(&first_leaves[0], &first_leaves[1]));
    run();
    assert_eq!(store.hits.load(Ordering::Relaxed), 2);
    host.changed.store(true, Ordering::Relaxed);
    host.base.version.store(2, Ordering::Relaxed);
    let changed = run();
    assert_eq!(store.hits.load(Ordering::Relaxed), 2);
    assert_eq!(store.recomputed.load(Ordering::Relaxed), 4);
    let current_leaves = ancestry_leaves(&store);
    assert_eq!(current_leaves.len(), 2);
    assert!(Arc::ptr_eq(&current_leaves[0], &current_leaves[1]));
    assert_ne!(first_leaves[0].as_ref(), current_leaves[0].as_ref());
    let fresh = crate::initializer_policy::classify_with_token_mode_on_executor(
        &roster, &symbols, factory, false, &executor,
    )
    .unwrap();
    for (a, b) in changed.writes.iter().zip(&fresh.writes) {
        assert_eq!(a.default, b.default);
        assert_eq!(a.phase, b.phase);
        assert_eq!(a.source_ordinal, b.source_ordinal);
    }
}
