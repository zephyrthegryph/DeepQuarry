//! The pump component: the reference for `#[vg::component]` (`rust_architecture.md` §5).
use vg_core::vg;

use crate::device::{Direction, Flow, Rate, Side, Target, Cmp};

#[vg::component(domain = gas, kind = 1, dm = "/obj/machinery/atmospherics/binary/pump")]
pub struct Pump {
	#[vg(config, unit = "kPa", range = 0.0..=15000.0, default = 101.325, on_invalid = clamp)]
	pub target_pressure: f32,
	#[vg(config, unit = "W", range = 0.0..=60000.0, default = 7500.0, on_invalid = clamp)]
	pub power_rating: f32,
	#[vg(config, default = false)]
	pub on: bool,
	#[vg(input, from = [construction, integrity])]
	pub operable: bool,
	#[vg(state, unit = "mol/s")]
	pub flow_rate: f32,
}

#[vg::query(Pump, ui = [target_pressure, power_rating, on, flow_rate])]
#[allow(dead_code)]
struct PumpQuery;

#[vg::events(Pump)]
pub enum PumpEvent {
	TargetReached,
	Starved,
}

impl Pump {
	/// The flow law this pump runs (`simulation.md` section5, the pump row): isothermal compression power against its own
	/// target on the output side. `None` while it is off or not operable, so a pump needs no flow row of its own: the
	/// device staging reads this component directly (`rust_bindings.md` section14 step 2).
	#[must_use]
	pub fn flow(&self) -> Option<Flow> {
		(self.on && self.operable).then_some(Flow {
			gases: 0,
			rate: Rate::Power(self.power_rating),
			direction: Direction::Forced,
			stop: Some(Target {
				side: Side::B,
				cmp: Cmp::AtLeast,
				kpa: self.target_pressure,
			}),
			limit: None,
		})
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	fn pump(on: bool, operable: bool) -> Pump {
		Pump {
			target_pressure: 101.325,
			power_rating: 7500.0,
			on,
			operable,
			flow_rate: 0.0,
		}
	}

	#[test]
	fn a_running_pump_is_the_forced_power_flow_against_its_target() {
		assert_eq!(
			pump(true, true).flow(),
			Some(Flow {
				gases: 0,
				rate: Rate::Power(7500.0),
				direction: Direction::Forced,
				stop: Some(Target { side: Side::B, cmp: Cmp::AtLeast, kpa: 101.325 }),
				limit: None,
			})
		);
	}

	#[test]
	fn the_pump_flow_equals_the_device_flow_row_dm_used_to_forward() {
		use crate::kind::device::{DeviceFlow, direction, rate_kind, stop_cmp, stop_side};
		let row = DeviceFlow {
			rate_kind: rate_kind::POWER,
			rate: 7500.0,
			direction: direction::FORCED,
			stop_side: stop_side::B,
			stop_cmp: stop_cmp::AT_LEAST,
			stop_kpa: 101.325,
			..DeviceFlow::default()
		};
		assert_eq!(pump(true, true).flow(), Some(row.flow()));
	}

	#[test]
	fn an_off_or_inoperable_pump_has_no_flow() {
		assert_eq!(pump(false, true).flow(), None);
		assert_eq!(pump(true, false).flow(), None);
	}
}
