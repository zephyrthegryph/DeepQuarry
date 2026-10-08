//! CPU clocks never substitute wall time when a platform query fails.
use serde::Serialize;

#[derive(Clone, Debug, Serialize)]
pub struct Calibration {
    pub method: &'static str,
    pub cycles_per_cpu_second: Option<f64>,
    pub calibration_wall_s: f64,
    pub calibration_cpu_s: Option<f64>,
    pub note: &'static str,
}
// At least ~32 coarse Windows CPU ticks: wall time is not evidence that
// a contended calibration thread received enough CPU to estimate a rate.
const MIN_CALIBRATION_CPU_NS: u64 = 500_000_000;
const COARSE_TICK_NS: f64 = 15_625_000.0;

#[derive(Clone, Debug, Serialize)]
pub struct ThreadCalibration {
    pub thread: String,
    pub cycles_per_cpu_second: Option<f64>,
    pub observed_cpu_s: Option<f64>,
    pub checked_subintervals: usize,
    pub max_relative_rate_deviation: Option<f64>,
    pub max_relative_quantization_uncertainty: Option<f64>,
    pub envelope_relative_quantization_uncertainty: Option<f64>,
    pub status: &'static str,
}
#[derive(Default)]
pub(crate) struct ThreadEnvelope {
    first: Option<(u64, u64)>,
    last: Option<(u64, u64)>,
    window: Option<(u64, u64)>,
    intervals: Vec<(u64, u64)>,
    failed: bool,
}
impl ThreadEnvelope {
    pub fn observe(&mut self, raw: Option<u64>, coarse: Option<u64>) {
        let Some(sample) = raw.zip(coarse) else {
            self.failed = true;
            return;
        };
        if self
            .last
            .is_some_and(|last| sample.0 < last.0 || sample.1 < last.1)
        {
            self.failed = true;
            return;
        }
        self.first.get_or_insert(sample);
        let begin = *self.window.get_or_insert(sample);
        if sample.1 - begin.1 >= MIN_CALIBRATION_CPU_NS {
            self.intervals
                .push((sample.0 - begin.0, sample.1 - begin.1));
            self.window = Some(sample);
        }
        self.last = Some(sample);
    }
    pub fn finish(&self, thread: String, windows: bool) -> ThreadCalibration {
        let total = self
            .first
            .zip(self.last)
            .and_then(|(a, b)| Some((b.0.checked_sub(a.0)?, b.1.checked_sub(a.1)?)));
        let mut result = ThreadCalibration {
            thread,
            cycles_per_cpu_second: None,
            observed_cpu_s: total.map(|(_, ns)| ns as f64 / 1e9),
            checked_subintervals: self.intervals.len(),
            max_relative_rate_deviation: None,
            max_relative_quantization_uncertainty: None,
            envelope_relative_quantization_uncertainty: None,
            status: "insufficient_cpu",
        };
        if self.failed {
            result.status = "clock_failed_or_backwards";
            return result;
        }
        if !windows {
            result.status = "native_nanoseconds";
            return result;
        }
        let Some((cycles, ns)) = total else {
            return result;
        };
        let Some(rate) = calibration_rate(Some(cycles), Some(ns)) else {
            return result;
        };
        result.envelope_relative_quantization_uncertainty = Some(2.0 * COARSE_TICK_NS / ns as f64);
        if self.intervals.len() < 2 {
            result.status = "insufficient_stability_windows";
            return result;
        }
        let mut unstable = false;
        let mut max_drift: f64 = 0.0;
        let mut max_uncertainty: f64 = 0.0;
        for &(window_cycles, window_ns) in &self.intervals {
            let Some(window_rate) = calibration_rate(Some(window_cycles), Some(window_ns)) else {
                result.status = "invalid_subinterval";
                return result;
            };
            let drift = (window_rate / rate - 1.0).abs();
            // Two coarse boundary ticks for each interval's duration, propagated
            // through the subinterval/envelope rate ratio. Conservative, explicit.
            let window_error = 2.0 * COARSE_TICK_NS / window_ns as f64;
            let total_error = 2.0 * COARSE_TICK_NS / ns as f64;
            let uncertainty = (1.0 + window_error) / (1.0 - total_error) - 1.0;
            max_drift = max_drift.max(drift);
            max_uncertainty = max_uncertainty.max(uncertainty);
            unstable |= drift > 0.05 + uncertainty;
        }
        result.max_relative_rate_deviation = Some(max_drift);
        result.max_relative_quantization_uncertainty = Some(max_uncertainty);
        if unstable {
            result.status = "unstable_rate";
            return result;
        }
        result.cycles_per_cpu_second = Some(rate);
        result.status = "valid_observed_envelope";
        result
    }
}

pub(crate) fn convert(
    raw: u64,
    calibration: Option<&ThreadCalibration>,
    windows: bool,
) -> Option<f64> {
    let calibration = calibration?;
    if windows {
        calibration
            .cycles_per_cpu_second
            .map(|rate| raw as f64 / rate)
    } else {
        (calibration.status == "native_nanoseconds").then_some(raw as f64 / 1e9)
    }
}

fn calibration_rate(cycles: Option<u64>, cpu_ns: Option<u64>) -> Option<f64> {
    let (cycles, ns) = cycles.zip(cpu_ns)?;
    if ns < MIN_CALIBRATION_CPU_NS || cycles == 0 {
        return None;
    }
    let rate = cycles as f64 * 1e9 / ns as f64;
    (rate.is_finite() && rate > 0.0).then_some(rate)
}

pub fn calibrate() -> Calibration {
    Calibration {
        method: if cfg!(windows) { "QueryThreadCycleTime" } else { "CLOCK_THREAD_CPUTIME_ID" },
        cycles_per_cpu_second: None,
        calibration_wall_s: 0.0,
        calibration_cpu_s: None,
        note: "Windows rates are derived per thread from naturally observed paired cycle/GetThreadTimes envelopes at finish; no startup rate, busy loop, global fallback or process-total scaling. See thread_calibrations for validity and uncertainty. Linux retains native thread CPU nanoseconds.",
    }
}
#[derive(Clone, Copy, Default)]
pub struct Process {
    pub cpu_ns: Option<u64>,
    pub read_bytes: Option<u64>,
    pub write_bytes: Option<u64>,
    pub peak_private_bytes: Option<u64>,
}
#[cfg(windows)]
mod platform {
    use super::Process;
    type Handle = *mut std::ffi::c_void;
    #[repr(C)]
    #[derive(Default)]
    struct FileTime {
        low: u32,
        high: u32,
    }
    impl FileTime {
        fn ns(&self) -> u64 {
            ((u64::from(self.high) << 32) | u64::from(self.low)).saturating_mul(100)
        }
    }
    #[repr(C)]
    #[derive(Default)]
    struct Io {
        read_ops: u64,
        write_ops: u64,
        other_ops: u64,
        read: u64,
        write: u64,
        other: u64,
    }
    #[repr(C)]
    #[derive(Default)]
    struct Memory {
        cb: u32,
        faults: u32,
        peak_working: usize,
        working: usize,
        quota_peak_paged: usize,
        quota_paged: usize,
        quota_peak_nonpaged: usize,
        quota_nonpaged: usize,
        pagefile: usize,
        peak_pagefile: usize,
        private: usize,
    }
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn GetCurrentThread() -> Handle;
        fn GetCurrentProcess() -> Handle;
        fn QueryThreadCycleTime(thread: Handle, cycles: *mut u64) -> i32;
        fn GetThreadTimes(
            thread: Handle,
            creation: *mut FileTime,
            exit: *mut FileTime,
            kernel: *mut FileTime,
            user: *mut FileTime,
        ) -> i32;
        fn GetProcessTimes(
            process: Handle,
            creation: *mut FileTime,
            exit: *mut FileTime,
            kernel: *mut FileTime,
            user: *mut FileTime,
        ) -> i32;
        fn GetProcessIoCounters(process: Handle, io: *mut Io) -> i32;
    }
    #[link(name = "psapi")]
    unsafe extern "system" {
        fn GetProcessMemoryInfo(process: Handle, memory: *mut Memory, cb: u32) -> i32;
    }
    pub fn thread_raw() -> Option<u64> {
        let mut cycles = 0;
        (unsafe { QueryThreadCycleTime(GetCurrentThread(), &mut cycles) } != 0).then_some(cycles)
    }
    pub fn thread_coarse_ns() -> Option<u64> {
        let (mut a, mut b, mut c, mut d) = (
            FileTime::default(),
            FileTime::default(),
            FileTime::default(),
            FileTime::default(),
        );
        (unsafe { GetThreadTimes(GetCurrentThread(), &mut a, &mut b, &mut c, &mut d) } != 0)
            .then(|| c.ns() + d.ns())
    }
    pub fn process() -> Process {
        let (mut a, mut b, mut c, mut d) = (
            FileTime::default(),
            FileTime::default(),
            FileTime::default(),
            FileTime::default(),
        );
        let cpu_ns =
            (unsafe { GetProcessTimes(GetCurrentProcess(), &mut a, &mut b, &mut c, &mut d) } != 0)
                .then(|| c.ns() + d.ns());
        let mut io = Io::default();
        let io_ok = unsafe { GetProcessIoCounters(GetCurrentProcess(), &mut io) } != 0;
        let mut memory = Memory {
            cb: std::mem::size_of::<Memory>() as u32,
            ..Memory::default()
        };
        let cb = memory.cb;
        let memory_ok = unsafe { GetProcessMemoryInfo(GetCurrentProcess(), &mut memory, cb) } != 0;
        Process {
            cpu_ns,
            read_bytes: io_ok.then_some(io.read),
            write_bytes: io_ok.then_some(io.write),
            peak_private_bytes: memory_ok.then_some(memory.peak_pagefile as u64),
        }
    }
    pub fn current_private_bytes() -> Option<u64> {
        let mut memory = Memory {
            cb: std::mem::size_of::<Memory>() as u32,
            ..Memory::default()
        };
        let cb = memory.cb;
        // A current-process pseudo handle needs no elevation. The initialized
        // PROCESS_MEMORY_COUNTERS_EX buffer remains valid for the entire call.
        (unsafe { GetProcessMemoryInfo(GetCurrentProcess(), &mut memory, cb) } != 0)
            .then_some(memory.private as u64)
    }
}
#[cfg(windows)]
pub(crate) fn current_private_bytes() -> Option<u64> {
    platform::current_private_bytes()
}
#[cfg(target_os = "linux")]
mod platform {
    use super::Process;
    #[repr(C)]
    struct Timespec {
        seconds: i64,
        nanos: i64,
    }
    unsafe extern "C" {
        fn clock_gettime(clock: i32, time: *mut Timespec) -> i32;
    }
    fn cpu(clock: i32) -> Option<u64> {
        let mut time = Timespec {
            seconds: 0,
            nanos: 0,
        };
        (unsafe { clock_gettime(clock, &mut time) } == 0)
            .then(|| (time.seconds as u64).saturating_mul(1_000_000_000) + time.nanos as u64)
    }
    pub fn thread_raw() -> Option<u64> {
        cpu(3)
    }
    pub fn thread_coarse_ns() -> Option<u64> {
        cpu(3)
    }
    pub fn process() -> Process {
        let io = std::fs::read_to_string("/proc/self/io").unwrap_or_default();
        let field = |name: &str| {
            io.lines()
                .find_map(|line| line.strip_prefix(name)?.trim().parse::<u64>().ok())
        };
        Process {
            cpu_ns: cpu(2),
            read_bytes: field("read_bytes:"),
            write_bytes: field("write_bytes:"),
            peak_private_bytes: None,
        }
    }
}
#[cfg(not(any(windows, target_os = "linux")))]
mod platform {
    use super::Process;
    pub fn thread_raw() -> Option<u64> {
        None
    }
    pub fn thread_coarse_ns() -> Option<u64> {
        None
    }
    pub fn process() -> Process {
        Process::default()
    }
}
pub use platform::{process, thread_coarse_ns, thread_raw};

#[cfg(test)]
mod calibration_tests {
    use super::*;

    #[test]
    fn naturally_observed_threads_keep_independent_rates() {
        let mut fast = ThreadEnvelope::default();
        let mut slow = ThreadEnvelope::default();
        for cpu in [0, 500_000_000, 1_000_000_000] {
            fast.observe(Some(cpu * 4), Some(cpu));
            slow.observe(Some(cpu * 2), Some(cpu));
        }
        let fast = fast.finish("fast".into(), true);
        let slow = slow.finish("slow".into(), true);
        assert_eq!(fast.cycles_per_cpu_second, Some(4_000_000_000.0));
        assert_eq!(slow.cycles_per_cpu_second, Some(2_000_000_000.0));
        assert_eq!(convert(4_000_000_000, Some(&fast), true), Some(1.0));
        assert_eq!(convert(4_000_000_000, Some(&slow), true), Some(2.0));
        assert_eq!(convert(4_000_000_000, None, true), None);
    }

    #[test]
    fn drift_insufficient_windows_and_failures_never_use_a_fallback_rate() {
        let mut envelope = ThreadEnvelope::default();
        envelope.observe(Some(0), Some(0));
        envelope.observe(Some(2_000_000_000), Some(500_000_000));
        assert_eq!(
            envelope.finish("worker".into(), true).status,
            "insufficient_stability_windows"
        );
        envelope.observe(Some(3_000_000_000), Some(1_000_000_000));
        let drifted = envelope.finish("worker".into(), true);
        assert_eq!(drifted.status, "unstable_rate");
        assert_eq!(convert(1, Some(&drifted), true), None);
        envelope.observe(None, Some(1_100_000_000));
        assert_eq!(
            envelope.finish("worker".into(), true).status,
            "clock_failed_or_backwards"
        );
        let mut backwards = ThreadEnvelope::default();
        backwards.observe(Some(10), Some(10));
        backwards.observe(Some(9), Some(20));
        assert_eq!(
            backwards.finish("worker".into(), true).status,
            "clock_failed_or_backwards"
        );
    }

    #[test]
    fn native_nanoseconds_require_no_cycle_rate_or_minimum_window() {
        let mut envelope = ThreadEnvelope::default();
        envelope.observe(Some(0), Some(0));
        envelope.observe(Some(10), Some(10));
        let native = envelope.finish("worker".into(), false);
        assert_eq!(convert(10, Some(&native), false), Some(10e-9));
    }

    #[test]
    fn contended_short_cpu_calibration_is_unavailable() {
        assert_eq!(calibration_rate(Some(50_000_000), Some(15_625_000)), None);
        assert_eq!(
            calibration_rate(Some(1), Some(MIN_CALIBRATION_CPU_NS - 1)),
            None
        );
        assert_eq!(calibration_rate(None, Some(MIN_CALIBRATION_CPU_NS)), None);
        assert_eq!(calibration_rate(Some(1), None), None);
        assert_eq!(
            calibration_rate(Some(0), Some(MIN_CALIBRATION_CPU_NS)),
            None
        );
    }

    #[test]
    fn sufficient_cpu_interval_yields_the_scripted_rate() {
        assert_eq!(
            calibration_rate(Some(1_500_000_000), Some(500_000_000)),
            Some(3_000_000_000.0)
        );
    }
}
