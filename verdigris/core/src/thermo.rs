//! Thermodynamics kernel (`rust_core.md` §13: heat share formulas become
//! `core::thermo`). Pure functions over unit newtypes; no domain state.

use crate::units::{HeatCapacity, Joules, Kelvin, Moles};

/// Below this a body has no meaningful temperature (matches the gas code's
/// minimum heat capacity guard).
pub const MIN_HEAT_CAPACITY: HeatCapacity = HeatCapacity(0.0003);

/// Total heat capacity of a mixture from `(amount, molar heat capacity in
/// J/(mol·K))` pairs. Summed in `f64`.
pub fn heat_capacity(parts: impl IntoIterator<Item = (Moles, f32)>) -> HeatCapacity {
    let total: f64 = parts
        .into_iter()
        .map(|(moles, specific)| f64::from(moles.0) * f64::from(specific))
        .sum();
    #[allow(clippy::cast_possible_truncation)]
    HeatCapacity(total as f32)
}

/// Thermal energy `C·T`.
#[must_use]
pub fn thermal_energy(capacity: HeatCapacity, temperature: Kelvin) -> Joules {
    capacity * temperature
}

/// Temperature `E/C`, or zero kelvin for a body below [`MIN_HEAT_CAPACITY`].
#[must_use]
pub fn temperature(capacity: HeatCapacity, energy: Joules) -> Kelvin {
    if capacity.0 < MIN_HEAT_CAPACITY.0 {
        Kelvin::ZERO
    } else {
        energy / capacity
    }
}

/// Energy that brings two bodies to a common temperature:
/// `ΔT · C₁C₂ / (C₁ + C₂)`, where `ΔT = T₁ − T₂`. Positive means energy
/// flows from body 1 to body 2. Zero if either capacity is not positive.
#[must_use]
pub fn equalizing_energy(delta: Kelvin, cap_1: HeatCapacity, cap_2: HeatCapacity) -> Joules {
    if cap_1.0 <= 0.0 || cap_2.0 <= 0.0 {
        return Joules::ZERO;
    }
    let (c1, c2) = (f64::from(cap_1.0), f64::from(cap_2.0));
    #[allow(clippy::cast_possible_truncation)]
    Joules((f64::from(delta.0) * c1 * c2 / (c1 + c2)) as f32)
}

/// A lump with a heat capacity and a temperature.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ThermalBody {
    pub capacity: HeatCapacity,
    pub temperature: Kelvin,
}

impl ThermalBody {
    #[must_use]
    pub const fn new(capacity: HeatCapacity, temperature: Kelvin) -> Self {
        Self {
            capacity,
            temperature,
        }
    }

    #[must_use]
    pub fn energy(self) -> Joules {
        thermal_energy(self.capacity, self.temperature)
    }
}

/// Pairwise exchange between `a` and `b`. `coefficient` is the fraction of
/// the way to equilibrium to go, clamped to `[0, 1]`, so the exchange never
/// overshoots (the hotter body never ends colder than the other). The same
/// energy is removed from one body and added to the other, so the total is
/// conserved up to `f32` rounding of the stored temperatures. Returns the
/// energy moved from `a` to `b`.
pub fn exchange(a: &mut ThermalBody, b: &mut ThermalBody, coefficient: f32) -> Joules {
    let coefficient = if coefficient.is_nan() {
        0.0
    } else {
        coefficient.clamp(0.0, 1.0)
    };
    if a.capacity.0 < MIN_HEAT_CAPACITY.0 || b.capacity.0 < MIN_HEAT_CAPACITY.0 {
        return Joules::ZERO;
    }
    let (ca, cb) = (f64::from(a.capacity.0), f64::from(b.capacity.0));
    let (ta, tb) = (f64::from(a.temperature.0), f64::from(b.temperature.0));
    let moved = f64::from(coefficient) * (ta - tb) * ca * cb / (ca + cb);
    #[allow(clippy::cast_possible_truncation)]
    {
        a.temperature = Kelvin((ta - moved / ca) as f32);
        b.temperature = Kelvin((tb + moved / cb) as f32);
        Joules(moved as f32)
    }
}

/// `1/C`, with a non-positive or infinite capacity counting as a reservoir
/// (contributes nothing to the combined `1/C`, so it never changes
/// temperature no matter how much energy crosses it).
fn inverse(capacity: f64) -> f64 {
    if capacity.is_finite() && capacity > 0.0 {
        1.0 / capacity
    } else {
        0.0
    }
}

/// Exact energy moved from `a` to `b` over `dt` seconds by conductance `g`
/// (W/K): `ΔT · h · (1 − e^(−g (1/Ca + 1/Cb) dt))` with `h = 1 / (1/Ca +
/// 1/Cb)`. A reservoir side (`Ca`/`Cb` non-positive or infinite) never
/// overshoots regardless of `g` or `dt`; this is the continuous-time
/// integral of Newton's law of cooling, not a fixed-step approximation of
/// it. The one pair-exchange law every domain that moves heat over a
/// conductance and a timestep should use (`rust_core.md` §15) -- if you're
/// about to write `ΔT * conductance * dt` or similar, use this instead so
/// large conductances/timesteps can't push a pair past equilibrium.
#[must_use]
pub fn pair_exchange(a: ThermalBody, b: ThermalBody, conductance: f32, dt: f32) -> Joules {
    let inv = inverse(f64::from(a.capacity.0)) + inverse(f64::from(b.capacity.0));
    if inv <= 0.0 || conductance.is_nan() || conductance <= 0.0 || dt.is_nan() || dt <= 0.0 {
        return Joules::ZERO;
    }
    let fraction = -(-f64::from(conductance) * inv * f64::from(dt)).exp_m1();
    let moved = f64::from(a.temperature.0 - b.temperature.0) / inv * fraction;
    #[allow(clippy::cast_possible_truncation)]
    Joules(if moved.is_finite() { moved as f32 } else { 0.0 })
}

/// As [`pair_exchange`], with the pair's relaxation rate (1/s) given
/// directly instead of a conductance: `ΔT · h · (1 − e^(−rate dt))`.
#[must_use]
pub fn pair_exchange_at_rate(a: ThermalBody, b: ThermalBody, rate: f32, dt: f32) -> Joules {
    let inv = inverse(f64::from(a.capacity.0)) + inverse(f64::from(b.capacity.0));
    if inv <= 0.0 || rate.is_nan() || rate <= 0.0 || dt.is_nan() || dt <= 0.0 {
        return Joules::ZERO;
    }
    let fraction = -(-f64::from(rate) * f64::from(dt)).exp_m1();
    let moved = f64::from(a.temperature.0 - b.temperature.0) / inv * fraction;
    #[allow(clippy::cast_possible_truncation)]
    Joules(if moved.is_finite() { moved as f32 } else { 0.0 })
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    /// Carried over from vg-gas `superconduct.rs`.
    #[test]
    fn solid_heat_transfer_conserves_energy() {
        let transferred = equalizing_energy(
            Kelvin(250.0 - 350.0),
            HeatCapacity(10_000.0),
            HeatCapacity(2_500.0),
        ) * (0.04 * 0.5);
        let hot_end = 350.0 + transferred.0 / 10_000.0;
        let cold_end = 250.0 - transferred.0 / 2_500.0;
        let before = 350.0 * 10_000.0 + 250.0 * 2_500.0;
        let after = hot_end * 10_000.0 + cold_end * 2_500.0;
        assert!(f32::abs(before - after) < 0.5);
        assert!(hot_end < 350.0);
        assert!(cold_end > 250.0);
    }

    #[test]
    fn full_exchange_reaches_equilibrium() {
        let mut a = ThermalBody::new(HeatCapacity(100.0), Kelvin(400.0));
        let mut b = ThermalBody::new(HeatCapacity(300.0), Kelvin(200.0));
        let moved = exchange(&mut a, &mut b, 1.0);
        assert!((a.temperature.0 - 250.0).abs() < 1e-3);
        assert!((b.temperature.0 - 250.0).abs() < 1e-3);
        assert!((moved.0 - 15_000.0).abs() < 1e-2);
    }

    #[test]
    fn capacity_and_conversions() {
        let c = heat_capacity([(Moles(2.0), 20.0), (Moles(1.0), 30.0)]);
        assert_eq!(c, HeatCapacity(70.0));
        assert_eq!(
            temperature(c, thermal_energy(c, Kelvin(293.0))),
            Kelvin(293.0)
        );
        assert_eq!(temperature(HeatCapacity(0.0), Joules(5.0)), Kelvin::ZERO);
    }

    proptest! {
        #[test]
        fn exchange_conserves_energy_and_never_overshoots(
            ca in 0.01f32..1e6, cb in 0.01f32..1e6,
            ta in 0.0f32..1e5, tb in 0.0f32..1e5,
            k in -0.5f32..1.5,
        ) {
            let mut a = ThermalBody::new(HeatCapacity(ca), Kelvin(ta));
            let mut b = ThermalBody::new(HeatCapacity(cb), Kelvin(tb));
            let before = f64::from(ca) * f64::from(ta) + f64::from(cb) * f64::from(tb);
            exchange(&mut a, &mut b, k);
            let after = f64::from(ca) * f64::from(a.temperature.0)
                + f64::from(cb) * f64::from(b.temperature.0);
            // Only f32 rounding of the two stored temperatures is lost.
            let tolerance = 2.0 * f64::from(f32::EPSILON)
                * (f64::from(ca) + f64::from(cb)) * f64::from(ta.max(tb)).max(1.0);
            prop_assert!((before - after).abs() <= tolerance, "{before} vs {after}");
            let (lo, hi) = (ta.min(tb), ta.max(tb));
            let slack = hi * 1e-6;
            prop_assert!(a.temperature.0 >= lo - slack && a.temperature.0 <= hi + slack);
            prop_assert!(b.temperature.0 >= lo - slack && b.temperature.0 <= hi + slack);
            if ta >= tb {
                prop_assert!(a.temperature.0 + slack >= b.temperature.0);
            } else {
                prop_assert!(b.temperature.0 + slack >= a.temperature.0);
            }
        }

        /// A chain of exchanges over many bodies conserves the total.
        #[test]
        fn repeated_exchange_conserves_total(
            bodies in prop::collection::vec((1.0f32..1e4, 1.0f32..1e4), 2..16),
            pairs in prop::collection::vec((any::<prop::sample::Index>(), any::<prop::sample::Index>(), 0.0f32..1.0), 0..200),
        ) {
            let mut bodies: Vec<_> = bodies.into_iter()
                .map(|(c, t)| ThermalBody::new(HeatCapacity(c), Kelvin(t))).collect();
            let total = |bs: &[ThermalBody]| bs.iter()
                .map(|b| f64::from(b.capacity.0) * f64::from(b.temperature.0)).sum::<f64>();
            let before = total(&bodies);
            for (i, j, k) in pairs {
                let (i, j) = (i.index(bodies.len()), j.index(bodies.len()));
                if i == j { continue; }
                let (lo, hi) = (i.min(j), i.max(j));
                let (left, right) = bodies.split_at_mut(hi);
                exchange(&mut left[lo], &mut right[0], k);
            }
            let after = total(&bodies);
            prop_assert!((before - after).abs() / before < 1e-4, "{before} vs {after}");
        }
    }

    /// Carried over from vg-heat `couple.rs`, where `pair_exchange`/
    /// `pair_exchange_at_rate` lived before the dedup (`rust_core.md` §15).
    #[test]
    fn exact_exchange_matches_the_closed_form() {
        // Equal capacities: the gap halves at rate 2g/C.
        let a = ThermalBody::new(HeatCapacity(100.0), Kelvin(400.0));
        let b = ThermalBody::new(HeatCapacity(100.0), Kelvin(200.0));
        let moved = pair_exchange(a, b, 10.0, 3.0);
        let expect = 200.0 * 50.0 * (1.0 - (-0.6f64).exp());
        assert!(
            (f64::from(moved.0) - expect).abs() < 1e-3,
            "{} vs {expect}",
            moved.0
        );
        // A reservoir: harmonic -> the body's capacity.
        let a = ThermalBody::new(HeatCapacity(100.0), Kelvin(400.0));
        let b = ThermalBody::new(HeatCapacity(f32::INFINITY), Kelvin(300.0));
        let moved = pair_exchange(a, b, 10.0, 1e6);
        assert!((moved.0 - 10_000.0).abs() < 1e-2);
    }

    proptest! {
        /// Any step size: never overshoots, and applying +/-moved conserves.
        #[test]
        fn pair_exchange_never_overshoots(
            ta in 3.0f32..5000.0, tb in 3.0f32..5000.0,
            ca in 0.01f32..1e6, cb in 0.01f32..1e6,
            g in 0.0f32..1e5, dt in 0.0f32..1e4,
        ) {
            let a = ThermalBody::new(HeatCapacity(ca), Kelvin(ta));
            let b = ThermalBody::new(HeatCapacity(cb), Kelvin(tb));
            let m = pair_exchange(a, b, g, dt).0;
            let (na, nb) = (ta - m / ca, tb + m / cb);
            let (lo, hi) = (ta.min(tb), ta.max(tb));
            let slack = hi * 1e-5;
            prop_assert!(na >= lo - slack && na <= hi + slack);
            prop_assert!(nb >= lo - slack && nb <= hi + slack);
            if ta >= tb { prop_assert!(na + slack >= nb); } else { prop_assert!(nb + slack >= na); }
            let before = f64::from(ca) * f64::from(ta) + f64::from(cb) * f64::from(tb);
            let after = (f64::from(ca) * f64::from(ta) - f64::from(m))
                + (f64::from(cb) * f64::from(tb) + f64::from(m));
            prop_assert!((before - after).abs() <= before * 1e-12);
        }
    }
}
