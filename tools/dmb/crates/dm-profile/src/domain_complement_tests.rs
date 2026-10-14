use super::*;
use std::time::{Duration, Instant};
fn value(
    start: Instant,
    begin: u64,
    end: u64,
    raw_begin: u64,
    raw_end: u64,
    coarse_begin: u64,
    coarse_end: u64,
) -> TimedInterval {
    TimedInterval {
        begin: start + Duration::from_nanos(begin),
        end: start + Duration::from_nanos(end),
        cpu: clock::CpuInterval {
            raw_begin,
            raw_end,
            coarse_begin,
            coarse_end,
        },
    }
}
#[test]
fn zero_lower_gaps_remain_in_outer_bound_and_tighten_fragmented_uncertainty() {
    let start = Instant::now();
    // True CPU: three selected 1ms intervals, two unselected 2ms gaps.
    // All observed coarse samples are 0; the nonzero gaps are NOT erased.
    let values = vec![
        value(start, 0, 1, 0, 1_000_000, 0, 0),
        value(start, 2, 3, 3_000_000, 4_000_000, 0, 0),
        value(start, 4, 5, 6_000_000, 7_000_000, 0, 0),
    ];
    let (upper, gaps) = thread_bound(values.clone(), true).unwrap();
    assert_eq!(upper, 31_250_000);
    assert_eq!(gaps, 2);
    assert!(upper >= 3_000_000); // Independently specified true selected CPU.
    assert!(upper < 3 * 31_250_000); // Old independent interval upper sum.
    assert_eq!(thread_bound(values, false).unwrap().0, 3_000_000);
}
#[test]
fn long_gaps_subtract_only_their_proven_lower_and_linux_is_exact() {
    let start = Instant::now();
    let values = vec![
        value(start, 0, 1, 0, 10_000_000, 0, 0),
        value(
            start,
            2,
            3,
            110_000_000,
            120_000_000,
            109_375_000,
            109_375_000,
        ),
    ];
    // Outer upper140625000 - gap lower78125000 =62500000.
    let upper = thread_bound(values.clone(), true).unwrap().0;
    assert_eq!(upper, 62_500_000);
    assert!(upper >= 20_000_000); // True selected duration10ms+10ms.
    assert_eq!(thread_bound(values, false).unwrap().0, 20_000_000);
}
#[test]
fn multiple_threads_sum_exact_integer_bounds_then_round_outward() {
    let start = Instant::now();
    let values = vec![
        value(start, 0, 1, 0, 1_000_000, 0, 0),
        value(start, 2, 3, 3_000_000, 4_000_000, 0, 0),
    ];
    let threads = BTreeMap::from([("first".into(), values.clone()), ("second".into(), values)]);
    let report = collect(&threads, false);
    assert_eq!(report.proof, "complete_observed_gap_complement_v1");
    assert_eq!(report.selected_threads, 2);
    assert_eq!(report.selected_intervals, 4);
    assert_eq!(report.observed_gaps, 2);
    assert!(report.upper_s.unwrap() >= 0.004);
    assert!(report.upper_s.unwrap() < 0.004000000001);
}
#[test]
fn monotonicity_overlap_missing_roster_and_unequal_shared_samples_refuse_proof() {
    let start = Instant::now();
    let first = value(start, 0, 10, 100, 200, 100, 200);
    for second in [
        value(start, 5, 20, 200, 300, 200, 300),
        value(start, 11, 20, 199, 300, 200, 300),
        value(start, 11, 20, 200, 300, 199, 300),
        value(start, 10, 20, 201, 300, 200, 300),
        value(start, 11, 9, 200, 300, 200, 300),
    ] {
        assert!(thread_bound(vec![first, second], true).is_err());
    }
    assert!(collect(&BTreeMap::new(), true).upper_s.is_none());
    assert!(
        collect(&BTreeMap::from([("empty".into(), Vec::new())]), true)
            .upper_s
            .is_none()
    );
}
#[test]
fn contiguous_samples_and_near_u64_max_are_checked_without_overflow() {
    let start = Instant::now();
    let values = vec![
        value(
            start,
            0,
            1,
            u64::MAX - 200,
            u64::MAX - 100,
            u64::MAX - 200,
            u64::MAX - 100,
        ),
        value(
            start,
            1,
            2,
            u64::MAX - 100,
            u64::MAX,
            u64::MAX - 100,
            u64::MAX,
        ),
    ];
    assert_eq!(thread_bound(values.clone(), false).unwrap(), (200, 0));
    assert_eq!(thread_bound(values, true).unwrap(), (31_250_200, 0));
    assert!(upward_seconds(u128::MAX).is_finite());
    assert_eq!(upward_seconds(0), 0.0);
}
