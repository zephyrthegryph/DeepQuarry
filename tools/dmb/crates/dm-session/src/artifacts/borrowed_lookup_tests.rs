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
        .insert_with_owned(Arc::clone(&key), ledger(1), 3, || 17)
        .unwrap();
    let digest = xxhash_rust::xxh3::xxh3_128(&key);
    let current = store.lease();
    let mut changed = |reads: &Receipt<u8, u32, u8>, _: &Arc<u32>| {
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
            &mut |_, _| None,
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
    seed.insert_with_owned(Arc::clone(&key), ledger(1), 1, || 11)
        .unwrap();
    let digest = xxhash_rust::xxh3::xxh3_128(&key);
    // Deliberately construct a collision bucket: digest is only a locator and
    // cannot authenticate this unrelated immutable key or its answer ledger.
    store
        .state
        .write()
        .unwrap()
        .buckets
        .get_mut(&digest)
        .unwrap()
        .push(Variant {
            key: Arc::from(b"forged:exact-body".as_slice()),
            reads: ledger(9).into(),
            value: Arc::new(99),
            weight: 0,
            holders: Default::default(),
        });
    let current = store.lease();
    let mut visits = 0;
    let result = current
        .visit_borrowed_receipted_with_value(
            digest,
            &|candidate| candidate == key.as_ref(),
            &mut |_, value| {
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
        &mut |_, _| panic!("wrong key cannot replay reads"),
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
        .insert_with_owned(Arc::clone(&key), ledger(1), 5, || 21)
        .unwrap();
    let current = store.lease();
    let digest = xxhash_rust::xxh3::xxh3_128(&key);
    let accepted = current
        .visit_borrowed_receipted_with_value(
            digest,
            &|candidate| candidate == key.as_ref(),
            &mut |reads, _| {
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
    let state = store.state.write().unwrap();
    let entry = &state.buckets[&digest][0];
    assert!(Arc::ptr_eq(&entry.key, &key));
    assert_eq!(state.bytes, 5);
    drop(state);
    drop(current);
    assert!(store.is_empty());
}

#[test]
fn fallible_acceptance_preserves_actual_error_without_claim_and_same_input_recovers() {
    let store = ObservedArtifactStore::<u32, u8, u32, u8>::shared_current_rosters();
    let seed = store.lease();
    let key: Arc<[u8]> = Arc::from(b"actual-key".as_slice());
    let value = seed
        .insert_with_owned(key.clone(), ledger(1), 7, || 17)
        .unwrap();
    let current = store.lease();
    let digest = xxhash_rust::xxh3::xxh3_128(&key);
    let before = store.state.read().unwrap().claim_counts();
    let error = current
        .try_visit_borrowed_receipted_with_value(
            digest,
            &|actual| actual == key.as_ref(),
            &mut |_, _| Ok(None),
            &mut |_| {
                assert!(!store.is_empty(), "callback runs outside core lock");
                Err(std::io::Error::from_raw_os_error(1450))
            },
        )
        .err()
        .expect("actual consumer operation failed");
    assert_eq!(error.raw_os_error(), Some(1450));
    assert_eq!(
        before,
        store.state.read().unwrap().claim_counts(),
        "operation error must not attach pending claim"
    );
    let accepted = current
        .try_visit_borrowed_receipted_with_value::<std::io::Error>(
            digest,
            &|actual| actual == key.as_ref(),
            &mut |_, _| Ok(None),
            &mut |_| Ok(true),
        )
        .unwrap()
        .0
        .unwrap();
    assert!(Arc::ptr_eq(&accepted.value, &value));
    drop(seed);
    assert!(!store.is_empty());
    drop(current);
    assert!(store.is_empty());
}
#[test]
fn fallible_validation_aborts_before_consumer_and_never_falls_through_as_a_miss() {
    let store = ObservedArtifactStore::<u32, u8, u32, u8>::with_limit(64);
    let key: Arc<[u8]> = Arc::from(b"variants".as_slice());
    store.insert_with_receipt(key.clone(), ledger(1).into(), 1, || 11);
    store.insert_with_receipt(key.clone(), ledger(1).into(), 1, || 12);
    let mut accept_calls = 0;
    let error = store
        .try_visit_receipted_with_value(
            &key,
            &mut |_, _| {
                Err(std::io::Error::new(
                    std::io::ErrorKind::Interrupted,
                    "actual validation cancellation",
                ))
            },
            &mut |_| {
                accept_calls += 1;
                Ok(true)
            },
        )
        .err()
        .expect("actual validation failure");
    assert_eq!(error.kind(), std::io::ErrorKind::Interrupted);
    assert_eq!(error.to_string(), "actual validation cancellation");
    assert_eq!(accept_calls, 0);
    let mut order = Vec::new();
    let hit = store
        .try_visit_receipted_with_value::<std::io::Error>(&key, &mut |_, _| Ok(None), &mut |v| {
            order.push(**v);
            Ok(**v == 11)
        })
        .unwrap()
        .0
        .unwrap();
    assert_eq!(order, [12, 11]);
    assert_eq!(*hit.value, 11);
    let mut order = Vec::new();
    let error = store
        .try_visit_receipted_with_value(&key, &mut |_, _| Ok(None), &mut |v| {
            order.push(**v);
            Err(std::io::Error::new(
                std::io::ErrorKind::OutOfMemory,
                "actual acceptance quota",
            ))
        })
        .err()
        .expect("acceptance cannot become a miss");
    assert_eq!(error.kind(), std::io::ErrorKind::OutOfMemory);
    assert_eq!(order, [12]);
}
