//! Heat's laws, as pure functions and (below the `Law`/`LawCtx` heading) as
//! real [`vg_core::law::Law`] implementations against Core A's driver
//! (`doc/rewrite/rust_architecture.md` §2/§6/§4.3). Each pure function is
//! `fn(inputs) -> outputs` with no `Sim`, no host state and no side effect
//! beyond its return value; each `Law` wraps one in the driver's shape
//! (`Reads`/`Writes`/`step`) so it can run under `order_laws`/`Pacer` once
//! Core B's component stores land, with no further physics change. The
//! `Task`-based wiring in [`crate::body`]/[`crate::couple`]/[`crate::world`]
//! is today's driver and stays until Core B's stores replace it (§7);
//! every one of those call sites already reduces to exactly the function or
//! law next to it here.
//!
//! - **Body↔environment exchange**: [`pair_exchange`]/[`pair_exchange_at_rate`]
//!   (conductance, or a precomputed rate, over `dt`; a reservoir passes
//!   `f32::INFINITY`), and [`relax_toward`] for the analytic path against a
//!   reservoir-like environment. As a law: [`BodyEnvironmentExchange`].
//! - **The phase buffer**: [`phase_temperature`]/[`phase_energy`] (a phase
//!   plateau's latent-heat step).
//! - **The Regulator as a heat pump**: [`regulator_step`] (wraps the
//!   already-pure [`Regulator::step`]). As a law: [`RegulatorHeatPump`].
//! - **Coupling laws**: [`solid_gas_exchange`] (solid↔gas, conductance
//!   scaled by [`crate::consts::GAS_COUPLING`] and deadbanded by
//!   [`crate::consts::GAS_COUPLING_MIN_K`]; as a law, [`SolidGasCoupling`])
//!   and [`pair_exchange`] again (body↔gas: a body's gas-target coupling is
//!   exactly a two-body exchange against the gas's temperature/capacity, so
//!   it needs no separate function -- this *is* the law, replacing
//!   `GasExchange`/`GasRef`/`GasProbe`'s job of fetching those two numbers;
//!   as a law, [`BodyGasCoupling`]).

use vg_core::law::{Law, LawCtx, Settle};
use vg_core::units::Seconds;

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

// -------------------------------------------------------- Law/LawCtx (Core A)

/// One side of a pairwise exchange: its current temperature, its heat
/// capacity, and whether it's a reservoir. `Reads`/`Writes` types must be
/// `'static` (`vg_core::law::Query`), so unlike an earlier draft of this
/// module this holds its temperature *by value*, not a reference into the
/// caller's own storage -- `LawCtx<'a, R, W>` already provides the
/// borrowing (`writes: &'a mut W`), so a law's `Writes` is read back by the
/// caller through the same `PairSides` it passed in, exactly like the
/// `Law` trait's own doctest (`Breaker { tripped: bool }`, mutated via
/// `ctx.writes.tripped = true` with no extra indirection).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ThermalSide {
    pub temperature: f32,
    /// Ignored when `reservoir` is `true` (treated as infinite capacity
    /// regardless of this field).
    pub capacity: f32,
    /// A reservoir (space, a planet's atmosphere, or a gas side the
    /// coupling can't write back to) doesn't move: the energy that would
    /// have changed its temperature is recorded on the ledger instead,
    /// exactly [`crate::couple::GasProbe::reservoir`]'s job today.
    pub reservoir: bool,
}

impl ThermalSide {
    #[must_use]
    pub const fn mutable(temperature: f32, capacity: f32) -> Self {
        Self {
            temperature,
            capacity,
            reservoir: false,
        }
    }

    #[must_use]
    pub const fn reservoir(temperature: f32) -> Self {
        Self {
            temperature,
            capacity: f32::INFINITY,
            reservoir: true,
        }
    }

    fn effective_capacity(&self) -> f32 {
        if self.reservoir {
            f32::INFINITY
        } else {
            self.capacity
        }
    }

    /// Applies `moved` J leaving this side (negative: entering it). Returns
    /// `Some(moved)` for a reservoir side instead of changing its
    /// temperature, for the caller to book to the ledger once both sides
    /// are done (see [`apply_pair`]).
    #[must_use]
    fn apply(&mut self, moved: f32) -> Option<f32> {
        if self.reservoir {
            return Some(moved);
        }
        self.temperature -= moved / self.capacity;
        None
    }
}

/// Reads every pair-exchange law shares: the coupling's own [`ThermalSide`]s
/// are in `Writes` (both may be mutated), so all that's left to read is the
/// coupling strength. `dt` comes from [`Law::step`]'s own parameter (the
/// driver's fixed step), not duplicated here.
#[derive(Clone, Copy, Debug)]
pub struct PairCoupling {
    /// W/K (`solid_gas_exchange`-style laws pass a precomputed rate here
    /// too -- conductance and a rate are the same units).
    pub conductance: f32,
}

/// Both sides of a pair-exchange law. `quantity` names the conserved total
/// these two sides are part of, for the reservoir-sink ledger entry; every
/// coupling law in this module uses `"heat_energy"`.
#[derive(Clone, Copy, Debug)]
pub struct PairSides {
    pub a: ThermalSide,
    pub b: ThermalSide,
    pub quantity: &'static str,
}

/// Applies `moved_a`/`moved_b` J leaving each side to `sides.a`/`sides.b`
/// respectively, booking either side's flow to the ledger if it's a
/// reservoir. Generic over the law's `Reads` type (every coupling law here
/// shares this, whether its `Reads` is [`PairCoupling`] or [`Regulator`]).
/// The two amounts are independent (not required to be negatives of each
/// other) so this covers both a symmetric pair exchange (`moved`, `-moved`)
/// and the Regulator's generally-asymmetric `moved`/`other` flows.
///
/// Structured to call [`ThermalSide::apply`] (pure `&mut self`, no ledger
/// involved) on both sides *first*, copying out any unbooked reservoir
/// amounts as plain values, and only then calling `ctx.ledger()` -- calling
/// it any earlier would borrow the whole `LawCtx` for as long as the
/// reference lives, conflicting with the still-needed `ctx.writes.a`/
/// `ctx.writes.b` field-projected borrows (`LawCtx::ledger`/`reads`/
/// `writes` are ordinary methods/fields from this crate's side of the
/// boundary, so the borrow checker can't see them as disjoint the way it
/// can two literal struct fields).
fn apply_pair<R>(ctx: &mut LawCtx<'_, R, PairSides>, moved_a: f32, moved_b: f32) {
    let unbooked_a = ctx.writes.a.apply(moved_a);
    let unbooked_b = ctx.writes.b.apply(moved_b);
    let quantity = ctx.writes.quantity;
    if unbooked_a.is_some() || unbooked_b.is_some() {
        let ledger = ctx.ledger();
        if let Some(m) = unbooked_a {
            ledger.source(quantity, f64::from(m));
        }
        if let Some(m) = unbooked_b {
            ledger.source(quantity, f64::from(m));
        }
    }
}

fn pair_law_step(ctx: &mut LawCtx<'_, PairCoupling, PairSides>, dt: Seconds) -> Settle {
    let (ta, ca) = (ctx.writes.a.temperature, ctx.writes.a.effective_capacity());
    let (tb, cb) = (ctx.writes.b.temperature, ctx.writes.b.effective_capacity());
    #[allow(clippy::cast_possible_truncation)]
    let moved = pair_exchange(ta, ca, tb, cb, ctx.reads.conductance, dt.0 as f32);
    if moved == 0.0 {
        return Settle::Sleep;
    }
    apply_pair(ctx, moved, -moved);
    Settle::Active
}

/// Body<->environment exchange as a [`Law`]: the stepped path (an exact
/// two-body [`pair_exchange`] every frame). The analytic [`relax_toward`]
/// path is a scheduling optimisation over the same law, not a different
/// one -- see this module's docs.
pub struct BodyEnvironmentExchange;
impl Law for BodyEnvironmentExchange {
    type Reads = PairCoupling;
    type Writes = PairSides;
    const NAME: &'static str = "heat_body_environment_exchange";
    fn step(ctx: &mut LawCtx<'_, PairCoupling, PairSides>, dt: Seconds) -> Settle {
        pair_law_step(ctx, dt)
    }
}

/// Solid<->gas coupling as a [`Law`]: [`solid_gas_exchange`]'s deadbanded
/// exact exchange, replacing `GasExchange`/`GasRef`/`GasProbe`'s job of
/// fetching a gas cell's temperature/capacity for `couple.rs`'s
/// `add_gas_coupling` `Task` to consume.
pub struct SolidGasCoupling;
impl Law for SolidGasCoupling {
    type Reads = PairCoupling;
    type Writes = PairSides;
    const NAME: &'static str = "heat_solid_gas_coupling";
    fn step(ctx: &mut LawCtx<'_, PairCoupling, PairSides>, dt: Seconds) -> Settle {
        let (ts, cs) = (ctx.writes.a.temperature, ctx.writes.a.effective_capacity());
        let (tg, cg) = (ctx.writes.b.temperature, ctx.writes.b.effective_capacity());
        // `conductance` here is `conductivity` (solid_gas_exchange scales it
        // by GAS_COUPLING itself and applies GAS_COUPLING_MIN_K's deadband,
        // unlike the plain pair_law_step every other coupling uses).
        #[allow(clippy::cast_possible_truncation)]
        let moved = solid_gas_exchange(ts, cs, ctx.reads.conductance, tg, cg, dt.0 as f32);
        if moved == 0.0 {
            return Settle::Sleep;
        }
        apply_pair(ctx, moved, -moved);
        Settle::Active
    }
}

/// Body<->gas coupling as a [`Law`]: exactly [`pair_law_step`], the same
/// function [`BodyEnvironmentExchange`] uses -- a body's coupling to a gas
/// cell (turf air, a canister, a tank) is a two-body exchange against
/// whatever temperature/capacity the gas side reports, with no gas-specific
/// physics of its own.
///
/// This is the law `dq_h3_hotspot_heats_items` needs. Today's production
/// path (`domains/gas/src/world.rs`'s `Exchange`) probes a gas cell through
/// a `views` cache that is only republished on a *completed gas field
/// frame*: a body coupled through it can go arbitrarily long without seeing
/// a direct DM write (`T.air.set_temperature()`, exactly what
/// `hotspot_expose()` does) if nothing drives a gas tick in between --
/// which `vg_heat_debug_run_frames`/heat-only frames never do, matching
/// `dq_h3_hotspot_heats_items`'s reported failure exactly (the item never
/// measurably warms, however many heat frames run). A `Law`-driven coupling
/// has no such gap: `ctx.writes.b` is read fresh every step, by
/// construction, whatever store or cell it is wired to once Core B lands.
/// See [`tests::gas_cell_warms_item_body_through_the_hotspot_coupling_law`]
/// for the scenario, reproduced host-side without any gas-tick dependency.
pub struct BodyGasCoupling;
impl Law for BodyGasCoupling {
    type Reads = PairCoupling;
    type Writes = PairSides;
    const NAME: &'static str = "heat_body_gas_coupling";
    fn step(ctx: &mut LawCtx<'_, PairCoupling, PairSides>, dt: Seconds) -> Settle {
        pair_law_step(ctx, dt)
    }
}

/// The Regulator as a heat pump, as a [`Law`]: [`regulator_step`] applied to
/// both sides directly (the controlled body and whatever the rejected/drawn
/// heat's other side is), so a regulator's own settings are `Reads` and
/// both bodies it moves energy between are `Writes` -- matching every other
/// coupling law's shape instead of returning a [`RegulatorStep`] for the
/// caller to apply by hand.
pub struct RegulatorHeatPump;
impl Law for RegulatorHeatPump {
    type Reads = Regulator;
    type Writes = PairSides;
    const NAME: &'static str = "heat_regulator_pump";
    fn step(ctx: &mut LawCtx<'_, Regulator, PairSides>, dt: Seconds) -> Settle {
        #[allow(clippy::cast_possible_truncation)]
        let step = regulator_step(
            ctx.reads,
            ctx.writes.a.temperature,
            ctx.writes.a.effective_capacity(),
            ctx.writes.b.temperature,
            ctx.writes.b.effective_capacity(),
            dt.0 as f32,
        );
        if step.moved == 0.0 && step.other == 0.0 {
            return Settle::Sleep;
        }
        // step.moved is signed into the controlled side; step.other is
        // signed into the other side. apply_pair's amounts are "energy
        // leaving this side", so both are negated.
        apply_pair(ctx, -step.moved, -step.other);
        Settle::Active
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;
    use vg_core::conservation::Ledger;

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

    fn ledger_for(quantity: &'static str, starting_total: f64) -> Ledger {
        let mut ledger = Ledger::new();
        ledger.check(quantity, starting_total, 1e-9).unwrap();
        ledger
    }

    #[test]
    fn body_environment_exchange_law_warms_a_body_from_a_hot_solid() {
        let (body_t, solid_t) = (300.0_f32, 500.0_f32);
        let (cb, cs) = (100.0_f32, 1000.0_f32);
        let mut events: Vec<u32> = Vec::new();
        let mut wakes = Vec::new();
        let mut ledger = ledger_for(
            "heat_energy",
            f64::from(body_t) * f64::from(cb) + f64::from(solid_t) * f64::from(cs),
        );
        let reads = PairCoupling { conductance: 10.0 };
        let mut writes = PairSides {
            a: ThermalSide::mutable(body_t, cb),
            b: ThermalSide::mutable(solid_t, cs),
            quantity: "heat_energy",
        };
        let mut ctx = LawCtx::new(&reads, &mut writes, &mut events, &mut wakes, &mut ledger);
        let settle = BodyEnvironmentExchange::step(&mut ctx, Seconds(1.0));
        assert_eq!(settle, Settle::Active);
        assert!(
            writes.a.temperature > 300.0,
            "body should have warmed: {}",
            writes.a.temperature
        );
        assert!(
            writes.b.temperature < 500.0,
            "solid should have cooled: {}",
            writes.b.temperature
        );
        // Nothing crossed a reservoir boundary: the two-sided total is
        // exactly what it started at.
        let total = f64::from(writes.a.temperature) * f64::from(cb)
            + f64::from(writes.b.temperature) * f64::from(cs);
        assert!(
            ledger
                .check("heat_energy", total, total.abs() * 1e-5 + 1e-3)
                .is_ok()
        );
    }

    /// The scenario `dq_h3_hotspot_heats_items` needs: a hot gas cell (the
    /// hotspot's tile, coupled at `HEAT_TARGET_TURF_AIR`'s conductance) with
    /// an item's heat body on it must warm the body, at the rate
    /// `pair_exchange` predicts -- and, critically, it must do so from
    /// *this step's* gas reading, with no dependency on a separately paced
    /// gas tick or cached view (see [`BodyGasCoupling`]'s doc comment for
    /// why that dependency is exactly today's production bug).
    #[test]
    fn gas_cell_warms_item_body_through_the_hotspot_coupling_law() {
        let (item_t0, gas_t0) = (293.15_f32, 900.0_f32); // room temp item, burning-hot gas
        let (item_capacity, gas_capacity) = (400.0_f32, 2_000.0_f32); // an item's w_class-scaled capacity; a turf's air
        let conductance = 2.0_f32; // FIRE_CONDUCTANCE_PER_W_CLASS-scale coupling
        let dt = 1.0_f32; // one heat frame

        let mut events: Vec<u32> = Vec::new();
        let mut wakes = Vec::new();
        let total0 = f64::from(item_t0) * f64::from(item_capacity)
            + f64::from(gas_t0) * f64::from(gas_capacity);
        let mut ledger = ledger_for("heat_energy", total0);
        let reads = PairCoupling { conductance };
        let mut writes = PairSides {
            a: ThermalSide::mutable(item_t0, item_capacity),
            b: ThermalSide::mutable(gas_t0, gas_capacity),
            quantity: "heat_energy",
        };

        // The exact energy the underlying law predicts, computed
        // independently so this test would catch a law/wiring mismatch,
        // not just "the body warmed at all".
        let expected_moved = pair_exchange(
            item_t0,
            item_capacity,
            gas_t0,
            gas_capacity,
            conductance,
            dt,
        );
        assert!(
            expected_moved < 0.0,
            "energy should flow from the hot gas to the item"
        );

        let mut ctx = LawCtx::new(&reads, &mut writes, &mut events, &mut wakes, &mut ledger);
        let settle = BodyGasCoupling::step(&mut ctx, Seconds(f64::from(dt)));
        assert_eq!(settle, Settle::Active);

        let expected_item_t = item_t0 - expected_moved / item_capacity;
        assert!(
            (writes.a.temperature - expected_item_t).abs() < 1e-3,
            "item should warm at the rate pair_exchange predicts: got {}, expected {expected_item_t}",
            writes.a.temperature
        );
        assert!(
            writes.a.temperature > item_t0,
            "the coupled item must measurably warm: {}",
            writes.a.temperature
        );
        assert!(
            writes.b.temperature < gas_t0,
            "the gas must measurably cool as it gives up energy: {}",
            writes.b.temperature
        );

        // Conserved exactly (no reservoir on either side this step).
        let total1 = f64::from(writes.a.temperature) * f64::from(item_capacity)
            + f64::from(writes.b.temperature) * f64::from(gas_capacity);
        assert!(
            ledger
                .check("heat_energy", total1, total1.abs() * 1e-5 + 1e-3)
                .is_ok()
        );

        // Running it again with the *same* Writes (as a real driver would,
        // reading whatever's currently there, not a stale snapshot) keeps
        // warming the item every step until they equalize -- proving there
        // is no hidden dependency on an external refresh between calls.
        let before_second = writes.a.temperature;
        let mut events2 = Vec::new();
        let mut wakes2 = Vec::new();
        let mut ctx2 = LawCtx::new(&reads, &mut writes, &mut events2, &mut wakes2, &mut ledger);
        BodyGasCoupling::step(&mut ctx2, Seconds(f64::from(dt)));
        assert!(
            writes.a.temperature > before_second,
            "must keep warming step over step: {} vs {before_second}",
            writes.a.temperature
        );
    }

    #[test]
    fn body_gas_coupling_law_sleeps_at_equilibrium() {
        let mut events: Vec<u32> = Vec::new();
        let mut wakes = Vec::new();
        let mut ledger = ledger_for("heat_energy", 300.0 * 400.0 + 300.0 * 2000.0);
        let reads = PairCoupling { conductance: 5.0 };
        let mut writes = PairSides {
            a: ThermalSide::mutable(300.0, 400.0),
            b: ThermalSide::mutable(300.0, 2000.0),
            quantity: "heat_energy",
        };
        let mut ctx = LawCtx::new(&reads, &mut writes, &mut events, &mut wakes, &mut ledger);
        assert_eq!(BodyGasCoupling::step(&mut ctx, Seconds(1.0)), Settle::Sleep);
    }

    #[test]
    fn body_gas_coupling_law_against_a_reservoir_books_the_ledger_not_a_temperature() {
        let mut events: Vec<u32> = Vec::new();
        let mut wakes = Vec::new();
        // Only the item's side is part of the tracked total; the reservoir
        // is external, so the starting total is just the item's energy.
        let mut ledger = ledger_for("heat_energy", 200.0 * 100.0);
        let reads = PairCoupling { conductance: 8.0 };
        let mut writes = PairSides {
            a: ThermalSide::mutable(200.0, 100.0),
            b: ThermalSide::reservoir(400.0), // a hot, immutable gas reservoir (e.g. a planet's atmosphere)
            quantity: "heat_energy",
        };
        let mut ctx = LawCtx::new(&reads, &mut writes, &mut events, &mut wakes, &mut ledger);
        BodyGasCoupling::step(&mut ctx, Seconds(1.0));
        assert!(
            writes.a.temperature > 200.0,
            "item should warm from the reservoir: {}",
            writes.a.temperature
        );
        // The reservoir's contribution was booked as an explicit source, so
        // the ledger reconciles even though nothing represents its own
        // temperature in this total.
        let total = f64::from(writes.a.temperature) * 100.0;
        assert!(ledger.check("heat_energy", total, 1e-3).is_ok());
    }

    #[test]
    fn solid_gas_coupling_law_matches_the_pure_function() {
        let mut events: Vec<u32> = Vec::new();
        let mut wakes = Vec::new();
        let mut ledger = ledger_for("heat_energy", 400.0 * 1000.0 + 300.0 * 500.0);
        let reads = PairCoupling { conductance: 0.5 }; // conductivity
        let mut writes = PairSides {
            a: ThermalSide::mutable(400.0, 1000.0),
            b: ThermalSide::mutable(300.0, 500.0),
            quantity: "heat_energy",
        };
        let expected = solid_gas_exchange(400.0, 1000.0, 0.5, 300.0, 500.0, 1.0);
        let mut ctx = LawCtx::new(&reads, &mut writes, &mut events, &mut wakes, &mut ledger);
        SolidGasCoupling::step(&mut ctx, Seconds(1.0));
        assert!((writes.a.temperature - (400.0 - expected / 1000.0)).abs() < 1e-4);
    }

    #[test]
    fn regulator_heat_pump_law_conserves_and_matches_regulator_step() {
        let regulator = Regulator {
            target: 310.0,
            max_power: 500.0,
            mode: RegulatorMode::Both,
            carnot_fraction: 0.4,
            max_cop: 5.0,
            resistive_heating: false,
            deadband: 0.05,
        };
        let (cc, co) = (50.0_f32, 1_000_000.0_f32); // other is effectively a huge sink
        let expected = regulator_step(&regulator, 280.0, cc, 293.0, co, 1.0);

        let mut events: Vec<u32> = Vec::new();
        let mut wakes = Vec::new();
        let mut ledger = ledger_for(
            "heat_energy",
            f64::from(280.0_f32) * f64::from(cc) + f64::from(293.0_f32) * f64::from(co),
        );
        let mut writes = PairSides {
            a: ThermalSide::mutable(280.0, cc),
            b: ThermalSide::mutable(293.0, co),
            quantity: "heat_energy",
        };
        let mut ctx = LawCtx::new(
            &regulator,
            &mut writes,
            &mut events,
            &mut wakes,
            &mut ledger,
        );
        let settle = RegulatorHeatPump::step(&mut ctx, Seconds(1.0));
        assert_eq!(settle, Settle::Active);
        assert!(
            writes.a.temperature > 280.0,
            "heating: controlled body should warm: {}",
            writes.a.temperature
        );
        assert!(
            (writes.a.temperature - (280.0 + expected.moved / cc)).abs() < 1e-3,
            "law's result should match regulator_step exactly"
        );
        let total = f64::from(writes.a.temperature) * f64::from(cc)
            + f64::from(writes.b.temperature) * f64::from(co);
        assert!(
            ledger
                .check("heat_energy", total, total.abs() * 1e-5 + 1e-2)
                .is_ok()
        );
    }
}
