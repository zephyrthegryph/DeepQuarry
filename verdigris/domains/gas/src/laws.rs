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
		if ready != NO_REACTION && !ctx.reads.reservoir {
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
