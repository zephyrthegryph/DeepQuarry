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
    /// Whether a cell's change over one step is rounding noise. A chunk
    /// whose cells are all quiet sleeps even with an edge above its
    /// `settled` threshold: in `f32`, a nearly linear profile can reach a
    /// fixed point (or a limit cycle a few ulps wide) where every net flux
    /// rounds away. The default is exact equality.
    fn quiet(before: &Self::Value, after: &Self::Value) -> bool {
        before == after
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
    /// The grid layer revision as of the last step.
    grid_seen: u64,
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

/// Fluxes of one owner chunk for one sub-step.
struct ChunkFlux<F> {
    flux: Vec<[F; 3]>,
    /// Bit `axis` set where the edge exists and is live.
    present: Vec<u8>,
    ledger: Vec<f64>,
    wake: Vec<usize>,
    live: u32,
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
            grid_seen: 0,
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

    /// Face-neighbour chunks of `chunk`, in [`Face::ALL`] order.
    fn chunk_neighbors(&self, chunk: usize) -> [Option<usize>; 6] {
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
        Face::ALL.map(|face| match face {
            Face::North => at(Some(x), y.checked_add(CHUNK_EDGE), Some(z)),
            Face::South => at(Some(x), y.checked_sub(CHUNK_EDGE), Some(z)),
            Face::East => at(x.checked_add(CHUNK_EDGE), Some(y), Some(z)),
            Face::West => at(x.checked_sub(CHUNK_EDGE), Some(y), Some(z)),
            Face::Up => at(Some(x), Some(y), z.checked_add(1)),
            Face::Down => at(Some(x), Some(y), z.checked_sub(1)),
        })
    }

    /// Runs one frame: wake chunks changed since the last step, sub-step
    /// the active region, put settled chunks to sleep.
    ///
    /// # Panics
    /// If the stores' layouts do not match this field's.
    pub fn step(&mut self, cells: &mut CowStore<K::Value>, geom: &CowStore<Geom>, grid: Option<&Grid>) {
        assert_eq!(cells.layout(), self.layout, "cells layout mismatch");
        assert_eq!(geom.layout(), self.layout, "geometry layout mismatch");
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
                    }
                }
                self.grid_seen = revision;
            }
        }
        match &self.last_cells {
            Some(last) => {
                for chunk in cells.chunks_differing_from(last) {
                    self.active[chunk] = true;
                }
            }
            None => self.active.fill(true),
        }
        if let Some(last) = &self.last_geom {
            for chunk in geom.chunks_differing_from(last) {
                self.active[chunk] = true;
            }
        }
        let geo = Geo {
            store: geom,
            grid,
            kind: K::BLOCK,
        };
        self.advance(cells, &geo);
        self.last_cells = Some(cells.snapshot());
        self.last_geom = Some(geom.snapshot());
    }

    #[allow(clippy::too_many_lines)]
    fn advance(&mut self, cells: &mut CowStore<K::Value>, geom: &Geo<'_>) {
        self.stats.steps += 1;
        let count = self.active.iter().filter(|&&a| a).count();
        self.stats.active_chunks = u32::try_from(count).unwrap_or(u32::MAX);
        if count == 0 {
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
            for (face, nb) in Face::ALL.iter().zip(self.chunk_neighbors(chunk)) {
                if let Some(nb) = nb {
                    target[nb] = true;
                    if matches!(face, Face::West | Face::South | Face::Down) {
                        owner[nb] = true;
                    }
                }
            }
        }
        let owners: Vec<usize> = (0..chunks).filter(|&c| owner[c]).collect();
        let targets: Vec<usize> = (0..chunks).filter(|&c| target[c]).collect();
        let mut slot = vec![u32::MAX; chunks];
        for (i, &c) in owners.iter().enumerate() {
            slot[c] = u32::try_from(i).expect("chunk count fits u32");
        }
        self.stats.touched_chunks = u32::try_from(targets.len()).unwrap_or(u32::MAX);

        let dt = self.config.dt;
        let stiffness = {
            let this = &*self;
            let cells = &*cells;
            owners
                .par_iter()
                .map(|&c| this.chunk_stiffness(c, cells, geom))
                .reduce(|| 0.0, f32::max)
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
        self.stats.substeps = substeps;
        #[allow(clippy::cast_precision_loss)]
        let sub_dt = dt / substeps as f32;

        let start = cells.snapshot();
        let mut next = vec![false; chunks];
        for s in 0..substeps {
            let last = s + 1 == substeps;
            let old = cells.snapshot();
            let fluxes: Vec<ChunkFlux<K::Flux>> = {
                let this = &*self;
                owners
                    .par_iter()
                    .map(|&c| this.chunk_flux(c, &old, geom, sub_dt, last))
                    .collect()
            };
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
            let (dims, layout) = (self.dims, self.layout);
            let (owner, slot, fluxes) = (&owner, &slot, &fluxes);
            cells.par_for_listed_chunks_mut(&targets, |chunk, values| {
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
                        let own = &fluxes[slot[chunk] as usize];
                        for axis in 0..3 {
                            if own.present[i] & (1 << axis) != 0 {
                                add(-own.flux[i][axis]);
                            }
                        }
                    }
                    for (axis, (_, minus)) in AXES.iter().enumerate() {
                        let Some(nb) = dims.neighbor(index, *minus) else {
                            continue;
                        };
                        let Some((nc, ni)) = layout.locate(nb) else {
                            continue;
                        };
                        let Some(from) = fluxes.get(slot[nc] as usize) else {
                            continue;
                        };
                        if from.present[ni] & (1 << axis) != 0 {
                            add(from.flux[ni][axis]);
                        }
                    }
                    if let Some(net) = net {
                        K::apply_flux(value, net);
                    }
                }
            });
        }

        // A chunk the whole step left unchanged up to rounding has reached
        // the scheme's fixed point in f32 and sleeps (see `FieldKind::quiet`).
        for &c in &targets {
            if next[c] && !self.active_changed(c, cells, &start) {
                next[c] = false;
            }
        }

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
                if !g.is_node() || g.reservoir {
                    continue;
                }
                if active[chunk] && K::local(value, g.capacity, dt) {
                    awake[chunk].store(true, Ordering::Relaxed);
                }
                K::refresh(value, g.capacity);
            }
        });
        for (n, a) in next.iter_mut().zip(&awake) {
            *n |= a.load(Ordering::Relaxed);
        }
        self.active = next;
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
                let Some(nb) = self.dims.neighbor(index, *plus) else {
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

    fn chunk_stiffness(
        &self,
        chunk: usize,
        cells: &CowStore<K::Value>,
        geom: &Geo<'_>,
    ) -> f32 {
        let mut max = 0.0f32;
        self.for_live_edges(chunk, geom, |_, _, a, ga, b, gb| {
            let s = cells
                .with(a, |va| {
                    cells.with(b, |vb| {
                        K::stiffness(side(va, ga, self.faces), side(vb, gb, self.faces))
                    })
                })
                .flatten()
                .unwrap_or(0.0);
            if s.is_finite() {
                max = max.max(s);
            }
        });
        max
    }

    fn chunk_flux(
        &self,
        chunk: usize,
        old: &CowStore<K::Value>,
        geom: &Geo<'_>,
        dt: f32,
        last: bool,
    ) -> ChunkFlux<K::Flux> {
        let len = self.layout.chunk_len();
        let mut out = ChunkFlux {
            flux: vec![[K::Flux::default(); 3]; len],
            present: vec![0; len],
            ledger: vec![0.0; K::QUANTITIES],
            wake: Vec::new(),
            live: 0,
        };
        self.for_live_edges(chunk, geom, |i, axis, a, ga, b, gb| {
            let nc = self.layout.locate(b).map_or(chunk, |(c, _)| c);
            // An edge into a sleeping chunk only flows once it is unsettled,
            // so a sleeping chunk is never written until it wakes.
            let boundary = self.active[chunk] != self.active[nc];
            let Some((flux, settled)) = old
                .with(a, |va| {
                    old.with(b, |vb| {
                        let (sa, sb) = (side(va, ga, self.faces), side(vb, gb, self.faces));
                        let settled = (last || boundary) && K::settled(sa, sb);
                        (K::flux(sa, sb, dt), settled || !(last || boundary))
                    })
                })
                .flatten()
            else {
                return;
            };
            if boundary && settled {
                return;
            }
            out.flux[i][axis] = flux;
            out.present[i] |= 1 << axis;
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
        });
        out
    }
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
        ctx.write(state).step(&mut dom.store, &geom.store, grid.as_deref());
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
