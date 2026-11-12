//! The pipe devices whose flow law is a component on their own entity, the way the pump went (`kind/pump.rs`,
//! `rust_bindings.md` section 14): a volume pump, a passive gate, a dual-port vent, a vent, a scrubber and an injector.
//!
//! Each device's staging reads its component directly (`ffi/src/pipes.rs`'s `device_law_index`) and derives its [`Flow`] from
//! the settings the component holds, so DM pushes no flow row. What stays in DM is the device's topology (which ports and which
//! turf its edge joins) and the values DM itself owns (`running`: powered, switched on, operable, not welded; a mask built from
//! a gas list), which are declared `input`s the reconciler checks.
//!
//! A turf-facing device (vent, dual-port vent, scrubber, injector) treats the turf as side `A` and its pipe as side `B`; every
//! law below is that device's `Flow` exactly as its DM `push_to_rust()` used to build it, and each has a test that pins it to
//! the old row (`kind::device::DeviceFlow::flow()`).
use vg_core::vg;

use crate::device::{Cmp, Direction, Flow, Rate, Side, Target};

/// The most a volume pump will push its output side to unless its limiter is lifted, kPa.
/// @dm-define VOLUME_PUMP_MAX_OUTPUT_PRESSURE
pub const VOLUME_PUMP_MAX_OUTPUT_PRESSURE: u32 = 9000;

/// A vent's pressure checks (`pressure_checks`): never past the external bound in the room.
/// @dm-define VENT_CHECK_EXTERNAL
pub const VENT_CHECK_EXTERNAL: u8 = 1;
/// A vent's pressure checks: never past the internal bound in the pipe.
/// @dm-define VENT_CHECK_INTERNAL
pub const VENT_CHECK_INTERNAL: u8 = 2;

/// A dual-port vent's pressure checks: the external bound.
/// @dm-define PRESSURE_CHECK_EXTERNAL
pub const PRESSURE_CHECK_EXTERNAL: u8 = 1;
/// A dual-port vent's pressure checks: the input port's minimum.
/// @dm-define PRESSURE_CHECK_INPUT
pub const PRESSURE_CHECK_INPUT: u8 = 2;
/// A dual-port vent's pressure checks: the output port's maximum.
/// @dm-define PRESSURE_CHECK_OUTPUT
pub const PRESSURE_CHECK_OUTPUT: u8 = 4;

/// A passive gate regulating nothing: it flows downhill.
/// @dm-define REGULATE_NONE
pub const REGULATE_NONE: u8 = 0;
/// A passive gate that shuts off when its input side is below the target pressure.
/// @dm-define REGULATE_INPUT
pub const REGULATE_INPUT: u8 = 1;
/// A passive gate that shuts off when its output side is above the target pressure.
/// @dm-define REGULATE_OUTPUT
pub const REGULATE_OUTPUT: u8 = 2;

/// A vent releases gas this many times its own volume a second.
const VENT_FLOWS_PER_SECOND: f32 = 50.0;
/// What a vent's flow never reaches when it has no check on the room: the room fills without bound.
const UNBOUNDED_KPA: f32 = 1e30;

/// The rate a scrubber pulls the gases it scrubs at, L/s.
/// @dm-define MAX_SCRUBBER_FLOWRATE
pub const MAX_SCRUBBER_FLOWRATE: u32 = 200;
/// The rate a scrubber siphons the whole room at, L/s (anything above a cell's volume has no effect).
/// @dm-define MAX_SIPHON_FLOWRATE
pub const MAX_SIPHON_FLOWRATE: u32 = 2500;

fn target(side: Side, cmp: Cmp, kpa: f32) -> Target {
	Target { side, cmp, kpa }
}

/// The stop and limit of a vent-like flow whose turf is side `A` and whose pipe checks sit on side `B`: the external check is the
/// stop, the pipe-side check a cap, a lone pipe-side check becomes the stop, and with no check the room fills without bound
/// (releasing) or drains to nothing (siphoning).
fn turf_vent_targets(
	releasing: bool,
	external: Option<f32>,
	pipe: Option<f32>,
) -> (Target, Option<Target>) {
	let external_cmp = if releasing { Cmp::AtLeast } else { Cmp::AtMost };
	let pipe_cmp = if releasing { Cmp::AtMost } else { Cmp::AtLeast };
	match (external, pipe) {
		(Some(kpa), None) => (target(Side::A, external_cmp, kpa), None),
		(Some(kpa), Some(pipe_kpa)) => (
			target(Side::A, external_cmp, kpa),
			Some(target(Side::B, pipe_cmp, pipe_kpa)),
		),
		(None, Some(pipe_kpa)) => (target(Side::B, pipe_cmp, pipe_kpa), None),
		(None, None) => (
			target(
				Side::A,
				external_cmp,
				if releasing { UNBOUNDED_KPA } else { 0.0 },
			),
			None,
		),
	}
}

/// The volumetric pump: `transfer_rate` litres a second of its input, forced into its output, which a limiter keeps below
/// [`VOLUME_PUMP_MAX_OUTPUT_PRESSURE`] until a multitool lifts it.
#[vg::component(domain = gas, kind = 5, dm = "/obj/machinery/atmospherics/binary/volume_pump")]
pub struct VolumePump {
	#[vg(config, unit = "L/s", range = 0.0..=100000.0, default = 20.0, on_invalid = clamp)]
	pub transfer_rate: f32,
	/// The material's share of the rated pump power the impeller turns into volume (`material_pump_power()` over the rating).
	#[vg(config, range = 0.0..=2.5, default = 1.0, on_invalid = clamp)]
	pub power_scale: f32,
	/// Powered, switched on, operable and between two pipes.
	#[vg(input, from = [power, integrity, construction])]
	pub running: bool,
	/// The limiter is lifted (a multitool): the output side is not capped.
	#[vg(input)]
	pub overclocked: bool,
	#[vg(state, unit = "mol/s")]
	pub flow_rate: f32,
}

impl VolumePump {
	#[must_use]
	pub fn flow(&self) -> Option<Flow> {
		self.running.then_some(Flow {
			gases: 0,
			rate: Rate::Volume(self.transfer_rate * self.power_scale),
			direction: Direction::Forced,
			stop: (!self.overclocked).then_some(target(
				Side::B,
				Cmp::AtLeast,
				VOLUME_PUMP_MAX_OUTPUT_PRESSURE as f32,
			)),
			limit: None,
		})
	}
}

/// The passive gate (a pressure regulator): a one-way valve that flows `set_flow_rate` litres a second while it is unlocked,
/// regulating its input or output side to `target_pressure` or, regulating nothing, going downhill.
#[vg::component(domain = gas, kind = 6, dm = "/obj/machinery/atmospherics/binary/passive_gate")]
pub struct PassiveGate {
	#[vg(config, unit = "kPa", range = 0.0..=15000.0, default = 101.325, on_invalid = clamp)]
	pub target_pressure: f32,
	#[vg(config, unit = "L/s", range = 0.0..=100000.0, default = 500.0, on_invalid = clamp)]
	pub set_flow_rate: f32,
	/// [`REGULATE_NONE`], [`REGULATE_INPUT`] or [`REGULATE_OUTPUT`].
	#[vg(config, default = 2)]
	pub regulate_mode: u8,
	/// The valve is unlocked (it still closes by itself if gas would flow backwards).
	#[vg(input)]
	pub running: bool,
}

impl PassiveGate {
	#[must_use]
	pub fn flow(&self) -> Option<Flow> {
		if !self.running {
			return None;
		}
		let rate = Rate::Volume(self.set_flow_rate);
		Some(match self.regulate_mode {
			REGULATE_INPUT => Flow {
				gases: 0,
				rate,
				direction: Direction::Forced,
				stop: Some(target(Side::A, Cmp::AtMost, self.target_pressure)),
				limit: None,
			},
			REGULATE_OUTPUT => Flow {
				gases: 0,
				rate,
				direction: Direction::Forced,
				stop: Some(target(Side::B, Cmp::AtLeast, self.target_pressure)),
				limit: None,
			},
			_ => Flow {
				gases: 0,
				rate,
				direction: Direction::Downhill,
				stop: None,
				limit: None,
			},
		})
	}
}

/// The dual-port vent: releasing it pushes its input port's gas out to the turf, siphoning it pulls the turf's into its
/// output port, both at `power_rating` and stopping where the enabled checks say.
#[vg::component(domain = gas, kind = 7, dm = "/obj/machinery/atmospherics/binary/dp_vent_pump")]
pub struct DpVentPump {
	#[vg(config, unit = "W", range = 0.0..=60000.0, default = 7500.0, on_invalid = clamp)]
	pub power_rating: f32,
	#[vg(config, unit = "kPa", range = 0.0..=15000.0, default = 101.325, on_invalid = clamp)]
	pub external_pressure_bound: f32,
	#[vg(config, unit = "kPa", range = 0.0..=15000.0, default = 0.0, on_invalid = clamp)]
	pub input_pressure_min: f32,
	#[vg(config, unit = "kPa", range = 0.0..=15000.0, default = 10000.0, on_invalid = clamp)]
	pub output_pressure_max: f32,
	/// The [`PRESSURE_CHECK_EXTERNAL`], [`PRESSURE_CHECK_INPUT`] and [`PRESSURE_CHECK_OUTPUT`] bits that are on.
	#[vg(config, default = 1)]
	pub pressure_checks: u8,
	/// Releasing into the room (1) or siphoning out of it (0): the device's own var, which its look and its edge read too.
	#[vg(input)]
	pub pump_direction: u8,
	#[vg(input, from = [power, integrity, construction])]
	pub running: bool,
	#[vg(state, unit = "mol/s")]
	pub flow_rate: f32,
}

impl DpVentPump {
	#[must_use]
	pub fn flow(&self) -> Option<Flow> {
		if !self.running {
			return None;
		}
		let releasing = self.pump_direction != 0;
		let external = (self.pressure_checks & PRESSURE_CHECK_EXTERNAL != 0)
			.then_some(self.external_pressure_bound);
		let pipe = if releasing {
			(self.pressure_checks & PRESSURE_CHECK_INPUT != 0).then_some(self.input_pressure_min)
		} else {
			(self.pressure_checks & PRESSURE_CHECK_OUTPUT != 0).then_some(self.output_pressure_max)
		};
		let (stop, limit) = turf_vent_targets(releasing, external, pipe);
		Some(Flow {
			gases: 0,
			rate: Rate::Power(self.power_rating),
			direction: Direction::Forced,
			stop: Some(stop),
			limit,
		})
	}
}

/// The air vent: a volume rate (fifty times its own volume a second) between its pipe and the turf it faces, the room side
/// bounded by the external check and the pipe side by the internal one.
#[vg::component(domain = gas, kind = 8, dm = "/obj/machinery/atmospherics/unary/vent_pump")]
pub struct VentPump {
	/// The volume of its pipe-side air, L (a bigger vent moves more): fixed by the vent's type, and the volume of its own air too.
	#[vg(input, unit = "L")]
	pub vent_volume: f32,
	#[vg(config, unit = "kPa", range = 0.0..=15000.0, default = 101.325, on_invalid = clamp)]
	pub external_pressure_bound: f32,
	#[vg(config, unit = "kPa", range = 0.0..=15000.0, default = 0.0, on_invalid = clamp)]
	pub internal_pressure_bound: f32,
	/// The [`VENT_CHECK_EXTERNAL`] and [`VENT_CHECK_INTERNAL`] bits that are on.
	#[vg(config, default = 1)]
	pub pressure_checks: u8,
	/// Releasing into the room (1) or siphoning out of it (0): the device's own var, which its look and its edge read too.
	#[vg(input)]
	pub pump_direction: u8,
	#[vg(input, from = [power, integrity, construction])]
	pub running: bool,
	#[vg(state, unit = "mol/s")]
	pub flow_rate: f32,
}

impl VentPump {
	#[must_use]
	pub fn flow(&self) -> Option<Flow> {
		if !self.running {
			return None;
		}
		let releasing = self.pump_direction != 0;
		let external = (self.pressure_checks & VENT_CHECK_EXTERNAL != 0)
			.then_some(self.external_pressure_bound);
		let pipe = (self.pressure_checks & VENT_CHECK_INTERNAL != 0)
			.then_some(self.internal_pressure_bound);
		let (stop, limit) = turf_vent_targets(releasing, external, pipe);
		Some(Flow {
			gases: 0,
			rate: Rate::Volume(self.vent_volume * VENT_FLOWS_PER_SECOND),
			direction: Direction::Forced,
			stop: Some(stop),
			limit,
		})
	}
}

/// The air scrubber: from the turf into its pipe, the gases in `gas_mask` while it scrubs, everything while it siphons.
#[vg::component(domain = gas, kind = 9, dm = "/obj/machinery/atmospherics/unary/vent_scrubber")]
pub struct Scrubber {
	/// The gases it scrubs (a `1 << gas_id` bitset), built from its gas list.
	#[vg(input)]
	pub gas_mask: u32,
	/// Filtering the gases in `gas_mask` (true) or siphoning everything (false).
	#[vg(input)]
	pub scrubbing: bool,
	#[vg(input, from = [power, integrity, construction])]
	pub running: bool,
	#[vg(state, unit = "mol/s")]
	pub flow_rate: f32,
}

impl Scrubber {
	#[must_use]
	pub fn flow(&self) -> Option<Flow> {
		self.running.then_some(Flow {
			gases: if self.scrubbing { self.gas_mask } else { 0 },
			rate: Rate::Volume(if self.scrubbing {
				MAX_SCRUBBER_FLOWRATE as f32
			} else {
				MAX_SIPHON_FLOWRATE as f32
			}),
			direction: Direction::Forced,
			stop: None,
			limit: None,
		})
	}
}

/// The outlet injector: `volume_rate` litres a second of its pipe's gas forced into the turf it stands on, whatever the room
/// holds.
#[vg::component(domain = gas, kind = 10, dm = "/obj/machinery/atmospherics/unary/outlet_injector")]
pub struct OutletInjector {
	#[vg(config, unit = "L/s", range = 0.0..=100000.0, default = 50.0, on_invalid = clamp)]
	pub volume_rate: f32,
	#[vg(input, from = [power, integrity, construction])]
	pub running: bool,
	#[vg(state, unit = "mol/s")]
	pub flow_rate: f32,
}

impl OutletInjector {
	#[must_use]
	pub fn flow(&self) -> Option<Flow> {
		self.running.then_some(Flow {
			gases: 0,
			rate: Rate::Volume(self.volume_rate),
			direction: Direction::Forced,
			stop: Some(target(Side::A, Cmp::AtLeast, UNBOUNDED_KPA)),
			limit: None,
		})
	}
}

#[cfg(test)]
mod tests {
	use super::*;
	use crate::kind::device::{direction, rate_kind, stop_cmp, stop_side, DeviceFlow};

	/// The `DeviceFlow` row DM pushed for a flow (`rust_set_device_flow()`): the oracle every law here must equal.
	#[allow(clippy::too_many_arguments)]
	fn row(
		gases: u32,
		kind: u8,
		rate: f32,
		dir: u8,
		stop: (u8, u8, f32),
		limit: (u8, u8, f32),
	) -> Flow {
		DeviceFlow {
			gases,
			rate_kind: kind,
			rate,
			direction: dir,
			stop_side: stop.0,
			stop_cmp: stop.1,
			stop_kpa: stop.2,
			limit_side: limit.0,
			limit_cmp: limit.1,
			limit_kpa: limit.2,
			..DeviceFlow::default()
		}
		.flow()
	}

	const NO_LIMIT: (u8, u8, f32) = (stop_side::B, stop_cmp::NONE, 0.0);

	fn volume_pump(running: bool, overclocked: bool) -> VolumePump {
		VolumePump {
			transfer_rate: 20.0,
			power_scale: 1.5,
			running,
			overclocked,
			flow_rate: 0.0,
		}
	}

	#[test]
	fn a_volume_pump_is_the_old_forced_volume_row_with_its_output_cap() {
		assert_eq!(
			volume_pump(true, false).flow(),
			Some(row(
				0,
				rate_kind::VOLUME,
				30.0,
				direction::FORCED,
				(stop_side::B, stop_cmp::AT_LEAST, 9000.0),
				NO_LIMIT
			))
		);
	}

	#[test]
	fn an_overclocked_volume_pump_has_no_output_cap() {
		assert_eq!(
			volume_pump(true, true).flow(),
			Some(row(
				0,
				rate_kind::VOLUME,
				30.0,
				direction::FORCED,
				(stop_side::A, stop_cmp::NONE, 0.0),
				NO_LIMIT
			))
		);
	}

	#[test]
	fn a_stopped_volume_pump_has_no_flow() {
		assert_eq!(volume_pump(false, false).flow(), None);
	}

	fn gate(mode: u8, unlocked: bool) -> PassiveGate {
		PassiveGate {
			target_pressure: 150.0,
			set_flow_rate: 500.0,
			regulate_mode: mode,
			running: unlocked,
		}
	}

	#[test]
	fn a_passive_gate_matches_its_three_old_rows() {
		assert_eq!(
			gate(REGULATE_INPUT, true).flow(),
			Some(row(
				0,
				rate_kind::VOLUME,
				500.0,
				direction::FORCED,
				(stop_side::A, stop_cmp::AT_MOST, 150.0),
				NO_LIMIT
			))
		);
		assert_eq!(
			gate(REGULATE_OUTPUT, true).flow(),
			Some(row(
				0,
				rate_kind::VOLUME,
				500.0,
				direction::FORCED,
				(stop_side::B, stop_cmp::AT_LEAST, 150.0),
				NO_LIMIT
			))
		);
		assert_eq!(
			gate(REGULATE_NONE, true).flow(),
			Some(row(
				0,
				rate_kind::VOLUME,
				500.0,
				direction::DOWNHILL,
				(stop_side::A, stop_cmp::NONE, 0.0),
				NO_LIMIT
			))
		);
	}

	#[test]
	fn a_locked_passive_gate_has_no_flow() {
		assert_eq!(gate(REGULATE_OUTPUT, false).flow(), None);
	}

	fn dp(checks: u8, releasing: bool) -> DpVentPump {
		DpVentPump {
			power_rating: 7500.0,
			external_pressure_bound: 101.0,
			input_pressure_min: 20.0,
			output_pressure_max: 5000.0,
			pressure_checks: checks,
			pump_direction: u8::from(releasing),
			running: true,
			flow_rate: 0.0,
		}
	}

	#[test]
	fn a_dual_port_vent_matches_the_old_rows_for_every_check_set() {
		let power = |stop, limit| row(0, rate_kind::POWER, 7500.0, direction::FORCED, stop, limit);
		// Releasing: external check stops, the input minimum caps.
		assert_eq!(
			dp(PRESSURE_CHECK_EXTERNAL | PRESSURE_CHECK_INPUT, true).flow(),
			Some(power(
				(stop_side::A, stop_cmp::AT_LEAST, 101.0),
				(stop_side::B, stop_cmp::AT_MOST, 20.0)
			))
		);
		// Releasing with only the input minimum: it is the stop.
		assert_eq!(
			dp(PRESSURE_CHECK_INPUT, true).flow(),
			Some(power((stop_side::B, stop_cmp::AT_MOST, 20.0), NO_LIMIT))
		);
		// Releasing with no check: the turf fills without bound.
		assert_eq!(
			dp(0, true).flow(),
			Some(power((stop_side::A, stop_cmp::AT_LEAST, 1e30), NO_LIMIT))
		);
		// Siphoning: external drains down, the output maximum caps.
		assert_eq!(
			dp(PRESSURE_CHECK_EXTERNAL | PRESSURE_CHECK_OUTPUT, false).flow(),
			Some(power(
				(stop_side::A, stop_cmp::AT_MOST, 101.0),
				(stop_side::B, stop_cmp::AT_LEAST, 5000.0)
			))
		);
		assert_eq!(
			dp(PRESSURE_CHECK_OUTPUT, false).flow(),
			Some(power((stop_side::B, stop_cmp::AT_LEAST, 5000.0), NO_LIMIT))
		);
		// Siphoning with no check: the turf drains to nothing.
		assert_eq!(
			dp(0, false).flow(),
			Some(power((stop_side::A, stop_cmp::AT_MOST, 0.0), NO_LIMIT))
		);
		// The input minimum means nothing while siphoning, the output maximum nothing while releasing.
		assert_eq!(dp(PRESSURE_CHECK_INPUT, false).flow(), dp(0, false).flow());
		assert_eq!(dp(PRESSURE_CHECK_OUTPUT, true).flow(), dp(0, true).flow());
	}

	#[test]
	fn a_stopped_dual_port_vent_has_no_flow() {
		let mut vent = dp(1, true);
		vent.running = false;
		assert_eq!(vent.flow(), None);
	}

	fn vent(checks: u8, releasing: bool) -> VentPump {
		VentPump {
			vent_volume: 200.0,
			external_pressure_bound: 101.0,
			internal_pressure_bound: 2000.0,
			pressure_checks: checks,
			pump_direction: u8::from(releasing),
			running: true,
			flow_rate: 0.0,
		}
	}

	#[test]
	fn a_vent_matches_the_old_rows_for_every_check_set() {
		let volume = |stop, limit| {
			row(
				0,
				rate_kind::VOLUME,
				10_000.0,
				direction::FORCED,
				stop,
				limit,
			)
		};
		let both = VENT_CHECK_EXTERNAL | VENT_CHECK_INTERNAL;
		assert_eq!(
			vent(both, true).flow(),
			Some(volume(
				(stop_side::A, stop_cmp::AT_LEAST, 101.0),
				(stop_side::B, stop_cmp::AT_MOST, 2000.0)
			))
		);
		assert_eq!(
			vent(both, false).flow(),
			Some(volume(
				(stop_side::A, stop_cmp::AT_MOST, 101.0),
				(stop_side::B, stop_cmp::AT_LEAST, 2000.0)
			))
		);
		assert_eq!(
			vent(VENT_CHECK_EXTERNAL, true).flow(),
			Some(volume((stop_side::A, stop_cmp::AT_LEAST, 101.0), NO_LIMIT))
		);
		assert_eq!(
			vent(VENT_CHECK_INTERNAL, false).flow(),
			Some(volume((stop_side::B, stop_cmp::AT_LEAST, 2000.0), NO_LIMIT))
		);
		assert_eq!(
			vent(0, true).flow(),
			Some(volume((stop_side::A, stop_cmp::AT_LEAST, 1e30), NO_LIMIT))
		);
		assert_eq!(
			vent(0, false).flow(),
			Some(volume((stop_side::A, stop_cmp::AT_MOST, 0.0), NO_LIMIT))
		);
	}

	#[test]
	fn a_vent_moves_fifty_times_its_volume_a_second() {
		let mut big = vent(1, true);
		big.vent_volume = 1000.0;
		assert_eq!(big.flow().map(|f| f.rate), Some(Rate::Volume(50_000.0)));
	}

	#[test]
	fn a_scrubber_matches_its_old_scrubbing_and_siphoning_rows() {
		let mut s = Scrubber {
			gas_mask: 0b1010,
			scrubbing: true,
			running: true,
			flow_rate: 0.0,
		};
		assert_eq!(
			s.flow(),
			Some(row(
				0b1010,
				rate_kind::VOLUME,
				200.0,
				direction::FORCED,
				(stop_side::A, stop_cmp::NONE, 0.0),
				NO_LIMIT
			))
		);
		s.scrubbing = false;
		assert_eq!(
			s.flow(),
			Some(row(
				0,
				rate_kind::VOLUME,
				2500.0,
				direction::FORCED,
				(stop_side::A, stop_cmp::NONE, 0.0),
				NO_LIMIT
			))
		);
		s.running = false;
		assert_eq!(s.flow(), None);
	}

	#[test]
	fn an_injector_matches_its_old_row() {
		let mut i = OutletInjector {
			volume_rate: 75.0,
			running: true,
			flow_rate: 0.0,
		};
		assert_eq!(
			i.flow(),
			Some(row(
				0,
				rate_kind::VOLUME,
				75.0,
				direction::FORCED,
				(stop_side::A, stop_cmp::AT_LEAST, 1e30),
				NO_LIMIT
			))
		);
		i.running = false;
		assert_eq!(i.flow(), None);
	}
}
