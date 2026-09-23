//! The DLL's tracking allocator: live and peak Rust heap bytes, overall and
//! per [`AllocTag`] (`rust_core.md` §11).
//!
//! A thread-local tag scope ([`scope`]) attributes allocations to a domain.
//! So that a free is charged to the tag that allocated it (the freeing
//! thread may be in another scope), every block carries a small header just
//! before the pointer handed out, holding its tag. The header is
//! `max(align, 8)` bytes; counters report the requested sizes only.

use std::alloc::{GlobalAlloc, Layout, System};
use std::cell::Cell;
use std::sync::atomic::{AtomicU64, Ordering};

use vg_core::alloc::{AllocCounter, AllocTag, TagCounters};

pub struct TrackingAllocator;

static CURRENT_BYTES: AtomicU64 = AtomicU64::new(0);
static PEAK_BYTES: AtomicU64 = AtomicU64::new(0);
static TAGS: TagCounters = TagCounters::new();

thread_local! {
    // Const-initialised and drop-free, so reading it never allocates.
    static TAG: Cell<u8> = const { Cell::new(0) };
}

fn current_tag() -> u8 {
    TAG.try_with(Cell::get).unwrap_or(0)
}

fn tag_from(byte: u8) -> AllocTag {
    AllocTag::ALL
        .get(usize::from(byte))
        .copied()
        .unwrap_or(AllocTag::Untagged)
}

/// Restores the previous tag when dropped.
pub struct TagScope(u8);

impl Drop for TagScope {
    fn drop(&mut self) {
        let _ = TAG.try_with(|t| t.set(self.0));
    }
}

/// Attributes this thread's allocations to `tag` until the guard drops.
#[must_use]
pub fn scope(tag: AllocTag) -> TagScope {
    TagScope(TAG.try_with(|t| t.replace(tag as u8)).unwrap_or(0))
}

/// Runs `f` with this thread's allocations attributed to `tag`.
pub fn tagged<R>(tag: AllocTag, f: impl FnOnce() -> R) -> R {
    let _scope = scope(tag);
    f()
}

fn record_allocation(tag: u8, size: usize) {
    let current = CURRENT_BYTES.fetch_add(size as u64, Ordering::Relaxed) + size as u64;
    PEAK_BYTES.fetch_max(current, Ordering::Relaxed);
    TAGS.record_alloc(tag_from(tag), size);
}

fn record_deallocation(tag: u8, size: usize) {
    CURRENT_BYTES.fetch_sub(size as u64, Ordering::Relaxed);
    TAGS.record_free(tag_from(tag), size);
}

const fn header(align: usize) -> usize {
    if align > 8 { align } else { 8 }
}

/// The layout of the whole block (header + payload), or `None` on overflow.
fn outer(layout: Layout) -> Option<Layout> {
    let size = layout.size().checked_add(header(layout.align()))?;
    Layout::from_size_align(size, layout.align()).ok()
}

/// Writes the tag into the header and returns the user pointer.
///
/// # Safety
/// `base` must be a live allocation of at least `header(align) + <payload size>`
/// bytes (i.e. exactly what `outer(layout)` computed for this `align`), as
/// returned by `System.alloc`/`alloc_zeroed`. Then `base.add(header(align))` is
/// in bounds of that allocation and `user.sub(1)` is too (it lands inside the
/// header, never before `base`), so both the pointer arithmetic and the write
/// are sound.
unsafe fn finish(base: *mut u8, align: usize, tag: u8) -> *mut u8 {
    unsafe {
        let user = base.add(header(align));
        user.sub(1).write(tag);
        user
    }
}

// SAFETY: this impl upholds `GlobalAlloc`'s contract by construction:
// - `alloc`/`alloc_zeroed` grow the caller's `Layout` by a `header(align)`-byte
//   prefix (computed by `outer`, which returns `None` -- turned into a null
//   return, never UB -- on size overflow) and hand `System` that layout, so the
//   underlying allocation is always valid for the padded request.
// - The one-byte tag is stored at `user - 1`, which is inside that header, and
//   is never read/written by anyone outside `finish`/`dealloc`/`realloc`.
// - `dealloc`/`realloc` reconstruct the exact same padded `Layout` from the
//   `layout: Layout` the caller (which must itself uphold `GlobalAlloc`'s
//   contract: the same layout used for the matching `alloc`) passes back, so
//   `pointer.sub(hdr)` and the layout passed to `System` match what `System`
//   originally allocated -- required for `System.dealloc`/`realloc` to be sound,
//   and why `Layout::from_size_align_unchecked` here is safe: `layout` was
//   already validated when it was first constructed by the caller, and adding
//   the header can only overflow if `outer` would already have returned `None`
//   for the original `alloc`, in which case no such `pointer` exists to dealloc.
unsafe impl GlobalAlloc for TrackingAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let Some(block) = outer(layout) else {
            return std::ptr::null_mut();
        };
        // SAFETY: `block` is a valid, non-zero-sized `Layout` (padded from a
        // caller-supplied `Layout`, so its own invariants hold); this is
        // exactly `GlobalAlloc::alloc`'s contract, delegated to `System`.
        let base = unsafe { System.alloc(block) };
        if base.is_null() {
            return base;
        }
        let tag = current_tag();
        record_allocation(tag, layout.size());
        // SAFETY: `base` is the live allocation `System.alloc(block)` just
        // returned, sized for `header(layout.align()) + layout.size()` -- see
        // `finish`'s contract.
        unsafe { finish(base, layout.align(), tag) }
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        let Some(block) = outer(layout) else {
            return std::ptr::null_mut();
        };
        // SAFETY: as in `alloc`.
        let base = unsafe { System.alloc_zeroed(block) };
        if base.is_null() {
            return base;
        }
        let tag = current_tag();
        record_allocation(tag, layout.size());
        // SAFETY: as in `alloc`.
        unsafe { finish(base, layout.align(), tag) }
    }

    unsafe fn dealloc(&self, pointer: *mut u8, layout: Layout) {
        let hdr = header(layout.align());
        unsafe {
            // SAFETY: by `GlobalAlloc`'s contract, `pointer` is a value
            // previously returned by this allocator's `alloc`/`alloc_zeroed`/
            // `realloc` for a layout equivalent to `layout`, i.e. `finish`
            // wrote a tag byte at `pointer - 1`, which is therefore
            // initialised and in bounds of the underlying block.
            let tag = pointer.sub(1).read();
            // SAFETY: `layout.size() + hdr` cannot overflow here: `alloc`/
            // `alloc_zeroed` only ever produced this `pointer` after `outer`
            // (which computes the same `size + header` sum) succeeded for an
            // equivalent layout, and `align` is unchanged, so this
            // reconstructs that same valid layout.
            let block = Layout::from_size_align_unchecked(layout.size() + hdr, layout.align());
            // SAFETY: `pointer.sub(hdr)` recovers the `base` pointer `System`
            // itself allocated (see `finish`), and `block` is that
            // allocation's exact layout, satisfying `System.dealloc`'s
            // contract.
            System.dealloc(pointer.sub(hdr), block);
            record_deallocation(tag, layout.size());
        }
    }

    unsafe fn realloc(&self, pointer: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        let hdr = header(layout.align());
        let Some(new_block) = new_size.checked_add(hdr) else {
            return std::ptr::null_mut();
        };
        unsafe {
            // SAFETY: as in `dealloc`: `pointer - 1` is the tag byte `finish`
            // wrote for this allocation.
            let tag = pointer.sub(1).read();
            // SAFETY: as in `dealloc`: reconstructs the padded layout
            // `pointer` was actually allocated with.
            let block = Layout::from_size_align_unchecked(layout.size() + hdr, layout.align());
            // SAFETY: `pointer.sub(hdr)` recovers `System`'s `base` pointer
            // and `block` is its current layout; `new_block` is that same
            // padding scheme applied to `new_size` (`GlobalAlloc::realloc`'s
            // contract requires `new_size`'s alignment to match `layout`'s,
            // which we reuse), so this is a valid `System.realloc` call.
            let base = System.realloc(pointer.sub(hdr), block, new_block);
            if base.is_null() {
                return base;
            }
            let old = layout.size();
            if new_size >= old {
                record_allocation(tag, new_size - old);
            } else {
                record_deallocation(tag, old - new_size);
            }
            // realloc copied the header, tag included: `base + hdr` is in
            // bounds of the new, live allocation, same reasoning as `finish`.
            base.add(hdr)
        }
    }
}

/// `(current, peak)` live Rust heap bytes over every tag.
pub fn diagnostics() -> (u64, u64) {
    (
        CURRENT_BYTES.load(Ordering::Relaxed),
        PEAK_BYTES.load(Ordering::Relaxed),
    )
}

/// Per-tag current and peak bytes.
pub fn tag_counters() -> &'static TagCounters {
    &TAGS
}
