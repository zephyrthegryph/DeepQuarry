use super::*;
use crate::{
    observations::{first_changed_iter, ReceiptGroupPool},
    ObservedArtifactStore,
};
use std::collections::BTreeSet;
fn read(query: u8, answer: u8, domain: u8) -> Observation<u8, u8, u8> {
    Observation {
        query,
        answer,
        domain,
    }
}
#[test]
fn canonical_groups_preserve_conflicting_answers_and_domain_replay() {
    let shared: Arc<[_]> = vec![read(1, 7, 0), read(1, 8, 0)].into();
    let receipt = Receipt::from_groups(Arc::from([
        Arc::from([]),
        shared.clone(),
        Arc::from([read(2, 9, 1)]),
    ]))
    .unwrap();
    assert_eq!(
        receipt.iter().map(|read| read.answer).collect::<Vec<_>>(),
        vec![7, 8, 9]
    );
    assert_eq!(receipt.iter().len(), 3);
    assert!(receipt.flat().is_none());
    assert_eq!(
        first_changed_iter(receipt.iter(), &BTreeSet::new(), |_| 7, |a, b| a == b),
        Some(&1)
    );
    assert_eq!(
        first_changed_iter(receipt.iter(), &BTreeSet::from([0]), |_| 7, |a, b| a == b),
        Some(&2)
    );
    let clone = receipt.clone();
    let mut leaves = Vec::new();
    clone.visit_storage(|view| {
        if let ReceiptStorageView::Flat(value) = view {
            leaves.push(Arc::as_ptr(value) as *const () as usize);
        }
    });
    assert_eq!(leaves[1], Arc::as_ptr(&shared) as *const () as usize);
    assert_eq!(
        receipt.to_flat().as_ref(),
        &[read(1, 7, 0), read(1, 8, 0), read(2, 9, 1)]
    );
    assert!(Receipt::from_groups(Arc::from([
        Arc::from([read(2, 9, 0)]),
        Arc::from([read(1, 7, 0)])
    ]))
    .is_err());
}
#[test]
fn physical_pool_checks_all_answers_and_does_not_keep_leaves_alive() {
    let pool = ReceiptGroupPool::default();
    let a = pool.intern(vec![read(1, 7, 0), read(2, 8, 0)]);
    let b = pool.intern(vec![read(1, 7, 0), read(2, 8, 0)]);
    assert!(Arc::ptr_eq(&a, &b));
    let different = pool.intern(vec![read(1, 7, 0), read(2, 9, 0)]);
    assert!(!Arc::ptr_eq(&a, &different));
    let domain = pool.intern(vec![read(1, 7, 1), read(2, 8, 0)]);
    assert!(!Arc::ptr_eq(&a, &domain));
    let weak = Arc::downgrade(&a);
    drop(a);
    drop(b);
    drop(different);
    drop(domain);
    pool.prune();
    assert!(weak.upgrade().is_none());
    let mut buffers = 0;
    pool.visit_storage(|_, _, _| buffers += 1);
    assert_eq!(buffers, 0);
}
#[test]
fn grouped_lease_replays_exactly_across_issuers_and_releases_independently() {
    struct Host(u8);
    impl crate::ObservationHost<u8, u8, u8> for Host {
        fn answer(&self, _: &u8) -> u8 {
            self.0
        }
        fn version(&self, _: &u8) -> Option<u128> {
            Some(9)
        }
    }
    let store = ObservedArtifactStore::<u8, u8, u8, u8>::shared_current_rosters();
    let a = store.lease();
    let b = store.lease();
    let key: Arc<[u8]> = Arc::from(b"key".as_slice());
    let reads = Receipt::from_groups(Arc::from([Arc::from([read(1, 7, 0)])])).unwrap();
    let owner = a
        .insert_with_receipt(key.clone(), reads.clone(), 1, || 3)
        .unwrap();
    let other = b
        .insert_with_receipt(key.clone(), reads, 1, || panic!("exact owner should share"))
        .unwrap();
    assert!(Arc::ptr_eq(&owner, &other));
    assert!(b.visit_explained(&key, &Host(8), &mut |_| true).0.is_none());
    drop(a);
    assert_eq!(
        *b.visit_explained(&key, &Host(7), &mut |_| true).0.unwrap(),
        3
    );
    drop(b);
    assert_eq!(store.admitted_bytes(), 0);
}

#[test]
fn physical_pool_collision_overflow_is_fresh_and_storage_is_bounded() {
    let pool = ReceiptGroupPool::default();
    let owners: Vec<_> = (0..12)
        .map(|answer| pool.intern(vec![read(1, answer, 0)]))
        .collect();
    let first = pool.intern(vec![read(1, 0, 0)]);
    assert!(Arc::ptr_eq(&owners[0], &first));
    let overflow = pool.intern(vec![read(1, 11, 0)]);
    assert!(!Arc::ptr_eq(&owners[11], &overflow));
    assert_eq!(owners[11].as_ref(), overflow.as_ref());
    let element = std::mem::size_of::<std::sync::Weak<[Observation<u8, u8, u8>]>>();
    let mut buckets = 0;
    pool.visit_storage(|_, logical, capacity| {
        buckets += 1;
        assert_eq!(logical, 8 * element);
        assert_eq!(capacity, 8 * element);
    });
    assert_eq!(buckets, 1);
}
