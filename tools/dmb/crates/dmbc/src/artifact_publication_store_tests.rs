use super::*;
struct Host(u8);
impl ObservationHost<u8, u8, u8> for Host {
    fn answer(&self, _: &u8) -> u8 {
        self.0
    }
    fn domain_version(&self, _: &u8) -> Option<u128> {
        None
    }
}
fn insert(store: &Store<Vec<u8>, u8, u8, u8>, name: &[u8], value: u8) -> Arc<Vec<u8>> {
    store
        .insert_with_owned(
            Arc::from(name),
            vec![Observation {
                query: 1,
                answer: value,
                domain: 1,
            }],
            vec![],
            1,
            || vec![value],
        )
        .unwrap()
}
#[test]
fn failed_and_ephemeral_rosters_preserve_published_exact_variant() {
    let owner = Store::current_revision();
    let first = owner.for_request(true);
    let original = insert(&first, b"same", 1);
    assert!(first.publish_successful());
    let failed = owner.for_request(true);
    let discarded = insert(&failed, b"same", 2);
    let weak = Arc::downgrade(&discarded);
    drop(discarded);
    drop(failed);
    assert!(weak.upgrade().is_none());
    let build = owner.for_request(true);
    let replay = build.lookup(b"same", &Host(1)).unwrap();
    assert!(Arc::ptr_eq(&original, &replay));
    let analysis = owner.for_request(false);
    insert(&analysis, b"other", 3);
    assert!(!analysis.publish_successful());
    assert!(build.publish_successful());
    assert!(owner.for_request(true).lookup(b"same", &Host(2)).is_none());
}
#[test]
fn successful_current_roster_releases_deleted_claim_and_seals_old_attempt() {
    let owner = Store::current_revision();
    let first = owner.for_request(true);
    let old = insert(&first, b"old", 1);
    let weak = Arc::downgrade(&old);
    drop(old);
    assert!(first.publish_successful());
    assert!(first.lookup(b"old", &Host(1)).is_none());
    let next = owner.for_request(true);
    insert(&next, b"new", 2);
    next.retain_current_keys([b"new".as_slice()]);
    assert!(next.publish_successful());
    assert!(weak.upgrade().is_none());
}

#[test]
fn bounded_failed_and_ephemeral_claims_preserve_published_variant_and_budget() {
    let owner = Store::with_limit(2);
    let first = owner.for_request(true);
    let original = insert(&first, b"same", 1);
    assert!(first.publish_successful());
    let analysis = owner.for_request(false);
    let temporary = insert(&analysis, b"same", 2);
    let weak = Arc::downgrade(&temporary);
    drop(temporary);
    assert!(!analysis.publish_successful());
    drop(analysis);
    assert!(weak.upgrade().is_none());
    let failed = owner.for_request(true);
    let temporary = insert(&failed, b"partial", 3);
    let weak = Arc::downgrade(&temporary);
    drop(temporary);
    drop(failed);
    assert!(weak.upgrade().is_none());
    let current = owner.for_request(true);
    assert!(Arc::ptr_eq(
        &original,
        &current.lookup(b"same", &Host(1)).unwrap()
    ));
    assert!(current.lookup(b"same", &Host(2)).is_none());
    // The successful lease still consumes one byte. Budget rejection must not
    // run a fresh producer or evict that lease to make room for a failed row.
    assert!(current
        .insert_with_owned(
            Arc::from(&b"oversized"[..]),
            vec![Observation {
                query: 1,
                answer: 4,
                domain: 1
            }],
            vec![],
            2,
            || panic!("over-budget producer"),
        )
        .is_none());
    assert!(Arc::ptr_eq(
        &original,
        &current.lookup(b"same", &Host(1)).unwrap()
    ));
    let accepted = insert(&current, b"new", 4);
    assert_eq!(accepted.as_slice(), &[4]);
    current.retain_current_keys([b"same".as_slice(), b"new".as_slice()]);
    assert!(current.publish_successful());
    let replay = owner.for_request(true);
    assert!(Arc::ptr_eq(
        &accepted,
        &replay.lookup(b"new", &Host(4)).unwrap()
    ));
}
