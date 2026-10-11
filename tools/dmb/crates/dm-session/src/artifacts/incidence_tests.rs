use super::*;
type Store = ObservedArtifactStore<u8, u8, bool, u8>;
fn reads(domain: u8) -> Receipt<u8, bool, u8> {
    vec![Observation {
        query: 1,
        answer: false,
        domain,
    }]
    .into()
}
fn affected(store: &Store, domain: u8) -> Vec<u8> {
    let mut values = Vec::new();
    store.visit_affected(&[domain], |_, value| values.push(**value));
    values.sort();
    values
}
#[test]
fn replacement_pruning_and_budget_eviction_remove_exact_live_subscriptions() {
    let store = Store::current_revision();
    store.insert_with_receipt(Arc::from([1]), reads(3), Arc::from([]), 1, || 1);
    store.enable_incidence();
    assert_eq!(affected(&store, 3), vec![1]);
    store.insert_with_receipt(Arc::from([1]), reads(4), Arc::from([]), 1, || 2);
    assert!(affected(&store, 3).is_empty());
    assert_eq!(affected(&store, 4), vec![2]);
    store.retain_current_keys(std::iter::empty());
    assert!(affected(&store, 4).is_empty());
    assert_eq!(store.visit_incidence_storage(|_| {}), Some((0, 0, 0, 0)));
    let budget = Store::with_limit(1);
    budget.enable_incidence();
    budget.insert_with_receipt(Arc::from([1]), reads(3), Arc::from([]), 1, || 1);
    budget.insert_with_receipt(Arc::from([2]), reads(4), Arc::from([]), 1, || 2);
    assert!(affected(&budget, 3).is_empty());
    assert_eq!(affected(&budget, 4), vec![2]);
}
#[test]
fn sibling_claim_release_preserves_only_current_live_variant() {
    let store = Store::shared_current_rosters();
    store.enable_incidence();
    let a = store.lease();
    let b = store.lease();
    let receipt = reads(3);
    let old = a
        .insert_with_receipt(Arc::from([1]), receipt.clone(), 1, || 1)
        .unwrap();
    let same = b
        .insert_with_receipt(Arc::from([1]), receipt, 1, || 9)
        .unwrap();
    assert!(Arc::ptr_eq(&old, &same));
    a.insert_with_receipt(Arc::from([1]), reads(4), 1, || 2);
    assert_eq!(affected(&store, 3), vec![1]);
    drop(b);
    assert!(affected(&store, 3).is_empty());
    assert_eq!(affected(&store, 4), vec![2]);
    drop(a);
    assert!(affected(&store, 4).is_empty());
    // External old artifacts cannot keep stale scheduling subscriptions alive.
    assert_eq!(*old, 1);
    assert_eq!(store.visit_incidence_storage(|_| {}), Some((0, 0, 0, 0)));
}

#[test]
fn routed_dirty_candidates_preserve_store_order_and_exclude_unrelated_roster() {
    let store = Store::current_revision();
    for key in 0u8..120 {
        store.insert_with_receipt(
            Arc::from([key]),
            reads(if key % 29 == 0 { 7 } else { 8 }),
            Arc::from([]),
            1,
            || key,
        );
    }
    store.enable_incidence();
    let expected: Vec<_> = {
        let state = store.state.lock().unwrap();
        state
            .buckets
            .values()
            .flatten()
            .filter(|entry| entry.reads.iter().any(|read| read.domain == 7))
            .map(|entry| *entry.value)
            .collect()
    };
    let mut actual = Vec::new();
    store.visit_affected(&[7, 7, 99], |_, value| actual.push(**value));
    assert_eq!(actual, expected);
    let state = store.state.lock().unwrap();
    let index = state.incidence.as_ref().unwrap();
    let buckets = index.affected_buckets(&index.affected([&7]));
    assert_eq!(buckets.len(), 5);
    assert!(buckets.len() < state.buckets.len());
}
