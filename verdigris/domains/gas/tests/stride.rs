//! The idle stride of the turf gas field stays inside its tolerance.
//!
//! Tolerance (`TurfGas::STRIDE_TOLERANCE`): while every awake chunk changes by less than 5e-4 of its moles and energy per advance,
//! the field takes up to 4 steps as one advance of that many steps' time. Against the exact scheme after the same number of steps
//! this test requires every cell's moles within 0.1% (and 0.05 K), the conserved moles and energy equal to 1e-6 relative in both
//! runs, and no cell below zero moles.

use vg_core::cow::{ChunkLayout, CowStore};
use vg_core::field::{FieldConfig, FieldState, Geom};
use vg_core::grid::GridDims;
use vg_gas::cell::{GasCell, TurfGas, N};
use vg_gas::gas::ids::GAS_OXYGEN;

const LEN: u32 = 30;
const CAPACITY: f32 = 2500.0;

struct Room {
	cells: CowStore<GasCell>,
	geom: CowStore<Geom>,
	field: FieldState<TurfGas>,
}

/// A row of open turfs with a mild oxygen gradient (a slow exchange, as at idle).
fn room(cap: u32) -> Room {
	let dims = GridDims::new(LEN, 1, 1).unwrap();
	let layout = ChunkLayout::spatial(dims);
	let mut cells = CowStore::new(layout);
	let mut geom = CowStore::new(layout);
	for i in 0..LEN {
		let mut c = GasCell::new([0.0; N], 293.0);
		c.moles[GAS_OXYGEN] = 100.0 + 2.0 * i as f32;
		c.refresh_in(CAPACITY);
		geom.set(i, Geom::cell(CAPACITY));
		cells.set(i, c);
	}
	let mut field = FieldState::new(dims, FieldConfig { dt: 1.0, max_substeps: 16 });
	field.set_stride_cap(cap);
	Room { cells, geom, field }
}

impl Room {
	fn step(&mut self) {
		self.field.step(&mut self.cells, &self.geom, None);
	}

	fn moles(&self, i: u32) -> f32 {
		self.cells.get(i).unwrap().moles[GAS_OXYGEN]
	}

	fn totals(&self) -> Vec<f64> {
		FieldState::<TurfGas>::totals(&self.cells, &self.geom)
	}
}

#[test]
fn the_stride_stays_within_the_tolerance_of_the_exact_scheme_and_conserves() {
	let (mut exact, mut strided) = (room(1), room(4));
	let start = exact.totals();
	for step in 0..400 {
		exact.step();
		strided.step();
		for run in [&exact, &strided] {
			for (a, b) in run.totals().iter().zip(&start) {
				assert!((a - b).abs() <= 1e-6 * b.abs().max(1.0), "conservation at step {step}: {a} vs {b}");
			}
		}
		for i in 0..LEN {
			assert!(strided.moles(i) >= 0.0, "negative moles in cell {i} at step {step}");
		}
	}
	let worst = (0..LEN).map(|i| (exact.moles(i) - strided.moles(i)).abs() / exact.moles(i).max(1.0)).fold(0.0f32, f32::max);
	assert!(worst <= 1e-3, "the strided run drifted {worst} (relative) from the exact one");
	let worst_t = (0..LEN).map(|i| (exact.cells.get(i).unwrap().temperature - strided.cells.get(i).unwrap().temperature).abs()).fold(0.0f32, f32::max);
	assert!(worst_t <= 0.05, "the strided run's temperature drifted {worst_t} K");
	let stats = strided.field.stats();
	eprintln!("gas stride: advances {} skipped {} stride {} changes {}", stats.steps, stats.skipped_steps, stats.stride, stats.stride_changes);
	assert!(stats.skipped_steps > 0, "the idle stride never skipped a step: {stats:?}");
}
