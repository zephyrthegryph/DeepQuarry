//! A generic linear rate-model store (`rust_core.md` §15): a bounded
//! reservoir that converts between an external flow (e.g. watts) and
//! internal stored units (e.g. cell charge, SMES charge) at a fixed
//! per-tick rate. Every domain that holds energy behind a rate constant
//! (APC cells, SMES, and any future storage) should hold a [`RateStore`]
//! instead of hand-rolling the `charge / rate`,
//! `charge - min(charge, rate * watts)` arithmetic itself: that arithmetic
//! is where lost-write and over/under-draw bugs hide, and it is worth
//! getting right exactly once.
//!
//! All quantities are `f64`: this model backs the power domain, which
//! tracks the wire end to end in `f64` (`doc/rewrite/rust_bindings.md`).

/// A bounded store with a fixed conversion rate between an external flow
/// unit (watts) and internal stored units.
///
/// `rate` is stored-units per watt-tick: `stored += rate * watts` when
/// charging, `stored -= rate * watts` when discharging. A store with
/// `capacity <= 0.0` accepts and offers nothing.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct RateStore {
    /// Stored amount, in internal units. Always kept within
    /// `[0, capacity]` by every method here.
    pub charge: f64,
    /// Maximum stored amount, in internal units.
    pub capacity: f64,
    /// Internal units produced per watt-tick of flow.
    pub rate: f64,
}

impl RateStore {
    /// A store at zero charge and zero capacity with the given rate.
    #[must_use]
    pub const fn new(rate: f64) -> Self {
        Self { charge: 0.0, capacity: 0.0, rate }
    }

    /// The most this store could discharge this tick, in watts.
    #[must_use]
    pub fn watts_available(&self) -> f64 {
        if self.rate > 0.0 { (self.charge / self.rate).max(0.0) } else { 0.0 }
    }

    /// The most this store could absorb this tick before it is full, in
    /// watts.
    #[must_use]
    pub fn room_watts(&self) -> f64 {
        if self.rate > 0.0 {
            ((self.capacity - self.charge) / self.rate).max(0.0)
        } else {
            0.0
        }
    }

    /// Fraction full, in `[0, 1]` (0 when `capacity <= 0`).
    #[must_use]
    pub fn fraction(&self) -> f64 {
        if self.capacity > 0.0 { (self.charge / self.capacity).clamp(0.0, 1.0) } else { 0.0 }
    }

    /// Draws up to `watts` from the store this tick. Returns the watts
    /// actually delivered (never more than [`Self::watts_available`], never
    /// negative), and removes exactly that many watt-ticks' worth of
    /// charge — conservation holds by construction: the caller's energy
    /// books balance whatever this returns against whatever it did with
    /// the delivered watts.
    pub fn discharge_out(&mut self, watts: f64) -> f64 {
        let out = watts.max(0.0).min(self.watts_available());
        self.charge = (self.charge - out * self.rate).max(0.0);
        out
    }

    /// Accepts up to `watts` into the store this tick. Returns the watts
    /// actually consumed (never more than [`Self::room_watts`], never
    /// negative).
    pub fn charge_in(&mut self, watts: f64) -> f64 {
        let used = watts.max(0.0).min(self.room_watts());
        self.charge = (self.charge + used * self.rate).min(self.capacity.max(self.charge));
        used
    }

    /// Clamps `charge` into `[0, capacity]` (for external writes: a
    /// config change that lowered capacity, or a direct charge set).
    pub fn clamp(&mut self) {
        self.charge = self.charge.clamp(0.0, self.capacity.max(0.0));
    }
}

#[cfg(test)]
mod tests {
    use proptest::prelude::*;

    use super::RateStore;

    #[test]
    fn discharge_never_exceeds_available_or_goes_negative() {
        let mut s = RateStore { charge: 10.0, capacity: 100.0, rate: 0.5 };
        // watts_available = 10 / 0.5 = 20.
        let out = s.discharge_out(50.0);
        assert!((out - 20.0).abs() < 1e-9);
        assert!((s.charge - 0.0).abs() < 1e-9);
        // Nothing left to give.
        let out2 = s.discharge_out(5.0);
        assert_eq!(out2, 0.0);
    }

    #[test]
    fn charge_never_exceeds_capacity() {
        let mut s = RateStore { charge: 90.0, capacity: 100.0, rate: 2.0 };
        // room = (100 - 90) / 2 = 5 watts.
        let used = s.charge_in(100.0);
        assert!((used - 5.0).abs() < 1e-9);
        assert!((s.charge - 100.0).abs() < 1e-9);
        assert!(s.charge <= s.capacity);
    }

    #[test]
    fn zero_rate_offers_and_accepts_nothing() {
        let mut s = RateStore { charge: 10.0, capacity: 100.0, rate: 0.0 };
        assert_eq!(s.watts_available(), 0.0);
        assert_eq!(s.room_watts(), 0.0);
        assert_eq!(s.discharge_out(10.0), 0.0);
        assert_eq!(s.charge_in(10.0), 0.0);
    }

    proptest! {
        /// Conservation: whatever `discharge_out` reports as delivered is
        /// exactly what left the store (in watt-tick terms), for any
        /// starting charge, capacity and request.
        #[test]
        fn discharge_conserves(charge in 0.0f64..1e6, capacity in 0.0f64..1e6, rate in 0.001f64..10.0, request in 0.0f64..1e6) {
            let capacity = capacity.max(charge);
            let mut s = RateStore { charge, capacity, rate };
            let before = s.charge;
            let out = s.discharge_out(request);
            prop_assert!(out >= 0.0);
            prop_assert!(out <= request + 1e-6);
            prop_assert!((before - s.charge - out * rate).abs() < 1e-6 * (1.0 + before));
            prop_assert!(s.charge >= -1e-9);
        }

        /// Conservation for the charging half: whatever is reported as
        /// consumed is exactly what the store gained, and the store never
        /// overshoots capacity.
        #[test]
        fn charge_conserves(charge in 0.0f64..1e6, capacity in 0.0f64..1e6, rate in 0.001f64..10.0, offer in 0.0f64..1e6) {
            let charge = charge.min(capacity);
            let mut s = RateStore { charge, capacity, rate };
            let before = s.charge;
            let used = s.charge_in(offer);
            prop_assert!(used >= 0.0);
            prop_assert!(used <= offer + 1e-6);
            prop_assert!((s.charge - before - used * rate).abs() < 1e-6 * (1.0 + before));
            prop_assert!(s.charge <= capacity + 1e-9);
        }
    }
}
