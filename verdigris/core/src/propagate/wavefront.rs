//! Wavefront: a multi-source Dijkstra flood over the grid.
//!
//! Every step between face neighbours costs at least 1, given by a caller
//! closure that sees the cell being left, the cell being entered and the
//! face crossed; returning `None` makes the step impassable. Faces blocked
//! for the chosen [`BlockKind`] are never crossed, and `Up`/`Down` are
//! ordinary faces, so floods cross z-levels wherever the grid lets them.
//!
//! Cells settle in `(distance, index)` order, which makes every result,
//! including one truncated by the budget, deterministic. Users turn the
//! distance into a falloff: an explosion of power `p` floods with
//! `max_cost = p` and reads `p - distance` per reached cell.

use std::cmp::Reverse;
use std::collections::BinaryHeap;

use crate::grid::{BlockKind, ChunkedLayer, Face, Grid};

/// Where a flood stops.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct FloodLimits {
    /// Cells farther than this are never reached (the threshold / falloff
    /// radius). Inclusive.
    pub max_cost: u32,
    /// Stop after settling this many cells (the work budget).
    pub max_cells: usize,
}

impl FloodLimits {
    pub const UNLIMITED: FloodLimits = FloodLimits {
        max_cost: u32::MAX,
        max_cells: usize::MAX,
    };

    #[must_use]
    pub const fn within(max_cost: u32) -> Self {
        Self {
            max_cost,
            max_cells: usize::MAX,
        }
    }
}

/// Why a flood ended.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FloodStop {
    /// Everything reachable within `max_cost` was settled.
    Exhausted,
    /// `max_cells` cells were settled and more were pending.
    Budget,
}

/// Per-cell scratch state, valid only when `epoch` matches the run.
#[derive(Clone, Copy, Debug, Default)]
struct Slot {
    epoch: u32,
    dist: u32,
    settled: bool,
}

/// Reusable flood scratch. Slots are stamped with a run epoch, so a new run
/// does not clear the whole array; storage grows to the highest index
/// touched and is kept for the next run.
#[derive(Clone, Debug, Default)]
pub struct Wavefront {
    slots: Vec<Slot>,
    epoch: u32,
    heap: BinaryHeap<Reverse<(u32, u32)>>,
    settled: Vec<u32>,
}

impl Wavefront {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Scratch pre-sized for `cells` cells, so even the first run on a grid
    /// that size does not grow the slot array.
    #[must_use]
    pub fn with_cells(cells: usize) -> Self {
        Self {
            slots: vec![Slot::default(); cells],
            epoch: 0,
            heap: BinaryHeap::with_capacity(cells.min(1 << 16)),
            settled: Vec::with_capacity(cells),
        }
    }

    fn begin(&mut self) {
        self.heap.clear();
        self.settled.clear();
        self.epoch = self.epoch.wrapping_add(1);
        if self.epoch == 0 {
            self.slots.fill(Slot::default());
            self.epoch = 1;
        }
    }

    #[inline]
    fn slot(&self, cell: u32) -> Option<&Slot> {
        self.slots
            .get(cell as usize)
            .filter(|s| s.epoch == self.epoch)
    }

    #[inline]
    fn offer(&mut self, cell: u32, d: u32) {
        let i = cell as usize;
        if self.slots.len() <= i {
            self.slots
                .resize((i + 1).next_power_of_two(), Slot::default());
        }
        let epoch = self.epoch;
        let slot = &mut self.slots[i];
        if slot.epoch != epoch {
            *slot = Slot {
                epoch,
                dist: d,
                settled: false,
            };
        } else if d < slot.dist && !slot.settled {
            slot.dist = d;
        } else {
            return;
        }
        self.heap.push(Reverse((d, cell)));
    }

    /// Floods from `sources` (`(cell, starting cost)`; out-of-grid sources
    /// are ignored and duplicates keep the lowest cost). `step(from, to, face)`
    /// is the cost of entering `to` from `from`, clamped to at least 1;
    /// `None` makes the step impassable.
    pub fn run<F>(
        &mut self,
        grid: &Grid,
        kind: BlockKind,
        sources: &[(u32, u32)],
        limits: FloodLimits,
        mut step: F,
    ) -> FloodStop
    where
        F: FnMut(u32, u32, Face) -> Option<u32>,
    {
        self.begin();
        let dims = grid.dims();
        let layer = grid.layer(kind);
        for &(cell, cost) in sources {
            if dims.coords(cell).is_some() && cost <= limits.max_cost {
                self.offer(cell, cost);
            }
        }
        while let Some(Reverse((d, cell))) = self.heap.pop() {
            let slot = &mut self.slots[cell as usize];
            if slot.settled || slot.dist != d {
                continue; // stale entry
            }
            if self.settled.len() >= limits.max_cells {
                return FloodStop::Budget;
            }
            slot.settled = true;
            self.settled.push(cell);
            // Inline `Grid::open_neighbor`, reading this cell's mask once.
            let here = layer.get(cell).unwrap_or_default();
            for face in Face::ALL {
                if here.contains(face) {
                    continue;
                }
                let Some(next) = dims.neighbor(cell, face) else {
                    continue;
                };
                if layer
                    .get(next)
                    .unwrap_or_default()
                    .contains(face.opposite())
                {
                    continue;
                }
                if self.slot(next).is_some_and(|s| s.settled) {
                    continue;
                }
                let Some(cost) = step(cell, next, face) else {
                    continue;
                };
                let nd = d.saturating_add(cost.max(1));
                if nd <= limits.max_cost {
                    self.offer(next, nd);
                }
            }
        }
        FloodStop::Exhausted
    }

    /// [`run`](Self::run) with the step cost read from a per-cell layer:
    /// entering a cell costs `base + layer[cell]`, and cells holding `wall`
    /// are impassable.
    #[allow(clippy::too_many_arguments)]
    pub fn run_layer<T>(
        &mut self,
        grid: &Grid,
        kind: BlockKind,
        sources: &[(u32, u32)],
        limits: FloodLimits,
        base: u32,
        layer: &ChunkedLayer<T>,
        wall: T,
    ) -> FloodStop
    where
        T: Copy + Default + PartialEq + Into<u32>,
    {
        self.run(grid, kind, sources, limits, |_, to, _| {
            let v = layer.get(to)?;
            (v != wall).then(|| base.saturating_add(v.into()))
        })
    }

    /// Cells settled by the last run, in `(distance, index)` order.
    #[must_use]
    pub fn settled(&self) -> &[u32] {
        &self.settled
    }

    /// Distance of `cell` in the last run, if it was settled. Cells that were
    /// only queued when a budget stop hit report `None`.
    #[must_use]
    pub fn distance(&self, cell: u32) -> Option<u32> {
        self.slot(cell).filter(|s| s.settled).map(|s| s.dist)
    }

    /// `(cell, distance)` for every settled cell, in settle order.
    pub fn iter(&self) -> impl Iterator<Item = (u32, u32)> + '_ {
        self.settled
            .iter()
            .map(|&c| (c, self.slots[c as usize].dist))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::grid::{Dir, GridDims};
    use proptest::prelude::*;

    /// Brute force: O(n^2) Dijkstra with a linear scan for the minimum.
    fn reference(
        grid: &Grid,
        kind: BlockKind,
        sources: &[(u32, u32)],
        max_cost: u32,
        cost: &dyn Fn(u32) -> Option<u32>,
    ) -> Vec<Option<u32>> {
        let n = (grid.dims().layer_len() * grid.dims().max_z()) as usize;
        let mut dist = vec![None::<u32>; n];
        let mut done = vec![false; n];
        for &(s, c) in sources {
            if (s as usize) < n && c <= max_cost {
                dist[s as usize] = Some(dist[s as usize].map_or(c, |d: u32| d.min(c)));
            }
        }
        while let Some(u) = (0..n)
            .filter(|&i| !done[i] && dist[i].is_some())
            .min_by_key(|&i| dist[i])
        {
            done[u] = true;
            let du = dist[u].unwrap();
            for face in Face::ALL {
                if let Some(v) = grid.open_neighbor(kind, u as u32, face)
                    && let Some(c) = cost(v)
                {
                    let nd = du + c.max(1);
                    if nd <= max_cost && dist[v as usize].is_none_or(|d| nd < d) {
                        dist[v as usize] = Some(nd);
                    }
                }
            }
        }
        dist
    }

    #[derive(Debug)]
    struct Case {
        grid: Grid,
        costs: ChunkedLayer<u8>,
        sources: Vec<(u32, u32)>,
    }

    fn arb_case() -> impl Strategy<Value = Case> {
        (1u32..14, 1u32..14, 1u32..4).prop_flat_map(|(x, y, z)| {
            let n = (x * y * z) as usize;
            (
                prop::collection::vec((0u8..64, 0u8..8), n),
                prop::collection::vec((0..n as u32, 0u32..5), 1..5),
            )
                .prop_map(move |(cells, sources)| {
                    let dims = GridDims::new(x, y, z).unwrap();
                    let mut grid = Grid::new(dims);
                    let mut costs = ChunkedLayer::new(dims);
                    for (i, (mask, c)) in cells.into_iter().enumerate() {
                        // Sparse random blocked faces; cost 7 is an impassable cell.
                        let mask = if mask < 40 { 0 } else { mask & 0b11_1111 };
                        grid.set_blocked(BlockKind::Air, i as u32, Dir(mask));
                        costs.set(i as u32, c);
                    }
                    Case {
                        grid,
                        costs,
                        sources,
                    }
                })
        })
    }

    fn cost_of(layer: &ChunkedLayer<u8>) -> impl Fn(u32) -> Option<u32> + '_ {
        move |c| {
            let v = layer.get(c)?;
            (v != 7).then_some(1 + u32::from(v))
        }
    }

    proptest! {
        #[test]
        fn distances_equal_dijkstra(case in arb_case(), max_cost in prop_oneof![Just(u32::MAX), 0u32..30]) {
            let cost = cost_of(&case.costs);
            let expected = reference(&case.grid, BlockKind::Air, &case.sources, max_cost, &cost);
            let mut wf = Wavefront::new();
            let stop = wf.run(&case.grid, BlockKind::Air, &case.sources,
                FloodLimits::within(max_cost), |_, to, _| cost(to));
            prop_assert_eq!(stop, FloodStop::Exhausted);
            for (i, e) in expected.iter().enumerate() {
                prop_assert_eq!(wf.distance(i as u32), *e, "cell {}", i);
            }
            prop_assert_eq!(wf.settled().len(), expected.iter().flatten().count());
            // Settle order is (distance, index).
            let order: Vec<_> = wf.iter().map(|(c, d)| (d, c)).collect();
            prop_assert!(order.windows(2).all(|w| w[0] < w[1]));
            // The layer helper agrees, and reusing the scratch changes nothing.
            wf.run_layer(&case.grid, BlockKind::Air, &case.sources,
                FloodLimits::within(max_cost), 1, &case.costs, 7);
            for (i, e) in expected.iter().enumerate() {
                prop_assert_eq!(wf.distance(i as u32), *e);
            }
        }

        #[test]
        fn budget_truncates_to_a_prefix(case in arb_case(), budget in 0usize..40) {
            let cost = cost_of(&case.costs);
            let mut full = Wavefront::new();
            full.run(&case.grid, BlockKind::Air, &case.sources, FloodLimits::UNLIMITED, |_, t, _| cost(t));
            let mut cut = Wavefront::new();
            let stop = cut.run(&case.grid, BlockKind::Air, &case.sources,
                FloodLimits { max_cost: u32::MAX, max_cells: budget }, |_, t, _| cost(t));
            let n = budget.min(full.settled().len());
            prop_assert_eq!(cut.settled(), &full.settled()[..n]);
            prop_assert_eq!(stop == FloodStop::Budget, budget < full.settled().len());
        }
    }

    #[test]
    fn crosses_z_only_where_open() {
        let dims = GridDims::new(3, 1, 3).unwrap();
        let mut grid = Grid::new(dims);
        let mut wf = Wavefront::new();
        let src = dims.index(0, 0, 0).unwrap();
        let top = dims.index(2, 0, 2).unwrap();
        let unit = |_, _, _| Some(1);
        wf.run(
            &grid,
            BlockKind::Air,
            &[(src, 0)],
            FloodLimits::UNLIMITED,
            unit,
        );
        assert_eq!(wf.distance(top), Some(4));
        // Seal every floor between z0 and z1.
        for x in 0..3 {
            grid.set_blocked(
                BlockKind::Air,
                dims.index(x, 0, 0).unwrap(),
                Dir::NONE.with(Face::Up),
            );
        }
        wf.run(
            &grid,
            BlockKind::Air,
            &[(src, 0)],
            FloodLimits::UNLIMITED,
            unit,
        );
        assert_eq!(wf.distance(top), None);
        assert_eq!(wf.settled().len(), 3);
        // Other block kinds are unaffected.
        wf.run(
            &grid,
            BlockKind::Heat,
            &[(src, 0)],
            FloodLimits::UNLIMITED,
            unit,
        );
        assert_eq!(wf.distance(top), Some(4));
    }

    #[test]
    fn edges_blocked_cells_and_bad_sources() {
        let dims = GridDims::new(4, 2, 1).unwrap();
        let grid = Grid::new(dims);
        let mut wf = Wavefront::new();
        // An out-of-grid source is ignored; so is one over max_cost.
        let stop = wf.run(
            &grid,
            BlockKind::Air,
            &[(99, 0), (0, 9)],
            FloodLimits::within(5),
            |_, _, _| Some(1),
        );
        assert_eq!(stop, FloodStop::Exhausted);
        assert!(wf.settled().is_empty());
        // Cells 1 and 4 (east and north of 0) impassable: 0 is sealed in, and
        // the east edge (3) does not wrap to the next row (4).
        wf.run(
            &grid,
            BlockKind::Air,
            &[(0, 0)],
            FloodLimits::UNLIMITED,
            |_, t, _| (t != 1 && t != 4).then_some(1),
        );
        assert_eq!(wf.settled(), &[0]);
        // Duplicate sources keep the cheapest; zero step cost clamps to 1.
        wf.run(
            &grid,
            BlockKind::Air,
            &[(3, 4), (3, 1)],
            FloodLimits::within(3),
            |_, _, _| Some(0),
        );
        assert_eq!(
            wf.iter().collect::<Vec<_>>(),
            vec![(3, 1), (2, 2), (7, 2), (1, 3), (6, 3)]
        );
        assert_eq!(wf.distance(99), None);
    }

    #[test]
    fn scratch_survives_epoch_wrap() {
        let dims = GridDims::new(5, 5, 1).unwrap();
        let grid = Grid::new(dims);
        let mut wf = Wavefront::with_cells(25);
        wf.epoch = u32::MAX - 2;
        for i in 0..6u32 {
            wf.run(
                &grid,
                BlockKind::Air,
                &[(i, 0)],
                FloodLimits::within(0),
                |_, _, _| Some(1),
            );
            assert_eq!(wf.settled(), &[i]);
            assert_eq!(wf.distance(i), Some(0));
            assert_eq!(wf.distance(24 - i), None);
        }
    }
}
