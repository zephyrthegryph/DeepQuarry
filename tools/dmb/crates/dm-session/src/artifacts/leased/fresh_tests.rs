use super::*;
use crate::ArtifactPublication;
struct Host;
impl ObservationHost<u8, u8, u8> for Host {
    fn answer(&self, _: &u8) -> u8 {
        1
    }
}
type Store = ObservedArtifactStore<u32, u8, u8, u8>;
type Lease = ObservedArtifactLease<u32, u8, u8, u8>;
fn reads() -> crate::Receipt<u8, u8, u8> {
    vec![Observation {
        domain: 0,
        query: 0,
        answer: 1,
    }]
    .into()
}
#[test]
fn failed_fresh_same_ledger_input_keeps_previous_publication_and_escaped_arc() {
    let store = Store::shared_current_rosters();
    let owner = Arc::new(ArtifactPublication::<Lease>::default());
    let first = owner.begin(store.lease());
    let old = first
        .with_pending(|lease| {
            lease.insert_with_qualified_receipt(
                Arc::from(b"key".as_slice()),
                reads(),
                Arc::from([(0, 9)]),
                1,
                || 11,
            )
        })
        .flatten()
        .unwrap();
    assert!(first.publish_successful());
    let failed = owner.begin(store.lease());
    let fresh = failed
        .with_pending(|lease| {
            lease.insert_fresh_with_qualified_receipt(
                Arc::from(b"key".as_slice()),
                reads(),
                Arc::from([(0, 9)]),
                1,
                || 22,
            )
        })
        .flatten()
        .unwrap();
    assert_eq!(*fresh, 22);
    assert!(!Arc::ptr_eq(&old, &fresh));
    let pressure =
        store.prune_for_pressure(usize::MAX, |_, _, _, _| Some(std::mem::size_of::<u32>()));
    assert_eq!(pressure.retained_entries, 2);
    assert_eq!(pressure.payload_bytes, 2 * std::mem::size_of::<u32>());
    let weak = Arc::downgrade(&fresh);
    drop(fresh);
    drop(failed);
    assert!(weak.upgrade().is_none());
    let current = owner.begin(store.lease());
    let hit = current
        .with_pending(|lease| lease.visit_explained(b"key", &Host, &mut |_| true).0)
        .flatten()
        .unwrap();
    assert!(Arc::ptr_eq(&old, &hit));
    assert_eq!(*old, 11);
}
#[test]
fn successful_fresh_publication_selects_new_input_without_mutating_old_reader() {
    let store = Store::shared_current_rosters();
    let owner = Arc::new(ArtifactPublication::<Lease>::default());
    let first = owner.begin(store.lease());
    let old = first
        .with_pending(|lease| {
            lease.insert_with_qualified_receipt(
                Arc::from(b"key".as_slice()),
                reads(),
                Arc::from([(0, 9)]),
                1,
                || 11,
            )
        })
        .flatten()
        .unwrap();
    assert!(first.publish_successful());
    let next = owner.begin(store.lease());
    let fresh = next
        .with_pending(|lease| {
            lease.insert_fresh_with_qualified_receipt(
                Arc::from(b"key".as_slice()),
                reads(),
                Arc::from([(0, 9)]),
                1,
                || 22,
            )
        })
        .flatten()
        .unwrap();
    assert!(next.publish_successful());
    assert_eq!(*old, 11);
    assert_eq!(*fresh, 22);
    let current = owner.begin(store.lease());
    let hit = current
        .with_pending(|lease| lease.visit_explained(b"key", &Host, &mut |_| true).0)
        .flatten()
        .unwrap();
    assert!(Arc::ptr_eq(&fresh, &hit));
    assert_eq!(store.admitted_bytes(), 1);
}
