use super::*;
use std::sync::atomic::{AtomicUsize, Ordering};
type Store = ObservedArtifactStore<u8, u8, bool, u8>;
struct Host {
    version: Option<u128>,
    observing: bool,
    calls: AtomicUsize,
}
impl ObservationHost<u8, bool, u8> for Host {
    fn answer(&self, _: &u8) -> bool {
        self.calls.fetch_add(1, Ordering::Relaxed);
        self.version != Some(7) || self.observing
    }
    fn version(&self, _: &u8) -> Option<u128> {
        self.version
    }
    fn observes_answers(&self) -> bool {
        self.observing
    }
}
fn reads() -> Receipt<u8, bool, u8> {
    vec![Observation {
        query: 1,
        answer: false,
        domain: 2,
    }]
    .into()
}
#[test]
fn qualified_bulk_capabilities_preserve_negative_uncovered_and_observer_controls() {
    let store = Store::shared_current_rosters();
    store.enable_incidence();
    let published = store.lease();
    published.insert_with_qualified_receipt(Arc::from([1]), reads(), Arc::from([(2, 7)]), 1, || 11);
    published.insert_with_receipt(Arc::from([2]), reads(), 1, || 22);
    for (version, observing, expected) in [
        (Some(7), false, 1),
        (Some(8), false, 0),
        (None, false, 0),
        (Some(7), true, 0),
    ] {
        let host = Host {
            version,
            observing,
            calls: AtomicUsize::new(0),
        };
        let request = crate::ReceiptAdmission::new(&host);
        let candidates = store.unchanged_candidates(&request);
        assert_eq!(candidates.len(), expected);
        assert_eq!(host.calls.load(Ordering::Relaxed), 0);
        if expected == 0 {
            let current = store.lease();
            assert!(current
                .visit_explained(&[1], &host, &mut |_| true)
                .0
                .is_none());
            assert_eq!(host.calls.load(Ordering::Relaxed), 1);
        }
        if let Some(candidate) = candidates.into_iter().next() {
            let current = store.lease();
            let mut edges = 0;
            assert_eq!(
                *current
                    .claim_unchanged(
                        candidate,
                        &[1],
                        |value| **value == 11,
                        |leaf| edges += leaf.len()
                    )
                    .unwrap(),
                11
            );
            assert_eq!(edges, 1);
        }
    }
    drop(published);
    let host = Host {
        version: Some(7),
        observing: false,
        calls: AtomicUsize::new(0),
    };
    assert!(store
        .unchanged_candidates(&crate::ReceiptAdmission::new(&host))
        .is_empty());
}
#[test]
fn bulk_capability_requires_exact_key_and_independent_local_input_license() {
    let store = Store::current_revision();
    store.enable_incidence();
    store.insert_with_receipt(Arc::from([1]), reads(), Arc::from([(2, 7)]), 1, || 11);
    let host = Host {
        version: Some(7),
        observing: false,
        calls: AtomicUsize::new(0),
    };
    let request = crate::ReceiptAdmission::new(&host);
    let candidate = store.unchanged_candidates(&request).pop().unwrap();
    assert!(candidate
        .admit(&[9], |_| true, |_| panic!("foreign key edge"))
        .is_none());
    let candidate = store.unchanged_candidates(&request).pop().unwrap();
    assert!(candidate
        .admit(&[1], |_| false, |_| panic!("unlicensed input edge"))
        .is_none());
    store.insert_with_receipt(Arc::from([1]), reads(), Arc::from([(2, 8)]), 1, || 33);
    assert!(store.unchanged_candidates(&request).is_empty());
}
