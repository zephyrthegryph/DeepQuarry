//! Heat's coupling laws (`rust_architecture.md` §6, §8.5): each of
//! [`crate::components::SolidCoupling`]/[`crate::components::BodyCoupling`]/
//! [`crate::components::GasCoupling`]/[`crate::components::Regulator`]
//! anchors one [`Law`] here, joined to the [`HeatBody`] row(s) it moves
//! energy between through [`vg_core::query::Foreign`]/
//! [`vg_core::query::Foreign2`] (and, for a solid target,
//! [`vg_core::field::law::Cell`]). The exchange math itself -- exact pair
//! exchange, the analytic relaxation solution, the regulator's COP-limited
//! heat pump -- is [`vg_core::thermo`]/[`vg_core::rate`]; this module wires
//! it onto real component rows.
//!
//! A body coupled through its `slot == 0` edge to an environment at least
//! [`RELAX_CAPACITY_RATIO`] times its own capacity (or an outright
//! reservoir), with no phase plateau, follows [`RateModel::Relax`] instead
//! of being stepped every frame (`body.rs`'s analytic path, ported onto
//! [`LawCtx::schedule`]): [`anchor_relax`] anchors the model and schedules
//! the next required wake (either the exact time the body would settle
//! within [`consts::BODY_SETTLED_K`] of its target, or
//! [`RELAX_MAX_INTERVAL`], whichever is sooner); the row then sleeps until
//! that wake, an explicit [`vg_core::world::World::wake_row`] call from an
//! FFI bind that changed the body or its environment out from under it
//! (`verdigris/ffi/src/heat.rs`'s coupling side tables), or a `slot != 0`
//! edge that keeps stepping regardless. [`settle_relax`] resolves the
//! model exactly at whatever `now` the row next runs at (early or on
//! schedule), moves the net energy into the environment, and either
//! re-anchors (still eligible) or falls through to the ordinary per-frame
//! exchange below it in the same call. A releasable body (`!keep`, no
//! sustained `power`) within [`consts::BODY_SETTLED_K`] of its target when
//! it settles emits [`HeatEvent::Settled`]; the FFI layer, which alone
//! knows a body's coupling entities, does the actual release (settle
//! already happened here) and despawn.

use vg_core::field::law::Cell;
use vg_core::law::{Law, LawCtx, Settle};
use vg_core::query::{Foreign, Foreign2};
use vg_core::rate::RateModel;
use vg_core::thermo::{RegulatorStep, ThermalBody, pair_exchange_f32, phase_energy};
use vg_core::units::{HeatCapacity, Kelvin, Seconds};
use vg_core::vg;

use crate::components::{BodyCoupling, GasCoupling, HeatBody, Regulator, SolidCoupling};
use crate::consts::{BODY_SETTLED_K, RELAX_CAPACITY_RATIO, RELAX_HYSTERESIS_K, RELAX_MAX_INTERVAL, TCMB};
use crate::couple::{GasHandle, GasProbe, GasRef};
use crate::solid::SolidHeat;

/// Heat's domain events (`rust_architecture.md` §4.8).
#[vg::events(domain = heat)]
pub enum HeatEvent {
    /// A releasable body (slot 0) settled within [`BODY_SETTLED_K`] of its
    /// environment: its excess energy already moved there this step; the
    /// FFI layer drops its coupling entities and despawns it.
    Settled,
}

/// Adds `joules` to a body's energy, clamped at its TCMB floor
/// (`body.rs::Body::add`, ported verbatim).
fn add_body_energy(body: &mut HeatBody, joules: f64) {
    let floor = body.capacity * f64::from(TCMB);
    body.energy = (body.energy + joules).max(floor);
}

/// The analytic model's asymptote: `ambient + power / conductance`.
fn relax_target(ambient: f64, power: f64, conductance: f64) -> f64 {
    if conductance > 0.0 {
        ambient + power / conductance
    } else {
        ambient
    }
}

/// The analytic model's rate, `conductance / capacity`.
fn relax_rate(conductance: f64, capacity: f64) -> f64 {
    if capacity > 0.0 { conductance / capacity } else { 0.0 }
}

/// A body with no sustained power draw/sink and DM's authority to release
/// it (`body.rs::releasable`, ported verbatim -- `pending` doesn't exist
/// here: a command applies straight to `energy`, so nothing is held back).
fn releasable(body: &HeatBody) -> bool {
    !body.keep && body.power == 0.0
}

/// Whether `env` is a reservoir for relax purposes: an outright reservoir,
/// or at least [`RELAX_CAPACITY_RATIO`] times `body_capacity`.
fn is_reservoir_env(env_capacity: f64, env_reservoir: bool, body_capacity: f64) -> bool {
    env_reservoir || env_capacity >= f64::from(RELAX_CAPACITY_RATIO) * body_capacity
}

/// Resolves the analytic model exactly at `now`, moves the net energy out
/// of `body` (clamped at its TCMB floor) and returns it for the caller to
/// deposit into the environment. Leaves `body.relax` cleared; the caller
/// re-anchors immediately if the body is still eligible.
pub fn settle_relax(body: &mut HeatBody, conductance: f64, now: f64) -> f64 {
    let model = RateModel::Relax {
        target: relax_target(body.ambient, body.power, conductance),
        v0: body.temperature(),
        k: relax_rate(conductance, body.capacity),
        t0: body.since,
    };
    #[allow(clippy::cast_possible_truncation)]
    let t = (model.value_at(now).max(f64::from(TCMB))) as f32;
    let e_new = f64::from(phase_energy(t, body.capacity as f32, body.phase()));
    let supplied = body.power * (now - body.since).max(0.0);
    let out = body.energy + supplied - e_new;
    let floor = body.capacity * f64::from(TCMB);
    body.energy = e_new.max(floor);
    body.relax = false;
    out
}

/// Anchors the analytic model at `now` against `ambient`, and returns when
/// it must next be settled: the exact time it would reach
/// [`BODY_SETTLED_K`] of its target (if releasable), else
/// [`RELAX_MAX_INTERVAL`] from now.
fn anchor_relax(body: &mut HeatBody, ambient: f64, conductance: f64, now: f64) -> f64 {
    body.relax = true;
    body.since = now;
    body.ambient = ambient;
    let k = relax_rate(conductance, body.capacity);
    let mut due = now + f64::from(RELAX_MAX_INTERVAL);
    if releasable(body) && k > 0.0 {
        let target = relax_target(ambient, body.power, conductance);
        let gap = (body.temperature() - target).abs();
        let settled = f64::from(BODY_SETTLED_K) * 0.5;
        due = if gap > settled {
            due.min(now + (gap / settled).ln() / k)
        } else {
            now
        };
    }
    due
}

/// Body ↔ solid-cell exchange (`crate::components::SolidCoupling`).
pub struct SolidBodyExchange;
impl Law for SolidBodyExchange {
    type Reads = SolidCoupling;
    type Writes = (Foreign<SolidCoupling, HeatBody>, Foreign2<SolidCoupling, Cell<SolidHeat>>);
    const NAME: &'static str = "heat_solid_body_exchange";

    fn step(ctx: &mut LawCtx<'_, SolidCoupling, Self::Writes>, dt: Seconds) -> Settle {
        let now = ctx.now();
        let conductance = ctx.reads.conductance;
        let slot0 = ctx.reads.slot == 0;

        let (body_side, cell_side) = (&mut ctx.writes.0.value, &mut ctx.writes.1.value);
        let (Some(body), Some(cell)) = (body_side.as_mut(), cell_side.as_mut()) else {
            return Settle::Sleep;
        };
        let env = (f64::from(cell.value.temperature), if cell.reservoir { f64::INFINITY } else { f64::from(cell.capacity) }, cell.reservoir);
        let (action, entry) = if slot0 {
            try_relax(body, conductance, now, env, |moved| deposit_solid(cell, moved))
        } else {
            (RelaxAction::None, LedgerEntry::None)
        };
        entry.apply(ctx);
        match action {
            RelaxAction::Settled => {
                ctx.emit(HeatEvent::Settled);
                return Settle::Sleep;
            }
            RelaxAction::Scheduled(due) => {
                ctx.schedule(due);
                return Settle::Sleep;
            }
            RelaxAction::None => {}
        }

        let (Some(body), Some(cell)) = (ctx.writes.0.value.as_mut(), ctx.writes.1.value.as_mut()) else {
            return Settle::Sleep;
        };
        #[allow(clippy::cast_possible_truncation)]
        let dt32 = dt.0 as f32;
        #[allow(clippy::cast_possible_truncation)]
        let (tb, cb) = (body.temperature() as f32, body.capacity as f32);
        let cc = if cell.reservoir { f32::INFINITY } else { cell.capacity };
        let moved = pair_exchange_f32(tb, cb, cell.value.temperature, cc, conductance as f32, dt32);
        if moved == 0.0 {
            return Settle::Sleep;
        }
        add_body_energy(body, -f64::from(moved));
        if slot0 {
            body.flow = f64::from(moved);
        }
        deposit_solid(cell, f64::from(moved)).apply(ctx);
        Settle::Active
    }
}

/// What happened when [`try_relax`] ran: the caller applies this to its
/// `ctx` once the body/environment borrows it computed with are free
/// again (a plain returned value, not a closure over `ctx`, is what makes
/// that possible: `ctx.schedule`/`ctx.emit` need `&mut` the whole
/// `LawCtx`, which can't coexist with a live borrow of `ctx.writes`).
enum RelaxAction {
    /// Not relaxing (or no longer eligible): fall through to the ordinary
    /// per-frame exchange.
    None,
    /// Settled within [`BODY_SETTLED_K`] and releasable: emit
    /// [`HeatEvent::Settled`].
    Settled,
    /// Still relaxing (freshly anchored or re-anchored): sleep until `due`.
    Scheduled(f64),
}

/// Runs one coupling's relax handling for `now`, entering, continuing or
/// leaving analytic mode as needed. `env` is the environment's current
/// (temperature, capacity, is-a-reservoir); `deposit` moves `moved` joules
/// (leaving the body) into it, returning what to book to the ledger.
/// Returns `RelaxAction::None` unless the body is (or was, this call)
/// relaxing -- the caller runs the ordinary stepped exchange itself, this
/// only ever resolves down to a plain energy handoff.
fn try_relax(body: &mut HeatBody, conductance: f64, now: f64, env: (f64, f64, bool), deposit: impl FnOnce(f64) -> LedgerEntry) -> (RelaxAction, LedgerEntry) {
    let (env_t, env_c, env_reservoir) = env;
    let analytic_ok = body.phase_temperature <= 0.0 && is_reservoir_env(env_c, env_reservoir, body.capacity);
    if !body.relax {
        return if analytic_ok {
            let due = anchor_relax(body, env_t, conductance, now);
            (RelaxAction::Scheduled(due), LedgerEntry::None)
        } else {
            (RelaxAction::None, LedgerEntry::None)
        };
    }
    let env_moved = (env_t - body.ambient).abs() > f64::from(RELAX_HYSTERESIS_K);
    let moved = settle_relax(body, conductance, now);
    let entry = deposit(moved);
    if analytic_ok && !env_moved && releasable(body) && (body.temperature() - env_t).abs() < f64::from(BODY_SETTLED_K) {
        return (RelaxAction::Settled, entry);
    }
    if analytic_ok {
        let due = anchor_relax(body, env_t, conductance, now);
        return (RelaxAction::Scheduled(due), entry);
    }
    (RelaxAction::None, entry)
}

/// What a deposit into a reservoir side must book to the ledger, once the
/// caller's borrow of that side is free again.
enum LedgerEntry {
    None,
    Sink(f64),
    Source(f64),
}

impl LedgerEntry {
    fn apply(self, ctx: &mut impl LedgerSink) {
        match self {
            Self::None => {}
            Self::Sink(v) => ctx.ledger().sink("heat_energy", v),
            Self::Source(v) => ctx.ledger().source("heat_energy", v),
        }
    }
}

trait LedgerSink {
    fn ledger(&mut self) -> &mut vg_core::conservation::Ledger;
}

impl<R> LedgerSink for LawCtx<'_, R, <SolidBodyExchange as Law>::Writes> {
    fn ledger(&mut self) -> &mut vg_core::conservation::Ledger {
        LawCtx::ledger(self)
    }
}

impl LedgerSink for LawCtx<'_, <BodyGasExchange as Law>::Reads, <BodyGasExchange as Law>::Writes> {
    fn ledger(&mut self) -> &mut vg_core::conservation::Ledger {
        LawCtx::ledger(self)
    }
}

/// Deposits `moved` joules (leaving the body) into a solid cell side,
/// mutating it directly if it is not a reservoir. Returns what a reservoir
/// side must still book to the ledger (the caller applies it once its own
/// borrow of `ctx.writes` is free).
fn deposit_solid(cell: &mut vg_core::field::law::Cell<SolidHeat>, moved: f64) -> LedgerEntry {
    if moved == 0.0 {
        return LedgerEntry::None;
    }
    if cell.reservoir {
        if moved > 0.0 { LedgerEntry::Sink(moved) } else { LedgerEntry::Source(-moved) }
    } else {
        #[allow(clippy::cast_possible_truncation)]
        let m = moved as f32;
        cell.value.energy += m;
        cell.value.temperature = cell.value.energy / cell.capacity;
        LedgerEntry::None
    }
}

/// Body ↔ body exchange (`crate::components::BodyCoupling`): a container's
/// interior. `b` (the "other" side) is treated as `a`'s environment for
/// relax purposes; a `b` that is itself relaxing reports its own anchor
/// temperature, not a live value, until it next settles -- a known
/// approximation for two bodies relaxing against each other, which
/// `rust_architecture.md`'s target shape does not otherwise need (a
/// container's interior is usually a small, actively-stepped body against
/// a large fixed one, not two mutually-relaxing bodies).
pub struct BodyBodyExchange;
impl Law for BodyBodyExchange {
    type Reads = BodyCoupling;
    type Writes = (Foreign<BodyCoupling, HeatBody>, Foreign2<BodyCoupling, HeatBody>);
    const NAME: &'static str = "heat_body_body_exchange";

    fn step(ctx: &mut LawCtx<'_, BodyCoupling, Self::Writes>, dt: Seconds) -> Settle {
        let now = ctx.now();
        let conductance = ctx.reads.conductance;
        let slot0 = ctx.reads.slot == 0;

        let (a_side, b_side) = (&mut ctx.writes.0.value, &mut ctx.writes.1.value);
        let (Some(a), Some(b)) = (a_side.as_mut(), b_side.as_mut()) else {
            return Settle::Sleep;
        };
        let env = (b.temperature(), b.capacity, false);
        let (action, _) = if slot0 {
            try_relax(a, conductance, now, env, |moved| {
                add_body_energy(b, moved);
                LedgerEntry::None
            })
        } else {
            (RelaxAction::None, LedgerEntry::None)
        };
        match action {
            RelaxAction::Settled => {
                ctx.emit(HeatEvent::Settled);
                return Settle::Sleep;
            }
            RelaxAction::Scheduled(due) => {
                ctx.schedule(due);
                return Settle::Sleep;
            }
            RelaxAction::None => {}
        }

        let (Some(a), Some(b)) = (ctx.writes.0.value.as_mut(), ctx.writes.1.value.as_mut()) else {
            return Settle::Sleep;
        };
        #[allow(clippy::cast_possible_truncation)]
        let dt32 = dt.0 as f32;
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
        if slot0 {
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
        let now = ctx.now();
        let (coupling, gas) = (ctx.reads.0.clone(), ctx.reads.1.0.clone());
        let Some(body) = ctx.writes.value.as_mut() else {
            return Settle::Sleep;
        };
        let target = if coupling.kind == crate::components::gas_kind::MIXTURE {
            GasRef::Mixture(coupling.target)
        } else {
            GasRef::Turf(coupling.target)
        };
        let conductance = f64::from(coupling.conductance as f32);
        let slot0 = coupling.slot == 0;

        if slot0 {
            if let Some(probe) = gas.0.probe(target) {
                let env = (f64::from(probe.temperature), if probe.reservoir { f64::INFINITY } else { f64::from(probe.capacity) }, probe.reservoir);
                let (action, entry) = try_relax(body, conductance, now, env, |moved| deposit_gas(&gas, target, moved));
                entry.apply(ctx);
                match action {
                    RelaxAction::Settled => {
                        ctx.emit(HeatEvent::Settled);
                        return Settle::Sleep;
                    }
                    RelaxAction::Scheduled(due) => {
                        ctx.schedule(due);
                        return Settle::Sleep;
                    }
                    RelaxAction::None => {}
                }
            }
        }

        let Some(body) = ctx.writes.value.as_mut() else {
            return Settle::Sleep;
        };
        #[allow(clippy::cast_possible_truncation)]
        let dt32 = dt.0 as f32;
        #[allow(clippy::cast_possible_truncation)]
        let (tb, cb) = (body.temperature() as f32, body.capacity as f32);
        let mut moved_from_body = 0.0f32;
        let ok = gas
            .0
            .exchange(target, &mut |p: GasProbe| {
                if p.capacity <= 0.0 {
                    return 0.0;
                }
                let cg = if p.reservoir { f32::INFINITY } else { p.capacity };
                let m = pair_exchange_f32(tb, cb, p.temperature, cg, conductance as f32, dt32);
                moved_from_body = m;
                m
            })
            .is_some();
        if !ok || moved_from_body == 0.0 {
            return Settle::Sleep;
        }
        add_body_energy(body, -f64::from(moved_from_body));
        if slot0 {
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

/// Deposits `moved` joules (leaving the body) into `target` through
/// `gas`. Returns what must be booked to the ledger (gas is always outside
/// `"heat_energy"`'s tracked total, mutable or not).
fn deposit_gas(gas: &GasHandle, target: GasRef, moved: f64) -> LedgerEntry {
    if moved == 0.0 {
        return LedgerEntry::None;
    }
    #[allow(clippy::cast_possible_truncation)]
    let m = moved as f32;
    let applied = gas.0.exchange(target, &mut |_p| m).unwrap_or(0.0);
    if applied > 0.0 {
        LedgerEntry::Sink(f64::from(applied))
    } else if applied < 0.0 {
        LedgerEntry::Source(f64::from(-applied))
    } else {
        LedgerEntry::None
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

    #[test]
    fn relax_target_and_rate_match_the_closed_form() {
        assert!((relax_target(300.0, 100.0, 5.0) - 320.0).abs() < 1e-9);
        assert!((relax_target(300.0, 0.0, 0.0) - 300.0).abs() < 1e-9);
        assert!((relax_rate(5.0, 10.0) - 0.5).abs() < 1e-9);
    }

    #[test]
    fn settle_relax_matches_the_exact_exponential_and_conserves_with_the_environment() {
        let mut body = HeatBody {
            capacity: 10.0,
            energy: 10.0 * 400.0,
            relax: true,
            since: 0.0,
            ambient: 300.0,
            ..Default::default()
        };
        let conductance = 2.0;
        let before = body.energy;
        let moved = settle_relax(&mut body, conductance, 10.0);
        let k = relax_rate(conductance, body.capacity);
        let expect_t = 300.0 + (400.0f64 - 300.0) * (-k * 10.0).exp();
        assert!((body.temperature() - expect_t).abs() < 1e-3, "{} vs {expect_t}", body.temperature());
        assert!(!body.relax);
        assert!((before - moved - body.energy).abs() < 1e-6, "moved conserves with the stored energy");
        assert!(moved > 0.0, "a hot body relaxing toward a cooler ambient gives up energy");
    }

    #[test]
    fn anchor_relax_schedules_the_settle_time_for_a_releasable_body() {
        let mut body = HeatBody {
            capacity: 10.0,
            energy: 10.0 * 400.0,
            ..Default::default()
        };
        let due = anchor_relax(&mut body, 300.0, 2.0, 0.0);
        assert!(body.relax);
        assert!(due > 0.0 && due <= f64::from(RELAX_MAX_INTERVAL));
        let mut kept = body.clone();
        kept.keep = true;
        let due_kept = anchor_relax(&mut kept, 300.0, 2.0, 0.0);
        assert!((due_kept - f64::from(RELAX_MAX_INTERVAL)).abs() < 1e-9, "a kept body never settles early");
    }

    #[test]
    fn is_reservoir_env_matches_the_capacity_ratio_or_an_outright_reservoir() {
        assert!(is_reservoir_env(0.0, true, 10.0));
        assert!(is_reservoir_env(f64::from(RELAX_CAPACITY_RATIO) * 10.0, false, 10.0));
        assert!(!is_reservoir_env(f64::from(RELAX_CAPACITY_RATIO) * 10.0 - 1.0, false, 10.0));
    }
}
