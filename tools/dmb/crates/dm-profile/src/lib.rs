//! Span profiler with platform CPU clocks. No sampling agent or elevation.
mod item;
pub use item::{item, ItemGuard};
mod allocator;
mod clock;
mod internal_observer;
mod memory;
mod names;
mod thread_label;
mod trace_output;
mod worker;
mod writer;
pub use allocator::CountingAllocator;
use serde::Serialize;
use std::{
    cell::RefCell,
    collections::BTreeMap,
    fs::File,
    io::{BufReader, Write},
    marker::PhantomData,
    path::{Path, PathBuf},
    rc::Rc,
    sync::{Arc, Mutex, OnceLock},
    time::Instant,
};
pub use tracing;
use tracing_subscriber::prelude::*;
pub use worker::{worker_lifetime, WorkerLifetime};

#[derive(Clone, Debug, Default, Serialize)]
pub struct StageReport {
    pub name: String,
    pub calls: u64,
    /// Item-only spans have wall/allocation evidence and no CPU acceptance data.
    pub cpu_measurement: &'static str,
    pub wall_s: f64,
    /// Sum of outermost same-name intervals per thread, including concurrency.
    pub wall_scope: &'static str,
    pub cpu_s: Option<f64>,
    pub max_thread_cpu_s: Option<f64>,
    pub exclusive_cpu_s: Option<f64>,
    pub max_thread_exclusive_cpu_s: Option<f64>,
    pub cpu_bounds_s: Option<clock::CpuBounds>,
    pub max_thread_cpu_bounds_s: Option<clock::CpuBounds>,
    pub exclusive_cpu_bounds_s: Option<clock::CpuBounds>,
    pub max_thread_exclusive_cpu_bounds_s: Option<clock::CpuBounds>,
    pub coarse_thread_cpu_s: Option<f64>,
    pub coarse_max_thread_cpu_s: Option<f64>,
    pub coarse_exclusive_thread_cpu_s: Option<f64>,
    pub allocations: u64,
    pub allocated_bytes: u64,
    pub allocation_scope: &'static str,
    pub peak_live_bytes: u64,
    pub peak_live_scope: &'static str,
    /// Sampled current process PrivateUsage while this stage was active.
    /// Overlapping stages observe the same process; this is not attributable.
    pub sampled_peak_private_bytes: Option<u64>,
    pub sampled_private_scope: &'static str,
    pub private_memory_samples: u64,
    pub private_memory_failed_samples: u64,
    pub read_bytes: Option<u64>,
    pub write_bytes: Option<u64>,
    pub io_blocked_s: Option<f64>,
    /// Wall time inside annotated synchronous I/O calls, not blocked time.
    pub io_call_elapsed_s: Option<f64>,
    pub io_calls: u64,
    pub io_failed_calls: u64,
    pub io_scope: &'static str,
    pub attributed_read_bytes: u64,
    pub attributed_write_bytes: u64,
}

fn critical_stage<'a>(
    stages: &'a [StageReport],
    selector: &str,
) -> Option<(&'a StageReport, bool)> {
    let (name, exclusive) = selector
        .strip_prefix("exclusive:")
        .map_or((selector, false), |n| (n, true));
    Some((stages.iter().find(|stage| stage.name == name)?, exclusive))
}
#[derive(Clone, Debug, Serialize)]
pub struct Report {
    pub schema: u32,
    pub wall_s: f64,
    pub wall_scope: &'static str,
    pub critical_path_cpu_s: Option<f64>,
    pub critical_path_stages: Vec<String>,
    pub total_cpu_s: Option<f64>,
    pub covered_thread_cpu_s: Option<f64>,
    pub critical_path_cpu_bounds_s: Option<clock::CpuBounds>,
    pub covered_thread_cpu_bounds_s: Option<clock::CpuBounds>,
    pub cpu_crosscheck_ratio_bounds: Option<clock::CpuBounds>,
    pub cpu_bounds_method: &'static str,
    pub covered_cpu_bounds_method: &'static str,
    pub cpu_bounds_quantum_s: f64,
    pub peak_private_bytes: Option<u64>,
    pub peak_private_scope: &'static str,
    pub peak_allocator_live_bytes: u64,
    pub peak_allocator_live_scope: &'static str,
    pub read_bytes: Option<u64>,
    pub write_bytes: Option<u64>,
    pub allocation_counting: bool,
    pub calibration: clock::Calibration,
    pub cpu_crosscheck_ratio: Option<f64>,
    pub cpu_precision_scope: &'static str,
    pub coarse_covered_thread_cpu_s: Option<f64>,
    pub coarse_cpu_crosscheck_ratio: Option<f64>,
    pub thread_calibrations: Vec<clock::ThreadCalibration>,
    pub cpu_conversion_complete: bool,
    pub cpu_folded_omitted_threads: Vec<String>,
    pub stages: Vec<StageReport>,
    pub coverage_notes: Vec<String>,
    pub private_memory_sample_interval_ms: Option<u64>,
    pub trace_output: trace_output::Metadata,
}
#[derive(Default)]
struct Entry {
    report: StageReport,
    threads: BTreeMap<String, u64>,
    intervals: BTreeMap<String, Vec<clock::CpuInterval>>,
    exclusive_intervals: BTreeMap<String, Vec<clock::CpuInterval>>,
    interval_missing: bool,
    exclusive: u64,
    exclusive_threads: BTreeMap<String, u64>,
    cpu_stage: bool,
    cpu_valid: bool,
    cpu_missing: bool,
    coarse_threads: BTreeMap<String, u64>,
    coarse_exclusive: u64,
    coarse_valid: bool,
    coarse_missing: bool,
    active: u64,
}
struct State {
    calibration: clock::Calibration,
    entries: Mutex<BTreeMap<&'static str, Entry>>,
    folded: Mutex<BTreeMap<(String, String), Vec<clock::CpuInterval>>>,
    wall_folded: Mutex<BTreeMap<String, u64>>,
}
static ACTIVE: OnceLock<Arc<State>> = OnceLock::new();
struct Frame {
    name: &'static str,
    last_cpu: Option<u64>,
    last_coarse_cpu: Option<u64>,
    last_wall: Instant,
}
mod context;
pub use context::{StageContext, StageContextGuard};
thread_local! {static STACK:RefCell<Vec<Frame>>=const {RefCell::new(Vec::new())};}

fn sum_bounds(values: impl Iterator<Item = clock::CpuBounds>) -> clock::CpuBounds {
    values.fold(
        clock::CpuBounds {
            lower: 0.0,
            upper: 0.0,
        },
        clock::CpuBounds::add,
    )
}
// Union only observations from the same thread. Overlapping spans share clock
// uncertainty; charging it once per nested segment would multiply one error.
fn union_interval_bounds(mut intervals: Vec<clock::CpuInterval>) -> Option<clock::CpuBounds> {
    intervals.sort_unstable_by_key(|i| (i.raw_begin, i.raw_end));
    let mut merged: Vec<clock::CpuInterval> = Vec::new();
    for interval in intervals {
        if let Some(last) = merged.last_mut() {
            if interval.raw_begin <= last.raw_end {
                // Paired coarse endpoints must remain monotonic. Equal raw
                // boundaries must have identical paired observations.
                if interval.coarse_begin < last.coarse_begin
                    || interval.coarse_begin > last.coarse_end
                    || (interval.raw_begin == last.raw_begin
                        && interval.coarse_begin != last.coarse_begin)
                    || (interval.raw_begin == last.raw_end
                        && interval.coarse_begin != last.coarse_end)
                {
                    return None;
                }
                if interval.raw_end > last.raw_end {
                    if interval.coarse_end < last.coarse_end {
                        return None;
                    }
                    last.raw_end = interval.raw_end;
                    last.coarse_end = interval.coarse_end;
                } else if interval.coarse_end > last.coarse_end
                    || (interval.raw_end == last.raw_end && interval.coarse_end != last.coarse_end)
                {
                    return None;
                }
                continue;
            }
        }
        merged.push(interval);
    }
    Some(sum_bounds(
        merged.into_iter().map(|i| i.bounds(cfg!(windows))),
    ))
}
fn interval_bounds(intervals: &[clock::CpuInterval]) -> clock::CpuBounds {
    // Merge only exactly contiguous observations, never fill an unobserved gap.
    let mut merged: Vec<clock::CpuInterval> = Vec::new();
    for interval in intervals {
        if let Some(last) = merged.last_mut() {
            if last.raw_end == interval.raw_begin && last.coarse_end == interval.coarse_begin {
                last.raw_end = interval.raw_end;
                last.coarse_end = interval.coarse_end;
                continue;
            }
        }
        merged.push(*interval);
    }
    merged
        .into_iter()
        .map(|interval| interval.bounds(cfg!(windows)))
        .fold(
            clock::CpuBounds {
                lower: 0.0,
                upper: 0.0,
            },
            clock::CpuBounds::add,
        )
}
fn cpu_interval(start: Option<u64>, end: Option<u64>) -> Option<u64> {
    end.zip(start)
        .and_then(|(end, start)| end.checked_sub(start))
}
fn cpu_boundary(_state: &State) -> (Option<u64>, Option<u64>) {
    let sample = clock::thread_coarse_ns();
    (sample, sample)
}
fn outermost_name(stack: &[Frame], name: &str) -> bool {
    !stack.iter().any(|frame| frame.name == name)
}
fn coarse_segment(state: &State, now: Option<u64>) {
    STACK.with(|stack| {
        if let Some(frame) = stack.borrow_mut().last_mut() {
            let mut entries = state.entries.lock().unwrap_or_else(|e| e.into_inner());
            let entry = entries.entry(frame.name).or_default();
            match cpu_interval(frame.last_coarse_cpu, now) {
                Some(delta) => entry.coarse_exclusive += delta,
                None => entry.coarse_missing = true,
            }
            frame.last_coarse_cpu = now;
        }
    });
}
fn cpu_segment(state: &State, now: Option<u64>, coarse: Option<u64>, wall: Instant) {
    STACK.with(|stack| {
        let mut stack = stack.borrow_mut();
        let path = stack
            .iter()
            .map(|frame| frame.name)
            .collect::<Vec<_>>()
            .join(";");
        if let Some(frame) = stack.last_mut() {
            *state
                .wall_folded
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .entry(path.clone())
                .or_default() += wall
                .duration_since(frame.last_wall)
                .as_nanos()
                .min(u64::MAX as u128) as u64;
            frame.last_wall = wall;
            if let Some(delta) = cpu_interval(frame.last_cpu, now) {
                let thread = thread_label::owned();
                let mut entries = state.entries.lock().unwrap_or_else(|e| e.into_inner());
                entries.entry(frame.name).or_default().exclusive += delta;
                *entries
                    .entry(frame.name)
                    .or_default()
                    .exclusive_threads
                    .entry(thread.clone())
                    .or_default() += delta;
                if let Some(interval) = clock::CpuInterval::from_samples(
                    frame.last_cpu,
                    now,
                    frame.last_coarse_cpu,
                    coarse,
                ) {
                    entries
                        .entry(frame.name)
                        .or_default()
                        .exclusive_intervals
                        .entry(thread.clone())
                        .or_default()
                        .push(interval);
                    state
                        .folded
                        .lock()
                        .unwrap_or_else(|e| e.into_inner())
                        .entry((thread, path))
                        .or_default()
                        .push(interval);
                } else {
                    entries.entry(frame.name).or_default().interval_missing = true;
                }
            } else {
                state
                    .entries
                    .lock()
                    .unwrap_or_else(|error| error.into_inner())
                    .entry(frame.name)
                    .or_default()
                    .cpu_missing = true;
            }
            frame.last_cpu = now;
        }
    });
}
pub struct StageGuard {
    state: Option<Arc<State>>,
    name: &'static str,
    start: Instant,
    cpu: Option<u64>,
    coarse_cpu: Option<u64>,
    process: clock::ProcessIo,
    allocations: u64,
    bytes: u64,
    prior_peak: u64,
    aggregate_interval: bool,
    entered: Option<tracing::span::EnteredSpan>,
    thread_bound: PhantomData<Rc<()>>,
}
/// Enter the same named stage on every participating thread. Guards are thread-bound.
pub fn stage(name: &'static str) -> StageGuard {
    let state = ACTIVE.get().cloned();
    if state.is_none() {
        return StageGuard {
            state: None,
            name,
            start: Instant::now(),
            cpu: None,
            coarse_cpu: None,
            process: clock::ProcessIo::default(),
            allocations: 0,
            bytes: 0,
            prior_peak: 0,
            aggregate_interval: true,
            entered: None,
            thread_bound: PhantomData,
        };
    }
    let (start_cpu, start_coarse_cpu) = state
        .as_ref()
        .map(|state| cpu_boundary(state))
        .unwrap_or((None, None));
    let start_wall = Instant::now();
    let aggregate_interval = STACK.with(|stack| outermost_name(stack.borrow().as_slice(), name));
    if let Some(state) = &state {
        cpu_segment(state, start_cpu, start_coarse_cpu, start_wall);
        coarse_segment(state, start_coarse_cpu);
        memory::enter(state, name);
        STACK.with(|stack| {
            stack.borrow_mut().push(Frame {
                name,
                last_cpu: start_cpu,
                last_coarse_cpu: start_coarse_cpu,
                last_wall: start_wall,
            })
        });
    }
    let (allocations, bytes, _) = allocator::snapshot();
    let prior_peak = allocator::reset_peak();
    StageGuard {
        cpu: start_cpu,
        coarse_cpu: start_coarse_cpu,
        state,
        name,
        start: start_wall,
        process: clock::process_io(),
        allocations,
        bytes,
        prior_peak,
        aggregate_interval,
        entered: Some(
            tracing::info_span!(
                "compiler_stage",
                stage = name,
                cpu_raw = tracing::field::Empty,
                cpu_raw_units = "thread_cpu_nanoseconds",
                allocated_bytes = tracing::field::Empty,
                allocations = tracing::field::Empty,
                peak_live_bytes = tracing::field::Empty
            )
            .entered(),
        ),
        thread_bound: PhantomData,
    }
}
/// Explicit byte counts and blocked duration belong to the active leaf stage.
/// This is partial coverage unless every I/O call in that stage is instrumented.
pub fn record_io(
    read_bytes: u64,
    write_bytes: u64,
    blocked: impl Into<Option<std::time::Duration>>,
) {
    let Some(state) = ACTIVE.get() else {
        return;
    };
    STACK.with(|stack| {
        if let Some(frame) = stack.borrow().last() {
            let mut entries = state.entries.lock().unwrap_or_else(|e| e.into_inner());
            let report = &mut entries.entry(frame.name).or_default().report;
            report.attributed_read_bytes = report.attributed_read_bytes.saturating_add(read_bytes);
            report.attributed_write_bytes =
                report.attributed_write_bytes.saturating_add(write_bytes);
            if let Some(blocked) = blocked.into() {
                report.io_blocked_s =
                    Some(report.io_blocked_s.unwrap_or(0.0) + blocked.as_secs_f64());
            }
        }
    });
}
/// Measure one synchronous I/O operation and its successfully returned byte count.
/// Elapsed time includes kernel work, copying and scheduling; it is not evidence
/// of time blocked on storage. Failed operations may have transferred partial
/// bytes that their error does not expose, so those bytes are not fabricated.
pub fn io_call<T>(
    operation: impl FnOnce() -> std::io::Result<T>,
    byte_counts: impl FnOnce(&T) -> (u64, u64),
) -> std::io::Result<T> {
    let Some(state) = ACTIVE.get() else {
        return operation();
    };
    let start = Instant::now();
    let result = operation();
    let elapsed = start.elapsed().as_secs_f64();
    if let Ok(value) = &result {
        let (read, written) = byte_counts(value);
        record_io(read, written, None);
    }
    STACK.with(|stack| {
        if let Some(frame) = stack.borrow().last() {
            let mut entries = state.entries.lock().unwrap_or_else(|e| e.into_inner());
            let report = &mut entries.entry(frame.name).or_default().report;
            report.io_call_elapsed_s = Some(report.io_call_elapsed_s.unwrap_or(0.0) + elapsed);
            report.io_calls = report.io_calls.saturating_add(1);
            report.io_failed_calls = report
                .io_failed_calls
                .saturating_add(u64::from(result.is_err()));
        }
    });
    result
}
impl Drop for StageGuard {
    fn drop(&mut self) {
        let Some(state) = &self.state else {
            return;
        };
        let (end_cpu, end_coarse_cpu) = cpu_boundary(state);
        let end_wall = Instant::now();
        cpu_segment(state, end_cpu, end_coarse_cpu, end_wall);
        coarse_segment(state, end_coarse_cpu);
        let cpu = cpu_interval(self.cpu, end_cpu);
        let coarse_cpu = cpu_interval(self.coarse_cpu, end_coarse_cpu);
        STACK.with(|stack| {
            let mut stack = stack.borrow_mut();
            stack.pop();
            if let Some(parent) = stack.last_mut() {
                parent.last_cpu = end_cpu;
                parent.last_coarse_cpu = end_coarse_cpu;
                parent.last_wall = end_wall;
            }
        });
        let (allocations, bytes, _) = allocator::snapshot();
        let peak = allocator::restore_peak(self.prior_peak);
        let process = clock::process_io();
        let mut entries = state.entries.lock().unwrap_or_else(|e| e.into_inner());
        let entry = entries.entry(self.name).or_default();
        entry.cpu_stage = true;
        entry.active = entry.active.saturating_sub(1);
        entry.report.name = self.name.into();
        entry.report.calls += 1;
        thread_label::with_label(|thread| {
            record_cpu_interval(entry, thread, cpu, self.aggregate_interval);
            if self.aggregate_interval {
                if let Some(interval) = clock::CpuInterval::from_samples(
                    self.cpu,
                    end_cpu,
                    self.coarse_cpu,
                    end_coarse_cpu,
                ) {
                    entry
                        .intervals
                        .entry(thread.to_owned())
                        .or_default()
                        .push(interval);
                } else {
                    entry.interval_missing = true;
                }
            }
            record_coarse_interval(entry, thread, coarse_cpu, self.aggregate_interval);
        });
        if self.aggregate_interval {
            entry.report.wall_s += end_wall.duration_since(self.start).as_secs_f64();
            entry.report.allocations += allocations.saturating_sub(self.allocations);
            entry.report.allocated_bytes += bytes.saturating_sub(self.bytes);
        }
        entry.report.peak_live_bytes = entry.report.peak_live_bytes.max(peak);
        let add = |target: &mut Option<u64>, end: Option<u64>, begin: Option<u64>| {
            if let Some(bytes) = end.zip(begin).map(|(a, b)| a.saturating_sub(b)) {
                *target = Some(target.unwrap_or(0) + bytes);
            }
        };
        add(
            &mut entry.report.read_bytes,
            process.read_bytes,
            self.process.read_bytes,
        );
        add(
            &mut entry.report.write_bytes,
            process.write_bytes,
            self.process.write_bytes,
        );
        entry.report.io_scope = "overlapping_process_windows_not_additive";
        if let Some(entered) = self.entered.take() {
            if let Some(cpu) = cpu {
                entered.record("cpu_raw", cpu);
            }
            entered.record("allocated_bytes", bytes.saturating_sub(self.bytes));
            entered.record("allocations", allocations.saturating_sub(self.allocations));
            entered.record("peak_live_bytes", peak);
        }
    }
}

/// Same-named nested spans on one thread cover a union, not two independent
/// intervals. Their Chrome spans remain separate, but the stage aggregate uses
/// only the outermost interval. Missing nested clocks still invalidate coverage.
fn record_cpu_interval(entry: &mut Entry, thread: &str, cpu: Option<u64>, aggregate: bool) {
    if let Some(cpu) = cpu {
        if aggregate {
            *entry.threads.entry(thread.into()).or_default() += cpu;
            entry.cpu_valid = true;
        }
    } else {
        entry.cpu_missing = true;
    }
}
fn record_coarse_interval(entry: &mut Entry, thread: &str, cpu: Option<u64>, aggregate: bool) {
    match cpu {
        Some(cpu) if aggregate => {
            *entry.coarse_threads.entry(thread.into()).or_default() += cpu;
            entry.coarse_valid = true;
        }
        None => entry.coarse_missing = true,
        _ => (),
    }
}

pub struct ProfileGuard {
    state: Arc<State>,
    start: Instant,
    process: clock::Process,
    path: PathBuf,
    chrome: Option<tracing_chrome::FlushGuard>,
    flame: Option<tracing_flame::FlushGuard<std::io::BufWriter<trace_output::TraceWriter>>>,
    trace_outputs: trace_output::Outputs,
    memory_sampler: Option<memory::Sampler>,
}
pub fn artifact_path(path: &Path, suffix: &str) -> PathBuf {
    path.with_extension(suffix.trim_start_matches('.'))
}
pub fn initialize(path: &Path) -> Result<ProfileGuard, String> {
    let start = Instant::now();
    let process = clock::process();
    if let Some(parent) = path.parent().filter(|p| !p.as_os_str().is_empty()) {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let state = Arc::new(State {
        calibration: clock::calibrate(),
        entries: Mutex::new(BTreeMap::new()),
        folded: Mutex::new(BTreeMap::new()),
        wall_folded: Mutex::new(BTreeMap::new()),
    });
    let setup = internal_observer::InternalThreadObserver::new(Arc::clone(&state), "profile.setup");
    let mut trace_outputs = trace_output::Outputs::from_environment().map_err(|e| e.to_string())?;
    let writer = writer::ObservedWriter::new(
        trace_outputs
            .writer(path, "chrome-json")
            .map_err(|e| e.to_string())?,
        Arc::clone(&state),
    );
    let (chrome, chrome_guard) = tracing_chrome::ChromeLayerBuilder::new()
        .writer(writer)
        .include_args(true)
        .name_fn(Box::new(|entry| match entry {
            tracing_chrome::EventOrSpan::Span(span) => span
                .extensions()
                .get::<names::StageName>()
                .map(|name| name.0.clone())
                .unwrap_or_else(|| span.metadata().name().into()),
            tracing_chrome::EventOrSpan::Event(event) => event.metadata().name().into(),
        }))
        .build();
    let flame_writer = trace_outputs
        .writer(&artifact_path(path, ".tracing.folded"), "tracing-folded")
        .map_err(|e| e.to_string())?;
    let flame = tracing_flame::FlameLayer::new(std::io::BufWriter::new(flame_writer));
    let flame_guard = flame.flush_on_drop();
    tracing_subscriber::registry()
        .with(names::Names)
        .with(chrome)
        .with(flame)
        .try_init()
        .map_err(|e| e.to_string())?;
    ACTIVE
        .set(Arc::clone(&state))
        .map_err(|_| "profiler already initialized".to_string())?;
    let memory_sampler = memory::Sampler::start(Arc::clone(&state))?;
    drop(setup);
    Ok(ProfileGuard {
        state,
        start,
        process,
        path: path.into(),
        chrome: Some(chrome_guard),
        flame: Some(flame_guard),
        trace_outputs,
        memory_sampler,
    })
}
impl ProfileGuard {
    /// Lets a caller select a proven alternate pipeline (for example an
    /// authenticated unchanged build). Missing selected stages still fail the
    /// critical-path measurement in `finish`.
    pub fn has_stage(&self, name: &str) -> bool {
        self.state
            .entries
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .get(name)
            .is_some_and(|entry| entry.report.calls > 0)
    }
    /// Supply sequential inclusive names plus `exclusive:name` residual parents.
    /// Residuals exclude nested CPU stages; the caller must cover omitted children
    /// and prove that selected inclusive stages do not overlap.
    pub fn finish(mut self, sequential_stages: &[&str]) -> Result<Report, String> {
        self.finish_inner(sequential_stages)
    }
    fn finish_inner(&mut self, sequential_stages: &[&str]) -> Result<Report, String> {
        let shutdown = internal_observer::InternalThreadObserver::new(
            Arc::clone(&self.state),
            "profile.finalization",
        );
        if let Some(sampler) = self.memory_sampler.take() {
            sampler.stop()?;
        }
        // Drop sends the termination message and joins the Chrome writer. Its
        // direct lifetime CPU receipt must exist before the report snapshot.
        self.chrome.take();
        let flame_result = self.flame.as_ref().map(|guard| guard.flush()).transpose();
        self.flame.take();
        let trace_output = self
            .trace_outputs
            .finish()
            .map_err(|error| error.to_string())?;
        flame_result.map_err(|error| error.to_string())?;
        drop(shutdown);
        let process = clock::process();
        let measured_wall = self.start.elapsed().as_secs_f64();
        let delta = |a: Option<u64>, b: Option<u64>| a.zip(b).map(|(a, b)| a.saturating_sub(b));
        let total = delta(process.cpu_ns, self.process.cpu_ns).map(|v| v as f64 / 1e9);
        let thread_calibrations: Vec<clock::ThreadCalibration> = Vec::new();
        // Only failed/backward direct stage clock samples can omit CPU data.
        let omitted_threads = self
            .state
            .folded
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .iter()
            .filter(|((_thread, _), intervals)| {
                intervals
                    .iter()
                    .any(|interval| clock::convert_interval(*interval).is_none())
            })
            .map(|((thread, _), _)| thread.clone())
            .collect::<std::collections::BTreeSet<_>>()
            .into_iter()
            .collect::<Vec<_>>();
        let entries = self.state.entries.lock().unwrap_or_else(|e| e.into_inner());
        let stages = entries
            .values()
            .map(|entry| {
                let mut report = entry.report.clone();
                report.cpu_measurement = if report.name == "compiler.worker_lifetime" {
                    "worker_lifetime_coverage_not_additive_stage_cpu"
                } else if entry.cpu_stage {
                    "stage_thread_cpu"
                } else {
                    "wall_allocations_only"
                };
                report.wall_scope = "sum_thread_intervals_not_phase_elapsed";
                report.allocation_scope =
                    "sum_thread_local_inclusive_interval_deltas_not_process_total";
                report.peak_live_scope =
                    "process_requested_live_bytes_observed_on_stage_thread_allocations";
                if matches!(
                    report.name.as_str(),
                    "profile.setup"
                        | "profile.finalization"
                        | "profile.chrome_writer"
                        | "profiler.memory_sampler"
                        | "compiler.worker_lifetime"
                ) {
                    report.allocation_scope = "unmeasured_internal_observer";
                    report.peak_live_scope = "unmeasured_internal_observer";
                }
                report.sampled_private_scope =
                    "process_current_private_bytes_sampled_while_stage_active_not_attributable";
                if entry.cpu_valid && !entry.cpu_missing && !entry.interval_missing {
                    let converted = entry
                        .intervals
                        .values()
                        .map(|intervals| {
                            intervals
                                .iter()
                                .map(|interval| clock::convert_interval(*interval))
                                .sum::<Option<f64>>()
                        })
                        .collect::<Option<Vec<_>>>();
                    if let Some(converted) = converted {
                        report.cpu_s = Some(converted.iter().sum());
                        report.max_thread_cpu_s = converted.into_iter().reduce(f64::max);
                    }
                    report.exclusive_cpu_s = entry
                        .exclusive_intervals
                        .values()
                        .map(|intervals| {
                            intervals
                                .iter()
                                .map(|interval| clock::convert_interval(*interval))
                                .sum::<Option<f64>>()
                        })
                        .sum::<Option<f64>>();
                    report.max_thread_exclusive_cpu_s = entry
                        .exclusive_intervals
                        .values()
                        .map(|intervals| {
                            intervals
                                .iter()
                                .map(|v| clock::convert_interval(*v))
                                .sum::<Option<f64>>()
                        })
                        .collect::<Option<Vec<_>>>()
                        .and_then(|values| values.into_iter().reduce(f64::max));
                    let bounds = entry
                        .intervals
                        .values()
                        .map(|intervals| interval_bounds(intervals))
                        .collect::<Vec<_>>();
                    report.cpu_bounds_s = Some(sum_bounds(bounds.iter().copied()));
                    report.max_thread_cpu_bounds_s =
                        bounds.into_iter().reduce(|a, b| clock::CpuBounds {
                            lower: a.lower.max(b.lower),
                            upper: a.upper.max(b.upper),
                        });
                    report.exclusive_cpu_bounds_s = Some(sum_bounds(
                        entry
                            .exclusive_intervals
                            .values()
                            .map(|intervals| interval_bounds(intervals)),
                    ));
                    report.max_thread_exclusive_cpu_bounds_s = entry
                        .exclusive_intervals
                        .values()
                        .map(|intervals| interval_bounds(intervals))
                        .reduce(|a, b| clock::CpuBounds {
                            lower: a.lower.max(b.lower),
                            upper: a.upper.max(b.upper),
                        });
                }
                if entry.coarse_valid && !entry.coarse_missing {
                    report.coarse_thread_cpu_s =
                        Some(entry.coarse_threads.values().sum::<u64>() as f64 / 1e9);
                    report.coarse_max_thread_cpu_s =
                        entry.coarse_threads.values().max().map(|v| *v as f64 / 1e9);
                    report.coarse_exclusive_thread_cpu_s =
                        Some(entry.coarse_exclusive as f64 / 1e9);
                }
                report
            })
            .collect::<Vec<_>>();
        let covered_union = if entries
            .values()
            .filter(|entry| entry.cpu_stage)
            .any(|entry| !entry.cpu_valid || entry.cpu_missing || entry.interval_missing)
        {
            None
        } else {
            let mut by_thread: BTreeMap<String, Vec<clock::CpuInterval>> = BTreeMap::new();
            for entry in entries.values() {
                for (thread, intervals) in &entry.intervals {
                    by_thread
                        .entry(thread.clone())
                        .or_default()
                        .extend(intervals.iter().copied());
                }
            }
            by_thread
                .into_values()
                .map(|intervals| {
                    let cpu = worker::union_interval_cpu(intervals.clone());
                    union_interval_bounds(intervals).map(|bounds| (cpu, bounds))
                })
                .collect::<Option<Vec<_>>>()
                .map(|values| {
                    let cpu = values.iter().map(|(cpu, _)| *cpu).sum::<u64>() as f64 / 1e9;
                    let bounds = sum_bounds(values.into_iter().map(|(_, bounds)| bounds));
                    (cpu, bounds)
                })
        };
        let covered_bounds = covered_union.map(|(_, bounds)| bounds);
        let covered = covered_union.map(|(cpu, _)| cpu);
        drop(entries);
        // The direct stage and coarse endpoints are the same clock. Preserve
        // the legacy field with the same union, rather than double-counting.
        let coarse_covered = covered;
        let unique = sequential_stages
            .iter()
            .copied()
            .collect::<std::collections::BTreeSet<_>>();
        let critical = if sequential_stages.is_empty() || unique.len() != sequential_stages.len() {
            None
        } else {
            sequential_stages
                .iter()
                .map(|name| {
                    let (stage, exclusive) = critical_stage(&stages, name)?;
                    if exclusive {
                        stage.max_thread_exclusive_cpu_s
                    } else {
                        stage.max_thread_cpu_s
                    }
                })
                .sum::<Option<f64>>()
        };
        let critical_bounds =
            if sequential_stages.is_empty() || unique.len() != sequential_stages.len() {
                None
            } else {
                sequential_stages
                    .iter()
                    .map(|name| {
                        let (stage, exclusive) = critical_stage(&stages, name)?;
                        if exclusive {
                            stage.max_thread_exclusive_cpu_bounds_s
                        } else {
                            stage.max_thread_cpu_bounds_s
                        }
                    })
                    .collect::<Option<Vec<_>>>()
                    .map(|values| sum_bounds(values.into_iter()))
            };
        let report = Report {
            trace_output,
            schema: 1,
            wall_s: measured_wall,
            wall_scope: "profile_elapsed_wall_interval",
            critical_path_cpu_s: critical,
            critical_path_stages: sequential_stages.iter().map(|name| (*name).to_string()).collect(),
            total_cpu_s: total,
            covered_thread_cpu_s: covered,
            critical_path_cpu_bounds_s: critical_bounds,
            covered_thread_cpu_bounds_s: covered_bounds,
            cpu_crosscheck_ratio_bounds: total.filter(|v| *v > 0.0).zip(covered_bounds).map(|(total, bounds)| clock::CpuBounds { lower: bounds.lower / total, upper: bounds.upper / total }),
            cpu_bounds_method: "paired_thread_cpu_quantization",
            covered_cpu_bounds_method: "participating_thread_interval_union",
            cpu_bounds_quantum_s: if cfg!(windows) { 0.03125 } else { 0.0 },
            peak_private_bytes: process.peak_private_bytes,
            peak_private_scope: "process_lifetime_os_private_peak",
            peak_allocator_live_bytes: allocator::peak(),
            peak_allocator_live_scope: "process_lifetime_requested_live_allocation_peak",
            read_bytes: delta(process.read_bytes, self.process.read_bytes),
            write_bytes: delta(process.write_bytes, self.process.write_bytes),
            allocation_counting: cfg!(feature = "allocation-counting"),
            calibration: self.state.calibration.clone(),
            cpu_crosscheck_ratio: covered.zip(total.filter(|v| *v > 0.0)).map(|(covered, total)| covered / total),
            cpu_precision_scope: if cfg!(windows) {
                "direct_GetThreadTimes_stage_boundaries_with_quantization_bounds"
            } else {
                "native_thread_cpu_clock_platform_resolution"
            },
            coarse_covered_thread_cpu_s: coarse_covered,
            coarse_cpu_crosscheck_ratio: coarse_covered.zip(total.filter(|v| *v > 0.0)).map(|(covered, total)| covered / total),
            thread_calibrations: thread_calibrations.clone(),
            cpu_conversion_complete: covered.is_some() && critical.is_some() && omitted_threads.is_empty(),
            cpu_folded_omitted_threads: omitted_threads,
            stages,
            coverage_notes: vec![
                "Profiler setup/finalization and memory-worker CPU use direct non-tracing endpoint receipts. Chrome writer CPU covers its first underlying write/flush through drop after final flush; tracing-chrome buffers its initial output, so worker startup/initial buffered serialization before that boundary is unobserved. Worker joins precede the independent process endpoint and report snapshot. These internal receipts record CPU/wall only; allocation fields are not separately observed. Report serialization after the snapshot is outside this measurement window.".into(),
                "Stage CPU uses GetThreadTimes on Windows or CLOCK_THREAD_CPUTIME_ID on Linux, directly as nanoseconds; no cycles or calibration. Item-only spans record wall and allocations and do not split parent CPU intervals. Successful monotonic Windows stage endpoints provide bounds plus/minus31.25ms. Missing clocks stay unknown. Independent process coverage and entire ratio bounds retain5% tolerance. Chrome cpu_raw units are thread CPU nanoseconds.".into(),
                "CPU folded stacks use exclusive entered stage segments; uninstrumented threads/work are excluded. Chrome/flame wall traces come from tracing spans.".into(),
                "Same-named nested spans on one thread contribute only their outermost inclusive CPU, wall and allocation interval to the named stage aggregate; call counts and individual Chrome spans retain every call.".into(),
                "Allocator numbers include profiler overhead and nested scopes; peak_live is observed process allocator live bytes on current-thread allocations, not OS private memory attribution. Allocation counting requires the executable to install CountingAllocator.".into(),
                "Windows stage private memory is current process PrivateUsage sampled nominally every 20 ms while named stages are active. Values overlap across stages, include profiler overhead, miss short stages and between-sample peaks, and are not allocations attributable to a stage. Null means no successful sample; failed samples are counted. Other platforms have no stage private-memory sampling.".into(),
                "Stage I/O uses process-wide overlapping windows and includes profiling writes; it is not additive. Explicit attributed bytes/call elapsed/block durations cover only annotated operations; call elapsed includes scheduling and copying and is not blocked I/O. Failed calls can leave partial byte counts unknown. Windows peak_private is process lifetime peak committed private/pagefile usage; Linux private peak unavailable.".into(),
            ],
            private_memory_sample_interval_ms: memory::interval_ms(),
        };
        let mut file =
            File::create(artifact_path(&self.path, ".cpu.folded")).map_err(|e| e.to_string())?;
        let mut converted_stacks = BTreeMap::<String, f64>::new();
        for ((_thread, stack), intervals) in self
            .state
            .folded
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .iter()
        {
            if let Some(seconds) = intervals
                .iter()
                .map(|interval| clock::convert_interval(*interval))
                .sum::<Option<f64>>()
            {
                *converted_stacks.entry(stack.clone()).or_default() += seconds;
            }
        }
        for (stack, seconds) in converted_stacks {
            let ns = (seconds * 1e9).round() as u64;
            if ns > 0 {
                writeln!(file, "{stack} {ns}").map_err(|e| e.to_string())?;
            }
        }
        drop(file);
        let mut wall =
            File::create(artifact_path(&self.path, ".wall.folded")).map_err(|e| e.to_string())?;
        for (stack, ns) in self
            .state
            .wall_folded
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .iter()
        {
            if *ns > 0 {
                writeln!(wall, "{stack} {ns}").map_err(|e| e.to_string())?;
            }
        }
        drop(wall);
        for kind in ["cpu", "wall"] {
            let folded_path = artifact_path(&self.path, &format!(".{kind}.folded"));
            if std::fs::metadata(&folded_path)
                .map_err(|e| e.to_string())?
                .len()
                == 0
            {
                std::fs::write(artifact_path(&self.path,&format!(".{kind}.svg")),format!("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"600\" height=\"60\"><text x=\"10\" y=\"30\">No measured {kind} spans available</text></svg>")).map_err(|e|e.to_string())?;
                continue;
            }
            let mut options = inferno::flamegraph::Options::default();
            options.title = format!("Compiler {kind} span profile");
            inferno::flamegraph::from_reader(
                &mut options,
                BufReader::new(
                    File::open(artifact_path(&self.path, &format!(".{kind}.folded")))
                        .map_err(|e| e.to_string())?,
                ),
                File::create(artifact_path(&self.path, &format!(".{kind}.svg")))
                    .map_err(|e| e.to_string())?,
            )
            .map_err(|e| e.to_string())?;
        }
        serde_json::to_writer_pretty(
            File::create(artifact_path(&self.path, ".report.json")).map_err(|e| e.to_string())?,
            &report,
        )
        .map_err(|e| e.to_string())?;
        Ok(report)
    }
}
impl Drop for ProfileGuard {
    fn drop(&mut self) {
        if self.chrome.is_some() {
            if let Err(error) = self.finish_inner(&[]) {
                eprintln!("profile artifact write failed: {error}");
            }
        }
    }
}

#[cfg(test)]
#[path = "tests.rs"]
mod interval_tests;
