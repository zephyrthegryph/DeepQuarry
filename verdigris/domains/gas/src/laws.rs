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

use vg_core::law::{Law, LawCtx, Period, Settle};
use vg_core::units::Seconds;
use vg_core::vg;

use crate::device::{self, DeviceParams, StepReport};
use crate::gate;
use crate::pipes::PipeGas;

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

	#[test]
	fn reaction_gate_law_emits_the_ready_index() {
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
}
