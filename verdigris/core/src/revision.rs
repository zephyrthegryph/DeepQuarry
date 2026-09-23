//! Band-triggered revision counters (`rust_core.md` §15: change tracking
//! belongs in `core::watch`/`core::revision`, not reimplemented per domain).
//!
//! This is the cheap, per-value sibling of [`crate::watch`]'s frame-
//! evaluated conditions: no registration, no channel table, no chunk
//! bucketing -- just "bump a counter when a tracked scalar moved far enough
//! from what was last recorded", for a caller (typically an FFI read) that
//! wants to know "did this change enough to be worth re-reading" without
//! comparing full state every time. `core::watch::Cond::Band` is the right
//! tool when a watch needs to be *registered* and *fire* through the
//! frame/outbox pipeline; `BandRevision` is for a value a domain already
//! owns and just wants a cheap dirty counter on.

/// A `u32` counter over `N` scalar channels, bumped once per [`update`](Self::update)
/// call in which any channel moved by at least its band width from the
/// value recorded at the last bump. Channels are independent: a channel
/// that never moves never contributes, and one `None` value (unknown this
/// call) never itself triggers or blocks a bump from the others.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct BandRevision<const N: usize> {
    pub revision: u32,
    at: [f32; N],
}

impl<const N: usize> Default for BandRevision<N> {
    fn default() -> Self {
        Self::new()
    }
}

impl<const N: usize> BandRevision<N> {
    #[must_use]
    pub const fn new() -> Self {
        Self {
            revision: 0,
            at: [0.0; N],
        }
    }

    /// The values recorded at the last bump (or the initial zeros, before
    /// the first one).
    #[must_use]
    pub const fn recorded(&self) -> [f32; N] {
        self.at
    }

    /// Checks `values` against the value recorded at the last bump and
    /// `bands` (same index); if any channel moved by at least its band
    /// width, bumps `revision` once and records every `Some` value in
    /// `values` as the new baseline (a `None` channel keeps its old
    /// baseline). Non-finite comparisons never trigger a bump (a channel
    /// that reads NaN doesn't spuriously dirty every future call).
    pub fn update(&mut self, values: [Option<f32>; N], bands: [f32; N]) {
        let moved = values
            .iter()
            .zip(self.at)
            .zip(bands)
            .any(|((value, at), band)| {
                value.is_some_and(|v| v.is_finite() && (v - at).abs() >= band)
            });
        if moved {
            self.revision = self.revision.wrapping_add(1);
            for (slot, value) in self.at.iter_mut().zip(values) {
                if let Some(v) = value {
                    *slot = v;
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn does_not_bump_below_the_band() {
        let mut r = BandRevision::<1>::new();
        r.update([Some(0.4)], [0.5]);
        assert_eq!(r.revision, 0);
    }

    #[test]
    fn bumps_once_a_channel_crosses_its_band() {
        let mut r = BandRevision::<1>::new();
        r.update([Some(0.6)], [0.5]);
        assert_eq!(r.revision, 1);
        assert_eq!(r.recorded(), [0.6]);
    }

    #[test]
    fn settling_drift_within_the_band_never_bumps() {
        let mut r = BandRevision::<1>::new();
        for v in [0.1, 0.2, 0.3, 0.4, 0.45, 0.49] {
            r.update([Some(v)], [0.5]);
        }
        assert_eq!(r.revision, 0, "drifted within the band the whole time");
    }

    #[test]
    fn independent_channels_each_have_their_own_band() {
        let mut r = BandRevision::<2>::new();
        r.update([Some(0.0), Some(0.0)], [1.0, 1.0]);
        r.update([Some(0.5), Some(2.0)], [1.0, 1.0]);
        assert_eq!(r.revision, 1, "only channel 1 crossed its band");
        assert_eq!(r.recorded(), [0.5, 2.0], "both baselines still advance");
    }

    #[test]
    fn unknown_channel_neither_triggers_nor_blocks() {
        let mut r = BandRevision::<2>::new();
        r.update([None, Some(5.0)], [1.0, 1.0]);
        assert_eq!(r.revision, 1);
        assert_eq!(r.recorded(), [0.0, 5.0], "unknown channel keeps its baseline");
    }

    #[test]
    fn nan_never_triggers_a_bump() {
        let mut r = BandRevision::<1>::new();
        r.update([Some(f32::NAN)], [0.5]);
        assert_eq!(r.revision, 0);
    }
}

/// A plain `u32` generation/version counter: bumps unconditionally, every
/// time the caller says the thing it's attached to changed identity or
/// content (a slot was reused, a value was overwritten). This is
/// `BandRevision`'s sibling for the simpler "every write counts" case (no
/// band, no "did it move enough" comparison) -- e.g. a slab slot's "has
/// this handle's target changed since I last read it" counter.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Counter(pub u32);

impl Counter {
    #[must_use]
    pub const fn new() -> Self {
        Self(0)
    }

    /// Unconditionally advances the counter by one (wrapping).
    pub fn bump(&mut self) {
        self.0 = self.0.wrapping_add(1);
    }

    #[must_use]
    pub const fn get(self) -> u32 {
        self.0
    }
}

#[cfg(test)]
mod counter_tests {
    use super::Counter;

    #[test]
    fn starts_at_zero_and_bumps_by_one() {
        let mut c = Counter::new();
        assert_eq!(c.get(), 0);
        c.bump();
        assert_eq!(c.get(), 1);
        c.bump();
        assert_eq!(c.get(), 2);
    }

    #[test]
    fn wraps_instead_of_panicking() {
        let mut c = Counter(u32::MAX);
        c.bump();
        assert_eq!(c.get(), 0);
    }
}
