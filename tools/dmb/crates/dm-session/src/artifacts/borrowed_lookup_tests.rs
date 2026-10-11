use super::*;
fn ledger(value: u32) -> Vec<Observation<u8, u32, u8>> {
    vec![Observation {
        query: 7,
        answer: value,
        domain: 1,
    }]
}
#[test]
fn borrowed_locator_exact_match_claims_the_same_owner_and_replays_changed_reads() {
    let store = ObservedArtifactStore::<u32, u8, u32, u8>::shared_current_rosters();
    let initial = store.lease();
    let key: Arc<[u8]> = Arc::from(b"identity:exact-body".as_slice());
    let value = initial
        .insert_with_owned(Arc::clone(&key), ledger(1), vec![], 3, || 17)
        .unwrap();
    let digest = xxhash_rust::xxh3::xxh3_128(&key);
    let current = store.lease();
    let mut changed = |reads: &Receipt<u8, u32, u8>, _: &[(u8, u128)], _: &Arc<u32>| {
        reads
            .iter()
            .find(|read| read.answer != 2)
            .map(|read| read.query)
    };
    let (miss, query) = current.visit_borrowed_receipted_with_value(
        digest,
        &|candidate| candidate == key.as_ref(),
        &mut changed,
        &mut |_| true,
    );
    assert!(miss.is_none());
    assert_eq!(query, Some(7));
    let accepted = current
        .visit_borrowed_receipted_with_value(
            digest,
            &|candidate| {
                assert!(!store.is_empty()); // key callback must be outside the core lock
                candidate == key.as_ref()
            },
            &mut |_, _, _| None,
            &mut |_| true,
        )
        .0
        .unwrap();
    assert!(Arc::ptr_eq(&accepted.value, &value));
    drop(initial);
    assert!(!store.is_empty());
    drop(current);
    assert!(store.is_empty());
}
#[test]
fn colliding_or_forged_locator_never_validates_or_claims_an_inexact_key() {
    let store = ObservedArtifactStore::<u32, u8, u32, u8>::shared_current_rosters();
    let seed = store.lease();
    let key: Arc<[u8]> = Arc::from(b"identity:exact-body".as_slice());
    seed.insert_with_owned(Arc::clone(&key), ledger(1), vec![], 1, || 11)
        .unwrap();
    let digest = xxhash_rust::xxh3::xxh3_128(&key);
    // Deliberately construct a collision bucket: digest is only a locator and
    // cannot authenticate this unrelated immutable key or its answer ledger.
    store
        .state
        .lock()
        .unwrap()
        .buckets
        .get_mut(&digest)
        .unwrap()
        .push(Variant {
            key: Arc::from(b"forged:exact-body".as_slice()),
            reads: ledger(9).into(),
            versions: Arc::from([]),
            value: Arc::new(99),
            weight: 0,
        });
    let current = store.lease();
    let mut visits = 0;
    let result = current
        .visit_borrowed_receipted_with_value(
            digest,
            &|candidate| candidate == key.as_ref(),
            &mut |_, _, value| {
                visits += 1;
                assert_eq!(**value, 11);
                None
            },
            &mut |_| true,
        )
        .0
        .unwrap();
    assert_eq!(*result.value, 11);
    assert_eq!(visits, 1);
    let result = current.visit_borrowed_receipted_with_value(
        digest,
        &|candidate| candidate == b"identity:changed-body",
        &mut |_, _, _| panic!("wrong key cannot replay reads"),
        &mut |_| panic!("wrong key cannot acquire a claim"),
    );
    assert!(result.0.is_none());
    assert!(result.1.is_none());
}

#[test]
fn borrowed_claim_reattaches_the_same_stored_key_after_origin_lease_drops() {
    let store = ObservedArtifactStore::<u32, u8, u32, u8>::shared_current_rosters();
    let mut original = Some(store.lease());
    let key: Arc<[u8]> = Arc::from(b"owner:body".as_slice());
    let value = original
        .as_ref()
        .unwrap()
        .insert_with_owned(Arc::clone(&key), ledger(1), vec![], 5, || 21)
        .unwrap();
    let current = store.lease();
    let digest = xxhash_rust::xxh3::xxh3_128(&key);
    let accepted = current
        .visit_borrowed_receipted_with_value(
            digest,
            &|candidate| candidate == key.as_ref(),
            &mut |reads, _, _| {
                assert!(reads.iter().all(|read| read.answer == 1));
                None
            },
            &mut |_| {
                drop(original.take());
                assert!(store.is_empty());
                true
            },
        )
        .0
        .unwrap();
    assert!(Arc::ptr_eq(&accepted.value, &value));
    let state = store.state.lock().unwrap();
    let entry = &state.buckets[&digest][0];
    assert!(Arc::ptr_eq(&entry.key, &key));
    assert_eq!(state.bytes, 5);
    drop(state);
    drop(current);
    assert!(store.is_empty());
}
