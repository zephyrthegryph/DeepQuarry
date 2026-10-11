use super::*;
struct Host(u32);
impl ObservationHost<u8, u32, u8> for Host {
    fn answer(&self, _: &u8) -> u32 {
        self.0
    }
    // Deliberately identical numbers from unrelated issuers must NOT skip reads.
    fn version(&self, _: &u8) -> Option<u128> {
        Some(9)
    }
}
fn reads(value: u32) -> Vec<Observation<u8, u32, u8>> {
    vec![Observation {
        domain: 0,
        query: 0,
        answer: value,
    }]
}
#[test]
fn two_host_variants_same_key_survive_roster_changes_and_drop_independently() {
    let store = ObservedArtifactStore::<u32, u8, u32, u8>::shared_current_rosters();
    let a = store.lease();
    let b = store.lease();
    let key: Arc<[u8]> = Arc::from(b"owner".as_slice());
    let first = a
        .insert_with_owned(Arc::clone(&key), reads(1), vec![(0, 9)], 1, || 11)
        .unwrap();
    let second = b
        .insert_with_owned(Arc::clone(&key), reads(2), vec![(0, 9)], 2, || 22)
        .unwrap();
    assert!(!Arc::ptr_eq(&first, &second));
    let hit = a.visit_explained(&key, &Host(1), &mut |_| true).0.unwrap();
    assert!(Arc::ptr_eq(&hit, &first));
    assert!(a.visit_explained(&key, &Host(3), &mut |_| true).0.is_none());
    b.retain_current_keys(std::iter::empty());
    assert_eq!(store.admitted_bytes(), 1);
    let weak_second = Arc::downgrade(&second);
    drop(second);
    assert!(weak_second.upgrade().is_none());
    let shared = b.visit_explained(&key, &Host(1), &mut |_| true).0.unwrap();
    assert!(Arc::ptr_eq(&shared, &first));
    drop(a);
    assert_eq!(store.admitted_bytes(), 1);
    drop(b);
    assert_eq!(store.admitted_bytes(), 0);
    assert_eq!(*shared, 11);
}
#[test]
fn exact_same_read_insert_shares_owner_and_consumer_decline_does_not_claim() {
    let store = ObservedArtifactStore::<u32, u8, u32, u8>::shared_current_rosters();
    let a = store.lease();
    let b = store.lease();
    let key: Arc<[u8]> = Arc::from(b"owner".as_slice());
    let first = a
        .insert_with_owned(Arc::clone(&key), reads(1), vec![], 7, || 11)
        .unwrap();
    let shared = b
        .insert_with_owned(Arc::clone(&key), reads(1), vec![], 7, || {
            panic!("exact immutable producer already exists")
        })
        .unwrap();
    assert!(Arc::ptr_eq(&first, &shared));
    b.retain_current_keys(std::iter::empty());
    assert!(b
        .visit_explained(&key, &Host(1), &mut |_| false)
        .0
        .is_none());
    drop(a);
    assert_eq!(store.admitted_bytes(), 0);
}

#[test]
fn replacing_one_host_variant_updates_only_its_claim_and_bytes() {
    let store = ObservedArtifactStore::<u32, u8, u32, u8>::shared_current_rosters();
    let a = store.lease();
    let b = store.lease();
    let key: Arc<[u8]> = Arc::from(b"owner".as_slice());
    a.insert_with(Arc::clone(&key), reads(1), vec![], 3, || 1);
    b.visit_explained(&key, &Host(1), &mut |_| true);
    a.insert_with(Arc::clone(&key), reads(2), vec![], 5, || 2);
    assert_eq!(store.admitted_bytes(), 8);
    {
        let state = store.state.lock().unwrap();
        assert_eq!(state.claims.len(), 2);
        assert!(state.claims.values().all(|(_, count)| *count == 1));
    }
    b.retain_current_keys(std::iter::empty());
    assert_eq!(store.admitted_bytes(), 5);
    drop(a);
    assert_eq!(store.admitted_bytes(), 0);
    assert!(store.state.lock().unwrap().claims.is_empty());
}
struct DropProbe {
    store: std::sync::Weak<ObservedArtifactStore<DropProbe, u8, u32, u8>>,
    unlocked: Arc<std::sync::atomic::AtomicBool>,
}
impl Drop for DropProbe {
    fn drop(&mut self) {
        if let Some(store) = self.store.upgrade() {
            self.unlocked.store(
                store.state.try_lock().is_ok(),
                std::sync::atomic::Ordering::SeqCst,
            );
        }
    }
}
#[test]
fn roster_pruning_and_lease_drop_destroy_payloads_after_unlock() {
    for clear_roster in [false, true] {
        let store = ObservedArtifactStore::<DropProbe, u8, u32, u8>::shared_current_rosters();
        let lease = store.lease();
        let unlocked = Arc::new(std::sync::atomic::AtomicBool::new(false));
        lease.insert_with(Arc::from(b"probe".as_slice()), reads(1), vec![], 1, || {
            DropProbe {
                store: Arc::downgrade(&store),
                unlocked: Arc::clone(&unlocked),
            }
        });
        if clear_roster {
            lease.retain_current_keys(std::iter::empty());
        }
        drop(lease);
        assert!(unlocked.load(std::sync::atomic::Ordering::SeqCst));
        assert_eq!(store.admitted_bytes(), 0);
    }
}

#[test]
fn accepted_receipt_shares_exact_ledger_and_claims_only_after_admission() {
    let store = ObservedArtifactStore::<u32, u8, u32, u8>::shared_current_rosters();
    let published = store.lease();
    let pending = store.lease();
    let value = published
        .insert_with_owned(Arc::from(b"owner".as_slice()), reads(1), vec![], 7, || 11)
        .unwrap();
    assert!(pending
        .visit_explained_accepted(b"owner", &Host(1), &mut |_| false)
        .0
        .is_none());
    let accepted = pending
        .visit_explained_accepted(b"owner", &Host(1), &mut |_| true)
        .0
        .unwrap();
    assert!(Arc::ptr_eq(&accepted.value, &value));
    assert_eq!(accepted.reads.iter().count(), 1);
    assert_eq!(accepted.reads.iter().next().unwrap().answer, 1);
    drop(published);
    assert_eq!(store.admitted_bytes(), 7);
    drop(pending);
    assert_eq!(store.admitted_bytes(), 0);
    assert_eq!(*accepted.value, 11);
}
