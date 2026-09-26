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
use vg_core::units::Seconds;
use vg_core::vg;

use crate::cell::{NO_REACTION, TurfGas};
use crate::device::{self, DeviceParams, StepReport};
use crate::gate;
use crate::pipes::PipeGas;

/// A pressure difference above this (kPa, already scaled) is a
/// `PressureJump` (spacewind) -- `world.rs::PRESSURE_EVENT`, ported
/// verbatim.
const PRESSURE_EVENT: f32 = 5.0;
/// Scales the raw pressure difference before the [`PRESSURE_EVENT`] check
/// (the old diffusion constant) -- `world.rs::PRESSURE_EVENT_SCALE`, ported
/// verbatim.
const PRESSURE_EVENT_SCALE: f32 = 0.125;

/// A device edge's config for one step: its law and the two regions'
/// volumes. `Copy`, so a law's `'static` `Reads` costs nothing to hand in
/// by value.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct DeviceReads {
	pub params: DeviceParams,
	pub vol_a: f64,
	pub vol_b: f64,
}

/// A device edge's two mixtures, owned: the law mutates them in place, and
/// the caller (today, `PipeNet`/`GasWorld`) copies them back into the
/// region/cell store afterwards - the same pattern the network and field
/// hosts already use for every other write.
#[derive(Clone, Copy, Debug, PartialEq, Default)]
pub struct DeviceSides {
	pub a: PipeGas,
	pub b: PipeGas,
}

/// The M2 device flow law (`device::step`: `Flow`/`Equalize`), as a
/// [`Law`]. Sleeps once a step moves no gas and draws no power - the same
/// idle-skip condition `PipeNet`/`GasWorld` already use to decide whether
/// to keep stepping an edge.
pub struct FlowLaw;

impl Law for FlowLaw {
	type Reads = DeviceReads;
	type Writes = DeviceSides;
	const NAME: &'static str = "gas_device_flow";

	fn step(ctx: &mut LawCtx<'_, DeviceReads, DeviceSides>, dt: Seconds) -> Settle {
		let DeviceSides { a, b } = ctx.writes;
		let report = device::step(&ctx.reads.params, a, ctx.reads.vol_a, b, ctx.reads.vol_b, dt.get() as f32);
		if report.moles == 0.0 && report.power_w == 0.0 {
			Settle::Sleep
		} else {
			Settle::Active
		}
	}
}

impl DeviceSides {
	/// Runs [`FlowLaw`] directly (no driver yet: Core B's scheduling isn't
	/// wired up), returning the step's report alongside the `Settle`
	/// decision, for callers (and tests) that want the report `step`
	/// itself produces, not just whether the edge should keep running.
	#[must_use]
	pub fn step_flow(&mut self, params: DeviceParams, vol_a: f64, vol_b: f64, dt: f32) -> (StepReport, Settle) {
		let report = device::step(&params, &mut self.a, vol_a, &mut self.b, vol_b, dt);
		let settle = if report.moles == 0.0 && report.power_w == 0.0 {
			Settle::Sleep
		} else {
			Settle::Active
		};
		(report, settle)
	}
}

/// A reaction-gating check's input: one cell's (or region's) moles, energy
/// and temperature. Reactions themselves stay in DM (`AGENTS.md`); this is
/// only the pure gate.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct GateReads {
	pub moles: [f32; crate::cell::N],
	pub energy: f32,
	pub temperature: f32,
}

/// Gas's domain events (`rust_architecture.md` §4.8).
#[vg::events(domain = gas)]
pub enum GasEvent {
	/// A reaction's requirements hold: `reaction` is the gate's dense
	/// registry index (DM resolves it against its own registration order).
	ReactionReady { reaction: u32 },
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
	PressureJump { cell: u32, neighbor: u32, delta: f32 },
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
		if ready != NO_REACTION {
			let cell = ctx.index();
			ctx.emit(GasEvent::CellReactionReady { cell, reaction: ready });
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
		let vis = ctx.reads.value.vis;
		if vis != ctx.reads.value.last_vis {
			let cell = ctx.index();
			ctx.emit(GasEvent::CellVisualChange { cell, vis });
			ctx.writes.value.last_vis = vis;
		}
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
		let my_p = cell.value.pressure_in(cell.capacity);
		let index = ctx.index();
		for slot in &neighbors.0 {
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

/// Reaction gating as an event-emitting law: checks the installed
/// [`gate::Gate`] and, if a reaction's requirements hold, emits the dense
/// registry index of the highest-priority one that does (`E = u32`, the
/// same wire shape `EventKind::ReactionReady`'s `extra` field carries -
/// see `cell.rs`/`world.rs`). Never sleeps on its own: whether a reaction
/// is ready can change from composition or temperature changes the law
/// doesn't itself cause, so it's the caller's (the field's) job to decide
/// activity from its own settle condition, same as today.
pub struct ReactionGateLaw;

impl Law for ReactionGateLaw {
	type Reads = GateReads;
	type Writes = ();
	const NAME: &'static str = "gas_reaction_gate";
	const PERIOD: Period = Period::Frame;

	fn step(ctx: &mut LawCtx<'_, GateReads, ()>, _dt: Seconds) -> Settle {
		let r = ctx.reads;
		if let Some(index) = gate::current().and_then(|g| g.ready(&r.moles, r.energy, r.temperature)) {
			#[allow(clippy::cast_possible_truncation)]
			ctx.emit(GasEvent::ReactionReady { reaction: index as u32 });
		}
		Settle::Active
	}
}

#[cfg(test)]
mod tests {
	use super::*;
	use crate::cell::GasCell;
	use crate::gas::constants::CELL_VOLUME;
	use crate::gas::ids::{GAS_CARBON_DIOXIDE, GAS_OXYGEN};

	fn atmosphere(moles: f64, temp: f32) -> PipeGas {
		let mut g = PipeGas::default();
		g.moles[GAS_OXYGEN] = moles * 0.21;
		g.moles[GAS_CARBON_DIOXIDE] = moles * 0.79;
		g.temperature = temp;
		g.energy = crate::cell::heat_capacity(&g.moles_f32()) as f64 * f64::from(temp);
		g
	}

	fn run_flow(reads: DeviceReads, mut writes: DeviceSides, dt: f32) -> (DeviceSides, Settle) {
		let mut fx = vg_core::law::Effects {
            ledger: vg_core::conservation::Ledger::new(),
            ..Default::default()
        };
		let mut ctx = LawCtx::new(&reads, &mut writes, &mut fx);
		let settle = FlowLaw::step(&mut ctx, Seconds(f64::from(dt)));
		(writes, settle)
	}

	#[test]
	fn flow_law_moves_gas_and_conserves_through_law_ctx() {
		let sides = DeviceSides {
			a: atmosphere(1000.0, 293.0),
			b: PipeGas::default(),
		};
		let before = sides.a.total() + sides.b.total();
		let reads = DeviceReads {
			params: DeviceParams::decode(1, [101.325, 5000.0, 0.0, 0.0]), // pump
			vol_a: 1000.0,
			vol_b: 1000.0,
		};
		let (after, settle) = run_flow(reads, sides, 1.0);
		assert_eq!(settle, Settle::Active, "a fresh pump has somewhere to go");
		assert!((after.a.total() + after.b.total() - before).abs() < 1e-6, "conserves mass");
		assert!(after.b.total() > 0.0, "moved gas toward b");
	}

	#[test]
	fn flow_law_sleeps_once_settled() {
		let sides = DeviceSides {
			a: PipeGas::default(),
			b: PipeGas::default(),
		};
		let reads = DeviceReads {
			params: DeviceParams::None,
			vol_a: 1000.0,
			vol_b: 1000.0,
		};
		let (_, settle) = run_flow(reads, sides, 1.0);
		assert_eq!(settle, Settle::Sleep, "no device law moves nothing and settles");
	}

	/// Serializes tests that call `gate::install` (a process-wide
	/// `static`, `gate.rs`'s own docs): without this, two such tests
	/// running on different threads race each other's install and read
	/// whichever gate happened to land last, a pre-existing flake this
	/// discovered while adding more coverage of the same global.
	static GATE_TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

	#[test]
	fn reaction_gate_law_emits_the_ready_index() {
		let _guard = GATE_TEST_LOCK.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
		let mut gate = gate::Gate::default();
		gate.reactions.push(gate::Requirement {
			min_temp: Some(400.0),
			..Default::default()
		});
		gate.reactions.push(gate::Requirement {
			min_temp: Some(100.0),
			..Default::default()
		});
		gate::install(gate);

		let reads = GateReads {
			moles: [0.0; crate::cell::N],
			energy: 0.0,
			temperature: 250.0,
		};
		let mut writes = ();
		let mut fx = vg_core::law::Effects {
            ledger: vg_core::conservation::Ledger::new(),
            ..Default::default()
        };
		let mut ctx = LawCtx::new(&reads, &mut writes, &mut fx);
		let settle = ReactionGateLaw::step(&mut ctx, Seconds(1.0));
		assert_eq!(settle, Settle::Active);
		// Only the second requirement (min_temp 100) holds at 250K: its
		// dense index is 1.
		assert_eq!(fx.events.decoded::<GasEvent>().map(|(_, e)| e).collect::<Vec<_>>(), vec![GasEvent::ReactionReady { reaction: 1 }]);
	}

	#[test]
	fn reaction_gate_law_emits_nothing_when_no_reaction_is_ready() {
		let _guard = GATE_TEST_LOCK.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
		let mut gate = gate::Gate::default();
		gate.reactions.push(gate::Requirement {
			min_temp: Some(9000.0),
			..Default::default()
		});
		gate::install(gate);

		let reads = GateReads {
			moles: [0.0; crate::cell::N],
			energy: 0.0,
			temperature: 293.0,
		};
		let mut writes = ();
		let mut fx = vg_core::law::Effects {
            ledger: vg_core::conservation::Ledger::new(),
            ..Default::default()
        };
		let mut ctx = LawCtx::new(&reads, &mut writes, &mut fx);
		ReactionGateLaw::step(&mut ctx, Seconds(1.0));
		assert!(fx.events.is_empty());
	}

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
		let mut gate = gate::Gate::default();
		gate.reactions.push(gate::Requirement {
			min_temp: Some(100.0),
			..Default::default()
		});

		let mut moles = [0.0; crate::cell::N];
		moles[GAS_OXYGEN] = 10.0;
		let mut cell = GasCell::new(moles, 250.0);
		cell.ready = gate.ready(&cell.moles, cell.energy, cell.temperature_now()).map_or(NO_REACTION, |i| i as u32);
		let reads = field_cell(cell, CELL_VOLUME, false);
		let mut writes = ();
		let mut fx = cell_fx(42);
		let mut ctx = LawCtx::new(&reads, &mut writes, &mut fx);
		CellReactionReadyLaw::step(&mut ctx, Seconds(1.0));
		assert_eq!(
			fx.events.decoded::<GasEvent>().map(|(_, e)| e).collect::<Vec<_>>(),
			vec![GasEvent::CellReactionReady { cell: 42, reaction: 0 }]
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
			fx.events.decoded::<GasEvent>().map(|(_, e)| e).collect::<Vec<_>>(),
			vec![GasEvent::CellVisualChange { cell: 7, vis: 5 }]
		);
		assert_eq!(writes.value.last_vis, 5, "records the emitted vis as the new baseline");

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
		let hi = GasCell::new([1000.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], 293.0);
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
		let events = fx.events.decoded::<GasEvent>().map(|(_, e)| e).collect::<Vec<_>>();
		assert_eq!(events.len(), 1);
		let GasEvent::PressureJump { cell, neighbor, delta } = events[0] else {
			panic!("expected a PressureJump: {events:?}");
		};
		assert_eq!((cell, neighbor), (3, 10));
		assert!(delta > PRESSURE_EVENT, "{delta}");
	}

	#[test]
	fn spacewind_law_emits_nothing_below_the_threshold() {
		let a = GasCell::new([10.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], 293.0);
		let b = a;
		let reads = (
			field_cell(a, CELL_VOLUME, false),
			Neighbors([Some((5, field_cell(b, CELL_VOLUME, false))), None, None, None, None, None]),
		);
		let mut writes = ();
		let mut fx = cell_fx(0);
		let mut ctx = LawCtx::new(&reads, &mut writes, &mut fx);
		SpacewindLaw::step(&mut ctx, Seconds(1.0));
		assert!(fx.events.is_empty(), "equal pressures: no spacewind");
	}
}
