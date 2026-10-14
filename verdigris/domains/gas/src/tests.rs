//! Turf gas on the shared `vg_core::world::World`: the `TurfGas` field and
//! gas's laws registered the way `vg-ffi` registers them, stepped by the
//! world's own driver.
//!
//! Totals are `f64` sums of every gas and the energy over the field's cells
//! (pinned view) and its reservoir ledger. Cells are `f32`, so each check
//! allows a small relative error.

use proptest::prelude::*;
use vg_core::field::{FieldConfig, FieldKey, FieldState, Geom};
use vg_core::grid::{BlockKind, Dir, GridDims};
use vg_core::units::Seconds;
use vg_core::world::{World, WorldBuilder, WorldConfig};

use crate::cell::{GasCell, GasCmd, TurfGas, N, Q};
use crate::gas::ids::{GAS_NITROGEN, GAS_OXYGEN, GAS_PLASMA};
use crate::laws::{CellReactionReadyLaw, CellVisualChangeLaw, GasEvent, SpacewindLaw};

const X: u32 = 20;
const Y: u32 = 20;

/// A world holding only turf gas, as `vg-ffi` registers it.
struct Rig {
	w: World,
	key: FieldKey<TurfGas>,
}

impl Rig {
	fn new(x: u32, y: u32) -> Self {
		let mut b = WorldBuilder::new(WorldConfig {
			dt: Seconds(0.5),
			..WorldConfig::default()
		});
		b.add_grid(GridDims::new(x, y, 1).expect("fits"));
		let key = b.add_field::<TurfGas>(FieldConfig {
			dt: 0.5,
			max_substeps: 16,
		});
		b.watch_field(key);
		let _ = b.add_law::<CellReactionReadyLaw>();
		let _ = b.add_law::<CellVisualChangeLaw>();
		let _ = b.add_law::<SpacewindLaw>();
		Self {
			w: b.build().expect("world builds"),
			key,
		}
	}

	fn register(&mut self, cell: u32, mut value: GasCell, reservoir: bool, mask: u8) {
		value.refresh_in(2500.0);
		let _ = self.w.sim_mut().port(self.key.cells).put(cell, value);
		let geom = Geom {
			capacity: 2500.0,
			blocked: Dir::NONE,
			reservoir,
		};
		let _ = self.w.sim_mut().port(self.key.geometry).put(cell, geom);
		let _ = self
			.w
			.edit_grid(|g| g.set_blocked(BlockKind::Air, cell, Dir(mask)));
	}

	fn read(&self, cell: u32) -> Option<GasCell> {
		self.w.read_cell(self.key, cell)
	}

	fn run(&mut self, frames: u32) {
		for _ in 0..frames {
			self.w.step_blocking();
		}
	}

	/// Every cell's gas and energy (pinned) plus what flowed into
	/// reservoirs.
	fn totals(&mut self) -> [f64; Q] {
		self.w.settle();
		let cells = self.w.sim().port_ref(self.key.cells).pinned();
		let geom = self.w.sim().port_ref(self.key.geometry).pinned();
		let sums = FieldState::<TurfGas>::totals(cells.store(), geom.store());
		let state = self.key.state;
		let ledger = self
			.w
			.sim_mut()
			.with_idle_world(|res| res.get(state).ledger().to_vec())
			.expect("idle");
		let mut out = [0.0; Q];
		for (i, o) in out.iter_mut().enumerate() {
			*o = sums[i] + ledger[i];
		}
		out
	}

	fn active_chunks(&mut self) -> u32 {
		let state = self.key.state;
		self.w
			.sim_mut()
			.with_idle_world(|res| res.get(state).stats().active_chunks)
			.expect("idle")
	}
}

fn air(scale: f32, t: f32) -> GasCell {
	let mut m = [0.0; N];
	m[GAS_OXYGEN] = 21.8 * scale;
	m[GAS_NITROGEN] = 82.1 * scale;
	GasCell::new(m, t)
}

fn cell(x: u32, y: u32) -> u32 {
	y * X + x
}

/// A room with random walls, doors and gas, and the map's border as space
/// reservoirs when `space` is set.
fn build(r: &mut Rig, seed: u64, space: bool) {
	let mut rng = seed | 1;
	let mut next = || {
		rng ^= rng << 13;
		rng ^= rng >> 7;
		rng ^= rng << 17;
		rng
	};
	for y in 0..Y {
		for x in 0..X {
			let c = cell(x, y);
			if x == 0 || y == 0 || x == X - 1 || y == Y - 1 {
				if space {
					let mut v = GasCell::default();
					v.flags |= crate::cell::flags::IMMUTABLE;
					r.register(c, v, true, 0);
				}
				continue;
			}
			let n = next();
			if n % 11 == 0 {
				continue; // a wall: not in the field
			}
			let t = 150.0 + (n >> 20) as f32 % 400.0;
			let mut v = air((n % 1000) as f32 / 250.0, t);
			if n % 7 == 0 {
				v.moles[GAS_PLASMA] = 5.0;
				v = GasCell::new(v.moles, t);
			}
			// Some faces blocked (doors, windows).
			let mask = if n % 5 == 0 { 1 << (n % 4) } else { 0 };
			r.register(c, v, false, mask as u8);
		}
	}
}

fn close(a: &[f64; Q], b: &[f64; Q], rel: f64) -> Result<(), String> {
	for i in 0..Q {
		let scale = a[i].abs().max(b[i].abs()).max(1.0);
		if (a[i] - b[i]).abs() > rel * scale {
			return Err(format!(
				"quantity {i}: {} vs {} (diff {})",
				a[i],
				b[i],
				a[i] - b[i]
			));
		}
	}
	Ok(())
}

#[test]
fn the_field_conserves_gas_and_energy_including_space() {
	let mut r = Rig::new(X, Y);
	build(&mut r, 99, true);
	r.run(1);
	let before = r.totals();
	r.run(40);
	let after = r.totals();
	close(&before, &after, 1e-4).unwrap();
	let state = r.key.state;
	let ledger =
		r.w.sim_mut()
			.with_idle_world(|res| res.get(state).ledger().to_vec())
			.unwrap();
	assert!(ledger[GAS_OXYGEN] > 0.0, "space took nothing: {ledger:?}");
}

#[test]
fn a_breach_drains_a_room_and_settles() {
	let mut r = Rig::new(X, Y);
	build(&mut r, 7, true);
	let probe = cell(X / 2, Y / 2);
	let start = r.read(probe).unwrap_or_default();
	r.run(200);
	let end = r.read(probe).unwrap_or_default();
	assert!(
		end.total_moles() < start.total_moles() * 0.05 || start.total_moles() == 0.0,
		"{} -> {}",
		start.total_moles(),
		end.total_moles()
	);
}

proptest! {
	#![proptest_config(ProptestConfig::with_cases(
		std::env::var("PROPTEST_CASES").ok().and_then(|v| v.parse().ok()).unwrap_or(16)
	))]

	#[test]
	fn field_conserves_for_any_layout(seed in 1u64..u64::MAX, frames in 1u32..30) {
		let mut r = Rig::new(X, Y);
		build(&mut r, seed, seed % 2 == 0);
		r.run(1);
		let before = r.totals();
		r.run(frames);
		let after = r.totals();
		prop_assert!(close(&before, &after, 1e-4).is_ok(), "{:?}", close(&before, &after, 1e-4));
	}

}

#[test]
fn visual_and_reaction_events_are_typed_events() {
	let mut gate = crate::gate::Gate::default();
	gate.gases = vec![crate::gate::GasType::default(); crate::cell::N];
	gate.gases[GAS_PLASMA].visible = Some(0.25);
	gate.reactions.push(crate::gate::Requirement {
		min_temp: Some(500.0),
		gases: vec![(GAS_PLASMA, 1.0)],
		..Default::default()
	});
	crate::gate::install(gate);
	let mut r = Rig::new(X, Y);
	for y in 1..Y - 1 {
		for x in 1..X - 1 {
			r.register(cell(x, y), air(1.0, 293.15), false, 0);
		}
	}
	r.run(3);
	let _ = r.w.drain_events();
	let (a, b) = (cell(5, 5), cell(6, 5));
	let mut d = [0.0; Q];
	d[GAS_PLASMA] = 100.0;
	d[N] = 100.0 * 200.0 * 600.0;
	let _ = r.w.submit_cell(r.key, a, GasCmd::Delta(d));
	r.run(4);
	let events: Vec<GasEvent> =
		r.w.drain_events()
			.decoded::<GasEvent>()
			.map(|(_, e)| e)
			.collect();
	assert!(
		events
			.iter()
			.any(|e| matches!(e, GasEvent::CellVisualChange { cell, .. } if *cell == b)),
		"no CellVisualChange for b: {events:?}"
	);
	assert!(
		events
			.iter()
			.any(|e| matches!(e, GasEvent::CellReactionReady { cell, reaction: 0 } if *cell == a)),
		"no CellReactionReady(0) for a: {events:?}"
	);
}

/// Pins the activity invariants `FieldState` gives every field, for gas: a
/// settled room sleeps, a nudge wakes only nearby chunks (not the whole
/// map), a distant cell is untouched, and the field re-settles.
#[test]
fn nudging_one_cell_wakes_only_its_neighbourhood_and_settles_again() {
	const SIZE: u32 = 48; // several CHUNK_EDGE=16 chunks per axis
	let mut r = Rig::new(SIZE, SIZE);
	let idx = |x: u32, y: u32| y * SIZE + x;
	for y in 0..SIZE {
		for x in 0..SIZE {
			r.register(idx(x, y), air(1.0, 293.15), false, 0);
		}
	}
	r.run(20);
	assert_eq!(r.active_chunks(), 0, "a uniform room should settle");
	let far = idx(SIZE - 2, SIZE - 2);
	let before_far = r.read(far).unwrap();

	let mut d = [0.0; Q];
	d[N] = 200.0;
	let _ = r.w.submit_cell(r.key, idx(2, 2), GasCmd::Delta(d));
	r.run(1);
	let awake = r.active_chunks();
	let total = SIZE.div_ceil(16) * SIZE.div_ceil(16);
	assert!(
		awake > 0 && awake < total,
		"only a neighbourhood should wake: {awake} of {total}"
	);
	r.run(60);
	assert_eq!(r.active_chunks(), 0, "it settles again");
	assert_eq!(
		before_far,
		r.read(far).unwrap(),
		"the far cell was never part of the disturbance"
	);
}

#[test]
fn a_planet_cell_relaxes_back_to_its_atmosphere() {
	crate::planet::reset_for_test();
	let mut r = Rig::new(4, 4);
	let base = air(1.0, 293.15);
	let id = crate::planet::planet_id("test_planet_rig", base);
	let mut v = base;
	v.planet = id;
	r.register(5, v, true, 0);
	r.register(6, air(1.0, 293.15), false, 0);
	r.run(2);
	let mut d = [0.0; Q];
	d[GAS_OXYGEN] = -10.0;
	let _ = r.w.submit_cell(r.key, 5, GasCmd::Delta(d));
	r.run(1);
	assert!(r.read(5).unwrap().moles[GAS_OXYGEN] < base.moles[GAS_OXYGEN] - 1.0);
	r.run(60);
	let end = r.read(5).unwrap();
	assert!(
		(end.moles[GAS_OXYGEN] - base.moles[GAS_OXYGEN]).abs() < 0.1,
		"{end:?}"
	);
}

/// DM's writes are field commands with absolute amounts: whatever they
/// add, the field's totals gain exactly that, frames later.
#[test]
fn dm_deltas_conserve() {
	let mut r = Rig::new(X, Y);
	build(&mut r, 3, false);
	r.run(1);
	let mut expected = r.totals();
	for i in 0..120u32 {
		let c = cell(1 + i * 5 % (X - 2), 1 + i * 3 % (Y - 2));
		let Some(v) = r.read(c) else { continue };
		let mut d = [0.0f32; Q];
		d[GAS_PLASMA] = (i % 17) as f32 + 1.0;
		d[GAS_OXYGEN] = -(v.moles[GAS_OXYGEN] * 0.1);
		d[N] = 1000.0;
		if r.w
			.sim()
			.port_ref(r.key.geometry)
			.read(c)
			.unwrap_or_default()
			.is_node()
			&& r.w.submit_cell(r.key, c, GasCmd::Delta(d)).is_ok()
		{
			for (e, v) in expected.iter_mut().zip(d) {
				*e += f64::from(v);
			}
		}
		if i % 3 == 0 {
			r.run(1);
		}
	}
	r.run(3);
	close(&expected, &r.totals(), 1e-4).unwrap();
}

/// A closed room cooled at one cell (a cold machine or pipe loop on its floor) drifts toward the cold cell without ringing: the pressure
/// differences stay small, so the bulk flow below the stiffness threshold must stay stable at the sub-steps diffusion alone chooses. It once
/// overshot, grew until a difference crossed the threshold, then snapped back: every few frames a reading swung 20% around the room's
/// pressure (dq_station_alarm_component_is_sealed's Telecomms Control Room read 93 kPa of a 101 kPa room).
#[test]
fn a_slowly_cooled_room_does_not_ring() {
	const SIZE: u32 = 8;
	let mut r = Rig::new(SIZE, SIZE);
	let idx = |x: u32, y: u32| y * SIZE + x;
	for y in 0..SIZE {
		for x in 0..SIZE {
			let edge = x == 0 || y == 0 || x == SIZE - 1 || y == SIZE - 1;
			r.register(idx(x, y), air(1.0, 293.15), false, if edge { 0b1111 } else { 0 });
		}
	}
	r.run(4);
	let p = |r: &Rig, c: u32| {
		let cell = r.read(c).unwrap();
		cell.pressure_in(2500.0)
	};
	let room = p(&r, idx(4, 4));
	for frame in 0..60 {
		let mut d = [0.0; Q];
		d[N] = -4000.0; // about 0.04 K per frame out of one cell
		let _ = r.w.submit_cell(r.key, idx(2, 2), GasCmd::Delta(d));
		r.run(1);
		for y in 1..SIZE - 1 {
			for x in 1..SIZE - 1 {
				let now = p(&r, idx(x, y));
				assert!(
					(now - room).abs() < 2.0,
					"frame {frame}: cell ({x},{y}) reads {now} kPa in a {room} kPa room being cooled by a fraction of a kelvin"
				);
			}
		}
	}
}
