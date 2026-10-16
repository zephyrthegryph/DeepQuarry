//! Counting is enabled only by the executable installing this allocator.
use std::alloc::{GlobalAlloc, Layout};
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
impl CountingAllocator {
    /// Successful Rust global-allocator requested bytes still live at this instant.
    /// Valid only when this executable installs CountingAllocator. Native C
    /// allocations, allocator pages/metadata and OS private bytes are excluded.
    /// Sample before constructing diagnostic reports, ideally at quiescence.
    #[cfg(feature = "allocation-counting")]
    pub fn live_requested_bytes() -> u64 {
        LIVE.load(Ordering::Relaxed)
    }
}
// Diagnostic counting wraps the same allocator as the acceptance executable.
static BACKEND: mimalloc::MiMalloc = mimalloc::MiMalloc;
fn allocated(size: usize) {
    let live = LIVE
        .fetch_add(size as u64, Ordering::Relaxed)
        .saturating_add(size as u64);
    allocation_event(size, live);
}
fn allocation_event(size: usize, live: u64) {
    observe_peak(&PEAK, live);
    let _ = ALLOCATIONS.try_with(|value| value.set(value.get().saturating_add(1)));
    let _ = BYTES.try_with(|value| value.set(value.get().saturating_add(size as u64)));
    let _ = LOCAL_PEAK.try_with(|value| value.set(value.get().max(live)));
}
// Monotonic peak: a concurrent increase cannot invalidate fast rejection.
// fetch_max still resolves races between load and publication exactly.
fn observe_peak(peak: &AtomicU64, live: u64) {
    if live > peak.load(Ordering::Relaxed) {
        peak.fetch_max(live, Ordering::Relaxed);
    }
}
/// A successful realloc replaces one live allocation. Applying the size delta
/// in one atomic operation avoids exposing an artificial deallocated interval
/// to concurrent allocations and peak observations.
fn replace_live(counter: &AtomicU64, old_size: usize, new_size: usize) -> u64 {
    if new_size >= old_size {
        let growth = (new_size - old_size) as u64;
        counter
            .fetch_add(growth, Ordering::Relaxed)
            .saturating_add(growth)
    } else {
        let shrink = (old_size - new_size) as u64;
        counter
            .fetch_sub(shrink, Ordering::Relaxed)
            .saturating_sub(shrink)
    }
}
// Delegates allocation behavior to mimalloc; counters never allocate.
unsafe impl GlobalAlloc for CountingAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let pointer = unsafe { BACKEND.alloc(layout) };
        if !pointer.is_null() {
            allocated(layout.size());
            #[cfg(feature = "allocation-sites")]
            crate::allocation_sites::on_alloc(pointer, layout.size());
        }
        pointer
    }
    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        let pointer = unsafe { BACKEND.alloc_zeroed(layout) };
        if !pointer.is_null() {
            allocated(layout.size());
            #[cfg(feature = "allocation-sites")]
            crate::allocation_sites::on_alloc(pointer, layout.size());
        }
        pointer
    }
    unsafe fn dealloc(&self, pointer: *mut u8, layout: Layout) {
        LIVE.fetch_sub(layout.size() as u64, Ordering::Relaxed);
        #[cfg(feature = "allocation-sites")]
        crate::allocation_sites::on_free(pointer);
        unsafe { BACKEND.dealloc(pointer, layout) };
    }
    unsafe fn realloc(&self, pointer: *mut u8, layout: Layout, size: usize) -> *mut u8 {
        #[cfg(feature = "allocation-sites")]
        crate::allocation_sites::on_free(pointer);
        let result = unsafe { BACKEND.realloc(pointer, layout, size) };
        if !result.is_null() {
            let live = replace_live(&LIVE, layout.size(), size);
            allocation_event(size, live);
            #[cfg(feature = "allocation-sites")]
            crate::allocation_sites::on_alloc(result, size);
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{atomic::AtomicBool, Arc, Barrier};

    #[test]
    fn requested_live_realloc_tracks_growth_shrink_and_zero() {
        let live = AtomicU64::new(37);
        assert_eq!(replace_live(&live, 37, 103), 103);
        assert_eq!(replace_live(&live, 103, 11), 11);
        assert_eq!(replace_live(&live, 11, 0), 0);
        assert_eq!(live.load(Ordering::Relaxed), 0);
    }

    #[test]
    fn concurrent_peak_observations_preserve_maximum_and_never_regress() {
        let peak = AtomicU64::new(100);
        let barrier = Barrier::new(8);
        std::thread::scope(|scope| {
            for worker in 0..8 {
                let peak = &peak;
                let barrier = &barrier;
                scope.spawn(move || {
                    barrier.wait();
                    let mut previous = 0;
                    for index in 0..10_000 {
                        let value = 100 + worker * 10_000 + index;
                        observe_peak(peak, value);
                        observe_peak(peak, 1);
                        let current = peak.load(Ordering::Relaxed);
                        assert!(current >= value && current >= previous);
                        previous = current;
                    }
                });
            }
        });
        assert_eq!(peak.load(Ordering::Relaxed), 80_099);
    }

    #[test]
    fn concurrent_realloc_observers_never_see_an_artificial_freed_allocation() {
        let live = Arc::new(AtomicU64::new(100));
        let start = Arc::new(Barrier::new(2));
        let done = Arc::new(AtomicBool::new(false));
        let observer = {
            let live = Arc::clone(&live);
            let start = Arc::clone(&start);
            let done = Arc::clone(&done);
            std::thread::spawn(move || {
                start.wait();
                loop {
                    let observed = live.load(Ordering::Relaxed);
                    assert!(
                        observed == 100 || observed == 200,
                        "unexpected live bytes: {observed}"
                    );
                    if done.load(Ordering::Acquire) {
                        break;
                    }
                }
            })
        };
        start.wait();
        for _ in 0..10_000 {
            replace_live(&live, 100, 200);
            replace_live(&live, 200, 100);
        }
        done.store(true, Ordering::Release);
        observer.join().unwrap();
        assert_eq!(live.load(Ordering::Relaxed), 100);
    }
}
