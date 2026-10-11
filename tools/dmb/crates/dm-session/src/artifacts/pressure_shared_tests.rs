use super::*;
struct Payload {
    shared: Arc<Vec<u8>>,
    unknown: bool,
}
type Store = ObservedArtifactStore<Payload, u8, u8, u8>;
fn allocation(value: &Arc<Payload>) -> Vec<PressureAllocation> {
    vec![
        PressureAllocation {
            address: Arc::as_ptr(value) as usize,
            bytes: std::mem::size_of::<Payload>() + 64,
        },
        PressureAllocation {
            address: value.shared.as_ptr() as usize,
            bytes: value.shared.capacity() + 64,
        },
    ]
}
#[test]
fn shared_backing_is_charged_once_and_survivor_takes_removed_owner_charge() {
    let store = Store::shared_current_rosters();
    let lease = store.lease();
    let shared = Arc::new(vec![0; 4096]);
    for key in [b"a".as_slice(), b"b".as_slice()] {
        lease
            .insert_with_owned(Arc::from(key), Vec::new(), Vec::new(), 1, || Payload {
                shared: shared.clone(),
                unknown: false,
            })
            .unwrap();
    }
    let report =
        store.prune_for_pressure_shared(usize::MAX, |_, _, _, value, _| Some(allocation(value)));
    assert_eq!(report.retained_entries, 2);
    assert_eq!(
        report.payload_bytes,
        4096 + 64 + 2 * (std::mem::size_of::<Payload>() + 64)
    );
    assert!(store.admitted_bytes() > report.charged_bytes); // standalone conservative weights
    lease.retain_current_keys([b"b".as_slice()]);
    let report =
        store.prune_for_pressure_shared(usize::MAX, |_, _, _, value, _| Some(allocation(value)));
    assert_eq!(report.retained_entries, 1);
    assert_eq!(
        report.payload_bytes,
        4096 + 64 + std::mem::size_of::<Payload>() + 64
    );
}
#[test]
fn rejected_footprint_never_licenses_surviving_shared_bytes() {
    let store = Store::shared_current_rosters();
    let lease = store.lease();
    let shared = Arc::new(vec![0; 4096]);
    for (key, unknown) in [(b"a".as_slice(), true), (b"b".as_slice(), false)] {
        lease
            .insert_with_owned(Arc::from(key), Vec::new(), Vec::new(), 1, || Payload {
                shared: shared.clone(),
                unknown,
            })
            .unwrap();
    }
    let report = store.prune_for_pressure_shared(usize::MAX, |_, _, _, value, _| {
        if value.unknown {
            None
        } else {
            Some(allocation(value))
        }
    });
    assert_eq!(report.retained_entries, 1);
    assert_eq!(report.evicted_entries, 1);
    assert_eq!(
        report.payload_bytes,
        4096 + 64 + std::mem::size_of::<Payload>() + 64
    );
}
#[test]
fn unlocked_callback_removal_and_new_row_are_reconciled_exactly() {
    let store = Store::shared_current_rosters();
    let lease = store.lease();
    let shared = Arc::new(vec![0; 64]);
    lease
        .insert_with_owned(
            Arc::from(b"old".as_slice()),
            Vec::new(),
            Vec::new(),
            1,
            || Payload {
                shared: shared.clone(),
                unknown: false,
            },
        )
        .unwrap();
    let report = store.prune_for_pressure_shared(usize::MAX, |_, _, _, value, _| {
        lease.retain_current_keys(std::iter::empty::<&[u8]>());
        lease
            .insert_with_owned(
                Arc::from(b"new".as_slice()),
                Vec::new(),
                Vec::new(),
                1,
                || Payload {
                    shared: shared.clone(),
                    unknown: false,
                },
            )
            .unwrap();
        Some(allocation(value))
    });
    assert_eq!(report.retained_entries, 0);
    assert_eq!(report.payload_bytes, 0);
    assert_eq!(report.evicted_entries, 1);
    assert_eq!(store.admitted_bytes(), 0);
}
#[test]
fn inconsistent_allocation_sizes_decline_and_zero_budget_removes_every_row() {
    let store = Store::shared_current_rosters();
    let lease = store.lease();
    let shared = Arc::new(vec![0; 64]);
    for key in [b"a".as_slice(), b"b".as_slice()] {
        lease
            .insert_with_owned(Arc::from(key), Vec::new(), Vec::new(), 1, || Payload {
                shared: shared.clone(),
                unknown: false,
            })
            .unwrap();
    }
    let mut calls = 0;
    let report = store.prune_for_pressure_shared(usize::MAX, |_, _, _, value, _| {
        calls += 1;
        let mut result = allocation(value);
        result[1].bytes += calls;
        Some(result)
    });
    assert_eq!(report.retained_entries, 1);
    assert_eq!(report.evicted_entries, 1);
    let report = store.prune_for_pressure_shared(0, |_, _, _, value, _| Some(allocation(value)));
    assert_eq!(report.retained_entries, 0);
    assert_eq!(report.charged_bytes, 0);
}

#[test]
fn current_claim_growth_after_footprint_rejects_without_committing_shared_charge() {
    let store = Store::shared_current_rosters();
    let first = store.lease();
    let shared = Arc::new(vec![0; 64]);
    let escaped = first
        .insert_with_owned(Arc::from(b"key".as_slice()), vec![], vec![], 1, || {
            Payload {
                shared: shared.clone(),
                unknown: false,
            }
        })
        .unwrap();
    let original =
        store.prune_for_pressure_shared(usize::MAX, |_, _, _, value, _| Some(allocation(value)));
    let second = store.lease();
    let rejected = store.prune_for_pressure_shared(original.charged_bytes, |_, _, _, value, _| {
        let (accepted, changed) =
            second.visit_receipted_with(b"key", &mut |_, _| None, &mut |_| true);
        assert!(accepted.is_some());
        assert!(changed.is_none());
        Some(allocation(value))
    });
    assert_eq!(rejected.retained_entries, 0);
    assert_eq!(rejected.payload_bytes, 0);
    assert_eq!(rejected.evicted_entries, 1);
    assert_eq!(escaped.shared.len(), 64);
}
