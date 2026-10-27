use super::*;

struct Host(u32);
impl crate::ObservationHost<u8, u32, u8> for Host {
    fn answer(&self, _: &u8) -> u32 {
        self.0
    }
}
fn reads(answer: u32) -> Vec<crate::Observation<u8, u32, u8>> {
    vec![crate::Observation {
        query: 0,
        answer,
        domain: 0,
    }]
}
fn counts(report: ArtifactStorageAccounting) -> (usize, usize, usize, usize, usize, usize) {
    (
        report.buckets,
        report.variants,
        report.leases,
        report.roster_keys,
        report.claimed_variants,
        report.claims,
    )
}

#[test]
fn storage_accounting_tracks_shared_claims_and_exposes_private_owner_gaps() {
    let store = ObservedArtifactStore::<u32, u8, u32, u8>::shared_current_rosters();
    let empty = store.storage_accounting();
    assert_eq!(counts(empty), (0, 0, 0, 0, 0, 0));
    assert_eq!(empty.coverage, ArtifactStorageCoverage::Partial);
    assert!(empty
        .exclusions
        .contains(&ArtifactStorageExclusion::LeaseRosterNodes));
    assert!(empty
        .exclusions
        .contains(&ArtifactStorageExclusion::VariantClaimIndexNodes));
    let a = store.lease();
    let b = store.lease();
    let c = store.lease();
    let key: Arc<[u8]> = Arc::from(b"owner".as_slice());
    let first = a
        .insert_with_owned(Arc::clone(&key), reads(1), 1, || 11)
        .unwrap();
    let sibling = b.visit_explained(&key, &Host(1), &mut |_| true).0.unwrap();
    assert!(Arc::ptr_eq(&first, &sibling));
    // A hit on a claimed variant counts at once; its roster key is deferred
    // until the lease next reads or mutates its roster (here: accounting).
    let _ = b.storage_accounting();
    assert_eq!(counts(store.storage_accounting()), (1, 1, 3, 2, 1, 2));
    assert_eq!(a.storage_accounting(), store.storage_accounting());

    // Consumer rejection does not create a private roster/index claim.
    assert!(c
        .visit_explained(&key, &Host(1), &mut |_| false)
        .0
        .is_none());
    assert_eq!(counts(store.storage_accounting()), (1, 1, 3, 2, 1, 2));
    b.insert_with_owned(Arc::clone(&key), reads(2), 1, || 22)
        .unwrap();
    assert_eq!(counts(store.storage_accounting()), (1, 2, 3, 2, 2, 2));
    a.retain_current_keys(std::iter::empty());
    assert_eq!(counts(store.storage_accounting()), (1, 1, 3, 1, 1, 1));
    assert_eq!(*first, 11, "escaped payloads outlive indexed claims");
    drop(b);
    assert_eq!(counts(store.storage_accounting()), (0, 0, 2, 0, 0, 0));
    drop(a);
    drop(c);
    let empty = store.storage_accounting();
    assert_eq!(counts(empty), (0, 0, 0, 0, 0, 0));
    assert_eq!(empty.coverage, ArtifactStorageCoverage::Partial);
    assert_eq!(*sibling, 11, "store counts never cover escaped owners");
}

