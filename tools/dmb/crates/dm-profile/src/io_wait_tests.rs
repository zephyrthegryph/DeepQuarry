use super::*;
fn observation(begin: u128, end: u128, cpu_begin: u64, cpu_end: u64) -> Observation {
    Observation {
        begin,
        end,
        cpu: clock::CpuInterval::from_samples(
            Some(cpu_begin),
            Some(cpu_end),
            Some(cpu_begin),
            Some(cpu_end),
        ),
    }
}
#[test]
fn nested_calls_union_once_and_subtract_only_a_proven_lower() {
    let ledger = Ledger::default();
    ledger.record(
        "a".into(),
        observation(0, 10_000_000_000, 0, 3_000_000_000),
        false,
    );
    ledger.record(
        "a".into(),
        observation(2_000_000_000, 8_000_000_000, 1_000_000_000, 2_000_000_000),
        false,
    );
    let report = ledger.report();
    let upper = report.non_cpu_wait_upper_s.unwrap();
    assert!(upper >= 7.);
    assert!(upper < 7.04);
    assert!(report.call_wall_sum_upper_s.unwrap() >= 16.);
    assert_eq!(report.calls, 2);
    assert_eq!(report.coverage, "partial_annotated_calls_only");
}
#[test]
fn disjoint_threads_sum_wait_bounds_and_include_failed_calls() {
    let ledger = Ledger::default();
    ledger.record(
        "a".into(),
        observation(0, 2_000_000_000, 0, 1_000_000_000),
        true,
    );
    ledger.record(
        "b".into(),
        observation(0, 3_000_000_000, 0, 1_000_000_000),
        false,
    );
    let report = ledger.report();
    assert_eq!(report.failed_calls, 1);
    let upper = report.non_cpu_wait_upper_s.unwrap();
    assert!(upper >= 3.);
    assert!(upper < 3.07);
}
#[test]
fn missing_and_backward_cpu_fall_back_to_wall_component() {
    let ledger = Ledger::default();
    ledger.record(
        "a".into(),
        Observation {
            begin: 0,
            end: 1_000_000_000,
            cpu: None,
        },
        false,
    );
    ledger.record("a".into(), observation(0, 1_000_000_000, 9, 1), false);
    let report = ledger.report();
    assert_eq!(report.fallback_wall_only_components, 1);
    assert!(report.non_cpu_wait_upper_s.unwrap() >= 1.);
    assert!(report.non_cpu_wait_upper_s.unwrap() < 1.000001);
}
#[test]
fn capped_ledger_preserves_aggregate_conservative_wall_upper() {
    let ledger = Ledger::default();
    for index in 0..MAX_INTERVALS + 3 {
        ledger.record(
            "a".into(),
            Observation {
                begin: index as u128,
                end: index as u128 + 1,
                cpu: None,
            },
            false,
        );
    }
    let report = ledger.report();
    assert!(report.capped);
    assert_eq!(report.retained_intervals, MAX_INTERVALS);
    assert_eq!(report.non_cpu_wait_upper_s, report.call_wall_sum_upper_s);
    assert!(report.non_cpu_wait_upper_s.unwrap() >= (MAX_INTERVALS + 3) as f64 / 1e9);
}
#[test]
fn impossible_wall_or_cpu_envelope_never_produces_a_small_bound() {
    let ledger = Ledger::default();
    ledger.record("a".into(), observation(0, 1, 0, u64::MAX), false);
    assert!(ledger.report().non_cpu_wait_upper_s.unwrap() >= 1e-9);
    ledger.record(
        "a".into(),
        Observation {
            begin: 2,
            end: 1,
            cpu: None,
        },
        false,
    );
    assert!(ledger.report().non_cpu_wait_upper_s.is_none());
}
