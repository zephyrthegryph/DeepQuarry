//! The mob heat body (H2): the energy-integrator thermal model for DQ
//! Medical, per `doc/rewrite/temperature.md` and the R10 component model
//! (`rust_bindings.md`). Ported onto the driver as a plain component
//! (`rust_architecture.md` §6, §8.5): `MobHeat` was already written against
//! `Law`/`LawCtx` (see [`MobHeatFlux`]) as a preview of this shape, so this
//! file only replaces the hand-rolled host (`MobHeatWorld`, its slot table
//! and generation-checked handles) with `#[vg::component]`'s generic
//! entity/watch/accessor machinery -- the flux integration itself
//! ([`step`]) is unchanged.
//!
//! One model, every body plan (humanoid, simple, machine/robot, ...),
//! differing only in config: a robot zeroes `metabolic_watts` and sets
//! `coolant` instead. State is core temperature plus heat capacity; every
//! input is a **flux in watts**, integrated over `dt * time_scale` (never a
//! per-tick °C delta, `temperature.md` §2.1's energy-based rule):
//!
//! - metabolic production (`metabolic_watts`, zero on a robot);
//! - conduction to the environment through `insulation` (W/K: DQ Medical
//!   aggregates per-limb worn-protection into this one number);
//! - up to [`MOB_EXTERNAL_SOURCES`] independent external fluxes (reagents,
//!   cryo, bellies, items, afflictions), each set by DM's own generic
//!   `external_watts` array accessor and persisting (like a rate, not a
//!   one-shot amount) until the source updates or zeroes it;
//! - thermoregulation: a proportional controller driving the body toward
//!   `setpoint`, clamped to `sweat_capacity_w`/`shiver_capacity_w`.
//!
//! Comfort-band crossings are ordinary generic watches on the `temperature`
//! field (any numeric `#[vg::component]` field is watchable,
//! `rust_architecture.md` §4.8) -- nothing bespoke, and no separate
//! `MobHeatWorld::set_bands` call: DM registers a `Band` condition through
//! the same `vg_world_watch`-style bind every other component uses.

use vg_core::law::{Law, LawCtx, Settle};
use vg_core::units::Seconds;
use vg_core::vg;

use crate::consts::TCMB;

/// Independent external heat flux slots (DM's `set_external_watts(source,
/// watts)`): reagents, cryo, bellies, items, afflictions can each hold one
/// without clobbering the others.
pub const MOB_EXTERNAL_SOURCES: usize = 8;

/// A mob heat body's config and state.
#[vg::component(domain = heat, kind = 6, dm = "/atom/movable/vg_heat_mob", owner = worker)]
pub struct MobHeat {
    /// J/K.
    #[vg(config, unit = "J/K", range = 0.0001..=1000000000.0, default = 1.0, on_invalid = clamp)]
    pub capacity: f64,
    #[vg(state, unit = "K", range = 0.0..=1000000.0, default = 310.15, on_invalid = clamp)]
    pub temperature: f64,
    /// W; zero on a body with `coolant` set.
    #[vg(config, unit = "W", range = -1000000.0..=1000000.0, default = 0.0, on_invalid = clamp)]
    pub metabolic_watts: f64,
    /// A machine body: no metabolic heat, a coolant loop is itself a flux
    /// source (added through `external_watts`) rather than a second
    /// built-in term, so it composes with everything else instead of
    /// special-casing robots in [`step`].
    #[vg(config, default = false)]
    pub coolant: bool,
    /// Aggregate conductance to `ambient`, W/K.
    #[vg(config, unit = "W/K", range = 0.0..=1000000.0, default = 0.0, on_invalid = clamp)]
    pub insulation: f64,
    /// K; DM pushes this from the body's local environment.
    #[vg(config, unit = "K", range = 0.0..=1000000.0, default = 310.15, on_invalid = clamp)]
    pub ambient: f64,
    /// K; thermoregulation's target.
    #[vg(config, unit = "K", range = 0.0..=1000000.0, default = 310.15, on_invalid = clamp)]
    pub setpoint: f64,
    /// Max active cooling effort, W.
    #[vg(config, unit = "W", range = 0.0..=1000000.0, default = 0.0, on_invalid = clamp)]
    pub sweat_capacity_w: f64,
    /// Max active heating effort, W.
    #[vg(config, unit = "W", range = 0.0..=1000000.0, default = 0.0, on_invalid = clamp)]
    pub shiver_capacity_w: f64,
    /// Stasis/body-clock rate multiplier on `dt`. Zero freezes the body
    /// exactly.
    #[vg(config, range = 0.0..=100.0, default = 1.0, on_invalid = clamp)]
    pub time_scale: f64,
    #[vg(config, unit = "W", range = -1000000.0..=1000000.0, default = [0.0; 8], on_invalid = clamp)]
    pub external_watts: [f64; MOB_EXTERNAL_SOURCES],
}

/// Thermoregulation gain, W/K: how hard the controller pushes per kelvin of
/// error before the sweat/shiver capacity clamps it. A config field (not a
/// fixed constant) is a natural follow-up once DQ Medical's strategies need
/// per-species tuning; today it's shared, matching "one model... differing
/// only in config" for every *other* field.
const THERMOREG_GAIN_W_PER_K: f64 = 40.0;

/// One frame's flux integration for a live body. `dt_eff = dt * time_scale`,
/// so `time_scale == 0` changes nothing.
fn step(b: &mut MobHeat, dt: f64) {
    let metabolic = if b.coolant { 0.0 } else { b.metabolic_watts };
    let conduction = b.insulation * (b.ambient - b.temperature);
    let error = b.setpoint - b.temperature;
    let effort = (error * THERMOREG_GAIN_W_PER_K).clamp(-b.sweat_capacity_w, b.shiver_capacity_w);
    let external: f64 = b.external_watts.iter().sum();
    let total_w = metabolic + conduction + effort + external;
    let dt_eff = dt * b.time_scale;
    if dt_eff > 0.0 && b.capacity > 0.0 {
        b.temperature = (b.temperature + total_w * dt_eff / b.capacity).max(f64::from(TCMB));
    }
}

/// `MobHeat`'s flux integration as a [`Law`]: unchanged from the Core A
/// preview this file already had -- wraps exactly [`step`].
pub struct MobHeatFlux;
impl Law for MobHeatFlux {
    type Reads = ();
    type Writes = MobHeat;
    const NAME: &'static str = "heat_mob_flux";
    fn step(ctx: &mut LawCtx<'_, (), MobHeat>, dt: Seconds) -> Settle {
        step(ctx.writes, dt.0);
        if ctx.writes.time_scale > 0.0 {
            Settle::Active
        } else {
            Settle::Sleep
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn body() -> MobHeat {
        MobHeat {
            capacity: 280_000.0,
            temperature: 310.15,
            metabolic_watts: 100.0,
            coolant: false,
            insulation: 2.0,
            ambient: 293.15,
            setpoint: 310.15,
            sweat_capacity_w: 200.0,
            shiver_capacity_w: 200.0,
            time_scale: 1.0,
            external_watts: [0.0; MOB_EXTERNAL_SOURCES],
        }
    }

    #[test]
    fn frozen_body_does_not_change() {
        let mut b = body();
        b.time_scale = 0.0;
        let before = b.temperature;
        step(&mut b, 60.0);
        assert_eq!(b.temperature, before);
    }

    #[test]
    fn cooling_toward_ambient_stops_at_the_regulated_setpoint() {
        let mut b = body();
        b.ambient = 250.0;
        for _ in 0..20_000 {
            step(&mut b, 1.0);
        }
        assert!((b.temperature - b.setpoint).abs() < 1.0, "{}", b.temperature);
    }

    #[test]
    fn external_sources_sum_and_persist() {
        let mut b = body();
        b.metabolic_watts = 0.0;
        b.insulation = 0.0;
        b.external_watts[0] = 500.0;
        b.external_watts[3] = -100.0;
        let before = b.temperature;
        step(&mut b, 10.0);
        let expected = before + (500.0 - 100.0) * 10.0 / b.capacity;
        assert!((b.temperature - expected).abs() < 1e-6);
    }
}
