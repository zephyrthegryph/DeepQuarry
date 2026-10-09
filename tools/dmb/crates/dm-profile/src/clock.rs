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
const COARSE_TICK_NANOS: u64 = 15_625_000;
const COARSE_TICK_NS: f64 = COARSE_TICK_NANOS as f64;
pub(crate) fn uncertainty_ns(windows: bool) -> u128 {
    if windows {
        u128::from(COARSE_TICK_NANOS) * 2
    } else {
        0
    }
}

#[derive(Clone, Copy, Debug, Serialize)]
pub struct CpuBounds {
    pub lower: f64,
    pub upper: f64,
}
impl CpuBounds {
    pub fn add(self, other: Self) -> Self {
        Self {
            lower: self.lower + other.lower,
            upper: self.upper + other.upper,
        }
    }
}
#[derive(Clone, Copy, Debug)]
pub(crate) struct CpuInterval {
    pub raw_begin: u64,
    pub raw_end: u64,
    pub coarse_begin: u64,
    pub coarse_end: u64,
}
impl CpuInterval {
    pub fn from_samples(
        begin: Option<u64>,
        end: Option<u64>,
        coarse_begin: Option<u64>,
        coarse_end: Option<u64>,
    ) -> Option<Self> {
        let value = Self {
            raw_begin: begin?,
            raw_end: end?,
            coarse_begin: coarse_begin?,
            coarse_end: coarse_end?,
        };
        (value.raw_end >= value.raw_begin && value.coarse_end >= value.coarse_begin)
            .then_some(value)
    }
    /// Integer counterpart for additive proofs; existing floating bounds are unchanged.
    pub(crate) fn bounds_ns(self, windows: bool) -> Option<(u128, u128)> {
        let raw = self.raw_end.checked_sub(self.raw_begin)?;
        let coarse = self.coarse_end.checked_sub(self.coarse_begin)?;
        let delta = u128::from(if windows { coarse } else { raw });
        let error = uncertainty_ns(windows);
        Some((delta.saturating_sub(error), delta.checked_add(error)?))
    }
    pub fn bounds(self, windows: bool) -> CpuBounds {
        if !windows {
            let value = (self.raw_end - self.raw_begin) as f64 / 1e9;
            return CpuBounds {
                lower: value,
                upper: value,
            };
        }
        let value = (self.coarse_end - self.coarse_begin) as f64 / 1e9;
        let error = 2.0 * COARSE_TICK_NS / 1e9;
        CpuBounds {
            lower: (value - error).max(0.0),
            upper: value + error,
        }
    }
}
#[derive(Clone, Debug, Serialize)]
pub struct CalibrationWindow {
    pub raw_begin: u64,
    pub raw_end: u64,
    pub coarse_cpu_s: f64,
    pub cycles_per_cpu_second: f64,
    pub relative_quantization_uncertainty: f64,
}
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
    pub windows: Vec<CalibrationWindow>,
}
/// Direct stage CPU clock; conversion is a unit change, never calibration.
pub(crate) fn convert_interval(interval: CpuInterval) -> Option<f64> {
    interval
        .raw_end
        .checked_sub(interval.raw_begin)
        .map(|ns| ns as f64 / 1e9)
}
pub fn calibrate() -> Calibration {
    Calibration {
        method: if cfg!(windows) { "GetThreadTimes" } else { "CLOCK_THREAD_CPUTIME_ID" },
        cycles_per_cpu_second: None, calibration_wall_s: 0.0, calibration_cpu_s: None,
        note: "Direct thread CPU nanoseconds sampled at stage boundaries; no cycle query, calibration, process scaling or per-item CPU sampling.",
    }
}
#[derive(Clone, Copy, Default)]
pub struct Process {
    pub cpu_ns: Option<u64>,
    pub read_bytes: Option<u64>,
    pub write_bytes: Option<u64>,
    pub peak_private_bytes: Option<u64>,
}
/// Stage boundaries query only I/O; session CPU/peak observations remain independent.
#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct ProcessIo {
    pub read_bytes: Option<u64>,
    pub write_bytes: Option<u64>,
}

#[cfg(windows)]
mod platform {
    use super::{Process, ProcessIo};
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
        let io = process_io();
        let mut memory = Memory {
            cb: std::mem::size_of::<Memory>() as u32,
            ..Memory::default()
        };
        let cb = memory.cb;
        let memory_ok = unsafe { GetProcessMemoryInfo(GetCurrentProcess(), &mut memory, cb) } != 0;
        Process {
            cpu_ns,
            read_bytes: io.read_bytes,
            write_bytes: io.write_bytes,
            peak_private_bytes: memory_ok.then_some(memory.peak_pagefile as u64),
        }
    }
    pub fn process_io() -> ProcessIo {
        let mut io = Io::default();
        let success = unsafe { GetProcessIoCounters(GetCurrentProcess(), &mut io) } != 0;
        ProcessIo {
            read_bytes: success.then_some(io.read),
            write_bytes: success.then_some(io.write),
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
    use super::{Process, ProcessIo};
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
    pub fn thread_coarse_ns() -> Option<u64> {
        cpu(3)
    }
    pub fn process_io() -> ProcessIo {
        let io = std::fs::read_to_string("/proc/self/io").unwrap_or_default();
        let field = |name: &str| {
            io.lines()
                .find_map(|line| line.strip_prefix(name)?.trim().parse::<u64>().ok())
        };
        ProcessIo {
            read_bytes: field("read_bytes:"),
            write_bytes: field("write_bytes:"),
        }
    }
    pub fn process() -> Process {
        let io = process_io();
        Process {
            cpu_ns: cpu(2),
            read_bytes: io.read_bytes,
            write_bytes: io.write_bytes,
            peak_private_bytes: None,
        }
    }
}
#[cfg(not(any(windows, target_os = "linux")))]
mod platform {
    use super::{Process, ProcessIo};
    pub fn thread_coarse_ns() -> Option<u64> {
        None
    }
    pub fn process_io() -> ProcessIo {
        ProcessIo::default()
    }
    pub fn process() -> Process {
        Process::default()
    }
}
pub(crate) use platform::process_io;
pub use platform::{process, thread_coarse_ns};

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn direct_stage_clock_preserves_missing_backward_and_quantization() {
        assert!(CpuInterval::from_samples(None, Some(20), None, Some(20)).is_none());
        assert!(CpuInterval::from_samples(Some(20), Some(10), Some(20), Some(10)).is_none());
        let interval =
            CpuInterval::from_samples(Some(100), Some(500_000_100), Some(100), Some(500_000_100))
                .unwrap();
        assert_eq!(convert_interval(interval), Some(0.5));
        assert_eq!(interval.bounds(true).lower, 0.46875);
        assert_eq!(interval.bounds(true).upper, 0.53125);
        assert_eq!(interval.bounds(false).lower, 0.5);
        assert_eq!(interval.bounds(false).upper, 0.5);
    }
}
