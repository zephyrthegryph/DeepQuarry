//! Gas's laws against Core A's `vg_core::law` API
//! (`doc/rewrite/rust_architecture.md` §4.3, §7).
//!
//! `Law::Reads`/`Writes` must be `'static` (no borrowed fields): a law's
//! caller copies config in and hands mutable owned state through
//! `LawCtx::writes`, exactly the clone-in/write-back shape
//! `PipeNet::step_devices`/`GasWorld::step_turf_devices` already use for
//! device edges and `TurfGas::local` already uses for the per-cell
//! reaction check. These wrappers don't change that data flow; they give
//! the existing pure functions (`device::step`, `gate::ready`) the `Law`
//! shape the driver will schedule once Core B's component/region stores
//! land, and are tested here the same way `rust_architecture.md` §7 asks
//! for: "pure functions with Rust tests immediately."
//!
//! `TurfGas` itself (the field flux/diffusion/reaction-gate step) is
//! *not* wrapped here: a `FieldKind` is its own specialised law path
//! (§4.3, "`FieldKind` stays the monomorphised fast path... registered as
//! a law over cells"), already the real integration, not a stand-in for
//! this generic `Law` trait.

use vg_core::field::law::{Cell, Neighbors};
use vg_core::law::{Law, LawCtx, Period, Settle};
use vg_core::query::Global;
use vg_core::units::Seconds;
use vg_core::vg;

use crate::cell::{TurfGas, NO_REACTION};
use crate::device::{self, Flow, StepReport};
use crate::pipes::PipeGas;

/// A pressure difference above this (kPa, already scaled) is a
/// `PressureJump` (spacewind) -- `world.rs::PRESSURE_EVENT`, ported
/// verbatim.
const PRESSURE_EVENT: f32 = 5.0;
/// Scales the raw pressure difference before the [`PRESSURE_EVENT`] check
/// (the old diffusion constant) -- `world.rs::PRESSURE_EVENT_SCALE`, ported
/// verbatim.
const PRESSURE_EVENT_SCALE: f32 = 0.125;

/// Gas's domain events (`rust_architecture.md` §4.8).
#[vg::events(domain = gas)]
pub enum GasEvent {
	/// A turf cell's gas reaction requirements hold (`cell.rs`'s own
	/// `TurfGas::local` step already computes `GasCell::ready` every frame
	/// the field runs it; this law only turns a ready cell into an event a
	/// `Cell<TurfGas>`-anchored law can emit -- a field cell has no entity
	/// to attribute a plain [`GasEvent::ReactionReady`] to, so the cell
	/// index travels in the payload instead).
	CellReactionReady { cell: u32, reaction: u32 },
	/// A turf cell's visible-gas signature changed since the last time this
	/// fired (`GasCell::vis`/`last_vis`; `set_visuals()` on the DM side).
	CellVisualChange { cell: u32, vis: u16 },
	/// Spacewind: `cell`'s pressure differs from open neighbour
	/// `neighbor`'s by more than the threshold, already diffusion-scaled
	/// (`world.rs`'s old `Post::run`, ported onto a `Cell`/`Neighbors`
	/// law -- `rust_architecture.md` §8.5 step 6).
	PressureJump {
		cell: u32,
		neighbor: u32,
		delta: f32,
	},
}

/// Turns a turf cell's `GasCell::ready` (already computed every frame by
/// `TurfGas::local`) into [`GasEvent::CellReactionReady`]. Never sleeps on
/// its own, same as [`ReactionGateLaw`]: whether a reaction is ready can
/// change from composition or temperature changes this law doesn't itself
/// cause, so activity follows the field's own settle condition.
pub struct CellReactionReadyLaw;

impl Law for CellReactionReadyLaw {
	type Reads = Cell<TurfGas>;
	type Writes = ();
	const NAME: &'static str = "gas_cell_reaction_ready";
	const PERIOD: Period = Period::Frame;

	fn step(ctx: &mut LawCtx<'_, Cell<TurfGas>, ()>, _dt: Seconds) -> Settle {
		let ready = ctx.reads.value.ready;
		if ready != NO_REACTION && !ctx.reads.reservoir {
			let cell = ctx.index();
			ctx.emit(GasEvent::CellReactionReady {
				cell,
				reaction: ready,
			});
		}
		Settle::Active
	}
}

/// Emits [`GasEvent::CellVisualChange`] the frame a turf cell's `vis`
/// signature first differs from the value the last emission recorded
/// (`GasCell::last_vis`, written back below) -- edge-triggered, the same
/// as `world.rs`'s old snapshot-diffed `Post::run`, but without keeping an
/// external previous-frame snapshot: the cell carries its own baseline.
pub struct CellVisualChangeLaw;

impl Law for CellVisualChangeLaw {
	type Reads = Cell<TurfGas>;
	type Writes = Cell<TurfGas>;
	const NAME: &'static str = "gas_cell_visual_change";
	const PERIOD: Period = Period::Frame;

	fn step(ctx: &mut LawCtx<'_, Cell<TurfGas>, Cell<TurfGas>>, _dt: Seconds) -> Settle {
		let (vis, last) = (ctx.reads.value.vis, ctx.reads.value.last_vis);
		// A DM write (`flags::TOUCHED`) may have replaced DM's own visuals,
		// so a touched cell with anything visible (now or before) re-emits.
		let touched = ctx.reads.value.flags & crate::cell::flags::TOUCHED != 0;
		if !ctx.reads.reservoir && (vis != last || (touched && (vis != 0 || last != 0))) {
			let cell = ctx.index();
			ctx.emit(GasEvent::CellVisualChange { cell, vis });
			ctx.writes.value.last_vis = vis;
		}
		ctx.writes.value.flags &= !crate::cell::flags::TOUCHED;
		Settle::Active
	}
}

/// Emits [`GasEvent::PressureJump`] ("spacewind") for every open face where
/// a turf cell's pressure exceeds an open neighbour's by more than
/// [`PRESSURE_EVENT`] (scaled by [`PRESSURE_EVENT_SCALE`]) -- `world.rs`'s
/// old per-face check in `Post::run`, ported onto a
/// [`Neighbors<TurfGas>`] read instead of a hand-rolled `GridDims`/`CowStore`
/// walk.
pub struct SpacewindLaw;

impl Law for SpacewindLaw {
	type Reads = (Cell<TurfGas>, Neighbors<TurfGas>);
	type Writes = ();
	const NAME: &'static str = "gas_spacewind";
	const PERIOD: Period = Period::Frame;

	fn step(ctx: &mut LawCtx<'_, (Cell<TurfGas>, Neighbors<TurfGas>), ()>, _dt: Seconds) -> Settle {
		let (cell, neighbors) = ctx.reads;
		if cell.reservoir {
			return Settle::Active;
		}
		let my_p = cell.value.pressure_in(cell.capacity);
		let index = ctx.index();
		// Planar faces only (`Face::ALL`'s first four), as the old `Post::run`.
		for slot in &neighbors.0[..4] {
			let Some((neighbor, nb)) = slot else { continue };
			let nb_p = nb.value.pressure_in(nb.capacity);
			let moved = (my_p - nb_p) * PRESSURE_EVENT_SCALE;
			if moved > PRESSURE_EVENT {
				ctx.emit(GasEvent::PressureJump {
					cell: index,
					neighbor: *neighbor,
					delta: moved,
				});
			}
		}
		Settle::Active
	}
}

/// How often the pipe devices' flow law runs: every frame of the World's pacer. The pacer's fixed step is
/// 0.5 s (`WorldConfig::dt`), which is the device period the flows were always tuned to.
pub const PIPE_DEVICE_PERIOD: Period = Period::Frame;

/// One side of a device edge: a pipe region's gas or a turf's, with its volume. Devices that meet on one region (a
/// vent and a scrubber on one pipe network) or one turf share the side, so each sees what the ones before it did.
#[derive(Clone, Debug, PartialEq)]
pub struct DeviceSide {
	pub gas: PipeGas,
	pub volume: f64,
}

/// One pipe device edge's work for a step: its flows and valve, and which two [`DeviceJobs::sides`] it moves gas
/// between (staged by the FFI layer, which owns the turf side and the region payloads, and stepped by
/// [`PipeDeviceStep`]). A turf device has the turf as side `a` (a vent pump, a scrubber), wherever the graph stores
/// the cell.
#[derive(Clone, Debug, PartialEq)]
pub struct DeviceJob {
	/// The device's `vg_entity` value (reports are about it).
	pub entity: f32,
	pub flows: Vec<Flow>,
	pub valve_open: bool,
	/// Indexes into [`DeviceJobs::sides`]; never equal.
	pub a: usize,
	pub b: usize,
	/// What the steps since staging did: moles moved `a` to `b`, the power drawn by the latest step that drew any,
	/// whether a stop target was reached.
	pub moles: f64,
	pub power_w: f32,
	pub target_reached: bool,
}

impl DeviceJob {
	/// Runs every flow, then the valve gate, on the pair of `sides` for `dt` seconds, folding into the job's report.
	pub fn step(&mut self, sides: &mut [DeviceSide], dt: f32) {
		let (mut a, mut b) = (sides[self.a].gas, sides[self.b].gas);
		let (vol_a, vol_b) = (sides[self.a].volume, sides[self.b].volume);
		let mut total = StepReport::default();
		for flow in &self.flows {
			let r = device::step(flow, &mut a, vol_a, &mut b, vol_b, dt);
			total.moles += r.moles;
			total.power_w += r.power_w;
			total.target_reached |= r.target_reached;
		}
		if self.valve_open {
			total.moles += device::step_valve(true, &mut a, vol_a, &mut b, vol_b).moles;
		}
		sides[self.a].gas = a;
		sides[self.b].gas = b;
		self.moles += total.moles;
		if total.power_w != 0.0 {
			self.power_w = total.power_w;
		}
		self.target_reached |= total.target_reached;
	}

	/// Whether the steps moved gas or drew power (a settled device changes nothing and reports nothing).
	#[must_use]
	pub fn moved(&self) -> bool {
		self.moles != 0.0 || self.power_w != 0.0
	}
}

/// Every pipe device's [`DeviceJob`] for the coming steps, over the sides they share (a main-owned global the FFI
/// layer stages before the World's step and applies after it, as heat does with its mixture probes). Jobs step in
/// order, each on what the ones before it left.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct DeviceJobs {
	pub sides: Vec<DeviceSide>,
	pub jobs: Vec<DeviceJob>,
}

vg_core::law! {
	/// The pipe devices' flow law: every device edge's flows and valve, once per [`PIPE_DEVICE_PERIOD`] of the
	/// World's pacer (`device::step`'s maths, unchanged). The law is the only stepper: `vg_frame` no longer keeps a
	/// device clock of its own.
	pub PipeDeviceStep("gas_pipe_devices"): () => Global<DeviceJobs>, every PIPE_DEVICE_PERIOD, |ctx, dt| {
		#[allow(clippy::cast_possible_truncation)]
		let dt = dt.0 as f32;
		let DeviceJobs { sides, jobs } = &mut ctx.writes.0;
		for job in jobs.iter_mut() {
			job.step(sides, dt);
		}
		Settle::Active
	}
}

#[cfg(test)]
mod tests {
	use super::*;
	use crate::cell::GasCell;
	use crate::gas::constants::CELL_VOLUME;
	use crate::gas::ids::GAS_OXYGEN;

	fn field_cell(value: GasCell, capacity: f32, reservoir: bool) -> Cell<TurfGas> {
		Cell {
			value,
			capacity,
			reservoir,
		}
	}

	fn cell_fx(index: u32) -> vg_core::law::Effects {
		let mut fx = vg_core::law::Effects {
			ledger: vg_core::conservation::Ledger::new(),
			..Default::default()
		};
		fx.begin(index, 0.0, 0.0);
		fx
	}

	#[test]
	fn cell_reaction_ready_law_emits_the_cell_and_reaction() {
		// A local, un-installed `Gate` (`Gate::ready` is pure): the shared
		// `gate::install`/`gate::current()` global (used by
		// `ReactionGateLaw`'s own tests above) is process-wide and races
		// under parallel test execution, so this law's own coverage avoids
		// it entirely rather than adding a third racing installer.
		let mut gate = crate::gate::Gate::default();
		gate.reactions.push(crate::gate::Requirement {
			min_temp: Some(100.0),
			..Default::default()
		});

		let mut moles = [0.0; crate::cell::N];
		moles[GAS_OXYGEN] = 10.0;
		let mut cell = GasCell::new(moles, 250.0);
		cell.ready = gate
			.ready(&cell.moles, cell.energy, cell.temperature_now())
			.map_or(NO_REACTION, |i| i as u32);
		let reads = field_cell(cell, CELL_VOLUME, false);
		let mut writes = ();
		let mut fx = cell_fx(42);
		let mut ctx = LawCtx::new(&reads, &mut writes, &mut fx);
		CellReactionReadyLaw::step(&mut ctx, Seconds(1.0));
		assert_eq!(
			fx.events
				.decoded::<GasEvent>()
				.map(|(_, e)| e)
				.collect::<Vec<_>>(),
			vec![GasEvent::CellReactionReady {
				cell: 42,
				reaction: 0
			}]
		);
	}

	#[test]
	fn cell_reaction_ready_law_emits_nothing_when_not_ready() {
		let cell = GasCell::new([0.0; crate::cell::N], 250.0); // ready: NO_REACTION (default)
		let reads = field_cell(cell, CELL_VOLUME, false);
		let mut writes = ();
		let mut fx = cell_fx(1);
		let mut ctx = LawCtx::new(&reads, &mut writes, &mut fx);
		CellReactionReadyLaw::step(&mut ctx, Seconds(1.0));
		assert!(fx.events.is_empty());
	}

	#[test]
	fn cell_visual_change_law_fires_once_then_settles() {
		let mut cell = GasCell::new([0.0; crate::cell::N], 250.0);
		cell.vis = 5;
		let reads = field_cell(cell, CELL_VOLUME, false);
		let mut writes = field_cell(reads.value, reads.capacity, reads.reservoir);
		let mut fx = cell_fx(7);
		let mut ctx = LawCtx::new(&reads, &mut writes, &mut fx);
		CellVisualChangeLaw::step(&mut ctx, Seconds(1.0));
		assert_eq!(
			fx.events
				.decoded::<GasEvent>()
				.map(|(_, e)| e)
				.collect::<Vec<_>>(),
			vec![GasEvent::CellVisualChange { cell: 7, vis: 5 }]
		);
		assert_eq!(
			writes.value.last_vis, 5,
			"records the emitted vis as the new baseline"
		);

		// Running again with the same `vis`/`last_vis` (as the write-back
		// left it) emits nothing: the change already fired.
		let reads2 = field_cell(writes.value, writes.capacity, writes.reservoir);
		let mut writes2 = field_cell(reads2.value, reads2.capacity, reads2.reservoir);
		let mut fx2 = cell_fx(7);
		let mut ctx2 = LawCtx::new(&reads2, &mut writes2, &mut fx2);
		CellVisualChangeLaw::step(&mut ctx2, Seconds(1.0));
		assert!(fx2.events.is_empty(), "no further change: nothing to emit");
	}

	#[test]
	fn spacewind_law_emits_pressure_jump_across_an_open_face_only() {
		let hi = GasCell::new(
			[
				1000.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
				0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
			],
			293.0,
		);
		let lo = GasCell::new([0.0; crate::cell::N], 293.0);
		let reads = (
			field_cell(hi, CELL_VOLUME, false),
			Neighbors([
				Some((10, field_cell(lo, CELL_VOLUME, false))),
				None,
				None,
				None,
				None,
				None,
			]),
		);
		let mut writes = ();
		let mut fx = cell_fx(3);
		let mut ctx = LawCtx::new(&reads, &mut writes, &mut fx);
		SpacewindLaw::step(&mut ctx, Seconds(1.0));
		let events = fx
			.events
			.decoded::<GasEvent>()
			.map(|(_, e)| e)
			.collect::<Vec<_>>();
		assert_eq!(events.len(), 1);
		let GasEvent::PressureJump {
			cell,
			neighbor,
			delta,
		} = events[0]
		else {
			panic!("expected a PressureJump: {events:?}");
		};
		assert_eq!((cell, neighbor), (3, 10));
		assert!(delta > PRESSURE_EVENT, "{delta}");
	}

	#[test]
	fn spacewind_law_emits_nothing_below_the_threshold() {
		let a = GasCell::new(
			[
				10.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
				0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
			],
			293.0,
		);
		let b = a;
		let reads = (
			field_cell(a, CELL_VOLUME, false),
			Neighbors([
				Some((5, field_cell(b, CELL_VOLUME, false))),
				None,
				None,
				None,
				None,
				None,
			]),
		);
		let mut writes = ();
		let mut fx = cell_fx(0);
		let mut ctx = LawCtx::new(&reads, &mut writes, &mut fx);
		SpacewindLaw::step(&mut ctx, Seconds(1.0));
		assert!(fx.events.is_empty(), "equal pressures: no spacewind");
	}

	fn device_side(moles: f32) -> DeviceSide {
		let mut amounts = [0.0_f32; crate::cell::Q];
		amounts[GAS_OXYGEN] = moles;
		amounts[crate::cell::N] = moles * 20.0 * 293.15;
		DeviceSide {
			gas: PipeGas::from_amounts(&amounts, 293.15),
			volume: 200.0,
		}
	}

	fn pump_job(from: usize, to: usize) -> DeviceJob {
		DeviceJob {
			entity: 5.0,
			flows: vec![Flow {
				gases: 0,
				rate: device::Rate::Volume(100.0),
				direction: device::Direction::Forced,
				stop: None,
				limit: None,
			}],
			valve_open: false,
			a: from,
			b: to,
			moles: 0.0,
			power_w: 0.0,
			target_reached: false,
		}
	}

	fn total_moles(sides: &[DeviceSide]) -> f64 {
		sides.iter().map(|s| s.gas.total()).sum()
	}

	#[test]
	fn pipe_device_step_moves_gas_and_conserves_it_across_the_pair() {
		assert_eq!(PipeDeviceStep::PERIOD, PIPE_DEVICE_PERIOD);
		let reads = ();
		let jobs = DeviceJobs {
			sides: vec![device_side(200.0), device_side(0.0)],
			jobs: vec![pump_job(0, 1)],
		};
		let mut writes = Global(jobs);
		let mut fx = cell_fx(0);
		let mut ctx = LawCtx::new(&reads, &mut writes, &mut fx);
		let settle = PipeDeviceStep::step(&mut ctx, Seconds(0.5));
		assert_eq!(settle, Settle::Active);
		let jobs = &writes.0;
		assert!(jobs.jobs[0].moved(), "a flow with a source moves something");
		assert!(jobs.jobs[0].moles > 0.0, "a to b: {}", jobs.jobs[0].moles);
		assert!(
			(total_moles(&jobs.sides) - 200.0).abs() < 1e-3,
			"gas is conserved across the pair: {}",
			total_moles(&jobs.sides)
		);
	}

	#[test]
	fn pipe_device_step_accumulates_over_steps_and_an_empty_source_reports_nothing() {
		let reads = ();
		let jobs = DeviceJobs {
			sides: vec![device_side(200.0), device_side(0.0), device_side(0.0), device_side(0.0)],
			jobs: vec![pump_job(0, 1), pump_job(2, 3)],
		};
		let mut writes = Global(jobs);
		let mut fx = cell_fx(0);
		let mut ctx = LawCtx::new(&reads, &mut writes, &mut fx);
		let _ = PipeDeviceStep::step(&mut ctx, Seconds(0.5));
		let after_one = writes.0.jobs[0].moles;
		let mut ctx = LawCtx::new(&reads, &mut writes, &mut fx);
		let _ = PipeDeviceStep::step(&mut ctx, Seconds(0.5));
		assert!(writes.0.jobs[0].moles > after_one, "the report sums over steps");
		assert!(!writes.0.jobs[1].moved(), "nothing to move: nothing to report");
	}

	#[test]
	fn devices_on_one_side_each_see_what_the_ones_before_them_did() {
		// Two pumps drain one source (side 0) into two sinks: the second finds less there, and the source never goes
		// negative or is counted twice.
		let reads = ();
		let jobs = DeviceJobs {
			sides: vec![device_side(10.0), device_side(0.0), device_side(0.0)],
			jobs: vec![pump_job(0, 1), pump_job(0, 2)],
		};
		let mut writes = Global(jobs);
		let mut fx = cell_fx(0);
		for _ in 0..20 {
			let mut ctx = LawCtx::new(&reads, &mut writes, &mut fx);
			let _ = PipeDeviceStep::step(&mut ctx, Seconds(0.5));
		}
		let jobs = &writes.0;
		assert!(jobs.sides[0].gas.total() >= 0.0);
		assert!(jobs.jobs[0].moles > 0.0 && jobs.jobs[1].moles > 0.0);
		assert!(
			(total_moles(&jobs.sides) - 10.0).abs() < 1e-3,
			"one source shared by two devices is conserved: {}",
			total_moles(&jobs.sides)
		);
		assert!(
			(jobs.jobs[0].moles + jobs.jobs[1].moles - (10.0 - jobs.sides[0].gas.total())).abs() < 1e-3,
			"what the source lost is what the jobs report"
		);
	}
}
