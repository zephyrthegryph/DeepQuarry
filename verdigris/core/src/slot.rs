//! Generic generational slot ids (`rust_architecture.md` §4.1).
//!
//! This is **not** the DM-facing identity — that is
//! [`crate::entity::EntityTable`], the only handle type that crosses to DM.
//! This module is for internal, Rust-only generational ids that never leave
//! the process: the network graph's node/edge/region/device ids
//! (`network::graph`, `network::host`, a domain's own network kind). Arenas
//! keep their own private slot type instead of this one (`arena.rs`).
//!
//! A handle packs a 20-bit slot index and a 4-bit generation into the low 24
//! bits of a `u32` — exact as an `f32`, which matters only where a value
//! built from one (a network key) ends up crossing to DM; the packing itself
//! doesn't require it.

use std::fmt;
use std::hash::{Hash, Hasher};
use std::marker::PhantomData;

/// Bits used by the slot index.
pub const INDEX_BITS: u32 = 20;
/// Bits used by the generation.
pub const GENERATION_BITS: u32 = 4;
/// Number of addressable slots (2^20).
pub const MAX_SLOTS: u32 = 1 << INDEX_BITS;
/// Largest generation value (15).
pub const MAX_GENERATION: u8 = (1 << GENERATION_BITS) - 1;

const INDEX_MASK: u32 = MAX_SLOTS - 1;
const PACKED_MASK: u32 = (1 << (INDEX_BITS + GENERATION_BITS)) - 1;

/// An untyped handle: index in bits 0..20, generation in bits 20..24.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct RawHandle(u32);

impl RawHandle {
    /// `None` if `index` does not fit 20 bits or `generation` 4 bits.
    #[must_use]
    pub const fn new(index: u32, generation: u8) -> Option<Self> {
        if index > INDEX_MASK || generation > MAX_GENERATION {
            return None;
        }
        Some(Self(index | ((generation as u32) << INDEX_BITS)))
    }

    /// Unpacks a raw `u32`; `None` if any bit above bit 23 is set.
    #[must_use]
    pub const fn from_bits(bits: u32) -> Option<Self> {
        if bits & !PACKED_MASK != 0 {
            return None;
        }
        Some(Self(bits))
    }

    #[must_use]
    pub const fn bits(self) -> u32 {
        self.0
    }

    #[must_use]
    pub const fn index(self) -> u32 {
        self.0 & INDEX_MASK
    }

    #[must_use]
    pub const fn generation(self) -> u8 {
        (self.0 >> INDEX_BITS) as u8
    }

    /// The handle as a DM number. Exact: every packed value is below 2^24.
    #[must_use]
    #[allow(clippy::cast_precision_loss)]
    pub const fn to_f32(self) -> f32 {
        self.0 as f32
    }

    /// Reads a handle back from a DM number. Rejects fractions, negatives,
    /// NaN and values that do not fit 24 bits.
    #[must_use]
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    pub fn from_f32(value: f32) -> Option<Self> {
        if !(0.0..=PACKED_MASK as f32).contains(&value) || value.fract() != 0.0 {
            return None;
        }
        Self::from_bits(value as u32)
    }
}

/// A handle to a `T`. The type parameter only prevents mixing handles of
/// different stores; the representation is a [`RawHandle`].
pub struct Handle<T> {
    raw: RawHandle,
    _marker: PhantomData<fn() -> T>,
}

impl<T> Handle<T> {
    #[must_use]
    pub const fn from_raw(raw: RawHandle) -> Self {
        Self {
            raw,
            _marker: PhantomData,
        }
    }

    #[must_use]
    pub const fn raw(self) -> RawHandle {
        self.raw
    }

    #[must_use]
    pub const fn index(self) -> u32 {
        self.raw.index()
    }

    #[must_use]
    pub const fn generation(self) -> u8 {
        self.raw.generation()
    }

    #[must_use]
    pub const fn to_f32(self) -> f32 {
        self.raw.to_f32()
    }

    #[must_use]
    pub fn from_f32(value: f32) -> Option<Self> {
        RawHandle::from_f32(value).map(Self::from_raw)
    }
}

// Manual impls so `T` needs no bounds.
impl<T> Clone for Handle<T> {
    fn clone(&self) -> Self {
        *self
    }
}
impl<T> Copy for Handle<T> {}
impl<T> PartialEq for Handle<T> {
    fn eq(&self, other: &Self) -> bool {
        self.raw == other.raw
    }
}
impl<T> Eq for Handle<T> {}
impl<T> Hash for Handle<T> {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.raw.hash(state);
    }
}
impl<T> fmt::Debug for Handle<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Handle({}v{})", self.index(), self.generation())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    #[test]
    fn rejects_out_of_range_parts() {
        assert!(RawHandle::new(MAX_SLOTS, 0).is_none());
        assert!(RawHandle::new(0, 16).is_none());
        assert!(RawHandle::from_bits(1 << 24).is_none());
        assert!(RawHandle::from_f32(-1.0).is_none());
        assert!(RawHandle::from_f32(1.5).is_none());
        assert!(RawHandle::from_f32(f32::NAN).is_none());
        assert!(RawHandle::from_f32(16_777_216.0).is_none());
    }

    proptest! {
        #[test]
        fn packs_and_round_trips_through_f32(index in 0..MAX_SLOTS, generation in 0..=MAX_GENERATION) {
            let raw = RawHandle::new(index, generation).unwrap();
            prop_assert_eq!(raw.index(), index);
            prop_assert_eq!(raw.generation(), generation);
            prop_assert_eq!(RawHandle::from_f32(raw.to_f32()), Some(raw));
        }
    }
}
