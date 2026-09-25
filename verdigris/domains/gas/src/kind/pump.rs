//! The pump component: the reference for `#[vg::component]` (`rust_architecture.md` §5).
use vg_core::vg;

#[vg::component(domain = gas, kind = 1, dm = "/obj/machinery/atmospherics/binary/pump")]
pub struct Pump {
	#[vg(config, unit = "kPa", range = 0.0..=15000.0, default = 101.325, on_invalid = clamp)]
	target_pressure: f32,
	#[vg(config, unit = "W", range = 0.0..=60000.0, default = 7500.0, on_invalid = clamp)]
	power_rating: f32,
	#[vg(config, default = false)]
	on: bool,
	#[vg(input, from = [construction, integrity])]
	operable: bool,
	#[vg(state, unit = "mol/s")]
	flow_rate: f32,
}

#[vg::query(Pump, ui = [target_pressure, power_rating, on, flow_rate])]
#[allow(dead_code)]
struct PumpQuery;

#[vg::events(Pump)]
pub enum PumpEvent {
	TargetReached,
	Starved,
}
