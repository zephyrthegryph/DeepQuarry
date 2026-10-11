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
