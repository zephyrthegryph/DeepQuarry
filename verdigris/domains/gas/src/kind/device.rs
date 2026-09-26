//! Pipe device flow/valve as components (`rust_architecture.md` §8.5 step
//! 6, the pipe-device redesign the coordinator approved alongside the gas
//! cutover): replaces `DeviceParams`/`RUST_DEVICE_LAW_*`'s packed
//! `kind, p0..p3` wire encoding with declarative rows DM writes through the
//! generated per-field accessors.
//!
//! A device entity (`Pipes::Device`, `ffi/src/pipes.rs`'s own port/device
//! bookkeeping) may carry several [`DeviceFlow`] rows, each its own entity
//! naming the device with [`LinksTo`] -- the same one-owner/many-parts shape
//! `vg_power::components::SmesInputTerminal` uses for a SMES's several
//! input terminals -- so a filter (a passthrough flow plus a filtered one)
//! or a mixer (two input flows) compose from plain rows instead of a
//! bespoke per-device Rust type. [`DeviceValve`] is the one non-`Flow`
//! shape (a valve's "law" is really the pipe network's own topology merge
//! on connect; this only gates that, exactly as `DeviceParams::Equalize`
//! did): a device has at most one, since opening either merges the whole
//! edge.
//!
//! The actual step math is unchanged from `device.rs`'s `Flow::step`/
//! `equalize` (ported here verbatim as free functions taking the plain
//! enum values these components decode into, so both a component row and
//! `device.rs`'s own tests can drive it without depending on `vg_core`
//! component plumbing).

use vg_core::query::LinksTo;
use vg_core::vg;

use crate::device::{Cmp, Direction, Flow, Rate, Side, Target};

/// [`DeviceFlow::rate_kind`]'s wire values.
pub mod rate_kind {
	pub const VOLUME: u8 = 0;
	pub const POWER: u8 = 1;
	pub const UNLIMITED: u8 = 2;
}

/// [`DeviceFlow::direction`]'s wire values.
pub mod direction {
	pub const FORCED: u8 = 0;
	pub const DOWNHILL: u8 = 1;
}

/// [`DeviceFlow::stop_side`]'s wire values.
pub mod stop_side {
	pub const A: u8 = 0;
	pub const B: u8 = 1;
}

/// [`DeviceFlow::stop_cmp`]'s wire values (`NONE`: the flow has no stop
/// target -- `stop_side`/`stop_kpa` are ignored).
pub mod stop_cmp {
	pub const NONE: u8 = 0;
	pub const AT_LEAST: u8 = 1;
	pub const AT_MOST: u8 = 2;
}

/// One flow on a pipe device edge, declared as data instead of a packed
/// `kind, p0..p3` tuple: a pump is `rate_kind = POWER, direction = FORCED,
/// stop = (B, AT_LEAST, target_kpa)`; a passive gate's input mode is
/// `rate_kind = VOLUME, direction = FORCED, stop = (A, AT_MOST, target)`;
/// an injector is `rate_kind = VOLUME, stop_cmp = NONE`; and so on --
/// `simulation.md` §5's device table, unchanged, just declared instead of
/// packed. `owner = main`: DM sets these synchronously (device settings,
/// vent release/siphon mode switches), same as a pipe port itself.
#[vg::component(domain = gas, kind = 3, dm = "/obj/effect/device_flow_row", owner = main)]
pub struct DeviceFlow {
	/// The owning device entity's raw index (`LinksTo`).
	#[vg(config, default = 0)]
	pub device: u32,
	/// A `1 << gas_id` bitset (0: every gas).
	#[vg(config, default = 0)]
	pub gases: u32,
	/// [`rate_kind`].
	#[vg(config, default = 0)]
	pub rate_kind: u8,
	/// L/s, mol/s or W depending on `rate_kind` (unused for `UNLIMITED`).
	#[vg(config, unit = "mol/s", default = 0.0)]
	pub rate: f32,
	/// [`direction`].
	#[vg(config, default = 0)]
	pub direction: u8,
	/// [`stop_side`] (ignored when `stop_cmp` is `NONE`).
	#[vg(config, default = 0)]
	pub stop_side: u8,
	/// [`stop_cmp`].
	#[vg(config, default = 0)]
	pub stop_cmp: u8,
	#[vg(config, unit = "kPa", default = 0.0)]
	pub stop_kpa: f32,
}

impl LinksTo for DeviceFlow {
	fn linked_index(&self) -> Option<u32> {
		Some(self.device)
	}
}

impl DeviceFlow {
	/// This row as the plain [`Flow`] `device.rs`'s math already runs on.
	#[must_use]
	pub fn flow(&self) -> Flow {
		let rate = match self.rate_kind {
			rate_kind::POWER => Rate::Power(self.rate),
			rate_kind::UNLIMITED => Rate::Unlimited,
			_ => Rate::Volume(self.rate),
		};
		let direction = if self.direction == direction::DOWNHILL {
			Direction::Downhill
		} else {
			Direction::Forced
		};
		let stop = (self.stop_cmp != stop_cmp::NONE).then_some(Target {
			side: if self.stop_side == stop_side::B { Side::B } else { Side::A },
			cmp: if self.stop_cmp == stop_cmp::AT_MOST { Cmp::AtMost } else { Cmp::AtLeast },
			kpa: self.stop_kpa,
		});
		Flow {
			gases: self.gases,
			rate,
			direction,
			stop,
		}
	}
}

/// A device edge's valve gate (open: equalizes, same as `DeviceParams::
/// Equalize { open }`; a valve's actual mixing is the pipe network's own
/// topology merge on connect, this only gates it for the one tick before
/// that merge's next commit catches up). At most one per device -- unlike
/// `DeviceFlow`, a valve doesn't compose with others on the same edge.
#[vg::component(domain = gas, kind = 4, dm = "/obj/effect/device_valve_row", owner = main)]
pub struct DeviceValve {
	/// The owning device entity's raw index (`LinksTo`).
	#[vg(config, default = 0)]
	pub device: u32,
	#[vg(config, default = false)]
	pub open: bool,
}

impl LinksTo for DeviceValve {
	fn linked_index(&self) -> Option<u32> {
		Some(self.device)
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn a_pump_row_decodes_to_the_same_flow_pump_used_to_build_from_params() {
		let row = DeviceFlow {
			device: 0,
			gases: 0,
			rate_kind: rate_kind::POWER,
			rate: 7500.0,
			direction: direction::FORCED,
			stop_side: stop_side::B,
			stop_cmp: stop_cmp::AT_LEAST,
			stop_kpa: 101.325,
		};
		assert_eq!(
			row.flow(),
			Flow {
				gases: 0,
				rate: Rate::Power(7500.0),
				direction: Direction::Forced,
				stop: Some(Target { side: Side::B, cmp: Cmp::AtLeast, kpa: 101.325 }),
			}
		);
	}

	#[test]
	fn an_injector_row_has_no_stop() {
		let row = DeviceFlow {
			device: 0,
			gases: 0,
			rate_kind: rate_kind::VOLUME,
			rate: 200.0,
			direction: direction::FORCED,
			stop_side: stop_side::A,
			stop_cmp: stop_cmp::NONE,
			stop_kpa: 0.0,
		};
		assert_eq!(row.flow().stop, None);
	}

	#[test]
	fn a_downhill_passive_gate_row_decodes_correctly() {
		let row = DeviceFlow {
			device: 0,
			gases: 0,
			rate_kind: rate_kind::VOLUME,
			rate: 200.0,
			direction: direction::DOWNHILL,
			stop_side: stop_side::A,
			stop_cmp: stop_cmp::NONE,
			stop_kpa: 0.0,
		};
		assert_eq!(row.flow().direction, Direction::Downhill);
	}
}
