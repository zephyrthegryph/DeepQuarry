//! Every `/datum/gas_mixture`, whoever owns its gas (`rust_architecture.md`
//! §8.5 step 6): a datum holds one number, its handle ([`MixRef`]), in
//! `_extools_pointer_gasmixture`.
//!
//! - **Main-owned mixtures** (tanks, lungs, canisters, device buffers,
//!   scratch mixtures): this module's slab, read and written synchronously.
//! - **Turf gas**: a cell of the `TurfGas` field on the shared World.
//! - **Pipe gas**: a region payload of the pipe network on the shared World.
//!
//! Every DM gas proc goes through [`with_mix`]/[`with_mix_mut`], which
//! dispatch on the owner, so DM's gas API is unchanged.
//!
//! **Watches.** A mixture is watched through core's watch facility over the
//! `TurfGas` channels: turf cells through the field's own watches, main and
//! pipe mixtures through a [`WatchState`] over a mirror of their gas (kept
//! for watched handles only, refreshed on every write this module makes).
//! Gas dependency watches (`watch_dirty_gas_mixture`) are ordinary
//! `Changed` watches on pressure, temperature and composition, one per DM
//! watch handle (`code/datums/om/native.dm`), on their own mirror port so
//! DM handles never meet reactor subscriber ids.

use std::cell::RefCell;
use std::collections::HashMap;

use byondapi::prelude::*;
use eyre::{Result, bail, eyre};
use vg_core::cow::{ChunkLayout, CowStore};
use vg_core::outbox::{Lane, Outbox, Subscriber, Wake, WatchId};
use vg_core::watch::revision::Counter;
use vg_core::watch::{Cond, WatchPort, WatchState};
use vg_gas::cell::{GasCell, GasCmd, N, Q, TurfGas, flags, gas_ch, heat_capacity};
use vg_gas::gas::Mixture;
use vg_gas::gas::constants::{CELL_VOLUME, MINIMUM_HEAT_CAPACITY, TCMB};
use vg_gas::pipes::{PipeGas, Pipes};

use crate::world::with_world;

// --- Handles -------------------------------------------------------------------

/// Main-owned mixtures use handles `0..PIPE_BASE`.
/// @dm-define GAS_HANDLE_PIPE_BASE
pub const PIPE_BASE: u32 = 2_097_152;
/// Turf cells use `TURF_BASE + cell`.
/// @dm-define GAS_HANDLE_TURF_BASE
pub const TURF_BASE: u32 = 4_194_304;
/// Every handle is below this (exact as an `f32`).
const ID_LIMIT: u32 = 1 << 24;

/// What a gas handle names.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum MixRef {
    /// A main-owned mixture slot.
    Main(u32),
    /// A pipe region, by its DM slot.
    Pipe(u32),
    /// A turf's gas, by cell index.
    Turf(u32),
}

impl MixRef {
    #[must_use]
    pub const fn from_id(id: u32) -> Option<Self> {
        match id {
            i if i < PIPE_BASE => Some(Self::Main(i)),
            i if i < TURF_BASE => Some(Self::Pipe(i - PIPE_BASE)),
            i if i < ID_LIMIT => Some(Self::Turf(i - TURF_BASE)),
            _ => None,
        }
    }

    #[must_use]
    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss,
        clippy::cast_precision_loss
    )]
    pub fn from_f32(v: f32) -> Option<Self> {
        if !(v >= 0.0 && v.fract() == 0.0 && v < ID_LIMIT as f32) {
            return None;
        }
        Self::from_id(v as u32)
    }

    #[must_use]
    pub const fn id(self) -> u32 {
        match self {
            Self::Main(i) => i,
            Self::Pipe(s) => PIPE_BASE + s,
            Self::Turf(c) => TURF_BASE + c,
        }
    }

    /// The handle a gas mixture datum holds.
    ///
    /// # Errors
    /// If the datum has no valid handle.
    pub fn of(v: &ByondValue) -> Result<Self> {
        let n = v.read_number_id(byond_string!("_extools_pointer_gasmixture"))?;
        Self::from_f32(n).ok_or_else(|| eyre!("invalid gas mixture handle {n}"))
    }

    /// Writes the handle into a gas mixture datum.
    ///
    /// # Errors
    /// If the var cannot be written.
    pub fn store(self, v: &mut ByondValue) -> Result<()> {
        #[allow(clippy::cast_precision_loss)]
        v.write_var_id(
            byond_string!("_extools_pointer_gasmixture"),
            &ByondValue::from(self.id() as f32),
        )?;
        Ok(())
    }
}

fn missing(r: MixRef) -> eyre::Report {
    eyre!("no gas mixture behind handle {} ({r:?})", r.id())
}

// --- Conversions -------------------------------------------------------------

/// Energy of a mixture as DM sees it, in `f64`.
fn energy_of(mix: &Mixture) -> f64 {
    f64::from(heat_capacity(&mix.moles_array())) * f64::from(mix.get_temperature())
}

/// Moles and energy of a mixture (every gas, then energy).
#[must_use]
pub fn amounts_of(mix: &Mixture) -> [f32; Q] {
    let mut out = [0.0; Q];
    out[..N].copy_from_slice(&mix.moles_array());
    #[allow(clippy::cast_possible_truncation)]
    {
        out[N] = energy_of(mix) as f32;
    }
    out
}

/// A mixture from a turf cell.
#[must_use]
pub fn mixture_of_cell(cell: &GasCell, volume: f32) -> Mixture {
    Mixture::from_parts(
        &cell.moles,
        cell.temperature_now(),
        volume,
        cell.is_immutable(),
    )
}

/// A turf cell holding a mixture's gas.
#[must_use]
pub fn cell_of_mixture(mix: &Mixture) -> GasCell {
    let mut cell = GasCell::new(mix.moles_array(), mix.get_temperature());
    if mix.is_immutable() {
        cell.flags |= flags::IMMUTABLE;
    }
    cell.refresh_in(mix.volume.max(1.0));
    cell
}

#[allow(clippy::cast_possible_truncation)]
fn mixture_of_pipe(gas: &PipeGas, volume: f64) -> Mixture {
    Mixture::from_parts(
        &gas.moles_f32(),
        gas.temperature_now(),
        volume as f32,
        false,
    )
}

// --- The slab and its watches --------------------------------------------------

struct Slot {
    mix: Mixture,
    revision: Counter,
    live: bool,
}

/// Mirror ports: the reactor's watches on main and pipe mixtures, and the
/// dependency watches (subscribers are DM watch handles).
const REACTOR_PORT: u8 = 1;
const DEPENDENCY_PORT: u8 = 2;

/// A watch port over the mixture mirrors.
struct Mirror {
    state: WatchState<TurfGas>,
    port: WatchPort<TurfGas>,
}

impl Mirror {
    fn new(layout: ChunkLayout) -> Self {
        Self {
            state: WatchState::new(layout),
            port: WatchPort::new(layout),
        }
    }

    fn evaluate(&mut self, probes: &CowStore<GasCell>) -> Vec<Wake> {
        let mut outbox: Outbox<GasCell> = Outbox::default();
        self.port.dispatch(&mut self.state);
        self.state.evaluate(probes, &mut outbox);
        self.port.filter(&mut outbox);
        outbox.wakes().to_vec()
    }
}

struct Mixes {
    slots: Vec<Slot>,
    free: Vec<u32>,
    live: usize,
    /// Mirrors of watched main and pipe mixtures, by handle id.
    probes: CowStore<GasCell>,
    reactor: Mirror,
    deps: Mirror,
    /// Watches per handle id (only watched handles are mirrored).
    watched: HashMap<u32, u32>,
    /// The cells of each mirrored watch, by `(port, watch)`, to unmirror them.
    cells: HashMap<(u8, WatchId), Vec<u32>>,
    /// Dependency watches, by DM watch handle: `(mixture id, watch)`.
    dirty: HashMap<Subscriber, (u32, WatchId)>,
}

impl Default for Mixes {
    fn default() -> Self {
        let layout = ChunkLayout::linear_with_chunk(ID_LIMIT, 1024);
        Self {
            slots: Vec::new(),
            free: Vec::new(),
            live: 0,
            probes: CowStore::new(layout),
            reactor: Mirror::new(layout),
            deps: Mirror::new(layout),
            watched: HashMap::new(),
            cells: HashMap::new(),
            dirty: HashMap::new(),
        }
    }
}

thread_local! {
    static MIXES: RefCell<Mixes> = RefCell::new(Mixes::default());
}

fn with_mixes<T>(f: impl FnOnce(&mut Mixes) -> T) -> T {
    MIXES.with_borrow_mut(f)
}

/// Drops every watch but keeps the main-owned slots (`crate::world::build`).
///
/// Main mixtures are owned by their DM datums, not by the world: atoms of a
/// compiled-in map are created before `/world/New()` and allocate slots
/// (a machine's `internal = new()`), and the init/cleanup/configure calls in
/// `/world/New()` rebuild the world after that. Wiping the slab there left
/// those datums holding a dangling handle, or one that aliased a later
/// mixture. The world's watch ports go with the world, so the mirrors and
/// watch tables are rebuilt; the DM watch objects are reset with it.
/// Slots of datums that no longer exist (a previous round in the same
/// process) are freed by [`retain`].
pub(crate) fn reset_watches() {
    MIXES.with_borrow_mut(|m| {
        let fresh = Mixes::default();
        m.probes = fresh.probes;
        m.reactor = fresh.reactor;
        m.deps = fresh.deps;
        m.watched = fresh.watched;
        m.cells = fresh.cells;
        m.dirty = fresh.dirty;
    });
}

/// Frees every live main slot not in `keep`, returning how many were freed.
/// `/world/New()` passes the handles of every `/datum/gas_mixture` that
/// exists, so the slots of a previous round's datums (the library outlives a
/// world reboot) are reclaimed while the compiled-in map's mixtures, and the
/// gas they hold, survive.
pub fn retain(keep: &std::collections::HashSet<u32>) -> usize {
    let stale: Vec<u32> = with_mixes(|m| {
        m.slots
            .iter()
            .enumerate()
            .filter(|(_, s)| s.live)
            .filter_map(|(i, _)| u32::try_from(i).ok())
            .filter(|i| !keep.contains(i))
            .collect()
    });
    for &i in &stale {
        free(i);
    }
    stale.len()
}

/// Allocates a main-owned slot.
///
/// # Errors
/// If every main handle is in use.
pub fn alloc(mix: Mixture) -> Result<u32> {
    with_mixes(|m| {
        let i = if let Some(i) = m.free.pop() {
            i
        } else {
            let i = u32::try_from(m.slots.len())?;
            if i >= PIPE_BASE {
                bail!("out of main gas mixture handles ({PIPE_BASE})");
            }
            m.slots.push(Slot {
                mix: Mixture::new(),
                revision: Counter::new(),
                live: false,
            });
            i
        };
        let slot = &mut m.slots[i as usize];
        slot.mix = mix;
        slot.revision.bump();
        slot.live = true;
        m.live += 1;
        Ok(i)
    })
}

/// Frees a main-owned slot and its dependency watches.
pub fn free(i: u32) {
    let subs: Vec<Subscriber> = with_mixes(|m| {
        m.dirty
            .iter()
            .filter(|(_, (id, _))| *id == i)
            .map(|(&s, _)| s)
            .collect()
    });
    for s in subs {
        unwatch_dirty(s);
    }
    with_mixes(|m| {
        if let Some(slot) = m.slots.get_mut(i as usize).filter(|s| s.live) {
            slot.live = false;
            slot.mix = Mixture::new();
            slot.revision.bump();
            m.free.push(i);
            m.live -= 1;
        }
    });
}

/// `(live main mixtures, main slots)`.
pub fn counts() -> (usize, usize) {
    with_mixes(|m| (m.live, m.slots.len()))
}

fn turf_read(cell: u32) -> Option<(GasCell, vg_core::field::Geom)> {
    let key = super::turf_key().ok()?;
    with_world(|w| Ok(super::turf_read(w, key, cell)))
        .ok()
        .flatten()
}

fn turf_submit(cell: u32, cmd: GasCmd) {
    let _ = with_world(|w| {
        w.submit_cell(super::turf_key()?, cell, cmd)
            .map_err(|e| eyre!("{e}"))
    });
}

fn pipe_probe(slot: u32) -> Option<(PipeGas, f64)> {
    let region = super::region_of_slot(slot)?;
    with_world(|w| {
        let host = w.network::<Pipes>().map_err(|e| eyre!("{e}"))?;
        let r = host.network().region(region).map_err(|e| eyre!("{e}"))?;
        Ok((*r.payload(), *r.summary()))
    })
    .ok()
}

fn pipe_apply(slot: u32, gas: PipeGas) {
    let Some(region) = super::region_of_slot(slot) else {
        return;
    };
    let _ = with_world(|w| {
        w.edit_network::<Pipes>(move |host| {
            let _ = host.set_payload(region, gas);
        })
        .map_err(|e| eyre!("{e}"))
    });
}

/// Loads a mixture by value (turf and pipe gas are built on the fly).
#[must_use]
pub fn load(r: MixRef) -> Option<Mixture> {
    match r {
        MixRef::Main(i) => with_mixes(|m| {
            m.slots
                .get(i as usize)
                .filter(|s| s.live)
                .map(|s| s.mix.clone())
        }),
        MixRef::Pipe(s) => {
            let (gas, volume) = pipe_probe(s)?;
            Some(mixture_of_pipe(&gas, volume))
        }
        MixRef::Turf(c) => {
            let (cell, geom) = turf_read(c)?;
            Some(mixture_of_cell(
                &cell,
                if geom.capacity > 0.0 {
                    geom.capacity
                } else {
                    CELL_VOLUME
                },
            ))
        }
    }
}

/// Stores `after` into `r`, which held `before` (as loaded). Pipe and turf
/// writes apply the difference, so a concurrent change is kept; a turf
/// write is one command with absolute amounts (`rust_core.md` §3.2).
pub fn store(r: MixRef, before: &Mixture, after: &Mixture) {
    if before.same_state(after) {
        return;
    }
    let (b, a) = (before.moles_array(), after.moles_array());
    match r {
        MixRef::Main(i) => with_mixes(|m| {
            if let Some(s) = m.slots.get_mut(i as usize).filter(|s| s.live) {
                s.mix = after.clone();
                s.revision.bump();
            }
        }),
        MixRef::Pipe(s) => {
            let Some((mut gas, _)) = pipe_probe(s) else {
                return;
            };
            for i in 0..N {
                if a[i] != b[i] {
                    gas.moles[i] = (gas.moles[i] + f64::from(a[i] - b[i])).max(0.0);
                }
            }
            gas.energy = (gas.energy + energy_of(after) - energy_of(before)).max(0.0);
            gas.temperature = after.get_temperature();
            pipe_apply(s, gas);
        }
        MixRef::Turf(c) => {
            let Some((cell, _)) = turf_read(c) else {
                return;
            };
            if cell.is_immutable() {
                return;
            }
            let mut d = [0.0f32; Q];
            for i in 0..N {
                d[i] = a[i] - b[i];
            }
            // Energy relative to the cell's own (exact) energy, so a
            // read-modify-write never adds rounding noise.
            let e_after = if after.get_temperature() == before.get_temperature() && a == b {
                f64::from(cell.energy)
            } else {
                energy_of(after)
            };
            #[allow(clippy::cast_possible_truncation)]
            {
                d[N] = (e_after - f64::from(cell.energy)) as f32;
            }
            if d.iter().any(|v| *v != 0.0) {
                turf_submit(c, GasCmd::Delta(d));
            }
            return;
        }
    }
    mirror(r, after);
}

/// Refreshes a watched main or pipe mixture's mirror.
fn mirror(r: MixRef, mix: &Mixture) {
    with_mixes(|m| {
        if m.watched.contains_key(&r.id()) {
            m.probes.set(r.id(), cell_of_mixture(mix));
        }
    });
}

/// Adds amounts to a mixture (released pipe gas, reconciliations).
/// Negative amounts clamp at zero.
pub fn add_amounts(r: MixRef, amounts: &[f32; Q], temperature_hint: f32) {
    if let MixRef::Turf(c) = r {
        turf_submit(c, GasCmd::Delta(*amounts));
        return;
    }
    let Some(before) = load(r) else { return };
    if before.is_immutable() {
        return;
    }
    let mut moles = before.moles_array();
    for (m, a) in moles.iter_mut().zip(amounts) {
        *m = (*m + a).max(0.0);
    }
    let energy = (energy_of(&before) + f64::from(amounts[N])).max(0.0);
    let c = f64::from(heat_capacity(&moles));
    #[allow(clippy::cast_possible_truncation)]
    let t = if c > f64::from(MINIMUM_HEAT_CAPACITY) {
        ((energy / c) as f32).max(TCMB)
    } else if temperature_hint > 0.0 {
        temperature_hint
    } else {
        before.get_temperature()
    };
    let mut after = Mixture::from_parts(&moles, t, before.volume, false);
    after.set_min_heat_capacity(before.min_heat_capacity());
    store(r, &before, &after);
}

/// DM's `revision()`: bumped whenever the gas changes.
#[must_use]
pub fn revision(r: MixRef) -> u32 {
    match r {
        MixRef::Main(i) => with_mixes(|m| m.slots.get(i as usize).map_or(0, |s| s.revision.get())),
        MixRef::Pipe(s) => super::region_of_slot(s)
            .and_then(|region| {
                with_world(|w| {
                    Ok(w.network::<Pipes>()
                        .map(|h| h.region_revision(region))
                        .unwrap_or(0))
                })
                .ok()
            })
            .map_or(0, |r| u32::try_from(r & 0x00FF_FFFF).unwrap_or(0)),
        MixRef::Turf(c) => turf_read(c).map_or(0, |(cell, _)| cell.revision()),
    }
}

// --- The mixture access every gas bind uses ------------------------------------

/// Calls `f` with the mixture behind a `/datum/gas_mixture`.
///
/// # Errors
/// If the datum has no live handle, or `f` fails.
pub fn with_mix<T>(mix: &ByondValue, f: impl FnOnce(&Mixture) -> Result<T>) -> Result<T> {
    let r = MixRef::of(mix)?;
    f(&load(r).ok_or_else(|| missing(r))?)
}

/// As [`with_mix`], but mutable. A turf's gas changes by one command.
///
/// # Errors
/// If the datum has no live handle, or `f` fails.
pub fn with_mix_mut<T>(mix: &ByondValue, f: impl FnOnce(&mut Mixture) -> Result<T>) -> Result<T> {
    let r = MixRef::of(mix)?;
    let before = load(r).ok_or_else(|| missing(r))?;
    let mut after = before.clone();
    let out = f(&mut after)?;
    store(r, &before, &after);
    Ok(out)
}

/// As [`with_mix`], with two mixtures.
///
/// # Errors
/// If a datum has no live handle, or `f` fails.
pub fn with_mixes2<T>(
    src: &ByondValue,
    arg: &ByondValue,
    f: impl FnOnce(&Mixture, &Mixture) -> Result<T>,
) -> Result<T> {
    let (a, b) = (MixRef::of(src)?, MixRef::of(arg)?);
    f(
        &load(a).ok_or_else(|| missing(a))?,
        &load(b).ok_or_else(|| missing(b))?,
    )
}

/// As [`with_mix_mut`], with two mixtures. When both datums name the same
/// mixture, only the first argument's changes are kept.
///
/// # Errors
/// If a datum has no live handle, or `f` fails.
pub fn with_mixes_mut<T>(
    src: &ByondValue,
    arg: &ByondValue,
    f: impl FnOnce(&mut Mixture, &mut Mixture) -> Result<T>,
) -> Result<T> {
    let (a, b) = (MixRef::of(src)?, MixRef::of(arg)?);
    let before_a = load(a).ok_or_else(|| missing(a))?;
    let before_b = load(b).ok_or_else(|| missing(b))?;
    let (mut ma, mut mb) = (before_a.clone(), before_b.clone());
    let out = f(&mut ma, &mut mb)?;
    store(a, &before_a, &ma);
    if a != b {
        store(b, &before_b, &mb);
    }
    Ok(out)
}

/// The loaded mixture or the "no gas" error.
///
/// # Errors
/// If `r` names no mixture.
pub fn load_or_err(r: MixRef) -> Result<Mixture> {
    load(r).ok_or_else(|| missing(r))
}

// --- Watches -------------------------------------------------------------------

fn cond_cells(cond: &Cond, out: &mut Vec<u32>) {
    match cond {
        Cond::Changed { cell, .. }
        | Cond::Threshold { cell, .. }
        | Cond::Band { cell, .. }
        | Cond::ThresholdSet { cell, .. } => out.push(*cell),
        Cond::Difference { a, b, .. } => out.extend([*a, *b]),
        Cond::Any(cs) | Cond::All(cs) => cs.iter().for_each(|c| cond_cells(c, out)),
    }
}

/// Registers a watch on gas handles (turf cells, or main and pipe
/// mixtures; one kind per condition). Returns `(port, id)`: port 0 the
/// turf field's watches, 1 the mixtures'.
///
/// # Errors
/// If the handles are invalid or mixed, or the condition is rejected.
pub fn watch(sub: Subscriber, lane: Lane, cond: &Cond) -> Result<(u8, WatchId)> {
    let mut ids = Vec::new();
    cond_cells(cond, &mut ids);
    let refs = ids
        .iter()
        .map(|&id| MixRef::from_id(id).ok_or_else(|| eyre!("bad gas handle {id}")))
        .collect::<Result<Vec<_>>>()?;
    if refs.iter().all(|r| matches!(r, MixRef::Turf(_))) {
        let cells =
            crate::world::map_cells(cond, &|id| Ok(id - TURF_BASE)).map_err(|e| eyre!("{e}"))?;
        let id = with_world(|w| {
            w.watch_cells::<TurfGas>(sub, lane, &cells)
                .map_err(|e| eyre!("{e}"))
        })?;
        return Ok((0, id));
    }
    if refs.iter().any(|r| matches!(r, MixRef::Turf(_))) {
        bail!("a gas watch takes turf gas or other mixtures, not both");
    }
    watch_mirrored(REACTOR_PORT, sub, lane, cond, ids).map(|id| (REACTOR_PORT, id))
}

/// Registers `cond` on the mirror port (any handles, turf cells included:
/// their mirror is refreshed from DM's own view at each drain) and primes
/// it with the current values, so a write right after registering fires.
fn watch_mirrored(
    port: u8,
    sub: Subscriber,
    lane: Lane,
    cond: &Cond,
    ids: Vec<u32>,
) -> Result<WatchId> {
    let loaded: Vec<(u32, Option<Mixture>)> = ids
        .iter()
        .map(|&h| (h, MixRef::from_id(h).and_then(load)))
        .collect();
    let (id, primed) = with_mixes(|m| {
        let mirror = if port == DEPENDENCY_PORT {
            &mut m.deps
        } else {
            &mut m.reactor
        };
        let id = mirror
            .port
            .watch(sub, lane, cond)
            .map_err(|e| eyre!("{e:?}"))?;
        for (h, mix) in loaded {
            *m.watched.entry(h).or_default() += 1;
            if let Some(mix) = mix {
                m.probes.set(h, cell_of_mixture(&mix));
            }
        }
        m.cells.insert((port, id), ids);
        Ok::<_, eyre::Report>((id, evaluate(m)))
    })?;
    HELD.with_borrow_mut(|h| {
        h.2.extend(primed.0);
        h.1.extend(primed.1);
    });
    Ok(id)
}

/// Runs both mirror ports' watches once: `(reactor wakes, dependency wakes)`.
fn evaluate(m: &mut Mixes) -> (Vec<Wake>, Vec<Wake>) {
    (m.reactor.evaluate(&m.probes), m.deps.evaluate(&m.probes))
}

/// Removes a watch [`watch`] returned.
pub fn unwatch(port: u8, id: WatchId) {
    if port == 0 {
        let _ = with_world(|w| w.unwatch_cells::<TurfGas>(id).map_err(|e| eyre!("{e}")));
        return;
    }
    with_mixes(|m| {
        let mirror = if port == DEPENDENCY_PORT {
            &mut m.deps
        } else {
            &mut m.reactor
        };
        let _ = mirror.port.unwatch(id);
        for h in m.cells.remove(&(port, id)).unwrap_or_default() {
            if let Some(n) = m.watched.get_mut(&h) {
                *n -= 1;
                if *n == 0 {
                    m.watched.remove(&h);
                }
            }
        }
    });
}

/// Every gas wake since the last call: the turf field's (source: the
/// cell's gas handle) and the mixtures' (source: the handle).
fn take_wakes() -> Vec<Wake> {
    let mut turf = Vec::new();
    let _ = with_world(|w| {
        w.drain_field_wakes::<TurfGas>(&mut turf);
        Ok(())
    });
    let mut out: Vec<Wake> = turf
        .into_iter()
        .map(|w| Wake {
            source: MixRef::Turf(w.source).id(),
            ..w
        })
        .collect();
    // Turf cells change on the worker: refresh their mirrors from DM's view.
    let turfs: Vec<u32> = with_mixes(|m| {
        m.watched
            .keys()
            .copied()
            .filter(|&h| h >= TURF_BASE)
            .collect()
    });
    let fresh: Vec<(u32, GasCell)> = turfs
        .into_iter()
        .filter_map(|h| Some((h, cell_of_mixture(&load(MixRef::from_id(h)?)?))))
        .collect();
    let deps = with_mixes(|m| {
        for (h, c) in fresh {
            m.probes.set(h, c);
        }
        let (reactor, deps) = evaluate(m);
        out.extend(reactor);
        deps
    });
    HELD.with_borrow_mut(|h| {
        h.1.extend(deps);
        out.append(&mut h.2);
    });
    out
}

thread_local! {
    /// Wakes collected for one side (reactor or dirty) while draining the
    /// other: every drain takes both.
    static HELD: RefCell<(Vec<Wake>, Vec<Wake>, Vec<Wake>)> = const { RefCell::new((Vec::new(), Vec::new(), Vec::new())) };
}

/// Collects every pending wake: the reactor's into `HELD.0`, the
/// dependency watches' into `HELD.1`.
fn split_wakes() {
    let wakes = take_wakes();
    HELD.with_borrow_mut(|(reactor, _, _)| reactor.extend(wakes));
}

/// The reactor's gas wakes since the last call.
pub fn reactor_wakes(out: &mut Vec<Wake>) {
    split_wakes();
    HELD.with_borrow_mut(|(reactor, _, _)| out.append(reactor));
}

/// Dirty-change bits DM machinery interest masks use.
/// @dm-define GAS_DEPENDENCY_PRESSURE
pub const GAS_CHANGE_PRESSURE: u8 = 1;
/// @dm-define GAS_DEPENDENCY_TEMPERATURE
pub const GAS_CHANGE_TEMPERATURE: u8 = 2;
/// @dm-define GAS_DEPENDENCY_COMPOSITION
pub const GAS_CHANGE_COMPOSITION: u8 = 4;

const DIRTY_CHANNELS: [(u8, vg_core::channel::ChannelId); 3] = [
    (GAS_CHANGE_PRESSURE, gas_ch::PRESSURE),
    (GAS_CHANGE_TEMPERATURE, gas_ch::TEMPERATURE),
    (GAS_CHANGE_COMPOSITION, gas_ch::COMPOSITION),
];

/// DM watch `sub` watches mixture `id` for pressure, temperature or
/// composition changes (`mask`: `GAS_CHANGE_*`), replacing its earlier watch.
pub fn watch_dirty(id: u32, sub: Subscriber, mask: u8) {
    unwatch_dirty(sub);
    let bits = DIRTY_CHANNELS
        .iter()
        .filter(|(b, _)| mask & b != 0)
        .fold(0u32, |acc, (_, ch)| acc | ch.bit());
    if bits == 0 {
        return;
    }
    let cond = Cond::Changed {
        cell: id,
        mask: bits,
    };
    if let Ok(w) = watch_mirrored(DEPENDENCY_PORT, sub, Lane::Normal, &cond, vec![id]) {
        with_mixes(|m| m.dirty.insert(sub, (id, w)));
    }
}

/// Drops DM watch `sub`'s dependency watch.
pub fn unwatch_dirty(sub: Subscriber) {
    if let Some((_, w)) = with_mixes(|m| m.dirty.remove(&sub)) {
        unwatch(DEPENDENCY_PORT, w);
    }
}

/// Drains dependency notifications with the control-relevant state of each
/// mixture, `GAS_DEPENDENCY_OBSERVATION_STRIDE` floats per record: watch
/// handle, mixture id, mask, revision, pressure, temperature, volume, o2, co2, plasma,
/// methane, n2o, volatile fuel, miasma, zauker, total moles.
pub fn drain_observations() -> Vec<f32> {
    use vg_gas::gas::ids::{
        GAS_CARBON_DIOXIDE, GAS_METHANE, GAS_MIASMA, GAS_NITROUS_OXIDE, GAS_OXYGEN, GAS_PLASMA,
        GAS_VOLATILE_FUEL, GAS_ZAUKER,
    };
    split_wakes();
    let mut masks: Vec<(Subscriber, u32, u8)> = Vec::new();
    HELD.with_borrow_mut(|(_, dirty, _)| {
        for w in dirty.drain(..) {
            let mask = DIRTY_CHANNELS
                .iter()
                .filter(|(_, ch)| w.reason & ch.bit() != 0)
                .fold(0u8, |acc, (b, _)| acc | b);
            masks.push((w.subscriber, w.source, mask));
        }
    });
    masks.sort_unstable();
    masks.dedup_by(|b, a| {
        if a.0 == b.0 {
            a.2 |= b.2;
            true
        } else {
            false
        }
    });
    let gases = [
        GAS_OXYGEN,
        GAS_CARBON_DIOXIDE,
        GAS_PLASMA,
        GAS_METHANE,
        GAS_NITROUS_OXIDE,
        GAS_VOLATILE_FUEL,
        GAS_MIASMA,
        GAS_ZAUKER,
    ];
    let mut values = Vec::with_capacity(masks.len() * GAS_OBSERVATION_STRIDE);
    for (sub, id, mask) in masks {
        let Some(r) = MixRef::from_id(id) else {
            continue;
        };
        let Some(m) = load(r) else { continue };
        #[allow(clippy::cast_precision_loss)]
        values.extend([
            sub as f32,
            id as f32,
            f32::from(mask),
            (revision(r) & 0x00FF_FFFF) as f32,
            m.return_pressure(),
            m.get_temperature(),
            m.volume,
        ]);
        values.extend(gases.iter().map(|&g| m.get_moles(g)));
        values.push(m.total_moles());
    }
    values
}

/// Floats per record returned by `drain_dirty_gas_observations`.
/// @dm-define GAS_DEPENDENCY_OBSERVATION_STRIDE
pub const GAS_OBSERVATION_STRIDE: usize = 16;

#[cfg(test)]
mod tests {
    use super::*;
    use vg_gas::gas::ids::GAS_OXYGEN;

    fn tank(moles: f32) -> Mixture {
        let mut m = Mixture::from_vol(70.0);
        m.set_moles(GAS_OXYGEN, moles);
        m.set_temperature(293.15);
        m
    }

    #[test]
    fn a_world_rebuild_keeps_main_mixtures_and_their_gas() {
        with_world(|_| Ok(())).unwrap();
        let slot = alloc(tank(42.0)).unwrap();
        crate::world::reset().unwrap();
        crate::world::configure_for_test(8, 8, 2).unwrap();
        let mix = load(MixRef::Main(slot)).expect("slot survives the rebuild");
        assert!((mix.get_moles(GAS_OXYGEN) - 42.0).abs() < 1e-4);
        let other = alloc(tank(1.0)).unwrap();
        assert_ne!(other, slot, "a live slot is not handed out again");
        free(other);
        free(slot);
    }

    #[test]
    fn retain_frees_only_the_slots_left_out() {
        with_world(|_| Ok(())).unwrap();
        let (a, b) = (alloc(tank(5.0)).unwrap(), alloc(tank(6.0)).unwrap());
        let keep: std::collections::HashSet<u32> = [a].into_iter().collect();
        let (live_before, _) = counts();
        let freed = retain(&keep);
        assert!(freed >= 1);
        assert!(load(MixRef::Main(a)).is_some());
        assert_eq!(counts().0, live_before - freed);
        let reused = alloc(tank(1.0)).unwrap();
        assert!(
            load(MixRef::Main(a)).is_some_and(|m| (m.get_moles(GAS_OXYGEN) - 5.0).abs() < 1e-4)
        );
        let _ = b;
        free(reused);
        free(a);
    }

    #[test]
    fn each_dependency_watch_hears_its_own_mixture() {
        with_world(|_| Ok(())).unwrap();
        let (a, b) = (alloc(tank(10.0)).unwrap(), alloc(tank(10.0)).unwrap());
        let (ra, rb) = (MixRef::Main(a), MixRef::Main(b));
        watch_dirty(ra.id(), 7, GAS_CHANGE_PRESSURE);
        watch_dirty(ra.id(), 9, GAS_CHANGE_PRESSURE);
        watch_dirty(rb.id(), 11, GAS_CHANGE_TEMPERATURE);
        let _ = drain_observations();
        let before = load(ra).unwrap();
        store(ra, &before, &tank(20.0));
        let obs = drain_observations();
        let heard: Vec<(f32, f32)> = obs
            .chunks_exact(GAS_OBSERVATION_STRIDE)
            .map(|o| (o[0], o[1]))
            .collect();
        #[allow(clippy::cast_precision_loss)]
        let id = ra.id() as f32;
        assert_eq!(heard, vec![(7.0, id), (9.0, id)], "{obs:?}");
        unwatch_dirty(7);
        let before = load(ra).unwrap();
        store(ra, &before, &tank(30.0));
        let obs = drain_observations();
        assert_eq!(
            obs.len(),
            GAS_OBSERVATION_STRIDE,
            "only watch 9 is left: {obs:?}"
        );
        free(a);
        free(b);
    }

    #[test]
    fn a_changed_watch_on_a_main_mixture_wakes_on_a_write_only() {
        with_world(|_| Ok(())).unwrap();
        let slot = alloc(tank(10.0)).unwrap();
        let r = MixRef::Main(slot);
        let cond = Cond::Changed {
            cell: r.id(),
            mask: gas_ch::PRESSURE.bit(),
        };
        watch(5, Lane::Urgent, &cond).unwrap();
        let mut out = Vec::new();
        reactor_wakes(&mut out);
        assert!(out.is_empty(), "fired at registration: {out:?}");
        let before = load(r).unwrap();
        store(r, &before, &tank(20.0));
        reactor_wakes(&mut out);
        assert_eq!(out.len(), 1, "{out:?}");
        assert_eq!(out[0].source, r.id());
    }
}
