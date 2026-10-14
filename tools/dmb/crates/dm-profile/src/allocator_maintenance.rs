//! Return unused allocator pages after a quiescent ownership release.
//!
//! The compiler uses mimalloc in both ordinary and counted executables. Dropping
//! Rust owners does not guarantee their abandoned worker pages leave process
//! private memory. Collection never discards live Rust objects or their receipts.

/// Aggressively reclaim unused pages in the calling mimalloc thread heap and
/// purge eligible arenas. Call only at explicit idle ownership transitions.
/// This can be expensive; its elapsed time must be reported by the caller.
/// It is not a process-wide live-heap scan or a bound on private memory.
pub fn reclaim_unused_allocator_pages() {
    // SAFETY: mi_collect takes no borrowed pointer or externally owned heap.
    // Both executable allocators use the same pinned libmimalloc-sys instance.
    // Mimalloc synchronizes arena purges and never frees live allocations.
    unsafe { libmimalloc_sys::mi_collect(true) };
}

/// Bytes mimalloc currently has committed from the OS (its own accounting, not
/// the process private-bytes counter). Comparing it with private bytes and with
/// live requested bytes separates freed-but-committed pages from non-allocator
/// memory (thread stacks, mapped files, native libraries). Diagnostic only.
pub fn allocator_commit_bytes() -> Option<u64> {
    let (mut elapsed, mut user, mut system) = (0usize, 0usize, 0usize);
    let (mut rss, mut peak_rss, mut commit, mut peak_commit, mut faults) =
        (0usize, 0usize, 0usize, 0usize, 0usize);
    // SAFETY: every out-pointer refers to a live local usize for the call.
    unsafe {
        libmimalloc_sys::mi_process_info(
            &mut elapsed,
            &mut user,
            &mut system,
            &mut rss,
            &mut peak_rss,
            &mut commit,
            &mut peak_commit,
            &mut faults,
        );
    }
    Some(commit as u64)
}

extern "C" fn stats_line(message: *const std::os::raw::c_char, _argument: *mut std::os::raw::c_void) {
    if message.is_null() {
        return;
    }
    // SAFETY: mimalloc passes a NUL-terminated string valid for this call.
    let text = unsafe { std::ffi::CStr::from_ptr(message) }.to_string_lossy();
    eprint!("mimalloc-stats {text}");
}

/// Print mimalloc's process statistics (per size class, pages, segments/arenas)
/// to stderr. Diagnostic; the daemon calls it only when
/// DMB_DAEMON_ALLOCATOR_STATS is set.
pub fn print_allocator_stats() {
    // SAFETY: the callback only reads its message argument; no user pointer.
    unsafe { libmimalloc_sys::mi_stats_print_out(Some(stats_line), std::ptr::null_mut()) };
}
