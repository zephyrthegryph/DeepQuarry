//! Coverage-only observations for persistent compiler workers.
use super::*;

/// Starts on the actual worker before its scheduler loop, and must be dropped
/// on that worker after the loop. It deliberately cannot move across threads.
/// Unlike a stage, this does not produce exclusive CPU or folded-stack entries:
/// stage CPU lies inside the lifetime, and must only be counted once.
pub struct WorkerLifetime {
    state: Option<Arc<State>>,
    name: &'static str,
    thread: String,
    begin: Option<u64>,
    wall: Instant,
    thread_bound: PhantomData<Rc<()>>,
}

pub fn worker_lifetime(name: &'static str) -> WorkerLifetime {
    let state = request::active_state();
    if let Some(state) = &state {
        state
            .workers
            .fetch_add(1, std::sync::atomic::Ordering::AcqRel);
    }
    WorkerLifetime {
        begin: clock::thread_coarse_ns(),
        state,
        name,
        thread: format!("{:?}", std::thread::current().id()),
        wall: Instant::now(),
        thread_bound: PhantomData,
    }
}

impl Drop for WorkerLifetime {
    fn drop(&mut self) {
        let Some(state) = &self.state else { return };
        if state.finished.load(std::sync::atomic::Ordering::Acquire) {
            state
                .workers
                .fetch_sub(1, std::sync::atomic::Ordering::AcqRel);
            return;
        }
        let end = clock::thread_coarse_ns();
        let mut entries = state.entries.lock().unwrap_or_else(|e| e.into_inner());
        record(
            entries.entry(self.name).or_default(),
            self.name,
            &self.thread,
            self.begin,
            end,
            self.wall.elapsed().as_secs_f64(),
        );
        drop(entries);
        state
            .workers
            .fetch_sub(1, std::sync::atomic::Ordering::AcqRel);
    }
}

fn record(
    entry: &mut Entry,
    name: &str,
    thread: &str,
    begin: Option<u64>,
    end: Option<u64>,
    wall: f64,
) {
    entry.cpu_stage = true;
    entry.report.name = name.into();
    entry.report.calls += 1;
    entry.report.wall_s += wall;
    let delta = cpu_interval(begin, end);
    record_cpu_interval(entry, thread, delta, true);
    record_coarse_interval(entry, thread, delta, true);
    if let Some(interval) = clock::CpuInterval::from_samples(begin, end, begin, end) {
        entry
            .intervals
            .entry(thread.into())
            .or_default()
            .push(interval);
    } else {
        entry.interval_missing = true;
        entry.coarse_missing = true;
    }
}

// Raw observed CPU uses the same union as its uncertainty envelope, instead of
// summing exclusive stages that omit scheduling overhead or overlap lifetimes.
pub(super) fn union_interval_cpu(mut intervals: Vec<clock::CpuInterval>) -> u64 {
    intervals.sort_unstable_by_key(|i| (i.raw_begin, i.raw_end));
    let mut end = None;
    let mut total = 0;
    for interval in intervals {
        let begin = end.map_or(interval.raw_begin, |previous| {
            interval.raw_begin.max(previous)
        });
        total += interval.raw_end.saturating_sub(begin);
        end = Some(end.map_or(interval.raw_end, |previous| previous.max(interval.raw_end)));
    }
    total
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn lifetime_coverage_never_creates_duplicate_exclusive_stage_cpu() {
        let mut entry = Entry::default();
        record(
            &mut entry,
            "compiler.worker_lifetime",
            "worker",
            Some(10),
            Some(30),
            2.0,
        );
        assert_eq!(entry.threads["worker"], 20);
        assert_eq!(entry.intervals["worker"].len(), 1);
        assert_eq!(entry.exclusive, 0);
        assert!(entry.exclusive_intervals.is_empty());
    }
    #[test]
    fn missing_worker_endpoint_is_unknown() {
        let mut entry = Entry::default();
        record(
            &mut entry,
            "compiler.worker_lifetime",
            "worker",
            None,
            Some(30),
            2.0,
        );
        assert!(entry.cpu_missing && entry.interval_missing);
    }
    #[test]
    fn nested_stages_are_not_counted_again_and_gaps_stay_unobserved() {
        let interval = |a, b| clock::CpuInterval {
            raw_begin: a,
            raw_end: b,
            coarse_begin: a,
            coarse_end: b,
        };
        assert_eq!(
            union_interval_cpu(vec![interval(0, 100), interval(10, 20), interval(80, 110)]),
            110
        );
        assert_eq!(
            union_interval_cpu(vec![interval(0, 100), interval(200, 300)]),
            200
        );
    }
}
