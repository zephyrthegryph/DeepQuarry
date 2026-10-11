//! Pressure may evict performance claims, but cannot change publication identity
//! or mutate another destination's escaped immutable artifact.
use super::*;
use crate::ArtifactPublication;
use std::sync::Barrier;

type Store = ObservedArtifactStore<Vec<u8>, u8, u32, u8>;
type Lease = ObservedArtifactLease<Vec<u8>, u8, u32, u8>;
struct Host(u32);
impl ObservationHost<u8, u32, u8> for Host {
    fn answer(&self, _: &u8) -> u32 {
        self.0
    }
}
fn reads(answer: u32) -> crate::Receipt<u8, u32, u8> {
    vec![Observation {
        domain: 0,
        query: 0,
        answer,
    }]
    .into()
}

#[test]
fn six_publication_owners_keep_independent_claims_through_abort_and_pressure() {
    let store = Store::shared_current_rosters();
    store.enable_incidence();
    let shared_key: Arc<[u8]> = Arc::from(b"shared".as_slice());
    let private_key: Arc<[u8]> = Arc::from(b"private".as_slice());
    let owners: Vec<Arc<ArtifactPublication<Lease>>> = (0..6)
        .map(|_| Arc::new(ArtifactPublication::default()))
        .collect();
    let mut attempts = Vec::new();
    let mut shared = None;
    for (destination, owner) in owners.iter().enumerate() {
        let attempt = owner.begin(store.lease());
        let value = attempt
            .with_pending(|lease| {
                let value = lease
                    .insert_with_qualified_receipt(
                        shared_key.clone(),
                        reads(0),
                        Arc::from([(0, 9)]),
                        8,
                        || vec![7; 8],
                    )
                    .unwrap();
                assert!(lease
                    .insert_with_qualified_receipt(
                        private_key.clone(),
                        reads(destination as u32 + 10),
                        Arc::from([(0, 9)]),
                        4,
                        || vec![destination as u8; 4]
                    )
                    .is_some());
                value
            })
            .unwrap();
        if let Some(previous) = &shared {
            assert!(Arc::ptr_eq(previous, &value));
        }
        shared = Some(value);
        assert!(attempt.publish_successful());
        attempts.push(attempt);
    }
    assert_eq!(store.state.lock().unwrap().claims.len(), 7);
    let pending = owners[0].begin(store.lease());
    let unpublished = pending
        .with_pending(|lease| {
            assert!(lease
                .visit_explained(&private_key, &Host(99), &mut |_| true)
                .0
                .is_none());
            lease
                .insert_with_qualified_receipt(
                    private_key.clone(),
                    reads(99),
                    Arc::from([(0, 9)]),
                    4,
                    || vec![99; 4],
                )
                .unwrap()
        })
        .unwrap();
    let unpublished_weak = Arc::downgrade(&unpublished);
    pending.abort();
    assert!(!pending.publish_successful());
    drop(unpublished);
    assert!(unpublished_weak.upgrade().is_none());
    assert_eq!(store.state.lock().unwrap().claims.len(), 7);

    let pruned = store.prune_for_pressure(usize::MAX, |key, _, _, value| {
        (key == &shared_key).then_some(value.capacity())
    });
    assert_eq!(pruned.retained_entries, 1);
    assert_eq!(pruned.evicted_entries, 6);
    for owner in &owners {
        assert_eq!(owner.with_published(|_| ()), Some(()));
    }
    let probe = store.lease();
    let admitted = probe
        .visit_explained(&shared_key, &Host(0), &mut |_| true)
        .0
        .unwrap();
    assert!(Arc::ptr_eq(&admitted, shared.as_ref().unwrap()));
    // An identical version from a different destination never licenses an answer.
    assert!(probe
        .visit_explained(&shared_key, &Host(1), &mut |_| true)
        .0
        .is_none());
    drop(probe);
    assert_eq!(
        store
            .state
            .lock()
            .unwrap()
            .claims
            .values()
            .next()
            .unwrap()
            .1,
        6
    );
    drop(pending);
    drop(attempts);
    drop(owners);
    assert_eq!(store.admitted_bytes(), 0);
    assert_eq!(admitted.as_slice(), &[7; 8]);
}

#[test]
fn refresh_published_during_pressure_charge_keeps_escaped_values_and_generation() {
    let store = Store::shared_current_rosters();
    store.enable_incidence();
    let owner: Arc<ArtifactPublication<Lease>> = Arc::new(ArtifactPublication::default());
    let key: Arc<[u8]> = Arc::from(b"same-key".as_slice());
    let ledger = reads(0);
    let versions: Arc<[(u8, u128)]> = Arc::from([(0, 9)]);
    let original = owner.begin(store.lease());
    let old = original
        .with_pending(|lease| {
            lease
                .insert_with_qualified_receipt(
                    key.clone(),
                    ledger.clone(),
                    versions.clone(),
                    8,
                    || vec![1; 8],
                )
                .unwrap()
        })
        .unwrap();
    assert!(original.publish_successful());
    let started = Arc::new(Barrier::new(2));
    let resume = Arc::new(Barrier::new(2));
    let pressure_store = store.clone();
    let pressure_started = started.clone();
    let pressure_resume = resume.clone();
    let job = std::thread::spawn(move || {
        pressure_store.prune_for_pressure(usize::MAX, |_, _, _, value| {
            pressure_started.wait();
            pressure_resume.wait();
            Some(value.capacity())
        })
    });
    started.wait();
    let current = owner.begin(store.lease());
    let rebound = current
        .with_pending(|lease| {
            lease
                .rebind_with_qualified_receipt(&old, key.clone(), ledger, versions, 8, || {
                    vec![2; 8]
                })
                .unwrap()
        })
        .unwrap();
    assert!(!Arc::ptr_eq(&old, &rebound));
    assert!(current.publish_successful());
    let generation = current.generation().clone();
    resume.wait();
    let pruned = job.join().unwrap();
    // The new payload was not charged by the snapshot, so it fails closed.
    assert_eq!(pruned.retained_entries, 0);
    assert_eq!(pruned.evicted_entries, 1);
    assert_eq!(store.admitted_bytes(), 0);
    assert!(owner.is_latest(&generation));
    assert_eq!(owner.with_published(|_| ()), Some(()));
    assert!(current.with_pending(|_| ()).is_none());
    assert_eq!(old.as_slice(), &[1; 8]);
    assert_eq!(rebound.as_slice(), &[2; 8]);
    let probe = store.lease();
    assert!(probe
        .visit_explained(&key, &Host(0), &mut |_| true)
        .0
        .is_none());
    drop((probe, current, original, owner));
    assert!(store.state.lock().unwrap().claims.is_empty());
    assert!(store.state.lock().unwrap().buckets.is_empty());
}
