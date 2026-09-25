//! [`HeatWorld`]: the main-thread host of the heat domain. It owns the
//! [`Sim`] (the solid field, the bodies, the ledger and their watches), hands
//! out body handles, turns DM's API calls into commands, and paces frames.
//!
//! One frame is [`HeatConfig::dt`] simulated seconds. [`HeatWorld::tick`]
//! feeds the game time DM reports through [`vg_core::law::Pacer`] (Core A's
//! shared fixed-dt accumulator/idle-skip/backlog-cap, `rust_architecture.md`
//! §4.3) and dispatches a frame when a full step is due (never waiting: a
//! still-running frame just keeps the backlog, capped at
//! [`MAX_BACKLOG_FRAMES`]).
//!
//! Frame order: the field (conduction and radiation), the solid ↔ gas
//! coupling, the bodies, the ledger mirror, then the watches.

use std::collections::HashMap;
use std::sync::Arc;

use vg_core::channel::{Quantity, Unit};
use vg_core::field::{FieldConfig, FieldKey, Geom, add_field};
use vg_core::grid::{Dir, Face, GridDims};
use vg_core::outbox::{Event, EventKind, Lane, Subscriber, Wake, WatchId};
use vg_core::owner::DomainKey;
use vg_core::sim::{BuildError, Sim, SimBuilder, SimConfig, WatchKey};
use vg_core::watch::{Cmp, Cond, Edge, Level, SetEntry, WatchError};

use crate::body::{self, Bodies, Body, BodyCmd, body_ch};
use crate::consts::{
    BODY_GENERATION_BITS, BODY_LEVELS, DEFAULT_EMISSIVITY, HEAT_CAPACITY_VACUUM, HEAT_DT,
    MAX_BACKLOG_FRAMES, MAX_BODIES, MAX_WATCHES, TCMB,
};
use crate::couple::{self, GasExchange, HeatLedger, ledger};
use crate::solid::{SolidCell, SolidCmd, SolidHeat, flags, solid_ch};

/// Construction options.
#[derive(Clone, Copy, Debug)]
pub struct HeatConfig {
    pub dims: GridDims,
    /// Simulated seconds per frame.
    pub dt: f32,
    /// Frame pool threads.
    pub threads: usize,
    pub max_substeps: u32,
}

impl HeatConfig {
    #[must_use]
    pub fn new(dims: GridDims) -> Self {
        Self {
            dims,
            dt: HEAT_DT,
            threads: 2,
            max_substeps: 16,
        }
    }
}

/// What kind of turf a cell is.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CellKind {
    /// An ordinary solid (wall, floor): conducts, couples to its air.
    Solid,
    /// Space: a reservoir that neighbours radiate into.
    Space,
    /// A planet's surface: a reservoir at its temperature that neighbours
    /// conduct into.
    Planet,
}

/// A turf's thermal values, as DM sends them.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CellSpec {
    pub kind: CellKind,
    /// J/K.
    pub capacity: f32,
    /// DM `thermal_conductivity`.
    pub conductivity: f32,
    pub emissivity: f32,
    /// Used for a new cell (an existing one keeps its temperature).
    pub temperature: f32,
    /// The turf has air to couple to.
    pub air: bool,
}

impl CellSpec {
    #[must_use]
    pub const fn solid(capacity: f32, conductivity: f32, temperature: f32) -> Self {
        Self {
            kind: CellKind::Solid,
            capacity,
            conductivity,
            emissivity: DEFAULT_EMISSIVITY,
            temperature,
            air: false,
        }
    }

    #[must_use]
    pub const fn space() -> Self {
        Self {
            kind: CellKind::Space,
            capacity: HEAT_CAPACITY_VACUUM,
            conductivity: 0.0,
            emissivity: 0.0,
            temperature: TCMB,
            air: false,
        }
    }

    #[must_use]
    pub const fn with_air(mut self) -> Self {
        self.air = true;
        self
    }

    #[must_use]
    pub const fn with_emissivity(mut self, e: f32) -> Self {
        self.emissivity = e;
        self
    }
}

/// A body handle: `slot | generation << 16`, exact as an `f32`.
pub type BodyHandle = u32;

fn handle(slot: u32, generation: u8) -> BodyHandle {
    slot | (u32::from(generation) << 16)
}

fn split(h: BodyHandle) -> (u32, u8) {
    #[allow(clippy::cast_possible_truncation)]
    (h & (MAX_BODIES - 1), (h >> 16) as u8)
}

/// What a watch is on.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum WatchTarget {
    Cell(u32),
    Body(BodyHandle),
}

/// A temperature watch.
#[derive(Clone, Debug, PartialEq)]
pub enum WatchCond {
    /// Fires on entering `T >= limit` (and leaving, if `both`).
    Above { limit: f32, both: bool },
    /// Fires on entering `T <= limit` (and leaving, if `both`).
    Below { limit: f32, both: bool },
    /// Fires when the band (the number of levels `<= T`) changes; always
    /// once at registration.
    Band(Vec<f32>),
    /// A `ThresholdSet`: entries are added with [`HeatWorld::set_add`].
    Set,
}

/// Cumulative energy books, for conservation checks and diagnostics.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Totals {
    /// Energy in non-reservoir solid cells.
    pub cells: f64,
    /// Energy in live bodies (analytic ones: see [`Body::books_energy`]).
    pub bodies: f64,
    /// The [`ledger`] entries.
    pub ledger: [f64; ledger::LEN as usize],
}

impl Totals {
    /// Stores plus everything the ledger booked (energy put into gases,
    /// reservoirs, released baselines), minus what power sources added.
    /// Constant under the physics; DM commands change it by what they add.
    #[must_use]
    pub fn conserved(&self) -> f64 {
        let l = &self.ledger;
        self.cells
            + self.bodies
            + l[ledger::FIELD_RESERVOIRS as usize]
            + l[ledger::GAS_RESERVOIRS as usize]
            + l[ledger::GAS as usize]
            + l[ledger::RELEASED as usize]
            + l[ledger::LOST as usize]
            + l[ledger::BODY_RESERVOIRS as usize]
            - l[ledger::POWER as usize]
    }
}

/// Per-slot host bookkeeping.
#[derive(Clone, Debug, Default)]
struct Slot {
    generation: u8,
    /// DM holds a valid handle.
    live: bool,
    /// Released (by DM or at equilibrium) and not yet confirmed by the
    /// worker; the slot is not reused until it is.
    releasing: bool,
    /// Watches on this body, with the levels each contributes.
    watches: Vec<(u32, Vec<f32>)>,
}

/// Host-side watch record.
#[derive(Clone, Debug)]
struct WatchRec {
    target: WatchTarget,
    /// The sim's own watch id (its table index and generation), used to
    /// call back into `self.sim.watches(...)`. Never exposed to DM: DM only
    /// ever sees the host-allocated handle this record is keyed under.
    id: WatchId,
    set_levels: Vec<(u32, f32)>,
    /// This record's host watch slot, freed (and its generation bumped) on
    /// `unwatch`.
    slot: u32,
}

/// The heat domain's host.
pub struct HeatWorld {
    sim: Sim,
    field: FieldKey<SolidHeat>,
    bodies: DomainKey<Bodies>,
    ledger: DomainKey<HeatLedger>,
    cell_watch: WatchKey<SolidHeat>,
    body_watch: WatchKey<Bodies>,
    dims: GridDims,
    dt: f32,
    /// The fixed-dt accumulator/idle-skip/backlog-cap Core A's driver
    /// generalized (`rust_architecture.md` §4.3): replaces this type's own
    /// `accum`/[`MAX_BACKLOG_FRAMES`] arithmetic.
    pacer: vg_core::law::Pacer,
    /// Steps [`Pacer::advance`] has already counted as due but this host
    /// hasn't dispatched yet (at most one frame is ever in flight at a
    /// time, so a call that reports 2+ due steps still only starts one;
    /// the rest carry here instead of being re-derived from elapsed time
    /// on a later call, which would double-count it).
    pending_frames: u32,
    slots: Vec<Slot>,
    free: Vec<u32>,
    next_slot: u32,
    watches: HashMap<u32, WatchRec>,
    /// This host's own generation per watch slot (`world.rs`'s handle
    /// allocator, parallel to `slots`/`free`/`next_slot` for bodies).
    watch_generations: Vec<u8>,
    watch_free: Vec<u32>,
    next_watch_slot: u32,
    /// Sim watch-table index -> host handle, so a wake or event the sim
    /// reports (keyed by its own table index) can be re-keyed to the DM
    /// handle without a linear scan. One map per watch domain.
    cell_watch_owner: HashMap<u32, u32>,
    body_watch_owner: HashMap<u32, u32>,
    wakes: Vec<Wake>,
    events: Vec<Event>,
}

/// Allocates a host watch slot: the freed slot with the lowest index, or a
/// new one, exactly like [`HeatWorld::alloc_slot`] for bodies. Returns the
/// slot and its *current* (not yet bumped) generation.
fn alloc_watch_slot(free: &mut Vec<u32>, next: &mut u32, generations: &mut Vec<u8>) -> (u32, u8) {
    if let Some(slot) = free.pop() {
        (slot, generations[slot as usize])
    } else {
        let slot = *next;
        *next += 1;
        generations.push(0);
        (slot, 0)
    }
}

/// Packs a host watch handle: `(slot * 2 + domain) | (generation << 16)`,
/// mirroring [`handle`]/[`BodyHandle`]'s body-handle scheme so it stays
/// exact as an f32 (`consts::MAX_WATCHES`, `consts::WATCH_GENERATION_BITS`).
/// Unlike the old `index * 16 + generation & 15` scheme this packed the
/// *sim's* watch-table generation into only 4 bits, this handle is host-
/// allocated: a value only repeats after `2^WATCH_GENERATION_BITS` reuses
/// of the same host slot, each requiring an explicit `unwatch()` first, so
/// a DM handle can never alias a watch it wasn't given.
fn watch_pack(slot: u32, generation: u8, body: bool) -> u32 {
    (slot * 2 + u32::from(body)) | (u32::from(generation) << 16)
}

impl HeatWorld {
    /// Builds the heat sim over `config.dims` with `gas` as the gas side.
    ///
    /// # Errors
    /// If the sim fails to build (a bad channel table, the frame pool).
    pub fn new(config: HeatConfig, gas: Arc<dyn GasExchange>) -> Result<Self, BuildError> {
        let mut b = SimBuilder::new(SimConfig {
            threads: config.threads.max(1),
            seed: 0x4845_4154,
            record: false,
            ..SimConfig::default()
        });
        let field = add_field::<SolidHeat>(
            &mut b,
            config.dims,
            FieldConfig {
                dt: config.dt,
                max_substeps: config.max_substeps,
            },
            None,
        );
        let ledger = couple::add_ledger(&mut b);
        couple::add_gas_coupling(&mut b, field, ledger, Arc::clone(&gas), config.dt);
        let bodies = body::add_bodies(&mut b, field, ledger, gas, config.dt);
        couple::add_field_ledger_mirror(&mut b, field, ledger);
        let cell_watch = b.add_watches(field.cells);
        let body_watch = b.add_watches(bodies);
        let sim = b.build()?;
        Ok(Self {
            sim,
            field,
            bodies,
            ledger,
            cell_watch,
            body_watch,
            dims: config.dims,
            dt: config.dt,
            #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
            pacer: vg_core::law::Pacer::new(
                vg_core::units::Seconds(f64::from(config.dt)),
                MAX_BACKLOG_FRAMES as u32,
            ),
            pending_frames: 0,
            slots: vec![Slot::default(); MAX_BODIES as usize],
            free: Vec::new(),
            next_slot: 0,
            watches: HashMap::new(),
            watch_generations: Vec::new(),
            watch_free: Vec::new(),
            next_watch_slot: 0,
            cell_watch_owner: HashMap::new(),
            body_watch_owner: HashMap::new(),
            wakes: Vec::new(),
            events: Vec::new(),
        })
    }

    #[must_use]
    pub const fn dims(&self) -> GridDims {
        self.dims
    }

    /// Simulated seconds of the frames dispatched so far.
    #[must_use]
    #[allow(clippy::cast_precision_loss)]
    pub fn now(&self) -> f64 {
        // Frames are numbered from 0 and each ends `dt` after it starts;
        // this is the end of the last dispatched frame (settle and replay
        // dispatch frames too).
        self.sim.metrics().frames_dispatched as f64 * f64::from(self.dt)
    }

    #[must_use]
    pub fn sim(&self) -> &Sim {
        &self.sim
    }

    // ------------------------------------------------------------- cells

    fn cell_count(&self) -> u32 {
        self.dims.layer_len() * self.dims.max_z()
    }

    /// Registers or updates a turf. A cell that already exists keeps its
    /// temperature across a capacity change (a new wall material, a turf
    /// change); a new one starts at `spec.temperature`.
    pub fn set_cell(&mut self, cell: u32, spec: CellSpec) -> bool {
        if cell >= self.cell_count() {
            return false;
        }
        let reservoir = spec.kind != CellKind::Solid;
        let capacity = if reservoir {
            spec.capacity.max(1.0)
        } else {
            spec.capacity
        };
        if capacity.is_nan() || capacity <= 0.0 || !capacity.is_finite() {
            self.clear_cell(cell);
            return true;
        }
        let mut f = match spec.kind {
            CellKind::Solid => 0,
            CellKind::Space => flags::SPACE,
            CellKind::Planet => flags::PLANET,
        };
        if spec.air {
            f |= flags::AIR;
        }
        let old = self
            .sim
            .port(self.field.geometry)
            .read(cell)
            .unwrap_or_default();
        let geom = Geom {
            capacity,
            // A solid deck separates z-levels (as superconduct.rs did):
            // cross-z heat needs an explicit conductor.
            blocked: Dir::NONE.with(Face::Up).with(Face::Down),
            reservoir,
        };
        let ports = &mut self.sim;
        if old != geom {
            let _ = ports.port(self.field.geometry).put(cell, geom);
        }
        let cells = ports.port(self.field.cells);
        if old.is_node() && !old.reservoir && !reservoir {
            let current = cells.read(cell).unwrap_or_default();
            if current.conductivity != spec.conductivity
                || current.emissivity != spec.emissivity
                || current.flags != f
            {
                let _ = cells.submit(
                    cell,
                    SolidCmd::Props {
                        conductivity: spec.conductivity,
                        emissivity: spec.emissivity,
                        flags: f,
                    },
                );
            }
            if old.capacity != capacity {
                let _ = cells.submit(
                    cell,
                    SolidCmd::Rescale {
                        from: old.capacity,
                        to: capacity,
                    },
                );
            }
        } else {
            let t = if spec.kind == CellKind::Space {
                TCMB
            } else {
                spec.temperature.max(TCMB)
            };
            let _ = cells.put(
                cell,
                SolidCell::at(capacity, t, spec.conductivity.max(0.0), spec.emissivity, f),
            );
        }
        true
    }

    /// Removes a turf from the field (its heat leaves with it).
    pub fn clear_cell(&mut self, cell: u32) {
        if cell >= self.cell_count() {
            return;
        }
        let old = self
            .sim
            .port(self.field.geometry)
            .read(cell)
            .unwrap_or_default();
        if old != Geom::default() {
            let _ = self
                .sim
                .port(self.field.geometry)
                .put(cell, Geom::default());
            let _ = self
                .sim
                .port(self.field.cells)
                .put(cell, SolidCell::default());
        }
    }

    /// The solid temperature of a turf, `None` if it is not in the field.
    pub fn cell_temperature(&mut self, cell: u32) -> Option<f32> {
        let g = self.sim.port(self.field.geometry).read(cell)?;
        if !g.is_node() {
            return None;
        }
        let c = self.sim.port(self.field.cells).read(cell)?;
        Some(if g.reservoir {
            c.temperature
        } else {
            c.temperature_in(g.capacity)
        })
    }

    /// Heat capacity, conductivity and emissivity of a turf.
    pub fn cell_properties(&mut self, cell: u32) -> Option<(f32, f32, f32)> {
        let g = self.sim.port(self.field.geometry).read(cell)?;
        let c = self.sim.port(self.field.cells).read(cell)?;
        g.is_node()
            .then_some((g.capacity, c.conductivity, c.emissivity))
    }

    /// Adds heat to a turf's solid (a reservoir ignores it). Returns whether
    /// the turf took it.
    pub fn add_cell_heat(&mut self, cell: u32, joules: f32) -> bool {
        let Some(g) = self.sim.port(self.field.geometry).read(cell) else {
            return false;
        };
        if !g.is_node() || g.reservoir || !joules.is_finite() {
            return false;
        }
        self.sim
            .port(self.field.cells)
            .submit(cell, SolidCmd::Add(joules))
            .is_ok()
    }

    /// Sets a turf's solid temperature (DM authority).
    pub fn set_cell_temperature(&mut self, cell: u32, temperature: f32) -> bool {
        let Some(g) = self.sim.port(self.field.geometry).read(cell) else {
            return false;
        };
        if !g.is_node() || !temperature.is_finite() {
            return false;
        }
        self.sim
            .port(self.field.cells)
            .submit(
                cell,
                SolidCmd::Set {
                    temperature,
                    capacity: g.capacity,
                },
            )
            .is_ok()
    }

    // ------------------------------------------------------------ bodies

    /// Creates a body; `None` when every slot is taken.
    pub fn create_body(&mut self, body: Body) -> Option<BodyHandle> {
        if body.capacity.is_nan() || body.capacity <= 0.0 {
            return None;
        }
        let slot = match self.free.pop() {
            Some(s) => s,
            None if self.next_slot < MAX_BODIES => {
                self.next_slot += 1;
                self.next_slot - 1
            }
            None => return None,
        };
        let rec = &mut self.slots[slot as usize];
        rec.generation = rec.generation.wrapping_add(1) & ((1 << BODY_GENERATION_BITS) - 1) as u8;
        rec.live = true;
        rec.releasing = false;
        rec.watches.clear();
        let generation = rec.generation;
        let _ = self
            .sim
            .port(self.bodies)
            .put(slot, body.with_generation(generation));
        Some(handle(slot, generation))
    }

    fn live_slot(&self, h: BodyHandle) -> Option<u32> {
        let (slot, generation) = split(h);
        let rec = self.slots.get(slot as usize)?;
        (rec.live && rec.generation == generation).then_some(slot)
    }

    /// A coupling target as DM names it, with a body's packed handle
    /// (slot | generation << 16) resolved to the slot the bodies store
    /// indexes. A dead or stale handle couples to nothing.
    #[must_use]
    pub fn resolve_target(&self, target: body::Target) -> body::Target {
        match target {
            body::Target::Body(h) => self.live_slot(h).map_or(body::Target::None, body::Target::Body),
            other => other,
        }
    }

    /// Whether `h` names a live body.
    #[must_use]
    pub fn is_live(&self, h: BodyHandle) -> bool {
        self.live_slot(h).is_some()
    }

    /// The body as DM sees it now.
    pub fn body(&mut self, h: BodyHandle) -> Option<Body> {
        let slot = self.live_slot(h)?;
        let b = self.sim.port(self.bodies).read(slot)?;
        b.is_live().then_some(b)
    }

    /// A body's temperature now (the analytic model is evaluated).
    pub fn body_temperature(&mut self, h: BodyHandle) -> Option<f32> {
        let now = self.now();
        self.body(h).map(|b| b.temperature_at(now))
    }

    /// Sends a command to a body.
    pub fn body_command(&mut self, h: BodyHandle, cmd: BodyCmd) -> bool {
        let Some(slot) = self.live_slot(h) else {
            return false;
        };
        if matches!(cmd, BodyCmd::Release) {
            self.release_body(h);
            return true;
        }
        self.sim.port(self.bodies).submit(slot, cmd).is_ok()
    }

    /// Releases a body: its excess heat goes to its environment at the next
    /// frame, and the handle is dead at once.
    pub fn release_body(&mut self, h: BodyHandle) {
        let Some(slot) = self.live_slot(h) else {
            return;
        };
        let _ = self.sim.port(self.bodies).submit(slot, BodyCmd::Release);
        self.retire(slot);
    }

    /// Marks a slot dead for DM and drops its watches.
    fn retire(&mut self, slot: u32) {
        let watches = {
            let rec = &mut self.slots[slot as usize];
            rec.live = false;
            rec.releasing = true;
            std::mem::take(&mut rec.watches)
        };
        for (w, _) in watches {
            let _ = self.unwatch(w);
        }
    }

    // ----------------------------------------------------------- watches

    /// Registers a temperature watch. Returns the DM watch handle.
    ///
    /// # Errors
    /// A dead body, a cell outside the grid, or an invalid condition.
    pub fn watch(
        &mut self,
        target: WatchTarget,
        subscriber: Subscriber,
        lane: Lane,
        cond: &WatchCond,
    ) -> Result<u32, String> {
        let (cell, body) = match target {
            WatchTarget::Cell(c) => (c, false),
            WatchTarget::Body(h) => (self.live_slot(h).ok_or("dead body")?, true),
        };
        let ch = if body {
            body_ch::TEMPERATURE
        } else {
            solid_ch::TEMPERATURE
        };
        let k = |v: f32| Quantity::new(v, Unit::Kelvin);
        let (c, levels) = match cond {
            WatchCond::Above { limit, both } => {
                let mut level = Level::above(ch, k(*limit));
                if *both {
                    level = level.both_edges();
                }
                (Cond::Threshold { cell, level }, vec![*limit])
            }
            WatchCond::Below { limit, both } => {
                let mut level = Level::below(ch, k(*limit));
                if *both {
                    level = level.both_edges();
                }
                (Cond::Threshold { cell, level }, vec![*limit])
            }
            WatchCond::Band(levels) => (
                Cond::Band {
                    cell,
                    ch,
                    unit: Unit::Kelvin,
                    levels: levels.clone(),
                    hysteresis: None,
                },
                levels.clone(),
            ),
            WatchCond::Set => (Cond::ThresholdSet { cell, ch }, Vec::new()),
        };
        let id = if body {
            self.sim
                .watches(self.body_watch)
                .watch(subscriber, lane, &c)
        } else {
            self.sim
                .watches(self.cell_watch)
                .watch(subscriber, lane, &c)
        }
        .map_err(|e: WatchError| format!("{e:?}"))?;
        if self.watch_free.is_empty() && self.next_watch_slot >= MAX_WATCHES {
            // Undo the sim-side registration: don't leak a watch we can't
            // hand a host handle back for.
            if body {
                let _ = self.sim.watches(self.body_watch).unwatch(id);
            } else {
                let _ = self.sim.watches(self.cell_watch).unwatch(id);
            }
            return Err("out of watch slots".to_owned());
        }
        let (slot, generation) = alloc_watch_slot(
            &mut self.watch_free,
            &mut self.next_watch_slot,
            &mut self.watch_generations,
        );
        let wh = watch_pack(slot, generation, body);
        self.watches.insert(
            wh,
            WatchRec {
                target,
                id,
                set_levels: Vec::new(),
                slot,
            },
        );
        if body {
            self.body_watch_owner.insert(id.index, wh);
            self.slots[cell as usize].watches.push((wh, levels));
            self.push_levels(cell);
        } else {
            self.cell_watch_owner.insert(id.index, wh);
        }
        Ok(wh)
    }

    /// Adds (or replaces, by payload) an entry of a `Set` watch.
    ///
    /// # Errors
    /// A stale watch, or not a set.
    pub fn set_add(
        &mut self,
        watch: u32,
        payload: u32,
        generation: u32,
        cmp: Cmp,
        limit: f32,
        both: bool,
    ) -> Result<(), String> {
        let rec = self.watches.get_mut(&watch).ok_or("stale watch")?;
        let entry = SetEntry {
            payload,
            generation,
            cmp,
            limit: Quantity::new(limit, Unit::Kelvin),
            hysteresis: None,
            edge: if both { Edge::Both } else { Edge::Enter },
        };
        let id = rec.id;
        let body = watch & 1 == 1;
        rec.set_levels.retain(|e| e.0 != payload);
        rec.set_levels.push((payload, limit));
        let target = rec.target;
        if body {
            self.sim.watches(self.body_watch).add_entry(id, entry)
        } else {
            self.sim.watches(self.cell_watch).add_entry(id, entry)
        }
        .map_err(|e| format!("{e:?}"))?;
        self.refresh_set_levels(watch, target);
        Ok(())
    }

    /// Removes an entry of a `Set` watch.
    ///
    /// # Errors
    /// A stale watch or payload.
    pub fn set_remove(&mut self, watch: u32, payload: u32) -> Result<(), String> {
        let rec = self.watches.get_mut(&watch).ok_or("stale watch")?;
        rec.set_levels.retain(|e| e.0 != payload);
        let (id, target) = (rec.id, rec.target);
        if watch & 1 == 1 {
            self.sim.watches(self.body_watch).remove_entry(id, payload)
        } else {
            self.sim.watches(self.cell_watch).remove_entry(id, payload)
        }
        .map_err(|e| format!("{e:?}"))?;
        self.refresh_set_levels(watch, target);
        Ok(())
    }

    fn refresh_set_levels(&mut self, watch: u32, target: WatchTarget) {
        let WatchTarget::Body(h) = target else {
            return;
        };
        let Some(slot) = self.live_slot(h) else {
            return;
        };
        let levels: Vec<f32> = self.watches[&watch]
            .set_levels
            .iter()
            .map(|e| e.1)
            .collect();
        if let Some(w) = self.slots[slot as usize]
            .watches
            .iter_mut()
            .find(|w| w.0 == watch)
        {
            w.1 = levels;
        }
        self.push_levels(slot);
    }

    /// Removes a watch.
    ///
    /// # Errors
    /// A stale watch.
    pub fn unwatch(&mut self, watch: u32) -> Result<(), String> {
        let rec = self.watches.remove(&watch).ok_or("stale watch")?;
        let body = watch & 1 == 1;
        if body {
            self.sim.watches(self.body_watch).unwatch(rec.id)
        } else {
            self.sim.watches(self.cell_watch).unwatch(rec.id)
        }
        .map_err(|e| format!("{e:?}"))?;
        // Free the host slot (bumping its generation) and the reverse
        // sim-index -> handle mapping, so neither a repacked handle nor a
        // late wake/event for the old sim id can alias this watch.
        self.watch_generations[rec.slot as usize] =
            self.watch_generations[rec.slot as usize].wrapping_add(1);
        self.watch_free.push(rec.slot);
        if body {
            self.body_watch_owner.remove(&rec.id.index);
        } else {
            self.cell_watch_owner.remove(&rec.id.index);
        }
        if let WatchTarget::Body(h) = rec.target {
            let (slot, _) = split(h);
            let s = &mut self.slots[slot as usize];
            s.watches.retain(|w| w.0 != watch);
            if s.live {
                self.push_levels(slot);
            }
        }
        Ok(())
    }

    /// Sends a body the watched levels nearest its temperature, so its
    /// analytic model can schedule the crossings.
    fn push_levels(&mut self, slot: u32) {
        let now = self.now();
        let t = self
            .sim
            .port(self.bodies)
            .read(slot)
            .map_or(0.0, |b| b.temperature_at(now));
        let mut all: Vec<f32> = self.slots[slot as usize]
            .watches
            .iter()
            .flat_map(|w| w.1.iter().copied())
            .filter(|l| l.is_finite())
            .collect();
        all.sort_by(|a, b| (a - t).abs().total_cmp(&(b - t).abs()));
        all.dedup();
        let mut levels = [f32::NAN; BODY_LEVELS];
        for (o, l) in levels.iter_mut().zip(all) {
            *o = l;
        }
        let _ = self
            .sim
            .port(self.bodies)
            .submit(slot, BodyCmd::Levels(levels));
    }

    // -------------------------------------------------------------- tick

    /// One DM tick: reclaim a finished frame, collect its wakes and events,
    /// retire released bodies, and dispatch the next frame if `elapsed`
    /// seconds of game time make one due. Returns whether a frame started.
    ///
    /// At most one frame is ever in flight (one `dispatch_frame()` call per
    /// `tick()`), so a call that reports more than one step now due (a
    /// backlog) carries the rest in `pending_frames` for later calls
    /// instead of asking [`Pacer::advance`] again, which would double-count
    /// the elapsed time already spent on this call's steps.
    pub fn tick(&mut self, elapsed: f32) -> bool {
        self.sim.begin_tick();
        self.collect();
        self.pending_frames += self
            .pacer
            .advance(vg_core::units::Seconds(f64::from(elapsed)));
        if self.pending_frames > 0 && self.sim.dispatch_frame() {
            self.pending_frames -= 1;
            return true;
        }
        false
    }

    fn collect(&mut self) {
        let out = self.sim.drain(self.field.cells);
        for w in out.wakes() {
            // Re-key by the host handle currently owning this sim table
            // slot. A wake for a watch already `unwatch()`-ed (no owner
            // left) is dropped rather than aliased onto whatever new watch
            // has since reused the slot.
            if let Some(&wh) = self.cell_watch_owner.get(&w.watch.index) {
                let mut w = *w;
                w.watch = WatchId {
                    index: wh,
                    generation: 0,
                };
                self.wakes.push(w);
            }
        }
        let cell_events: Vec<Event> = out.events().to_vec();
        for e in cell_events {
            self.push_event(e, false);
        }
        let out = self.sim.drain(self.bodies);
        for w in out.wakes() {
            if let Some(&wh) = self.body_watch_owner.get(&w.watch.index) {
                let mut w = *w;
                w.watch = WatchId {
                    index: wh,
                    generation: 0,
                };
                self.wakes.push(w);
            }
        }
        for e in out.events() {
            if e.kind == body::SETTLED {
                // At equilibrium: release it now, after anything DM sent.
                let slot = e.key;
                if let Some(rec) = self.slots.get(slot as usize) {
                    if rec.live && u32::from(rec.generation) == e.generation {
                        self.release_body(handle(slot, rec.generation));
                    }
                }
            } else if e.kind == EventKind::Destroyed {
                let slot = e.key;
                let Some(rec) = self.slots.get(slot as usize) else {
                    continue;
                };
                #[allow(clippy::cast_possible_truncation)]
                if u32::from(rec.generation) == e.generation {
                    if rec.live {
                        self.retire(slot);
                    }
                    self.slots[slot as usize].releasing = false;
                    self.free.push(slot);
                }
            } else {
                self.push_event(*e, true);
            }
        }
    }

    /// Re-keys a `ThresholdCrossed` event by its DM watch handle, via the
    /// same sim-index -> handle owner map `collect()`'s wakes use. An event
    /// for a since-`unwatch()`-ed watch (no current owner) is dropped.
    fn push_event(&mut self, e: Event, body: bool) {
        let owner = if body {
            &self.body_watch_owner
        } else {
            &self.cell_watch_owner
        };
        if let Some(&key) = owner.get(&e.key) {
            self.events.push(Event { key, ..e });
        }
    }

    /// Takes the wakes collected so far, as `[subscriber, watch, reason,
    /// source]` quads (`watch` is the DM watch handle; `source` the cell or
    /// body slot).
    #[allow(clippy::cast_precision_loss)]
    pub fn take_wakes(&mut self, out: &mut Vec<f32>) {
        for w in self.wakes.drain(..) {
            out.extend_from_slice(&[
                w.subscriber as f32,
                w.watch.index as f32,
                w.reason as f32,
                (w.source & 0x00ff_ffff) as f32,
            ]);
        }
    }

    /// Wakes plus `ThresholdSet` crossings collected and not yet taken.
    #[must_use]
    pub fn pending_notices(&self) -> usize {
        self.wakes.len()
            + self
                .events
                .iter()
                .filter(|e| e.kind == EventKind::ThresholdCrossed)
                .count()
    }

    /// Takes the collected wakes as records.
    pub fn drain_wakes(&mut self) -> Vec<Wake> {
        std::mem::take(&mut self.wakes)
    }

    /// Takes the collected `ThresholdSet` crossings as `(watch handle,
    /// payload, entered, generation)`.
    pub fn drain_crossings(&mut self) -> Vec<(u32, u32, bool, u32)> {
        self.events
            .drain(..)
            .filter(|e| e.kind == EventKind::ThresholdCrossed)
            .map(|e| (e.key, e.extra, e.value > 0.5, e.generation))
            .collect()
    }

    /// Runs frames until every command is applied (tests, shutdown).
    pub fn settle(&mut self) {
        self.sim.settle();
        self.collect();
    }

    /// Runs `n` frames, waiting for each (tests).
    pub fn run_frames(&mut self, n: u32) {
        for _ in 0..n {
            self.sim.wait_for_frame();
            self.tick(self.dt);
            self.sim.wait_for_frame();
        }
        self.sim.wait_for_frame();
        self.sim.begin_tick();
        self.collect();
    }

    /// The energy books as of the pinned views.
    pub fn totals(&mut self) -> Totals {
        let geom = Arc::clone(self.sim.port(self.field.geometry).pinned());
        let cells = Arc::clone(self.sim.port(self.field.cells).pinned());
        let mut t = Totals::default();
        let layout = cells.store().layout();
        for chunk in 0..layout.chunk_count() {
            let Some(values) = cells.store().chunk(chunk) else {
                continue;
            };
            for (i, v) in values.iter().enumerate() {
                let Some(index) = layout.index_of(chunk, i) else {
                    continue;
                };
                let g = geom.get(index).unwrap_or_default();
                if g.is_node() && !g.reservoir {
                    t.cells += f64::from(v.energy);
                }
            }
        }
        let bodies = Arc::clone(self.sim.port(self.bodies).pinned());
        let layout = bodies.store().layout();
        for chunk in 0..layout.chunk_count() {
            if let Some(values) = bodies.store().chunk(chunk) {
                for b in values.iter().filter(|b| b.is_live()) {
                    t.bodies += b.books_energy();
                }
            }
        }
        let l = Arc::clone(self.sim.port(self.ledger).pinned());
        for (i, v) in t.ledger.iter_mut().enumerate() {
            *v = l.get(u32::try_from(i).unwrap_or(0)).unwrap_or(0.0);
        }
        t
    }

    /// Live bodies (DM-visible handles).
    #[must_use]
    pub fn live_bodies(&self) -> usize {
        self.slots.iter().filter(|s| s.live).count()
    }

    /// Diagnostics: (frames dispatched, frames completed, last frame µs,
    /// live bodies).
    #[must_use]
    pub fn diagnostics(&self) -> (u64, u64, u64, usize) {
        let m = self.sim.metrics();
        #[allow(clippy::cast_possible_truncation)]
        (
            m.frames_dispatched,
            m.frames_completed,
            m.last_frame.as_micros() as u64,
            self.live_bodies(),
        )
    }
}
