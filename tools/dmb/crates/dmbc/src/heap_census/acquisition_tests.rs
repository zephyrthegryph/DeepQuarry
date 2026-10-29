use super::*;
#[test]
fn separate_leases_count_metadata_twice_but_shared_prepared_text_once() {
    let a = dm_preprocess::AcquiredSource::from_original_bytes(
        b"/datum/census_lease_unique_739747\n".to_vec(),
        1u64,
    );
    let b = dm_preprocess::AcquiredSource::from_original_bytes(
        b"/datum/census_lease_unique_739747\n".to_vec(),
        2u64,
    );
    assert!(Arc::ptr_eq(a.prepared(), b.prepared()));
    let weak = Arc::downgrade(a.prepared());
    let mut once = HeapCensus::new("once");
    once.source_acquisition(a.lease());
    let once = once.finish();
    let mut twice = HeapCensus::new("twice");
    twice.source_acquisition(a.lease());
    twice.source_acquisition(b.lease());
    let twice = twice.finish();
    let text = |report: &HeapCensusReport| {
        report
            .owners
            .iter()
            .filter(|row| row.owner == "source_acquisition.text")
            .map(|row| row.unique_known_capacity_bytes)
            .sum::<u64>()
    };
    let metadata = |report: &HeapCensusReport| {
        report
            .owners
            .iter()
            .filter(|row| row.owner == "source_acquisition.metadata")
            .map(|row| row.unique_known_capacity_bytes)
            .sum::<u64>()
    };
    assert_eq!(text(&once), text(&twice));
    assert!(metadata(&twice) > metadata(&once));
    drop(a);
    drop(b);
    assert!(
        weak.upgrade().is_none(),
        "census cannot retain the lexical owner"
    );
}
