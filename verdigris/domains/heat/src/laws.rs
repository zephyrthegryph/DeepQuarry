//! Heat's coupling laws (`rust_architecture.md` §6, §8.5): each of
//! [`crate::components::SolidCoupling`]/[`crate::components::BodyCoupling`]/
//! [`crate::components::GasCoupling`]/[`crate::components::Regulator`]
//! anchors one [`Law`] here, joined to the [`HeatBody`] row(s) it moves
//! energy between through [`vg_core::query::Foreign`]/
//! [`vg_core::query::Foreign2`] (and, for a solid target,
//! [`vg_core::field::law::Cell`]). The exchange math itself -- exact pair
//! exchange, the regulator's COP-limited heat pump -- is
//! [`vg_core::thermo`]; this module only wires it onto real component rows.
//!
//! Every law here is a *stepped* exchange: an exact two-body solution every
//! frame, which `temperature.md`/`body.rs` note is stable for any step size
//! and self-sleeps once a pair settles (`moved == 0.0`). The earlier
//! analytic "don't step a body that's pinned to a reservoir at all, jump
//! straight to its equilibrium time" fast path
//! (`RateModel::Relax`/`LawCtx::schedule_crossing`) is a scheduling
//! optimisation over the same physics, not a correctness requirement, and
//! is intentionally deferred to a follow-up: it needs a settle/release
//! state machine on top of these laws (waking once at the predicted
//! crossing, folding in energy added meanwhile, re-anchoring or releasing)
//! that is easiest to get right as its own change once this step's
//! component/query shape has landed and proven itself against the ported
//! tests.

use vg_core::field::law::Cell;
use vg_core::law::{Law, LawCtx, Settle};
use vg_core::query::{Foreign, Foreign2};
use vg_core::thermo::{RegulatorStep, ThermalBody, pair_exchange_f32};
use vg_core::units::{HeatCapacity, Kelvin, Seconds};

use crate::components::{BodyCoupling, GasCoupling, HeatBody, Regulator, SolidCoupling};
use crate::consts::TCMB;
use crate::couple::{GasHandle, GasProbe, GasRef};
use crate::solid::SolidHeat;

/// Adds `joules` to a body's energy, clamped at its TCMB floor
/// (`body.rs::Body::add`, ported verbatim).
fn add_body_energy(body: &mut HeatBody, joules: f64) {
    let floor = body.capacity * f64::from(TCMB);
    body.energy = (body.energy + joules).max(floor);
}

/// Body ↔ solid-cell exchange (`crate::components::SolidCoupling`).
pub struct SolidBodyExchange;
impl Law for SolidBodyExchange {
    type Reads = SolidCoupling;
    type Writes = (Foreign<SolidCoupling, HeatBody>, Foreign2<SolidCoupling, Cell<SolidHeat>>);
    const NAME: &'static str = "heat_solid_body_exchange";

    fn step(ctx: &mut LawCtx<'_, SolidCoupling, Self::Writes>, dt: Seconds) -> Settle {
        let conductance = ctx.reads.conductance;
        #[allow(clippy::cast_possible_truncation)]
        let dt32 = dt.0 as f32;
        let (body_side, cell_side) = (&mut ctx.writes.0.value, &mut ctx.writes.1.value);
        let (Some(body), Some(cell)) = (body_side.as_mut(), cell_side.as_mut()) else {
            return Settle::Sleep;
        };
        #[allow(clippy::cast_possible_truncation)]
        let (tb, cb) = (body.temperature() as f32, body.capacity as f32);
        let cc = if cell.reservoir { f32::INFINITY } else { cell.capacity };
        #[allow(clippy::cast_possible_truncation)]
        let moved = pair_exchange_f32(tb, cb, cell.value.temperature, cc, conductance as f32, dt32);
        if moved == 0.0 {
            return Settle::Sleep;
        }
        add_body_energy(body, -f64::from(moved));
        if ctx.reads.slot == 0 {
            body.flow = f64::from(moved);
        }
        if cell.reservoir {
            let ledger = ctx.ledger();
            if moved > 0.0 {
                ledger.sink("heat_energy", f64::from(moved));
            } else {
                ledger.source("heat_energy", f64::from(-moved));
            }
        } else {
            cell.value.energy += moved;
            cell.value.temperature = cell.value.energy / cell.capacity;
        }
        Settle::Active
    }
}

/// Body ↔ body exchange (`crate::components::BodyCoupling`): a container's
/// interior.
pub struct BodyBodyExchange;
impl Law for BodyBodyExchange {
    type Reads = BodyCoupling;
    type Writes = (Foreign<BodyCoupling, HeatBody>, Foreign2<BodyCoupling, HeatBody>);
    const NAME: &'static str = "heat_body_body_exchange";

    fn step(ctx: &mut LawCtx<'_, BodyCoupling, Self::Writes>, dt: Seconds) -> Settle {
        let conductance = ctx.reads.conductance;
        #[allow(clippy::cast_possible_truncation)]
        let dt32 = dt.0 as f32;
        let (a, b) = (&mut ctx.writes.0.value, &mut ctx.writes.1.value);
        let (Some(a), Some(b)) = (a.as_mut(), b.as_mut()) else {
            return Settle::Sleep;
        };
        #[allow(clippy::cast_possible_truncation)]
        let (ta, ca) = (a.temperature() as f32, a.capacity as f32);
        #[allow(clippy::cast_possible_truncation)]
        let (tb, cb) = (b.temperature() as f32, b.capacity as f32);
        let moved = pair_exchange_f32(ta, ca, tb, cb, conductance as f32, dt32);
        if moved == 0.0 {
            return Settle::Sleep;
        }
        add_body_energy(a, -f64::from(moved));
        add_body_energy(b, f64::from(moved));
        if ctx.reads.slot == 0 {
            a.flow = f64::from(moved);
        }
        Settle::Active
    }
}

/// Body ↔ gas exchange (`crate::components::GasCoupling`), through
/// [`crate::couple::GasExchange`] while gas is not yet a field
/// (`rust_architecture.md` step 4 decision (b)). Every joule that crosses
/// this edge leaves or enters `"heat_energy"`'s tracked total (gas is
/// outside it, mutable or not), so it is always booked to the ledger,
/// matching the old `ledger::GAS`/`GAS_RESERVOIRS` entries.
pub struct BodyGasExchange;
impl Law for BodyGasExchange {
    type Reads = (GasCoupling, vg_core::query::Global<GasHandle>);
    type Writes = Foreign<GasCoupling, HeatBody>;
    const NAME: &'static str = "heat_body_gas_exchange";

    fn step(ctx: &mut LawCtx<'_, Self::Reads, Self::Writes>, dt: Seconds) -> Settle {
        let (coupling, gas) = (&ctx.reads.0, &ctx.reads.1.0);
        let Some(body) = ctx.writes.value.as_mut() else {
            return Settle::Sleep;
        };
        #[allow(clippy::cast_possible_truncation)]
        let dt32 = dt.0 as f32;
        #[allow(clippy::cast_possible_truncation)]
        let (tb, cb) = (body.temperature() as f32, body.capacity as f32);
        let target = if coupling.kind == crate::components::gas_kind::MIXTURE {
            GasRef::Mixture(coupling.target)
        } else {
            GasRef::Turf(coupling.target)
        };
        let conductance = coupling.conductance as f32;
        let mut moved_from_body = 0.0f32;
        let ok = gas
            .0
            .exchange(target, &mut |p: GasProbe| {
                if p.capacity <= 0.0 {
                    return 0.0;
                }
                let cg = if p.reservoir { f32::INFINITY } else { p.capacity };
                let m = pair_exchange_f32(tb, cb, p.temperature, cg, conductance, dt32);
                moved_from_body = m;
                m
            })
            .is_some();
        if !ok || moved_from_body == 0.0 {
            return Settle::Sleep;
        }
        add_body_energy(body, -f64::from(moved_from_body));
        if coupling.slot == 0 {
            body.flow = f64::from(moved_from_body);
        }
        let ledger = ctx.ledger();
        if moved_from_body > 0.0 {
            ledger.sink("heat_energy", f64::from(moved_from_body));
        } else {
            ledger.source("heat_energy", f64::from(-moved_from_body));
        }
        Settle::Active
    }
}

/// The regulator as a heat pump (`crate::components::Regulator`):
/// [`vg_core::thermo::Regulator::step`] applied to the controlled body and
/// the other side it moves energy between.
pub struct RegulatorHeatPump;
impl Law for RegulatorHeatPump {
    type Reads = Regulator;
    type Writes = (Foreign<Regulator, HeatBody>, Foreign2<Regulator, HeatBody>);
    const NAME: &'static str = "heat_regulator_pump";

    fn step(ctx: &mut LawCtx<'_, Regulator, Self::Writes>, dt: Seconds) -> Settle {
        let settings = ctx.reads.settings();
        #[allow(clippy::cast_possible_truncation)]
        let dt32 = dt.0 as f32;
        let (controlled, other) = (&mut ctx.writes.0.value, &mut ctx.writes.1.value);
        let (Some(controlled), Some(other)) = (controlled.as_mut(), other.as_mut()) else {
            return Settle::Sleep;
        };
        let cb = ThermalBody::new(HeatCapacity(controlled.capacity), Kelvin(controlled.temperature()));
        let ob = ThermalBody::new(HeatCapacity(other.capacity), Kelvin(other.temperature()));
        let step: RegulatorStep = settings.step(cb, ob, dt32);
        if step.moved == 0.0 && step.other == 0.0 {
            return Settle::Sleep;
        }
        add_body_energy(controlled, f64::from(step.moved));
        add_body_energy(other, f64::from(step.other));
        Settle::Active
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn add_body_energy_clamps_at_the_tcmb_floor() {
        let mut b = HeatBody {
            capacity: 10.0,
            energy: 10.0 * 300.0,
            ..Default::default()
        };
        add_body_energy(&mut b, -1.0e12);
        assert!((b.temperature() - f64::from(TCMB)).abs() < 1e-6);
    }

    #[test]
    fn body_body_exchange_conserves_total_energy() {
        let a = HeatBody {
            capacity: 10.0,
            energy: 10.0 * 400.0,
            ..Default::default()
        };
        let b = HeatBody {
            capacity: 20.0,
            energy: 20.0 * 300.0,
            ..Default::default()
        };
        let before = a.energy + b.energy;
        #[allow(clippy::cast_possible_truncation)]
        let dt32 = 1.0f32;
        let moved = pair_exchange_f32(a.temperature() as f32, a.capacity as f32, b.temperature() as f32, b.capacity as f32, 5.0, dt32);
        let mut a2 = a.clone();
        let mut b2 = b.clone();
        add_body_energy(&mut a2, -f64::from(moved));
        add_body_energy(&mut b2, f64::from(moved));
        assert!(((a2.energy + b2.energy) - before).abs() < 1e-3);
        assert!(a2.temperature() < a.temperature());
        assert!(b2.temperature() > b.temperature());
    }
}
