use super::*;
struct Host(u32);
impl ObservationHost<u8, u32, u8> for Host {
    fn answer(&self, _: &u8) -> u32 {
        self.0
    }
    // Deliberately identical numbers from unrelated issuers must NOT skip reads.
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
        .insert_with_owned(Arc::clone(&key), reads(1),1, || 11)
        .unwrap();
    let second = b
        .insert_with_owned(Arc::clone(&key), reads(2),2, || 22)
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
        .insert_with_owned(Arc::clone(&key), reads(1), 7, || 11)
        .unwrap();
    let shared = b
        .insert_with_owned(Arc::clone(&key), reads(1), 7, || {
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
    a.insert_with(Arc::clone(&key), reads(1), 3, || 1);
    b.visit_explained(&key, &Host(1), &mut |_| true);
    a.insert_with(Arc::clone(&key), reads(2), 5, || 2);
    assert_eq!(store.admitted_bytes(), 8);
    {
        let state = store.state.write().unwrap();
        assert_eq!(state.claimed_variants(), 2);
        assert!(state.claim_counts().iter().all(|count| *count == 1));
    }
    b.retain_current_keys(std::iter::empty());
    assert_eq!(store.admitted_bytes(), 5);
    drop(a);
    assert_eq!(store.admitted_bytes(), 0);
    assert_eq!(store.state.write().unwrap().claimed_variants(), 0);
}
struct DropProbe {
    store: std::sync::Weak<ObservedArtifactStore<DropProbe, u8, u32, u8>>,
    unlocked: Arc<std::sync::atomic::AtomicBool>,
}
impl Drop for DropProbe {
    fn drop(&mut self) {
        if let Some(store) = self.store.upgrade() {
            self.unlocked.store(
                store.state.try_write().is_ok(),
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
        lease.insert_with(Arc::from(b"probe".as_slice()), reads(1), 1, || {
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
        .insert_with_owned(Arc::from(b"owner".as_slice()), reads(1), 7, || 11)
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

#[test]
fn custom_current_receipt_proof_claims_only_after_complete_consumer_admission() {
    let store = ObservedArtifactStore::<u32, u8, u32, u8>::shared_current_rosters();
    let published = store.lease();
    let key: Arc<[u8]> = Arc::from(b"recipe".as_slice());
    let value = published
        .insert_with_owned(Arc::clone(&key), reads(7), 1, || 19)
        .unwrap();
    let weak = Arc::downgrade(&value);
    drop(value);
    let pending = store.lease();
    let mut consumer_called = false;
    let rejected = pending.visit_receipted_with(
        &key,
        &mut |receipt| {
            assert_eq!(receipt.iter().next().unwrap().answer, 7);
            Some(0)
        },
        &mut |_| {
            consumer_called = true;
            true
        },
    );
    assert!(rejected.0.is_none());
    assert_eq!(rejected.1, Some(0));
    assert!(!consumer_called);
    let declined = pending.visit_receipted_with(&key, &mut |_| None, &mut |_| false);
    assert!(declined.0.is_none());
    drop(published);
    assert!(weak.upgrade().is_none());
    assert_eq!(store.admitted_bytes(), 0);
}

#[test]
fn bounded_shared_rosters_charge_unique_values_and_never_evict_live_claims() {
    let store = ObservedArtifactStore::<u32, u8, u32, u8>::shared_current_rosters_with_limit(2);
    let first = store.lease();
    let key: Arc<[u8]> = Arc::from(b"first".as_slice());
    let value = first
        .insert_with_owned(Arc::clone(&key), reads(1), 2, || 11)
        .unwrap();
    let second = store.lease();
    assert!(second
        .insert_with_owned(
            Arc::from(b"second".as_slice()),
            reads(1),
            1,
            || panic!("budget miss must not construct payload")
        )
        .is_none());
    let shared = second
        .insert_with_owned(Arc::clone(&key), reads(1), 2, || {
            panic!("same exact producer must share")
        })
        .unwrap();
    assert!(Arc::ptr_eq(&value, &shared));
    assert_eq!(store.admitted_bytes(), 2);
    assert_eq!(store.available_bytes(), 0);
    drop(first);
    assert_eq!(store.admitted_bytes(), 2);
    drop(second);
    assert_eq!(store.admitted_bytes(), 0);
    assert_eq!(*value, 11);
}
#[test]
fn bounded_reattachment_declines_if_other_live_roster_consumed_the_budget() {
    let store = ObservedArtifactStore::<u32, u8, u32, u8>::shared_current_rosters_with_limit(2);
    let first = store.lease();
    let key: Arc<[u8]> = Arc::from(b"old".as_slice());
    let value = first
        .insert_with_owned(Arc::clone(&key), reads(1), 2, || 11)
        .unwrap();
    let weak = Arc::downgrade(&value);
    drop(value);
    let first = std::cell::RefCell::new(Some(first));
    let pending = store.lease();
    let competing = store.lease();
    let hit = pending
        .visit_explained_accepted(&key, &Host(1), &mut |_| {
            // Replay holds only the accepted value, not the core mutex. The old
            // owning lease disappears and another exact live value takes its charge.
            drop(first.borrow_mut().take());
            assert!(competing
                .insert_with_owned(Arc::from(b"new".as_slice()), reads(1), 2, || 22)
                .is_some());
            true
        })
        .0;
    assert!(hit.is_none());
    assert!(weak.upgrade().is_none());
    assert_eq!(store.admitted_bytes(), 2);
    assert!(competing
        .visit_explained(b"new", &Host(1), &mut |_| true)
        .0
        .is_some());
    drop(pending);
    drop(competing);
    assert_eq!(store.admitted_bytes(), 0);
}
#[test]
fn bounded_shared_roster_callbacks_can_admit_in_parallel_outside_core_lock() {
    use std::{sync::mpsc, time::Duration};
    let store = ObservedArtifactStore::<u32, u8, u32, u8>::shared_current_rosters_with_limit(2);
    let first = store.lease();
    for key in [b"a", b"b"] {
        first
            .insert_with_owned(Arc::from(key.as_slice()), reads(1), 1, || 7)
            .unwrap();
    }
    let (started, observed) = mpsc::channel();
    std::thread::scope(|scope| {
        let mut workers = Vec::new();
        let mut releases = Vec::new();
        for key in [b"a", b"b"] {
            let lease = store.lease();
            let started = started.clone();
            let (release, gate) = mpsc::channel();
            releases.push(release);
            workers.push(scope.spawn(move || {
                lease
                    .visit_explained(key, &Host(1), &mut |_| {
                        started.send(()).unwrap();
                        gate.recv_timeout(Duration::from_secs(3))
                            .expect("bounded callback release");
                        true
                    })
                    .0
                    .is_some()
            }));
        }
        for _ in 0..2 {
            observed
                .recv_timeout(Duration::from_secs(2))
                .expect("both callbacks must enter concurrently");
        }
        for release in releases {
            release.send(()).unwrap();
        }
        for worker in workers {
            assert!(worker.join().unwrap());
        }
    });
    assert_eq!(store.admitted_bytes(), 2);
}

#[path = "rebind_tests.rs"]
mod rebind_tests;
#[test]
fn retain_where_releases_only_this_leases_rejected_keys() {
    let store = ObservedArtifactStore::<u32, u8, u32, u8>::shared_current_rosters();
    let a = store.lease();
    let b = store.lease();
    let keep: Arc<[u8]> = Arc::from(b"keep-1".as_slice());
    let drop_key: Arc<[u8]> = Arc::from(b"drop-1".as_slice());
    a.insert_with_owned(Arc::clone(&keep), reads(1), 3, || 1).unwrap();
    let doomed = a.insert_with_owned(Arc::clone(&drop_key), reads(1), 5, || 2).unwrap();
    let shared = b.insert_with_owned(Arc::clone(&drop_key), reads(1), 5, || 2).unwrap();
    assert!(Arc::ptr_eq(&doomed, &shared));
    assert_eq!(store.admitted_bytes(), 8);
    a.retain_where(|key| key.starts_with(b"keep"));
    // The sibling lease still holds the shared variant; only `a` let go of it.
    assert_eq!(store.admitted_bytes(), 8);
    b.retain_where(|key| key.starts_with(b"keep"));
    drop(doomed);
    drop(shared);
    assert_eq!(store.admitted_bytes(), 3);
    assert!(a.visit_explained(&keep, &Host(1), &mut |_| true).0.is_some());
    assert!(a.visit_explained(&drop_key, &Host(1), &mut |_| true).0.is_none());
}

#[test]
fn lease_slots_hold_every_claim_as_a_bit_and_are_reused_after_drop() {
    let store = ObservedArtifactStore::<u32, u8, u32, u8>::shared_current_rosters();
    let leases: Vec<_> = (0..128).map(|_| store.lease()).collect();
    let key: Arc<[u8]> = Arc::from(b"owner".as_slice());
    let first = leases[0].insert_with_owned(Arc::clone(&key), reads(1), 3, || 1).unwrap();
    for lease in &leases[1..] {
        let (found, _) = lease.visit_explained(&key, &Host(1), &mut |_| true);
        assert!(Arc::ptr_eq(&found.unwrap(), &first));
    }
    assert_eq!(store.storage_accounting().claims, 128);
    assert_eq!(store.storage_accounting().claimed_variants, 1);
    assert_eq!(store.storage_accounting().leases, 128);
    // The variant lives until the last of the 128 claims goes.
    let mut leases = leases;
    while leases.len() > 1 {
        leases.pop();
        assert_eq!(store.admitted_bytes(), 3);
    }
    drop(leases);
    assert_eq!(store.admitted_bytes(), 0);
    assert_eq!(store.storage_accounting().leases, 0);
    // A freed slot is handed out again.
    let again = store.lease();
    again.insert_with(Arc::clone(&key), reads(1), 3, || 2);
    assert_eq!(store.storage_accounting().claims, 1);
    drop(again);
    assert_eq!(store.admitted_bytes(), 0);
}
#[test]
fn key_storage_reports_which_variants_this_lease_claims_and_claim_stored_adopts_one() {
    let store = ObservedArtifactStore::<u32, u8, u32, u8>::shared_current_rosters();
    let (a, b) = (store.lease(), store.lease());
    let key: Arc<[u8]> = Arc::from(b"unit".as_slice());
    let first = a.insert_with_owned(Arc::clone(&key), reads(1), 1, || 11).unwrap();
    let held = |lease: &ObservedArtifactLease<u32, u8, u32, u8>| {
        let mut seen = Vec::new();
        lease.visit_key_storage([key.as_ref()], |view, mine| {
            if let ObservedArtifactStorageView::Entry { value, .. } = view {
                seen.push((**value, mine));
            }
        });
        seen
    };
    assert_eq!(held(&a), [(11, true)]);
    assert_eq!(held(&b), [(11, false)]);
    assert!(b.claim_stored(&key, &first));
    assert_eq!(held(&b), [(11, true)]);
    // A different variant of the key replaces the claim; the sibling keeps the first one alive.
    let second = b.insert_with_owned(Arc::clone(&key), reads(2), 1, || 22).unwrap();
    assert_eq!(*second, 22);
    assert_eq!(held(&a), [(11, true), (22, false)]);
    drop(a);
    assert_eq!(store.admitted_bytes(), 1);
    // A released variant cannot be claimed back.
    assert!(!b.claim_stored(&key, &first));
}
