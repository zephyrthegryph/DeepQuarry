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
fn request_roster_consumes_exact_keys_once_and_keeps_variant_precedence() {
    let store = Store::with_limit(8);
    store.insert_with_receipt(Arc::from([1]), reads(), 1, || 11);
    store.insert_with_receipt(Arc::from([1]), reads(), 1, || 12);
    store.insert_with_receipt(Arc::from([3]), reads(), 1, || 33);
    let host = Host {
        version: Some(7),
        observing: false,
        calls: AtomicUsize::new(0),
    };
    let request = crate::ReceiptAdmission::new(&host);
    let mut roster = UnchangedCandidates::from_proven(&request, store.variant_snapshot());
    assert!(roster.take(&[2]).is_empty());
    let first = roster.take(&[1]);
    let values: Vec<_> = first
        .into_iter()
        .map(|candidate| *candidate.admit(&[1], |_| true, |_| {}).unwrap().value)
        .collect();
    assert_eq!(values, vec![12, 11]);
    assert!(roster.take(&[1]).is_empty());
    assert_eq!(
        *roster
            .take(&[3])
            .pop()
            .unwrap()
            .admit(&[3], |_| true, |_| {})
            .unwrap()
            .value,
        33
    );
}

#[test]
fn prefix_dispatch_never_substitutes_for_complete_local_inputs() {
    let store = Store::current_revision();
    store.insert_with_receipt(Arc::from([1, 0]), reads(), 1, || 11);
    store.insert_with_receipt(Arc::from([1, 1]), reads(), 1, || 12);
    store.insert_with_receipt(Arc::from([2, 0]), reads(), 1, || 22);
    let host = Host {
        version: Some(7),
        observing: false,
        calls: AtomicUsize::new(0),
    };
    let request = crate::ReceiptAdmission::new(&host);
    let mut roster = UnchangedCandidates::from_proven(&request, store.variant_snapshot());
    let mut delivered = 0;
    let accepted: Vec<_> = roster
        .take_prefix(&[1])
        .into_iter()
        .filter_map(|candidate| {
            candidate.admit_current(
                |key, value| key == [1, 0] && **value == 11,
                |leaf| delivered += leaf.len(),
            )
        })
        .collect();
    assert_eq!(accepted.len(), 1);
    assert_eq!(accepted[0].0.as_ref(), &[1, 0]);
    assert_eq!(delivered, 1);
    assert_eq!(roster.take_prefix(&[2]).len(), 1);
}

#[test]
fn fallible_certified_local_check_delivers_no_reads_or_claim_before_success() {
    let store = Store::shared_current_rosters();
    let seed = store.lease();
    let key: Arc<[u8]> = Arc::from([1]);
    let original = seed
        .insert_with_receipt(key.clone(), reads(), 1, || 11)
        .unwrap();
    let host = Host {
        version: Some(7),
        observing: false,
        calls: AtomicUsize::new(0),
    };
    let request = crate::ReceiptAdmission::new(&host);
    let current = store.lease();
    let mut roster = UnchangedCandidates::from_proven(&request, store.variant_snapshot());
    let candidate = roster.take(&key).pop().unwrap();
    let mut delivered = 0;
    let error = current
        .try_claim_unchanged(
            candidate,
            &key,
            |_| {
                Err(std::io::Error::new(
                    std::io::ErrorKind::OutOfMemory,
                    "actual original body demand",
                ))
            },
            |leaf| delivered += leaf.len(),
        )
        .err()
        .expect("actual current-local failure");
    assert_eq!(error.kind(), std::io::ErrorKind::OutOfMemory);
    assert_eq!(delivered, 0);
    assert_eq!(store.state.read().unwrap().claim_counts(), [1]);
    let mut roster = UnchangedCandidates::from_proven(&request, store.variant_snapshot());
    let candidate = roster.take(&key).pop().unwrap();
    let value = current
        .try_claim_unchanged::<_, std::io::Error>(
            candidate,
            &key,
            |_| Ok(true),
            |leaf| delivered += leaf.len(),
        )
        .unwrap()
        .unwrap();
    assert!(Arc::ptr_eq(&original, &value));
    assert_eq!(delivered, 1);
    drop(seed);
    assert!(!store.is_empty());
    drop(current);
    assert!(store.is_empty());
}
