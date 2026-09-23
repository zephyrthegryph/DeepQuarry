//! Allocator tags (`rust_core.md` §11): current and peak bytes per domain.
//!
//! Core owns no statics, so it only defines the tag type, the counter trait
//! and a lock-free counter table. The DLL's tracking allocator (vg-ffi
//! `allocator`) keeps a `static TagCounters` and reports into it; stores
//! such as [`Arena`](crate::Arena) report their reserved bytes under a tag.

use std::sync::atomic::{AtomicU64, Ordering};

/// A memory domain. The discriminant indexes [`TagCounters`].
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum AllocTag {
    /// Anything not attributed to a domain.
    Untagged = 0,
    Core = 1,
    Gas = 2,
    Heat = 3,
    Power = 4,
    Devices = 5,
    Layout = 6,
    Ffi = 7,
}

impl AllocTag {
    pub const COUNT: usize = 8;
    pub const ALL: [AllocTag; Self::COUNT] = [
        AllocTag::Untagged,
        AllocTag::Core,
        AllocTag::Gas,
        AllocTag::Heat,
        AllocTag::Power,
        AllocTag::Devices,
        AllocTag::Layout,
        AllocTag::Ffi,
    ];

    #[must_use]
    pub const fn name(self) -> &'static str {
        match self {
            AllocTag::Untagged => "untagged",
            AllocTag::Core => "core",
            AllocTag::Gas => "gas",
            AllocTag::Heat => "heat",
            AllocTag::Power => "power",
            AllocTag::Devices => "devices",
            AllocTag::Layout => "layout",
            AllocTag::Ffi => "ffi",
        }
    }

    #[must_use]
    pub const fn index(self) -> usize {
        self as usize
    }
}

/// Something that counts tagged allocations. Must be callable from inside a
/// global allocator: implementations must not allocate or lock.
pub trait AllocCounter: Sync {
    fn record_alloc(&self, tag: AllocTag, bytes: usize);
    fn record_free(&self, tag: AllocTag, bytes: usize);

    /// A resize, as the allocator sees it.
    fn record_realloc(&self, tag: AllocTag, old: usize, new: usize) {
        if new >= old {
            self.record_alloc(tag, new - old);
        } else {
            self.record_free(tag, old - new);
        }
    }
}

/// Current and peak bytes for one tag.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct TagUsage {
    pub current: u64,
    pub peak: u64,
}

/// Lock-free per-tag counters. `const`-constructible so the DLL can hold one
/// in a static next to its global allocator.
pub struct TagCounters {
    current: [AtomicU64; AllocTag::COUNT],
    peak: [AtomicU64; AllocTag::COUNT],
}

impl Default for TagCounters {
    fn default() -> Self {
        Self::new()
    }
}

impl TagCounters {
    #[must_use]
    pub const fn new() -> Self {
        Self {
            current: [const { AtomicU64::new(0) }; AllocTag::COUNT],
            peak: [const { AtomicU64::new(0) }; AllocTag::COUNT],
        }
    }

    #[must_use]
    pub fn usage(&self, tag: AllocTag) -> TagUsage {
        TagUsage {
            current: self.current[tag.index()].load(Ordering::Relaxed),
            peak: self.peak[tag.index()].load(Ordering::Relaxed),
        }
    }

    /// Every tag's usage, indexed by [`AllocTag::index`].
    #[must_use]
    pub fn snapshot(&self) -> [TagUsage; AllocTag::COUNT] {
        AllocTag::ALL.map(|tag| self.usage(tag))
    }

    /// Resets every peak to the current value (e.g. per benchmark phase).
    pub fn reset_peaks(&self) {
        for (current, peak) in self.current.iter().zip(&self.peak) {
            peak.store(current.load(Ordering::Relaxed), Ordering::Relaxed);
        }
    }
}

impl AllocCounter for TagCounters {
    fn record_alloc(&self, tag: AllocTag, bytes: usize) {
        let i = tag.index();
        let now = self.current[i].fetch_add(bytes as u64, Ordering::Relaxed) + bytes as u64;
        self.peak[i].fetch_max(now, Ordering::Relaxed);
    }

    fn record_free(&self, tag: AllocTag, bytes: usize) {
        // Saturate rather than wrap if frees are ever attributed to the wrong tag.
        let _ = self.current[tag.index()].fetch_update(Ordering::Relaxed, Ordering::Relaxed, |v| {
            Some(v.saturating_sub(bytes as u64))
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tracks_current_and_peak_per_tag() {
        let counters = TagCounters::new();
        counters.record_alloc(AllocTag::Gas, 100);
        counters.record_alloc(AllocTag::Gas, 50);
        counters.record_free(AllocTag::Gas, 120);
        counters.record_realloc(AllocTag::Heat, 10, 40);
        assert_eq!(
            counters.usage(AllocTag::Gas),
            TagUsage {
                current: 30,
                peak: 150
            }
        );
        assert_eq!(counters.usage(AllocTag::Heat).current, 30);
        assert_eq!(counters.usage(AllocTag::Core), TagUsage::default());
        counters.reset_peaks();
        assert_eq!(counters.usage(AllocTag::Gas).peak, 30);
        counters.record_free(AllocTag::Power, 5);
        assert_eq!(counters.usage(AllocTag::Power).current, 0);
    }

    #[test]
    fn tags_index_their_slot() {
        for (i, tag) in AllocTag::ALL.iter().enumerate() {
            assert_eq!(tag.index(), i);
        }
    }
}
