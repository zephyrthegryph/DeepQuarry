use super::*;
#[test]
fn payload_validation_is_reentrant_and_declined_consumers_never_claim() {
    let store: Arc<ObservedArtifactStore<u128, u32, bool, ()>> =
        ObservedArtifactStore::shared_current_rosters();
    let published = store.lease();
    let key: Arc<[u8]> = Arc::from(b"payload".as_slice());
    assert!(published
        .insert_with_owned(
            key.clone(),
            vec![Observation {
                domain: (),
                query: 1,
                answer: false
            }],
            vec![],
            1,
            || 7
        )
        .is_some());
    let request = store.lease();
    let mut callbacks = 0;
    let (rejected, _) = request.visit_receipted_with_value(
        &key,
        &mut |reads, versions, payload| {
            // Would deadlock if validation still held the artifact store lock.
            store.visit_storage(|_| {});
            assert_eq!(reads.len(), 1);
            assert!(versions.is_empty());
            assert_eq!(**payload, 7);
            callbacks += 1;
            None
        },
        &mut |_| false,
    );
    assert!(rejected.is_none());
    assert_eq!(callbacks, 1);
    drop(published);
    assert!(store
        .visit_receipted_with_value(&key, &mut |_, _, _| None, &mut |_| true)
        .0
        .is_none());
}
#[test]
fn payload_validation_preserves_variant_order_and_replays_changed_versions() {
    struct Host {
        answers: std::cell::Cell<usize>,
        version: Option<u128>,
    }
    impl ObservationHost<u32, bool, ()> for Host {
        fn answer(&self, _: &u32) -> bool {
            self.answers.set(self.answers.get() + 1);
            false
        }
        fn version(&self, _: &()) -> Option<u128> {
            self.version
        }
    }
    let store: Arc<ObservedArtifactStore<u128, u32, bool, ()>> =
        ObservedArtifactStore::shared_current_rosters();
    let old = store.lease();
    let newest = store.lease();
    let current = store.lease();
    let key: Arc<[u8]> = Arc::from(b"variants".as_slice());
    assert!(old
        .insert_with_owned(
            key.clone(),
            vec![Observation {
                domain: (),
                query: 1,
                answer: false
            }],
            vec![],
            1,
            || 7
        )
        .is_some());
    assert!(newest
        .insert_with_owned(
            key.clone(),
            vec![Observation {
                domain: (),
                query: 1,
                answer: true
            }],
            vec![],
            1,
            || 8
        )
        .is_some());
    let host = Host {
        answers: std::cell::Cell::new(0),
        version: Some(7),
    };
    let admission = crate::ReceiptAdmission::new(&host);
    let mut order = Vec::new();
    let mut edges = 0;
    let (selected, _) = current.visit_receipted_with_value(
        &key,
        &mut |reads, _, payload| {
            order.push(**payload);
            admission.first_changed_receipted(reads, &[((), **payload)], |leaf| edges += leaf.len())
        },
        &mut |_| true,
    );
    assert_eq!(order, vec![8, 7]);
    assert_eq!(*selected.as_ref().unwrap().value, 7);
    assert_eq!(host.answers.get(), 1);
    assert_eq!(edges, 1);
    drop(old);
    drop(newest);
    assert!(selected.is_some());
}
