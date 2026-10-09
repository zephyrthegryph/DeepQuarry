//! Opt-in conservative domain bounds. No changes to process audit or critical points.
use super::{clock, Entry, StageReport};
use serde::Serialize;
use std::{
    collections::{BTreeMap, BTreeSet},
    time::Instant,
};

#[derive(Clone, Copy, Debug)]
pub enum CpuSelector<'a> {
    Inclusive(&'a str),
    Exclusive(&'a str),
}
impl<'a> CpuSelector<'a> {
    fn parts(self) -> (&'a str, bool) {
        match self {
            Self::Inclusive(name) => (name, false),
            Self::Exclusive(name) => (name, true),
        }
    }
}
pub struct CpuDomain<'a> {
    pub name: &'a str,
    pub selectors: &'a [CpuSelector<'a>],
}
#[derive(Clone, Debug, Serialize)]
pub struct DomainCpuBounds {
    pub critical_point_s: Option<f64>,
    pub original_upper_s: Option<f64>,
    pub all_thread_union_upper_s: Option<f64>,
    pub upper_s: Option<f64>,
    pub proof: &'static str,
    /// Additive diagnostic totals; neither existing acceptance nor process audit uses them.
    pub total_point_s: Option<f64>,
    pub original_total_upper_s: Option<f64>,
    pub total_union_upper_s: Option<f64>,
    pub total_upper_s: Option<f64>,
    pub total_proof: &'static str,
    /// Validated observations gathered; partial counts do not imply complete coverage.
    pub selected_threads: usize,
    pub selected_intervals: usize,
    pub gap_complement: super::domain_complement::ComplementReport,
}
#[derive(Clone, Copy)]
pub(super) struct TimedInterval {
    pub cpu: clock::CpuInterval,
    pub begin: Instant,
    pub end: Instant,
}

fn union_upper(mut values: Vec<TimedInterval>) -> Result<f64, &'static str> {
    values.sort_unstable_by_key(|value| (value.begin, value.end));
    let mut merged: Vec<TimedInterval> = Vec::new();
    for value in values {
        if value.end < value.begin {
            return Err("backward_temporal_interval");
        }
        if let Some(last) = merged.last_mut() {
            if value.begin < last.end {
                return Err("overlapping_selector_intervals");
            }
            if value.begin == last.end {
                if last.cpu.raw_end != value.cpu.raw_begin
                    || last.cpu.coarse_end != value.cpu.coarse_begin
                {
                    return Err("shared_temporal_boundary_has_different_clock_samples");
                }
                last.end = value.end;
                last.cpu.raw_end = value.cpu.raw_end;
                last.cpu.coarse_end = value.cpu.coarse_end;
                continue;
            }
        }
        merged.push(value);
    }
    Ok(merged
        .into_iter()
        .map(|value| value.cpu.bounds(cfg!(windows)).upper)
        .sum())
}

fn domain(
    domain: &CpuDomain<'_>,
    entries: &BTreeMap<&'static str, Entry>,
    stages: &[StageReport],
) -> DomainCpuBounds {
    let mut report = DomainCpuBounds {
        critical_point_s: Some(0.0),
        original_upper_s: Some(0.0),
        all_thread_union_upper_s: None,
        upper_s: None,
        proof: "missing_selector_or_cpu_observation",
        total_point_s: Some(0.0),
        original_total_upper_s: Some(0.0),
        total_union_upper_s: None,
        total_upper_s: None,
        total_proof: "missing_selector_or_cpu_observation",
        selected_threads: 0,
        selected_intervals: 0,
        gap_complement: super::domain_complement::ComplementReport::unavailable(
            "missing_selector_or_cpu_observation",
        ),
    };
    let mut selected = BTreeSet::new();
    let mut by_thread: BTreeMap<String, Vec<TimedInterval>> = BTreeMap::new();
    let mut failure = None;
    if domain.selectors.is_empty() {
        failure = Some("empty_domain");
    }
    for selector in domain.selectors {
        let (name, exclusive) = selector.parts();
        let Some(stage) = stages.iter().find(|stage| stage.name == name) else {
            report.critical_point_s = None;
            report.original_upper_s = None;
            report.total_point_s = None;
            report.original_total_upper_s = None;
            break;
        };
        let point = if exclusive {
            stage.max_thread_exclusive_cpu_s
        } else {
            stage.max_thread_cpu_s
        };
        let bound = if exclusive {
            stage.max_thread_exclusive_cpu_bounds_s
        } else {
            stage.max_thread_cpu_bounds_s
        };
        report.critical_point_s = report
            .critical_point_s
            .zip(point)
            .map(|(sum, value)| sum + value);
        report.original_upper_s = report
            .original_upper_s
            .zip(bound)
            .map(|(sum, value)| sum + value.upper);
        let total_point = if exclusive {
            stage.exclusive_cpu_s
        } else {
            stage.cpu_s
        };
        let total_bound = if exclusive {
            stage.exclusive_cpu_bounds_s
        } else {
            stage.cpu_bounds_s
        };
        report.total_point_s = report
            .total_point_s
            .zip(total_point)
            .map(|(sum, value)| sum + value);
        report.original_total_upper_s = report
            .original_total_upper_s
            .zip(total_bound)
            .map(|(sum, value)| sum + value.upper);
        if !selected.insert((name, exclusive)) {
            failure = Some("duplicate_selector");
        }
        let Some(entry) = entries.get(name) else {
            failure = Some("missing_selector");
            continue;
        };
        if entry.active != 0 || !entry.cpu_valid || entry.cpu_missing || entry.interval_missing {
            failure = Some("incomplete_cpu_observation");
            continue;
        }
        let (plain, timed) = if exclusive {
            (&entry.exclusive_intervals, &entry.timed_exclusive_intervals)
        } else {
            (&entry.intervals, &entry.timed_intervals)
        };
        if plain.is_empty()
            || plain.len() != timed.len()
            || plain.iter().any(|(thread, values)| {
                timed.get(thread).is_none_or(|proof| {
                    proof.len() != values.len()
                        || values.iter().zip(proof).any(|(cpu, proof)| {
                            cpu.raw_begin != proof.cpu.raw_begin
                                || cpu.raw_end != proof.cpu.raw_end
                                || cpu.coarse_begin != proof.cpu.coarse_begin
                                || cpu.coarse_end != proof.cpu.coarse_end
                        })
                })
            })
        {
            failure = Some("missing_temporal_proof");
            continue;
        }
        for (thread, values) in timed {
            by_thread
                .entry(thread.clone())
                .or_default()
                .extend(values.iter().copied());
        }
    }
    report.upper_s = report.original_upper_s;
    report.total_upper_s = report.original_total_upper_s;
    report.selected_threads = by_thread.len();
    report.selected_intervals = by_thread.values().map(Vec::len).sum();
    if let Some(reason) = failure {
        report.proof = reason;
        report.total_proof = reason;
        report.gap_complement = super::domain_complement::ComplementReport::unavailable(reason);
        return report;
    }
    if report.original_upper_s.is_none() {
        return report;
    }
    report.gap_complement = super::domain_complement::collect(&by_thread, cfg!(windows));
    let cap = by_thread
        .into_values()
        .map(union_upper)
        .try_fold(0.0, |sum, value| value.map(|value| sum + value));
    match cap {
        Ok(cap) => {
            report.all_thread_union_upper_s = Some(cap);
            report.upper_s = report.original_upper_s.map(|original| original.min(cap));
            report.proof = "complete_temporally_disjoint_all_thread_union";
            if let Some(original) = report.original_total_upper_s {
                report.total_union_upper_s = Some(cap);
                report.total_upper_s = Some(original.min(cap));
                report.total_proof = "complete_temporally_disjoint_all_thread_union";
            } else {
                report.total_proof = "missing_original_total_cpu_bound";
            }
        }
        Err(reason) => {
            report.proof = reason;
            report.total_proof = reason;
        }
    }
    report
}
pub(super) fn collect(
    domains: &[CpuDomain<'_>],
    entries: &BTreeMap<&'static str, Entry>,
    stages: &[StageReport],
) -> BTreeMap<String, DomainCpuBounds> {
    let mut reports = BTreeMap::new();
    for item in domains {
        if reports.contains_key(item.name) {
            reports.insert(
                item.name.into(),
                DomainCpuBounds {
                    critical_point_s: None,
                    original_upper_s: None,
                    all_thread_union_upper_s: None,
                    upper_s: None,
                    proof: "duplicate_domain_name",
                    total_point_s: None,
                    original_total_upper_s: None,
                    total_union_upper_s: None,
                    total_upper_s: None,
                    total_proof: "duplicate_domain_name",
                    selected_threads: 0,
                    selected_intervals: 0,
                    gap_complement: super::domain_complement::ComplementReport::unavailable(
                        "duplicate_domain_name",
                    ),
                },
            );
        } else {
            reports.insert(item.name.into(), domain(item, entries, stages));
        }
    }
    reports
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;
    fn interval(start: Instant, a: u64, b: u64, begin: u64, end: u64) -> TimedInterval {
        TimedInterval {
            begin: start + Duration::from_nanos(a),
            end: start + Duration::from_nanos(b),
            cpu: clock::CpuInterval {
                raw_begin: begin,
                raw_end: end,
                coarse_begin: begin,
                coarse_end: end,
            },
        }
    }
    #[test]
    fn shared_endpoint_cancels_only_one_measurement_boundary() {
        let start = Instant::now();
        let a = interval(start, 0, 10, 0, 100_000_000);
        let b = interval(start, 10, 20, 100_000_000, 200_000_000);
        assert_eq!(
            union_upper(vec![a, b]).unwrap(),
            clock::CpuInterval {
                raw_begin: 0,
                raw_end: 200_000_000,
                coarse_begin: 0,
                coarse_end: 200_000_000
            }
            .bounds(cfg!(windows))
            .upper
        );
        let mut gap = b;
        gap.begin += Duration::from_nanos(1);
        assert_eq!(
            union_upper(vec![a, gap]).unwrap(),
            a.cpu.bounds(cfg!(windows)).upper + gap.cpu.bounds(cfg!(windows)).upper
        );
        let mut different = b;
        different.cpu.raw_begin += 1;
        assert_eq!(
            union_upper(vec![a, different]).unwrap_err(),
            "shared_temporal_boundary_has_different_clock_samples"
        );
    }
    #[test]
    fn overlap_fails_even_when_quantized_readings_are_equal() {
        let start = Instant::now();
        assert_eq!(
            union_upper(vec![
                interval(start, 0, 20, 0, 0),
                interval(start, 5, 10, 0, 0)
            ])
            .unwrap_err(),
            "overlapping_selector_intervals"
        );
    }
    #[test]
    fn all_threads_are_summed_and_missing_proof_preserves_original_upper() {
        let start = Instant::now();
        let mut entries = BTreeMap::new();
        let mut stages = Vec::new();
        for (name, thread, end) in [("a", "worker1", 100_000_000), ("b", "worker2", 200_000_000)] {
            let value = interval(start, 0, 10, 0, end);
            let mut entry = Entry {
                cpu_valid: true,
                ..Entry::default()
            };
            entry.intervals.insert(thread.into(), vec![value.cpu]);
            entry.timed_intervals.insert(thread.into(), vec![value]);
            entries.insert(name, entry);
            stages.push(StageReport {
                name: name.into(),
                cpu_s: Some(end as f64 / 1e9),
                cpu_bounds_s: Some(value.cpu.bounds(cfg!(windows))),
                max_thread_cpu_s: Some(end as f64 / 1e9),
                max_thread_cpu_bounds_s: Some(value.cpu.bounds(cfg!(windows))),
                ..StageReport::default()
            });
        }
        let selectors = [CpuSelector::Inclusive("a"), CpuSelector::Inclusive("b")];
        let definition = CpuDomain {
            name: "test",
            selectors: &selectors,
        };
        let complete = domain(&definition, &entries, &stages);
        assert_eq!(complete.critical_point_s, Some(0.1 + 0.2));
        assert_eq!(complete.total_point_s, Some(0.1 + 0.2));
        assert_eq!(
            complete.total_union_upper_s,
            complete.original_total_upper_s
        );
        assert_eq!(complete.total_upper_s, complete.original_total_upper_s);
        assert_eq!(complete.selected_threads, 2);
        assert_eq!(complete.selected_intervals, 2);
        assert_eq!(complete.all_thread_union_upper_s, complete.original_upper_s);
        entries.get_mut("a").unwrap().timed_intervals.clear();
        let fallback = domain(&definition, &entries, &stages);
        assert_eq!(fallback.proof, "missing_temporal_proof");
        assert_eq!(fallback.upper_s, fallback.original_upper_s);
        assert_eq!(fallback.total_upper_s, fallback.original_total_upper_s);
        assert_eq!(fallback.total_proof, "missing_temporal_proof");
        assert!(fallback.total_union_upper_s.is_none());
        assert!(fallback.all_thread_union_upper_s.is_none());
        let absent = [CpuSelector::Inclusive("missing")];
        let missing = domain(
            &CpuDomain {
                name: "absent",
                selectors: &absent,
            },
            &entries,
            &stages,
        );
        assert!(missing.upper_s.is_none());
    }
    #[test]
    fn total_domain_reuses_exact_endpoints_and_sums_independent_threads() {
        let start = Instant::now();
        let mut entries = BTreeMap::new();
        let mut stages = Vec::new();
        for (name, a, b, raw_a, raw_b) in [
            ("first", 0, 10, 0, 100_000_000),
            ("second", 10, 20, 100_000_000, 200_000_000),
        ] {
            let value = interval(start, a, b, raw_a, raw_b);
            let mut entry = Entry {
                cpu_valid: true,
                ..Entry::default()
            };
            for thread in ["one", "two"] {
                entry
                    .exclusive_intervals
                    .insert(thread.into(), vec![value.cpu]);
                entry
                    .timed_exclusive_intervals
                    .insert(thread.into(), vec![value]);
            }
            let bound = value.cpu.bounds(cfg!(windows));
            entries.insert(name, entry);
            stages.push(StageReport {
                name: name.into(),
                exclusive_cpu_s: Some(0.2),
                exclusive_cpu_bounds_s: Some(super::super::clock::CpuBounds {
                    lower: bound.lower * 2.0,
                    upper: bound.upper * 2.0,
                }),
                max_thread_exclusive_cpu_s: Some(0.1),
                max_thread_exclusive_cpu_bounds_s: Some(bound),
                ..StageReport::default()
            });
        }
        let selectors = [
            CpuSelector::Exclusive("first"),
            CpuSelector::Exclusive("second"),
        ];
        let definition = CpuDomain {
            name: "total",
            selectors: &selectors,
        };
        let result = domain(&definition, &entries, &stages);
        let expected = 2.0
            * interval(start, 0, 20, 0, 200_000_000)
                .cpu
                .bounds(cfg!(windows))
                .upper;
        assert_eq!(result.total_point_s, Some(0.4));
        assert_eq!(result.total_union_upper_s, Some(expected));
        assert_eq!(result.total_upper_s, Some(expected));
        assert_eq!(result.selected_threads, 2);
        assert_eq!(result.selected_intervals, 4);
        assert_eq!(
            result.total_proof,
            "complete_temporally_disjoint_all_thread_union"
        );
        // Equal CPU readings across a temporal gap are never treated as one endpoint.
        let gap = entries.get_mut("second").unwrap();
        for values in gap.timed_exclusive_intervals.values_mut() {
            values[0].begin += Duration::from_nanos(1);
        }
        let result = domain(&definition, &entries, &stages);
        assert_eq!(result.total_upper_s, result.original_total_upper_s);
        // An overlap invalidates the proof even with identical quantized readings.
        for values in entries
            .get_mut("second")
            .unwrap()
            .timed_exclusive_intervals
            .values_mut()
        {
            values[0].begin = start + Duration::from_nanos(5);
        }
        let result = domain(&definition, &entries, &stages);
        assert_eq!(result.total_proof, "overlapping_selector_intervals");
        assert_eq!(result.total_upper_s, result.original_total_upper_s);
        assert!(result.total_union_upper_s.is_none());
    }
}
