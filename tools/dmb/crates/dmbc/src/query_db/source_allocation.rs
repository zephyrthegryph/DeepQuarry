//! Allocation-only prerequisite: NOT yet used by original Answers storage.
//! Exact allocator Layout charges, no semantic cache or global allocator hook.
//! Runtime mode is intentionally uncapped; the limit is source-introduced work.
//! Source callers must use fallible try_reserve BEFORE insertion. Infallible
//! map clone/insert must never be a source endpoint allocation path. Allocator
//! clone tests use ample capacity solely to verify mode inheritance/reset.
//! Fixed allocator-state/ledger Arc metadata is not in payload Layout counters;
//! the integration layer must admit/census that metadata separately.
use allocator_api2::alloc::{AllocError, Allocator, Global};
use std::{
    alloc::Layout,
    ptr::NonNull,
    sync::{
        atomic::{AtomicBool, AtomicUsize, Ordering},
        Arc,
    },
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct Denied {
    pub requested: usize,
    pub live: usize,
    pub limit: usize,
}
#[derive(Debug)]
pub(super) struct SourceLedger {
    limit: usize,
    live: AtomicUsize,
    peak: AtomicUsize,
    reserves: AtomicUsize,
}
impl SourceLedger {
    pub(super) fn new(limit: usize) -> Arc<Self> {
        Arc::new(Self {
            limit,
            live: AtomicUsize::new(0),
            peak: AtomicUsize::new(0),
            reserves: AtomicUsize::new(0),
        })
    }
    pub(super) fn reserve(self: &Arc<Self>, bytes: usize) -> Result<SourceLease, Denied> {
        let mut live = self.live.load(Ordering::Acquire);
        loop {
            let Some(next) = live.checked_add(bytes).filter(|next| *next <= self.limit) else {
                return Err(Denied {
                    requested: bytes,
                    live,
                    limit: self.limit,
                });
            };
            match self
                .live
                .compare_exchange_weak(live, next, Ordering::AcqRel, Ordering::Acquire)
            {
                Ok(_) => {
                    self.peak.fetch_max(next, Ordering::Relaxed);
                    self.reserves.fetch_add(1, Ordering::Relaxed);
                    return Ok(SourceLease {
                        ledger: Arc::clone(self),
                        bytes,
                    });
                }
                Err(actual) => live = actual,
            }
        }
    }
    pub(super) fn snapshot(&self) -> LedgerSnapshot {
        LedgerSnapshot {
            live: self.live.load(Ordering::Acquire),
            peak: self.peak.load(Ordering::Relaxed),
            reserves: self.reserves.load(Ordering::Relaxed),
        }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct LedgerSnapshot {
    pub live: usize,
    pub peak: usize,
    pub reserves: usize,
}
/// Inline lease: reserving does not allocate a second per-allocation Arc.
/// It must outlive the allocation it admits, including any retained Weak owner.
pub(super) struct SourceLease {
    ledger: Arc<SourceLedger>,
    bytes: usize,
}
impl Drop for SourceLease {
    fn drop(&mut self) {
        let before = self.ledger.live.fetch_sub(self.bytes, Ordering::AcqRel);
        debug_assert!(before >= self.bytes);
    }
}
struct State {
    ledger: Arc<SourceLedger>,
    source: AtomicBool,
    denied: AtomicBool,
    live_layout_bytes: AtomicUsize,
    live_allocations: AtomicUsize,
}
/// A map-local allocator. Clone deliberately SHARES mode, including internal
/// hashbrown clones. The operation guard clears mode for all clones afterward.
/// A caller must hold its ORIGINAL container mutex through source_mode/use/drop.
/// Independently concurrent containers must have separate allocator states.
/// No original Answers container is migrated by this prerequisite.
pub(super) struct SourceAllocator<A: Allocator + Clone = Global> {
    backend: A,
    state: Arc<State>,
}
impl<A: Allocator + Clone> Clone for SourceAllocator<A> {
    fn clone(&self) -> Self {
        Self {
            backend: self.backend.clone(),
            state: Arc::clone(&self.state),
        }
    }
}
impl SourceAllocator<Global> {
    pub(super) fn new(ledger: Arc<SourceLedger>) -> Self {
        Self::with_backend(ledger, Global)
    }
}
impl<A: Allocator + Clone> SourceAllocator<A> {
    fn with_backend(ledger: Arc<SourceLedger>, backend: A) -> Self {
        Self {
            backend,
            state: Arc::new(State {
                ledger,
                source: AtomicBool::new(false),
                denied: AtomicBool::new(false),
                live_layout_bytes: AtomicUsize::new(0),
                live_allocations: AtomicUsize::new(0),
            }),
        }
    }
    pub(super) fn source_mode(&self) -> Result<SourceMode<'_>, ModeBusy> {
        self.state
            .source
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .map_err(|_| ModeBusy)?;
        self.state.denied.store(false, Ordering::Release);
        Ok(SourceMode { state: &self.state })
    }
    /// Actual backend Layout totals (including private headers/padding), not RSS
    /// or a deduplicated allocation-address census. Fixed counters never retain
    /// source values, pointers, maps or per-allocation registry entries.
    pub(super) fn allocation_snapshot(&self) -> AllocationSnapshot {
        AllocationSnapshot {
            bytes: self.state.live_layout_bytes.load(Ordering::Acquire),
            allocations: self.state.live_allocations.load(Ordering::Acquire),
        }
    }
    fn fail(&self) -> AllocError {
        if self.state.source.load(Ordering::Acquire) {
            self.state.denied.store(true, Ordering::Release);
        }
        AllocError
    }
}
#[derive(Debug)]
pub(super) struct ModeBusy;
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct AllocationSnapshot {
    pub bytes: usize,
    pub allocations: usize,
}
pub(super) struct SourceMode<'a> {
    state: &'a State,
}
impl SourceMode<'_> {
    pub(super) fn denied(&self) -> bool {
        self.state.denied.load(Ordering::Acquire)
    }
}
impl Drop for SourceMode<'_> {
    fn drop(&mut self) {
        self.state.source.store(false, Ordering::Release);
    }
}

struct Header {
    layout: Layout,
    state: Arc<State>,
    charge: Option<SourceLease>,
}
fn composed_layout(payload: Layout) -> Result<(Layout, usize), AllocError> {
    // The pointer just BEFORE returned data supports ANY fitting deallocation
    // layout, retaining the exact underlying composed Layout. It may live in padding.
    let (prefix, _) = Layout::new::<Header>()
        .extend(Layout::new::<NonNull<Header>>())
        .map_err(|_| AllocError)?;
    let (whole, offset) = prefix.extend(payload).map_err(|_| AllocError)?;
    Ok((whole.pad_to_align(), offset))
}
// SAFETY: every returned pointer is aligned for the requested Layout; private
// header stores the actual backend Layout and issuing state. Clone shares the
// backend's allocation domain. Deallocation never trusts a fitting layout to
// reconstruct offsets. Default grow/shrink allocate-copy-deallocate through
// these same methods, preserving overlap charges and original failure semantics.
unsafe impl<A: Allocator + Clone> Allocator for SourceAllocator<A> {
    fn allocate(&self, payload: Layout) -> Result<NonNull<[u8]>, AllocError> {
        let (whole, offset) = composed_layout(payload).map_err(|_| self.fail())?;
        let source = self.state.source.load(Ordering::Acquire);
        if source && self.state.denied.load(Ordering::Acquire) {
            return Err(AllocError);
        }
        let charge = if source {
            Some(
                self.state
                    .ledger
                    .reserve(whole.size())
                    .map_err(|_| self.fail())?,
            )
        } else {
            None
        };
        // Charge is already held before the underlying allocator sees Layout.
        // A failed backend allocation drops it without publishing any owner.
        let block = self.backend.allocate(whole).map_err(|_| self.fail())?;
        let base = block.cast::<u8>();
        // SAFETY: whole starts with aligned Header, followed by a back-pointer
        // slot and aligned payload; even zero-sized payload has a valid slot.
        let data = unsafe {
            let header = base.cast::<Header>();
            header.as_ptr().write(Header {
                layout: whole,
                state: Arc::clone(&self.state),
                charge,
            });
            let data = NonNull::new_unchecked(base.as_ptr().add(offset));
            let slot = data
                .as_ptr()
                .sub(std::mem::size_of::<NonNull<Header>>())
                .cast::<NonNull<Header>>();
            slot.write_unaligned(header);
            data
        };
        self.state
            .live_layout_bytes
            .fetch_add(whole.size(), Ordering::AcqRel);
        self.state.live_allocations.fetch_add(1, Ordering::AcqRel);
        Ok(NonNull::slice_from_raw_parts(data, payload.size()))
    }
    unsafe fn deallocate(&self, data: NonNull<u8>, _fitting_layout: Layout) {
        // SAFETY: the Allocator contract requires an exact previously returned
        // pointer. The back-pointer is within that allocated block and stores
        // the original header pointer regardless of fitting size/alignment.
        let slot = unsafe {
            data.as_ptr()
                .sub(std::mem::size_of::<NonNull<Header>>())
                .cast::<NonNull<Header>>()
        };
        let header = unsafe { slot.read_unaligned() };
        let Header {
            layout,
            state,
            charge,
        } = unsafe { header.as_ptr().read() };
        // Keep header-owned state+charge locally alive THROUGH the actual free.
        unsafe {
            self.backend.deallocate(header.cast(), layout);
        }
        state
            .live_layout_bytes
            .fetch_sub(layout.size(), Ordering::AcqRel);
        state.live_allocations.fetch_sub(1, Ordering::AcqRel);
        drop(charge);
        drop(state);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::hash_map::RandomState;
    #[derive(Default)]
    struct BackendCounters {
        allocs: AtomicUsize,
        frees: AtomicUsize,
        fail: AtomicBool,
        source_frees: AtomicUsize,
    }
    #[derive(Clone)]
    struct Backend {
        counters: Arc<BackendCounters>,
        ledger: Arc<SourceLedger>,
        require_charge_at_free: bool,
    }
    unsafe impl Allocator for Backend {
        fn allocate(&self, layout: Layout) -> Result<NonNull<[u8]>, AllocError> {
            self.counters.allocs.fetch_add(1, Ordering::Relaxed);
            if self.counters.fail.load(Ordering::Relaxed) {
                return Err(AllocError);
            }
            Global.allocate(layout)
        }
        unsafe fn deallocate(&self, ptr: NonNull<u8>, layout: Layout) {
            if self.require_charge_at_free {
                assert!(
                    self.ledger.snapshot().live >= layout.size(),
                    "charge released before actual free"
                );
                self.counters.source_frees.fetch_add(1, Ordering::Relaxed);
            }
            unsafe {
                Global.deallocate(ptr, layout);
            }
            self.counters.frees.fetch_add(1, Ordering::Relaxed);
        }
    }
    fn backend(
        ledger: &Arc<SourceLedger>,
        require_charge_at_free: bool,
    ) -> (SourceAllocator<Backend>, Arc<BackendCounters>) {
        let counters = Arc::new(BackendCounters::default());
        (
            SourceAllocator::with_backend(
                Arc::clone(ledger),
                Backend {
                    counters: Arc::clone(&counters),
                    ledger: Arc::clone(ledger),
                    require_charge_at_free,
                },
            ),
            counters,
        )
    }
    #[test]
    fn actual_header_layout_alignment_zero_and_fitting_deallocation() {
        let ledger = SourceLedger::new(1 << 20);
        let (alloc, calls) = backend(&ledger, true);
        let _mode = alloc.source_mode().unwrap();
        for (size, align) in [(0, 1), (0, 256), (3, 128), (4097, 4096)] {
            let layout = Layout::from_size_align(size, align).unwrap();
            let (whole, _) = composed_layout(layout).unwrap();
            let block = alloc.allocate(layout).unwrap();
            assert_eq!((block.as_ptr() as *mut u8 as usize) % align, 0);
            assert_eq!(ledger.snapshot().live, whole.size());
            assert_eq!(
                alloc.allocation_snapshot(),
                AllocationSnapshot {
                    bytes: whole.size(),
                    allocations: 1
                }
            );
            // Exact-size returned blocks accept this original layout; preserve the
            // requested alignment even for a zero-sized payload.
            unsafe {
                alloc.deallocate(block.cast(), layout);
            }
            assert_eq!(ledger.snapshot().live, 0);
            assert_eq!(alloc.allocation_snapshot().bytes, 0);
        }
        assert_eq!(calls.source_frees.load(Ordering::Relaxed), 4);
    }
    #[test]
    fn denial_overflow_and_backend_failure_happen_before_publication() {
        let ledger = SourceLedger::new(64);
        let (alloc, calls) = backend(&ledger, false);
        {
            let mode = alloc.source_mode().unwrap();
            assert!(alloc.allocate(Layout::new::<[u8; 128]>()).is_err());
            assert!(mode.denied());
            assert_eq!(calls.allocs.load(Ordering::Relaxed), 0);
            assert_eq!(ledger.snapshot().live, 0);
        }
        let big = SourceLedger::new(usize::MAX);
        let (alloc, calls) = backend(&big, false);
        {
            let mode = alloc.source_mode().unwrap();
            let impossible = Layout::from_size_align(isize::MAX as usize, 1).unwrap();
            assert!(alloc.allocate(impossible).is_err());
            assert!(mode.denied());
            assert_eq!(calls.allocs.load(Ordering::Relaxed), 0);
            assert_eq!(big.snapshot().live, 0);
        }
        calls.fail.store(true, Ordering::Relaxed);
        {
            let mode = alloc.source_mode().unwrap();
            assert!(alloc.allocate(Layout::new::<u8>()).is_err());
            assert!(mode.denied());
            assert_eq!(big.snapshot().live, 0);
        }
    }
    #[test]
    fn real_grow_keeps_old_and_new_charged_until_backend_frees_old() {
        let ledger = SourceLedger::new(1 << 20);
        let (alloc, calls) = backend(&ledger, true);
        let _mode = alloc.source_mode().unwrap();
        let old = Layout::from_size_align(8, 8).unwrap();
        let new = Layout::from_size_align(1024, 64).unwrap();
        let block = alloc.allocate(old).unwrap();
        unsafe {
            block.cast::<u8>().as_ptr().write(91);
        }
        let grown = unsafe { alloc.grow(block.cast(), old, new).unwrap() };
        assert_eq!(unsafe { grown.cast::<u8>().as_ptr().read() }, 91);
        let old_bytes = composed_layout(old).unwrap().0.size();
        let new_bytes = composed_layout(new).unwrap().0.size();
        assert_eq!(ledger.snapshot().peak, old_bytes + new_bytes);
        assert_eq!(ledger.snapshot().live, new_bytes);
        assert_eq!(calls.frees.load(Ordering::Relaxed), 1);
        unsafe {
            alloc.deallocate(grown.cast(), new);
        }
        assert_eq!(ledger.snapshot().live, 0);
    }
    #[test]
    fn failed_growth_preserves_original_allocation_and_charge() {
        let layout = Layout::new::<[u8; 16]>();
        let bytes = composed_layout(layout).unwrap().0.size();
        let ledger = SourceLedger::new(bytes);
        let (alloc, calls) = backend(&ledger, true);
        let mode = alloc.source_mode().unwrap();
        let block = alloc.allocate(layout).unwrap();
        unsafe {
            block.cast::<u8>().as_ptr().write(45);
        }
        assert!(unsafe { alloc.grow(block.cast(), layout, Layout::new::<[u8; 32]>()) }.is_err());
        assert!(mode.denied());
        assert_eq!(calls.allocs.load(Ordering::Relaxed), 1);
        assert_eq!(ledger.snapshot().live, bytes);
        assert_eq!(unsafe { block.cast::<u8>().as_ptr().read() }, 45);
        unsafe {
            alloc.deallocate(block.cast(), layout);
        }
        assert_eq!(ledger.snapshot().live, 0);
    }
    #[test]
    fn actual_hashbrown_reserve_rehash_clear_and_drop_use_same_mode() {
        let ledger = SourceLedger::new(1 << 20);
        let alloc = SourceAllocator::new(Arc::clone(&ledger));
        let scope_alloc = alloc.clone();
        let mut map = hashbrown::HashMap::with_hasher_in(RandomState::new(), alloc);
        {
            let mode = scope_alloc.source_mode().unwrap();
            assert!(
                map.allocator().source_mode().is_err(),
                "same owner cannot have nested modes"
            );
            map.try_reserve(8).unwrap();
            for i in 0..8 {
                map.insert(i, i);
            }
            let old = ledger.snapshot().live;
            map.try_reserve(128).unwrap();
            let live = ledger.snapshot().live;
            assert!(
                ledger.snapshot().peak >= old + live,
                "rehash overlap must be admitted"
            );
            assert!(!mode.denied());
            map.clear();
            assert_eq!(ledger.snapshot().live, live, "clear retains raw backing");
            assert!(live >= map.allocation_size());
        }
        drop(map);
        assert_eq!(ledger.snapshot().live, 0);
        // A clone retained beyond the guard is runtime mode, not stuck source.
        let layout = Layout::new::<[u8; 8]>();
        let block = scope_alloc.allocate(layout).unwrap();
        assert_eq!(ledger.snapshot().live, 0);
        unsafe {
            scope_alloc.deallocate(block.cast(), layout);
        }
    }
    #[test]
    fn actual_original_history_vec_growth_retains_charge_until_drop() {
        let ledger = SourceLedger::new(1 << 20);
        let alloc = SourceAllocator::new(Arc::clone(&ledger));
        let handle = alloc.clone();
        let _mode = handle.source_mode().unwrap();
        let mut stamps = allocator_api2::vec::Vec::new_in(alloc);
        for i in 0..128u128 {
            stamps.try_reserve(1).unwrap();
            stamps.push((i, i));
        }
        let live = ledger.snapshot().live;
        assert!(
            ledger.snapshot().peak > live,
            "Vec grow must retain old while admitting new"
        );
        stamps.clear();
        assert_eq!(ledger.snapshot().live, live);
        drop(stamps);
        assert_eq!(ledger.snapshot().live, 0);
    }
    #[test]
    fn runtime_is_uncapped_and_new_source_operation_recovers_after_denial() {
        let ledger = SourceLedger::new(1024);
        let alloc = SourceAllocator::new(Arc::clone(&ledger));
        let layout = Layout::new::<[u8; 4096]>();
        let runtime = alloc.allocate(layout).unwrap();
        assert_eq!(ledger.snapshot().live, 0);
        {
            let mode = alloc.source_mode().unwrap();
            assert!(alloc.allocate(layout).is_err());
            assert!(
                alloc.allocate(Layout::new::<u8>()).is_err(),
                "denial is sticky for this operation"
            );
            assert!(mode.denied());
        }
        {
            let mode = alloc.source_mode().unwrap();
            let small = alloc.allocate(Layout::new::<u8>()).unwrap();
            assert!(!mode.denied());
            unsafe {
                alloc.deallocate(small.cast(), Layout::new::<u8>());
            }
        }
        unsafe {
            alloc.deallocate(runtime.cast(), layout);
        }
        assert_eq!(ledger.snapshot().live, 0);
        assert_eq!(alloc.allocation_snapshot().allocations, 0);
    }
    #[test]
    fn actual_container_clone_inherits_source_mode_then_runtime_clone_is_unrestricted() {
        let ledger = SourceLedger::new(1 << 20);
        let alloc = SourceAllocator::new(Arc::clone(&ledger));
        let handle = alloc.clone();
        let mut map = hashbrown::HashMap::with_hasher_in(RandomState::new(), alloc);
        let source_copy;
        let original_bytes;
        {
            let mode = handle.source_mode().unwrap();
            map.try_reserve(16).unwrap();
            for n in 0..16 {
                map.insert(n, n);
            }
            original_bytes = ledger.snapshot().live;
            // RawTable::clone calls allocator.clone internally. Its allocations
            // must inherit active source mode, not silently become runtime.
            source_copy = map.clone();
            assert!(ledger.snapshot().live > original_bytes);
            assert!(!mode.denied());
        }
        let charged = ledger.snapshot().live;
        // The same internal clone path AFTER the guard must be runtime mode.
        let runtime_copy = map.clone();
        assert_eq!(ledger.snapshot().live, charged);
        drop(source_copy);
        assert_eq!(ledger.snapshot().live, original_bytes);
        drop(map);
        assert_eq!(ledger.snapshot().live, 0);
        assert!(
            handle.allocation_snapshot().bytes > 0,
            "runtime copy still owns actual backing"
        );
        drop(runtime_copy);
        assert_eq!(handle.allocation_snapshot().allocations, 0);
    }
    #[test]
    fn actual_default_shrink_preserves_payload_and_overlap_until_actual_free() {
        let ledger = SourceLedger::new(1 << 20);
        let (alloc, calls) = backend(&ledger, true);
        let _mode = alloc.source_mode().unwrap();
        let old = Layout::from_size_align(1024, 256).unwrap();
        let small = Layout::from_size_align(1, 128).unwrap();
        let block = alloc.allocate(old).unwrap();
        unsafe {
            block.cast::<u8>().as_ptr().write(106);
        }
        let smaller = unsafe { alloc.shrink(block.cast(), old, small).unwrap() };
        assert_eq!(unsafe { smaller.cast::<u8>().as_ptr().read() }, 106);
        assert_eq!(
            ledger.snapshot().peak,
            composed_layout(old).unwrap().0.size() + composed_layout(small).unwrap().0.size()
        );
        assert_eq!(
            ledger.snapshot().live,
            composed_layout(small).unwrap().0.size()
        );
        assert_eq!(calls.frees.load(Ordering::Relaxed), 1);
        unsafe {
            alloc.deallocate(smaller.cast(), small);
        }
        assert_eq!(ledger.snapshot().live, 0);
    }
}
