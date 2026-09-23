//! Conservation tests for the gas world: the turf field alone, the field
//! with DM writes (overlay and fallback), `Take` reconciliation, and pipes.
//!
//! Totals are `f64` sums of every gas and the energy over main-owned
//! mixtures, pipe regions, field cells and the field's reservoir ledger.
//! Cells are `f32`, so each check allows a small relative error.

use proptest::prelude::*;
use vg_core::sim::Mode;

use crate::cell::{GasCell, N, Q};
use crate::gas::ids::{GAS_NITROGEN, GAS_OXYGEN, GAS_PLASMA};
use crate::gas::Mixture;
use crate::pipes::PipeGas;
use crate::world::{GasWorld, MixRef};

const X: u32 = 20;
const Y: u32 = 20;

fn air(scale: f32, t: f32) -> GasCell {
	let mut m = [0.0; N];
	m[GAS_OXYGEN] = 21.8 * scale;
	m[GAS_NITROGEN] = 82.1 * scale;
	GasCell::new(m, t)
}

fn world(mode: Mode) -> GasWorld {
	let mut w = GasWorld::default();
	let field = crate::world::Field::new(X, Y, 1, mode, &w.exchange).expect("field builds");
	w.mode = field.mode;
	w.field = Some(field);
	w
}

fn cell(x: u32, y: u32) -> u32 {
	y * X + x
}

/// A walled room of `w` x `h` cells at the origin, `gas` inside, with the
/// border of the map as space reservoirs when `space` is set.
fn build(world: &mut GasWorld, seed: u64, space: bool) {
	let field = world.field.as_mut().expect("field");
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
			let edge = x == 0 || y == 0 || x == X - 1 || y == Y - 1;
			if edge {
				if space {
					let mut v = GasCell::default();
					v.flags |= crate::cell::flags::IMMUTABLE;
					field.register(c, v, 2500.0, true, Some(0));
				}
				continue;
			}
			let r = next();
			if r % 11 == 0 {
				continue; // a wall: not registered
			}
			let scale = (r % 1000) as f32 / 250.0;
			let t = 150.0 + (r >> 20) as f32 % 400.0;
			let mut v = air(scale, t);
			if r % 7 == 0 {
				v.moles[GAS_PLASMA] = 5.0;
				v = GasCell::new(v.moles, t);
			}
			// Some faces blocked (doors, windows).
			let mask = if r % 5 == 0 { 1 << (r % 4) } else { 0 };
			field.register(c, v, 2500.0, false, Some(mask as u8));
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

fn totals(w: &GasWorld) -> [f64; Q] {
	let mut t = w.totals();
	for (o, v) in t.iter_mut().zip(w.field_ledger()) {
		*o += v;
	}
	t
}

#[test]
fn the_field_conserves_gas_and_energy_including_space() {
	let mut w = world(Mode::Overlay);
	build(&mut w, 99, true);
	w.run_frames(1);
	let before = totals(&w);
	w.run_frames(40);
	let after = totals(&w);
	close(&before, &after, 1e-4).unwrap();
	// Space took something.
	let ledger = w.field_ledger();
	assert!(ledger[GAS_OXYGEN] > 0.0, "{ledger:?}");
}

/// Same scenario as above, checked through the shared
/// `vg_core::conservation::Ledger` instead of a by-hand `close()` diff --
/// wiring gas into the generic conservation audit (`rust_core.md` §15).
/// `totals()` already folds the field's reservoir ledger (what space took)
/// into the sum, so no external source/sink events are expected here: the
/// energy total should hold across the run within the ledger's tolerance.
#[test]
fn the_field_conserves_energy_through_the_shared_ledger() {
	let mut w = world(Mode::Overlay);
	build(&mut w, 99, true);
	w.run_frames(1);
	let mut ledger = vg_core::conservation::Ledger::new();
	// Relative tolerance (as `close()` above uses), scaled to the current
	// total's magnitude: an absolute epsilon would be meaninglessly tight
	// or loose depending on how much energy is in the system.
	let tolerance = |total: f64| 1e-4 * total.abs().max(1.0);
	let energy = totals(&w)[N];
	// Primes the baseline; nothing to compare against yet.
	ledger
		.check("gas_energy_j", energy, tolerance(energy))
		.expect("priming never fails");
	for _ in 0..40 {
		w.run_frames(1);
		let energy = totals(&w)[N];
		vg_core::conservation::assert_conserved(&mut ledger, "gas_energy_j", energy, tolerance(energy));
	}
}

#[test]
fn a_breach_drains_a_room_and_settles() {
	let mut w = world(Mode::Overlay);
	build(&mut w, 7, true);
	let field = w.field.as_ref().unwrap();
	let probe = cell(X / 2, Y / 2);
	let (start, _) = field.read(probe).unwrap();
	w.run_frames(200);
	let (end, _) = w.field.as_ref().unwrap().read(probe).unwrap();
	assert!(
		end.total_moles() < start.total_moles() * 0.05 || start.total_moles() == 0.0,
		"{} -> {}",
		start.total_moles(),
		end.total_moles()
	);
}

/// DM's view of a turf: read, change, store (as every gas bind does).
fn dm_write(w: &mut GasWorld, c: u32, f: impl FnOnce(&mut Mixture)) {
	let r = MixRef::Turf(c);
	let before = w.load(r).unwrap();
	let mut after = before.clone();
	f(&mut after);
	w.store(r, &before, &after);
}

fn dm_writes(mode: Mode, seed: u64, ops: &[(u8, u8, u8, f32)]) -> Result<(), String> {
	let mut w = world(mode);
	build(&mut w, seed, false);
	let tank = w.mains.alloc(Mixture::from_vol(70.0)).unwrap();
	w.run_frames(1);
	let start = totals(&w);
	let mut expected = start;
	for &(kind, x, y, amount) in ops {
		let c = cell(1 + u32::from(x) % (X - 2), 1 + u32::from(y) % (Y - 2));
		if w.load(MixRef::Turf(c)).is_none() {
			continue;
		}
		match kind % 4 {
			0 => {
				// Add plasma at 400 K (a canister release).
				let mut add = Mixture::from_vol(2500.0);
				add.set_moles(GAS_PLASMA, amount);
				add.set_temperature(400.0);
				expected[GAS_PLASMA] += f64::from(amount);
				expected[N] += f64::from(amount * 200.0 * 400.0);
				dm_write(&mut w, c, |m| m.merge(&add));
			}
			1 => {
				// Remove a fraction into the tank (a scrubber, a breath).
				let r = MixRef::Turf(c);
				let before = w.load(r).unwrap();
				let tank_before = w.load(MixRef::Main(tank)).unwrap();
				let (mut a, mut b) = (before.clone(), tank_before.clone());
				b.merge(&a.remove_ratio((amount / 100.0).clamp(0.0, 1.0)));
				w.store(r, &before, &a);
				w.store(MixRef::Main(tank), &tank_before, &b);
			}
			2 => {
				// Heat it (set_temperature: energy comes from outside).
				let r = MixRef::Turf(c);
				let before = w.load(r).unwrap();
				let t = before.get_temperature() + amount;
				let de = f64::from(before.heat_capacity()) * f64::from(amount);
				expected[N] += de;
				dm_write(&mut w, c, |m| m.set_temperature(t));
			}
			_ => {
				// Take the whole cell into the tank, reconciled later.
				let taken = w.take_turf(c, tank);
				if let Some(m) = taken {
					let tank_before = w.load(MixRef::Main(tank)).unwrap();
					let mut b = tank_before.clone();
					b.merge(&m);
					w.store(MixRef::Main(tank), &tank_before, &b);
				}
			}
		}
		if kind % 3 == 0 {
			w.run_frames(1);
		}
	}
	w.run_frames(3);
	let end = totals(&w);
	// Heat added by set_temperature is only approximately what DM saw
	// (the cell's capacity may have moved by a frame), so allow for it.
	close(&expected, &end, 2e-3)
}

#[test]
fn dm_writes_conserve_with_the_overlay() {
	let ops: Vec<(u8, u8, u8, f32)> = (0..120u32)
		.map(|i| {
			(
				(i * 7 % 13) as u8,
				(i * 5) as u8,
				(i * 3) as u8,
				(i % 17) as f32 + 1.0,
			)
		})
		.collect();
	dm_writes(Mode::Overlay, 3, &ops).unwrap();
}

proptest! {
	#![proptest_config(ProptestConfig::with_cases(
		std::env::var("PROPTEST_CASES").ok().and_then(|v| v.parse().ok()).unwrap_or(16)
	))]

	#[test]
	fn field_conserves_for_any_layout(seed in 1u64..u64::MAX, frames in 1u32..30) {
		let mut w = world(Mode::Overlay);
		build(&mut w, seed, seed % 2 == 0);
		w.run_frames(1);
		let before = totals(&w);
		w.run_frames(frames);
		let after = totals(&w);
		prop_assert!(close(&before, &after, 1e-4).is_ok(), "{:?}", close(&before, &after, 1e-4));
	}

	#[test]
	fn dm_writes_conserve(seed in 1u64..u64::MAX, ops in proptest::collection::vec(
		(0u8..8, 0u8..20, 0u8..20, 0.5f32..40.0), 1..60)
	) {
		let r = dm_writes(Mode::Overlay, seed, &ops);
		prop_assert!(r.is_ok(), "{:?}", r);
	}

	#[test]
	fn pipe_edits_conserve(ops in proptest::collection::vec((0u8..5, 1u32..12, 1u32..12), 1..80)) {
		let mut w = GasWorld::default();
		let mut released = [0.0f64; Q];
		for (i, &(kind, a, b)) in ops.iter().enumerate() {
			match kind {
				0 => {
					let mut g = PipeGas::default();
					g.moles[GAS_OXYGEN] = f64::from(a) * 3.0;
					g.energy = g.moles[GAS_OXYGEN] * 20.0 * 293.0;
					w.pipes.upsert(a, 0, 50.0 + b as f32 * 10.0, g);
				}
				1 => { w.pipes.connect(a, b); }
				2 => w.pipes.disconnect(a, b),
				_ => { w.pipes.remove(a, Some(i as u32)); }
			}
			let (_, rel) = w.pipes.commit();
			for r in rel {
				for (slot, &moles) in released.iter_mut().zip(r.gas.moles.iter()).take(N) {
					*slot += moles;
				}
				released[N] += r.gas.energy;
			}
		}
		let total: f64 = ops.iter().filter(|o| o.0 == 0).count() as f64;
		let _ = total;
		// Everything ever added is in a region or was released.
		let mut added = 0.0;
		let mut seen = std::collections::HashSet::new();
		let mut live = std::collections::HashSet::new();
		for &(kind, a, _) in &ops {
			if kind == 0 && !live.contains(&a) {
				added += f64::from(a) * 3.0;
				live.insert(a);
				seen.insert(a);
			}
			if kind >= 3 {
				live.remove(&a);
			}
		}
		let held = w.pipes.totals()[GAS_OXYGEN] + released[GAS_OXYGEN];
		prop_assert!((held - added).abs() < 1e-6 * added.max(1.0), "{held} vs {added}");
	}
}

/// Overlay vs fallback (`rust_core.md` §3.11): main-thread cost per tick
/// and conservation, under a breach. Run with
/// `cargo test --release -p vg-gas --target i686-pc-windows-msvc -- --ignored --nocapture overlay_vs_fallback`.
#[test]
#[ignore = "measurement, run by hand"]
fn overlay_vs_fallback() {
	for mode in [Mode::Overlay, Mode::Fallback { budget_cells: 4096 }] {
		let mut w = world(mode);
		build(&mut w, 11, true);
		w.run_frames(1);
		let before = totals(&w);
		let mut main_us = Vec::new();
		let mut writes = 0u32;
		for i in 0..200u32 {
			let t = std::time::Instant::now();
			// DM-side work per tick: a scrubber and a vent on every tenth cell.
			for y in (1..Y - 1).step_by(3) {
				for x in (1..X - 1).step_by(3) {
					let c = cell(x, y);
					if w.load(MixRef::Turf(c)).is_some() {
						dm_write(&mut w, c, |m| m.adjust_moles(GAS_OXYGEN, 0.01));
						writes += 1;
					}
				}
			}
			w.tick(true);
			main_us.push(t.elapsed().as_secs_f64() * 1e6);
			if let Some(f) = w.field.as_mut() {
				f.sim.wait_for_frame();
			}
			let _ = i;
		}
		w.run_frames(2);
		let after = totals(&w);
		main_us.sort_by(f64::total_cmp);
		let avg = main_us.iter().sum::<f64>() / main_us.len() as f64;
		let p99 = main_us[main_us.len() * 99 / 100];
		let added = 0.01 * f64::from(writes);
		println!(
			"{mode:?}: main-thread avg {avg:.1} us, p99 {p99:.1} us, oxygen drift {:.4} mol (added {added:.1})",
			after[GAS_OXYGEN] - before[GAS_OXYGEN] - added
		);
	}
}

#[test]
fn visual_and_reaction_events_reach_dm() {
	let mut gate = crate::gate::Gate::default();
	gate.visible[GAS_PLASMA] = Some(0.25);
	gate.reactions.push(crate::gate::Requirement {
		min_temp: Some(500.0),
		gases: vec![(GAS_PLASMA, 1.0)],
		..Default::default()
	});
	crate::gate::install(gate);
	let mut w = world(Mode::Overlay);
	build(&mut w, 5, false);
	w.run_frames(3);
	let a = cell(5, 5);
	let b = cell(6, 5);
	{
		let f = w.field.as_mut().unwrap();
		f.set_mask(a, Some(0));
		f.set_mask(b, Some(0));
	}
	dm_write(&mut w, a, |m| {
		let mut add = Mixture::from_vol(2500.0);
		add.set_moles(GAS_PLASMA, 100.0);
		add.set_temperature(600.0);
		m.merge(&add);
	});
	let events = w.run_frames(4);
	let visual_b = events
		.chunks_exact(4)
		.any(|e| e[0] as u32 == 3 && e[1] as u32 == b);
	let react_a = events
		.chunks_exact(4)
		.any(|e| e[0] as u32 == 2 && e[1] as u32 == a);
	assert!(visual_b, "no VisualChange for b: {events:?}");
	assert!(react_a, "no ReactionCheck for a");
}

#[test]
fn a_settled_station_sleeps() {
	let mut w = world(Mode::Overlay);
	{
		let f = w.field.as_mut().unwrap();
		for y in 1..Y - 1 {
			for x in 1..X - 1 {
				f.register(cell(x, y), air(1.0, 293.15), 2500.0, false, Some(0));
			}
		}
	}
	w.run_frames(5);
	let idle = |w: &mut GasWorld| w.field.as_mut().unwrap().idle();
	assert!(idle(&mut w));
	let skips = w.field.as_ref().unwrap().idle_skips;
	assert!(skips > 0, "a settled field still dispatched frames");
	// A heat-sized nudge wakes it; it settles and sleeps again.
	let mut d = [0.0; Q];
	d[N] = 50.0;
	w.add_amounts(MixRef::Turf(cell(5, 5)), &d, 0.0);
	assert!(!idle(&mut w));
	let frames = w.field.as_ref().unwrap().frames;
	w.run_frames(10);
	assert!(w.field.as_ref().unwrap().frames > frames);
	assert!(idle(&mut w), "{:?}", w.field.as_ref().unwrap().stats());
}

/// Pins the activity/sleep invariants `core::field::FieldState` (which
/// `TurfGas` runs on -- `rust_core.md` §16.5/§15 (2)) is supposed to give
/// every field, at the gas level specifically: a nudge wakes only nearby
/// chunks (not the whole map), a distant, settled cell's gas is bit-
/// identical throughout, and the field re-settles afterward. Gas has no
/// activity tracking of its own to migrate onto a core service -- this
/// confirms it's already there (turf gas is `FieldState<TurfGas>`, not a
/// gas-local reimplementation) rather than building a redundant one.
#[test]
fn nudging_one_cell_wakes_only_its_neighbourhood_and_settles_again() {
	const SIZE: u32 = 48; // several CHUNK_EDGE=16 chunks per axis
	let mut w = GasWorld::default();
	let field = crate::world::Field::new(SIZE, SIZE, 1, Mode::Overlay, &w.exchange)
		.expect("field builds");
	w.mode = field.mode;
	w.field = Some(field);
	let idx = |x: u32, y: u32| y * SIZE + x;
	{
		let f = w.field.as_mut().unwrap();
		for y in 0..SIZE {
			for x in 0..SIZE {
				f.register(idx(x, y), air(1.0, 293.15), 2500.0, false, Some(0));
			}
		}
	}
	w.run_frames(20);
	let idle = |w: &mut GasWorld| w.field.as_mut().unwrap().idle();
	assert!(idle(&mut w), "a uniform room should settle");

	// A far corner, well outside the chunk(s) the nudge below can reach.
	let far = MixRef::Turf(idx(SIZE - 2, SIZE - 2));
	let before_far = w.load(far).expect("far cell readable");

	// Nudge one cell near the origin.
	let mut d = [0.0; Q];
	d[N] = 200.0;
	w.add_amounts(MixRef::Turf(idx(2, 2)), &d, 0.0);
	assert!(!idle(&mut w), "the nudge must wake the field");
	w.run_frames(1);
	let awake_after_one_step = w.field.as_ref().unwrap().awake_chunks();
	let total_chunks = SIZE.div_ceil(16) * SIZE.div_ceil(16);
	assert!(awake_after_one_step > 0, "the nudged neighbourhood woke");
	assert!(
		(awake_after_one_step as u32) < total_chunks,
		"only a neighbourhood should wake, not the whole {total_chunks}-chunk map: {awake_after_one_step}"
	);

	// The far corner never moved while the field was mid-settle.
	let mid_far = w.load(far).expect("far cell readable");
	assert_eq!(
		before_far.get_temperature(),
		mid_far.get_temperature(),
		"a sleeping cell's gas must be untouched by an unrelated wake"
	);

	// It settles again.
	w.run_frames(60);
	assert!(idle(&mut w), "{:?}", w.field.as_ref().unwrap().stats());
	let after_far = w.load(far).expect("far cell readable");
	assert_eq!(
		before_far.get_temperature(),
		after_far.get_temperature(),
		"the far cell was never part of the disturbance"
	);
}

/// M2 (simulation.md §5): a vent pump/scrubber device edge with one side on
/// a turf (the R6 field) and the other on a pipe region (the R7 network) —
/// `GasWorld::step_turf_devices`. Siphons a live cell into an empty pipe
/// region and checks the whole world (field + pipes) still conserves.
#[test]
fn step_turf_devices_bridges_pipe_and_field_and_conserves() {
	use crate::device::{DeviceParams, VentMode};
	use vg_core::network::Endpoint;

	let mut w = world(Mode::Overlay);
	build(&mut w, 7, false);
	w.run_frames(1);

	let mut turf_cell = None;
	'search: for y in 1..Y - 1 {
		for x in 1..X - 1 {
			let c = cell(x, y);
			if w.load(MixRef::Turf(c)).is_some_and(|m| m.total_moles() > 0.0) {
				turf_cell = Some(c);
				break 'search;
			}
		}
	}
	let turf_cell = turf_cell.expect("a live cell with gas");

	w.pipes.upsert(1, 0, 1000.0, PipeGas::default());
	w.pipes.commit();
	let node = w.pipes.port(1).expect("port exists");
	w.pipes
		.net
		.add_device(
			Endpoint::Cell(turf_cell),
			Endpoint::Node(node),
			0,
			1,
			DeviceParams::VentPump {
				mode: VentMode::Siphon,
				min_kpa: 0.0,
				max_kpa: 1_000_000.0,
				max_rate_l_s: 1000.0,
			},
		)
		.expect("device added");

	w.run_frames(1);
	let before = w.totals();
	for _ in 0..20 {
		w.step_turf_devices(1.0);
	}
	w.run_frames(3);
	let after = w.totals();
	assert!(close(&before, &after, 1e-3).is_ok(), "{:?}", close(&before, &after, 1e-3));

	let moved = w.pipes.totals();
	assert!(
		moved[GAS_OXYGEN] > 0.0 || moved[GAS_NITROGEN] > 0.0,
		"the vent pump moved nothing from the turf into the pipe network"
	);
}
