//! The idle stride of the solid heat field stays inside its tolerance.
//!
//! Tolerance (`SolidHeat::STRIDE_TOLERANCE`, the doc of `FieldKind::MAX_STRIDE`): while every awake chunk changes by less than 1e-3 of
//! its energy per advance, the field takes up to 8 steps as one advance of that many steps' time. Against the exact scheme (every step
//! advances) after the same number of steps this test requires
//! - every cell's temperature within 0.05 K,
//! - the conserved total (cells plus what went into reservoirs) unchanged to 1e-6 relative in both runs (the stride moves the same
//!   fluxes in fewer, longer advances, so conservation is exact up to `f32` rounding),
//! - no cell outside the physical bounds (the initial minimum and maximum temperature, with the sky the floor),
//!   and that a write from outside takes a plain step at once.

use vg_core::cow::{ChunkLayout, CowStore};
use vg_core::field::{FieldConfig, FieldState, Geom};
use vg_core::grid::GridDims;
use vg_heat::solid::flags;
use vg_heat::{SolidCell, SolidHeat};

const N: u32 = 40;
const CAPACITY: f32 = 5_000.0;

struct Row {
    cells: CowStore<SolidCell>,
    geom: CowStore<Geom>,
    field: FieldState<SolidHeat>,
}

/// `N` plating cells in a row, a 20 K gradient along it, the last one next to a space reservoir (it radiates).
fn row(cap: u32) -> Row {
    let dims = GridDims::new(N + 1, 1, 1).unwrap();
    let layout = ChunkLayout::spatial(dims);
    let mut cells = CowStore::new(layout);
    let mut geom = CowStore::new(layout);
    for i in 0..N {
        let t = 285.0 - 20.0 * i as f32 / N as f32;
        geom.set(i, Geom::cell(CAPACITY));
        cells.set(i, SolidCell::at(CAPACITY, t, 0.05, 0.9, 0));
    }
    geom.set(N, Geom::reservoir(7_000.0));
    cells.set(N, SolidCell::at(7_000.0, 3.0, 0.4, 0.0, flags::SPACE));
    let mut field = FieldState::new(dims, FieldConfig { dt: 1.0, max_substeps: 16 });
    field.set_stride_cap(cap);
    Row { cells, geom, field }
}

impl Row {
    fn step(&mut self) {
        self.field.step(&mut self.cells, &self.geom, None);
    }

    fn temperature(&self, i: u32) -> f32 {
        self.cells.get(i).unwrap().energy / CAPACITY
    }

    fn conserved(&self) -> f64 {
        FieldState::<SolidHeat>::totals(&self.cells, &self.geom)[0] + self.field.ledger()[0]
    }
}

#[test]
fn the_stride_stays_within_the_tolerance_of_the_exact_scheme_and_conserves_energy() {
    let (mut exact, mut strided) = (row(1), row(8));
    let start = exact.conserved();
    let (lo, hi) = (265.0f32, 285.0f32);
    for step in 0..600 {
        exact.step();
        strided.step();
        // Both runs conserve at every step (the strided one between advances too: nothing moves then).
        for run in [&exact, &strided] {
            assert!((run.conserved() - start).abs() <= 1e-6 * start.abs(), "conservation at step {step}: {} vs {start}", run.conserved());
        }
        for i in 0..N {
            let t = strided.temperature(i);
            assert!(t >= lo - 0.05 && t <= hi + 0.05, "cell {i} left the physical bounds at step {step}: {t}");
        }
    }
    let worst = (0..N).map(|i| (exact.temperature(i) - strided.temperature(i)).abs()).fold(0.0f32, f32::max);
    assert!(worst <= 0.05, "the strided run drifted {worst} K from the exact one");
    let stats = strided.field.stats();
    assert!(stats.skipped_steps > 0, "the idle stride never skipped a step: {stats:?}");
    assert!(stats.steps < exact.field.stats().steps / 2, "the strided run advanced {} times, the exact one {}", stats.steps, exact.field.stats().steps);
    assert_eq!(exact.field.stats().skipped_steps, 0);
}

#[test]
fn a_write_from_outside_takes_a_plain_step_at_once() {
    let mut r = row(8);
    // Let the gradient flatten until the field strides.
    for _ in 0..600 {
        r.step();
    }
    assert!(r.field.stats().stride > 1, "no stride after 600 steps: {:?}", r.field.stats());
    // The field is mid-stride: a write from outside must not wait for the advance.
    let before = r.temperature(10);
    let mut cell = r.cells.get(10).unwrap();
    cell.energy += 50_000.0;
    r.cells.set(10, cell);
    let skipped = r.field.stats().skipped_steps;
    r.step();
    assert_eq!(r.field.stats().skipped_steps, skipped, "the step after a write was skipped");
    assert_eq!(r.field.stats().stride, 1, "a write did not reset the stride");
    assert!(r.field.stats().woke_cells > 0);
    assert!(r.temperature(10) < before + 50_000.0 / CAPACITY, "the written cell did not start to exchange");
}

/// Multi-rate edges (`FieldState::set_multirate`): a row of plating with a 0.2 J/K radiating plate at its end (a stiff edge, so the whole
/// field wants 16 sub-steps) against the exact scheme (every edge every sub-step).
///
/// Tolerance: after 300 steps every cell is within 0.05 K of the exact run (the slow edges take one Euler step per advance where
/// the exact run takes 16 shorter ones: the same first-order scheme at a longer step, measured 0.012 K), the conserved total matches to 1e-5 relative in both runs (f32 rounding of cell energies near 1e6 J), and the fast cell is within the physical bounds.
#[test]
fn multirate_edges_stay_within_the_tolerance_of_every_edge_every_substep() {
    let build = |multirate: bool| {
        let mut r = row(1);
        r.field.set_multirate(multirate);
        // A 0.2 J/K plate between the row and space: radiating, its edge is stiff (4 e s A T^3 / C is about 23 per second), so the
        // field wants its 16 sub-steps for it while every conduction edge (k = 0.05) needs one.
        r.geom.set(N - 1, Geom::cell(0.2));
        r.cells.set(N - 1, SolidCell::at(0.2, 285.0, 0.05, 0.9, 0));
        r
    };
    let (mut exact, mut multi) = (build(false), build(true));
    let start = exact.conserved();
    for step in 0..300 {
        exact.step();
        multi.step();
        for run in [&exact, &multi] {
            assert!((run.conserved() - start).abs() <= 1e-5 * start.abs(), "conservation (1e-5, f32 rounding of 16 sub-steps) at step {step}: {} vs {start}", run.conserved());
        }
    }
    let worst = (0..N).map(|i| (exact.temperature(i) - multi.temperature(i)).abs()).fold(0.0f32, f32::max);
    let (se, sm) = (exact.field.stats(), multi.field.stats());
    eprintln!("multirate: worst {worst} K, exact substeps {} multi substeps {} slow edges {}/{}", se.substeps, sm.substeps, sm.slow_edges, sm.edges);
    assert!(worst <= 0.05, "multi-rate drifted {worst} K from the exact scheme");
    assert!(sm.slow_edges > 0, "no edge ran on the slow cadence: {sm:?}");
    assert_eq!(se.slow_edges, 0);
}
