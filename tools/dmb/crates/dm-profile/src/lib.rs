//! Span profiler with platform CPU clocks. No sampling agent or elevation.
mod allocator;
mod clock;
mod names;
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

#[derive(Clone, Debug, Default, Serialize)]
pub struct StageReport {
    pub name: String,
    pub calls: u64,
    pub wall_s: f64,
    pub cpu_s: Option<f64>,
    pub max_thread_cpu_s: Option<f64>,
    pub exclusive_cpu_s: Option<f64>,
    pub allocations: u64,
    pub allocated_bytes: u64,
    pub peak_live_bytes: u64,
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
#[derive(Clone, Debug, Serialize)]
pub struct Report {
    pub schema: u32,
    pub wall_s: f64,
    pub critical_path_cpu_s: Option<f64>,
    pub critical_path_stages: Vec<String>,
    pub total_cpu_s: Option<f64>,
    pub covered_thread_cpu_s: f64,
    pub peak_private_bytes: Option<u64>,
    pub peak_allocator_live_bytes: u64,
    pub read_bytes: Option<u64>,
    pub write_bytes: Option<u64>,
    pub allocation_counting: bool,
    pub calibration: clock::Calibration,
    pub cpu_crosscheck_ratio: Option<f64>,
    pub stages: Vec<StageReport>,
    pub coverage_notes: Vec<String>,
}
#[derive(Default)]
struct Entry {
    report: StageReport,
    threads: BTreeMap<String, u64>,
    exclusive: u64,
    cpu_valid: bool,
    cpu_missing: bool,
}
struct State {
    calibration: clock::Calibration,
    entries: Mutex<BTreeMap<&'static str, Entry>>,
    folded: Mutex<BTreeMap<String, u64>>,
    wall_folded: Mutex<BTreeMap<String, u64>>,
}
static ACTIVE: OnceLock<Arc<State>> = OnceLock::new();
struct Frame {
    name: &'static str,
    last_cpu: Option<u64>,
    last_wall: Instant,
}
thread_local! {static STACK:RefCell<Vec<Frame>>=const {RefCell::new(Vec::new())};}

fn cpu_interval(start: Option<u64>, end: Option<u64>) -> Option<u64> {
    end.zip(start)
        .and_then(|(end, start)| end.checked_sub(start))
}
#[cfg(test)]
mod interval_tests {
    use super::*;
    #[test]
    fn shared_cpu_boundaries_partition_nested_intervals_exactly() {
        let state = State {
            calibration: clock::Calibration {
                method: "scripted",
                cycles_per_cpu_second: None,
                calibration_wall_s: 0.0,
                calibration_cpu_s: None,
                note: "test",
            },
            entries: Mutex::new(BTreeMap::new()),
            folded: Mutex::new(BTreeMap::new()),
            wall_folded: Mutex::new(BTreeMap::new()),
        };
        let wall = Instant::now();
        STACK.with(|stack| {
            stack.borrow_mut().push(Frame {
                name: "parent",
                last_cpu: Some(10),
                last_wall: wall,
            })
        });
        cpu_segment(&state, Some(20), wall);
        STACK.with(|stack| {
            stack.borrow_mut().push(Frame {
                name: "child",
                last_cpu: Some(20),
                last_wall: wall,
            })
        });
        cpu_segment(&state, Some(30), wall);
        STACK.with(|stack| {
            let mut stack = stack.borrow_mut();
            stack.pop();
            stack.last_mut().unwrap().last_cpu = Some(30);
        });
        cpu_segment(&state, Some(50), wall);
        let entries = state.entries.lock().unwrap();
        assert_eq!(entries["parent"].exclusive, 30);
        assert_eq!(entries["child"].exclusive, 10);
        assert_eq!(
            entries.values().map(|entry| entry.exclusive).sum::<u64>(),
            cpu_interval(Some(10), Some(50)).unwrap()
        );
        drop(entries);
        cpu_segment(&state, None, wall);
        assert!(state.entries.lock().unwrap()["parent"].cpu_missing);
        STACK.with(|stack| stack.borrow_mut().clear());
        assert_eq!(cpu_interval(Some(50), Some(49)), None);
        assert_eq!(cpu_interval(None, Some(50)), None);
    }
}
fn cpu_segment(state: &State, now: Option<u64>, wall: Instant) {
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
                let mut entries = state.entries.lock().unwrap_or_else(|e| e.into_inner());
                entries.entry(frame.name).or_default().exclusive += delta;
                *state
                    .folded
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .entry(path)
                    .or_default() += delta;
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
    process: clock::Process,
    allocations: u64,
    bytes: u64,
    prior_peak: u64,
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
            process: clock::Process::default(),
            allocations: 0,
            bytes: 0,
            prior_peak: 0,
            entered: None,
            thread_bound: PhantomData,
        };
    }
    let start_cpu = state
        .as_ref()
        .and_then(|state| clock::thread_ns(&state.calibration));
    let start_wall = Instant::now();
    if let Some(state) = &state {
        cpu_segment(state, start_cpu, start_wall);
        STACK.with(|stack| {
            stack.borrow_mut().push(Frame {
                name,
                last_cpu: start_cpu,
                last_wall: start_wall,
            })
        });
    }
    let (allocations, bytes, _) = allocator::snapshot();
    let prior_peak = allocator::reset_peak();
    StageGuard {
        cpu: start_cpu,
        state,
        name,
        start: start_wall,
        process: clock::process(),
        allocations,
        bytes,
        prior_peak,
        entered: Some(
            tracing::info_span!(
                "compiler_stage",
                stage = name,
                cpu_ns = tracing::field::Empty,
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
        let end_cpu = clock::thread_ns(&state.calibration);
        let end_wall = Instant::now();
        cpu_segment(state, end_cpu, end_wall);
        let cpu = cpu_interval(self.cpu, end_cpu);
        STACK.with(|stack| {
            let mut stack = stack.borrow_mut();
            stack.pop();
            if let Some(parent) = stack.last_mut() {
                parent.last_cpu = end_cpu;
                parent.last_wall = end_wall;
            }
        });
        let (allocations, bytes, _) = allocator::snapshot();
        let peak = allocator::restore_peak(self.prior_peak);
        let process = clock::process();
        let mut entries = state.entries.lock().unwrap_or_else(|e| e.into_inner());
        let entry = entries.entry(self.name).or_default();
        entry.report.name = self.name.into();
        entry.report.calls += 1;
        entry.report.wall_s += end_wall.duration_since(self.start).as_secs_f64();
        if let Some(cpu) = cpu {
            *entry
                .threads
                .entry(format!("{:?}", std::thread::current().id()))
                .or_default() += cpu;
            entry.cpu_valid = true;
        } else {
            entry.cpu_missing = true;
        }
        entry.report.allocations += allocations.saturating_sub(self.allocations);
        entry.report.allocated_bytes += bytes.saturating_sub(self.bytes);
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
                entered.record("cpu_ns", cpu);
            }
            entered.record("allocated_bytes", bytes.saturating_sub(self.bytes));
            entered.record("allocations", allocations.saturating_sub(self.allocations));
            entered.record("peak_live_bytes", peak);
        }
    }
}

pub struct ProfileGuard {
    state: Arc<State>,
    start: Instant,
    process: clock::Process,
    path: PathBuf,
    chrome: Option<tracing_chrome::FlushGuard>,
    flame: Option<tracing_flame::FlushGuard<std::io::BufWriter<File>>>,
}
pub fn artifact_path(path: &Path, suffix: &str) -> PathBuf {
    path.with_extension(suffix.trim_start_matches('.'))
}
pub fn initialize(path: &Path) -> Result<ProfileGuard, String> {
    if let Some(parent) = path.parent().filter(|p| !p.as_os_str().is_empty()) {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let state = Arc::new(State {
        calibration: clock::calibrate(),
        entries: Mutex::new(BTreeMap::new()),
        folded: Mutex::new(BTreeMap::new()),
        wall_folded: Mutex::new(BTreeMap::new()),
    });
    let writer = File::create(path).map_err(|e| e.to_string())?;
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
    let (flame, flame_guard) =
        tracing_flame::FlameLayer::with_file(artifact_path(path, ".tracing.folded"))
            .map_err(|e| e.to_string())?;
    tracing_subscriber::registry()
        .with(names::Names)
        .with(chrome)
        .with(flame)
        .try_init()
        .map_err(|e| e.to_string())?;
    ACTIVE
        .set(Arc::clone(&state))
        .map_err(|_| "profiler already initialized".to_string())?;
    Ok(ProfileGuard {
        state,
        start: Instant::now(),
        process: clock::process(),
        path: path.into(),
        chrome: Some(chrome_guard),
        flame: Some(flame_guard),
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
    /// Supply only sequential top-level names. Nested/overlapping stage maxima
    /// cannot be summed into a critical path without an explicit pipeline proof.
    pub fn finish(mut self, sequential_stages: &[&str]) -> Result<Report, String> {
        self.finish_inner(sequential_stages)
    }
    fn finish_inner(&mut self, sequential_stages: &[&str]) -> Result<Report, String> {
        let process = clock::process();
        let delta = |a: Option<u64>, b: Option<u64>| a.zip(b).map(|(a, b)| a.saturating_sub(b));
        let total = delta(process.cpu_ns, self.process.cpu_ns).map(|v| v as f64 / 1e9);
        let entries = self.state.entries.lock().unwrap_or_else(|e| e.into_inner());
        let stages = entries
            .values()
            .map(|entry| {
                let mut report = entry.report.clone();
                if entry.cpu_valid && !entry.cpu_missing {
                    report.cpu_s = Some(entry.threads.values().sum::<u64>() as f64 / 1e9);
                    report.max_thread_cpu_s = entry.threads.values().max().map(|v| *v as f64 / 1e9);
                    report.exclusive_cpu_s = Some(entry.exclusive as f64 / 1e9);
                }
                report
            })
            .collect::<Vec<_>>();
        drop(entries);
        let covered = stages
            .iter()
            .filter_map(|stage| stage.exclusive_cpu_s)
            .sum::<f64>();
        let unique = sequential_stages
            .iter()
            .copied()
            .collect::<std::collections::BTreeSet<_>>();
        let critical = if sequential_stages.is_empty() || unique.len() != sequential_stages.len() {
            None
        } else {
            sequential_stages
                .iter()
                .map(|name| stages.iter().find(|s| s.name == *name)?.max_thread_cpu_s)
                .sum::<Option<f64>>()
        };
        let report = Report {
            schema: 1,
            wall_s: self.start.elapsed().as_secs_f64(),
            critical_path_cpu_s: critical,
            critical_path_stages: sequential_stages.iter().map(|name| (*name).to_string()).collect(),
            total_cpu_s: total,
            covered_thread_cpu_s: covered,
            peak_private_bytes: process.peak_private_bytes,
            peak_allocator_live_bytes: allocator::peak(),
            read_bytes: delta(process.read_bytes, self.process.read_bytes),
            write_bytes: delta(process.write_bytes, self.process.write_bytes),
            allocation_counting: cfg!(feature = "allocation-counting"),
            calibration: self.state.calibration.clone(),
            cpu_crosscheck_ratio: total.filter(|v| *v > 0.0).map(|v| covered / v),
            stages,
            coverage_notes: vec![
                "CPU folded stacks use exclusive entered stage segments; uninstrumented threads/work are excluded. Chrome/flame wall traces come from tracing spans.".into(),
                "Allocator numbers include profiler overhead and nested scopes; peak_live is observed process allocator live bytes on current-thread allocations, not OS private memory attribution. Allocation counting requires the executable to install CountingAllocator.".into(),
                "Stage I/O uses process-wide overlapping windows and includes profiling writes; it is not additive. Explicit attributed bytes/call elapsed/block durations cover only annotated operations; call elapsed includes scheduling and copying and is not blocked I/O. Failed calls can leave partial byte counts unknown. Windows peak_private is process lifetime peak committed private/pagefile usage; Linux private peak unavailable.".into(),
            ],
        };
        self.chrome.take();
        self.flame.take();
        let mut file =
            File::create(artifact_path(&self.path, ".cpu.folded")).map_err(|e| e.to_string())?;
        for (stack, ns) in self
            .state
            .folded
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .iter()
        {
            if *ns > 0 {
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
