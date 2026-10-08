//! Lifetime CPU observations for profiler-owned workers, without recursive tracing.
use crate::{clock, State};
use std::sync::Arc;
use std::time::Instant;

pub(crate) struct InternalThreadObserver {
    state: Arc<State>,
    name: &'static str,
    thread: String,
    begin: Option<u64>,
    wall: Instant,
    thread_id: std::thread::ThreadId,
}

impl InternalThreadObserver {
    pub(crate) fn new(state: Arc<State>, name: &'static str) -> Self {
        // This guard belongs inside the worker, never on its spawning thread.
        let begin = clock::thread_coarse_ns();
        Self {
            state,
            name,
            thread: format!("{:?}", std::thread::current().id()),
            begin,
            wall: Instant::now(),
            thread_id: std::thread::current().id(),
        }
    }
}

impl Drop for InternalThreadObserver {
    fn drop(&mut self) {
        // A writer is Send before its first worker write. If it is moved after
        // observation starts, never subtract clocks from different threads.
        let end = if self.thread_id == std::thread::current().id() {
            clock::thread_coarse_ns()
        } else {
            None
        };
        let wall = self.wall.elapsed();
        let mut entries = self.state.entries.lock().unwrap_or_else(|e| e.into_inner());
        record(
            entries.entry(self.name).or_default(),
            self.name,
            &self.thread,
            self.begin,
            end,
            wall.as_secs_f64(),
        );
        drop(entries);
        if let Some(interval) = clock::CpuInterval::from_samples(self.begin, end, self.begin, end) {
            self.state
                .folded
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .entry((self.thread.clone(), self.name.into()))
                .or_default()
                .push(interval);
        }
        *self
            .state
            .wall_folded
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .entry(self.name.into())
            .or_default() += wall.as_nanos().min(u64::MAX as u128) as u64;
    }
}

fn record(
    entry: &mut crate::Entry,
    name: &str,
    thread: &str,
    begin: Option<u64>,
    end: Option<u64>,
    wall_s: f64,
) {
    entry.cpu_stage = true;
    entry.report.name = name.into();
    entry.report.calls += 1;
    entry.report.wall_s += wall_s;
    let delta = crate::cpu_interval(begin, end);
    crate::record_cpu_interval(entry, thread, delta, true);
    crate::record_coarse_interval(entry, thread, delta, true);
    if let Some(delta) = delta {
        entry.exclusive += delta;
        entry.coarse_exclusive += delta;
        *entry.exclusive_threads.entry(thread.into()).or_default() += delta;
    }
    if let Some(interval) = clock::CpuInterval::from_samples(begin, end, begin, end) {
        entry
            .intervals
            .entry(thread.into())
            .or_default()
            .push(interval);
        entry
            .exclusive_intervals
            .entry(thread.into())
            .or_default()
            .push(interval);
    } else {
        entry.interval_missing = true;
        entry.coarse_missing = true;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn worker_lifetime_records_only_observed_cpu_not_sleeping_wall() {
        let mut entry = crate::Entry::default();
        record(
            &mut entry,
            "profiler.memory_sampler",
            "worker",
            Some(10),
            Some(15),
            20.0,
        );
        assert_eq!(entry.exclusive, 5);
        assert_eq!(entry.threads["worker"], 5);
        assert_eq!(entry.report.wall_s, 20.0);
        assert_eq!(entry.intervals["worker"][0].raw_begin, 10);
        assert_eq!(entry.intervals["worker"][0].raw_end, 15);
        assert_eq!(entry.report.allocations, 0);
    }

    #[test]
    fn unavailable_worker_clock_is_not_zero_cpu() {
        let mut entry = crate::Entry::default();
        record(
            &mut entry,
            "profiler.memory_sampler",
            "worker",
            None,
            Some(15),
            20.0,
        );
        assert!(entry.cpu_missing);
        assert!(entry.coarse_missing);
        assert!(entry.interval_missing);
        assert!(entry.threads.is_empty());
    }
}
