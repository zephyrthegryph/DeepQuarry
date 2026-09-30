//! Heat's coupling laws (`rust_architecture.md` §6, §8.5). Each coupling
//! component ([`SolidCoupling`], [`BodyCoupling`], [`GasCoupling`],
//! [`Regulator`]) anchors one law, joined through
//! [`vg_core::query::Foreign`]/[`vg_core::query::Foreign2`] to the body and
//! the environment it exchanges with. Every environment -- a solid cell, a
//! turf's gas, another body -- is an [`Env`], so one function, [`couple`],
//! runs every body coupling. A gas is any field whose cells are
//! [`Thermal`]: heat does not depend on the gas domain.
//!
//! A body coupled through its `slot == 0` edge to an environment at least
//! [`RELAX_CAPACITY_RATIO`] times its own capacity (or a reservoir), with
//! no phase plateau, follows [`RateModel::Relax`] instead of being stepped
//! every frame: [`anchor_relax`] anchors the model and schedules the next
//! wake ([`LawCtx::schedule`]); [`settle_relax`] resolves it exactly at
//! whatever `now` the row next runs. A releasable body within
//! [`BODY_SETTLED_K`] of its environment emits [`HeatEvent::Settled`]; the
//! FFI layer releases it.

use vg_core::field::FieldKind;
use vg_core::field::law::{Cell, Coupled};
use vg_core::law::{LawCtx, Settle};
use vg_core::query::{Foreign, Foreign2};
use vg_core::rate::RateModel;
use vg_core::thermo::{Thermal, ThermalBody, pair_exchange_at_rate_f32, pair_exchange_f32, phase_energy};
use vg_core::units::{HeatCapacity, Kelvin, Seconds};
use vg_core::vg;

use crate::components::{BodyCoupling, GasCoupling, HeatBody, Regulator, SolidCoupling};
use crate::consts::{BODY_SETTLED_K, GAS_COUPLING, GAS_COUPLING_MIN_K, RELAX_CAPACITY_RATIO, RELAX_HYSTERESIS_K, RELAX_MAX_INTERVAL, TCMB};
use crate::solid::{SolidHeat, flags};

/// Heat's domain events (`rust_architecture.md` §4.8).
#[vg::events(domain = heat)]
pub enum HeatEvent {
    /// A releasable body (slot 0) settled within [`BODY_SETTLED_K`] of its
    /// environment: its excess energy already moved there this step; the
    /// FFI layer drops its coupling entities and despawns it.
    Settled,
    /// A body coupled to a gas mixture (a tank, a canister; `target` is its arena id) moved `joules` into it (negative: out of it); the FFI layer, which owns
    /// mixtures, applies it.
    MixtureHeat { target: u32, joules: f32 },
    /// A body coupled to a pipe port moved `joules` into (negative: out of) the gas of the region the port is in. The port's
    /// packed entity id is below 2^24, so it survives the event's `f32` wire exactly (a probe key does not).
    PortHeat { port: u32, joules: f32 },
}

/// Adds `joules` to a body's energy, clamped at its TCMB floor.
pub fn add_body_energy(body: &mut HeatBody, joules: f64) {
    body.energy = (body.energy + joules).max(body.capacity * f64::from(TCMB));
}

fn relax_target(ambient: f64, power: f64, conductance: f64) -> f64 {
    if conductance > 0.0 { ambient + power / conductance } else { ambient }
}

fn relax_rate(conductance: f64, capacity: f64) -> f64 {
    if capacity > 0.0 { conductance / capacity } else { 0.0 }
}

/// No sustained power, and DM lets it go.
fn releasable(body: &HeatBody) -> bool {
    !body.keep && body.power == 0.0
}

/// An outright reservoir, or at least [`RELAX_CAPACITY_RATIO`] times the body.
fn is_reservoir_env(env_capacity: f64, env_reservoir: bool, body_capacity: f64) -> bool {
    env_reservoir || env_capacity >= f64::from(RELAX_CAPACITY_RATIO) * body_capacity
}

/// Resolves the analytic model exactly at `now` and returns the net energy
/// that left the body (clamped at its TCMB floor) for the caller to deposit
/// into the environment. Clears `body.relax`.
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
    let out = body.energy + body.power * (now - body.since).max(0.0) - e_new;
    body.energy = e_new.max(body.capacity * f64::from(TCMB));
    body.relax = false;
    out
}

/// Anchors the analytic model at `now` against `ambient` and returns when
/// it must next be settled: when it would reach [`BODY_SETTLED_K`] of its
/// target (if releasable), else [`RELAX_MAX_INTERVAL`] from now.
fn anchor_relax(body: &mut HeatBody, ambient: f64, conductance: f64, now: f64) -> f64 {
    body.relax = true;
    body.since = now;
    body.ambient = ambient;
    let k = relax_rate(conductance, body.capacity);
    let due = now + f64::from(RELAX_MAX_INTERVAL);
    if !releasable(body) || k <= 0.0 {
        return due;
    }
    let gap = (body.temperature() - relax_target(ambient, body.power, conductance)).abs();
    let settled = f64::from(BODY_SETTLED_K) * 0.5;
    if gap > settled { due.min(now + (gap / settled).ln() / k) } else { now }
}

/// A body's exchange partner.
pub trait Env {
    /// `(temperature K, heat capacity J/K, reservoir)`.
    fn state(&self) -> (f32, f32, bool);
    /// Adds `joules`; returns the part that left `"heat_energy"`'s tracked
    /// total (all of it for a reservoir or a gas).
    fn deposit(&mut self, joules: f64) -> f64;
}

impl Env for HeatBody {
    #[allow(clippy::cast_possible_truncation)]
    fn state(&self) -> (f32, f32, bool) {
        (self.temperature() as f32, self.capacity as f32, false)
    }

    fn deposit(&mut self, joules: f64) -> f64 {
        add_body_energy(self, joules);
        0.0
    }
}

impl<K: FieldKind> Env for Cell<K>
where
    K::Value: Thermal,
{
    fn state(&self) -> (f32, f32, bool) {
        let (t, c) = self.value.thermal(self.capacity);
        (t, if self.reservoir { f32::INFINITY } else { c }, self.reservoir)
    }

    fn deposit(&mut self, joules: f64) -> f64 {
        #[allow(clippy::cast_possible_truncation)]
        if !self.reservoir {
            self.value.add_heat(joules as f32, self.capacity);
        }
        if self.reservoir || !K::Value::IN_HEAT_TOTAL { joules } else { 0.0 }
    }
}

/// A field whose cells are [`Thermal`]: a gas a body or a solid couples to.
pub trait ThermalField: FieldKind<Value: Thermal> {}
impl<K: FieldKind<Value: Thermal>> ThermalField for K {}

/// Gas mixtures a body couples to (tanks, pipe networks), by handle, sorted:
/// `(handle, temperature K, heat capacity J/K, reservoir)`. Main-owned (the
/// FFI layer refreshes it each step); the exchange law reads its snapshot.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct MixtureProbes(pub Vec<(u32, f32, f32, bool)>);

/// A mixture as a coupling's environment: what the body deposits into it is
/// only recorded (the mixture is main-owned; see [`HeatEvent::MixtureHeat`]).
struct MixtureEnv {
    state: (f32, f32, bool),
    deposited: f64,
}

impl Env for MixtureEnv {
    fn state(&self) -> (f32, f32, bool) {
        let (t, c, r) = self.state;
        (t, if r { f32::INFINITY } else { c }, r)
    }

    fn deposit(&mut self, joules: f64) -> f64 {
        self.deposited += joules;
        joules
    }
}

/// What a coupling step asks of its law's `ctx`.
enum Outcome {
    Settled,
    Scheduled(f64),
    Active,
    Sleep,
}

/// One body coupling step: the analytic relax path for a slot-0 edge to a
/// large environment, else the exact pair exchange over `dt`. Returns what
/// to do and the joules to book as leaving `"heat_energy"`.
#[allow(clippy::cast_possible_truncation)]
fn couple(body: &mut HeatBody, env: &mut impl Env, conductance: f64, slot0: bool, now: f64, dt: Seconds) -> (Outcome, f64) {
    let (env_t, env_c, env_reservoir) = env.state();
    let mut booked = 0.0;
    if slot0 {
        let analytic = body.phase_temperature <= 0.0 && is_reservoir_env(f64::from(env_c), env_reservoir, body.capacity);
        if body.relax {
            let env_moved = (f64::from(env_t) - body.ambient).abs() > f64::from(RELAX_HYSTERESIS_K);
            booked = env.deposit(settle_relax(body, conductance, now));
            if analytic && !env_moved && releasable(body) && (body.temperature() - f64::from(env_t)).abs() < f64::from(BODY_SETTLED_K) {
                return (Outcome::Settled, booked);
            }
        }
        if analytic {
            return (Outcome::Scheduled(anchor_relax(body, f64::from(env_t), conductance, now)), booked);
        }
    }
    let (tb, cb, _) = body.state();
    let moved = pair_exchange_f32(tb, cb, env_t, env_c, conductance as f32, dt.0 as f32);
    if moved == 0.0 {
        return (Outcome::Sleep, booked);
    }
    add_body_energy(body, -f64::from(moved));
    if slot0 {
        body.flow = f64::from(moved);
    }
    (Outcome::Active, booked + env.deposit(f64::from(moved)))
}

/// Applies a coupling step's [`Outcome`] and ledger booking to `ctx`.
fn finish<R, W>(ctx: &mut LawCtx<'_, R, W>, (outcome, booked): (Outcome, f64)) -> Settle {
    if booked > 0.0 {
        ctx.ledger().sink("heat_energy", booked);
    } else if booked < 0.0 {
        ctx.ledger().source("heat_energy", -booked);
    }
    match outcome {
        Outcome::Settled => {
            ctx.emit(HeatEvent::Settled);
            Settle::Sleep
        }
        Outcome::Scheduled(due) => {
            ctx.schedule(due);
            Settle::Sleep
        }
        Outcome::Active => Settle::Active,
        Outcome::Sleep => Settle::Sleep,
    }
}

vg_core::law! {
    /// Body ↔ solid-cell exchange ([`SolidCoupling`]).
    pub SolidBodyExchange("heat_solid_body_exchange"): SolidCoupling => (Foreign<SolidCoupling, HeatBody>, Foreign2<SolidCoupling, Cell<SolidHeat>>), |ctx, dt| {
        let (now, c) = (ctx.now(), ctx.reads.clone());
        let (Some(body), Some(cell)) = (ctx.writes.0.value.as_mut(), ctx.writes.1.value.as_mut()) else {
            return Settle::Sleep;
        };
        let step = couple(body, cell, c.conductance, c.slot == 0, now, dt);
        finish(ctx, step)
    }
}

vg_core::law! {
    /// Body ↔ body exchange ([`BodyCoupling`]): a container's interior, `b`
    /// (the "other" side) being `a`'s environment.
    pub BodyBodyExchange("heat_body_body_exchange"): BodyCoupling => (Foreign<BodyCoupling, HeatBody>, Foreign2<BodyCoupling, HeatBody>), |ctx, dt| {
        let (now, c) = (ctx.now(), ctx.reads.clone());
        let (Some(a), Some(b)) = (ctx.writes.0.value.as_mut(), ctx.writes.1.value.as_mut()) else {
            return Settle::Sleep;
        };
        let step = couple(a, b, c.conductance, c.slot == 0, now, dt);
        finish(ctx, step)
    }
}

vg_core::law! {
    /// Body ↔ turf gas exchange ([`GasCoupling`]) with gas field `G`.
    pub BodyGasExchange<G: ThermalField>("heat_body_gas_exchange"): GasCoupling => (Foreign<GasCoupling, HeatBody>, Foreign2<GasCoupling, Cell<G>>), |ctx, dt| {
        let (now, c) = (ctx.now(), ctx.reads.clone());
        let (Some(body), Some(gas)) = (ctx.writes.0.value.as_mut(), ctx.writes.1.value.as_mut()) else {
            return Settle::Sleep;
        };
        let step = couple(body, gas, c.conductance, c.slot == 0, now, dt);
        finish(ctx, step)
    }
}

vg_core::law! {
    /// A turf's solid ↔ its gas (`OPEN_HEAT_TRANSFER_COEFFICIENT`): each pair
    /// relaxes at `GAS_COUPLING * conductivity` where the solid has air and
    /// they differ by more than [`GAS_COUPLING_MIN_K`]. Runs over every cell
    /// active in either field: the air changing, or the turf's heat.
    pub SolidGasExchange<G: ThermalField>("heat_solid_gas_exchange"): () => Coupled<G, SolidHeat>, |ctx, dt| {
        let Coupled(gas, solid) = &mut ctx.writes;
        if !solid.value.has(flags::AIR) || solid.value.conductivity <= 0.0 || solid.reservoir {
            return Settle::Sleep;
        }
        let ((tg, cg, _), (ts, cs, _)) = (gas.state(), solid.state());
        if cg <= 0.0 || (ts - tg).abs() < GAS_COUPLING_MIN_K {
            return Settle::Sleep;
        }
        #[allow(clippy::cast_possible_truncation)]
        let moved = pair_exchange_at_rate_f32(ts, cs, tg, cg, GAS_COUPLING * solid.value.conductivity, dt.0 as f32);
        let booked = gas.deposit(f64::from(moved)) + solid.deposit(-f64::from(moved));
        finish(ctx, (if moved == 0.0 { Outcome::Sleep } else { Outcome::Active }, booked))
    }
}

vg_core::law! {
    /// Body ↔ gas mixture exchange ([`GasCoupling`] to a tank or pipe
    /// network): the mixture's side is read from [`MixtureProbes`] and
    /// applied by the FFI layer from [`HeatEvent::MixtureHeat`].
    pub BodyMixtureExchange("heat_body_mixture_exchange"): (GasCoupling, vg_core::query::Global<MixtureProbes>) => Foreign<GasCoupling, HeatBody>, |ctx, dt| {
        let (now, c) = (ctx.now(), ctx.reads.0.clone());
        if c.kind == crate::components::gas_kind::TURF {
            return Settle::Sleep;
        }
        let key = c.probe_key();
        let probes = &ctx.reads.1 .0 .0;
        let Ok(i) = probes.binary_search_by_key(&key, |p| p.0) else {
            return Settle::Active;
        };
        let (_, t, cap, reservoir) = probes[i];
        let Some(body) = ctx.writes.value.as_mut() else {
            return Settle::Sleep;
        };
        let mut env = MixtureEnv { state: (t, cap, reservoir), deposited: 0.0 };
        let step = couple(body, &mut env, c.conductance, c.slot == 0, now, dt);
        if env.deposited != 0.0 {
            #[allow(clippy::cast_possible_truncation)]
            if c.kind == crate::components::gas_kind::PIPE_PORT {
                ctx.emit(HeatEvent::PortHeat { port: c.target, joules: env.deposited as f32 });
            } else {
                ctx.emit(HeatEvent::MixtureHeat { target: c.target, joules: env.deposited as f32 });
            }
        }
        let settle = finish(ctx, step);
        // A pipeline's gas changes under it (devices, other exchanges) and nothing wakes a sleeping coupling for that:
        // a port coupling keeps stepping.
        if c.kind == crate::components::gas_kind::PIPE_PORT && settle == Settle::Sleep {
            Settle::Active
        } else {
            settle
        }
    }
}

vg_core::law! {
    /// The regulator as a heat pump ([`Regulator`]):
    /// [`vg_core::thermo::Regulator::step`] between the controlled body and
    /// the other side.
    pub RegulatorHeatPump("heat_regulator_pump"): Regulator => (Foreign<Regulator, HeatBody>, Foreign2<Regulator, HeatBody>), |ctx, dt| {
        let settings = ctx.reads.settings();
        let (Some(controlled), Some(other)) = (ctx.writes.0.value.as_mut(), ctx.writes.1.value.as_mut()) else {
            return Settle::Sleep;
        };
        let cb = ThermalBody::new(HeatCapacity(controlled.capacity), Kelvin(controlled.temperature()));
        let ob = ThermalBody::new(HeatCapacity(other.capacity), Kelvin(other.temperature()));
        #[allow(clippy::cast_possible_truncation)]
        let step = settings.step(cb, ob, dt.0 as f32);
        if step.moved == 0.0 && step.other == 0.0 {
            return Settle::Sleep;
        }
        add_body_energy(controlled, f64::from(step.moved));
        add_body_energy(other, f64::from(step.other));
        Settle::Active
    }
}

vg_core::law! {
    /// A body's own heat source (`HeatBody::power`, W) each step. A relaxing
    /// body's analytic model already carries it, so this adds nothing then.
    pub BodyPower("heat_body_power"): () => HeatBody, |ctx, dt| {
        let body = &mut ctx.writes;
        if body.power == 0.0 {
            return Settle::Sleep;
        }
        if body.relax {
            return Settle::Active;
        }
        let joules = body.power * dt.0;
        add_body_energy(body, joules);
        if joules > 0.0 {
            ctx.ledger().source("heat_energy", joules);
        } else {
            ctx.ledger().sink("heat_energy", -joules);
        }
        Settle::Active
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn add_body_energy_clamps_at_the_tcmb_floor() {
        let mut b = HeatBody { capacity: 10.0, energy: 10.0 * 300.0, ..Default::default() };
        add_body_energy(&mut b, -1.0e12);
        assert!((b.temperature() - f64::from(TCMB)).abs() < 1e-6);
    }

    #[test]
    fn body_body_exchange_conserves_total_energy() {
        let a = HeatBody { capacity: 10.0, energy: 10.0 * 400.0, ..Default::default() };
        let b = HeatBody { capacity: 20.0, energy: 20.0 * 300.0, ..Default::default() };
        let before = a.energy + b.energy;
        #[allow(clippy::cast_possible_truncation)]
        let (mut a2, mut b2) = (a.clone(), b.clone());
        couple(&mut a2, &mut b2, 5.0, false, 0.0, Seconds(1.0));
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
        let mut body = HeatBody { capacity: 10.0, energy: 10.0 * 400.0, relax: true, since: 0.0, ambient: 300.0, ..Default::default() };
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
        let mut body = HeatBody { capacity: 10.0, energy: 10.0 * 400.0, ..Default::default() };
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
