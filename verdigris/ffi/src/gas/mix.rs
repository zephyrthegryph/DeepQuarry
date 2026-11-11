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
//! A DM holder that wants to hear a gas change registers an ordinary world
//! `Changed` watch (`world_watch_changed` on a `VG_GAS_HANDLES` handle); there
//! is no separate dependency channel.

use std::cell::RefCell;
use std::collections::HashMap;

use crate::held::HeldRead;
use byondapi::prelude::*;
use eyre::{Result, bail, eyre};
use vg_core::cow::{ChunkLayout, CowStore};
use vg_core::outbox::{Lane, Outbox, Subscriber, Wake, WatchId};
use vg_core::watch::revision::Counter;
use vg_core::watch::{Cond, WatchPort, WatchState};
use vg_core::world::ThresholdCrossing;
use vg_gas::cell::{GasCell, GasCmd, N, Q, TurfGas, gas_ch, heat_capacity};
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

    /// The handle a gas mixture datum holds, with the generation the datum
    /// was stamped with (`None` when the datum carries none).
    ///
    /// # Errors
    /// If the datum has no valid handle.
    pub fn of_unchecked(v: &ByondValue) -> Result<(Self, Option<u32>)> {
        let n = v.read_number_id(byond_string!("_extools_pointer_gasmixture"))?;
        let r = Self::from_f32(n).ok_or_else(|| eyre!("invalid gas mixture handle {n}"))?;
        let held = v
            .held_var_id(byond_string!("_extools_generation_gasmixture"))
            .ok()
            .filter(|g| !g.is_null())
            .and_then(|g| g.get_number().ok())
            .map(generation_from_f32);
        Ok((r, held))
    }

    /// The handle a gas mixture datum holds. A handle whose generation is not
    /// the one the owner is at now (the mixture was freed, or the turf or
    /// region was replaced, since the datum was stamped) is refused: the error
    /// names the owner type, the handle and both generations.
    ///
    /// # Errors
    /// If the datum has no valid handle, or the handle is stale.
    pub fn of(v: &ByondValue) -> Result<Self> {
        let (r, held) = Self::of_unchecked(v)?;
        check_generation(r, held).map_err(|stale| stale.report(v))?;
        Ok(r)
    }

    /// Writes the handle and its current generation into a gas mixture datum.
    ///
    /// # Errors
    /// If the vars cannot be written.
    pub fn store(self, v: &mut ByondValue) -> Result<()> {
        #[allow(clippy::cast_precision_loss)]
        {
            v.write_var_id(
                byond_string!("_extools_pointer_gasmixture"),
                &ByondValue::from(self.id() as f32),
            )?;
            v.write_var_id(
                byond_string!("_extools_generation_gasmixture"),
                &ByondValue::from(generation(self) as f32),
            )?;
        }
        Ok(())
    }

    /// Clears a datum's handle (its owner let go of it).
    ///
    /// # Errors
    /// If the vars cannot be written.
    pub fn clear(v: &mut ByondValue) -> Result<()> {
        v.write_var_id(
            byond_string!("_extools_pointer_gasmixture"),
            &ByondValue::null(),
        )?;
        v.write_var_id(
            byond_string!("_extools_generation_gasmixture"),
            &ByondValue::null(),
        )?;
        Ok(())
    }
}

// --- Generations -----------------------------------------------------------------

/// A generation is a number a datum can hold exactly (an `f32`).
pub const GENERATION_MASK: u32 = 0x00FF_FFFF;

/// The generation after `g`.
#[must_use]
pub const fn next_generation(g: u32) -> u32 {
    g.wrapping_add(1) & GENERATION_MASK
}

#[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
fn generation_from_f32(v: f32) -> u32 {
    if v >= 0.0 {
        (v as u32) & GENERATION_MASK
    } else {
        u32::MAX
    }
}

thread_local! {
    /// Turf cell generations. A cell has no slot to carry one: it is bumped when
    /// a turf's air is bound to the cell and when the cell is unregistered, so
    /// the old turf object a `ChangeTurf` leaves behind holds a stale one.
    static TURF_GENERATIONS: RefCell<HashMap<u32, u32>> = RefCell::new(HashMap::new());
}

/// Starts a new owner of turf `cell`: every datum stamped before is stale.
pub fn bump_turf_generation(cell: u32) -> u32 {
    TURF_GENERATIONS.with_borrow_mut(|g| {
        let e = g.entry(cell).or_insert(0);
        *e = next_generation(*e);
        *e
    })
}

/// The generation `r` is at now.
#[must_use]
pub fn generation(r: MixRef) -> u32 {
    match r {
        MixRef::Main(i) => with_mixes(|m| m.slots.get(i as usize).map_or(0, |s| s.generation)),
        MixRef::Pipe(s) => super::pipe_slot_generation(s),
        MixRef::Turf(c) => TURF_GENERATIONS.with_borrow(|g| g.get(&c).copied().unwrap_or(0)),
    }
}

/// What a stale handle looks like.
#[derive(Debug, PartialEq, Eq)]
pub struct Stale {
    pub handle: MixRef,
    pub held: Option<u32>,
    pub current: u32,
}

impl Stale {
    /// The runtime for a datum holding this handle: owner type, handle and both
    /// generations (BYOND adds the DM stack to a bind's error).
    pub fn report(&self, owner: &ByondValue) -> eyre::Report {
        let label = owner
            .held_call_id(byond_string!("handle_owner_label"), &[])
            .ok()
            .and_then(|v| v.get_string().ok())
            .unwrap_or_else(|| "unknown owner".to_string());
        eyre!(
            "stale gas mixture handle {} ({:?}) on {label}: the datum holds generation {:?}, the {} is at generation {}; the mixture it named was freed or replaced",
            self.handle.id(),
            self.handle,
            self.held,
            match self.handle {
                MixRef::Main(_) => "main slot",
                MixRef::Pipe(_) => "pipe region slot",
                MixRef::Turf(_) => "turf cell",
            },
            self.current,
        )
    }
}

/// Whether a datum stamped with `held` may use `r`.
///
/// # Errors
/// [`Stale`] when it may not (a datum with no generation never may).
pub fn check_generation(r: MixRef, held: Option<u32>) -> std::result::Result<(), Stale> {
    let current = generation(r);
    if held == Some(current) {
        Ok(())
    } else {
        Err(Stale {
            handle: r,
            held,
            current,
        })
    }
}

/// A handle that arrives as two numbers (a queued batch keeps no datum): `id` is
/// the handle, `held` the generation it was stamped with. Refused when `id` is
/// not a handle or the owner has moved on since.
///
/// # Errors
/// If `id` is not a handle, or it is stale.
pub fn checked_ref(id: f32, held: Option<u32>) -> Result<MixRef> {
    let r = MixRef::from_f32(id).ok_or_else(|| eyre!("invalid gas mixture handle {id}"))?;
    check_generation(r, held).map_err(|s| {
        eyre!(
            "stale gas mixture handle {} ({:?}): queued with generation {:?}, now at {}",
            r.id(),
            r,
            s.held,
            s.current
        )
    })?;
    Ok(r)
}

/// [`checked_ref`] for the two numbers DM queued.
///
/// # Errors
/// As [`checked_ref`], or if either is not a number.
pub fn checked_ref_value(id: &ByondValue, generation: &ByondValue) -> Result<MixRef> {
    checked_ref(
        id.get_number()?,
        Some(generation_from_f32(generation.get_number()?)),
    )
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
pub fn mixture_of_cell(cell: &GasCell, volume: f32, immutable: bool) -> Mixture {
    Mixture::from_parts(&cell.moles, cell.temperature_now(), volume, immutable)
}

/// A turf cell holding a mixture's gas.
#[must_use]
pub fn cell_of_mixture(mix: &Mixture) -> GasCell {
    let mut cell = GasCell::new(mix.moles_array(), mix.get_temperature());
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
    /// Bumped each time the slot is freed, so a datum that still holds the
    /// number of a freed slot cannot read the mixture that reuses it.
    generation: u32,
}

/// Mirror port: the reactor's watches on main and pipe mixtures.
const REACTOR_PORT: u8 = 1;

thread_local! {
    /// `ThresholdSet` crossings of the mirror port found since the last [`take_crossings`].
    static MIRROR_CROSSINGS: RefCell<Vec<ThresholdCrossing>> = const { RefCell::new(Vec::new()) };
}

/// Keeps the set crossings of `outbox` (the stale ones are already filtered out) for the frame.
fn note_crossings(outbox: &Outbox<GasCell>) {
    MIRROR_CROSSINGS.with_borrow_mut(|out| {
        out.extend(
            outbox
                .events()
                .iter()
                .filter(|e| e.kind == vg_core::outbox::EventKind::ThresholdCrossed)
                .map(|e| ThresholdCrossing {
                    watch: e.key,
                    payload: e.extra,
                    entered: e.value > 0.5,
                    generation: e.generation,
                }),
        );
    });
}

/// Every set crossing of the mirror port (main and pipe mixtures) since the last call.
pub fn take_crossings() -> Vec<ThresholdCrossing> {
    MIRROR_CROSSINGS.with_borrow_mut(std::mem::take)
}

/// Adds (or replaces, by payload) an entry of a set watch [`watch`] returned.
///
/// # Errors
/// If the watch is stale or the entry is refused.
pub fn add_entry(port: u8, id: WatchId, entry: vg_core::watch::SetEntry) -> Result<()> {
    if port == 0 {
        return with_world(|w| {
            w.add_field_watch_entry::<TurfGas>(id, entry)
                .map_err(|e| eyre!("{e}"))
        });
    }
    with_mixes(|m| m.reactor.port.add_entry(id, entry)).map_err(|e| eyre!("{e}"))
}

/// Removes an entry of a set watch.
pub fn remove_entry(port: u8, id: WatchId, payload: u32) {
    if port == 0 {
        let _ = with_world(|w| Ok(w.remove_field_watch_entry::<TurfGas>(id, payload)));
        return;
    }
    with_mixes(|m| {
        let _ = m.reactor.port.remove_entry(id, payload);
    });
}

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

    fn evaluate(&mut self, probes: &CowStore<GasCell>, written: &[usize]) -> Vec<Wake> {
        let started = std::time::Instant::now();
        let mut outbox: Outbox<GasCell> = Outbox::default();
        self.port.dispatch(&mut self.state);
        self.state.evaluate_chunks(probes, written, &mut outbox);
        self.port.filter(&mut outbox);
        note_crossings(&outbox);
        // Cumulative: how often a drain finds changed mirror chunks and evaluates, and what that costs.
        let stats = self.state.stats();
        let metrics = crate::metrics::registry();
        metrics.counter("gas_watch.mirror_evaluations").inc();
        if stats.changed_chunks > 0 {
            metrics.counter("gas_watch.mirror_full_passes").inc();
            metrics
                .counter("gas_watch.mirror_changed_chunks")
                .add(stats.changed_chunks as u64);
            metrics
                .counter("gas_watch.mirror_evaluated")
                .add(stats.evaluated as u64);
        }
        #[allow(clippy::cast_possible_truncation)]
        metrics
            .counter("gas_watch.mirror_us")
            .add(started.elapsed().as_micros() as u64);
        outbox.wakes().to_vec()
    }

    /// Evaluates only the watches registered since the last evaluation
    /// (`WatchState::evaluate_fresh`): what a registration pays.
    fn prime(&mut self, probes: &CowStore<GasCell>) -> Vec<Wake> {
        let mut outbox: Outbox<GasCell> = Outbox::default();
        self.port.dispatch(&mut self.state);
        self.state.evaluate_fresh(probes, &mut outbox);
        self.port.filter(&mut outbox);
        note_crossings(&outbox);
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
    /// Watches per handle id (only watched handles are mirrored).
    watched: HashMap<u32, u32>,
    /// The cells of each mirrored watch, by `(port, watch)`, to unmirror them.
    cells: HashMap<(u8, WatchId), Vec<u32>>,
    /// Probe chunks written since the mirrors last evaluated, each once (`written_mark`). The mirrors are
    /// told which chunks changed instead of diffing the 16k-chunk store against a snapshot, which also
    /// made every first write to a chunk copy it (the snapshot shared it).
    written: Vec<usize>,
    written_mark: Vec<bool>,
    /// The pipe region revision each watched pipe handle's mirror was last read at. A region changes outside
    /// [`store`] too (a device step's write-back, a heat exchanger levelling two loops), so a drain re-reads every
    /// watched pipe handle whose region moved (`refresh_pipe_mirrors`): the network's own change tracking, not the
    /// writer, keeps the mirror current.
    pipe_seen: HashMap<u32, u64>,
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
            watched: HashMap::new(),
            cells: HashMap::new(),
            written: Vec::new(),
            written_mark: vec![false; layout.chunk_count()],
            pipe_seen: HashMap::new(),
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
        m.watched = fresh.watched;
        m.cells = fresh.cells;
        m.written = fresh.written;
        m.written_mark = fresh.written_mark;
        m.pipe_seen = fresh.pipe_seen;
    });
    MIRROR_CROSSINGS.with_borrow_mut(Vec::clear);
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
                generation: 0,
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

/// Frees a main-owned slot.
pub fn free(i: u32) {
    release_slot(i);
}

/// Frees a main-owned slot whose gas moved into a turf's field cell (a turf's air joining the arena). A DM holder's watch on the slot is not
/// carried over: a holder that watched before the turfs registered is registered with Rust after (`gas_turfs_registered()`).
pub fn free_into_turf(i: u32) {
    release_slot(i);
}

fn release_slot(i: u32) {
    with_mixes(|m| {
        if let Some(slot) = m.slots.get_mut(i as usize).filter(|s| s.live) {
            slot.live = false;
            slot.mix = Mixture::new();
            slot.revision.bump();
            slot.generation = next_generation(slot.generation);
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
        super::submit_turf(w, super::turf_key()?, cell, cmd);
        Ok(())
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
                cell.immutable_in(&geom),
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
            let Some((cell, geom)) = turf_read(c) else {
                return;
            };
            if cell.immutable_in(&geom) {
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

/// Writes a mirror only when it changes. `CowStore::set` copies the whole
/// chunk (1024 cells) when the watch states' last snapshot still shares it,
/// even for an equal value, and a changed chunk also makes every watch in it
/// re-evaluate at the next drain.
fn set_probe(m: &mut Mixes, h: u32, cell: GasCell) {
    if m.probes.get(h) != Some(cell) {
        m.probes.set(h, cell);
        if let Some((chunk, _)) = m.probes.layout().locate(h)
            && !m.written_mark[chunk]
        {
            m.written_mark[chunk] = true;
            m.written.push(chunk);
        }
    }
}

/// Refreshes a watched main or pipe mixture's mirror.
fn mirror(r: MixRef, mix: &Mixture) {
    with_mixes(|m| {
        if m.watched.contains_key(&r.id()) {
            set_probe(m, r.id(), cell_of_mixture(mix));
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

/// Registers `cond` on the mirror port (main and pipe mixtures) and primes
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
        let id = m
            .reactor
            .port
            .watch(sub, lane, cond)
            .map_err(|e| eyre!("{e:?}"))?;
        for (h, mix) in loaded {
            *m.watched.entry(h).or_default() += 1;
            if let Some(mix) = mix {
                set_probe(m, h, cell_of_mixture(&mix));
            }
        }
        m.cells.insert((port, id), ids);
        // Only the new watch is evaluated (its baseline): a full evaluate of
        // both ports here cost ~1 ms per registration and made boot, which
        // registers thousands, quadratic. Other watches see the probes just
        // set at the next drain.
        let wakes = m.reactor.prime(&m.probes);
        Ok::<_, eyre::Report>((id, wakes))
    })?;
    HELD.with_borrow_mut(|h| h.extend(primed));
    Ok(id)
}

/// Runs the mirror port's watches once.
fn evaluate(m: &mut Mixes) -> Vec<Wake> {
    let written = std::mem::take(&mut m.written);
    for &c in &written {
        m.written_mark[c] = false;
    }
    m.reactor.evaluate(&m.probes, &written)
}

/// Removes a watch [`watch`] returned.
pub fn unwatch(port: u8, id: WatchId) {
    if port == 0 {
        let _ = with_world(|w| w.unwatch_cells::<TurfGas>(id).map_err(|e| eyre!("{e}")));
        return;
    }
    with_mixes(|m| {
        let _ = m.reactor.port.unwatch(id);
        for h in m.cells.remove(&(port, id)).unwrap_or_default() {
            if let Some(n) = m.watched.get_mut(&h) {
                *n -= 1;
                if *n == 0 {
                    m.watched.remove(&h);
                    m.pipe_seen.remove(&h);
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
    let pipes = refresh_pipe_mirrors();
    let evaluated = std::time::Instant::now();
    with_mixes(|m| {
        for (h, c) in pipes {
            set_probe(m, h, c);
        }
        out.extend(evaluate(m));
    });
    #[allow(clippy::cast_possible_truncation)]
    crate::metrics::registry()
        .counter("gas_watch.evaluate_us_total")
        .add(evaluated.elapsed().as_micros() as u64);
    HELD.with_borrow_mut(|h| out.append(h));
    out
}

/// The watched pipe handles whose region moved since their mirror was last read, freshly read. Pipe gas changes in
/// ways [`store`] never sees (a device step writes its region back on the world, `crate::pipes::apply_devices`), so
/// a watch on a pipe region asks the network's region revision instead of trusting every writer to report.
fn refresh_pipe_mirrors() -> Vec<(u32, GasCell)> {
    let handles: Vec<u32> = with_mixes(|m| {
        m.watched
            .keys()
            .copied()
            .filter(|&h| matches!(MixRef::from_id(h), Some(MixRef::Pipe(_))))
            .collect()
    });
    if handles.is_empty() {
        return Vec::new();
    }
    let revisions: Vec<(u32, u64)> = with_world(|w| {
        let Ok(host) = w.network::<Pipes>() else {
            return Ok(Vec::new());
        };
        Ok(handles
            .iter()
            .filter_map(|&h| {
                let Some(MixRef::Pipe(slot)) = MixRef::from_id(h) else {
                    return None;
                };
                let region = super::region_of_slot(slot)?;
                Some((h, host.region_revision(region)))
            })
            .collect())
    })
    .unwrap_or_default();
    let moved: Vec<(u32, u64)> = with_mixes(|m| {
        revisions
            .into_iter()
            .filter(|(h, rev)| m.pipe_seen.get(h) != Some(rev))
            .collect()
    });
    let fresh: Vec<(u32, u64, GasCell)> = moved
        .into_iter()
        .filter_map(|(h, rev)| Some((h, rev, cell_of_mixture(&load(MixRef::from_id(h)?)?))))
        .collect();
    with_mixes(|m| {
        fresh
            .into_iter()
            .map(|(h, rev, cell)| {
                m.pipe_seen.insert(h, rev);
                (h, cell)
            })
            .collect()
    })
}

thread_local! {
    /// Wakes found when a watch was registered (its starting state), delivered with the next drain.
    static HELD: RefCell<Vec<Wake>> = const { RefCell::new(Vec::new()) };
}

/// The reactor's gas wakes since the last call.
pub fn reactor_wakes(out: &mut Vec<Wake>) {
    out.extend(take_wakes());
}

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
    fn each_watch_hears_its_own_mixture() {
        with_world(|_| Ok(())).unwrap();
        let (a, b) = (alloc(tank(10.0)).unwrap(), alloc(tank(10.0)).unwrap());
        let (ra, rb) = (MixRef::Main(a), MixRef::Main(b));
        let changed = |r: MixRef, ch: vg_core::channel::ChannelId| Cond::Changed {
            cell: r.id(),
            mask: ch.bit(),
        };
        watch(7, Lane::Normal, &changed(ra, gas_ch::PRESSURE)).unwrap();
        let (port, nine) = watch(9, Lane::Normal, &changed(ra, gas_ch::PRESSURE)).unwrap();
        watch(11, Lane::Normal, &changed(rb, gas_ch::TEMPERATURE)).unwrap();
        let mut out = Vec::new();
        reactor_wakes(&mut out);
        out.clear();
        let before = load(ra).unwrap();
        store(ra, &before, &tank(20.0));
        reactor_wakes(&mut out);
        let mut heard: Vec<u32> = out.iter().map(|w| w.subscriber).collect();
        heard.sort_unstable();
        assert_eq!(heard, vec![7, 9], "{out:?}");
        assert!(out.iter().all(|w| w.source == ra.id()), "{out:?}");
        unwatch(port, nine);
        out.clear();
        let before = load(ra).unwrap();
        store(ra, &before, &tank(30.0));
        reactor_wakes(&mut out);
        let heard: Vec<u32> = out.iter().map(|w| w.subscriber).collect();
        assert_eq!(heard, vec![7], "only watch 7 is left: {out:?}");
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

    /// A pipe region changed outside `store` (a device step's write-back: a heat exchanger levelling two loops changes only the
    /// temperature) still reaches a temperature watch on it: the drain reads the region's revision, not a report from the writer.
    #[test]
    fn a_temperature_watch_hears_a_pipe_region_written_by_the_world() {
        use vg_gas::pipes::PipeGas;
        with_world(|_| Ok(())).unwrap();
        let node = with_world(|w| {
            let node = w.entities_mut().bind().unwrap();
            let mut gas = PipeGas::default();
            gas.moles[vg_gas::gas::ids::GAS_OXYGEN] = 50.0;
            gas.energy = 50.0 * 20.0 * 293.0;
            w.edit_network::<Pipes>(move |host| {
                let _ = host.bind_node(node, 0, 0, 100.0);
                let region = host.region_of(node).expect("bound");
                let _ = host.set_payload(region, gas);
            })
            .map_err(|e| eyre!("{e}"))?;
            w.commit_network::<Pipes>();
            Ok(node)
        })
        .unwrap();
        let r = with_world(|w| Ok(crate::pipes::port_mixture(w, node.bits())))
            .unwrap()
            .expect("a region");
        let before = load(r).unwrap();
        let cond = Cond::Changed {
            cell: r.id(),
            mask: gas_ch::TEMPERATURE.bit(),
        };
        watch(301, Lane::Normal, &cond).unwrap();
        let mut out = Vec::new();
        reactor_wakes(&mut out);
        out.clear();
        reactor_wakes(&mut out);
        assert!(out.is_empty(), "nothing changed yet");
        // The device law's write-back: the payload, on the world, with no `store`.
        with_world(|w| {
            w.edit_network::<Pipes>(move |host| {
                let region = host.region_of(node).expect("bound");
                if let Ok(p) = host.payload_mut(region) {
                    p.energy *= 1.2;
                }
            })
            .map_err(|e| eyre!("{e}"))?;
            w.commit_network::<Pipes>();
            Ok(())
        })
        .unwrap();
        let after = load(r).unwrap();
        assert!(
            after.get_temperature() > before.get_temperature() + 10.0,
            "the write-back heated the region"
        );
        reactor_wakes(&mut out);
        assert_eq!(
            out.len(),
            1,
            "the temperature watch heard the region: {out:?}"
        );
        assert_eq!(out[0].subscriber, 301);
        assert_eq!(out[0].source, r.id());
    }

    #[test]
    fn a_freed_main_slot_reused_by_a_new_mixture_refuses_the_old_handle() {
        with_world(|_| Ok(())).unwrap();
        let a = alloc(tank(5.0)).unwrap();
        let stamped = generation(MixRef::Main(a));
        assert_eq!(check_generation(MixRef::Main(a), Some(stamped)), Ok(()));
        free(a);
        let b = alloc(tank(9.0)).unwrap();
        assert_eq!(a, b, "the free slot is handed out again");
        // The stale datum still holds `a` and `stamped`; the new mixture is not its to read.
        let refused = check_generation(MixRef::Main(a), Some(stamped)).unwrap_err();
        assert_eq!(refused.held, Some(stamped));
        assert_ne!(refused.current, stamped);
        // The new owner is stamped with the slot's current generation and passes.
        assert_eq!(
            check_generation(MixRef::Main(b), Some(generation(MixRef::Main(b)))),
            Ok(())
        );
        // A datum with no generation never passes.
        assert!(check_generation(MixRef::Main(b), None).is_err());
        free(b);
    }

    #[test]
    fn a_turf_cell_given_a_new_owner_refuses_the_old_turfs_handle() {
        let cell = 4_000_001;
        let stamped = bump_turf_generation(cell);
        assert_eq!(check_generation(MixRef::Turf(cell), Some(stamped)), Ok(()));
        // ChangeTurf: the successor's air takes the cell over.
        let successor = bump_turf_generation(cell);
        assert_ne!(successor, stamped);
        assert!(check_generation(MixRef::Turf(cell), Some(stamped)).is_err());
        assert_eq!(
            check_generation(MixRef::Turf(cell), Some(successor)),
            Ok(())
        );
        // Unregistering the cell also strands every earlier datum.
        bump_turf_generation(cell);
        assert!(check_generation(MixRef::Turf(cell), Some(successor)).is_err());
    }

    #[test]
    fn a_retired_pipe_slot_reused_by_another_region_refuses_the_old_handle() {
        use super::super::REGION_SLOTS;
        let (slot, stamped) = REGION_SLOTS.with(|s| {
            let slot = s.borrow_mut().slot_for(9_000_001);
            (slot, s.borrow().generation_of(slot))
        });
        assert_eq!(check_generation(MixRef::Pipe(slot), Some(stamped)), Ok(()));
        // The region is rebuilt: its slot is retired and handed to another region.
        let reused = REGION_SLOTS.with(|s| {
            s.borrow_mut().retire(9_000_001);
            s.borrow_mut().slot_for(9_000_002)
        });
        assert_eq!(reused, slot);
        assert!(check_generation(MixRef::Pipe(slot), Some(stamped)).is_err());
        let now = generation(MixRef::Pipe(slot));
        assert_eq!(check_generation(MixRef::Pipe(slot), Some(now)), Ok(()));
        REGION_SLOTS.with(|s| s.borrow_mut().retire(9_000_002));
    }

    #[test]
    fn a_queued_id_and_generation_pair_is_refused_once_the_slot_moves_on() {
        with_world(|_| Ok(())).unwrap();
        let a = alloc(tank(5.0)).unwrap();
        let stamped = generation(MixRef::Main(a));
        #[allow(clippy::cast_precision_loss)]
        let id = a as f32;
        assert_eq!(checked_ref(id, Some(stamped)).unwrap(), MixRef::Main(a));
        assert!(checked_ref(id, None).is_err(), "no generation never passes");
        assert!(checked_ref(-1.0, Some(stamped)).is_err());
        assert!(checked_ref(1.5, Some(stamped)).is_err());
        free(a);
        let b = alloc(tank(9.0)).unwrap();
        assert_eq!(a, b);
        let err = checked_ref(id, Some(stamped)).unwrap_err().to_string();
        assert!(err.contains("stale"), "{err}");
        free(b);
    }

    #[test]
    fn generations_wrap_inside_what_a_datum_can_hold_exactly() {
        assert_eq!(next_generation(0), 1);
        assert_eq!(next_generation(GENERATION_MASK), 0);
        assert!(f64::from(GENERATION_MASK as f32) == f64::from(GENERATION_MASK));
    }
}
