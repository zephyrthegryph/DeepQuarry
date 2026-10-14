//! Partial annotated synchronous-call waiting bounds, never exact storage blocking.
use super::{clock, request, STACK};
use serde::Serialize;
use std::{collections::BTreeMap, sync::Mutex, time::Instant};
const MAX_INTERVALS: usize = 16_384;
#[derive(Clone, Copy)]
struct Observation {
    begin: u128,
    end: u128,
    cpu: Option<clock::CpuInterval>,
}
pub(super) struct Ledger {
    epoch: Instant,
    data: Mutex<Data>,
}
#[derive(Default)]
struct Data {
    calls: u64,
    failures: u64,
    wall_sum: u128,
    overflow: bool,
    capped: bool,
    intervals: BTreeMap<String, Vec<Observation>>,
}
impl Default for Ledger {
    fn default() -> Self {
        Self {
            epoch: Instant::now(),
            data: Mutex::new(Data::default()),
        }
    }
}
#[derive(Clone, Debug, Serialize)]
pub struct AnnotatedIoWait {
    pub method: &'static str,
    pub coverage: &'static str,
    pub calls: u64,
    pub failed_calls: u64,
    pub retained_intervals: usize,
    pub interval_limit: usize,
    pub fallback_wall_only_components: usize,
    pub capped: bool,
    pub call_wall_sum_upper_s: Option<f64>,
    pub non_cpu_wait_upper_s: Option<f64>,
}
fn outward(ns: u128) -> f64 {
    if ns == 0 {
        return 0.;
    }
    let ns = ns as f64;
    let rounded = f64::from_bits(ns.to_bits() + 1) / 1e9;
    f64::from_bits(rounded.to_bits() + 1)
}
impl Ledger {
    fn record(&self, thread: String, observation: Observation, failed: bool) {
        let mut data = self.data.lock().unwrap_or_else(|e| e.into_inner());
        data.calls = data.calls.saturating_add(1);
        data.failures = data.failures.saturating_add(u64::from(failed));
        if let Some(wall) = observation.end.checked_sub(observation.begin) {
            if let Some(sum) = data.wall_sum.checked_add(wall) {
                data.wall_sum = sum;
            } else {
                data.overflow = true;
            }
        } else {
            data.overflow = true;
        }
        if data.calls as u128 > MAX_INTERVALS as u128 {
            data.capped = true;
            return;
        }
        data.intervals.entry(thread).or_default().push(observation);
    }
    pub(super) fn report(&self) -> AnnotatedIoWait {
        let data = self.data.lock().unwrap_or_else(|e| e.into_inner());
        let mut sum = 0u128;
        let mut fallback = 0;
        let mut retained = 0;
        for observations in data.intervals.values() {
            retained += observations.len();
            let mut intervals = observations.clone();
            intervals.sort_by_key(|i| (i.begin, i.end));
            let mut index = 0;
            while index < intervals.len() {
                let first = intervals[index];
                let begin = first.begin;
                let mut end = first.end;
                let mut lower = 0;
                let mut valid = true;
                loop {
                    let item = intervals[index];
                    end = end.max(item.end);
                    match item.cpu.and_then(|cpu| cpu.bounds_ns(cfg!(windows))) {
                        Some((cpu_lower, _)) => lower = lower.max(cpu_lower),
                        None => valid = false,
                    };
                    index += 1;
                    if index == intervals.len() || intervals[index].begin > end {
                        break;
                    }
                }
                let wall = end.saturating_sub(begin);
                if !valid || lower > wall {
                    lower = 0;
                    fallback += 1;
                }
                sum = sum.saturating_add(wall - lower);
            }
        }
        let aggregate = (!data.overflow).then(|| outward(data.wall_sum));
        let upper = if data.overflow {
            None
        } else if data.capped {
            aggregate
        } else {
            Some(outward(sum).min(aggregate.unwrap()))
        };
        AnnotatedIoWait {
            method: "annotated_thread_union_minus_proven_cpu_lower_v1",
            coverage: "partial_annotated_calls_only",
            calls: data.calls,
            failed_calls: data.failures,
            retained_intervals: retained,
            interval_limit: MAX_INTERVALS,
            fallback_wall_only_components: fallback,
            capped: data.capped,
            call_wall_sum_upper_s: aggregate,
            non_cpu_wait_upper_s: upper,
        }
    }
}
/// CPU samples lie inside the wall envelope, so subtracting their proven lower
/// bound cannot understate waiting inside the annotated operation.
pub fn io_call<T>(
    operation: impl FnOnce() -> std::io::Result<T>,
    byte_counts: impl FnOnce(&T) -> (u64, u64),
) -> std::io::Result<T> {
    let Some(state) = request::active_state() else {
        return operation();
    };
    let start = Instant::now();
    let begin = start.duration_since(state.io_wait.epoch).as_nanos();
    let (raw_begin, coarse_begin) = super::cpu_boundary(&state);
    let operation_start = Instant::now();
    let result = operation();
    let elapsed = operation_start.elapsed().as_secs_f64();
    let (raw_end, coarse_end) = super::cpu_boundary(&state);
    let finish = Instant::now();
    state.io_wait.record(
        super::thread_label::owned(),
        Observation {
            begin,
            end: finish.duration_since(state.io_wait.epoch).as_nanos(),
            cpu: clock::CpuInterval::from_samples(raw_begin, raw_end, coarse_begin, coarse_end),
        },
        result.is_err(),
    );
    if let Ok(value) = &result {
        let (read, written) = byte_counts(value);
        super::record_io(read, written, None);
    }
    STACK.with(|stack| {
        if let Some(frame) = stack.borrow().last() {
            let mut entries = state.entries.lock().unwrap_or_else(|e| e.into_inner());
            let report = &mut entries.entry(frame.name).or_default().report;
            report.io_call_elapsed_s = Some(report.io_call_elapsed_s.unwrap_or(0.) + elapsed);
            report.io_calls = report.io_calls.saturating_add(1);
            report.io_failed_calls = report
                .io_failed_calls
                .saturating_add(u64::from(result.is_err()));
        }
    });
    result
}
#[cfg(test)]
#[path = "io_wait_tests.rs"]
mod tests;
