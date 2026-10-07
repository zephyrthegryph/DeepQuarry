//! Counting is enabled only by the executable installing this allocator.
use std::alloc::{GlobalAlloc, Layout, System};
use std::cell::Cell;
use std::sync::atomic::{AtomicU64, Ordering};
static LIVE: AtomicU64 = AtomicU64::new(0);
static PEAK: AtomicU64 = AtomicU64::new(0);
thread_local! {
    static ALLOCATIONS: Cell<u64> = const {Cell::new(0)};
    static BYTES: Cell<u64> = const {Cell::new(0)};
    static LOCAL_PEAK: Cell<u64> = const {Cell::new(0)};
}
pub struct CountingAllocator;
fn allocated(size: usize) {
    let live = LIVE
        .fetch_add(size as u64, Ordering::Relaxed)
        .saturating_add(size as u64);
    PEAK.fetch_max(live, Ordering::Relaxed);
    let _ = ALLOCATIONS.try_with(|value| value.set(value.get().saturating_add(1)));
    let _ = BYTES.try_with(|value| value.set(value.get().saturating_add(size as u64)));
    let _ = LOCAL_PEAK.try_with(|value| value.set(value.get().max(live)));
}
// Delegates all allocation behavior unchanged to System; counters never allocate.
unsafe impl GlobalAlloc for CountingAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let pointer = unsafe { System.alloc(layout) };
        if !pointer.is_null() {
            allocated(layout.size());
        }
        pointer
    }
    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        let pointer = unsafe { System.alloc_zeroed(layout) };
        if !pointer.is_null() {
            allocated(layout.size());
        }
        pointer
    }
    unsafe fn dealloc(&self, pointer: *mut u8, layout: Layout) {
        LIVE.fetch_sub(layout.size() as u64, Ordering::Relaxed);
        unsafe { System.dealloc(pointer, layout) };
    }
    unsafe fn realloc(&self, pointer: *mut u8, layout: Layout, size: usize) -> *mut u8 {
        let result = unsafe { System.realloc(pointer, layout, size) };
        if !result.is_null() {
            LIVE.fetch_sub(layout.size() as u64, Ordering::Relaxed);
            allocated(size);
        }
        result
    }
}
pub(crate) fn snapshot() -> (u64, u64, u64) {
    (
        ALLOCATIONS.with(Cell::get),
        BYTES.with(Cell::get),
        LOCAL_PEAK.with(Cell::get),
    )
}
pub(crate) fn reset_peak() -> u64 {
    LOCAL_PEAK.with(|value| value.replace(LIVE.load(Ordering::Relaxed)))
}
pub(crate) fn restore_peak(previous: u64) -> u64 {
    LOCAL_PEAK.with(|value| {
        let peak = value.get();
        value.set(previous.max(peak));
        peak
    })
}
pub(crate) fn peak() -> u64 {
    PEAK.load(Ordering::Relaxed)
}
