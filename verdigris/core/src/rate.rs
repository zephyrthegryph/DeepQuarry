//! Rate models (`rust_core.md` §7, `rust_architecture.md` §4.10): the one
//! module for "a quantity that flows toward a target/at a rate, with a
//! limit and a stop condition."
//!
//! Two complementary shapes:
//! - [`RateModel`]: a *prediction* over continuous time -- "what is the
//!   value at time `t`" and "when does it cross level `L`", solved exactly
//!   (no stepping), so the reactor's timer wheel can wake a subscriber at
//!   the predicted tick instead of polling every tick. This is what the
//!   reactor's `#[auxmacros::bind]`d `vg_rate_*` procs expose to DM
//!   (`core::reactor`, which re-exports [`RateModel`] from here for every
//!   existing `vg_core::reactor::RateModel` reference).
//! - [`RateStore`]: a *bounded reservoir* -- "how much is stored, out of
//!   how much capacity, converting at this rate between an external flow
//!   unit (watts) and internal stored units." This is the arithmetic every
//!   domain that holds energy behind a rate constant (power cells, SMES,
//!   and any future storage) needs, gotten right exactly once instead of
//!   hand-rolled per domain (the duplication `rust_architecture.md` §1's
//!   table calls out: "gas Flow internals, power APC/SMES constants and
//!   passes, the heat regulator").
//!
//! They compose, per §4.10 ("Storage (cells, SMES) is `RateModel::Linear`
//! between events, and relaxing bodies are `Relax`"): a storage law applies
//! a step with [`RateStore::discharge_out`]/[`charge_in`](RateStore::charge_in)
//! as usual for the actual bookkeeping, and whenever the *rate* changes
//! (a new demand, a config change, ...) it also rebuilds a
//! `RateModel::Linear::new(store.charge, external_rate * store.rate, now)`
//! for that store, so the reactor can predict exactly when it will empty
//! or fill and wake the law then, instead of that law polling every frame.
//! `RateStore` doesn't do this itself -- it has no notion of "now" or a
//! reactor to schedule against -- so a law only needs to rebuild the model
//! on a rate change, not every step.

// --- Rate models -------------------------------------------------------------

/// A quantity that changes at a known rate between events, in value units
/// per tick. Reading evaluates it at a time; crossing times are solved
/// exactly.
#[derive(Clone, Debug, PartialEq)]
pub enum RateModel {
    /// `clamp(v0 + rate * (t - t0), min, max)`.
    Linear {
        v0: f64,
        rate: f64,
        t0: f64,
        min: f64,
        max: f64,
    },
    /// `target + (v0 - target) * e^(-k (t - t0))`, `k > 0`.
    Relax {
        target: f64,
        v0: f64,
        k: f64,
        t0: f64,
    },
    /// A store with named inflows and outflows: linear with the summed
    /// rate, clamped.
    Sum {
        v0: f64,
        t0: f64,
        terms: Vec<(u32, f64)>,
        min: f64,
        max: f64,
    },
}

impl RateModel {
    #[must_use]
    pub const fn linear(v0: f64, rate: f64, t0: f64) -> Self {
        Self::Linear {
            v0,
            rate,
            t0,
            min: f64::NEG_INFINITY,
            max: f64::INFINITY,
        }
    }

    fn line(&self) -> Option<(f64, f64, f64, f64, f64)> {
        match self {
            Self::Linear {
                v0,
                rate,
                t0,
                min,
                max,
            } => Some((*v0, *rate, *t0, *min, *max)),
            Self::Sum {
                v0,
                t0,
                terms,
                min,
                max,
            } => Some((*v0, terms.iter().map(|t| t.1).sum(), *t0, *min, *max)),
            Self::Relax { .. } => None,
        }
    }

    /// The value at time `t`.
    #[must_use]
    pub fn value_at(&self, t: f64) -> f64 {
        match self {
            Self::Relax { target, v0, k, t0 } => target + (v0 - target) * (-k * (t - t0)).exp(),
            _ => {
                let (v0, rate, t0, min, max) = self.line().expect("linear");
                rate.mul_add(t - t0, v0).clamp(min, max)
            }
        }
    }

    /// The first time strictly after `after` at which the value reaches
    /// `level` from the side it is on at `after`, or `None` if it never
    /// does. Exact up to floating point: no stepping.
    #[must_use]
    pub fn crossing(&self, level: f64, after: f64) -> Option<f64> {
        let now = self.value_at(after);
        if now == level || !level.is_finite() {
            return None;
        }
        let t = match self {
            Self::Relax { target, v0, k, t0 } => {
                // Reachable only strictly between the current value and the
                // target (the target itself is approached, never reached).
                let between = (now < level && level < *target) || (*target < level && level < now);
                if !between || *k <= 0.0 {
                    return None;
                }
                t0 - ((level - target) / (v0 - target)).ln() / k
            }
            _ => {
                let (v0, rate, t0, min, max) = self.line().expect("linear");
                let heading_up = rate > 0.0;
                if rate == 0.0 || (heading_up != (level > now)) || level < min || level > max {
                    return None;
                }
                t0 + (level - v0) / rate
            }
        };
        (t > after && t.is_finite()).then_some(t)
    }

    /// Restarts the model at time `now` from its current value, so a new
    /// input applies from now on (§7 "input changes").
    pub fn rebase(&mut self, now: f64) {
        let v = self.value_at(now);
        match self {
            Self::Linear { v0, t0, .. } | Self::Relax { v0, t0, .. } | Self::Sum { v0, t0, .. } => {
                *v0 = v;
                *t0 = now;
            }
        }
    }
}

// --- Rate stores --------------------------------------------------------------

/// A bounded store with a fixed conversion rate between an external flow
/// unit (watts) and internal stored units.
///
/// `rate` is stored-units per watt-tick: `stored += rate * watts` when
/// charging, `stored -= rate * watts` when discharging. A store with
/// `capacity <= 0.0` accepts and offers nothing. All quantities are `f64`
/// (this backs the power domain, which tracks the wire end to end in
/// `f64`, `doc/rewrite/rust_bindings.md`).
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
        Self {
            charge: 0.0,
            capacity: 0.0,
            rate,
        }
    }

    /// The most this store could discharge this tick, in watts.
    #[must_use]
    pub fn watts_available(&self) -> f64 {
        if self.rate > 0.0 {
            (self.charge / self.rate).max(0.0)
        } else {
            0.0
        }
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
        if self.capacity > 0.0 {
            (self.charge / self.capacity).clamp(0.0, 1.0)
        } else {
            0.0
        }
    }

    /// Draws up to `watts` from the store this tick. Returns the watts
    /// actually delivered (never more than [`Self::watts_available`], never
    /// negative), and removes exactly that many watt-ticks' worth of
    /// charge -- conservation holds by construction: the caller's energy
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

    /// Clamps `charge` into `[0, capacity]` (for external writes: a config
    /// change that lowered capacity, or a direct charge set).
    pub fn clamp(&mut self) {
        self.charge = self.charge.clamp(0.0, self.capacity.max(0.0));
    }

    /// A [`RateModel::Linear`] predicting this store's charge over time at
    /// a constant `external_rate` watts (positive: charging: negative:
    /// discharging), for the reactor to schedule an exact wake against
    /// instead of the owning law polling every frame. Rebuild this
    /// whenever `external_rate` changes (§4.10); the store itself doesn't
    /// track time, so it can't do this automatically.
    #[must_use]
    pub fn model(&self, external_rate: f64, now: f64) -> RateModel {
        RateModel::Linear {
            v0: self.charge,
            rate: external_rate * self.rate,
            t0: now,
            min: 0.0,
            max: self.capacity,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    #[test]
    fn linear_and_relax_crossings_are_exact() {
        let m = RateModel::linear(100.0, -2.0, 10.0);
        assert_eq!(m.value_at(15.0), 90.0);
        assert_eq!(m.crossing(50.0, 10.0), Some(35.0));
        assert_eq!(m.crossing(150.0, 10.0), None, "moving away");
        assert_eq!(m.crossing(50.0, 40.0), None, "already past");
        let clamped = RateModel::Linear {
            v0: 0.0,
            rate: 1.0,
            t0: 0.0,
            min: 0.0,
            max: 10.0,
        };
        assert_eq!(clamped.value_at(50.0), 10.0);
        assert_eq!(clamped.crossing(20.0, 0.0), None, "beyond the clamp");
        assert_eq!(clamped.crossing(10.0, 0.0), Some(10.0));

        let r = RateModel::Relax {
            target: 20.0,
            v0: 100.0,
            k: 0.1,
            t0: 0.0,
        };
        let t = r.crossing(50.0, 0.0).unwrap();
        assert!((r.value_at(t) - 50.0).abs() < 1e-9);
        assert!(r.value_at(t - 1e-6) > 50.0);
        assert_eq!(r.crossing(20.0, 0.0), None, "the target is never reached");
        assert_eq!(r.crossing(10.0, 0.0), None, "beyond the target");

        let mut s = RateModel::Sum {
            v0: 10.0,
            t0: 0.0,
            terms: vec![(1, 3.0), (2, -1.0)],
            min: 0.0,
            max: 100.0,
        };
        assert_eq!(s.crossing(30.0, 0.0), Some(10.0));
        s.rebase(5.0);
        if let RateModel::Sum { terms, .. } = &mut s {
            terms[0].1 = 0.0;
        }
        assert_eq!(s.value_at(5.0), 20.0);
        assert_eq!(s.crossing(0.0, 5.0), Some(25.0));
    }

    #[test]
    fn discharge_never_exceeds_available_or_goes_negative() {
        let mut s = RateStore {
            charge: 10.0,
            capacity: 100.0,
            rate: 0.5,
        };
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
        let mut s = RateStore {
            charge: 90.0,
            capacity: 100.0,
            rate: 2.0,
        };
        // room = (100 - 90) / 2 = 5 watts.
        let used = s.charge_in(100.0);
        assert!((used - 5.0).abs() < 1e-9);
        assert!((s.charge - 100.0).abs() < 1e-9);
        assert!(s.charge <= s.capacity);
    }

    #[test]
    fn zero_rate_offers_and_accepts_nothing() {
        let mut s = RateStore {
            charge: 10.0,
            capacity: 100.0,
            rate: 0.0,
        };
        assert_eq!(s.watts_available(), 0.0);
        assert_eq!(s.room_watts(), 0.0);
        assert_eq!(s.discharge_out(10.0), 0.0);
        assert_eq!(s.charge_in(10.0), 0.0);
    }

    #[test]
    fn model_predicts_an_exact_empty_time() {
        let s = RateStore {
            charge: 100.0,
            capacity: 200.0,
            rate: 1.0,
        };
        // Discharging at 10 W with rate 1.0: 10 units/tick, so 10 ticks to empty.
        let m = s.model(-10.0, 0.0);
        assert_eq!(m.crossing(0.0, 0.0), Some(10.0));
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
