use super::*;
use crate::ReceiptGroupPool;
use std::sync::atomic::{AtomicUsize, Ordering};
struct Host {
    calls: AtomicUsize,
    present: bool,
}
impl ObservationHost<u32, Option<u32>, ()> for Host {
    fn answer(&self, query: &u32) -> Option<u32> {
        self.calls.fetch_add(1, Ordering::Relaxed);
        self.present.then_some(*query)
    }
}
fn reads() -> Vec<Observation<u32, Option<u32>, ()>> {
    (0..4)
        .map(|query| Observation {
            domain: (),
            query,
            answer: None,
        })
        .collect()
}
#[test]
fn shared_negative_leaves_validate_once_and_always_reach_observer() {
    let pool = ReceiptGroupPool::default();
    let first = pool
        .intern_receipt(reads(), |a, b| a.query / 2 == b.query / 2)
        .unwrap();
    let second = pool
        .intern_receipt(reads(), |a, b| a.query / 2 == b.query / 2)
        .unwrap();
    assert_eq!(
        first.iter().collect::<Vec<_>>(),
        second.iter().collect::<Vec<_>>()
    );
    let host = Host {
        calls: AtomicUsize::new(0),
        present: false,
    };
    let admission = ReceiptAdmission::new(&host);
    let mut recorded = Vec::new();
    assert_eq!(
        admission.first_changed(&first, |leaf| recorded.push(Arc::clone(leaf))),
        None
    );
    assert_eq!(
        admission.first_changed(&second, |leaf| {
            assert!(admission.leaves.try_lock().is_ok());
            recorded.push(Arc::clone(leaf));
        }),
        None
    );
    assert_eq!(host.calls.load(Ordering::Relaxed), 4);
    assert_eq!(recorded.len(), 4);
    assert!(Arc::ptr_eq(&recorded[0], &recorded[2]));
    let changed_host = Host {
        calls: AtomicUsize::new(0),
        present: true,
    };
    let changed = ReceiptAdmission::new(&changed_host);
    assert_eq!(
        changed.first_changed(&second, |_| panic!("negative answer no longer holds")),
        Some(0)
    );
    assert_eq!(changed_host.calls.load(Ordering::Relaxed), 1);
}
#[test]
fn grouping_keeps_conflicting_answers_and_rejects_noncanonical_input() {
    let pool = ReceiptGroupPool::default();
    let observations = vec![
        Observation {
            domain: (),
            query: 1,
            answer: None,
        },
        Observation {
            domain: (),
            query: 1,
            answer: Some(1),
        },
    ];
    let receipt = pool
        .intern_receipt(observations.clone(), |_, _| true)
        .unwrap();
    assert_eq!(receipt.iter().cloned().collect::<Vec<_>>(), observations);
    let host = Host {
        calls: AtomicUsize::new(0),
        present: false,
    };
    assert_eq!(
        ReceiptAdmission::new(&host).first_changed(&receipt, |_| {}),
        Some(1)
    );
    assert!(pool
        .intern_receipt(
            vec![
                Observation {
                    domain: (),
                    query: 2,
                    answer: None::<u32>
                },
                Observation {
                    domain: (),
                    query: 1,
                    answer: None
                },
            ],
            |_, _| true
        )
        .is_err());
}
