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
