//! Heat bodies: nodes for objects, machines and containers
//! (`temperature.md` §2.2, `simulation.md` §7).
//!
//! An item follows its surroundings until something heats or cools it
//! directly; only then does it get a body (DM's `add_heat` creates one on
//! first divergence), and the body is released when it is back at
//! equilibrium, returning its excess energy to its environment.
//!
//! A body has a heat capacity, an optional phase plateau (latent heat at a
//! phase temperature: `material_service`'s phase buffer), a power source or
//! sink in watts, and up to two [`Coupling`]s, each a conductance (W/K) to a
//! turf solid cell, a gas (turf air or a mixture by id) or another body (a
//! container).
//!
//! # Two ways to advance
//! - **Analytic** (`RELAX`): one coupling, no phase, and an environment that
//!   is a reservoir or has at least [`RELAX_CAPACITY_RATIO`] times the
//!   body's capacity. The body follows
//!   `T(t) = T∞ + (T0 − T∞)·e^(−(G/C)(t − t0))` with `T∞ = Ta + P/G` and is
//!   not stepped: the frame task only reads the environment, and settles
//!   the model (moves the exchanged energy into the environment and
//!   re-anchors) when the environment moves past [`RELAX_HYSTERESIS_K`], on
//!   a command, when a watched level is crossed (crossing times are solved
//!   exactly, as the reactor's `RateModel::Relax`), at equilibrium, or after
//!   [`RELAX_MAX_INTERVAL`].
//! - **Stepped**: otherwise, each frame applies the exact two-body solution
//!   per coupling ([`pair_exchange`]), which is stable for any step.
//!
//! Every exchange writes both sides with the same number (or the ledger for
//! a reservoir), so energy is conserved exactly apart from `f32` rounding.

use std::sync::Arc;

use vg_core::cow::ChunkLayout;
use vg_core::field::{FieldKey, Geom};
use vg_core::frame::Task;
use vg_core::outbox::{Event, EventKind};
use vg_core::owner::{Applied, Domain, DomainKey};
use vg_core::rate::RateModel;
use vg_core::sim::SimBuilder;

use crate::consts::{
    BODY_LEVELS, BODY_SETTLED_K, MAX_BODIES, RELAX_CAPACITY_RATIO, RELAX_HYSTERESIS_K,
    RELAX_MAX_INTERVAL, TCMB,
};
use crate::couple::{GasExchange, GasRef, HeatLedger, ledger, pair_exchange};
use crate::solid::SolidHeat;

/// What a coupling reaches.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub enum Target {
    #[default]
    None,
    /// A turf's solid heat cell.
    Solid(u32),
    /// A gas: turf air or a mixture.
    Gas(GasRef),
    /// Another body (the container's interior).
    Body(u32),
}

/// A conductance to a target.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Coupling {
    pub target: Target,
    /// W/K.
    pub conductance: f32,
}

impl Coupling {
    #[must_use]
    pub const fn new(target: Target, conductance: f32) -> Self {
        Self {
            target,
            conductance,
        }
    }

    #[must_use]
    pub fn is_live(&self) -> bool {
        !matches!(self.target, Target::None) && self.conductance > 0.0
    }
}

/// A phase plateau: heating through `temperature` first fills `latent`
/// joules at constant temperature (and cooling empties it).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Phase {
    pub temperature: f32,
    pub latent: f32,
}

impl Phase {
    #[must_use]
    pub fn is_active(&self) -> bool {
        self.latent > 0.0 && self.temperature > 0.0
    }
}

/// Body state flags.
pub mod state {
    /// Following the exact relaxation model (not stepped).
    pub const RELAX: u8 = 1;
    /// A command changed the body since the task last saw it.
    pub const DIRTY: u8 = 2;
    /// Never released at equilibrium (DM holds it: a machine's interior).
    pub const KEEP: u8 = 4;
    /// Release at the next frame.
    pub const RELEASE: u8 = 8;
    /// Reported to the host as at equilibrium.
    pub const SETTLED: u8 = 16;
}

/// One heat body. Capacity 0 is a free slot.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Body {
    /// J: sensible heat plus the filled part of the phase plateau. For an
    /// analytic body, the energy at `since`.
    pub energy: f32,
    /// J/K.
    pub capacity: f32,
    /// K (for an analytic body, the temperature at `since`).
    pub temperature: f32,
    /// W in effect (analytic: since `since`).
    pub power: f32,
    /// W from the next frame on.
    pub power_next: f32,
    /// Heat added by commands since the analytic model's anchor, J.
    pub pending: f32,
    pub couplings: [Coupling; 2],
    pub phase: Phase,
    pub generation: u8,
    pub state: u8,
    /// Anchor time of the analytic model, s.
    pub since: f64,
    /// Environment temperature at the anchor.
    pub ambient: f32,
    /// Next time the analytic model must be settled, s.
    pub due: f64,
    /// Energy that left through coupling 0 in the last settle or step, J
    /// (thermoelectric conversion and diagnostics read it).
    pub flow: f32,
    /// Watched levels, for crossing prediction (`levels_len` used).
    pub levels: [f32; BODY_LEVELS],
    pub levels_len: u8,
}

/// Temperature of `energy` in a body of `capacity` with `phase`.
#[must_use]
pub fn temperature_of(energy: f32, capacity: f32, phase: Phase) -> f32 {
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

/// Energy of a body at `temperature` (the plateau empty at exactly the phase
/// temperature, full above it).
#[must_use]
pub fn energy_at(temperature: f32, capacity: f32, phase: Phase) -> f32 {
    let sensible = capacity * temperature;
    if phase.is_active() && temperature > phase.temperature {
        sensible + phase.latent
    } else {
        sensible
    }
}

impl Body {
    /// A new body at `temperature`.
    #[must_use]
    pub fn new(capacity: f32, temperature: f32) -> Self {
        let t = temperature.max(TCMB);
        Self {
            energy: capacity * t,
            capacity,
            temperature: t,
            state: state::DIRTY,
            ambient: t,
            ..Self::default()
        }
    }

    #[must_use]
    pub const fn with_coupling(mut self, i: usize, coupling: Coupling) -> Self {
        self.couplings[i] = coupling;
        self
    }

    #[must_use]
    pub const fn with_power(mut self, watts: f32) -> Self {
        self.power = watts;
        self.power_next = watts;
        self
    }

    #[must_use]
    pub fn with_phase(mut self, phase: Phase) -> Self {
        self.phase = phase;
        self.energy = energy_at(self.temperature, self.capacity, phase);
        self
    }

    #[must_use]
    pub const fn with_generation(mut self, generation: u8) -> Self {
        self.generation = generation;
        self
    }

    #[must_use]
    pub const fn kept(mut self) -> Self {
        self.state |= state::KEEP;
        self
    }

    #[must_use]
    pub const fn is_live(&self) -> bool {
        self.capacity > 0.0
    }

    #[must_use]
    pub const fn has(&self, flag: u8) -> bool {
        self.state & flag != 0
    }

    fn floor(&self) -> f32 {
        self.capacity * TCMB
    }

    /// Asymptote of the analytic model.
    fn relax_target(&self) -> f32 {
        let g = self.couplings[0].conductance;
        if g > 0.0 {
            self.ambient + self.power / g
        } else {
            self.ambient
        }
    }

    fn relax_rate(&self) -> f64 {
        f64::from(self.couplings[0].conductance) / f64::from(self.capacity)
    }

    fn relax_model(&self) -> RateModel {
        RateModel::Relax {
            target: f64::from(self.relax_target()),
            v0: f64::from(self.temperature),
            k: self.relax_rate(),
            t0: self.since,
        }
    }

    /// The temperature at time `now` (the analytic model, or the stored
    /// value), including heat added since the last settle.
    #[must_use]
    pub fn temperature_at(&self, now: f64) -> f32 {
        if !self.is_live() {
            return 0.0;
        }
        if self.has(state::RELAX) {
            #[allow(clippy::cast_possible_truncation)]
            let t = self.relax_model().value_at(now.max(self.since)) as f32;
            (t + self.pending / self.capacity).max(TCMB)
        } else {
            self.temperature
        }
    }

    /// The energy the books hold for this body: for an analytic body, the
    /// anchor energy plus pending heat. What its source supplied and what it
    /// exchanged since the anchor are booked when the model settles, both
    /// sides at once.
    #[must_use]
    pub fn books_energy(&self) -> f64 {
        f64::from(self.energy) + f64::from(self.pending)
    }

    /// The energy at `now` (see [`temperature_at`](Self::temperature_at)).
    #[must_use]
    pub fn energy_at(&self, now: f64) -> f32 {
        if self.has(state::RELAX) {
            energy_at(self.temperature_at(now), self.capacity, self.phase)
        } else {
            self.energy
        }
    }

    fn refresh(&mut self) {
        self.temperature = temperature_of(self.energy, self.capacity, self.phase);
    }

    /// Adds `e` to the stored energy, clamped at the TCMB floor. Returns
    /// what was actually added.
    fn add(&mut self, e: f32) -> f32 {
        let before = self.energy;
        self.energy = (self.energy + e).max(self.floor());
        self.refresh();
        self.energy - before
    }

    /// Adds heat from outside the model (a body coupled to this one as its
    /// environment). Returns what was applied.
    fn deposit(&mut self, e: f32) -> f32 {
        if self.has(state::RELAX) {
            // Never take more than the body holds above its floor.
            let e = e.max(-(self.energy + self.pending - self.floor()).max(0.0));
            self.pending += e;
            self.state = (self.state | state::DIRTY) & !state::SETTLED;
            e
        } else {
            self.add(e)
        }
    }
}

/// Commands DM sends a body. A new body is a `Put`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum BodyCmd {
    /// Adds heat (negative removes; clamps at the TCMB floor and reports
    /// the shortfall).
    AddHeat(f32),
    /// Sets a sustained source (negative: sink), W, from the next frame.
    Power(f32),
    /// Sets coupling 0 or 1.
    Couple(u8, Coupling),
    /// Changes the heat capacity, keeping the temperature.
    Capacity(f32),
    /// Changes the phase plateau, keeping the temperature.
    Phase(Phase),
    /// Sets the temperature (DM authority).
    SetTemperature(f32),
    /// Watched levels (up to [`BODY_LEVELS`]; NaN entries are unused).
    Levels([f32; BODY_LEVELS]),
    /// Never release at equilibrium (true), or allow it (false).
    Keep(bool),
    /// Release at the next frame: excess energy goes to coupling 0.
    Release,
}

/// The bodies domain (linear slots).
pub struct Bodies;

impl Domain for Bodies {
    type Value = Body;
    type Command = BodyCmd;
    const NAME: &'static str = "heat_bodies";

    fn apply(b: &mut Body, cmd: &BodyCmd) -> Applied {
        if !b.is_live() {
            return match *cmd {
                BodyCmd::AddHeat(e) => Applied { shortfall: e.abs() },
                _ => Applied::default(),
            };
        }
        match *cmd {
            BodyCmd::AddHeat(e) => {
                if b.has(state::RELAX) {
                    // Settled against the model at the next frame; clamp
                    // against the anchor energy as a bound.
                    let room = b.energy + b.pending - b.floor();
                    let e2 = e.max(-room.max(0.0));
                    b.pending += e2;
                    b.state = (b.state | state::DIRTY) & !state::SETTLED;
                    return Applied {
                        shortfall: (e2 - e).max(0.0),
                    };
                }
                let added = b.add(e);
                b.state = (b.state | state::DIRTY) & !state::SETTLED;
                return Applied {
                    shortfall: (added - e).max(0.0),
                };
            }
            BodyCmd::Power(w) => b.power_next = w,
            BodyCmd::Couple(i, c) => {
                if let Some(slot) = b.couplings.get_mut(usize::from(i)) {
                    *slot = c;
                }
            }
            BodyCmd::Capacity(c) if c > 0.0 => {
                if !b.has(state::RELAX) {
                    b.energy = energy_at(b.temperature, c, b.phase);
                }
                b.capacity = c;
                if b.has(state::RELAX) {
                    // Keep the anchor's temperature; the model restarts.
                    b.energy = energy_at(b.temperature, c, b.phase);
                }
            }
            BodyCmd::Capacity(_) => {}
            BodyCmd::Phase(p) => {
                b.phase = p;
                b.energy = energy_at(b.temperature, b.capacity, p);
            }
            BodyCmd::SetTemperature(t) => {
                let t = t.max(TCMB);
                b.temperature = t;
                b.energy = energy_at(t, b.capacity, b.phase);
                b.pending = 0.0;
                b.state &= !state::RELAX;
            }
            BodyCmd::Levels(levels) => {
                let mut n = 0;
                let mut out = [f32::NAN; BODY_LEVELS];
                for l in levels.into_iter().filter(|l| l.is_finite()) {
                    out[n] = l;
                    n += 1;
                }
                b.levels = out;
                b.levels_len = u8::try_from(n).unwrap_or(0);
            }
            BodyCmd::Keep(keep) => {
                if keep {
                    b.state |= state::KEEP;
                } else {
                    b.state &= !state::KEEP;
                }
            }
            BodyCmd::Release => b.state |= state::RELEASE,
        }
        b.state = (b.state | state::DIRTY) & !state::SETTLED;
        Applied::default()
    }
}

vg_core::channels! { pub mod body_ch for Bodies {
    TEMPERATURE: Scalar<Kelvin> hysteresis 0.1 => |b, o| o[0] = b.temperature,
}}

/// Body slots layout.
#[must_use]
pub fn layout() -> ChunkLayout {
    ChunkLayout::linear(MAX_BODIES)
}

/// An environment as a body sees it.
#[derive(Clone, Copy, Debug)]
struct Env {
    temperature: f32,
    /// `INFINITY` for a reservoir.
    capacity: f32,
}

impl Env {
    fn is_reservoir_for(&self, capacity: f32) -> bool {
        !self.capacity.is_finite() || self.capacity >= RELAX_CAPACITY_RATIO * capacity
    }
}

/// Everything a body frame reads and writes.
struct Stores<'a> {
    cells: &'a mut vg_core::cow::CowStore<crate::solid::SolidCell>,
    geom: &'a vg_core::cow::CowStore<Geom>,
    bodies: &'a mut vg_core::cow::CowStore<Body>,
    gas: &'a dyn GasExchange,
    /// Ledger deltas: indexed by `ledger::*`.
    ledger: [f64; ledger::LEN as usize],
}

impl Stores<'_> {
    fn probe(&self, target: Target, skip: u32) -> Option<Env> {
        match target {
            Target::None => None,
            Target::Solid(i) => {
                let g = self.geom.get(i)?;
                if !g.is_node() {
                    return None;
                }
                let c = self.cells.get(i)?;
                Some(Env {
                    temperature: c.temperature_in(g.capacity),
                    capacity: if g.reservoir {
                        f32::INFINITY
                    } else {
                        g.capacity
                    },
                })
            }
            Target::Gas(r) => {
                let p = self.gas.probe(r)?;
                (p.capacity > 0.0).then_some(Env {
                    temperature: p.temperature,
                    capacity: if p.reservoir {
                        f32::INFINITY
                    } else {
                        p.capacity
                    },
                })
            }
            Target::Body(j) if j != skip => {
                let b = self.bodies.get(j)?;
                b.is_live().then_some(Env {
                    temperature: b.temperature,
                    capacity: b.capacity,
                })
            }
            Target::Body(_) => None,
        }
    }

    /// Moves `e` into `target` (negative: out of it). Returns what was
    /// applied (`None`: nothing, retry later). Reservoir inflow goes to the
    /// ledger.
    fn deposit(&mut self, target: Target, e: f32) -> Option<f32> {
        if e == 0.0 {
            return Some(0.0);
        }
        match target {
            Target::None => None,
            Target::Solid(i) => {
                let g = self.geom.get(i)?;
                if !g.is_node() {
                    return None;
                }
                if g.reservoir {
                    self.ledger[ledger::BODY_RESERVOIRS as usize] += f64::from(e);
                    return Some(e);
                }
                let c = self.cells.get_mut(i)?;
                let before = c.energy;
                c.energy = (c.energy + e).max(0.0);
                c.temperature = c.energy / g.capacity;
                Some(c.energy - before)
            }
            Target::Gas(r) => {
                let mut reservoir = false;
                let applied = self.gas.exchange(r, &mut |p| {
                    reservoir = p.reservoir;
                    e
                })?;
                self.book_gas(applied, reservoir);
                Some(applied)
            }
            Target::Body(j) => {
                let b = self.bodies.get_mut(j)?;
                if !b.is_live() {
                    return None;
                }
                Some(b.deposit(e))
            }
        }
    }

    fn book_gas(&mut self, applied: f32, reservoir: bool) {
        let slot = if reservoir {
            ledger::GAS_RESERVOIRS
        } else {
            ledger::GAS
        };
        self.ledger[slot as usize] += f64::from(applied);
    }

    /// Exact exchange of body `b` (index `i`) over coupling `c` for `dt`.
    /// Returns the energy that left the body.
    fn exchange(&mut self, i: u32, b: &mut Body, c: Coupling, dt: f32) -> Option<f32> {
        if !c.is_live() {
            return Some(0.0);
        }
        let (tb, cb) = (b.temperature, b.capacity);
        let moved = if let Target::Gas(r) = c.target {
            let mut reservoir = false;
            let applied = self.gas.exchange(r, &mut |p| {
                reservoir = p.reservoir;
                if p.capacity <= 0.0 {
                    return 0.0;
                }
                let ce = if p.reservoir {
                    f32::INFINITY
                } else {
                    p.capacity
                };
                let m = pair_exchange(tb, cb, p.temperature, ce, c.conductance, dt);
                // The body cannot go below its floor.
                m.min(b.energy - b.floor())
            })?;
            self.book_gas(applied, reservoir);
            applied
        } else {
            let env = self.probe(c.target, i)?;
            let m = pair_exchange(tb, cb, env.temperature, env.capacity, c.conductance, dt)
                .min(b.energy - b.floor());
            self.deposit(c.target, m)?
        };
        b.energy -= moved;
        b.refresh();
        Some(moved)
    }
}

/// Registers the bodies domain and its frame task (after the field and the
/// gas coupling). Returns the domain key.
pub fn add_bodies(
    builder: &mut SimBuilder,
    field: FieldKey<SolidHeat>,
    ledger_key: DomainKey<HeatLedger>,
    gas: Arc<dyn GasExchange>,
    dt: f32,
) -> DomainKey<Bodies> {
    let bodies = builder.add_domain::<Bodies>(layout());
    let (geom_res, cells_res, bodies_res, ledger_res) = (
        field.geometry.state(),
        field.cells.state(),
        bodies.state(),
        ledger_key.state(),
    );
    builder.add_task(
        Task::new("heat:bodies", move |ctx| {
            #[allow(clippy::cast_precision_loss)]
            // Commands apply at the start of the frame: that is the time
            // DM saw when it sent them (the host clock counts dispatched
            // frames), so the models anchor there.
            let now = ctx.frame() as f64 * f64::from(dt);
            let geom = ctx.read(geom_res);
            let mut cells = ctx.write(cells_res);
            let mut dom = ctx.write(bodies_res);
            let live: Vec<u32> = {
                let store = &dom.store;
                let layout = store.layout();
                (0..layout.chunk_count())
                    .filter_map(|c| store.chunk(c).map(|v| (c, v)))
                    .flat_map(|(c, v)| {
                        v.iter()
                            .enumerate()
                            .filter(|(_, b)| b.is_live())
                            .filter_map(move |(i, _)| layout.index_of(c, i))
                    })
                    .collect()
            };
            if live.is_empty() {
                return;
            }
            let mut events = Vec::new();
            let mut stores = Stores {
                cells: &mut cells.store,
                geom: &geom.store,
                bodies: &mut dom.store,
                gas: &*gas,
                ledger: [0.0; ledger::LEN as usize],
            };
            for i in live {
                let Some(before) = stores.bodies.get(i) else {
                    continue;
                };
                if !before.is_live() {
                    continue;
                }
                let mut b = before;
                if let Some(ev) = advance(&mut stores, i, &mut b, now, dt) {
                    events.push(ev);
                }
                if b != before {
                    stores.bodies.set(i, b);
                }
            }
            let deltas = stores.ledger;
            for e in events {
                dom.outbox_mut().push_event(e);
            }
            drop(dom);
            drop(cells);
            if deltas.iter().any(|&d| d != 0.0) {
                let mut l = ctx.write(ledger_res);
                for (k, d) in deltas.iter().enumerate() {
                    if *d != 0.0 {
                        if let Some(v) = l.store.get_mut(u32::try_from(k).unwrap_or(0)) {
                            *v += d;
                        }
                    }
                }
            }
        })
        .reads(geom_res.id())
        .writes(cells_res.id())
        .writes(bodies_res.id())
        .writes(ledger_res.id()),
    );
    bodies
}

/// Settles an analytic body at `now`: moves the energy it exchanged since
/// the anchor into its environment and folds in pending heat. Returns false
/// (changing nothing) if the environment could not be written.
fn settle(s: &mut Stores<'_>, b: &mut Body, now: f64) -> bool {
    #[allow(clippy::cast_possible_truncation)]
    let t = (b.relax_model().value_at(now.max(b.since)) as f32).max(TCMB);
    let e_new = b.capacity * t;
    #[allow(clippy::cast_possible_truncation)]
    let supplied = (f64::from(b.power) * (now - b.since).max(0.0)) as f32;
    let out = b.energy + supplied - e_new;
    let target = b.couplings[0].target;
    let applied = if matches!(target, Target::None) {
        // The coupling was removed under the model: nowhere to put it.
        s.ledger[ledger::LOST as usize] += f64::from(out);
        out
    } else {
        let Some(applied) = s.deposit(target, out) else {
            return false;
        };
        applied
    };
    s.ledger[ledger::POWER as usize] += f64::from(supplied);
    b.flow = applied;
    let raw = b.energy + supplied - applied + b.pending;
    b.pending = 0.0;
    b.energy = raw.max(b.floor());
    // A sink or a removal that would take the body below TCMB stops at the
    // floor; the difference is booked, not created.
    s.ledger[ledger::LOST as usize] += f64::from(raw - b.energy);
    b.state &= !state::RELAX;
    b.refresh();
    true
}

/// Anchors an analytic model at `now` against environment `env`.
fn anchor(b: &mut Body, env: Env, now: f64) {
    b.state |= state::RELAX;
    b.since = now;
    b.ambient = env.temperature;
    b.power = b.power_next;
    let model = b.relax_model();
    let target = b.relax_target();
    let mut due = now + f64::from(RELAX_MAX_INTERVAL);
    for &level in &b.levels[..usize::from(b.levels_len)] {
        if let Some(t) = model.crossing(f64::from(level), now) {
            due = due.min(t);
        }
    }
    if releasable(b) {
        let gap = f64::from((b.temperature - target).abs());
        let settled = f64::from(BODY_SETTLED_K) * 0.5;
        if gap > settled {
            let k = b.relax_rate();
            if k > 0.0 {
                due = due.min(now + (gap / settled).ln() / k);
            }
        } else {
            due = now;
        }
    }
    b.due = due;
}

fn releasable(b: &Body) -> bool {
    !b.has(state::KEEP) && b.power == 0.0 && b.power_next == 0.0 && b.pending == 0.0
}

/// Releases body `i`: its excess over its environment goes to coupling 0's
/// target, and its baseline leaves the books (ledger `RELEASED`).
fn release(s: &mut Stores<'_>, i: u32, b: &mut Body, now: f64) -> Option<Event> {
    if b.has(state::RELAX) && !settle(s, b, now) {
        return None;
    }
    let target = b.couplings[0].target;
    let env = s.probe(target, i);
    let baseline_t = env.map_or(b.temperature, |e| e.temperature);
    let baseline = energy_at(baseline_t, b.capacity, b.phase).max(0.0);
    let excess = b.energy + b.pending - baseline;
    let applied = if env.is_some() {
        s.deposit(target, excess)?
    } else {
        0.0
    };
    s.ledger[ledger::RELEASED as usize] += f64::from(b.energy + b.pending - applied);
    let event = Event {
        kind: EventKind::Destroyed,
        key: i,
        value: b.temperature,
        extra: 0,
        generation: u32::from(b.generation),
    };
    *b = Body::default();
    Some(event)
}

/// One frame of body `i`. Returns an event for the host: `Destroyed` when
/// the body was released, [`SETTLED`] when it reached equilibrium (the host
/// then releases it with a command, ordered after any heat DM sent it, so
/// nothing DM adds can land on a freed slot).
fn advance(s: &mut Stores<'_>, i: u32, b: &mut Body, now: f64, dt: f32) -> Option<Event> {
    if b.has(state::RELEASE) {
        return release(s, i, b, now);
    }
    let c0 = b.couplings[0];
    let env0 = if c0.is_live() {
        s.probe(c0.target, i)
    } else {
        None
    };
    let analytic = !b.couplings[1].is_live()
        && !b.phase.is_active()
        && env0.is_some_and(|e| e.is_reservoir_for(b.capacity));

    if b.has(state::RELAX) {
        let env_moved = env0.is_none_or(|e| (e.temperature - b.ambient).abs() > RELAX_HYSTERESIS_K);
        let due = now >= b.due;
        if !(b.has(state::DIRTY) || env_moved || due || !analytic) {
            return None;
        }
        if !settle(s, b, now) {
            return None;
        }
        b.state &= !state::DIRTY;
        if analytic {
            anchor(b, env0.expect("analytic has an environment"), now);
        }
        return settled_event(s, i, b);
    }

    if analytic {
        b.state &= !state::DIRTY;
        anchor(b, env0.expect("analytic has an environment"), now);
        return settled_event(s, i, b);
    }

    // Stepped: power, then the exact exchange on each coupling.
    b.power = b.power_next;
    b.state &= !state::DIRTY;
    if b.power != 0.0 {
        let added = b.add(b.power * dt);
        s.ledger[ledger::POWER as usize] += f64::from(added);
    }
    let mut flow = 0.0;
    for (k, c) in b.couplings.into_iter().enumerate() {
        if let Some(m) = s.exchange(i, b, c, dt) {
            if k == 0 {
                flow = m;
            }
        }
    }
    b.flow = flow;
    settled_event(s, i, b)
}

/// The event a body at equilibrium sends the host (once).
pub const SETTLED: EventKind = EventKind::Restore;

fn settled_event(s: &Stores<'_>, i: u32, b: &mut Body) -> Option<Event> {
    if b.has(state::SETTLED) || !releasable(b) || !at_equilibrium(s, i, b) {
        return None;
    }
    b.state |= state::SETTLED;
    Some(Event {
        kind: SETTLED,
        key: i,
        value: b.temperature,
        extra: 0,
        generation: u32::from(b.generation),
    })
}

/// Whether every live coupling's environment is within the settle band.
/// A body with no live coupling is never at equilibrium (nothing to relax
/// to).
fn at_equilibrium(s: &Stores<'_>, i: u32, b: &Body) -> bool {
    let mut any = false;
    for c in b.couplings.iter().filter(|c| c.is_live()) {
        let Some(env) = s.probe(c.target, i) else {
            return false;
        };
        any = true;
        if (env.temperature - b.temperature).abs() >= BODY_SETTLED_K {
            return false;
        }
    }
    any
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn phase_plateau_maps_energy_both_ways() {
        let p = Phase {
            temperature: 300.0,
            latent: 1_000.0,
        };
        assert_eq!(temperature_of(100.0 * 299.0, 100.0, p), 299.0);
        assert_eq!(temperature_of(100.0 * 300.0 + 500.0, 100.0, p), 300.0);
        assert_eq!(temperature_of(100.0 * 301.0 + 1_000.0, 100.0, p), 301.0);
        assert_eq!(energy_at(301.0, 100.0, p), 100.0 * 301.0 + 1_000.0);
    }

    #[test]
    fn commands_clamp_at_the_floor_and_keep_temperature() {
        let mut b = Body::new(10.0, 300.0);
        let a = Bodies::apply(&mut b, &BodyCmd::AddHeat(-10_000.0));
        assert_eq!(b.temperature, TCMB);
        assert!((a.shortfall - (10_000.0 - 10.0 * (300.0 - TCMB))).abs() < 1e-2);
        let mut b = Body::new(10.0, 300.0);
        Bodies::apply(&mut b, &BodyCmd::Capacity(20.0));
        assert_eq!(b.energy, 6_000.0);
        assert_eq!(b.temperature, 300.0);
    }
}
