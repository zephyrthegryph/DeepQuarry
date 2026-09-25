//! Thermodynamics kernel (`rust_core.md` §13, `rust_architecture.md` §4.11
//! and §8): the **only** exchange math in the workspace. Pure functions over
//! unit newtypes (plus `f32` entry points for laws that read `f32` hot
//! columns); no domain state.
//!
//! - pairwise exchange: [`exchange`] (a fraction of the way to equilibrium),
//!   [`pair_exchange`]/[`pair_exchange_at_rate`] (the exact integral of
//!   Newton cooling over a conductance or rate and a `dt`), and their `f32`
//!   forms [`pair_exchange_f32`]/[`pair_exchange_at_rate_f32`];
//! - the phase buffer: [`Phase`], [`phase_temperature`], [`phase_energy`];
//! - analytic relaxation against a reservoir: [`relax_toward`];
//! - heat pumps and heaters: [`regulator`] (`Regulator::step`, COPs).
//!
//! A domain that writes `ΔT * g * dt`, a latent-heat plateau or a COP by
//! hand is re-implementing this module (`rust_architecture.md` §2).

pub mod regulator;

pub use regulator::{Regulator, RegulatorMode, RegulatorStep, cooling_cop, heating_cop, reservoir};

use crate::units::{HeatCapacity, Joules, Kelvin, Moles, Seconds};

/// Below this a body has no meaningful temperature (matches the gas code's
/// minimum heat capacity guard).
pub const MIN_HEAT_CAPACITY: HeatCapacity = HeatCapacity(0.0003);

/// Total heat capacity of a mixture from `(amount, molar heat capacity in
/// J/(mol·K))` pairs.
pub fn heat_capacity(parts: impl IntoIterator<Item = (Moles, f64)>) -> HeatCapacity {
    HeatCapacity(
        parts
            .into_iter()
            .map(|(moles, specific)| moles.0 * specific)
            .sum(),
    )
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
    Joules(delta.0 * cap_1.0 * cap_2.0 / (cap_1.0 + cap_2.0))
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
/// conserved exactly (`f64` throughout). A capacity below
/// [`MIN_HEAT_CAPACITY`] is a reservoir: it contributes nothing to the
/// combined `1/C` (see [`pair_exchange`]'s `inverse`), so it never changes
/// temperature no matter how much energy crosses it, and an infinite
/// capacity on the *other* side is handled the same way rather than
/// producing an `inf/inf` `NaN`. Returns the energy moved from `a` to `b`.
pub fn exchange(a: &mut ThermalBody, b: &mut ThermalBody, coefficient: f32) -> Joules {
    let coefficient = if coefficient.is_nan() {
        0.0
    } else {
        f64::from(coefficient.clamp(0.0, 1.0))
    };
    if a.capacity.0 < MIN_HEAT_CAPACITY.0 || b.capacity.0 < MIN_HEAT_CAPACITY.0 {
        return Joules::ZERO;
    }
    // A capacity may be infinite (a reservoir on this side): contributes 0
    // to the combined 1/C instead of producing an inf/inf NaN when the
    // other side is also large, so the change lands entirely on the
    // non-reservoir side, as it should.
    let inv_a = if a.capacity.0.is_finite() {
        1.0 / a.capacity.0
    } else {
        0.0
    };
    let inv_b = if b.capacity.0.is_finite() {
        1.0 / b.capacity.0
    } else {
        0.0
    };
    let inv = inv_a + inv_b;
    if inv <= 0.0 {
        // Both sides are reservoirs: no well-defined transfer.
        return Joules::ZERO;
    }
    let moved = coefficient * (a.temperature.0 - b.temperature.0) / inv;
    a.temperature = Kelvin(a.temperature.0 - moved * inv_a);
    b.temperature = Kelvin(b.temperature.0 + moved * inv_b);
    Joules(moved)
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
pub fn pair_exchange(a: ThermalBody, b: ThermalBody, conductance: f64, dt: Seconds) -> Joules {
    let inv = inverse(a.capacity.0) + inverse(b.capacity.0);
    if inv <= 0.0 || conductance.is_nan() || conductance <= 0.0 || dt.0.is_nan() || dt.0 <= 0.0 {
        return Joules::ZERO;
    }
    let fraction = -(-conductance * inv * dt.0).exp_m1();
    let moved = (a.temperature.0 - b.temperature.0) / inv * fraction;
    Joules(if moved.is_finite() { moved } else { 0.0 })
}

/// As [`pair_exchange`], with the pair's relaxation rate (1/s) given
/// directly instead of a conductance: `ΔT · h · (1 − e^(−rate dt))`.
#[must_use]
pub fn pair_exchange_at_rate(a: ThermalBody, b: ThermalBody, rate: f64, dt: Seconds) -> Joules {
    let inv = inverse(a.capacity.0) + inverse(b.capacity.0);
    if inv <= 0.0 || rate.is_nan() || rate <= 0.0 || dt.0.is_nan() || dt.0 <= 0.0 {
        return Joules::ZERO;
    }
    let fraction = -(-rate * dt.0).exp_m1();
    let moved = (a.temperature.0 - b.temperature.0) / inv * fraction;
    Joules(if moved.is_finite() { moved } else { 0.0 })
}

/// [`pair_exchange`] for laws working on `f32` columns: energy (J) moved
/// from side `a` (`ta` K, `ca` J/K) to side `b` over `dt` s by conductance
/// `g` W/K. A reservoir side passes `f32::INFINITY` as its capacity.
#[must_use]
#[allow(clippy::cast_possible_truncation)]
pub fn pair_exchange_f32(ta: f32, ca: f32, tb: f32, cb: f32, g: f32, dt: f32) -> f32 {
    let a = ThermalBody::new(HeatCapacity::from(ca), Kelvin::from(ta));
    let b = ThermalBody::new(HeatCapacity::from(cb), Kelvin::from(tb));
    pair_exchange(a, b, f64::from(g), Seconds::from(dt)).0 as f32
}

/// [`pair_exchange_at_rate`] for laws working on `f32` columns.
#[must_use]
#[allow(clippy::cast_possible_truncation)]
pub fn pair_exchange_at_rate_f32(ta: f32, ca: f32, tb: f32, cb: f32, rate: f32, dt: f32) -> f32 {
    let a = ThermalBody::new(HeatCapacity::from(ca), Kelvin::from(ta));
    let b = ThermalBody::new(HeatCapacity::from(cb), Kelvin::from(tb));
    pair_exchange_at_rate(a, b, f64::from(rate), Seconds::from(dt)).0 as f32
}

/// A phase plateau: heating through `temperature` first fills `latent`
/// joules at constant temperature (and cooling empties it). The default
/// (`latent == 0`) is no plateau.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Phase {
    /// K.
    pub temperature: f32,
    /// J.
    pub latent: f32,
}

impl Phase {
    #[must_use]
    pub fn is_active(&self) -> bool {
        self.latent > 0.0 && self.temperature > 0.0
    }
}

/// Temperature (K) of `energy` J in a body of `capacity` J/K with `phase`:
/// sensible heat below the plateau, the plateau temperature while it
/// fills, sensible heat above it. `0` for a non-positive capacity.
#[must_use]
pub fn phase_temperature(energy: f32, capacity: f32, phase: Phase) -> f32 {
    if capacity <= 0.0 {
        return 0.0;
    }
    if !phase.is_active() {
        return energy / capacity;
    }
    let at_phase = capacity * phase.temperature;
    if energy <= at_phase {
        energy / capacity
    } else if energy <= at_phase + phase.latent {
        phase.temperature
    } else {
        (energy - phase.latent) / capacity
    }
}

/// Energy (J) of a body at `temperature`: the plateau is empty at exactly
/// the phase temperature and full above it, so
/// `phase_temperature(phase_energy(t)) == t`.
#[must_use]
pub fn phase_energy(temperature: f32, capacity: f32, phase: Phase) -> f32 {
    let sensible = capacity * temperature;
    if phase.is_active() && temperature > phase.temperature {
        sensible + phase.latent
    } else {
        sensible
    }
}

/// The exact relaxation of a body toward a reservoir-like environment:
/// `T(t) = T_inf + (T0 - T_inf)·e^(-(g/c)·elapsed)` with
/// `T_inf = ambient + power/g` (a power source shifts the asymptote). The
/// closed form [`pair_exchange`] integrates against a reservoir, so using it
/// instead of stepping is a performance choice, not different physics.
/// `g <= 0` or `c <= 0` returns `t0` unchanged. The same curve as
/// [`crate::rate::RateModel::Relax`] with `k = g/c`.
#[must_use]
#[allow(clippy::cast_possible_truncation)]
pub fn relax_toward(t0: f32, ambient: f32, power: f32, conductance: f32, capacity: f32, elapsed: f32) -> f32 {
    if conductance <= 0.0 || capacity <= 0.0 {
        return t0;
    }
    let target = f64::from(ambient) + f64::from(power) / f64::from(conductance);
    let rate = f64::from(conductance) / f64::from(capacity);
    (target + (f64::from(t0) - target) * (-rate * f64::from(elapsed.max(0.0))).exp()) as f32
}

#[cfg(test)]
mod tests {
    #[test]
    fn phase_plateau_maps_energy_both_ways() {
        let p = Phase { temperature: 300.0, latent: 1_000.0 };
        assert_eq!(phase_temperature(100.0 * 299.0, 100.0, p), 299.0);
        assert_eq!(phase_temperature(100.0 * 300.0 + 500.0, 100.0, p), 300.0);
        assert_eq!(phase_temperature(100.0 * 301.0 + 1_000.0, 100.0, p), 301.0);
        assert_eq!(phase_energy(301.0, 100.0, p), 100.0 * 301.0 + 1_000.0);
    }

    #[test]
    fn relax_toward_approaches_the_shifted_asymptote() {
        let t = relax_toward(400.0, 300.0, 100.0, 10.0, 1_000.0, 1e6);
        assert!((t - 310.0).abs() < 1e-3, "{t}");
        assert_eq!(relax_toward(400.0, 300.0, 0.0, 0.0, 1.0, 10.0), 400.0);
    }

    #[test]
    fn f32_forms_match_the_unit_forms() {
        let moved = pair_exchange_f32(400.0, 100.0, 200.0, 100.0, 10.0, 3.0);
        let expect = 200.0 * 50.0 * (1.0 - (-0.6f64).exp());
        assert!((f64::from(moved) - expect).abs() < 1e-2);
        let moved = pair_exchange_at_rate_f32(400.0, 100.0, 200.0, 100.0, 0.2, 3.0);
        assert!((f64::from(moved) - expect).abs() < 1e-2);
    }

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
        assert!(f64::abs(before - after) < 0.5);
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
            ca in 0.01f64..1e6, cb in 0.01f64..1e6,
            ta in 0.0f64..1e5, tb in 0.0f64..1e5,
            k in -0.5f32..1.5,
        ) {
            let mut a = ThermalBody::new(HeatCapacity(ca), Kelvin(ta));
            let mut b = ThermalBody::new(HeatCapacity(cb), Kelvin(tb));
            let before = ca * ta + cb * tb;
            exchange(&mut a, &mut b, k);
            let after = ca * a.temperature.0 + cb * b.temperature.0;
            // Only f64 rounding is lost, negligible next to the magnitudes here.
            let tolerance = 2.0 * f64::EPSILON * (ca + cb) * ta.max(tb).max(1.0);
            prop_assert!((before - after).abs() <= tolerance, "{before} vs {after}");
            let (lo, hi) = (ta.min(tb), ta.max(tb));
            let slack = hi * 1e-9;
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
            bodies in prop::collection::vec((1.0f64..1e4, 1.0f64..1e4), 2..16),
            pairs in prop::collection::vec((any::<prop::sample::Index>(), any::<prop::sample::Index>(), 0.0f32..1.0), 0..200),
        ) {
            let mut bodies: Vec<_> = bodies.into_iter()
                .map(|(c, t)| ThermalBody::new(HeatCapacity(c), Kelvin(t))).collect();
            let total = |bs: &[ThermalBody]| bs.iter()
                .map(|b| b.capacity.0 * b.temperature.0).sum::<f64>();
            let before = total(&bodies);
            for (i, j, k) in pairs {
                let (i, j) = (i.index(bodies.len()), j.index(bodies.len()));
                if i == j { continue; }
                let (lo, hi) = (i.min(j), i.max(j));
                let (left, right) = bodies.split_at_mut(hi);
                exchange(&mut left[lo], &mut right[0], k);
            }
            let after = total(&bodies);
            prop_assert!((before - after).abs() / before < 1e-9, "{before} vs {after}");
        }
    }

    /// Carried over from vg-heat `couple.rs`, where `pair_exchange`/
    /// `pair_exchange_at_rate` lived before the dedup (`rust_core.md` §15).
    #[test]
    fn exact_exchange_matches_the_closed_form() {
        // Equal capacities: the gap halves at rate 2g/C.
        let a = ThermalBody::new(HeatCapacity(100.0), Kelvin(400.0));
        let b = ThermalBody::new(HeatCapacity(100.0), Kelvin(200.0));
        let moved = pair_exchange(a, b, 10.0, Seconds(3.0));
        let expect = 200.0 * 50.0 * (1.0 - (-0.6f64).exp());
        assert!((moved.0 - expect).abs() < 1e-3, "{} vs {expect}", moved.0);
        // A reservoir: harmonic -> the body's capacity.
        let a = ThermalBody::new(HeatCapacity(100.0), Kelvin(400.0));
        let b = ThermalBody::new(HeatCapacity(f64::INFINITY), Kelvin(300.0));
        let moved = pair_exchange(a, b, 10.0, Seconds(1e6));
        assert!((moved.0 - 10_000.0).abs() < 1e-2);
    }

    proptest! {
        /// Any step size: never overshoots, and applying +/-moved conserves.
        #[test]
        fn pair_exchange_never_overshoots(
            ta in 3.0f64..5000.0, tb in 3.0f64..5000.0,
            ca in 0.01f64..1e6, cb in 0.01f64..1e6,
            g in 0.0f64..1e5, dt in 0.0f64..1e4,
        ) {
            let a = ThermalBody::new(HeatCapacity(ca), Kelvin(ta));
            let b = ThermalBody::new(HeatCapacity(cb), Kelvin(tb));
            let m = pair_exchange(a, b, g, Seconds(dt)).0;
            let (na, nb) = (ta - m / ca, tb + m / cb);
            let (lo, hi) = (ta.min(tb), ta.max(tb));
            let slack = hi * 1e-9;
            prop_assert!(na >= lo - slack && na <= hi + slack);
            prop_assert!(nb >= lo - slack && nb <= hi + slack);
            if ta >= tb { prop_assert!(na + slack >= nb); } else { prop_assert!(nb + slack >= na); }
            let before = ca * ta + cb * tb;
            let after = (ca * ta - m) + (cb * tb + m);
            prop_assert!((before - after).abs() <= before * 1e-12);
        }
    }
}
