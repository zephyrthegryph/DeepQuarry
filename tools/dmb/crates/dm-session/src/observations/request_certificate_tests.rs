use super::*;
use crate::ObservedArtifactStore;
use std::sync::atomic::{AtomicUsize, Ordering};
struct Host {
    versions: AtomicUsize,
    answers: AtomicUsize,
    current: bool,
}
impl ObservationHost<u32, Option<u32>, u32> for Host {
    fn version(&self, domain: &u32) -> Option<u128> {
        self.versions.fetch_add(1, Ordering::Relaxed);
        (*domain == 1).then_some(if self.current { 8 } else { 7 })
    }
    fn answer(&self, query: &u32) -> Option<u32> {
        self.answers.fetch_add(1, Ordering::Relaxed);
        (*query == 0).then_some(10)
    }
}
fn host(current: bool) -> Host {
    Host {
        versions: AtomicUsize::new(0),
        answers: AtomicUsize::new(0),
        current,
    }
}
fn receipt() -> Receipt<u32, Option<u32>, u32> {
    vec![
        Observation {
            query: 0,
            domain: 0,
            answer: Some(10),
        },
        Observation {
            query: 1,
            domain: 1,
            answer: None,
        },
    ]
    .into()
}
#[test]
fn six_store_visits_share_current_certificates_but_replay_local_inputs() {
    let store = ObservedArtifactStore::current_revision();
    for key in 0u32..6 {
        assert!(store
            .insert_with_receipt(
                Arc::from(key.to_le_bytes()),
                receipt(),
                Arc::from([(0, 99), (1, 7)]),
                1,
                || key
            )
            .is_some());
    }
    let host = host(false);
    let request = ReceiptAdmission::new(&host);
    std::thread::scope(|scope| {
        for key in 0u32..6 {
            let store = &store;
            let request = &request;
            scope.spawn(move || {
                let accepted = store
                    .visit_receipted_in(&key.to_le_bytes(), request, &mut |_| true)
                    .0
                    .unwrap();
                assert_eq!(*accepted.value, key);
            });
        }
    });
    assert_eq!(host.versions.load(Ordering::Relaxed), 2);
    assert_eq!(
        host.answers.load(Ordering::Relaxed),
        6,
        "unavailable local domain must replay on every candidate"
    );
    assert!(store
        .visit_receipted_in(b"foreign", &request, &mut |_| true)
        .0
        .is_none());
    let stale_local: Receipt<_, _, _> = vec![Observation {
        query: 0,
        domain: 0,
        answer: Some(9),
    }]
    .into();
    store.insert_with_receipt(
        Arc::from(b"stale".as_slice()),
        stale_local,
        Arc::from([]),
        1,
        || 9,
    );
    assert_eq!(
        store
            .visit_receipted_in(b"stale", &request, &mut |_| true)
            .1,
        Some(0)
    );
}
#[test]
fn candidate_certificates_never_seed_shared_full_answer_verdicts() {
    let host = host(false);
    let request = ReceiptAdmission::new(&host);
    let reads: Receipt<_, _, _> = vec![Observation {
        query: 1,
        domain: 1,
        answer: Some(42),
    }]
    .into();
    let mut observed = 0;
    assert_eq!(
        request.first_changed_receipted(&reads, &[(1, 7)], |_| observed += 1),
        None
    );
    assert_eq!(observed, 1);
    assert!(request.leaves.lock().unwrap().is_empty());
    assert_eq!(
        request.first_changed_receipted(&reads, &[(1, 6)], |_| observed += 1),
        Some(1)
    );
    assert_eq!(host.versions.load(Ordering::Relaxed), 1);
    assert_eq!(observed, 1, "failed leaf cannot reach accepted observer");
    assert_eq!(request.first_changed(&reads, |_| observed += 1), Some(1));
}
#[test]
fn next_immutable_request_invalidates_negative_and_preserves_observable_replay() {
    let old = host(false);
    let old_request = ReceiptAdmission::new(&old);
    let reads = receipt();
    let mut edges = 0;
    for _ in 0..2 {
        assert_eq!(
            old_request.first_changed_receipted(&reads, &[(1, 7)], |leaf| edges += leaf.len()),
            None
        );
    }
    assert_eq!(edges, 4);
    assert_eq!(old.answers.load(Ordering::Relaxed), 2);
    let changed = host(true);
    let current = ReceiptAdmission::new(&changed);
    let stale: Receipt<_, _, _> = vec![Observation {
        query: 0,
        domain: 1,
        answer: None,
    }]
    .into();
    assert_eq!(
        current.first_changed_receipted(&stale, &[(1, 7)], |_| {}),
        Some(0)
    );
    assert_eq!(changed.versions.load(Ordering::Relaxed), 1);
}
