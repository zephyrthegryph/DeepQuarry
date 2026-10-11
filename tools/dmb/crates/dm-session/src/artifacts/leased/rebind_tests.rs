use super::*;
#[test]
fn immutable_rebind_preserves_failed_publication_and_replaces_successful_claim() {
    let store = ObservedArtifactStore::<u32, u8, u32, u8>::shared_current_rosters();
    store.enable_incidence();
    let publication = Arc::new(crate::ArtifactPublication::default());
    let key: Arc<[u8]> = Arc::from(b"owner".as_slice());
    let ledger: crate::Receipt<_, _, _> = reads(1).into();
    let versions: Arc<[(u8, u128)]> = Arc::from([(0, 9)]);
    let initial = publication.begin(store.lease());
    let old = initial
        .with_pending(|lease| {
            lease.insert_with_qualified_receipt(
                Arc::clone(&key),
                ledger.clone(),
                Arc::clone(&versions),
                7,
                || 11,
            )
        })
        .flatten()
        .unwrap();
    assert!(initial.publish_successful());
    drop(initial);
    let failed = publication.begin(store.lease());
    let temporary = failed
        .with_pending(|lease| {
            lease.rebind_with_qualified_receipt(
                &old,
                Arc::clone(&key),
                ledger.clone(),
                Arc::clone(&versions),
                7,
                || 22,
            )
        })
        .flatten()
        .unwrap();
    assert!(!Arc::ptr_eq(&old, &temporary));
    assert_eq!(store.admitted_bytes(), 14);
    failed.abort();
    assert_eq!(store.admitted_bytes(), 7);
    let still_old = publication
        .with_published(|lease| {
            lease
                .visit_explained(&key, &Host(1), &mut |_| true)
                .0
                .unwrap()
        })
        .unwrap();
    assert!(Arc::ptr_eq(&old, &still_old));
    let success = publication.begin(store.lease());
    let new = success
        .with_pending(|lease| {
            lease.rebind_with_qualified_receipt(
                &old,
                Arc::clone(&key),
                ledger.clone(),
                Arc::clone(&versions),
                7,
                || 33,
            )
        })
        .flatten()
        .unwrap();
    assert!(success.publish_successful());
    assert_eq!(store.admitted_bytes(), 7);
    let current = publication
        .with_published(|lease| {
            lease
                .visit_explained(&key, &Host(1), &mut |_| true)
                .0
                .unwrap()
        })
        .unwrap();
    assert!(Arc::ptr_eq(&new, &current));
    assert_eq!(*old, 11, "escaped old immutable readers survive");
    let next = publication.begin(store.lease());
    assert!(
        next.with_pending(|lease| lease.rebind_with_qualified_receipt(
            &old,
            key,
            ledger,
            versions,
            7,
            || 44
        ))
        .flatten()
        .is_none(),
        "detached previous publication is not admission authority"
    );
}
#[test]
fn immutable_rebind_declines_changed_ledger_key_version_or_foreign_value() {
    let store = ObservedArtifactStore::<u32, u8, u32, u8>::shared_current_rosters();
    let first = store.lease();
    let key: Arc<[u8]> = Arc::from(b"owner".as_slice());
    let ledger: crate::Receipt<_, _, _> = reads(1).into();
    let versions: Arc<[(u8, u128)]> = Arc::from([(0, 9)]);
    let old = first
        .insert_with_qualified_receipt(
            Arc::clone(&key),
            ledger.clone(),
            Arc::clone(&versions),
            7,
            || 11,
        )
        .unwrap();
    let pending = store.lease();
    for (prior, k, r, v) in [
        (
            Arc::new(11),
            Arc::clone(&key),
            ledger.clone(),
            Arc::clone(&versions),
        ),
        (
            Arc::clone(&old),
            Arc::from(b"other".as_slice()),
            ledger.clone(),
            Arc::clone(&versions),
        ),
        (
            Arc::clone(&old),
            Arc::clone(&key),
            reads(2).into(),
            Arc::clone(&versions),
        ),
        (
            Arc::clone(&old),
            Arc::clone(&key),
            ledger.clone(),
            Arc::from([(0, 10)]),
        ),
    ] {
        assert!(pending
            .rebind_with_qualified_receipt(&prior, k, r, v, 7, || panic!(
                "invalid proof must not issue replacement"
            ))
            .is_none());
    }
    assert_eq!(store.admitted_bytes(), 7);
}
