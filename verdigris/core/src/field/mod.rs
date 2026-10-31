//! The field framework (`simulation.md` §1, roadmap R6): per-cell state on
//! the grid, exchanged across open faces by a pluggable, conservative flux.
//!
//! A field is two [`Domain`]s and one worker resource:
//! - the **cells**: a domain `K` implementing [`FieldKind`]. Its value is
//!   the per-cell state (energy; moles and energy; ...) and its commands are
//!   the sources and sinks DM submits. `Put`/`Take` move whole cells in and
//!   out, and R5 made `Take` report exactly what it removed;
//! - the **geometry**: [`Geometry<K>`], one [`Geom`] per cell with the
//!   capacity (heat capacity, volume) and the reservoir flag. DM changes it
//!   with [`GeomCmd`]s, so geometry goes through the same commands,
//!   overlay, views and replay as everything else;
//! - the **blocked faces** come from the world's one [`Grid`], layer
//!   [`FieldKind::BLOCK`] (a door closing is one grid write, seen by every
//!   field on that layer). A field registered without a grid falls back to
//!   the per-cell [`Geom::blocked`], which the hosts that predate the grid
//!   still write; they move to the grid when they port
//!   (`rust_architecture.md` §8);
//! - [`FieldState<K>`]: active chunks, the reservoir ledger and statistics.
//!
//! [`add_field`] registers all three and a `field:<name>` frame task that
//! runs after the apply tasks and before the watch task, so R5 watches on
//! the cells domain (declared with [`channels!`](crate::channels)) see the
//! frame's result.
//!
//! # One step
//! 1. **Wake.** Every chunk of the cells or geometry store that is not the
//!    same allocation as at the end of the previous step was written by a
//!    command (or by another task) and wakes. No command list is needed: an
//!    untouched chunk is still shared with the last snapshot.
//! 2. **Sub-steps.** The largest [`FieldKind::stiffness`] over live edges
//!    gives `n = ceil(dt * faces * stiffness)` sub-steps (clamped to
//!    [`FieldConfig::max_substeps`]), the monotone bound of the explicit
//!    scheme.
//! 3. **Flux, then apply.** An edge is *live* when either end's chunk is
//!    active. Each chunk computes the flux of the live edges on its East,
//!    North and Up faces from the sub-step's starting snapshot, in parallel.
//!    Each cell then applies `-F` for its own edges and `+F` for the edges
//!    owned by its West, South and Down neighbours, in a fixed order, in
//!    parallel by chunk. Every flux is computed once and applied once with
//!    each sign: conservation holds by construction, and no sum depends on
//!    the thread count.
//! 4. **Sleep.** A chunk stays active only if one of its live edges was not
//!    [`settled`](FieldKind::settled) on the last sub-step (both ends
//!    wake, which is how activity spreads to a sleeping neighbour), or its
//!    [`local`](FieldKind::local) step asked to stay awake. Sleeping chunks
//!    are never written, so they stay shared with every published view.
//!
//! # Reservoirs and capacity
//! A cell with capacity 0 (or NaN) is not part of the field: it has no
//! edges, and whatever it holds stays put. A **reservoir** cell (space, a
//! planet's atmosphere) exchanges through its edges but is never changed by
//! them; what flows into reservoirs is added to [`FieldState::ledger`], so
//! `sum over non-reservoir cells + ledger` is constant (to rounding) apart
//! from commands.

pub mod kernel;
pub mod law;
pub mod toy;

use std::fmt;
use std::marker::PhantomData;
use std::sync::atomic::{AtomicBool, Ordering};

use rayon::prelude::*;

use crate::cow::{ChunkLayout, CowStore};
use crate::frame::{Res, Task};
use crate::grid::{BlockKind, CHUNK_EDGE, Dir, Face, Grid, GridDims};
use crate::owner::{Applied, Domain, DomainKey};
use crate::sim::SimBuilder;

/// The geometry of one field cell.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Geom {
    /// Heat capacity, volume, ...: intensive = amount / capacity. 0 means
    /// the cell is not part of the field.
    pub capacity: f32,
    /// Faces this cell blocks (a face is open only if neither side blocks
    /// it), for a field without a [`Grid`]; with one, the grid's layer is
    /// used as well.
    pub blocked: Dir,
    /// Exchanges but never changes (space, a planet's atmosphere).
    pub reservoir: bool,
}

impl Geom {
    #[must_use]
    pub const fn cell(capacity: f32) -> Self {
        Self {
            capacity,
            blocked: Dir::NONE,
            reservoir: false,
        }
    }

    #[must_use]
    pub const fn reservoir(capacity: f32) -> Self {
        Self {
            capacity,
            blocked: Dir::NONE,
            reservoir: true,
        }
    }

    /// Whether the cell takes part in the field.
    #[must_use]
    pub fn is_node(&self) -> bool {
        self.capacity > 0.0
    }

    /// `1 / capacity`, 0 for a reservoir.
    #[must_use]
    pub fn inv_capacity(&self) -> f32 {
        if self.reservoir {
            0.0
        } else {
            1.0 / self.capacity
        }
    }
}

/// A geometry command.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum GeomCmd {
    Capacity(f32),
    Blocked(Dir),
    Reservoir(bool),
}

/// The geometry domain of field `K`.
pub struct Geometry<K>(PhantomData<fn() -> K>);

impl<K: FieldKind> Domain for Geometry<K> {
    type Value = Geom;
    type Command = GeomCmd;
    const NAME: &'static str = K::GEOMETRY_NAME;

    fn apply(value: &mut Geom, cmd: &GeomCmd) -> Applied {
        match *cmd {
            GeomCmd::Capacity(c) => value.capacity = c,
            GeomCmd::Blocked(m) => value.blocked = Dir(m.0 & Dir::ALL.0),
            GeomCmd::Reservoir(r) => value.reservoir = r,
        }
        Applied::default()
    }
}

/// One side of an edge.
#[derive(Debug)]
pub struct Side<'a, V> {
    pub cell: &'a V,
    pub capacity: f32,
    /// `1 / capacity`, 0 for a reservoir.
    pub inv_capacity: f32,
    pub reservoir: bool,
    /// The largest fraction of this cell one edge may remove: one over the
    /// faces a cell has in this grid (infinite for a reservoir). See
    /// [`kernel`].
    pub share: f32,
}

impl<V> Clone for Side<'_, V> {
    fn clone(&self) -> Self {
        *self
    }
}
impl<V> Copy for Side<'_, V> {}

/// The physics of a field. The cells domain itself implements it; its
/// `Domain::apply` is the source/sink command set.
pub trait FieldKind: Domain {
    /// The name of the geometry domain (e.g. `"heat_geometry"`).
    const GEOMETRY_NAME: &'static str;
    /// How many conserved quantities [`totals`](Self::totals) reports.
    const QUANTITIES: usize;
    /// The conserved quantities' names, in [`totals`](Self::totals) order,
    /// for the driver's conservation check (empty: not checked).
    const QUANTITY_NAMES: &'static [&'static str] = &[];
    /// The [`Grid`] block layer this field's faces follow.
    const BLOCK: BlockKind = BlockKind::Air;
    /// What crosses an edge. `-F` must undo `F`, and `+` must add
    /// componentwise: a cell's fluxes are summed first and applied once,
    /// so small fluxes are not each rounded against a large content.
    type Flux: Copy
        + Default
        + Send
        + Sync
        + std::ops::Neg<Output = Self::Flux>
        + std::ops::Add<Output = Self::Flux>;

    /// The flux from `a` to `b` over `dt` seconds. Pure and deterministic.
    fn flux(a: Side<'_, Self::Value>, b: Side<'_, Self::Value>, dt: f32) -> Self::Flux;
    /// Adds `flux` to `cell` (it receives `-F` as the `a` side).
    fn apply_flux(cell: &mut Self::Value, flux: Self::Flux);
    /// Whether the edge may sleep.
    fn settled(a: Side<'_, Self::Value>, b: Side<'_, Self::Value>) -> bool;
    /// The edge's stiffness in 1/s (see [`kernel`]); 0 needs no sub-steps.
    fn stiffness(_a: Side<'_, Self::Value>, _b: Side<'_, Self::Value>) -> f32 {
        0.0
    }
    /// Per-cell local physics (reactions) once per frame on active cells.
    /// Returns whether the cell must stay awake.
    fn local(_cell: &mut Self::Value, _capacity: f32, _dt: f32) -> bool {
        false
    }
    /// A reservoir cell's own dynamics, once per frame on active cells (a
    /// planet's atmosphere returning to its baseline after DM disturbed it;
    /// the flux never changes a reservoir). Returns whether the cell must
    /// stay awake. Reservoirs are outside the conserved totals (their
    /// inflow is the field's ledger), so this may change them freely.
    fn relax(_cell: &mut Self::Value, _capacity: f32, _dt: f32) -> bool {
        false
    }
    /// Whether a cell's change over one step is rounding noise. A chunk
    /// whose cells are all quiet sleeps even with an edge above its
    /// `settled` threshold: in `f32`, a nearly linear profile can reach a
    /// fixed point (or a limit cycle a few ulps wide) where every net flux
    /// rounds away. The default is exact equality.
    fn quiet(before: &Self::Value, after: &Self::Value) -> bool {
        before == after
    }
    /// Whether the field runs each edge on its own sub-step cadence (multi-rate; see `FieldState::advance`). Off (the default) runs
    /// every edge every sub-step. The gas field keeps it off: its bulk flow couples the edges through pressure, and events that read
    /// a cell a few steps after a large write (a reaction) are sensitive to the timing.
    const MULTIRATE: bool = false;
    /// The most steps the field may take as one advance of that many steps' time, while everything awake is slow. 1 (the default)
    /// is the exact scheme. A field that sets more also sets [`STRIDE_TOLERANCE`](Self::STRIDE_TOLERANCE) and
    /// [`relative_change`](Self::relative_change); see [`FieldState::step`].
    const MAX_STRIDE: u32 = 1;
    /// The largest relative change of any cell ([`relative_change`](Self::relative_change)) one strided advance may make.
    /// The stride is chosen so that the measured rate times the stride stays under it, so the error of one advance (second order
    /// in this number) and the staleness of a read between advances are both bounded by it.
    const STRIDE_TOLERANCE: f32 = 0.0;
    /// How much `after` differs from `before`, relative to the cell's own size (0: identical). Infinite (the default) is never slow.
    fn relative_change(_before: &Self::Value, _after: &Self::Value) -> f32 {
        f32::INFINITY
    }
    /// Refreshes cached intensive values (a temperature a channel reads)
    /// after a step, on every cell of a touched chunk. Must not change
    /// conserved quantities.
    fn refresh(_cell: &mut Self::Value, _capacity: f32) {}
    /// Adds the cell's conserved quantities into `out` (`QUANTITIES` long).
    fn totals(cell: &Self::Value, out: &mut [f64]);
    /// Adds a flux's conserved quantities into `out`.
    fn flux_totals(flux: &Self::Flux, out: &mut [f64]);
}

/// Field options.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct FieldConfig {
    /// Simulated seconds per frame.
    pub dt: f32,
    /// Upper bound on sub-steps per frame (beyond it kernels' clamps keep
    /// the scheme bounded, but not monotone).
    pub max_substeps: u32,
}

impl Default for FieldConfig {
    fn default() -> Self {
        Self {
            dt: 1.0,
            max_substeps: 16,
        }
    }
}

/// Per-step statistics.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct FieldStats {
    pub steps: u64,
    /// Sub-steps of the last step.
    pub substeps: u32,
    /// Chunks active at the start of the last step.
    pub active_chunks: u32,
    /// Chunks written by the last step.
    pub touched_chunks: u32,
    /// Live edges computed per sub-step in the last step.
    pub live_edges: u32,
    /// Chunks woken at the start of the last step because their cells changed since the previous step (a write from outside the field).
    pub woke_cells: u32,
    /// Chunks woken at the start of the last step by a geometry change.
    pub woke_geom: u32,
    /// Chunks woken at the start of the last step by a change of the grid's blocked layer.
    pub woke_grid: u32,
    /// Chunks the last step kept awake because an edge was unsettled (after the quiet filter).
    pub kept_edges: u32,
    /// Chunks the last step kept awake because a cell's local step or a reservoir's relax asked to.
    pub kept_local: u32,
    /// Live edges of the last step that ran on a coarser cadence than the sub-step grid (multi-rate), and the grid's sub-steps.
    pub slow_edges: u32,
    /// Live edges of the last step in all (each counted once, not per sub-step).
    pub edges: u32,
    /// Steps the field takes per advance now (1: every step advances).
    pub stride: u32,
    /// Steps skipped (owed to the next advance) so far.
    pub skipped_steps: u64,
    /// Times the stride changed so far.
    pub stride_changes: u64,
    /// The largest per-step relative change of the last advance, in millionths (0 when the field does not stride).
    pub rate_ppm: u32,
}

/// Cumulative wall microseconds of the step's parts since the field was built: the chunk lists and stiffness, the flux of the
/// sub-steps, writing the fluxes, the quiet filter, and local physics. Wall time, so apart from [`FieldStats`] (which is deterministic).
#[derive(Clone, Copy, Debug, Default)]
pub struct FieldTimes {
    pub setup: u64,
    pub flux: u64,
    pub apply: u64,
    pub quiet: u64,
    pub local: u64,
}

/// The positive faces a chunk owns the edges of, with their opposites.
const AXES: [(Face, Face); 3] = [
    (Face::East, Face::West),
    (Face::North, Face::South),
    (Face::Up, Face::Down),
];

/// Worker-side state of a field.
pub struct FieldState<K: FieldKind> {
    dims: GridDims,
    layout: ChunkLayout,
    config: FieldConfig,
    faces: f32,
    active: Vec<bool>,
    last_cells: Option<CowStore<K::Value>>,
    last_geom: Option<CowStore<Geom>>,
    ledger: Vec<f64>,
    stats: FieldStats,
    times: FieldTimes,
    /// The grid layer revision as of the last step.
    grid_seen: u64,
    /// Steps per advance while everything awake is slow (see [`FieldKind::MAX_STRIDE`]).
    stride: u32,
    /// The cap on `stride` ([`FieldKind::MAX_STRIDE`] unless the host lowered it; 1 is the exact scheme).
    stride_cap: u32,
    /// Steps taken since the last advance, this one included.
    owed: u32,
    /// Whether edges run on their own sub-step cadence (see `advance`); off is the exact scheme.
    multirate: bool,
}

impl<K: FieldKind> fmt::Debug for FieldState<K> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("FieldState")
            .field("kind", &K::NAME)
            .field("stats", &self.stats)
            .field("ledger", &self.ledger)
            .finish_non_exhaustive()
    }
}

/// Summed fluxes for a run of cells, allocated on the first write (most
/// owner chunks on a station map are space; a full-size buffer for each was
/// most of the first frames' transient heap, Phase 4b).
struct Strip<F> {
    sum: Vec<F>,
    /// Whether any edge reached the cell (an untouched cell is not written).
    hit: Vec<bool>,
}

impl<F: Copy + Default + std::ops::Add<Output = F>> Strip<F> {
    const fn new() -> Self {
        Self {
            sum: Vec::new(),
            hit: Vec::new(),
        }
    }

    fn add(&mut self, len: usize, at: usize, f: F) {
        if self.sum.is_empty() {
            self.sum = vec![F::default(); len];
            self.hit = vec![false; len];
        }
        if self.hit[at] {
            self.sum[at] = self.sum[at] + f;
        } else {
            self.sum[at] = f;
            self.hit[at] = true;
        }
    }

    fn get(&self, at: usize) -> Option<F> {
        self.hit
            .get(at)
            .copied()
            .unwrap_or(false)
            .then(|| self.sum[at])
    }
}

/// Fluxes of one owner chunk for one sub-step, already summed per receiving
/// cell: one value per cell of the chunk, plus the edges that leave it
/// across its east and north faces (keyed by the source cell's row or
/// column) and its vertical faces (keyed by the source cell). One summed
/// flux per cell instead of one per cell and axis: a third of the old
/// per-owner buffer, and the vertical strip only where air crosses levels.
struct ChunkFlux<F> {
    net: Strip<F>,
    east: Strip<F>,
    north: Strip<F>,
    up: Strip<F>,
    ledger: Vec<f64>,
    wake: Vec<usize>,
    live: u32,
}

impl<F: Copy + Default + std::ops::Add<Output = F>> ChunkFlux<F> {
    /// What the edges leaving this chunk along `axis` from its local cell
    /// `source` carry into the neighbouring chunk.
    fn crossing(&self, axis: usize, source: usize) -> Option<F> {
        match axis {
            0 => self.east.get(source / CHUNK_EDGE as usize),
            1 => self.north.get(source % CHUNK_EDGE as usize),
            _ => self.up.get(source),
        }
    }
}

impl<K: FieldKind> FieldState<K> {
    #[must_use]
    pub fn new(dims: GridDims, config: FieldConfig) -> Self {
        let layout = ChunkLayout::spatial(dims);
        let faces = [dims.max_x(), dims.max_y(), dims.max_z()]
            .iter()
            .filter(|&&n| n > 1)
            .count()
            * 2;
        Self {
            dims,
            layout,
            config,
            #[allow(clippy::cast_precision_loss)]
            faces: faces.max(1) as f32,
            active: vec![false; layout.chunk_count()],
            last_cells: None,
            last_geom: None,
            ledger: vec![0.0; K::QUANTITIES],
            stats: FieldStats::default(),
            times: FieldTimes::default(),
            grid_seen: 0,
            stride: 1,
            stride_cap: K::MAX_STRIDE,
            owed: 0,
            multirate: K::MULTIRATE,
        }
    }

    #[must_use]
    pub const fn layout(&self) -> ChunkLayout {
        self.layout
    }

    #[must_use]
    pub const fn config(&self) -> FieldConfig {
        self.config
    }

    pub fn set_config(&mut self, config: FieldConfig) {
        self.config = config;
    }

    /// Turns the multi-rate sub-step cadence off (every edge every sub-step: the exact scheme) or on (only a field that sets
    /// [`FieldKind::MULTIRATE`] has it by default).
    pub fn set_multirate(&mut self, on: bool) {
        self.multirate = on;
    }

    /// Lowers (or restores, up to [`FieldKind::MAX_STRIDE`]) the stride cap; 1 runs the exact scheme.
    pub fn set_stride_cap(&mut self, cap: u32) {
        self.stride_cap = cap.clamp(1, K::MAX_STRIDE.max(1));
        if self.stride > self.stride_cap {
            self.stride = self.stride_cap;
        }
    }

    #[must_use]
    pub const fn times(&self) -> FieldTimes {
        self.times
    }

    /// Both at once, for the host's metrics.
    pub const fn stats_and_times(&self) -> (FieldStats, FieldTimes) {
        (self.stats, self.times)
    }

    #[must_use]
    pub const fn stats(&self) -> FieldStats {
        self.stats
    }

    /// Net conserved quantities that flowed into reservoirs so far.
    #[must_use]
    pub fn ledger(&self) -> &[f64] {
        &self.ledger
    }

    #[must_use]
    pub fn is_active(&self, chunk: usize) -> bool {
        self.active.get(chunk).copied().unwrap_or(false)
    }

    /// Active chunks, in chunk order.
    pub fn active_chunks(&self) -> impl Iterator<Item = usize> + '_ {
        self.active
            .iter()
            .enumerate()
            .filter_map(|(i, &a)| a.then_some(i))
    }

    /// Wakes the chunk holding `cell` (for tasks that write cells directly;
    /// commands are detected on their own).
    pub fn wake_cell(&mut self, cell: u32) {
        if let Some((chunk, _)) = self.layout.locate(cell) {
            self.active[chunk] = true;
        }
    }

    pub fn wake_all(&mut self) {
        self.active.fill(true);
    }

    /// Sum of every non-reservoir cell's conserved quantities.
    #[must_use]
    pub fn totals(cells: &CowStore<K::Value>, geom: &CowStore<Geom>) -> Vec<f64> {
        let mut out = vec![0.0; K::QUANTITIES];
        let layout = cells.layout();
        for chunk in 0..layout.chunk_count() {
            let Some(values) = cells.chunk(chunk) else {
                continue;
            };
            for (i, v) in values.iter().enumerate() {
                let Some(index) = layout.index_of(chunk, i) else {
                    continue;
                };
                if !geom.with(index, |g| g.reservoir).unwrap_or(false) {
                    K::totals(v, &mut out);
                }
            }
        }
        out
    }

    /// Face-neighbour chunks of `chunk`, in [`Face::ALL`] order. `Up`/`Down`
    /// follow `grid`'s z-links when it has any (the same origin-cell
    /// traversal [`Geo::neighbor`] uses for individual cells): a z-linked
    /// pair is rarely chunk-adjacent in flat index space (an expedition
    /// site's z can be far from the station's), so without this a linked
    /// pair's flux (already correct once [`Geo::neighbor`] is fixed) would
    /// never wake or even visit the other side's chunk.
    fn chunk_neighbors(&self, chunk: usize, grid: Option<&Grid>) -> [Option<usize>; 6] {
        let Some(origin) = self.layout.index_of(chunk, 0) else {
            return [None; 6];
        };
        let Some((x, y, z)) = self.dims.coords(origin) else {
            return [None; 6];
        };
        let at = |x: Option<u32>, y: Option<u32>, z: Option<u32>| {
            let index = self.dims.index(x?, y?, z?)?;
            self.layout.locate(index).map(|(c, _)| c)
        };
        let vertical = |face: Face| match grid {
            Some(g) => g
                .neighbor(origin, face)
                .and_then(|i| self.layout.locate(i).map(|(c, _)| c)),
            None => at(
                Some(x),
                Some(y),
                if face == Face::Up {
                    z.checked_add(1)
                } else {
                    z.checked_sub(1)
                },
            ),
        };
        Face::ALL.map(|face| match face {
            Face::North => at(Some(x), y.checked_add(CHUNK_EDGE), Some(z)),
            Face::South => at(Some(x), y.checked_sub(CHUNK_EDGE), Some(z)),
            Face::East => at(x.checked_add(CHUNK_EDGE), Some(y), Some(z)),
            Face::West => at(x.checked_sub(CHUNK_EDGE), Some(y), Some(z)),
            Face::Up | Face::Down => vertical(face),
        })
    }

    /// Runs one frame: wake chunks changed since the last step, sub-step
    /// the active region, put settled chunks to sleep.
    ///
    /// # Panics
    /// If the stores' layouts do not match this field's.
    pub fn step(
        &mut self,
        cells: &mut CowStore<K::Value>,
        geom: &CowStore<Geom>,
        grid: Option<&Grid>,
    ) {
        assert_eq!(cells.layout(), self.layout, "cells layout mismatch");
        assert_eq!(geom.layout(), self.layout, "geometry layout mismatch");
        self.stats.woke_cells = 0;
        self.stats.woke_geom = 0;
        self.stats.woke_grid = 0;
        if let Some(g) = grid {
            let revision = g.layer(K::BLOCK).revision();
            if revision != self.grid_seen {
                for chunk in 0..self.layout.chunk_count() {
                    let changed = self
                        .layout
                        .index_of(chunk, 0)
                        .is_some_and(|cell| g.blocked_revision(K::BLOCK, cell) > self.grid_seen);
                    if changed {
                        self.active[chunk] = true;
                        self.stats.woke_grid += 1;
                    }
                }
                self.grid_seen = revision;
            }
        }
        // The largest relative size of a write from outside since the last advance (only measured when the field may stride: a
        // coupling that nudges a few cells every step is not an event, a big write is).
        let mut outside = 0.0f32;
        match &self.last_cells {
            Some(last) => {
                for chunk in cells.chunks_differing_from(last) {
                    self.active[chunk] = true;
                    self.stats.woke_cells += 1;
                    if self.stride_cap > 1 {
                        outside = outside.max(self.max_relative_change(cells, last, &[chunk]));
                    }
                }
            }
            // First step: every chunk that has geometry (a chunk without it
            // has no field nodes, so nothing to step).
            None => {
                for (chunk, active) in self.active.iter_mut().enumerate() {
                    *active = geom.chunk(chunk).is_some();
                }
            }
        }
        if let Some(last) = &self.last_geom {
            for chunk in geom.chunks_differing_from(last) {
                self.active[chunk] = true;
                self.stats.woke_geom += 1;
            }
        }
        let woke = self.stats.woke_geom + self.stats.woke_grid > 0
            || self.last_cells.is_none()
            || (self.stats.woke_cells > 0 && (self.stride_cap <= 1 || !(outside <= K::STRIDE_TOLERANCE)));
        self.owed += 1;
        if self.stride_cap > 1 && !woke && self.owed < self.stride {
            // Everything awake is slow and nothing was written from outside: this step's time is owed to the advance `stride` steps in.
            self.stats.skipped_steps += 1;
            self.stats.substeps = 0;
            return;
        }
        // A write from outside takes a plain step now (and drops the time owed, at most the tolerance's worth of drift).
        let steps = if woke { 1 } else { self.owed };
        self.owed = 0;
        let geo = Geo {
            store: geom,
            grid,
            kind: K::BLOCK,
        };
        #[allow(clippy::cast_precision_loss)]
        let dt = self.config.dt * steps as f32;
        self.advance(cells, &geo, dt, steps, woke);
        self.last_cells = Some(cells.snapshot());
        self.last_geom = Some(geom.snapshot());
    }

    #[allow(clippy::too_many_lines)]
    fn advance(&mut self, cells: &mut CowStore<K::Value>, geom: &Geo<'_>, dt: f32, steps: u32, woke: bool) {
        self.stats.steps += 1;
        let mut lap = std::time::Instant::now();
        let take = |lap: &mut std::time::Instant| {
            let us = u64::try_from(lap.elapsed().as_micros()).unwrap_or(u64::MAX);
            *lap = std::time::Instant::now();
            us
        };
        let count = self.active.iter().filter(|&&a| a).count();
        self.stats.active_chunks = u32::try_from(count).unwrap_or(u32::MAX);
        if count == 0 {
            self.set_stride(1, 0.0);
            self.stats.substeps = 0;
            self.stats.touched_chunks = 0;
            self.stats.live_edges = 0;
            return;
        }
        // Owners hold live edges on their positive faces; targets receive.
        let chunks = self.layout.chunk_count();
        let mut owner = vec![false; chunks];
        let mut target = vec![false; chunks];
        for (chunk, _) in self.active.iter().enumerate().filter(|(_, a)| **a) {
            owner[chunk] = true;
            target[chunk] = true;
            for (face, nb) in Face::ALL.iter().zip(self.chunk_neighbors(chunk, geom.grid)) {
                if let Some(nb) = nb {
                    target[nb] = true;
                    if matches!(face, Face::West | Face::South | Face::Down) {
                        owner[nb] = true;
                    }
                }
            }
        }
        // Only chunks with field nodes own edges (an edge needs a node at
        // both ends), and only chunks with a non-reservoir node are ever
        // written. Listing a chunk as a target allocates it, so a chunk of
        // pure reservoir (space) or no geometry at all must not be listed:
        // stepping everything once allocated every chunk of the grid.
        let owners: Vec<usize> = (0..chunks)
            .filter(|&c| owner[c] && geom.store.chunk(c).is_some())
            .collect();
        let targets: Vec<usize> = (0..chunks)
            .filter(|&c| {
                target[c]
                    && geom
                        .store
                        .chunk(c)
                        .is_some_and(|g| g.iter().any(|g| g.is_node() && !g.reservoir))
            })
            .collect();
        let mut slot = vec![u32::MAX; chunks];
        for (i, &c) in owners.iter().enumerate() {
            slot[c] = u32::try_from(i).expect("chunk count fits u32");
        }
        self.stats.touched_chunks = u32::try_from(targets.len()).unwrap_or(u32::MAX);

        let (stiffness, mut live_edges) = {
            let this = &*self;
            let cells = &*cells;
            let per_chunk: Vec<(f32, Vec<LiveEdge>)> =
                owners.par_iter().map(|&c| this.chunk_stiffness(c, cells, geom)).collect();
            let stiffness = per_chunk.iter().map(|(s, _)| *s).fold(0.0, f32::max);
            (stiffness, per_chunk.into_iter().map(|(_, e)| e).collect::<Vec<_>>())
        };
        #[allow(
            clippy::cast_possible_truncation,
            clippy::cast_sign_loss,
            clippy::cast_precision_loss
        )]
        let substeps = {
            let n = (dt * self.faces * stiffness).ceil();
            if n.is_finite() && n >= 1.0 {
                (n.min(self.config.max_substeps as f32) as u32).max(1)
            } else {
                1
            }
        };
        // Multi-rate: the sub-step grid is a power of two, and an edge needing fewer sub-steps than the grid has is computed on a
        // coarser cadence (every `period` sub-steps over that much time), so one stiff edge no longer makes every edge pay for it.
        // Each edge still moves the same flux out of one cell and into the other, so conservation is unchanged.
        self.stats.slow_edges = 0;
        self.stats.edges = u32::try_from(live_edges.iter().map(Vec::len).sum::<usize>()).unwrap_or(u32::MAX);
        let substeps = if self.multirate && substeps > 1 {
            let grid = substeps.next_power_of_two().min(prev_power_of_two(self.config.max_substeps.max(1)));
            #[allow(clippy::cast_precision_loss, clippy::cast_possible_truncation, clippy::cast_sign_loss)]
            let wanted = |stiff: f32| -> u32 {
                let n = (dt * self.faces * stiff).ceil();
                if n.is_finite() && n >= 1.0 { (n.min(grid as f32) as u32).next_power_of_two().min(grid) } else { 1 }
            };
            live_edges.par_iter_mut().for_each(|edges| {
                for e in edges {
                    e.period = grid / wanted(e.stiff);
                }
            });
            let slow = live_edges.iter().flatten().filter(|e| e.period > 1).count();
            self.stats.slow_edges = u32::try_from(slow).unwrap_or(u32::MAX);
            grid
        } else {
            substeps
        };
        self.stats.substeps = substeps;
        // The substeps one step needs on its own: how far the stride may grow before the cap (the monotone bound) is hit.
        let base_substeps = {
            let n = (self.config.dt * self.faces * stiffness).ceil();
            if n.is_finite() && n >= 1.0 { n } else { 1.0 }
        };
        #[allow(clippy::cast_precision_loss)]
        let sub_dt = dt / substeps as f32;

        let start = cells.snapshot();
        let mut next = vec![false; chunks];
        self.times.setup += take(&mut lap);
        for s in 0..substeps {
            let last = s + 1 == substeps;
            // Every flux is computed from the substep's start before any
            // cell is written, so they read `cells` directly: a snapshot
            // here would make each substep copy every target chunk.
            let fluxes: Vec<ChunkFlux<K::Flux>> = {
                let this = &*self;
                let old = &*cells;
                owners
                    .par_iter()
                    .zip(live_edges.par_iter())
                    .map(|(&c, edges)| this.chunk_flux(c, edges, old, sub_dt, s, last))
                    .collect()
            };
            self.times.flux += take(&mut lap);
            let mut live = 0u32;
            for f in &fluxes {
                live = live.saturating_add(f.live);
                for (l, v) in self.ledger.iter_mut().zip(&f.ledger) {
                    *l += v;
                }
                for &w in &f.wake {
                    next[w] = true;
                }
            }
            self.stats.live_edges = live;
            // The chunks this sub-step writes at all: an owner with a summed flux, and the neighbour a strip crosses into. Writing
            // visits every cell of a chunk and its six neighbours, so a chunk with nothing to take is not visited (at idle most
            // sub-steps only move the few edges on their turn).
            let mut dirty = vec![false; chunks];
            for (&c, f) in owners.iter().zip(&fluxes) {
                let (own, east, north, up) = (!f.net.sum.is_empty(), !f.east.sum.is_empty(), !f.north.sum.is_empty(), !f.up.sum.is_empty());
                if own {
                    dirty[c] = true;
                }
                if east || north || up {
                    let nbs = self.chunk_neighbors(c, geom.grid);
                    for (face, nb) in Face::ALL.iter().zip(nbs) {
                        let crosses = match face {
                            Face::East => east,
                            Face::North => north,
                            Face::Up => up,
                            _ => false,
                        };
                        if let (true, Some(nb)) = (crosses, nb) {
                            dirty[nb] = true;
                        }
                    }
                }
            }
            let dirty = &dirty;
            let (dims, layout) = (self.dims, self.layout);
            let (owner, slot, fluxes) = (&owner, &slot, &fluxes);
            cells.par_for_listed_chunks_mut(&targets, |chunk, values| {
                if !dirty[chunk] {
                    return;
                }
                for (i, value) in values.iter_mut().enumerate() {
                    let Some(index) = layout.index_of(chunk, i) else {
                        continue;
                    };
                    let g = geom.store.get(index).unwrap_or_default();
                    if !g.is_node() || g.reservoir {
                        continue;
                    }
                    let mut net: Option<K::Flux> = None;
                    let mut add = |f: K::Flux| net = Some(net.map_or(f, |n| n + f));
                    if owner[chunk] {
                        if let Some(f) = fluxes[slot[chunk] as usize].net.get(i) {
                            add(f);
                        }
                    }
                    for (axis, (_, minus)) in AXES.iter().enumerate() {
                        let Some(nb) = geom.neighbor(dims, index, *minus) else {
                            continue;
                        };
                        let Some((nc, ni)) = layout.locate(nb) else {
                            continue;
                        };
                        if nc == chunk {
                            // Summed into this chunk's own `net` already.
                            continue;
                        }
                        let Some(from) = fluxes.get(slot[nc] as usize) else {
                            continue;
                        };
                        if let Some(f) = from.crossing(axis, ni) {
                            add(f);
                        }
                    }
                    if let Some(net) = net {
                        K::apply_flux(value, net);
                    }
                }
            });
        }

        self.times.apply += take(&mut lap);
        // A chunk the whole step left unchanged up to rounding has reached
        // the scheme's fixed point in f32 and sleeps (see `FieldKind::quiet`).
        for &c in &targets {
            if next[c] && !self.active_changed(c, cells, &start) {
                next[c] = false;
            }
        }

        self.times.quiet += take(&mut lap);
        // Local physics and cached intensive values on every touched chunk.
        let awake: Vec<AtomicBool> = (0..chunks).map(|_| AtomicBool::new(false)).collect();
        let layout = self.layout;
        let active = &self.active;
        cells.par_for_listed_chunks_mut(&targets, |chunk, values| {
            for (i, value) in values.iter_mut().enumerate() {
                let Some(index) = layout.index_of(chunk, i) else {
                    continue;
                };
                let g = geom.store.get(index).unwrap_or_default();
                if !g.is_node() {
                    continue;
                }
                if g.reservoir {
                    if active[chunk] && K::relax(value, g.capacity, dt) {
                        awake[chunk].store(true, Ordering::Relaxed);
                    }
                    continue;
                }
                if active[chunk] && K::local(value, g.capacity, dt) {
                    awake[chunk].store(true, Ordering::Relaxed);
                }
                K::refresh(value, g.capacity);
            }
        });
        self.times.local += take(&mut lap);
        self.stats.kept_edges = u32::try_from(next.iter().filter(|&&n| n).count()).unwrap_or(u32::MAX);
        let mut kept_local = 0u32;
        for (n, a) in next.iter_mut().zip(&awake) {
            if a.load(Ordering::Relaxed) {
                kept_local += 1;
                *n = true;
            }
        }
        self.stats.kept_local = kept_local;
        if self.stride_cap > 1 {
            #[allow(clippy::cast_precision_loss)]
            let rate = if woke || kept_local > 0 {
                f32::INFINITY
            } else {
                self.max_relative_change(cells, &start, &targets) / steps.max(1) as f32
            };
            let by_rate = if rate > 0.0 { (K::STRIDE_TOLERANCE / rate).floor() } else { f32::INFINITY };
            #[allow(clippy::cast_precision_loss, clippy::cast_possible_truncation, clippy::cast_sign_loss)]
            let wanted = {
                let by_cap = (self.config.max_substeps as f32 / base_substeps).floor();
                by_rate.min(by_cap).min(self.stride_cap as f32).max(1.0) as u32
            };
            self.set_stride(wanted, rate);
        }
        self.active = next;
    }

    /// The largest [`FieldKind::relative_change`] of any cell of the listed chunks between `start` and `cells`.
    fn max_relative_change(&self, cells: &CowStore<K::Value>, start: &CowStore<K::Value>, targets: &[usize]) -> f32 {
        targets
            .par_iter()
            .map(|&c| match (cells.chunk(c), start.chunk(c)) {
                (Some(now), Some(then)) if now.as_ptr() != then.as_ptr() => now
                    .iter()
                    .zip(then)
                    .map(|(a, b)| K::relative_change(b, a))
                    .fold(0.0f32, |m, v| if v.is_nan() { f32::INFINITY } else { m.max(v) }),
                (Some(_) | None, Some(_) | None) if cells.chunk(c).is_none() == start.chunk(c).is_none() => 0.0,
                _ => f32::INFINITY,
            })
            .reduce(|| 0.0, f32::max)
    }

    /// Sets the stride, recording the change (the first few are logged to stderr: a stride that flaps shows up there and in the gauges).
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    fn set_stride(&mut self, stride: u32, rate: f32) {
        static LOGGED: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);
        let stride = stride.max(1);
        self.stats.rate_ppm = if rate.is_finite() { (rate * 1.0e6).min(4.0e9) as u32 } else { u32::MAX };
        if stride != self.stride {
            self.stats.stride_changes += 1;
            if LOGGED.fetch_add(1, Ordering::Relaxed) < 64 {
                eprintln!(
                    "verdigris field {}: stride {} -> {} (rate {rate:.3e}/step, tolerance {:.1e}, step {}, skipped {})",
                    K::NAME,
                    self.stride,
                    stride,
                    K::STRIDE_TOLERANCE,
                    self.stats.steps,
                    self.stats.skipped_steps
                );
            }
            self.stride = stride;
        }
        self.stats.stride = stride;
    }

    fn active_changed(
        &self,
        chunk: usize,
        cells: &CowStore<K::Value>,
        start: &CowStore<K::Value>,
    ) -> bool {
        match (cells.chunk(chunk), start.chunk(chunk)) {
            (Some(now), Some(then)) => {
                now.as_ptr() != then.as_ptr() && now.iter().zip(then).any(|(a, b)| !K::quiet(b, a))
            }
            (None, None) => false,
            _ => true,
        }
    }

    /// Calls `f(a, b, face_axis, a_index, b_index)` for each existing edge
    /// on the positive faces of `chunk` whose two ends are field nodes, not
    /// both reservoirs, and where either end's chunk is active.
    fn for_live_edges(
        &self,
        chunk: usize,
        geom: &Geo<'_>,
        mut f: impl FnMut(usize, usize, u32, Geom, u32, Geom),
    ) {
        for i in 0..self.layout.chunk_len() {
            let Some(index) = self.layout.index_of(chunk, i) else {
                continue;
            };
            let ga = geom.store.get(index).unwrap_or_default();
            if !ga.is_node() {
                continue;
            }
            for (axis, (plus, minus)) in AXES.iter().enumerate() {
                let Some(nb) = geom.neighbor(self.dims, index, *plus) else {
                    continue;
                };
                let Some((nc, _)) = self.layout.locate(nb) else {
                    continue;
                };
                if !(self.active[chunk] || self.active[nc]) {
                    continue;
                }
                let gb = geom.store.get(nb).unwrap_or_default();
                if !gb.is_node()
                    || (ga.reservoir && gb.reservoir)
                    || geom.blocked(index, &ga).contains(*plus)
                    || geom.blocked(nb, &gb).contains(*minus)
                {
                    continue;
                }
                f(i, axis, index, ga, nb, gb);
            }
        }
    }

    /// The largest stiffness of the chunk's live edges, with the edges themselves: which edges are live depends on the geometry, the
    /// active set and the grid, none of which change during a step, so the sub-steps reuse this list instead of scanning every
    /// cell of the chunk again (16 scans of 4096 cells per chunk per step at idle).
    fn chunk_stiffness(&self, chunk: usize, cells: &CowStore<K::Value>, geom: &Geo<'_>) -> (f32, Vec<LiveEdge>) {
        let mut max = 0.0f32;
        let mut edges = Vec::new();
        self.for_live_edges(chunk, geom, |i, axis, a, ga, b, gb| {
            let s = cells
                .with(a, |va| {
                    cells.with(b, |vb| {
                        K::stiffness(side(va, ga, self.faces), side(vb, gb, self.faces))
                    })
                })
                .flatten()
                .unwrap_or(0.0);
            let s = if s.is_finite() { s.max(0.0) } else { 0.0 };
            max = max.max(s);
            edges.push(LiveEdge { i, axis, a, ga, b, gb, stiff: s, period: 1 });
        });
        (max, edges)
    }

    fn chunk_flux(
        &self,
        chunk: usize,
        edges: &[LiveEdge],
        old: &CowStore<K::Value>,
        dt: f32,
        step: u32,
        last: bool,
    ) -> ChunkFlux<K::Flux> {
        let len = self.layout.chunk_len();
        let edge = CHUNK_EDGE as usize;
        let mut out = ChunkFlux {
            net: Strip::new(),
            east: Strip::new(),
            north: Strip::new(),
            up: Strip::new(),
            ledger: vec![0.0; K::QUANTITIES],
            wake: Vec::new(),
            live: 0,
        };
        for &LiveEdge { i, axis, a, ga, b, gb, period, .. } in edges {
            let due = step % period == 0;
            let located = self.layout.locate(b);
            let nc = located.map_or(chunk, |(c, _)| c);
            // An edge into a sleeping chunk only flows once it is unsettled,
            // so a sleeping chunk is never written until it wakes.
            let boundary = self.active[chunk] != self.active[nc];
            if !due && !(last || boundary) {
                // A slow edge between its turns, nothing to judge: no reads at all (the point of the cadence).
                continue;
            }
            let Some((flux, settled)) = old
                .with(a, |va| {
                    old.with(b, |vb| {
                        let (sa, sb) = (side(va, ga, self.faces), side(vb, gb, self.faces));
                        let settled = (last || boundary) && K::settled(sa, sb);
                        let flux = if due { K::flux(sa, sb, dt * period as f32) } else { Default::default() };
                        (flux, settled || !(last || boundary))
                    })
                })
                .flatten()
            else {
                continue;
            };
            if boundary && settled {
                continue;
            }
            if !due {
                // A slow edge between its turns: only its settled test counts (it keeps its chunks awake).
                if !settled {
                    for c in [chunk, nc] {
                        if !out.wake.contains(&c) {
                            out.wake.push(c);
                        }
                    }
                }
                continue;
            }
            // `a` (here) gives the flux up, `b` receives it.
            out.net.add(len, i, -flux);
            match located {
                Some((c, ni)) if c == chunk => out.net.add(len, ni, flux),
                _ => match axis {
                    0 => out.east.add(edge, i / edge, flux),
                    1 => out.north.add(edge, i % edge, flux),
                    _ => out.up.add(len, i, flux),
                },
            }
            out.live += 1;
            if gb.reservoir {
                K::flux_totals(&flux, &mut out.ledger);
            } else if ga.reservoir {
                K::flux_totals(&-flux, &mut out.ledger);
            }
            if !settled {
                for c in [chunk, nc] {
                    if !out.wake.contains(&c) {
                        out.wake.push(c);
                    }
                }
            }
        }
        out
    }
}

/// One live edge of a chunk (see `for_live_edges`): the owner's cell index within the chunk, the axis, and both ends.
#[derive(Clone, Copy)]
struct LiveEdge {
    i: usize,
    axis: usize,
    a: u32,
    ga: Geom,
    b: u32,
    gb: Geom,
    /// The edge's own stiffness (1/s).
    stiff: f32,
    /// The edge is computed every `period`-th sub-step, over `period` sub-steps' time (1: every one). Set per step from `stiff`.
    period: u32,
}

/// A step's view of the geometry: the per-cell store plus the grid's
/// block layer.
struct Geo<'a> {
    store: &'a CowStore<Geom>,
    grid: Option<&'a Grid>,
    kind: BlockKind,
}

impl Geo<'_> {
    fn blocked(&self, index: u32, g: &Geom) -> Dir {
        match self.grid {
            Some(grid) => g.blocked.union(grid.blocked(self.kind, index)),
            None => g.blocked,
        }
    }

    /// The neighbour across `face` in `dims`, following the grid's z-links
    /// (`Grid::neighbor`) when one is registered, plain index arithmetic
    /// otherwise (a field with no grid, e.g. in a unit test).
    fn neighbor(&self, dims: GridDims, index: u32, face: Face) -> Option<u32> {
        match self.grid {
            Some(grid) => grid.neighbor(index, face),
            None => dims.neighbor(index, face),
        }
    }
}

fn side<V>(cell: &V, g: Geom, faces: f32) -> Side<'_, V> {
    Side {
        cell,
        capacity: g.capacity,
        inv_capacity: g.inv_capacity(),
        reservoir: g.reservoir,
        share: if g.reservoir {
            f32::INFINITY
        } else {
            1.0 / faces
        },
    }
}

/// The keys of a registered field.
pub struct FieldKey<K: FieldKind> {
    pub cells: DomainKey<K>,
    pub geometry: DomainKey<Geometry<K>>,
    pub state: Res<FieldState<K>>,
}

impl<K: FieldKind> Clone for FieldKey<K> {
    fn clone(&self) -> Self {
        *self
    }
}
impl<K: FieldKind> Copy for FieldKey<K> {}
impl<K: FieldKind> fmt::Debug for FieldKey<K> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "FieldKey<{}>", K::NAME)
    }
}

/// Registers field `K` over `dims`: the geometry and cells domains (spatial
/// chunks), the field state, and its `field:<name>` frame task, reading its
/// blocked faces from `grid` (the world's grid resource; `None` for a field
/// that still carries them in [`Geom::blocked`]). Add the field before
/// tasks that should run after it in the frame.
pub fn add_field<K: FieldKind>(
    builder: &mut SimBuilder,
    dims: GridDims,
    config: FieldConfig,
    grid: Option<Res<Grid>>,
) -> FieldKey<K> {
    let layout = ChunkLayout::spatial(dims);
    let geometry = builder.add_domain::<Geometry<K>>(layout);
    let cells = builder.add_domain::<K>(layout);
    let state = builder.add_resource(
        format!("field:{}", K::NAME),
        FieldState::<K>::new(dims, config),
    );
    let (g, c) = (geometry.state(), cells.state());
    let mut task = Task::new(format!("field:{}", K::NAME), move |ctx| {
        let geom = ctx.read(g);
        let mut dom = ctx.write(c);
        let grid = grid.map(|r| ctx.read(r));
        ctx.write(state)
            .step(&mut dom.store, &geom.store, grid.as_deref());
    })
    .reads(g.id())
    .writes(c.id())
    .writes(state.id());
    if let Some(r) = grid {
        task = task.reads(r.id());
    }
    builder.add_task(task);
    FieldKey {
        cells,
        geometry,
        state,
    }
}

/// The largest power of two not above `n` (`n >= 1`).
const fn prev_power_of_two(n: u32) -> u32 {
    1 << (31 - n.leading_zeros())
}
