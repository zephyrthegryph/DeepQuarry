//! Reference toy fields: solid heat conduction and a two-component gas.
//! Used by the framework's tests and benches, and as worked examples for
//! the real heat (M4) and gas (M1b) fields.

use super::kernel::{
    Amounts, Operand, conduction, diffusion, exchange_stiffness, pressure_flow, pressure_stiffness,
};
use super::{FieldKind, Side};
use crate::owner::{Applied, Domain};

/// Equal up to a few `f32` ulps: a step's change that is rounding noise.
fn close(a: f32, b: f32) -> bool {
    (a - b).abs() <= 1e-6 * a.abs().max(b.abs())
}

/// Conductance of every heat edge, W/K.
pub const HEAT_CONDUCTANCE: f32 = 1.0;
/// A heat edge sleeps below this temperature difference, K.
pub const HEAT_SETTLED_K: f32 = 0.01;

/// One cell of the toy heat field: energy (J), and the temperature (K)
/// cached by `refresh` for channels.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct HeatCell {
    pub energy: f32,
    pub temperature: f32,
}

impl HeatCell {
    #[must_use]
    pub fn at(capacity: f32, temperature: f32) -> Self {
        Self {
            energy: capacity * temperature,
            temperature,
        }
    }
}

/// Heat sources and sinks (absolute amounts, computed on the main thread).
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum HeatCmd {
    Add(f32),
    /// Clamps at zero energy and reports the shortfall.
    Remove(f32),
}

/// The toy heat field.
pub struct HeatToy;

impl Domain for HeatToy {
    type Value = HeatCell;
    type Command = HeatCmd;
    const NAME: &'static str = "toy_heat";

    fn apply(value: &mut HeatCell, cmd: &HeatCmd) -> Applied {
        match *cmd {
            HeatCmd::Add(e) => {
                value.energy += e;
                Applied::default()
            }
            HeatCmd::Remove(e) => {
                let taken = e.min(value.energy).max(0.0);
                value.energy -= taken;
                Applied {
                    shortfall: e - taken,
                }
            }
        }
    }
}

fn heat_operand<'a>(s: &Side<'a, HeatCell>) -> Operand<'a, 1> {
    Operand {
        amounts: std::array::from_ref(&s.cell.energy),
        capacity: s.capacity,
        inv_capacity: s.inv_capacity,
        share: s.share,
    }
}

impl FieldKind for HeatToy {
    const GEOMETRY_NAME: &'static str = "toy_heat_geometry";
    const QUANTITIES: usize = 1;
    type Flux = f32;

    fn flux(a: Side<'_, HeatCell>, b: Side<'_, HeatCell>, dt: f32) -> f32 {
        conduction(heat_operand(&a), heat_operand(&b), HEAT_CONDUCTANCE, dt)
    }

    fn apply_flux(cell: &mut HeatCell, flux: f32) {
        cell.energy += flux;
    }

    fn settled(a: Side<'_, HeatCell>, b: Side<'_, HeatCell>) -> bool {
        (a.cell.energy / a.capacity - b.cell.energy / b.capacity).abs() < HEAT_SETTLED_K
    }

    fn stiffness(a: Side<'_, HeatCell>, b: Side<'_, HeatCell>) -> f32 {
        exchange_stiffness(HEAT_CONDUCTANCE, a.inv_capacity, b.inv_capacity)
    }

    fn quiet(before: &HeatCell, after: &HeatCell) -> bool {
        close(before.energy, after.energy)
    }

    fn refresh(cell: &mut HeatCell, capacity: f32) {
        cell.temperature = cell.energy / capacity;
    }

    fn totals(cell: &HeatCell, out: &mut [f64]) {
        out[0] += f64::from(cell.energy);
    }

    fn flux_totals(flux: &f32, out: &mut [f64]) {
        out[0] += f64::from(*flux);
    }
}

crate::channels! { pub mod heat_ch for HeatToy {
    ENERGY: Scalar<Joules> hysteresis 0.5 => |c, o| o[0] = c.energy,
    TEMPERATURE: Scalar<Kelvin> hysteresis 0.1 => |c, o| o[0] = c.temperature,
}}

/// Molar heat capacity of the toy gas (R = 1): `p = R * E / (CV * V)`.
pub const GAS_CV: f32 = 1.5;
/// Bulk-flow conductance, moles per second per unit pressure.
pub const GAS_FLOW: f32 = 0.002;
/// Diffusion coefficient of every component (and energy density).
pub const GAS_DIFFUSION: f32 = 0.05;

/// One cell of the toy gas: moles of A, moles of B and energy, plus the
/// pressure `refresh` caches for channels.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct GasCell {
    pub amounts: [f32; 3],
    pub pressure: f32,
}

impl GasCell {
    #[must_use]
    pub fn moles(&self) -> f32 {
        self.amounts[0] + self.amounts[1]
    }

    #[must_use]
    pub fn pressure_in(&self, volume: f32) -> f32 {
        self.amounts[2] / (GAS_CV * volume)
    }
}

/// Gas sources and sinks: add or remove absolute amounts (removal clamps
/// per component and reports the total shortfall).
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum GasCmd {
    Add([f32; 3]),
    Remove([f32; 3]),
}

/// The toy two-component gas field.
pub struct GasToy;

impl Domain for GasToy {
    type Value = GasCell;
    type Command = GasCmd;
    const NAME: &'static str = "toy_gas";

    fn apply(value: &mut GasCell, cmd: &GasCmd) -> Applied {
        match *cmd {
            GasCmd::Add(a) => {
                for (v, x) in value.amounts.iter_mut().zip(a) {
                    *v += x;
                }
                Applied::default()
            }
            GasCmd::Remove(a) => {
                let mut shortfall = 0.0;
                for (v, x) in value.amounts.iter_mut().zip(a) {
                    let taken = x.min(*v).max(0.0);
                    *v -= taken;
                    shortfall += x - taken;
                }
                Applied { shortfall }
            }
        }
    }
}

fn gas_operand<'a>(s: &Side<'a, GasCell>) -> Operand<'a, 3> {
    Operand {
        amounts: &s.cell.amounts,
        capacity: s.capacity,
        inv_capacity: s.inv_capacity,
        share: s.share,
    }
}

fn dp_dn(s: &Side<'_, GasCell>) -> f32 {
    let n = s.cell.moles();
    if s.reservoir || n <= 0.0 {
        0.0
    } else {
        s.cell.pressure_in(s.capacity) / n
    }
}

impl FieldKind for GasToy {
    const GEOMETRY_NAME: &'static str = "toy_gas_geometry";
    const QUANTITIES: usize = 3;
    type Flux = Amounts<3>;

    fn flux(a: Side<'_, GasCell>, b: Side<'_, GasCell>, dt: f32) -> Amounts<3> {
        let (oa, ob) = (gas_operand(&a), gas_operand(&b));
        let (pa, pb) = (
            a.cell.pressure_in(a.capacity),
            b.cell.pressure_in(b.capacity),
        );
        // Two kernels: each may take half of a donor's share.
        let (oa, ob) = (oa.with_share(0.5), ob.with_share(0.5));
        pressure_flow(oa, pa, ob, pb, 2, GAS_FLOW, dt) + diffusion(oa, ob, GAS_DIFFUSION, dt)
    }

    fn apply_flux(cell: &mut GasCell, flux: Amounts<3>) {
        for (v, f) in cell.amounts.iter_mut().zip(flux.0) {
            *v += f;
        }
    }

    fn settled(a: Side<'_, GasCell>, b: Side<'_, GasCell>) -> bool {
        (0..3).all(|i| {
            let (ca, cb) = (
                a.cell.amounts[i] / a.capacity,
                b.cell.amounts[i] / b.capacity,
            );
            (ca - cb).abs() <= 1e-4 * ca.abs().max(cb.abs()).max(1e-3)
        })
    }

    fn stiffness(a: Side<'_, GasCell>, b: Side<'_, GasCell>) -> f32 {
        pressure_stiffness(GAS_FLOW, dp_dn(&a), dp_dn(&b))
            + exchange_stiffness(GAS_DIFFUSION, a.inv_capacity, b.inv_capacity)
    }

    fn quiet(before: &GasCell, after: &GasCell) -> bool {
        before
            .amounts
            .iter()
            .zip(after.amounts)
            .all(|(&a, b)| close(a, b))
    }

    fn refresh(cell: &mut GasCell, capacity: f32) {
        cell.pressure = cell.pressure_in(capacity);
    }

    fn totals(cell: &GasCell, out: &mut [f64]) {
        for (o, v) in out.iter_mut().zip(cell.amounts) {
            *o += f64::from(v);
        }
    }

    fn flux_totals(flux: &Amounts<3>, out: &mut [f64]) {
        flux.add_to(out);
    }
}

crate::channels! { pub mod gas_ch for GasToy {
    PRESSURE: Scalar<Kpa> hysteresis 0.1 => |c, o| o[0] = c.pressure,
    MOLES: Vector(2)<Moles> hysteresis 0.01 => |c, o| o.copy_from_slice(&c.amounts[..2]),
}}
