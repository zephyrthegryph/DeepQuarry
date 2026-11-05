//! The one driver: `vg_frame(elapsed, budget)`.
//!
//! DM makes exactly one call into the simulation per tick. In it Rust
//!
//! 1. paces the [`World`](vg_core::world::World) (laws, heat, gas, power and
//!    the pipe devices: `PipeDeviceStep` is a law on the pacer's period,
//!    [`PIPE_DEVICE_PERIOD`] seconds per step),
//! 2. ticks the hosts that are not on the world's pacer,
//! 3. runs the scheduler (timers, rate crossings, keys, every watch port), and
//! 4. hands back **one outbox page** of records.
//!
//! Nothing else drains the simulation: the old `vg_world_tick`,
//! `vg_world_events`, `vg_world_step`, `vg_entity_tick_all`,
//! `vg_heat_take_wakes`, `vg_heat_tick`, `vg_drain_dirty_gas_observations`
//! and `vg_pipe_step_devices` are internal to this module now.
//!
//! # The outbox
//!
//! A flat list of records, every number exact as an `f32`:
//!
//! ```text
//! kind, a, b, n, payload[0], ..., payload[n - 1]
//! ```
//!
//! | kind | a | b | payload |
//! |---|---|---|---|
//! | [`REC_CHANGED`] | the entity (an entity for a plain change, a watch's subscriber for a change wake) | the key: a channel mask | a change wake: `lane, source` |
//! | [`REC_NOTICE`] | the entity the event is about (0: none) | the event header (`domain << 16 \| kind << 8 \| variant`, or a `NATIVE_NOTICE_*`) | the event's fields |
//! | [`REC_CROSSED`] | the watch's subscriber | the band: a wake's class bits, or a set entry's payload | wake: `lane, reason, source, source_kind`; set crossing: `entered, generation` |
//!
//! Records of one kind keep their emission order; occurrences are never
//! merged here (a wake is already merged per subscriber by the scheduler).
//! The DM side is `/datum/system/native` (`code/datums/native/system.dm`).

use vg_core::metrics::MetricsRegistry;
use std::cell::RefCell;

use byondapi::prelude::*;
use eyre::{Result, bail};
use vg_core::timer::Tick;

use crate::world::{list, num, whole};
use crate::{entity, gas, heat, sched, world};

/// Record kind: something changed (`entity`, `key`).
/// @dm-define NATIVE_REC_CHANGED
pub const REC_CHANGED: u32 = 1;
/// Record kind: something happened (`entity`, `header`, fields).
/// @dm-define NATIVE_REC_NOTICE
pub const REC_NOTICE: u32 = 2;
/// Record kind: a watch crossed a band (`watch`, `band`, detail).
/// @dm-define NATIVE_REC_CROSSED
pub const REC_CROSSED: u32 = 3;

/// The notice a pipe device's step raises: `moles, power_w, target_reached`.
/// Above every `domain << 16` event header.
/// @dm-define NATIVE_NOTICE_PIPE_DEVICE
pub const NOTICE_PIPE_DEVICE: u32 = 0x00FF_0001;

/// Seconds of one World step, which is the period of the pipe devices' flow law (`PipeDeviceStep`, one run per
/// step).
/// @dm-define NATIVE_PIPE_DEVICE_PERIOD
pub const PIPE_DEVICE_PERIOD: f32 = 0.5;

/// The most game time one frame gives the pacer (an overloaded server, or the
/// first frame, whose `elapsed` is the whole wheel tick count, must not owe a
/// flood of steps).
pub const MAX_PACE_SECONDS: f64 = 2.0;

/// A crossing record (set entry) carries two detail numbers, a wake four.
/// @dm-define NATIVE_CROSSED_SET_DETAIL
pub const CROSSED_SET_DETAIL: u32 = 2;

struct Clock {
    /// Seconds per wheel tick (`world.tick_lag / 10`).
    tick_seconds: f64,
    /// The wheel tick the scheduler is at: the sum of every `elapsed`.
    now: Tick,
    /// The next frame steps the world once, whatever the pacer owes ([`frame_force_devices`]).
    force_step: bool,
    frames: u64,
    /// World steps run by hand ([`note_steps`], `vg_world_run_steps`): time the native world passed outside the frame.
    steps: u64,
}

thread_local! {
    static CLOCK: RefCell<Clock> = const {
        RefCell::new(Clock { tick_seconds: 0.05, now: 0, force_step: false, frames: 0, steps: 0 })
    };
}

/// Tells the frame how long a wheel tick is: `tick_lag` in deciseconds
/// (`world.tick_lag`). Call at boot and whenever it changes.
#[auxmacros::bind("/proc/frame_set_tick_lag")]
fn frame_set_tick_lag(tick_lag: ByondValue) -> Result<ByondValue> {
    let lag = f64::from(num(&tick_lag)?);
    if lag.is_nan() || lag <= 0.0 {
        bail!("bad tick lag {lag}");
    }
    CLOCK.with_borrow_mut(|c| c.tick_seconds = lag / 10.0);
    Ok(ByondValue::null())
}

/// The frames run since boot (tests, the profiler).
#[auxmacros::bind("/proc/frame_count")]
fn frame_count() -> Result<ByondValue> {
    #[allow(clippy::cast_precision_loss)]
    Ok(ByondValue::from(CLOCK.with_borrow(|c| c.frames) as f32))
}

/// Counts `n` world steps run outside the frame (tests and admin tools step the world directly): `vg_world_steps_run()` reads the total, so a harness can tell that
/// native world time passed even though no frame ran.
pub(crate) fn note_steps(n: u64) {
    CLOCK.with_borrow_mut(|c| c.steps += n);
}

/// The world steps run by hand since boot (tests: whether native world time passed during one).
#[auxmacros::bind("/proc/world_steps_run")]
fn world_steps_run() -> Result<ByondValue> {
    #[allow(clippy::cast_precision_loss)]
    Ok(ByondValue::from(CLOCK.with_borrow(|c| c.steps) as f32))
}

/// Test hook: makes the next frame step the world once, so the pipe devices' law
/// runs for a full [`PIPE_DEVICE_PERIOD`] (a deterministic step for a DM test that
/// built a device by hand).
#[auxmacros::bind("/proc/frame_force_devices")]
fn frame_force_devices() -> Result<ByondValue> {
    CLOCK.with_borrow_mut(|c| c.force_step = true);
    Ok(ByondValue::null())
}

/// One frame: see the module docs. `elapsed` is the wheel ticks since the
/// last frame (`0`: no pacing, just drain: a test that ran steps by hand),
/// `budget` how many normal/background wakes to take (urgent ones are never
/// limited). Returns the outbox page.
#[auxmacros::bind("/proc/frame")]
fn frame(elapsed: ByondValue, budget: ByondValue) -> Result<ByondValue> {
    let elapsed = whole(&elapsed, "elapsed")?;
    let budget = whole(&budget, "budget")? as usize;
    list(run(elapsed, budget)?)
}

/// Pushes one record.
fn record(out: &mut Vec<f32>, kind: u32, a: f32, b: f32, payload: &[f32]) {
    #[allow(clippy::cast_precision_loss)]
    out.extend_from_slice(&[kind as f32, a, b, payload.len() as f32]);
    out.extend_from_slice(payload);
}

/// The frame itself, callable without DM (tests).
pub(crate) fn run(elapsed: u32, budget: usize) -> Result<Vec<f32>> {
    let (seconds, now, force) = CLOCK.with_borrow_mut(|c| {
        c.now = c.now.saturating_add(Tick::from(elapsed));
        c.frames += 1;
        let seconds = (f64::from(elapsed) * c.tick_seconds).min(MAX_PACE_SECONDS);
        (seconds, c.now, std::mem::take(&mut c.force_step))
    });
    let mut out: Vec<f32> = Vec::new();
    let mut timer = PhaseTimer::start();

    // 1-2. The world (the pipe devices are a law of it) and the hosts not yet on it.
    let mut devices = Vec::new();
    if elapsed > 0 || force {
        devices = world::pace(seconds, force)?;
    }
    timer.lap("pace");
    entity::tick_hosts();
    timer.lap("hosts");

    // 3. The scheduler: every watch port's wakes, timers, rates, keys.
    let (wakes, owners) = sched::step(now, budget)?;
    timer.lap("sched");

    // Set-watch crossings, and the retiring of settled heat bodies (read off
    // the events, so before they are taken).
    let crossings = heat::take_crossings(&owners)?;
    timer.lap("crossings");

    // 3. Typed events -> notices.
    let events = world::take_events()?;
    timer.lap("events");
    let mut at = 0;
    while at + 3 <= events.len() {
        #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
        let len = events[at + 2] as usize;
        let end = (at + 3 + len).min(events.len());
        record(
            &mut out,
            REC_NOTICE,
            events[at + 1],
            events[at],
            &events[at + 3..end],
        );
        at = end;
    }

    // What the pipe devices' law did this frame (one report per device that moved gas or drew power).
    #[allow(clippy::cast_precision_loss)]
    for r in devices.chunks_exact(4) {
        record(
            &mut out,
            REC_NOTICE,
            r[0],
            NOTICE_PIPE_DEVICE as f32,
            &[r[1], r[2], r[3]],
        );
    }

    // Wakes: a plain channel change is CHANGED, everything else CROSSED.
    for w in wakes {
        #[allow(clippy::cast_precision_loss)]
        if w.reason & !sched::REASON_DETAIL == 0 {
            record(
                &mut out,
                REC_CHANGED,
                w.subscriber as f32,
                w.reason as f32,
                &[f32::from(w.lane), w.source],
            );
        } else {
            record(
                &mut out,
                REC_CROSSED,
                w.subscriber as f32,
                (w.reason & !sched::REASON_DETAIL) as f32,
                &[f32::from(w.lane), w.reason as f32, w.source, w.kind],
            );
        }
    }
    #[allow(clippy::cast_precision_loss)]
    for (sub, payload, entered, generation) in crossings {
        record(
            &mut out,
            REC_CROSSED,
            sub as f32,
            payload as f32,
            &[f32::from(u8::from(entered)), generation as f32],
        );
    }
    timer.lap("outbox");
    timer.finish();
    Ok(out)
}

/// Cumulative wall time of each frame phase (`frame.us.<phase>` counters in the metrics registry, read by
/// `verdigris_metrics_list()` and every bench mark), so a change in the frame's cost names the phase that moved.
struct PhaseTimer {
    at: std::time::Instant,
    /// Wall time of the top-level phases so far this frame, microseconds.
    total_us: u64,
    /// The thread's CPU time when the frame began, microseconds (see [`thread_cpu_us`]).
    cpu_start_us: u64,
    /// What the machine was doing when the frame began (see [`os_reading`]).
    os_start: OsReading,
}

/// What the machine and this process had done up to now: the evidence that tells a frame that waited for the CPU from one that waited for memory or
/// the disk, or that nothing ran at all. Read at most every OS_READING_PERIOD at a frame start and at the end of a slow one; zeros off Windows.
#[derive(Clone, Copy, Default, PartialEq, Debug)]
struct OsReading {
    /// CPU time of every thread of this process, microseconds.
    process_cpu_us: u64,
    /// CPU time all the machine's cores spent not idle, microseconds (summed over cores).
    machine_busy_us: u64,
    /// CPU time all the machine's cores had in total, microseconds (cores times wall time).
    machine_total_us: u64,
    /// Page faults this process took (soft and hard).
    page_faults: u64,
    /// Read, write and other I/O operations this process issued.
    io_ops: u64,
}

impl OsReading {
    /// The change from `start` to `self`.
    fn since(self, start: Self) -> Self {
        Self {
            process_cpu_us: self.process_cpu_us.saturating_sub(start.process_cpu_us),
            machine_busy_us: self.machine_busy_us.saturating_sub(start.machine_busy_us),
            machine_total_us: self.machine_total_us.saturating_sub(start.machine_total_us),
            page_faults: self.page_faults.saturating_sub(start.page_faults),
            io_ops: self.io_ops.saturating_sub(start.io_ops),
        }
    }
}

/// The process's scheduling priority class (Windows `GetPriorityClass` value, 0 elsewhere): 0x40 idle, 0x4000 below normal, 0x20 normal,
/// 0x8000 above normal, 0x80 high. Read when a slow frame is filed, so a stall is read against the priority the server had at the time.
#[cfg(windows)]
fn priority_class() -> u64 {
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn GetCurrentProcess() -> isize;
        fn GetPriorityClass(process: isize) -> u32;
    }
    // SAFETY: both calls take and return plain values for the calling process's pseudo-handle.
    u64::from(unsafe { GetPriorityClass(GetCurrentProcess()) })
}

#[cfg(not(windows))]
fn priority_class() -> u64 {
    0
}

/// [`OsReading`] now (Windows `GetProcessTimes`, `GetSystemTimes`, `K32GetProcessMemoryInfo`, `GetProcessIoCounters`; zeros elsewhere or when a call fails).
#[cfg(windows)]
fn os_reading() -> OsReading {
    #[repr(C)]
    struct MemoryCounters {
        cb: u32,
        page_fault_count: u32,
        sizes: [usize; 8],
    }
    #[repr(C)]
    #[derive(Default)]
    struct IoCounters {
        read_ops: u64,
        write_ops: u64,
        other_ops: u64,
        read_bytes: u64,
        write_bytes: u64,
        other_bytes: u64,
    }
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn GetCurrentProcess() -> isize;
        fn GetProcessTimes(process: isize, created: *mut u64, exited: *mut u64, kernel: *mut u64, user: *mut u64) -> i32;
        fn GetSystemTimes(idle: *mut u64, kernel: *mut u64, user: *mut u64) -> i32;
        fn K32GetProcessMemoryInfo(process: isize, counters: *mut MemoryCounters, cb: u32) -> i32;
        fn GetProcessIoCounters(process: isize, counters: *mut IoCounters) -> i32;
    }
    let mut reading = OsReading::default();
    // SAFETY: each call writes only the out-parameters passed (FILETIME pairs as u64, the two C structs above sized as the API expects) and reads the
    // calling process's pseudo-handle.
    unsafe {
        let process = GetCurrentProcess();
        let (mut created, mut exited, mut kernel, mut user) = (0u64, 0u64, 0u64, 0u64);
        if GetProcessTimes(process, &mut created, &mut exited, &mut kernel, &mut user) != 0 {
            reading.process_cpu_us = (kernel + user) / 10;
        }
        let (mut idle, mut machine_kernel, mut machine_user) = (0u64, 0u64, 0u64);
        if GetSystemTimes(&mut idle, &mut machine_kernel, &mut machine_user) != 0 {
            // The kernel time includes the idle time.
            reading.machine_total_us = (machine_kernel + machine_user) / 10;
            reading.machine_busy_us = (machine_kernel + machine_user).saturating_sub(idle) / 10;
        }
        let mut memory = MemoryCounters { cb: 0, page_fault_count: 0, sizes: [0; 8] };
        #[allow(clippy::cast_possible_truncation)]
        let cb = std::mem::size_of::<MemoryCounters>() as u32;
        memory.cb = cb;
        if K32GetProcessMemoryInfo(process, &mut memory, cb) != 0 {
            reading.page_faults = u64::from(memory.page_fault_count);
        }
        let mut io = IoCounters::default();
        if GetProcessIoCounters(process, &mut io) != 0 {
            reading.io_ops = io.read_ops + io.write_ops + io.other_ops;
        }
    }
    reading
}

#[cfg(not(windows))]
fn os_reading() -> OsReading {
    OsReading::default()
}

/// CPU time this thread has used, microseconds (Windows `GetThreadTimes`; 0 elsewhere). A slow frame whose wall time far exceeds the CPU time it used
/// was not computing: it was descheduled or blocked, not slow work.
#[cfg(windows)]
fn thread_cpu_us() -> u64 {
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn GetCurrentThread() -> isize;
        fn GetThreadTimes(thread: isize, created: *mut u64, exited: *mut u64, kernel: *mut u64, user: *mut u64) -> i32;
    }
    let (mut created, mut exited, mut kernel, mut user) = (0u64, 0u64, 0u64, 0u64);
    // SAFETY: GetThreadTimes writes four FILETIMEs (two 32-bit halves, little endian: one u64 each) for the calling thread's pseudo-handle.
    let ok = unsafe { GetThreadTimes(GetCurrentThread(), &mut created, &mut exited, &mut kernel, &mut user) };
    if ok == 0 {
        return 0;
    }
    (kernel + user) / 10 // 100 ns units
}

#[cfg(not(windows))]
fn thread_cpu_us() -> u64 {
    0
}

/// A frame at least this long (microseconds) adds its own per-phase times to the `frame.slow_us.<phase>` counters, so the
/// slow frame is named by its phase and not hidden in the cumulative `frame.us.*` totals of the quick ones.
const SLOW_FRAME_US: u64 = 20_000;

/// How old the reading a slow frame's OS evidence is measured from may be. `os_reading()` on every frame was itself the idle stall: 40 times a second on the
/// main thread, it held 7.3 s of the 7.7 s of slow frames in a run with the machine saturated, nearly all off the CPU, so the machine shares in a slow frame's
/// report now cover up to this long around it.
const OS_READING_PERIOD: std::time::Duration = std::time::Duration::from_secs(10);

thread_local! {
    /// The last [`OsReading`] taken and when.
    static OS_LAST: std::cell::Cell<Option<(std::time::Instant, OsReading)>> = const { std::cell::Cell::new(None) };
}

/// The latest [`OsReading`], taken again only when it is older than [`OS_READING_PERIOD`].
fn os_reading_recent(now: std::time::Instant) -> OsReading {
    if let Some((at, reading)) = OS_LAST.get() {
        if now.duration_since(at) < OS_READING_PERIOD {
            return reading;
        }
    }
    let reading = os_reading();
    OS_LAST.set(Some((now, reading)));
    reading
}

thread_local! {
    /// Every lap of the frame in progress (the nested `pace_*` ones too): `(phase, microseconds)`.
    static TRACE: std::cell::RefCell<Vec<(String, u64)>> = const { std::cell::RefCell::new(Vec::new()) };
}

/// Adds one lap to the cumulative counter and to the trace of the frame in progress.
pub(crate) fn trace_lap(phase: &str, us: u64) {
    crate::metrics::registry().counter(&format!("frame.us.{phase}")).add(us);
    // The worst single lap of each phase (`frame.max_us.*`): a spike every few seconds hides in the cumulative counters.
    let worst = crate::metrics::registry().gauge(&format!("frame.max_us.{phase}"));
    #[allow(clippy::cast_precision_loss)]
    if us as f64 > worst.get() {
        worst.set(us as f64);
    }
    TRACE.with_borrow_mut(|t| t.push((phase.to_owned(), us)));
}

impl PhaseTimer {
    fn start() -> Self {
        crate::metrics::registry().counter("frame.count").inc();
        TRACE.with_borrow_mut(Vec::clear);
        let at = std::time::Instant::now();
        let mut timer = Self { at, total_us: 0, cpu_start_us: thread_cpu_us(), os_start: os_reading_recent(at) };
        // These readings are syscalls and can block: their time is a phase of its own, not charged to whatever runs first.
        timer.lap("open");
        timer
    }

    fn lap(&mut self, phase: &str) {
        let now = std::time::Instant::now();
        #[allow(clippy::cast_possible_truncation)]
        let us = (now - self.at).as_micros() as u64;
        trace_lap(phase, us);
        self.total_us += us;
        self.at = now;
    }

    /// Ends the frame: a slow one files its trace under `frame.slow_us.*` in the process registry.
    fn finish(&self) {
        let cpu_us = thread_cpu_us().saturating_sub(self.cpu_start_us);
        // The machine is read only for a frame that turned out slow (the start reading is the cheap half).
        let os = if self.total_us < SLOW_FRAME_US {
            OsReading::default()
        } else {
            let reading = os_reading();
            OS_LAST.set(Some((std::time::Instant::now(), reading)));
            reading.since(self.os_start)
        };
        self.file_slow(crate::metrics::registry(), cpu_us, os);
    }

    /// Files this frame into `registry` when it was slow: its per-phase times, and its wall time split into `cpu_us` on the CPU and the rest off it. The
    /// clock readings come in as arguments, so a test fixes them instead of timing real work.
    fn file_slow(&self, registry: &MetricsRegistry, cpu_us: u64, os: OsReading) {
        if self.total_us < SLOW_FRAME_US {
            return;
        }
        registry.counter("frame.slow_count").inc();
        registry.counter("frame.slow_us.total").add(self.total_us);
        // On the CPU against off it: a frame that waited (descheduled, blocked) shows its wall time here and little CPU time.
        registry.counter("frame.slow_us.on_cpu").add(cpu_us.min(self.total_us));
        registry.counter("frame.slow_us.off_cpu").add(self.total_us.saturating_sub(cpu_us));
        // Why it was off the CPU: the machine's busy share (`os_machine_busy` of `os_machine_capacity`) says whether the cores were all taken, the process's own
        // CPU (`os_process_cpu`, every thread) whether anything of the server ran, and the counts whether it was paging or waiting on I/O.
        registry.counter("frame.slow_us.os_process_cpu").add(os.process_cpu_us);
        registry.counter("frame.slow_us.os_machine_busy").add(os.machine_busy_us);
        registry.counter("frame.slow_us.os_machine_capacity").add(os.machine_total_us);
        registry.counter("frame.slow_n.page_faults").add(os.page_faults);
        registry.counter("frame.slow_n.io_ops").add(os.io_ops);
        #[allow(clippy::cast_precision_loss)]
        registry.gauge("frame.priority_class").set(priority_class() as f64);
        TRACE.with_borrow(|t| {
            for (phase, us) in t {
                registry.counter(&format!("frame.slow_us.{phase}")).add(*us);
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::gas::mix::{self, MixRef};
    use crate::world::with_world;
    use vg_core::component::Component;
    use vg_core::outbox::Lane;
    use vg_core::registry::world_kind_domain;
    use vg_core::watch::{Cmp, Cond, Edge, SetEntry};
    use vg_gas::cell::gas_ch;
    use vg_gas::gas::Mixture;
    use vg_heat::HeatBody;

    /// Splits an outbox page into `(kind, a, b, payload)` records.
    fn records(page: &[f32]) -> Vec<(u32, f32, f32, Vec<f32>)> {
        let mut out = Vec::new();
        let mut at = 0;
        while at + 4 <= page.len() {
            let n = page[at + 3] as usize;
            out.push((
                page[at] as u32,
                page[at + 1],
                page[at + 2],
                page[at + 4..at + 4 + n].to_vec(),
            ));
            at += 4 + n;
        }
        assert_eq!(at, page.len(), "the page is whole records: {page:?}");
        out
    }

    /// A slow frame files its wall time split into the CPU it used and the time it did not run: the two always add up to the frame. Fixed durations and a
    /// private registry: nothing here depends on how loaded the machine is or on what another test files.
    #[test]
    fn a_slow_frame_splits_its_wall_time_into_on_and_off_cpu() {
        let registry = MetricsRegistry::new();
        let mut timer = PhaseTimer::start();
        timer.total_us = SLOW_FRAME_US + 5_000;
        timer.file_slow(&registry, 1_500, OsReading::default());
        assert_eq!(registry.counter("frame.slow_us.total").get(), SLOW_FRAME_US + 5_000, "the slow frame was filed");
        assert_eq!(registry.counter("frame.slow_us.on_cpu").get(), 1_500, "the CPU it used");
        assert_eq!(registry.counter("frame.slow_us.off_cpu").get(), SLOW_FRAME_US + 3_500, "the rest it spent off the CPU");
        assert_eq!(registry.counter("frame.slow_count").get(), 1);
    }

    /// CPU time cannot exceed the wall time it was used in: a reading past it is capped, and the frame still adds up.
    #[test]
    fn a_cpu_reading_past_the_frame_is_capped() {
        let registry = MetricsRegistry::new();
        let mut timer = PhaseTimer::start();
        timer.total_us = SLOW_FRAME_US;
        timer.file_slow(&registry, SLOW_FRAME_US * 3, OsReading::default());
        assert_eq!(registry.counter("frame.slow_us.on_cpu").get(), SLOW_FRAME_US);
        assert_eq!(registry.counter("frame.slow_us.off_cpu").get(), 0);
    }

    /// A slow frame also files what the machine did meanwhile, so a stall is read as CPU contention, paging or I/O: the deltas of the two readings.
    #[test]
    fn a_slow_frame_files_what_the_machine_did_meanwhile() {
        let registry = MetricsRegistry::new();
        let mut timer = PhaseTimer::start();
        timer.total_us = SLOW_FRAME_US;
        let start = OsReading { process_cpu_us: 100, machine_busy_us: 1_000, machine_total_us: 2_000, page_faults: 10, io_ops: 5 };
        let end = OsReading { process_cpu_us: 400, machine_busy_us: 31_000, machine_total_us: 62_000, page_faults: 110, io_ops: 25 };
        timer.file_slow(&registry, 0, end.since(start));
        assert_eq!(registry.counter("frame.slow_us.os_process_cpu").get(), 300, "the process's CPU over the frame");
        assert_eq!(registry.counter("frame.slow_us.os_machine_busy").get(), 30_000, "the machine's busy time");
        assert_eq!(registry.counter("frame.slow_us.os_machine_capacity").get(), 60_000, "the machine's total time");
        assert_eq!(registry.counter("frame.slow_n.page_faults").get(), 100, "page faults taken");
        assert_eq!(registry.counter("frame.slow_n.io_ops").get(), 20, "I/O operations issued");
    }

    /// The Windows readings are live, which also proves the structs handed to the API are the size it expects: a process that has run, touched memory and
    /// has a priority class reads non-zero.
    #[cfg(windows)]
    #[test]
    fn the_os_reading_is_live() {
        let ballast: Vec<u8> = (0..4_000_000).map(|i| (i % 251) as u8).collect();
        assert!(ballast.iter().map(|b| u64::from(*b)).sum::<u64>() > 0);
        let reading = os_reading();
        assert!(reading.process_cpu_us > 0, "this process has used CPU: {reading:?}");
        assert!(reading.machine_total_us > 0, "the machine has had CPU time: {reading:?}");
        assert!(reading.page_faults > 0, "this process has faulted pages in: {reading:?}");
        assert!(reading.machine_busy_us <= reading.machine_total_us, "busy time is part of the total: {reading:?}");
        assert!(priority_class() != 0, "the process has a priority class");
    }

    /// A reading that went backwards (a counter reset) is a zero change, not a huge one.
    #[test]
    fn a_reading_that_went_backwards_is_no_change() {
        let earlier = OsReading { page_faults: 50, ..OsReading::default() };
        assert_eq!(OsReading::default().since(earlier), OsReading::default());
    }

    /// A frame under the slow line files nothing, however the clock read.
    #[test]
    fn a_quick_frame_files_no_slow_time() {
        let registry = MetricsRegistry::new();
        let mut timer = PhaseTimer::start();
        timer.total_us = SLOW_FRAME_US - 1;
        timer.file_slow(&registry, 0, OsReading::default());
        assert_eq!(registry.counter("frame.slow_us.total").get(), 0);
        assert_eq!(registry.counter("frame.slow_count").get(), 0);
    }

    #[test]
    fn an_idle_frame_reports_nothing() {
        with_world(|_| Ok(())).unwrap();
        assert!(records(&run(0, 100).unwrap()).is_empty());
    }

    #[test]
    fn a_gas_change_watch_leaves_as_a_changed_record() {
        with_world(|_| Ok(())).unwrap();
        let mut tank = Mixture::from_vol(70.0);
        tank.set_moles(0, 10.0);
        tank.set_temperature(293.15);
        let r = MixRef::Main(mix::alloc(tank.clone()).unwrap());
        let cond = Cond::Changed {
            cell: r.id(),
            mask: gas_ch::PRESSURE.bit(),
        };
        let code = crate::sched::GAS_HANDLES;
        let (port, id) = crate::registry::with_domain(world_kind_domain(code), |d| {
            d.watch(7, Lane::Urgent, &cond)
        })
        .unwrap()
        .unwrap();
        with_world(|w| {
            w.sched_watch(7, code, port, id)
                .map_err(|e| eyre::eyre!("{e}"))
        })
        .unwrap();
        assert!(
            records(&run(0, 100).unwrap()).is_empty(),
            "nothing changed yet"
        );
        let mut after = tank.clone();
        after.set_moles(0, 20.0);
        mix::store(r, &tank, &after);
        let page = records(&run(0, 100).unwrap());
        let changed: Vec<_> = page
            .iter()
            .filter(|r| r.0 == REC_CHANGED && r.1 == 7.0)
            .collect();
        assert_eq!(changed.len(), 1, "{page:?}");
        assert_ne!(
            changed[0].2 as u32 & gas_ch::PRESSURE.bit(),
            0,
            "the key is the channel mask"
        );
    }

    #[test]
    fn a_heat_set_crossing_leaves_as_a_crossed_record() {
        let code = vg_core::world::kind_code(HeatBody::DOMAIN_ID, HeatBody::KIND);
        let body = with_world(|w| {
            w.bind_value(
                None,
                HeatBody {
                    capacity: 1_000.0,
                    energy: 1_000.0 * 300.0,
                    keep: true,
                    ..Default::default()
                },
            )
            .map_err(|e| eyre::eyre!("{e}"))
        })
        .unwrap();
        let chans =
            crate::registry::with_domain(world_kind_domain(code), |d| d.channels()).unwrap();
        let ch = vg_core::channel::ChannelId(
            chans.iter().position(|c| c.name == "temperature").unwrap() as u8,
        );
        let (port, id) = crate::registry::with_domain(world_kind_domain(code), |d| {
            d.watch(
                9,
                Lane::Normal,
                &Cond::ThresholdSet {
                    cell: crate::entity::entity_value(body) as u32,
                    ch,
                },
            )
        })
        .unwrap()
        .unwrap();
        with_world(|w| {
            w.sched_watch(9, code, port, id)
                .map_err(|e| eyre::eyre!("{e}"))
        })
        .unwrap();
        crate::registry::with_domain(world_kind_domain(code), |d| {
            d.add_entry(
                port,
                id,
                SetEntry {
                    payload: 3,
                    generation: 1,
                    cmp: Cmp::Above,
                    limit: vg_core::channel::Quantity::new(320.0, vg_core::channel::Unit::Kelvin),
                    hysteresis: None,
                    edge: Edge::Enter,
                },
            )
        })
        .unwrap()
        .unwrap();
        with_world(|w| {
            w.step_blocking();
            Ok(())
        })
        .unwrap();
        let _ = run(0, 100).unwrap();
        with_world(|w| {
            let mut b = w.read::<HeatBody>(body).unwrap();
            b.relax = false;
            b.energy = 1_000.0 * 330.0;
            w.put(body, b).unwrap();
            crate::heat::wake_body_couplings(w, body.index());
            w.step_blocking();
            Ok(())
        })
        .unwrap();
        let page = records(&run(0, 100).unwrap());
        let crossed: Vec<_> = page
            .iter()
            .filter(|r| {
                r.0 == REC_CROSSED && r.1 == 9.0 && r.3.len() == CROSSED_SET_DETAIL as usize
            })
            .collect();
        assert_eq!(crossed.len(), 1, "{page:?}");
        assert_eq!(crossed[0].2, 3.0, "the band is the entry's payload");
        assert_eq!(crossed[0].3, vec![1.0, 1.0], "entered, generation");
    }
}
