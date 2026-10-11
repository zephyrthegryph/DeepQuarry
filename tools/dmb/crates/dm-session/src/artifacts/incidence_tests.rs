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

fn selected(store: &Store, keys: &[&[u8]]) -> Vec<(Vec<u8>, u8)> {
    let mut values = Vec::new();
    store.visit_key_storage(keys.iter().copied(), |view| {
        if let ObservedArtifactStorageView::Entry { key, value, .. } = view {
            values.push((key.to_vec(), **value));
        }
    });
    values
}
#[test]
fn direct_current_candidates_preserve_selection_order_and_live_lifecycle() {
    let store = Store::current_revision();
    store.enable_incidence();
    for key in 0..100u8 {
        store.insert_with_receipt(Arc::from([key]), reads(3), Arc::from([]), 1, || key);
    }
    assert_eq!(
        selected(&store, &[&[9], &[3], &[255]]),
        vec![(vec![9], 9), (vec![3], 3)]
    );
    store.insert_with_receipt(Arc::from([9]), reads(4), Arc::from([]), 1, || 29);
    assert_eq!(selected(&store, &[&[9]]), vec![(vec![9], 29)]);
    store.retain_current_keys([&[3][..]]);
    assert_eq!(selected(&store, &[&[9], &[3]]), vec![(vec![3], 3)]);
    let budget = Store::with_limit(1);
    budget.insert_with_receipt(Arc::from([1]), reads(3), Arc::from([]), 1, || 1);
    budget.insert_with_receipt(Arc::from([2]), reads(4), Arc::from([]), 1, || 2);
    assert_eq!(selected(&budget, &[&[1], &[2]]), vec![(vec![2], 2)]);
    let shared = Store::shared_current_rosters();
    let lease = shared.lease();
    let external = lease
        .insert_with_receipt(Arc::from([1]), reads(3), 1, || 1)
        .unwrap();
    assert_eq!(selected(&shared, &[&[1]]), vec![(vec![1], 1)]);
    drop(lease);
    assert!(selected(&shared, &[&[1]]).is_empty());
    assert_eq!(*external, 1);
}
#[test]
fn direct_candidate_routing_still_checks_full_key_inside_collision_bucket() {
    let store = Store::current_revision();
    store.insert_with_receipt(Arc::from([1]), reads(3), Arc::from([]), 1, || 1);
    store.insert_with_receipt(Arc::from([2]), reads(4), Arc::from([]), 1, || 2);
    let target = xxhash_rust::xxh3::xxh3_128(&[1]);
    let other = xxhash_rust::xxh3::xxh3_128(&[2]);
    {
        let mut state = store.state.lock().unwrap();
        let collision = state.buckets.remove(&other).unwrap();
        state.buckets.get_mut(&target).unwrap().extend(collision);
    }
    assert_eq!(selected(&store, &[&[1]]), vec![(vec![1], 1)]);
    assert!(
        selected(&store, &[&[2]]).is_empty(),
        "misrouted hash is not authority"
    );
}

#[test]
fn fresh_incidence_variants_skip_removal_walk_and_replacement_keeps_exact_edges() {
    let store = Store::current_revision();
    store.enable_incidence();
    for key in 0u8..80 {
        store.insert_with_receipt(
            Arc::from([key]),
            reads(key),
            Arc::from([(key, 7)]),
            1,
            || key,
        );
    }
    {
        let state = store.state.lock().unwrap();
        assert_eq!(
            state.incidence.as_ref().unwrap().removal_visits,
            0,
            "new variants must not scan prior certificate subscriptions"
        );
    }
    store.insert_with_receipt(Arc::from([3]), reads(99), Arc::from([(99, 8)]), 1, || 81);
    assert!(affected(&store, 3).is_empty());
    assert_eq!(affected(&store, 99), vec![81]);
    assert_eq!(affected(&store, 4), vec![4]);
    assert!(
        store
            .state
            .lock()
            .unwrap()
            .incidence
            .as_ref()
            .unwrap()
            .removal_visits
            > 0
    );
    store.retain_current_keys(std::iter::empty());
    assert_eq!(store.visit_incidence_storage(|_| {}), Some((0, 0, 0, 0)));
}

#[test]
fn ordered_incidence_replacement_touches_only_its_reverse_domains() {
    let mut index = incidence::Incidence::default();
    for domain in (0u32..1024).rev() {
        let receipt: Receipt<u32, bool, u32> = vec![Observation {
            query: domain,
            answer: false,
            domain,
        }]
        .into();
        index.insert(domain as u64, domain as u128, &receipt, &[(domain, 7)]);
    }
    assert_eq!(index.removal_visits, 0);
    let current: Vec<_> = (0u32..1024).rev().map(|domain| (domain, Some(7))).collect();
    assert_eq!(index.certified(&current).len(), 1024);
    index.remove(511);
    assert_eq!(
        index.removal_visits, 1,
        "removal visits its one certificate, not global domains"
    );
    assert!(index.affected([&511]).is_empty());
    assert_eq!(index.affected([&512]), BTreeSet::from([512]));
    let receipt: Receipt<u32, bool, u32> = vec![Observation {
        query: 511,
        answer: false,
        domain: 511,
    }]
    .into();
    index.insert(511, 9, &receipt, &[(511, 7), (511, 8)]);
    assert!(
        !index.certified(&current).contains(&511),
        "conflicting certificates never authorize skipping replay"
    );
    index.insert(511, 9, &receipt, &[]);
    assert!(!index.certified(&current).contains(&511));
    assert!(index
        .certified_with_local(&current, Some(&511))
        .contains(&511));
    let mut changed = current;
    changed.iter_mut().find(|row| row.0 == 512).unwrap().1 = Some(8);
    assert!(!index.certified(&changed).contains(&512));
    for variant in 0..1024 {
        index.remove(variant);
    }
    assert_eq!(index.counts(), (0, 0, 0, 0));
}
