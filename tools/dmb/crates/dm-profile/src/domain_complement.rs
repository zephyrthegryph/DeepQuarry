//! Diagnostic outer-minus-observed-gap inequality; no acceptance metric uses it.
use super::{clock, domain_bounds::TimedInterval};
use serde::Serialize;
use std::collections::BTreeMap;

#[derive(Clone, Debug, Serialize)]
pub struct ComplementReport {
    pub upper_s: Option<f64>,
    pub proof: &'static str,
    pub selected_threads: usize,
    pub selected_intervals: usize,
    pub observed_gaps: usize,
}
impl ComplementReport {
    pub(super) fn unavailable(reason: &'static str) -> Self {
        Self {
            upper_s: None,
            proof: reason,
            selected_threads: 0,
            selected_intervals: 0,
            observed_gaps: 0,
        }
    }
}
fn thread_bound(
    mut values: Vec<TimedInterval>,
    windows: bool,
) -> Result<(u128, usize), &'static str> {
    values.sort_unstable_by_key(|value| (value.begin, value.end));
    let first = values.first().ok_or("empty_thread_roster")?;
    let last = values.last().unwrap();
    let mut lower_gaps = 0u128;
    let mut gaps = 0;
    for value in &values {
        if value.end < value.begin || value.cpu.bounds_ns(windows).is_none() {
            return Err("backward_interval_or_cpu_clock");
        }
    }
    for pair in values.windows(2) {
        let a = pair[0];
        let b = pair[1];
        if b.begin < a.end {
            return Err("overlapping_selector_intervals");
        }
        if b.cpu.raw_begin < a.cpu.raw_end || b.cpu.coarse_begin < a.cpu.coarse_end {
            return Err("backward_cross_interval_cpu_clock");
        }
        if b.begin == a.end {
            if a.cpu.raw_end != b.cpu.raw_begin || a.cpu.coarse_end != b.cpu.coarse_begin {
                return Err("shared_temporal_boundary_has_different_clock_samples");
            }
        } else {
            let gap = clock::CpuInterval {
                raw_begin: a.cpu.raw_end,
                raw_end: b.cpu.raw_begin,
                coarse_begin: a.cpu.coarse_end,
                coarse_end: b.cpu.coarse_begin,
            };
            let (lower, _) = gap.bounds_ns(windows).ok_or("invalid_observed_gap")?;
            lower_gaps = lower_gaps.checked_add(lower).ok_or("gap_bound_overflow")?;
            gaps += 1;
        }
    }
    let outer = clock::CpuInterval {
        raw_begin: first.cpu.raw_begin,
        raw_end: last.cpu.raw_end,
        coarse_begin: first.cpu.coarse_begin,
        coarse_end: last.cpu.coarse_end,
    };
    let (_, upper) = outer
        .bounds_ns(windows)
        .ok_or("invalid_outer_cpu_interval")?;
    Ok((
        upper
            .checked_sub(lower_gaps)
            .ok_or("inconsistent_gap_lower_bounds")?,
        gaps,
    ))
}
fn upward_seconds(ns: u128) -> f64 {
    if ns == 0 {
        return 0.0;
    }
    // Round upward after both integer conversion and division, without relying
    // on an approximate subtraction allowance or cancelling quantized clocks.
    let converted = ns as f64;
    let converted_up = f64::from_bits(converted.to_bits() + 1);
    let seconds = converted_up / 1e9;
    f64::from_bits(seconds.to_bits() + 1)
}
pub(super) fn collect(
    threads: &BTreeMap<String, Vec<TimedInterval>>,
    windows: bool,
) -> ComplementReport {
    if threads.is_empty() {
        return ComplementReport::unavailable("empty_thread_roster");
    }
    let mut report = ComplementReport::unavailable("complete_observed_gap_complement_v1");
    let mut total = 0u128;
    for values in threads.values() {
        match thread_bound(values.clone(), windows) {
            Ok((upper, gaps)) => {
                let Some(sum) = total.checked_add(upper) else {
                    return ComplementReport::unavailable("total_bound_overflow");
                };
                total = sum;
                report.selected_threads += 1;
                report.selected_intervals += values.len();
                report.observed_gaps += gaps;
            }
            Err(reason) => return ComplementReport::unavailable(reason),
        }
    }
    report.upper_s = Some(upward_seconds(total));
    report
}

#[cfg(test)]
#[path = "domain_complement_tests.rs"]
mod tests;
