//! Host limits belong outside the compiler's language and artifact layers.
//! Windows Job Objects enforce the process memory ceiling before parsing.

use std::io;

pub mod file_stamp;
pub mod journal;
pub mod tool_path;
pub use tool_path::legacy_tool_path;

/// Windows' main-thread stack is too small for normal compiler expression trees.
/// Use a fixed worker reservation while the process memory budget remains enforced.
pub fn run_on_compiler_thread<T: Send + 'static>(
    operation: impl FnOnce() -> Result<T, String> + Send + 'static,
) -> Result<T, String> {
    std::thread::Builder::new()
        .name("dm-compiler".into())
        .stack_size(16 * 1024 * 1024)
        .spawn(operation)
        .map_err(|error| error.to_string())?
        .join()
        .map_err(|_| "compiler worker panicked".to_owned())?
}

/// Keep this guard alive for the lifetime of the tool. `DM_MEMORY_LIMIT_MB=0`
/// explicitly disables the default 2 GiB Windows process memory ceiling.
pub fn install_process_budget() -> io::Result<ProcessBudget> {
    let mb = std::env::var("DM_MEMORY_LIMIT_MB")
        .unwrap_or_else(|_| "2048".into())
        .parse::<usize>()
        .map_err(|_| {
            io::Error::new(
                io::ErrorKind::InvalidInput,
                "DM_MEMORY_LIMIT_MB must be a nonnegative integer",
            )
        })?;
    let bytes = mb.checked_mul(1024 * 1024).ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "DM_MEMORY_LIMIT_MB is too large",
        )
    })?;
    ProcessBudget::install(bytes)
}

#[cfg(not(windows))]
pub struct ProcessBudget;

#[cfg(not(windows))]
impl ProcessBudget {
    fn install(_bytes: usize) -> io::Result<Self> {
        Ok(Self)
    }
}

#[cfg(windows)]
pub use windows::ProcessBudget;

#[cfg(windows)]
mod windows {
    use super::io;
    use std::ffi::c_void;
    use std::ptr;

    type Handle = *mut c_void;
    const JOB_OBJECT_EXTENDED_LIMIT_INFORMATION: i32 = 9;
    const JOB_OBJECT_LIMIT_PROCESS_MEMORY: u32 = 0x100;

    #[repr(C)]
    #[derive(Default)]
    struct BasicLimit {
        process_user_time: i64,
        job_user_time: i64,
        flags: u32,
        min_working_set: usize,
        max_working_set: usize,
        active_processes: u32,
        affinity: usize,
        priority_class: u32,
        scheduling_class: u32,
    }

    #[repr(C)]
    #[derive(Default)]
    struct ExtendedLimit {
        basic: BasicLimit,
        io_counters: [u64; 6],
        process_memory: usize,
        job_memory: usize,
        peak_process_memory: usize,
        peak_job_memory: usize,
    }

    #[link(name = "kernel32")]
    extern "system" {
        fn CreateJobObjectW(attributes: *const c_void, name: *const u16) -> Handle;
        fn SetInformationJobObject(
            job: Handle,
            class: i32,
            information: *const c_void,
            size: u32,
        ) -> i32;
        fn AssignProcessToJobObject(job: Handle, process: Handle) -> i32;
        fn GetCurrentProcess() -> Handle;
        fn CloseHandle(handle: Handle) -> i32;
    }

    pub struct ProcessBudget {
        job: Handle,
    }

    impl ProcessBudget {
        pub(super) fn install(bytes: usize) -> io::Result<Self> {
            if bytes == 0 {
                return Ok(Self {
                    job: ptr::null_mut(),
                });
            }
            // SAFETY: null attributes/name request an unnamed job with default
            // security. The owned handle is closed by Drop on every error path.
            let job = unsafe { CreateJobObjectW(ptr::null(), ptr::null()) };
            if job.is_null() {
                return Err(io::Error::last_os_error());
            }
            let guard = Self { job };
            let limit = ExtendedLimit {
                basic: BasicLimit {
                    flags: JOB_OBJECT_LIMIT_PROCESS_MEMORY,
                    ..Default::default()
                },
                process_memory: bytes,
                ..Default::default()
            };
            // SAFETY: ExtendedLimit follows the documented Windows ABI. Its
            // pointer and exact size remain valid throughout this call.
            if unsafe {
                SetInformationJobObject(
                    job,
                    JOB_OBJECT_EXTENDED_LIMIT_INFORMATION,
                    &limit as *const _ as *const c_void,
                    std::mem::size_of::<ExtendedLimit>() as u32,
                )
            } == 0
            {
                return Err(io::Error::last_os_error());
            }
            // SAFETY: GetCurrentProcess returns the valid process pseudo-handle;
            // neither it nor the process itself is closed by this guard.
            if unsafe { AssignProcessToJobObject(job, GetCurrentProcess()) } == 0 {
                return Err(io::Error::last_os_error());
            }
            Ok(guard)
        }
    }

    impl Drop for ProcessBudget {
        fn drop(&mut self) {
            if !self.job.is_null() {
                // SAFETY: this guard uniquely owns the real job handle.
                unsafe {
                    CloseHandle(self.job);
                }
            }
        }
    }

    #[cfg(all(test, target_pointer_width = "64"))]
    mod tests {
        use super::*;

        #[test]
        fn windows_limit_structs_match_x64_abi() {
            assert_eq!(std::mem::size_of::<BasicLimit>(), 64);
            assert_eq!(std::mem::size_of::<ExtendedLimit>(), 144);
        }
    }
}

/// Host memory observations for compiler phase traces; never a query input.
#[derive(Clone,Copy,Debug)]
pub struct ProcessMemorySnapshot {pub private_bytes:usize,pub working_set_bytes:usize,pub peak_commit_bytes:usize}
#[cfg(not(windows))]
pub fn process_memory_snapshot()->Option<ProcessMemorySnapshot> {None}
#[cfg(windows)]
pub fn process_memory_snapshot()->Option<ProcessMemorySnapshot> {
    #[repr(C)]
    #[derive(Default)]
    struct Counters {cb:u32,faults:u32,peak_working_set:usize,working_set:usize,peak_paged:usize,paged:usize,
        peak_nonpaged:usize,nonpaged:usize,pagefile:usize,peak_pagefile:usize,private:usize}
    #[link(name="kernel32")]
    unsafe extern "system" {
        fn GetCurrentProcess()->*mut std::ffi::c_void;
        fn K32GetProcessMemoryInfo(process:*mut std::ffi::c_void,counters:*mut Counters,size:u32)->i32;
    }
    let mut counters=Counters::default();counters.cb=u32::try_from(std::mem::size_of::<Counters>()).ok()?;
    // The pseudo handle is read-only and the repr(C) buffer matches the Windows
    // PROCESS_MEMORY_COUNTERS_EX layout on the calling pointer width.
    let size=counters.cb;
    if unsafe {K32GetProcessMemoryInfo(GetCurrentProcess(),&mut counters,size)}==0 {return None;}
    Some(ProcessMemorySnapshot {private_bytes:counters.private,working_set_bytes:counters.working_set,peak_commit_bytes:counters.peak_pagefile})
}