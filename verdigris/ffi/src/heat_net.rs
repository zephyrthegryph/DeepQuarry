//! The heat network (`temperature.md` §2.3): persistent heat edges between
//! reservoirs of every kind, integrated once per world step, plus the one-off
//! [`heat_move`] for events. All maths is `vg_core::thermo::transfer`; this
//! module only adapts storage:
//!
//! | DM kind | Reservoir | Storage |
//! |---|---|---|
//! | `HEAT_TARGET_MIXTURE` | a `/datum/gas_mixture` (or its handle) | main slab, pipe region or turf cell |
//! | `HEAT_TARGET_TURF_AIR` | a turf's air | the `TurfGas` cell |
//! | `HEAT_TARGET_PIPE_PORT` | the pipe region a port is in (follows merges/splits) | the region payload |
//! | `HEAT_TARGET_BODY` | a heat body (`vg_heat_body_create`) | the `HeatBody` row |
//! | `HEAT_TARGET_SOLID` | a turf's solid | the solid heat field cell |
//! | `HEAT_TARGET_SPACE` | outer space at a temperature (the ref, K) | none: infinite |
//!
//! A step reads every touched reservoir once, runs every edge on that
//! snapshot (each edge sees the ones before it: an exact, conserving
//! Gauss–Seidel sweep), then writes each reservoir's net change back in one
//! write. A gas write goes through `gas::mix::add_amounts`, which bumps the
//! mixture's revision and wakes its pipe network or turf: DM never marks
//! anything dirty after heat. Every transfer and every external work in or
//! out is booked per step ([`Books`]); debug builds assert the books balance.

use std::cell::RefCell;
use std::collections::HashMap;

use byondapi::prelude::*;
use eyre::{Result, bail};
use vg_core::thermo::transfer::{self, Books, Edge, EdgeKind, Flow, Reservoirs, State};
use vg_core::thermo::{Regulator, RegulatorMode};
use vg_heat::HeatBody;
use vg_heat::components::gas_kind;

use crate::gas::mix::{self, MixRef};
use crate::heat::{
    HEAT_TARGET_BODY, HEAT_TARGET_MIXTURE, HEAT_TARGET_NONE, HEAT_TARGET_PIPE_PORT, HEAT_TARGET_SOLID,
    HEAT_TARGET_TURF_AIR,
};
use crate::world::{list, num, with_world};

/// Outer space as a reservoir: the ref is its temperature in K.
/// @dm-define HEAT_TARGET_SPACE
#[allow(dead_code)]
pub const HEAT_TARGET_SPACE: i32 = 6;

/// Edge kinds (`heat_edge_info`'s first number).
/// @dm-define HEAT_EDGE_LINK
#[allow(dead_code)]
pub const HEAT_EDGE_LINK: i32 = 1;
/// @dm-define HEAT_EDGE_PUMP
#[allow(dead_code)]
pub const HEAT_EDGE_PUMP: i32 = 2;
/// @dm-define HEAT_EDGE_ENGINE
#[allow(dead_code)]
pub const HEAT_EDGE_ENGINE: i32 = 3;

/// Pump modes (`RegulatorMode`).
/// @dm-define HEAT_PUMP_HEAT
#[allow(dead_code)]
pub const HEAT_PUMP_HEAT: i32 = 0;
/// @dm-define HEAT_PUMP_COOL
#[allow(dead_code)]
pub const HEAT_PUMP_COOL: i32 = 1;
/// @dm-define HEAT_PUMP_BOTH
#[allow(dead_code)]
pub const HEAT_PUMP_BOTH: i32 = 2;

/// Declared external sources/sinks for [`heat_move`] (the ledger's
/// categories). A one-off move between two reservoirs is internal and books
/// no source.
/// @dm-define HEAT_SOURCE_NONE
#[allow(dead_code)]
pub const HEAT_SOURCE_NONE: i32 = 0;
/// A chemical or gas reaction's enthalpy outside the gas domain.
/// @dm-define HEAT_SOURCE_REACTION
#[allow(dead_code)]
pub const HEAT_SOURCE_REACTION: i32 = 1;
/// A machine's electrical heating (its power draw is the source).
/// @dm-define HEAT_SOURCE_DEVICE
#[allow(dead_code)]
pub const HEAT_SOURCE_DEVICE: i32 = 2;
/// Fire and burning.
/// @dm-define HEAT_SOURCE_FIRE
#[allow(dead_code)]
pub const HEAT_SOURCE_FIRE: i32 = 3;
/// Magic: spells, technomancer functions.
/// @dm-define HEAT_SOURCE_SPELL
#[allow(dead_code)]
pub const HEAT_SOURCE_SPELL: i32 = 4;
/// Metabolism: a living body's own heat.
/// @dm-define HEAT_SOURCE_METABOLISM
#[allow(dead_code)]
pub const HEAT_SOURCE_METABOLISM: i32 = 5;
/// Authority writes: map load, admin, holodeck, spawn-time temperatures.
/// @dm-define HEAT_SOURCE_AUTHORITY
#[allow(dead_code)]
pub const HEAT_SOURCE_AUTHORITY: i32 = 6;
/// Weapons, explosions, projectiles.
/// @dm-define HEAT_SOURCE_WEAPON
#[allow(dead_code)]
pub const HEAT_SOURCE_WEAPON: i32 = 7;
/// Anything else (named in the caller's comment).
/// @dm-define HEAT_SOURCE_OTHER
#[allow(dead_code)]
pub const HEAT_SOURCE_OTHER: i32 = 8;
/// A material's own heat model (material science's DM solid state) giving
/// heat to or taking it from a gas.
/// @dm-define HEAT_SOURCE_MATERIAL
#[allow(dead_code)]
pub const HEAT_SOURCE_MATERIAL: i32 = 9;
const SOURCES: usize = 10;

/// A reservoir.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Res {
    Mix(u32),
    Port(u32),
    Body(vg_core::entity::EntityId),
    Solid(u32),
    /// Space at a temperature (bits of the `f32` K).
    Space(u32),
}

impl Res {
    fn kind(self) -> i32 {
        match self {
            Self::Mix(_) => HEAT_TARGET_MIXTURE,
            Self::Port(_) => HEAT_TARGET_PIPE_PORT,
            Self::Body(_) => HEAT_TARGET_BODY,
            Self::Solid(_) => HEAT_TARGET_SOLID,
            Self::Space(_) => HEAT_TARGET_SPACE,
        }
    }

    #[allow(clippy::cast_precision_loss)]
    fn number(self) -> f32 {
        match self {
            Self::Mix(i) | Self::Port(i) | Self::Solid(i) => i as f32,
            Self::Body(e) => crate::entity::entity_value(e),
            Self::Space(bits) => f32::from_bits(bits),
        }
    }

    /// Resolves DM's `(HEAT_TARGET_*, ref)`.
    fn from_dm(kind: &ByondValue, r: &ByondValue) -> Result<Self> {
        #[allow(clippy::cast_possible_truncation)]
        let kind = num(kind)? as i32;
        Ok(match kind {
            HEAT_TARGET_MIXTURE => {
                if r.is_num() {
                    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
                    let id = num(r)? as u32;
                    Self::Mix(id)
                } else {
                    Self::Mix(MixRef::of(r)?.id())
                }
            }
            HEAT_TARGET_TURF_AIR => Self::Mix(MixRef::Turf(r.get_ref()?).id()),
            HEAT_TARGET_PIPE_PORT => Self::Port(crate::entity::decode(num(r)?)?.bits()),
            HEAT_TARGET_BODY => Self::Body(crate::entity::decode(num(r)?)?),
            HEAT_TARGET_SOLID => Self::Solid(r.get_ref()?),
            HEAT_TARGET_SPACE => {
                let t = if r.is_num() { num(r)? } else { vg_heat::consts::TCMB };
                Self::Space(t.max(0.0).to_bits())
            }
            _ => bail!("not a heat reservoir kind: {kind}"),
        })
    }
}

struct Slot {
    edge: Edge<Res>,
    /// The last step's flows, J, and the step length, s.
    last: Flow,
    last_dt: f64,
    /// Work in less work out since DM last took it (`heat_edge_take_work`), J.
    work_owed: f64,
}

#[derive(Default)]
struct Net {
    slots: Vec<Option<Slot>>,
    free: Vec<usize>,
    /// When the network last stepped (world time, s).
    last_now: Option<f64>,
    /// The last step's books, and cumulative books since boot.
    last: Books,
    total: Books,
    /// Cumulative declared external joules by `HEAT_SOURCE_*` (in, out).
    by_source: [(f64, f64); SOURCES],
    /// Steps whose books did not balance (release builds count instead of
    /// asserting).
    violations: u64,
}

thread_local! {
    static NET: RefCell<Net> = RefCell::new(Net::default());
}

// --- Storage adapter -----------------------------------------------------------

/// A snapshot of every reservoir one operation touches, with the net change
/// each one takes; written back once by [`Cache::flush`].
#[derive(Default)]
struct Cache {
    entries: HashMap<Res, (State, f64)>,
}

/// A side too small to hold heat (a vacuum mixture): no edge moves anything
/// through it (an exact pair solution would otherwise read a zero capacity as
/// an infinite reservoir).
const MIN_CAPACITY: f64 = 0.0003;

impl Cache {
    /// Reads `r` into the snapshot (once).
    fn load(&mut self, r: Res) {
        if self.entries.contains_key(&r) {
            return;
        }
        if let Some(s) = read_state(r) {
            self.entries.insert(r, (s, 0.0));
        }
    }

    /// Writes every net change back to its storage.
    fn flush(self) {
        for (r, (_, delta)) in self.entries {
            if delta != 0.0 {
                write_energy(r, delta);
            }
        }
    }

    /// The finite reservoirs' energy now (the books' conserved total).
    fn total(&self) -> f64 {
        self.entries
            .values()
            .filter(|(s, _)| !s.is_infinite())
            .map(|(s, d)| s.capacity * s.temperature + d)
            .sum()
    }
}

impl Reservoirs<Res> for Cache {
    fn state(&self, r: Res) -> Option<State> {
        let &(s, delta) = self.entries.get(&r)?;
        if s.is_infinite() {
            return Some(s);
        }
        if s.capacity < MIN_CAPACITY {
            return None;
        }
        Some(State { temperature: s.temperature + delta / s.capacity, ..s })
    }

    fn add(&mut self, r: Res, joules: f64) {
        if let Some((_, d)) = self.entries.get_mut(&r) {
            *d += joules;
        }
    }
}

fn tcmb() -> f64 {
    f64::from(vg_heat::consts::TCMB)
}

/// A port's current region, as a mixture handle.
fn port_mix(bits: u32) -> Option<MixRef> {
    with_world(|w| Ok(crate::heat::probe_mixture(w, gas_kind::PORT_KEY | bits))).ok().flatten()
}

fn mix_state(r: MixRef) -> Option<State> {
    let m = mix::load(r)?;
    let c = f64::from(m.heat_capacity());
    Some(State {
        temperature: f64::from(m.get_temperature()),
        capacity: if m.is_immutable() { f64::INFINITY } else { c },
        floor: tcmb(),
    })
}

fn read_state(r: Res) -> Option<State> {
    match r {
        Res::Mix(id) => mix_state(MixRef::from_id(id)?),
        Res::Port(bits) => mix_state(port_mix(bits)?),
        Res::Body(e) => with_world(|w| {
            let Some(mut b) = w.read::<HeatBody>(e) else { return Ok(None) };
            if b.relax {
                crate::heat::settle_body_if_relaxing(w, e, &mut b)?;
                let _ = w.put(e, b.clone());
            }
            Ok(Some(State { temperature: b.temperature(), capacity: b.capacity, floor: tcmb() }))
        })
        .ok()
        .flatten(),
        Res::Solid(cell) => with_world(|w| {
            let field = crate::heat::field()?;
            let (Some(g), Some(c)) = (w.sim_mut().port(field.geometry).read(cell), w.sim_mut().port(field.cells).read(cell)) else {
                return Ok(None);
            };
            if !g.is_node() {
                return Ok(None);
            }
            let t = f64::from(c.temperature_in(g.capacity));
            Ok(Some(State { temperature: t, capacity: if g.reservoir { f64::INFINITY } else { f64::from(g.capacity) }, floor: 0.0 }))
        })
        .ok()
        .flatten(),
        Res::Space(bits) => Some(State { temperature: f64::from(f32::from_bits(bits)), capacity: f64::INFINITY, floor: 0.0 }),
    }
}

/// Adds `joules` to a reservoir's storage (already capped by the transfer).
#[allow(clippy::cast_possible_truncation)]
fn write_energy(r: Res, joules: f64) {
    let gas = |m: MixRef| {
        let mut d = [0.0f32; vg_gas::cell::Q];
        d[vg_gas::cell::N] = joules as f32;
        mix::add_amounts(m, &d, 0.0);
    };
    match r {
        Res::Mix(id) => {
            if let Some(m) = MixRef::from_id(id) {
                gas(m);
            }
        }
        Res::Port(bits) => {
            if let Some(m) = port_mix(bits) {
                gas(m);
            }
        }
        Res::Body(e) => {
            let _ = with_world(|w| {
                if let Some(mut b) = w.read::<HeatBody>(e) {
                    vg_heat::laws::add_body_energy(&mut b, joules);
                    let _ = w.put(e, b);
                    crate::heat::wake_body_couplings(w, e.index());
                }
                Ok(())
            });
        }
        Res::Solid(cell) => {
            let _ = with_world(|w| {
                let field = crate::heat::field()?;
                let _ = w.sim_mut().port(field.cells).submit(cell, vg_heat::SolidCmd::Add(joules as f32));
                crate::heat::wake_cell_couplings(w, cell);
                Ok(())
            });
        }
        Res::Space(_) => {}
    }
}

// --- The step -------------------------------------------------------------------

/// Steps every edge over the world time since the last step. Called by the
/// frame after the world paced (outside the world borrow: gas loads take it).
pub(crate) fn step(now: f64, first_dt: f64) {
    let dt = NET.with_borrow_mut(|n| {
        let dt = n.last_now.map_or(first_dt, |t| (now - t).max(0.0));
        n.last_now = Some(now);
        dt
    });
    step_dt(dt);
}

/// Advances the heat network alone by `seconds` (the unit-test kernel clock, which does not pace the native world). Returns nothing.
#[auxmacros::bind("/proc/heat_net_advance")]
fn heat_net_advance(seconds: ByondValue) -> Result<ByondValue> {
    step_dt(f(&seconds)?.max(0.0));
    Ok(ByondValue::null())
}

/// Steps every edge over `dt` seconds.
fn step_dt(dt: f64) {
    let edges: Vec<(usize, Edge<Res>)> = NET.with_borrow(|n| {
        n.slots.iter().enumerate().filter_map(|(i, s)| s.as_ref().map(|s| (i, s.edge))).collect()
    });
    if edges.is_empty() || dt <= 0.0 {
        return;
    }
    let mut cache = Cache::default();
    for (_, e) in &edges {
        cache.load(e.a);
        cache.load(e.b);
    }
    let before = cache.total();
    let mut books = Books::default();
    let flows: Vec<(usize, Flow)> = edges.iter().map(|(i, e)| (*i, transfer::step_edge(&mut cache, &mut books, e, dt))).collect();
    let after = cache.total();
    let balanced = books.check(before, after);
    debug_assert!(balanced.is_ok(), "heat network books do not balance by {balanced:?} J ({before} -> {after})");
    cache.flush();
    NET.with_borrow_mut(|n| {
        for (i, f) in flows {
            if let Some(Some(s)) = n.slots.get_mut(i) {
                s.last = f;
                s.last_dt = dt;
                s.work_owed += f.work_in - f.work_out;
            }
        }
        n.last = books;
        n.total.absorb(&books);
        if balanced.is_err() {
            n.violations += 1;
        }
    });
}

/// Drops every edge (`verdigris_cleanup`, a fresh round).
pub(crate) fn reset() {
    NET.with_borrow_mut(|n| *n = Net::default());
}

// --- Binds ----------------------------------------------------------------------

fn insert(edge: Edge<Res>) -> f32 {
    NET.with_borrow_mut(|n| {
        let slot = Slot { edge, last: Flow::default(), last_dt: 0.0, work_owed: 0.0 };
        let i = if let Some(i) = n.free.pop() {
            n.slots[i] = Some(slot);
            i
        } else {
            n.slots.push(Some(slot));
            n.slots.len() - 1
        };
        #[allow(clippy::cast_precision_loss)]
        let id = (i + 1) as f32;
        id
    })
}

fn slot_index(id: &ByondValue) -> Result<usize> {
    let v = num(id)?;
    if !(v >= 1.0 && v.fract() == 0.0) {
        bail!("bad heat edge id {v}");
    }
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    Ok(v as usize - 1)
}

fn f(v: &ByondValue) -> Result<f64> {
    Ok(f64::from(num(v)?))
}

/// A conduction (and radiation) link between two reservoirs: `conductance`
/// W/K, plus `εσA(T_a⁴ − T_b⁴)` when `emissivity` and `area` (m²) are
/// positive. Integrated exactly each world step. Returns the edge id.
#[auxmacros::bind("/proc/heat_link_create")]
fn heat_link_create(
    a_kind: ByondValue,
    a_ref: ByondValue,
    b_kind: ByondValue,
    b_ref: ByondValue,
    conductance: ByondValue,
    emissivity: ByondValue,
    area: ByondValue,
) -> Result<ByondValue> {
    let edge = Edge {
        a: Res::from_dm(&a_kind, &a_ref)?,
        b: Res::from_dm(&b_kind, &b_ref)?,
        kind: EdgeKind::Link { conductance: f(&conductance)?.max(0.0), emissivity: f(&emissivity)?.clamp(0.0, 1.0), area: f(&area)?.max(0.0) },
    };
    Ok(insert(edge).into())
}

fn mode_of(v: &ByondValue) -> Result<RegulatorMode> {
    #[allow(clippy::cast_possible_truncation)]
    Ok(match num(v)? as i32 {
        HEAT_PUMP_HEAT => RegulatorMode::Heat,
        HEAT_PUMP_COOL => RegulatorMode::Cool,
        _ => RegulatorMode::Both,
    })
}

/// A heat pump driving `controlled` toward `target` K with at most `watts`
/// of electrical work, rejecting heat to (or drawing it from) `other`
/// (`HEAT_PUMP_*` mode; `resistive`: heating is resistive, COP 1). Its COP is
/// Carnot-bounded (`carnot_fraction`, `max_cop`). Returns the edge id.
#[auxmacros::bind("/proc/heat_pump_create")]
fn heat_pump_create(
    controlled_kind: ByondValue,
    controlled_ref: ByondValue,
    other_kind: ByondValue,
    other_ref: ByondValue,
    watts: ByondValue,
    target: ByondValue,
    mode: ByondValue,
    resistive: ByondValue,
    carnot_fraction: ByondValue,
    max_cop: ByondValue,
) -> Result<ByondValue> {
    #[allow(clippy::cast_possible_truncation)]
    let reg = Regulator {
        target: num(&target)?.max(0.0),
        max_power: num(&watts)?.max(0.0),
        mode: mode_of(&mode)?,
        resistive_heating: num(&resistive)? != 0.0,
        carnot_fraction: if carnot_fraction.is_num() { num(&carnot_fraction)?.clamp(0.0, 1.0) } else { 0.5 },
        max_cop: if max_cop.is_num() { num(&max_cop)?.max(1.0) } else { 10.0 },
        ..Regulator::default()
    };
    let edge = Edge { a: Res::from_dm(&controlled_kind, &controlled_ref)?, b: Res::from_dm(&other_kind, &other_ref)?, kind: EdgeKind::Pump(reg) };
    Ok(insert(edge).into())
}

/// A heat engine between two reservoirs: heat flows from the hotter to the
/// colder through `conductance` W/K and `efficiency` of it (capped at Carnot)
/// leaves as electrical work, read back with `heat_edge_power`. Returns the
/// edge id.
#[auxmacros::bind("/proc/heat_engine_create")]
fn heat_engine_create(
    hot_kind: ByondValue,
    hot_ref: ByondValue,
    cold_kind: ByondValue,
    cold_ref: ByondValue,
    efficiency: ByondValue,
    conductance: ByondValue,
) -> Result<ByondValue> {
    let edge = Edge {
        a: Res::from_dm(&hot_kind, &hot_ref)?,
        b: Res::from_dm(&cold_kind, &cold_ref)?,
        kind: EdgeKind::Engine { efficiency: f(&efficiency)?.clamp(0.0, 1.0), conductance: f(&conductance)?.max(0.0) },
    };
    Ok(insert(edge).into())
}

/// Removes an edge. Unknown ids are ignored.
#[auxmacros::bind("/proc/heat_edge_remove")]
fn heat_edge_remove(id: ByondValue) -> Result<ByondValue> {
    let i = slot_index(&id)?;
    NET.with_borrow_mut(|n| {
        if n.slots.get(i).is_some_and(Option::is_some) {
            n.slots[i] = None;
            n.free.push(i);
        }
    });
    Ok(ByondValue::null())
}

/// Edge parameters by index for [`heat_edge_set`].
/// @dm-define HEAT_PARAM_CONDUCTANCE
#[allow(dead_code)]
pub const HEAT_PARAM_CONDUCTANCE: i32 = 1;
/// @dm-define HEAT_PARAM_EMISSIVITY
#[allow(dead_code)]
pub const HEAT_PARAM_EMISSIVITY: i32 = 2;
/// @dm-define HEAT_PARAM_WATTS
#[allow(dead_code)]
pub const HEAT_PARAM_WATTS: i32 = 3;
/// @dm-define HEAT_PARAM_TARGET
#[allow(dead_code)]
pub const HEAT_PARAM_TARGET: i32 = 4;
/// @dm-define HEAT_PARAM_MODE
#[allow(dead_code)]
pub const HEAT_PARAM_MODE: i32 = 5;
/// @dm-define HEAT_PARAM_EFFICIENCY
#[allow(dead_code)]
pub const HEAT_PARAM_EFFICIENCY: i32 = 6;
/// @dm-define HEAT_PARAM_AREA
#[allow(dead_code)]
pub const HEAT_PARAM_AREA: i32 = 7;

/// Changes one parameter of a live edge (a thermostat turned, a part
/// upgraded) without recreating it. Returns whether it applied.
#[auxmacros::bind("/proc/heat_edge_set")]
fn heat_edge_set(id: ByondValue, param: ByondValue, value: ByondValue) -> Result<ByondValue> {
    let i = slot_index(&id)?;
    #[allow(clippy::cast_possible_truncation)]
    let param = num(&param)? as i32;
    let v = f(&value)?;
    #[allow(clippy::cast_possible_truncation)]
    let ok = NET.with_borrow_mut(|n| {
        let Some(Some(s)) = n.slots.get_mut(i) else { return false };
        match (&mut s.edge.kind, param) {
            (EdgeKind::Link { conductance, .. } | EdgeKind::Engine { conductance, .. }, HEAT_PARAM_CONDUCTANCE) => *conductance = v.max(0.0),
            (EdgeKind::Link { emissivity, .. }, HEAT_PARAM_EMISSIVITY) => *emissivity = v.clamp(0.0, 1.0),
            (EdgeKind::Link { area, .. }, HEAT_PARAM_AREA) => *area = v.max(0.0),
            (EdgeKind::Engine { efficiency, .. }, HEAT_PARAM_EFFICIENCY) => *efficiency = v.clamp(0.0, 1.0),
            (EdgeKind::Pump(r), HEAT_PARAM_WATTS) => r.max_power = (v as f32).max(0.0),
            (EdgeKind::Pump(r), HEAT_PARAM_TARGET) => r.target = (v as f32).max(0.0),
            (EdgeKind::Pump(r), HEAT_PARAM_MODE) => {
                r.mode = match v as i32 {
                    HEAT_PUMP_HEAT => RegulatorMode::Heat,
                    HEAT_PUMP_COOL => RegulatorMode::Cool,
                    _ => RegulatorMode::Both,
                }
            }
            _ => return false,
        }
        true
    });
    Ok(ok.into())
}

/// The electrical power an edge exchanged in its last step, W: positive for
/// an engine's output, negative for a pump's draw.
#[auxmacros::bind("/proc/heat_edge_power")]
fn heat_edge_power(id: ByondValue) -> Result<ByondValue> {
    let i = slot_index(&id)?;
    let w = NET.with_borrow(|n| match n.slots.get(i) {
        Some(Some(s)) if s.last_dt > 0.0 => (s.last.work_out - s.last.work_in) / s.last_dt,
        _ => 0.0,
    });
    #[allow(clippy::cast_possible_truncation)]
    Ok((w as f32).into())
}

/// The electrical work an edge exchanged since this was last called, J
/// (positive: a pump drew it; negative: an engine made it), and resets it:
/// what a machine pays from its cell or grid, exactly what Rust booked.
#[auxmacros::bind("/proc/heat_edge_take_work")]
fn heat_edge_take_work(id: ByondValue) -> Result<ByondValue> {
    let i = slot_index(&id)?;
    let w = NET.with_borrow_mut(|n| match n.slots.get_mut(i) {
        Some(Some(s)) => std::mem::take(&mut s.work_owed),
        _ => 0.0,
    });
    #[allow(clippy::cast_possible_truncation)]
    Ok((w as f32).into())
}

/// One edge, for tooling: `list(HEAT_EDGE_*, a kind, a ref, b kind, b ref,
/// p1, p2, p3, heat out of a W, heat into b W, work in W, work out W)`. The
/// parameters are (conductance, emissivity, area) for a link, (watts,
/// target, mode) for a pump, (efficiency, conductance, 0) for an engine.
#[auxmacros::bind("/proc/heat_edge_info")]
fn heat_edge_info(id: ByondValue) -> Result<ByondValue> {
    let i = slot_index(&id)?;
    let row = NET.with_borrow(|n| n.slots.get(i).and_then(Option::as_ref).map(edge_row));
    match row {
        Some(r) => list(r),
        None => Ok(ByondValue::null()),
    }
}

#[allow(clippy::cast_possible_truncation, clippy::cast_precision_loss)]
fn edge_row(s: &Slot) -> Vec<f32> {
    let (kind, p) = match s.edge.kind {
        EdgeKind::Link { conductance, emissivity, area } => (HEAT_EDGE_LINK, [conductance as f32, emissivity as f32, area as f32]),
        EdgeKind::Pump(r) => (HEAT_EDGE_PUMP, [r.max_power, r.target, match r.mode {
            RegulatorMode::Heat => 0.0,
            RegulatorMode::Cool => 1.0,
            RegulatorMode::Both => 2.0,
        }]),
        EdgeKind::Engine { efficiency, conductance } => (HEAT_EDGE_ENGINE, [efficiency as f32, conductance as f32, 0.0]),
    };
    let per = |j: f64| if s.last_dt > 0.0 { (j / s.last_dt) as f32 } else { 0.0 };
    vec![
        kind as f32,
        s.edge.a.kind() as f32,
        s.edge.a.number(),
        s.edge.b.kind() as f32,
        s.edge.b.number(),
        p[0],
        p[1],
        p[2],
        per(s.last.from_a),
        per(s.last.into_b),
        per(s.last.work_in),
        per(s.last.work_out),
    ]
}

/// Every edge touching a reservoir, for tooling: a flat list of edge ids.
#[auxmacros::bind("/proc/heat_reservoir_links")]
fn heat_reservoir_links(kind: ByondValue, r: ByondValue) -> Result<ByondValue> {
    let res = Res::from_dm(&kind, &r)?;
    #[allow(clippy::cast_precision_loss)]
    let ids: Vec<f32> = NET.with_borrow(|n| {
        n.slots
            .iter()
            .enumerate()
            .filter_map(|(i, s)| s.as_ref().filter(|s| s.edge.a == res || s.edge.b == res).map(|_| (i + 1) as f32))
            .collect()
    });
    list(ids)
}

/// The heat network's books: `list(edges, last step: transferred, work in,
/// work out, external in, external out (J); since boot: the same five;
/// unbalanced steps)` then, per `HEAT_SOURCE_*` from 0, `in, out` J since
/// boot.
#[auxmacros::bind("/proc/heat_books")]
fn heat_books() -> Result<ByondValue> {
    #[allow(clippy::cast_possible_truncation, clippy::cast_precision_loss)]
    let row = NET.with_borrow(|n| {
        let b = |b: &Books| [b.transferred as f32, b.work_in as f32, b.work_out as f32, b.external_in as f32, b.external_out as f32];
        let mut v = vec![n.slots.iter().filter(|s| s.is_some()).count() as f32];
        v.extend(b(&n.last));
        v.extend(b(&n.total));
        v.push(n.violations as f32);
        for (i, o) in n.by_source {
            v.push(i as f32);
            v.push(o as f32);
        }
        v
    });
    list(row)
}

fn source_index(v: &ByondValue) -> Result<usize> {
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    let s = if v.is_num() { num(v)? as usize } else { 0 };
    Ok(s.min(SOURCES - 1))
}

fn book_source(source: usize, applied: f64) {
    NET.with_borrow_mut(|n| {
        if applied >= 0.0 {
            n.by_source[source].0 += applied;
        } else {
            n.by_source[source].1 -= applied;
        }
    });
}

/// Runs a one-off operation on a fresh snapshot and writes it back.
fn one_off(rs: &[Res], f: impl FnOnce(&mut Cache, &mut Books) -> f64) -> f64 {
    let mut cache = Cache::default();
    for &r in rs {
        cache.load(r);
    }
    let before = cache.total();
    let mut books = Books::default();
    let applied = f(&mut cache, &mut books);
    debug_assert!(books.check(before, cache.total()).is_ok());
    cache.flush();
    NET.with_borrow_mut(|n| n.total.absorb(&books));
    applied
}

/// Moves `joules` from one reservoir to another in one operation (capped so
/// neither passes absolute zero; negative moves the other way). With
/// `from_kind` `HEAT_TARGET_NONE` the joules come from outside the
/// simulation (an external source, `source` a `HEAT_SOURCE_*`); with
/// `to_kind` `HEAT_TARGET_NONE` they leave it (an external sink). Either way
/// it is booked. Returns the joules actually moved.
#[auxmacros::bind("/proc/heat_move")]
fn heat_move(
    from_kind: ByondValue,
    from_ref: ByondValue,
    to_kind: ByondValue,
    to_ref: ByondValue,
    joules: ByondValue,
    source: ByondValue,
) -> Result<ByondValue> {
    let q = f(&joules)?;
    let none = |k: &ByondValue| -> Result<bool> { Ok(k.is_null() || (k.is_num() && num(k)? as i32 == HEAT_TARGET_NONE)) };
    let source = source_index(&source)?;
    let applied = match (none(&from_kind)?, none(&to_kind)?) {
        (true, true) => 0.0,
        (true, false) => {
            let to = Res::from_dm(&to_kind, &to_ref)?;
            let a = one_off(&[to], |c, b| transfer::external(c, b, to, q));
            book_source(source, a);
            a
        }
        (false, true) => {
            let from = Res::from_dm(&from_kind, &from_ref)?;
            let a = -one_off(&[from], |c, b| transfer::external(c, b, from, -q));
            book_source(source, -a);
            a
        }
        (false, false) => {
            let (from, to) = (Res::from_dm(&from_kind, &from_ref)?, Res::from_dm(&to_kind, &to_ref)?);
            one_off(&[from, to], |c, b| transfer::transfer(c, b, from, to, q))
        }
    };
    #[allow(clippy::cast_possible_truncation)]
    Ok((applied as f32).into())
}

/// Moves `fraction` (0..1) of the way to the common temperature of two
/// reservoirs in one conserved operation (1: both end at the mixed
/// temperature, as if they were one body). Returns the joules moved from
/// the first to the second.
#[auxmacros::bind("/proc/heat_equalize")]
fn heat_equalize(a_kind: ByondValue, a_ref: ByondValue, b_kind: ByondValue, b_ref: ByondValue, fraction: ByondValue) -> Result<ByondValue> {
    let (a, b) = (Res::from_dm(&a_kind, &a_ref)?, Res::from_dm(&b_kind, &b_ref)?);
    let fraction = f(&fraction)?.clamp(0.0, 1.0);
    let moved = one_off(&[a, b], |c, books| {
        let (Some(sa), Some(sb)) = (c.state(a), c.state(b)) else { return 0.0 };
        let inv = |s: State| if s.is_infinite() { 0.0 } else { 1.0 / s.capacity };
        let k = inv(sa) + inv(sb);
        if k <= 0.0 {
            return 0.0;
        }
        transfer::transfer(c, books, a, b, fraction * (sa.temperature - sb.temperature) / k)
    });
    #[allow(clippy::cast_possible_truncation)]
    Ok((moved as f32).into())
}

/// Conducts between two reservoirs for `seconds` at `conductance` W/K in one
/// conserved operation: the exact pair solution (never past equilibrium),
/// as a one-off for a sample that covers a stretch of time. Returns the
/// joules moved from the first to the second.
#[auxmacros::bind("/proc/heat_conduct")]
fn heat_conduct(
    a_kind: ByondValue,
    a_ref: ByondValue,
    b_kind: ByondValue,
    b_ref: ByondValue,
    conductance: ByondValue,
    seconds: ByondValue,
) -> Result<ByondValue> {
    let (a, b) = (Res::from_dm(&a_kind, &a_ref)?, Res::from_dm(&b_kind, &b_ref)?);
    let (g, dt) = (f(&conductance)?.max(0.0), f(&seconds)?.max(0.0));
    if g <= 0.0 || dt <= 0.0 {
        return Ok(0.0f32.into());
    }
    let moved = one_off(&[a, b], |c, books| {
        let (Some(sa), Some(sb)) = (c.state(a), c.state(b)) else { return 0.0 };
        transfer::transfer(c, books, a, b, transfer::link_heat(sa, sb, g, dt))
    });
    #[allow(clippy::cast_possible_truncation)]
    Ok((moved as f32).into())
}

/// Brings a reservoir to `temperature` K by an external, booked source
/// (`HEAT_SOURCE_*`): an authority write (map load, admin, a spawn-time
/// temperature) expressed as the joules it takes. Returns the joules added.
#[auxmacros::bind("/proc/heat_move_to_temperature")]
fn heat_move_to_temperature(kind: ByondValue, r: ByondValue, temperature: ByondValue, source: ByondValue) -> Result<ByondValue> {
    let res = Res::from_dm(&kind, &r)?;
    let t = f(&temperature)?;
    let source = source_index(&source)?;
    // A gas is set the way the gas domain sets a temperature (one read-modify-write of the mixture, through the same path every gas write
    // takes, so pending turf commands compose), and the joules it took are booked. An empty mixture keeps the temperature for gas added later.
    if let Some(m) = gas_mixture(res) {
        let Some(before) = mix::load(m) else { return Ok(0.0f32.into()) };
        if before.is_immutable() {
            return Ok(0.0f32.into());
        }
        let mut after = before.clone();
        #[allow(clippy::cast_possible_truncation)]
        after.set_temperature((t as f32).max(vg_heat::consts::TCMB));
        let added = f64::from(after.heat_capacity()) * (f64::from(after.get_temperature()) - f64::from(before.get_temperature()));
        mix::store(m, &before, &after);
        NET.with_borrow_mut(|n| {
            if added >= 0.0 { n.total.external_in += added } else { n.total.external_out -= added }
        });
        book_source(source, added);
        #[allow(clippy::cast_possible_truncation)]
        return Ok((added as f32).into());
    }
    let applied = one_off(&[res], |c, b| {
        let Some(s) = c.state(res) else { return 0.0 };
        if s.is_infinite() {
            return 0.0;
        }
        transfer::external(c, b, res, (t.max(s.floor) - s.temperature) * s.capacity)
    });
    book_source(source, applied);
    #[allow(clippy::cast_possible_truncation)]
    Ok((applied as f32).into())
}

/// Sets a reservoir's thermal energy to `joules` (its floor at least) by an
/// external, booked source: a reaction that changed a gas's composition and
/// released or consumed `joules - before` (`HEAT_SOURCE_REACTION`). Returns
/// the joules added.
#[auxmacros::bind("/proc/heat_set_energy")]
fn heat_set_energy(kind: ByondValue, r: ByondValue, joules: ByondValue, source: ByondValue) -> Result<ByondValue> {
    let res = Res::from_dm(&kind, &r)?;
    let target = f(&joules)?;
    let source = source_index(&source)?;
    let applied = one_off(&[res], |c, b| {
        let Some(s) = c.state(res) else { return 0.0 };
        if s.is_infinite() {
            return 0.0;
        }
        transfer::external(c, b, res, target - s.capacity * s.temperature)
    });
    book_source(source, applied);
    #[allow(clippy::cast_possible_truncation)]
    Ok((applied as f32).into())
}

/// The mixture behind a gas reservoir.
fn gas_mixture(r: Res) -> Option<MixRef> {
    match r {
        Res::Mix(id) => MixRef::from_id(id),
        Res::Port(bits) => port_mix(bits),
        _ => None,
    }
}

/// One heat-engine pass between two reservoirs (a thermoelectric generator
/// on the gas its circulators moved this step): the energy that would bring
/// them to a common temperature flows from the hotter to the colder, and
/// `efficiency` of it (capped at Carnot, `1 - T_cold/T_hot`) leaves as
/// electrical work, booked out. Returns the work, J.
#[auxmacros::bind("/proc/heat_engine_once")]
fn heat_engine_once(a_kind: ByondValue, a_ref: ByondValue, b_kind: ByondValue, b_ref: ByondValue, efficiency: ByondValue) -> Result<ByondValue> {
    let (a, b) = (Res::from_dm(&a_kind, &a_ref)?, Res::from_dm(&b_kind, &b_ref)?);
    let efficiency = f(&efficiency)?;
    let mut work = 0.0;
    one_off(&[a, b], |c, books| {
        let edge = Edge { a, b, kind: EdgeKind::Engine { efficiency, conductance: f64::INFINITY } };
        work = transfer::step_edge(c, books, &edge, 1.0).work_out;
        0.0
    });
    #[allow(clippy::cast_possible_truncation)]
    Ok((work as f32).into())
}

/// Reads a reservoir: `list(temperature K, heat capacity J/K (-1: infinite))`,
/// or null if it does not exist.
#[auxmacros::bind("/proc/heat_reservoir_state")]
fn heat_reservoir_state(kind: ByondValue, r: ByondValue) -> Result<ByondValue> {
    let res = Res::from_dm(&kind, &r)?;
    match read_state(res) {
        #[allow(clippy::cast_possible_truncation)]
        Some(s) => list([s.temperature as f32, if s.is_infinite() { -1.0 } else { s.capacity as f32 }]),
        None => Ok(ByondValue::null()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn main_mix(t: f32, moles: f32) -> MixRef {
        with_world(|_| Ok(())).unwrap();
        let mut m = vg_gas::gas::Mixture::from_vol(70.0);
        m.set_moles(0, moles);
        m.set_temperature(t);
        MixRef::Main(mix::alloc(m).unwrap())
    }

    #[test]
    fn a_link_between_two_mixtures_conserves_and_relaxes() {
        reset();
        let (a, b) = (main_mix(400.0, 10.0), main_mix(300.0, 10.0));
        let e = Edge { a: Res::Mix(a.id()), b: Res::Mix(b.id()), kind: EdgeKind::Link { conductance: 50.0, emissivity: 0.0, area: 0.0 } };
        insert(e);
        let energy = |r| {
            let s = read_state(Res::Mix(MixRef::id(r))).unwrap();
            s.capacity * s.temperature
        };
        let before = energy(a) + energy(b);
        for k in 1..=200 {
            step(f64::from(k) * 0.5, 0.5);
        }
        let (ta, tb) = (read_state(Res::Mix(a.id())).unwrap().temperature, read_state(Res::Mix(b.id())).unwrap().temperature);
        assert!((ta - tb).abs() < 0.5, "{ta} vs {tb}");
        assert!(((energy(a) + energy(b)) - before).abs() / before < 1e-5);
        assert_eq!(NET.with_borrow(|n| n.violations), 0);
    }

    #[test]
    fn a_one_off_conduction_is_the_exact_pair_solution_and_conserves() {
        reset();
        let (a, b) = (main_mix(500.0, 10.0), main_mix(300.0, 10.0));
        let (ra, rb) = (Res::Mix(a.id()), Res::Mix(b.id()));
        let (sa, sb) = (read_state(ra).unwrap(), read_state(rb).unwrap());
        let before = sa.capacity * sa.temperature + sb.capacity * sb.temperature;
        let expected = transfer::link_heat(sa, sb, 20.0, 5.0);
        let moved = one_off(&[ra, rb], |c, books| {
            let (Some(sa), Some(sb)) = (c.state(ra), c.state(rb)) else { return 0.0 };
            transfer::transfer(c, books, ra, rb, transfer::link_heat(sa, sb, 20.0, 5.0))
        });
        assert!((moved - expected).abs() < 1e-6 * expected.abs().max(1.0));
        let (ta, tb) = (read_state(ra).unwrap(), read_state(rb).unwrap());
        assert!(ta.temperature < 500.0 && tb.temperature > 300.0 && ta.temperature > tb.temperature);
        let after = ta.capacity * ta.temperature + tb.capacity * tb.temperature;
        assert!((after - before).abs() / before < 1e-5);
    }

    #[test]
    fn heat_move_from_an_external_source_is_booked() {
        reset();
        let a = main_mix(300.0, 10.0);
        let s0 = read_state(Res::Mix(a.id())).unwrap();
        let applied = one_off(&[Res::Mix(a.id())], |c, b| transfer::external(c, b, Res::Mix(a.id()), 1000.0));
        book_source(HEAT_SOURCE_REACTION as usize, applied);
        let s1 = read_state(Res::Mix(a.id())).unwrap();
        assert!((s1.capacity * s1.temperature - s0.capacity * s0.temperature - 1000.0).abs() < 1.0);
        assert!((NET.with_borrow(|n| n.by_source[HEAT_SOURCE_REACTION as usize].0) - 1000.0).abs() < 1e-6);
    }
}
