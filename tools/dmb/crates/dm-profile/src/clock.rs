//! CPU clocks never substitute wall time when a platform query fails.
use serde::Serialize;
use std::time::{Duration, Instant};

#[derive(Clone, Debug, Serialize)]
pub struct Calibration {
    pub method: &'static str,
    pub cycles_per_cpu_second: Option<f64>,
    pub calibration_wall_s: f64,
    pub calibration_cpu_s: Option<f64>,
    pub note: &'static str,
}
pub fn calibrate() -> Calibration {
    let start = Instant::now();
    if cfg!(windows) {
        let cycles = thread_raw();
        let cpu = thread_coarse_ns();
        let mut value = 1u64;
        while start.elapsed() < Duration::from_millis(250) {
            value = std::hint::black_box(value.wrapping_mul(6364136223846793005).wrapping_add(1));
        }
        std::hint::black_box(value);
        let elapsed_cpu = thread_coarse_ns()
            .zip(cpu)
            .map(|(end, begin)| end.saturating_sub(begin));
        let elapsed_cycles = thread_raw()
            .zip(cycles)
            .map(|(end, begin)| end.saturating_sub(begin));
        let rate = elapsed_cycles.zip(elapsed_cpu).and_then(|(cycles, ns)| {
            (ns > 0 && cycles > 0).then_some(cycles as f64 * 1e9 / ns as f64)
        });
        Calibration { method: "QueryThreadCycleTime", cycles_per_cpu_second: rate, calibration_wall_s: start.elapsed().as_secs_f64(), calibration_cpu_s: elapsed_cpu.map(|ns| ns as f64 / 1e9), note: "Single startup-thread calibration against coarse GetThreadTimes; frequency/core variation is possible. Process CPU crosscheck must be inspected." }
    } else {
        Calibration {
            method: "CLOCK_THREAD_CPUTIME_ID",
            cycles_per_cpu_second: None,
            calibration_wall_s: start.elapsed().as_secs_f64(),
            calibration_cpu_s: None,
            note: "Native nanosecond CPU clock on Linux; unsupported platforms report missing CPU.",
        }
    }
}
pub fn thread_ns(calibration: &Calibration) -> Option<u64> {
    let raw = thread_raw()?;
    if cfg!(windows) {
        calibration
            .cycles_per_cpu_second
            .map(|rate| (raw as f64 * 1e9 / rate) as u64)
    } else {
        Some(raw)
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
