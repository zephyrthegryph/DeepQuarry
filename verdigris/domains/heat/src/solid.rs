//! The turf solid heat field (replaces vg-gas `superconduct.rs`).
//!
//! One [`SolidCell`] per turf on R6's field framework: the conserved energy
//! (J), the temperature cached for channels, and the material values DM
//! sends (conductivity, emissivity, flags). The heat capacity is the
//! geometry's capacity ([`GeomCmd::Capacity`](vg_core::field::GeomCmd)).
//!
//! # Edges
//! - **Solid ↔ solid** (and solid ↔ planet reservoir): conduction with
//!   conductance `G = min(k_a, k_b) · C_a C_b / (C_a + C_b)` W/K, where `k`
//!   is DM's `thermal_conductivity` (a fraction of the way to equilibrium
//!   per second). This is today's superconduct.rs law, now integrated by
//!   the framework's monotone sub-steps and clamped to the pair
//!   equilibrium; its stiffness is just `min(k_a, k_b)`.
//! - **Solid ↔ space**: Stefan–Boltzmann radiation, `ε σ A (T⁴ − T_sky⁴)`
//!   ([`SPACE_SKY_TEMPERATURE`]). Vacuum does not conduct.
//!
//! # Deliberate changes from superconduct.rs
//! - Neighbours are bounds-checked (B1 fixed in R2's grid): no heat across
//!   the map's east/west edge or from the top row into the next z-level.
//! - Space exposure is a radiation edge to a reservoir cell instead of a
//!   conduction share against a fake 7000 J/K vacuum, and it runs in both
//!   directions (it used to apply only above 20 °C).
//! - Nothing is gated on 303 K: every unsettled edge flows, and settled
//!   regions sleep (so an idle map costs nothing).
//! - Energy is conserved per step (reservoir inflow is in the ledger); the
//!   old `to_be_destroyed` write and the 102 K / 300 K sentinels are gone.

use vg_core::field::kernel::{Operand, conduction, exchange_stiffness};
use vg_core::field::{FieldKind, Side};
use vg_core::owner::{Applied, Domain};

use crate::consts::{
    RADIATING_AREA, SOLID_SETTLED_K, SPACE_SKY_TEMPERATURE, STEFAN_BOLTZMANN, TCMB,
};

/// Cell flags DM sends with the material values.
pub mod flags {
    /// A space reservoir: neighbours radiate into it.
    pub const SPACE: u8 = 1;
    /// The turf has air: the cell couples to its turf gas.
    pub const AIR: u8 = 2;
    /// A planet reservoir: neighbours conduct into it at its temperature.
    pub const PLANET: u8 = 4;
}

/// One turf's solid heat.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct SolidCell {
    /// Conserved energy, J.
    pub energy: f32,
    /// `energy / capacity`, cached after every step (channels read it).
    pub temperature: f32,
    /// DM `thermal_conductivity`: fraction of the way to equilibrium per
    /// second across a face.
    pub conductivity: f32,
    /// Radiative emissivity of a face exposed to space, 0..1.
    pub emissivity: f32,
    pub flags: u8,
}

impl SolidCell {
    #[must_use]
    pub fn at(
        capacity: f32,
        temperature: f32,
        conductivity: f32,
        emissivity: f32,
        flags: u8,
    ) -> Self {
        Self {
            energy: capacity * temperature,
            temperature,
            conductivity,
            emissivity,
            flags,
        }
    }

    /// The temperature for `capacity` (the cached value for a non-node).
    #[must_use]
    pub fn temperature_in(&self, capacity: f32) -> f32 {
        if capacity > 0.0 {
            self.energy / capacity
        } else {
            self.temperature
        }
    }

    #[must_use]
    pub const fn has(&self, flag: u8) -> bool {
        self.flags & flag != 0
    }
}

/// Sources, sinks and material updates, computed on the main thread.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum SolidCmd {
    /// Adds energy (negative removes); clamps at zero energy and reports
    /// the shortfall.
    Add(f32),
    /// Sets the temperature (DM authority: map load, admin, holodeck).
    Set { temperature: f32, capacity: f32 },
    /// Material values.
    Props {
        conductivity: f32,
        emissivity: f32,
        flags: u8,
    },
    /// The capacity changes from `from` to `to` (a new wall material):
    /// the temperature is kept.
    Rescale { from: f32, to: f32 },
}

/// The solid heat field.
pub struct SolidHeat;

impl Domain for SolidHeat {
    type Value = SolidCell;
    type Command = SolidCmd;
    const NAME: &'static str = "heat";

    fn apply(value: &mut SolidCell, cmd: &SolidCmd) -> Applied {
        match *cmd {
            SolidCmd::Add(e) => {
                let next = value.energy + e;
                if next < 0.0 || !next.is_finite() {
                    let shortfall = if next.is_finite() { -next } else { 0.0 };
                    value.energy = 0.0;
                    return Applied { shortfall };
                }
                value.energy = next;
            }
            SolidCmd::Set {
                temperature,
                capacity,
            } => {
                let t = temperature.max(TCMB);
                value.temperature = t;
                value.energy = capacity.max(0.0) * t;
            }
            SolidCmd::Props {
                conductivity,
                emissivity,
                flags,
            } => {
                value.conductivity = conductivity.max(0.0);
                value.emissivity = emissivity.clamp(0.0, 1.0);
                value.flags = flags;
            }
            SolidCmd::Rescale { from, to } => {
                let t = if from > 0.0 {
                    value.energy / from
                } else {
                    value.temperature
                };
                value.temperature = t;
                value.energy = to.max(0.0) * t;
            }
        }
        Applied::default()
    }
}

fn operand<'a>(s: &Side<'a, SolidCell>) -> Operand<'a, 1> {
    Operand {
        amounts: std::array::from_ref(&s.cell.energy),
        capacity: s.capacity,
        inv_capacity: s.inv_capacity,
        share: s.share,
    }
}

fn is_space(s: &Side<'_, SolidCell>) -> bool {
    s.reservoir && s.cell.has(flags::SPACE)
}

fn temperature(s: &Side<'_, SolidCell>) -> f32 {
    if is_space(s) {
        SPACE_SKY_TEMPERATURE
    } else {
        s.cell.energy / s.capacity
    }
}

/// `C_a C_b / (C_a + C_b)`; for a reservoir side, the other side's capacity
/// weighted as superconduct.rs did (the reservoir's geometry capacity).
fn harmonic(a: f32, b: f32) -> f32 {
    let sum = a + b;
    if sum > 0.0 { a * b / sum } else { 0.0 }
}

/// Conductance of a conduction edge, W/K.
#[must_use]
pub fn edge_conductance(a: &SolidCell, ca: f32, b: &SolidCell, cb: f32) -> f32 {
    a.conductivity.min(b.conductivity).max(0.0) * harmonic(ca, cb)
}

/// Net radiated power from a body at `t` to the sky, W (negative: absorbed).
#[must_use]
pub fn radiated_power(emissivity: f32, t: f32) -> f64 {
    let (t, sky) = (f64::from(t), f64::from(SPACE_SKY_TEMPERATURE));
    f64::from(emissivity.clamp(0.0, 1.0))
        * STEFAN_BOLTZMANN
        * f64::from(RADIATING_AREA)
        * (t.powi(4) - sky.powi(4))
}

/// Energy a face radiates to space over `dt`, clamped so the body never
/// passes the sky temperature and never gives more than its share.
fn radiation(body: &Side<'_, SolidCell>, dt: f32) -> f32 {
    let t = body.cell.energy / body.capacity;
    if !t.is_finite() {
        return 0.0;
    }
    #[allow(clippy::cast_possible_truncation)]
    let q = (radiated_power(body.cell.emissivity, t) * f64::from(dt)) as f32;
    // The reservoir's inverse capacity is 0: the equilibrium is the sky's.
    let limit = (t - SPACE_SKY_TEMPERATURE) * body.capacity;
    let q = if !q.is_finite() || !limit.is_finite() {
        0.0
    } else if q.abs() > limit.abs() {
        limit
    } else {
        q
    };
    if q > 0.0 {
        q.min((body.cell.energy * body.share).max(0.0))
    } else {
        q
    }
}

impl FieldKind for SolidHeat {
    const GEOMETRY_NAME: &'static str = "heat_geometry";
    const QUANTITIES: usize = 1;
    const QUANTITY_NAMES: &'static [&'static str] = &["heat_energy"];
    const BLOCK: vg_core::grid::BlockKind = vg_core::grid::BlockKind::Heat;
    type Flux = f32;

    fn flux(a: Side<'_, SolidCell>, b: Side<'_, SolidCell>, dt: f32) -> f32 {
        match (is_space(&a), is_space(&b)) {
            (true, true) => 0.0,
            (false, true) => radiation(&a, dt),
            (true, false) => -radiation(&b, dt),
            (false, false) => {
                let g = edge_conductance(a.cell, a.capacity, b.cell, b.capacity);
                conduction(operand(&a), operand(&b), g, dt)
            }
        }
    }

    fn apply_flux(cell: &mut SolidCell, flux: f32) {
        cell.energy += flux;
    }

    fn settled(a: Side<'_, SolidCell>, b: Side<'_, SolidCell>) -> bool {
        (temperature(&a) - temperature(&b)).abs() < SOLID_SETTLED_K
    }

    fn stiffness(a: Side<'_, SolidCell>, b: Side<'_, SolidCell>) -> f32 {
        let radiating = |s: &Side<'_, SolidCell>| {
            let t = f64::from(s.cell.energy / s.capacity).max(0.0);
            #[allow(clippy::cast_possible_truncation)]
            let d = (4.0
                * f64::from(s.cell.emissivity.clamp(0.0, 1.0))
                * STEFAN_BOLTZMANN
                * f64::from(RADIATING_AREA)
                * t.powi(3)) as f32;
            d * s.inv_capacity
        };
        match (is_space(&a), is_space(&b)) {
            (true, true) => 0.0,
            (false, true) => radiating(&a),
            (true, false) => radiating(&b),
            (false, false) => exchange_stiffness(
                edge_conductance(a.cell, a.capacity, b.cell, b.capacity),
                a.inv_capacity,
                b.inv_capacity,
            ),
        }
    }

    fn quiet(before: &SolidCell, after: &SolidCell) -> bool {
        (before.energy - after.energy).abs() <= 1e-6 * before.energy.abs().max(after.energy.abs())
    }

    fn refresh(cell: &mut SolidCell, capacity: f32) {
        cell.temperature = cell.energy / capacity;
    }

    fn totals(cell: &SolidCell, out: &mut [f64]) {
        out[0] += f64::from(cell.energy);
    }

    fn flux_totals(flux: &f32, out: &mut [f64]) {
        out[0] += f64::from(*flux);
    }
}

vg_core::channels! { pub mod solid_ch for SolidHeat {
    TEMPERATURE: Scalar<Kelvin> hysteresis 0.1 => |c, o| o[0] = c.temperature,
}}

#[cfg(test)]
mod tests {
    use super::*;

    fn side(cell: &SolidCell, capacity: f32, reservoir: bool) -> Side<'_, SolidCell> {
        Side {
            cell,
            capacity,
            inv_capacity: if reservoir { 0.0 } else { 1.0 / capacity },
            reservoir,
            share: if reservoir { f32::INFINITY } else { 0.25 },
        }
    }

    #[test]
    fn conduction_uses_the_weaker_conductivity_and_is_antisymmetric() {
        let a = SolidCell::at(10_000.0, 400.0, 0.05, 0.9, 0);
        let b = SolidCell::at(2_500.0, 300.0, 0.2, 0.9, 0);
        let f = SolidHeat::flux(side(&a, 10_000.0, false), side(&b, 2_500.0, false), 1.0);
        let r = SolidHeat::flux(side(&b, 2_500.0, false), side(&a, 10_000.0, false), 1.0);
        // G = 0.05 * 2000 = 100 W/K; 100 K for one second.
        assert!((f - 10_000.0).abs() < 1.0, "{f}");
        assert!((f + r).abs() < 1e-3);
        let s = SolidHeat::stiffness(side(&a, 10_000.0, false), side(&b, 2_500.0, false));
        assert!((s - 0.05).abs() < 1e-6, "stiffness is min(k): {s}");
    }

    #[test]
    fn space_radiates_and_never_overshoots_the_sky() {
        let hot = SolidCell::at(1_000.0, 800.0, 0.05, 1.0, 0);
        let space = SolidCell::at(7_000.0, TCMB, 0.4, 0.0, flags::SPACE);
        let q = SolidHeat::flux(side(&hot, 1_000.0, false), side(&space, 7_000.0, true), 1.0);
        let expect = STEFAN_BOLTZMANN * (800f64.powi(4) - f64::from(SPACE_SKY_TEMPERATURE).powi(4));
        assert!(
            (f64::from(q) - expect).abs() < 1e-2 * expect,
            "{q} vs {expect}"
        );
        assert_eq!(
            SolidHeat::flux(side(&space, 7_000.0, true), side(&hot, 1_000.0, false), 1.0),
            -q
        );
        // A tiny body cannot radiate past the sky temperature in one step.
        let tiny = SolidCell::at(0.01, 800.0, 0.05, 1.0, 0);
        let q = SolidHeat::flux(side(&tiny, 0.01, false), side(&space, 7_000.0, true), 1.0);
        assert!(tiny.energy - q >= 0.01 * SPACE_SKY_TEMPERATURE - 1e-3);
        // At the sky temperature nothing flows and the edge is settled.
        let room = SolidCell::at(1_000.0, SPACE_SKY_TEMPERATURE, 0.05, 1.0, 0);
        assert!(SolidHeat::settled(
            side(&room, 1_000.0, false),
            side(&space, 7_000.0, true)
        ));
    }

    #[test]
    fn commands_clamp_and_rescale() {
        let mut c = SolidCell::at(100.0, 300.0, 0.05, 0.9, 0);
        let a = SolidHeat::apply(&mut c, &SolidCmd::Add(-40_000.0));
        assert_eq!(c.energy, 0.0);
        assert_eq!(a.shortfall, 10_000.0);
        let mut c = SolidCell::at(100.0, 300.0, 0.05, 0.9, 0);
        SolidHeat::apply(
            &mut c,
            &SolidCmd::Rescale {
                from: 100.0,
                to: 400.0,
            },
        );
        assert_eq!(c.energy, 120_000.0);
        assert_eq!(c.temperature, 300.0);
    }
}
