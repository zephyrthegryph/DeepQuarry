//! Heat's laws, as pure functions (`doc/rewrite/rust_architecture.md` §2/§6:
//! "domains are declarations plus laws"). Each one is `fn(inputs) -> outputs`
//! with no `Sim`, no host state and no side effect beyond its return value,
//! so it needs no driver to test and none of the framework below to be
//! correct. The `Task`-based wiring in [`crate::body`], [`crate::couple`]
//! and [`crate::world`] is today's driver (a per-domain `Sim`, per
//! `rust_architecture.md` §7's migration order: "domains write their laws as
//! pure functions with tests immediately... [and] delete their private host
//! code" once the shared `Law`/`LawCtx` driver (Core A) lands) -- every one
//! of those call sites already reduces to exactly the function below it, so
//! adopting the real driver is a wiring change, not a physics rewrite.
//!
//! - **Body↔environment exchange**: [`pair_exchange`]/[`pair_exchange_at_rate`]
//!   (conductance, or a precomputed rate, over `dt`; a reservoir passes
//!   `f32::INFINITY`), and [`relax_toward`] for the analytic path against a
//!   reservoir-like environment (`temperature.md`'s "large environment: an
//!   exponential curve, not a step").
//! - **The phase buffer**: [`phase_temperature`]/[`phase_energy`] (a phase
//!   plateau's latent-heat step).
//! - **The Regulator as a heat pump**: [`Regulator::step`] (already pure;
//!   re-exported here as the law's canonical entry point).
//! - **Coupling laws**: [`solid_gas_exchange`] (solid↔gas, conductance
//!   scaled by [`crate::consts::GAS_COUPLING`] and deadbanded by
//!   [`crate::consts::GAS_COUPLING_MIN_K`]) and [`pair_exchange`] again
//!   (body↔gas: a body's gas-target coupling is exactly a two-body exchange
//!   against the gas's temperature/capacity, so it needs no separate
//!   function -- this *is* the law, replacing `GasExchange`/`GasRef`/
//!   `GasProbe`'s job of fetching those two numbers).

use crate::body::{Phase, energy_at, temperature_of};
use crate::consts::{GAS_COUPLING, GAS_COUPLING_MIN_K};
pub use crate::couple::{pair_exchange, pair_exchange_at_rate};
pub use crate::regulator::{Regulator, RegulatorMode, RegulatorStep};

/// The phase buffer's temperature law: `energy_at(temperature_of(...))`
/// round-trips. Re-exported under the law's name; [`crate::body`]'s own
/// name (`temperature_of`) stays for its existing call sites.
#[must_use]
pub fn phase_temperature(energy: f32, capacity: f32, phase: Phase) -> f32 {
    temperature_of(energy, capacity, phase)
}

/// The phase buffer's energy law. See [`phase_temperature`].
#[must_use]
pub fn phase_energy(temperature: f32, capacity: f32, phase: Phase) -> f32 {
    energy_at(temperature, capacity, phase)
}

/// The exact exponential relaxation of a body toward a reservoir-like
/// environment: `T(t) = T_inf + (T0 - T_inf)*e^(-(g/c)*(t - t0))`, with
/// `T_inf = ambient + power/g` (a power source shifts the asymptote away
/// from the environment). `g <= 0.0` or `c <= 0.0` returns `t0_temperature`
/// unchanged (nothing to relax with).
///
/// This is the closed-form solution `pair_exchange`'s own conductance law
/// integrates exactly, so using this instead of stepping is a performance
/// choice (no work between crossings the caller cares about), not a
/// different physics -- see `body.rs`'s module docs for when each applies.
#[must_use]
pub fn relax_toward(
    t0_temperature: f32,
    ambient: f32,
    power: f32,
    conductance: f32,
    capacity: f32,
    elapsed: f32,
) -> f32 {
    if conductance <= 0.0 || capacity <= 0.0 {
        return t0_temperature;
    }
    let target = ambient + power / conductance;
    let rate = f64::from(conductance) / f64::from(capacity);
    #[allow(clippy::cast_possible_truncation)]
    let value = target as f64
        + (f64::from(t0_temperature) - f64::from(target))
            * (-rate * f64::from(elapsed.max(0.0))).exp();
    #[allow(clippy::cast_possible_truncation)]
    {
        value as f32
    }
}

/// The solid↔gas coupling law: exact exchange at
/// `rate = GAS_COUPLING * conductivity`, deadbanded so pairs already within
/// [`GAS_COUPLING_MIN_K`] of each other don't churn every frame for no
/// visible effect. Returns the energy moved from the solid to the gas (as
/// [`pair_exchange_at_rate`]'s sign convention: positive leaves the solid).
/// `gas_capacity` is `f32::INFINITY` for a reservoir gas (space, a planet's
/// atmosphere).
#[must_use]
pub fn solid_gas_exchange(
    solid_temperature: f32,
    solid_capacity: f32,
    conductivity: f32,
    gas_temperature: f32,
    gas_capacity: f32,
    dt: f32,
) -> f32 {
    if conductivity <= 0.0 || (solid_temperature - gas_temperature).abs() < GAS_COUPLING_MIN_K {
        return 0.0;
    }
    let rate = GAS_COUPLING * conductivity;
    pair_exchange_at_rate(
        solid_temperature,
        solid_capacity,
        gas_temperature,
        gas_capacity,
        rate,
        dt,
    )
}

/// The Regulator as a heat pump: `work` electrical W drawn moves
/// `step.moved` J into the controlled body and `step.other` J into (or out
/// of, for pumped heating) the other side, `work == moved + (-other)` up to
/// rounding (heating) or `work + moved.abs() == other` (cooling, rejecting
/// `Q + W`). See [`Regulator::step`]'s own docs for the exact per-mode
/// formulas; this function exists so the law has one name alongside the
/// others in this module.
#[must_use]
pub fn regulator_step(
    regulator: &Regulator,
    controlled_temperature: f32,
    controlled_capacity: f32,
    other_temperature: f32,
    other_capacity: f32,
    dt: f32,
) -> RegulatorStep {
    use vg_core::thermo::ThermalBody;
    use vg_core::units::{HeatCapacity, Kelvin};
    let controlled = ThermalBody::new(
        HeatCapacity::from(controlled_capacity),
        Kelvin::from(controlled_temperature),
    );
    let other = ThermalBody::new(
        HeatCapacity::from(other_capacity),
        Kelvin::from(other_temperature),
    );
    regulator.step(controlled, other, dt)
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    #[test]
    fn phase_law_round_trips_through_the_plateau() {
        let phase = Phase {
            temperature: 273.15,
            latent: 500.0,
        };
        // Below the plateau: sensible heat only.
        assert!(
            (phase_temperature(phase_energy(260.0, 10.0, phase), 10.0, phase) - 260.0).abs() < 1e-3
        );
        // On the plateau: energy absorbed without a temperature change.
        assert_eq!(
            phase_temperature(phase_energy(273.15, 10.0, phase) + 250.0, 10.0, phase),
            273.15
        );
        // Above the plateau: sensible heat resumes.
        assert!(
            (phase_temperature(phase_energy(300.0, 10.0, phase), 10.0, phase) - 300.0).abs() < 1e-3
        );
    }

    #[test]
    fn relax_toward_a_reservoir_matches_the_stepped_exchange_in_the_limit() {
        // Many small steps of the exact stepped law should approach the
        // same value the closed-form relaxation gives directly, for a
        // reservoir environment (a body's own capacity, a huge other side).
        let (t0, ambient, g, c) = (400.0_f32, 200.0_f32, 5.0_f32, 50.0_f32);
        let mut stepped = t0;
        let steps = 20_000;
        let dt = 5.0 / steps as f32;
        for _ in 0..steps {
            let moved = pair_exchange(stepped, c, ambient, f32::INFINITY, g, dt);
            stepped -= moved / c;
        }
        let closed = relax_toward(t0, ambient, 0.0, g, c, 5.0);
        assert!(
            (stepped - closed).abs() < 0.05,
            "stepped={stepped} closed={closed}"
        );
    }

    #[test]
    fn relax_toward_shifts_the_asymptote_by_power_over_conductance() {
        let (ambient, g, power) = (300.0_f32, 10.0_f32, 50.0_f32);
        // At equilibrium (t -> infinity, approximated by a long elapsed
        // time), the body settles at ambient + power/g, not at ambient.
        let settled = relax_toward(ambient, ambient, power, g, 1.0, 1e6);
        assert!(
            (settled - (ambient + power / g)).abs() < 1e-2,
            "settled={settled}"
        );
    }

    #[test]
    fn relax_toward_is_a_no_op_with_no_conductance_or_capacity() {
        assert_eq!(relax_toward(310.0, 200.0, 0.0, 0.0, 10.0, 5.0), 310.0);
        assert_eq!(relax_toward(310.0, 200.0, 0.0, 5.0, 0.0, 5.0), 310.0);
    }

    #[test]
    fn solid_gas_exchange_is_deadbanded_and_conserves() {
        // Within the deadband: no movement at all.
        assert_eq!(
            solid_gas_exchange(300.0, 1000.0, 0.5, 300.05, 500.0, 1.0),
            0.0
        );
        // Outside it: energy moves, and applying it to both sides (solid
        // loses what the gas gains) conserves exactly.
        let moved = solid_gas_exchange(400.0, 1000.0, 0.5, 300.0, 500.0, 1.0);
        assert!(
            moved > 0.0,
            "hot solid should move energy to cooler gas: {moved}"
        );
        let solid_after = 400.0 - moved / 1000.0;
        let gas_after = 300.0 + moved / 500.0;
        assert!(
            solid_after > gas_after,
            "must not overshoot past equilibrium: {solid_after} vs {gas_after}"
        );
    }

    #[test]
    fn solid_gas_exchange_zero_conductivity_never_moves_anything() {
        assert_eq!(
            solid_gas_exchange(500.0, 1000.0, 0.0, 200.0, 500.0, 1.0),
            0.0
        );
    }

    proptest! {
        /// The deadbanded law never overshoots equilibrium and never moves
        /// energy the wrong way (from cold to hot), for any inputs.
        #[test]
        fn solid_gas_exchange_never_overshoots_or_reverses(
            ts in 0.0f32..2000.0, cs in 1.0f32..1e5,
            tg in 0.0f32..2000.0, cg in 1.0f32..1e5,
            k in 0.0f32..2.0, dt in 0.001f32..10.0,
        ) {
            let moved = solid_gas_exchange(ts, cs, k, tg, cg, dt);
            if ts >= tg {
                prop_assert!(moved >= 0.0, "hot-to-cold must not reverse: {moved}");
            } else {
                prop_assert!(moved <= 0.0);
            }
            let solid_after = ts - moved / cs;
            let gas_after = tg + moved / cg;
            let (lo, hi) = (ts.min(tg), ts.max(tg));
            let slack = hi * 1e-4 + 1e-3;
            prop_assert!(solid_after >= lo - slack && solid_after <= hi + slack, "solid overshot: {solid_after}");
            prop_assert!(gas_after >= lo - slack && gas_after <= hi + slack, "gas overshot: {gas_after}");
        }
    }
}
