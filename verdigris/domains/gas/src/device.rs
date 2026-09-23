//! Atmos device flow laws (`simulation.md` §5, roadmap M2).
//!
//! A device becomes a device edge (`vg_core::network::Device`) between two
//! [`PipeGas`] payloads — two pipe regions, or a region and (once the field
//! bridge lands) a turf cell. Each edge carries a [`DeviceParams`], set by a
//! DM command whenever the player changes a setting; [`step`] runs every
//! edge's flow law once per gas tick inside the pipe network's step,
//! replacing the DM `process()` procs deleted by this item.
//!
//! Every law here is a pure function over two mixtures, their volumes and a
//! timestep: it never allocates, never talks to DM and always conserves
//! mass and energy (moved gas leaves one side and arrives whole in the
//! other, via [`PipeGas::carve`]/[`PipeGas::add`]).

use crate::cell::N;
use crate::gas::constants::{GAS_MIN_MOLES, MINIMUM_HEAT_CAPACITY, R_IDEAL_GAS_EQUATION};
use crate::pipes::PipeGas;

/// A passive gate or canister regulator's target.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Regulate {
	/// Shuts off once the input side falls to the target.
	Input,
	/// Shuts off once the output side reaches the target.
	#[default]
	Output,
	/// No target: equalizes both sides.
	Equalize,
}

/// A vent pump's direction.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum VentMode {
	/// Pumps from `a` (the turf/region side) into `b` (the network side).
	Siphon,
	/// Pumps from `b` (the network side) into `a`.
	#[default]
	Release,
}

/// One device edge's flow law and parameters (`Pipes::Device`,
/// `simulation.md` §5's table). `a` is always the law's nominal "input" and
/// `b` its "output"; DM chooses which physical port is which when it adds
/// the edge.
#[derive(Clone, Debug, Default, PartialEq)]
pub enum DeviceParams {
	/// No device on this edge (an inert connection, or a not-yet-configured
	/// slot). [`step`] is a no-op.
	#[default]
	None,
	/// Moves gas towards a target pressure on `b`, limited by power:
	/// isothermal work `n R T ln(P2/P1)`.
	Pump { target_kpa: f32, power_w: f32 },
	/// A fixed volume per second, uncapped by power.
	VolumePump { rate_l_s: f32 },
	/// A one-way regulator: flows from `a` to `b` while the regulated side
	/// has not met `target_kpa`, up to `max_rate_l_s`.
	PassiveGate {
		mode: Regulate,
		target_kpa: f32,
		max_rate_l_s: f32,
	},
	/// Equalizes while `open`; otherwise blocks (a valve or shutoff valve).
	Valve { open: bool },
	/// Pumps between `a` (the turf/region it faces) and `b` (the network),
	/// bounded so `a` stays within `[min_kpa, max_kpa]`.
	VentPump {
		mode: VentMode,
		min_kpa: f32,
		max_kpa: f32,
		max_rate_l_s: f32,
	},
	/// Removes the gases in `mask` (a `1 << gas_id` bitset) from `a` into
	/// `b` at up to `rate_l_s`; `siphon` removes everything instead.
	Scrubber { mask: u32, rate_l_s: f32, siphon: bool },
	/// Injects from `a` into `b` at a fixed rate (a canister outlet).
	Injector { rate_l_s: f32 },
	/// Splits `a` into `b`, moving only the gases in `mask` at up to
	/// `rate_l_s`; everything else stays on `a` (the other trinary leg is a
	/// second device edge DM adds alongside this one).
	Filter { mask: u32, rate_l_s: f32 },
	/// Exchanges thermal energy between `a` and `b` at a fixed conductance,
	/// without moving gas.
	HeatExchanger { conductance_w_k: f32 },
	/// A canister/connector pressure regulator: flows from `a` to `b` until
	/// `b` reaches `release_kpa`, uncapped by power (tanks are effectively
	/// infinite reservoirs on `a`).
	PressureRegulator { release_kpa: f32 },
}

/// What a step did, for DM's stalled/target-reached/filter-saturated events
/// and power billing.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct StepReport {
	/// Moles moved from `a` to `b` (negative: `b` to `a`).
	pub moles: f64,
	/// Power actually drawn (W), for `simulation.md`'s "power draw is
	/// published to the power domain".
	pub power_w: f32,
	/// The regulated side reached its target and flow stopped this tick.
	pub target_reached: bool,
}

fn pressure(gas: &PipeGas, volume: f64) -> f32 {
	if volume <= 0.0 {
		return 0.0;
	}
	let t = gas.temperature_now();
	((gas.total() * f64::from(R_IDEAL_GAS_EQUATION) * f64::from(t)) / volume) as f32
}

/// Moves `moles` from `from` to `to` (clamped to what `from` holds),
/// preserving composition and energy on both sides.
fn transfer(from: &mut PipeGas, to: &mut PipeGas, moles: f64) -> f64 {
	let total = from.total();
	if total <= GAS_MIN_MOLES.into() || moles <= 0.0 {
		return 0.0;
	}
	let moles = moles.min(total);
	let f = moles / total;
	let carved = from.carve(f);
	let moved = carved.total();
	to.add(&carved);
	moved
}

/// Runs one device's flow law for `dt` seconds, moving gas (and energy)
/// between `a` and `b` in place. Returns what happened.
#[must_use]
pub fn step(
	params: &DeviceParams,
	a: &mut PipeGas,
	vol_a: f64,
	b: &mut PipeGas,
	vol_b: f64,
	dt: f32,
) -> StepReport {
	if dt <= 0.0 {
		return StepReport::default();
	}
	match *params {
		DeviceParams::None => StepReport::default(),
		DeviceParams::Pump { target_kpa, power_w } => step_pump(a, vol_a, b, vol_b, dt, target_kpa, power_w),
		DeviceParams::VolumePump { rate_l_s } => {
			let moles = moles_for_volume(a, vol_a, f64::from(rate_l_s) * f64::from(dt));
			let moved = transfer(a, b, moles);
			StepReport {
				moles: moved,
				..Default::default()
			}
		}
		DeviceParams::PassiveGate {
			mode,
			target_kpa,
			max_rate_l_s,
		} => step_passive_gate(a, vol_a, b, vol_b, dt, mode, target_kpa, max_rate_l_s),
		DeviceParams::Valve { open } => {
			if !open {
				return StepReport::default();
			}
			let moved = equalize(a, vol_a, b, vol_b);
			StepReport {
				moles: moved,
				..Default::default()
			}
		}
		DeviceParams::VentPump {
			mode,
			min_kpa,
			max_kpa,
			max_rate_l_s,
		} => step_vent(a, vol_a, b, vol_b, dt, mode, min_kpa, max_kpa, max_rate_l_s),
		DeviceParams::Scrubber { mask, rate_l_s, siphon } => {
			step_scrubber(a, vol_a, b, dt, mask, rate_l_s, siphon)
		}
		DeviceParams::Injector { rate_l_s } => {
			let moles = moles_for_volume(a, vol_a, f64::from(rate_l_s) * f64::from(dt));
			let moved = transfer(a, b, moles);
			StepReport {
				moles: moved,
				..Default::default()
			}
		}
		DeviceParams::Filter { mask, rate_l_s } => step_filter(a, vol_a, b, dt, mask, rate_l_s),
		DeviceParams::HeatExchanger { conductance_w_k } => step_heat_exchanger(a, b, dt, conductance_w_k),
		DeviceParams::PressureRegulator { release_kpa } => step_regulator(a, vol_a, b, vol_b, release_kpa),
	}
}

/// The moles of `gas` a volume (L) at its current density represents.
fn moles_for_volume(gas: &PipeGas, volume: f64, take_l: f64) -> f64 {
	if volume <= 0.0 {
		return 0.0;
	}
	gas.total() * (take_l / volume).clamp(0.0, 1.0)
}

/// Moves gas from the higher- to the lower-pressure side until both are
/// equal (a valve or an unregulated passive gate).
fn equalize(a: &mut PipeGas, vol_a: f64, b: &mut PipeGas, vol_b: f64) -> f64 {
	let (pa, pb) = (pressure(a, vol_a), pressure(b, vol_b));
	if (pa - pb).abs() < 0.01 || vol_a <= 0.0 || vol_b <= 0.0 {
		return 0.0;
	}
	// Moles that bring both sides to the same pressure, assuming equal
	// temperature (a fair approximation for one tick's flow).
	let (from, to, vol_from, vol_to, sign): (&mut PipeGas, &mut PipeGas, f64, f64, f64) = if pa > pb {
		(a, b, vol_a, vol_b, 1.0)
	} else {
		(b, a, vol_b, vol_a, -1.0)
	};
	let t = from.temperature_now().max(1.0);
	let delta_p = (pressure(from, vol_from) - pressure(to, vol_to)).max(0.0);
	let moles = f64::from(delta_p) * (vol_from * vol_to / (vol_from + vol_to))
		/ (f64::from(R_IDEAL_GAS_EQUATION) * f64::from(t));
	transfer(from, to, moles) * sign
}

fn step_pump(a: &mut PipeGas, vol_a: f64, b: &mut PipeGas, vol_b: f64, dt: f32, target_kpa: f32, power_w: f32) -> StepReport {
	let pb = pressure(b, vol_b);
	if pb >= target_kpa || a.total() <= GAS_MIN_MOLES.into() {
		return StepReport {
			target_reached: pb >= target_kpa,
			..Default::default()
		};
	}
	let pa = pressure(a, vol_a).max(0.01);
	let t = a.temperature_now().max(1.0);
	// Moles that would bring `b` to the target pressure.
	let needed = f64::from((target_kpa - pb).max(0.0)) * vol_b / (f64::from(R_IDEAL_GAS_EQUATION) * f64::from(t));
	// Power-limited moles: isothermal compression work n R T ln(P2/P1).
	let ratio = (target_kpa.max(pa) / pa).max(1.0 + 1e-6);
	let work_per_mole = f64::from(R_IDEAL_GAS_EQUATION) * f64::from(t) * f64::from(ratio.ln());
	let energy_budget = f64::from(power_w) * f64::from(dt);
	let power_limited = if work_per_mole > 0.0 {
		energy_budget / work_per_mole
	} else {
		f64::INFINITY
	};
	let moles = needed.min(power_limited).min(a.total());
	let moved = transfer(a, b, moles);
	let power_used = if moved > 0.0 {
		((moved * work_per_mole) / f64::from(dt)) as f32
	} else {
		0.0
	};
	StepReport {
		moles: moved,
		power_w: power_used.min(power_w),
		target_reached: pressure(b, vol_b) >= target_kpa,
	}
}

fn step_passive_gate(
	a: &mut PipeGas,
	vol_a: f64,
	b: &mut PipeGas,
	vol_b: f64,
	dt: f32,
	mode: Regulate,
	target_kpa: f32,
	max_rate_l_s: f32,
) -> StepReport {
	let (pa, pb) = (pressure(a, vol_a), pressure(b, vol_b));
	let (delta, reached) = match mode {
		Regulate::Input => (pa - target_kpa, pa <= target_kpa),
		Regulate::Output => (target_kpa - pb, pb >= target_kpa),
		Regulate::Equalize => (pa - pb, (pa - pb).abs() < 0.01),
	};
	if delta <= 0.01 {
		return StepReport {
			target_reached: reached,
			..Default::default()
		};
	}
	let cap = moles_for_volume(a, vol_a, f64::from(max_rate_l_s) * f64::from(dt));
	let moles = match mode {
		Regulate::Equalize => {
			let moved = equalize(a, vol_a, b, vol_b);
			return StepReport {
				moles: moved,
				target_reached: false,
				..Default::default()
			};
		}
		_ => {
			let t = a.temperature_now().max(1.0);
			let by_target =
				f64::from(delta) * (vol_a * vol_b / (vol_a + vol_b)) / (f64::from(R_IDEAL_GAS_EQUATION) * f64::from(t));
			by_target.min(cap)
		}
	};
	let moved = transfer(a, b, moles);
	StepReport {
		moles: moved,
		target_reached: false,
		..Default::default()
	}
}

fn step_vent(
	a: &mut PipeGas,
	vol_a: f64,
	b: &mut PipeGas,
	vol_b: f64,
	dt: f32,
	mode: VentMode,
	min_kpa: f32,
	max_kpa: f32,
	max_rate_l_s: f32,
) -> StepReport {
	let pa = pressure(a, vol_a);
	match mode {
		VentMode::Release => {
			if pa >= max_kpa {
				return StepReport {
					target_reached: true,
					..Default::default()
				};
			}
			let t = b.temperature_now().max(1.0);
			let needed =
				f64::from(max_kpa - pa) * vol_a / (f64::from(R_IDEAL_GAS_EQUATION) * f64::from(t));
			let cap = moles_for_volume(b, vol_b, f64::from(max_rate_l_s) * f64::from(dt));
			let moved = transfer(b, a, needed.min(cap));
			StepReport {
				moles: -moved,
				target_reached: pressure(a, vol_a) >= max_kpa,
				..Default::default()
			}
		}
		VentMode::Siphon => {
			if pa <= min_kpa {
				return StepReport {
					target_reached: true,
					..Default::default()
				};
			}
			let t = a.temperature_now().max(1.0);
			let needed =
				f64::from(pa - min_kpa) * vol_a / (f64::from(R_IDEAL_GAS_EQUATION) * f64::from(t));
			let cap = moles_for_volume(a, vol_a, f64::from(max_rate_l_s) * f64::from(dt));
			let moved = transfer(a, b, needed.min(cap));
			StepReport {
				moles: moved,
				target_reached: pressure(a, vol_a) <= min_kpa,
				..Default::default()
			}
		}
	}
}

fn step_scrubber(a: &mut PipeGas, vol_a: f64, b: &mut PipeGas, dt: f32, mask: u32, rate_l_s: f32, siphon: bool) -> StepReport {
	if siphon {
		let moles = moles_for_volume(a, vol_a, f64::from(rate_l_s) * f64::from(dt));
		let moved = transfer(a, b, moles);
		return StepReport {
			moles: moved,
			..Default::default()
		};
	}
	// Scrub only the masked gases: carve their share of the take volume,
	// proportional to each masked gas's fraction of the total.
	let take_l = f64::from(rate_l_s) * f64::from(dt);
	if vol_a <= 0.0 || take_l <= 0.0 {
		return StepReport::default();
	}
	let total = a.total();
	if total <= GAS_MIN_MOLES.into() {
		return StepReport::default();
	}
	let masked: f64 = (0..N)
		.filter(|i| mask & (1 << i) != 0)
		.map(|i| a.moles[i])
		.sum();
	if masked <= GAS_MIN_MOLES.into() {
		return StepReport::default();
	}
	let take_moles = (total * (take_l / vol_a).clamp(0.0, 1.0)).min(masked);
	let f = (take_moles / masked).clamp(0.0, 1.0);
	let mut carved = PipeGas {
		temperature: a.temperature_now(),
		..PipeGas::default()
	};
	let mut removed_energy_frac = 0.0f64;
	for i in 0..N {
		if mask & (1 << i) != 0 {
			let amt = a.moles[i] * f;
			carved.moles[i] = amt;
			a.moles[i] -= amt;
			removed_energy_frac += amt;
		}
	}
	let e = a.energy * (removed_energy_frac / total.max(f64::from(GAS_MIN_MOLES)));
	carved.energy = e;
	a.energy -= e;
	let moved = carved.total();
	b.add(&carved);
	StepReport {
		moles: moved,
		..Default::default()
	}
}

fn step_filter(a: &mut PipeGas, vol_a: f64, b: &mut PipeGas, dt: f32, mask: u32, rate_l_s: f32) -> StepReport {
	// Same masked-carve as the scrubber's filtered mode; kept separate
	// because filters and scrubbers have independent parameter sets and
	// events (filter saturation vs. siphon).
	step_scrubber(a, vol_a, b, dt, mask, rate_l_s, false)
}

fn step_heat_exchanger(a: &mut PipeGas, b: &mut PipeGas, dt: f32, conductance_w_k: f32) -> StepReport {
	if conductance_w_k <= 0.0 {
		return StepReport::default();
	}
	let (ta, tb) = (a.temperature_now(), b.temperature_now());
	let delta = ta - tb;
	if delta.abs() < 0.01 {
		return StepReport::default();
	}
	let ca = crate::cell::heat_capacity(&a.moles_f32());
	let cb = crate::cell::heat_capacity(&b.moles_f32());
	if ca <= MINIMUM_HEAT_CAPACITY || cb <= MINIMUM_HEAT_CAPACITY {
		return StepReport::default();
	}
	let mut energy = f64::from(conductance_w_k) * f64::from(delta) * f64::from(dt);
	// Never overshoot past thermal equilibrium in one tick.
	let equilibrium_energy = f64::from(delta) / (1.0 / f64::from(ca) + 1.0 / f64::from(cb));
	energy = energy.clamp(-equilibrium_energy.abs(), equilibrium_energy.abs());
	a.energy -= energy;
	b.energy += energy;
	StepReport {
		power_w: (energy / f64::from(dt)) as f32,
		..Default::default()
	}
}

fn step_regulator(a: &mut PipeGas, _vol_a: f64, b: &mut PipeGas, vol_b: f64, release_kpa: f32) -> StepReport {
	let pb = pressure(b, vol_b);
	if pb >= release_kpa || a.total() <= GAS_MIN_MOLES.into() {
		return StepReport {
			target_reached: pb >= release_kpa,
			..Default::default()
		};
	}
	let t = a.temperature_now().max(1.0);
	let needed = f64::from((release_kpa - pb).max(0.0)) * vol_b / (f64::from(R_IDEAL_GAS_EQUATION) * f64::from(t));
	let moved = transfer(a, b, needed);
	StepReport {
		moles: moved,
		target_reached: pressure(b, vol_b) >= release_kpa,
		..Default::default()
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

	fn total(gas: &PipeGas) -> f64 {
		gas.total()
	}

	#[test]
	fn valve_closed_moves_nothing() {
		let mut a = atmosphere(100.0, 293.0);
		let mut b = PipeGas::default();
		let before = total(&a) + total(&b);
		let r = step(&DeviceParams::Valve { open: false }, &mut a, 100.0, &mut b, 100.0, 1.0);
		assert_eq!(r.moles, 0.0);
		assert!((total(&a) + total(&b) - before).abs() < 1e-9);
		assert!((total(&b)).abs() < 1e-9);
	}

	#[test]
	fn valve_open_equalizes_and_conserves() {
		let mut a = atmosphere(100.0, 293.0);
		let mut b = PipeGas::default();
		let before = total(&a) + total(&b);
		for _ in 0..500 {
			let _ = step(&DeviceParams::Valve { open: true }, &mut a, 100.0, &mut b, 100.0, 1.0);
		}
		assert!((total(&a) + total(&b) - before).abs() < 1e-6, "conserves mass");
		// Equal volumes at equal starting temperature converge to equal moles.
		assert!((total(&a) - total(&b)).abs() < 0.5, "equalized: {} vs {}", total(&a), total(&b));
	}

	#[test]
	fn pump_moves_towards_target_and_conserves() {
		let mut a = atmosphere(1000.0, 293.0);
		let mut b = PipeGas::default();
		let before = total(&a) + total(&b);
		let params = DeviceParams::Pump {
			target_kpa: 101.325,
			power_w: 5000.0,
		};
		for _ in 0..200 {
			let _ = step(&params, &mut a, 1000.0, &mut b, 1000.0, 1.0);
		}
		assert!((total(&a) + total(&b) - before).abs() < 1e-6);
		assert!(pressure(&b, 1000.0) <= 101.325 + 0.5, "does not overshoot target");
		assert!(pressure(&b, 1000.0) > 50.0, "made real progress towards target");
	}

	#[test]
	fn pump_at_target_stalls() {
		let mut a = atmosphere(10.0, 293.0);
		let mut b = atmosphere(10000.0, 293.0);
		let params = DeviceParams::Pump {
			target_kpa: 50.0,
			power_w: 5000.0,
		};
		let r = step(&params, &mut a, 1.0, &mut b, 1000.0, 1.0);
		assert_eq!(r.moles, 0.0);
		assert!(r.target_reached);
	}

	#[test]
	fn pump_is_power_limited() {
		// Low input pressure, a demanding target: real compression work.
		let mut a = atmosphere(10.0, 293.0);
		let mut b = PipeGas::default();
		let params = DeviceParams::Pump {
			target_kpa: 1000.0,
			power_w: 1.0,
		};
		let r = step(&params, &mut a, 1000.0, &mut b, 1000.0, 1.0);
		assert!(r.moles > 0.0);
		assert!(r.power_w <= 1.0 + 1e-3, "power draw stays within the rating");
		assert!(pressure(&b, 1000.0) < 1.0, "low power moves very little gas in one tick");
	}

	#[test]
	fn volume_pump_moves_fixed_rate() {
		let mut a = atmosphere(1000.0, 293.0);
		let mut b = PipeGas::default();
		let before_a = total(&a);
		let r = step(&DeviceParams::VolumePump { rate_l_s: 200.0 }, &mut a, 1000.0, &mut b, 1000.0, 1.0);
		assert!(r.moles > 0.0);
		assert!((total(&a) - (before_a - r.moles)).abs() < 1e-9);
		assert!((total(&b) - r.moles).abs() < 1e-9);
	}

	#[test]
	fn passive_gate_locked_direction_does_not_reverse() {
		// Output already above target: REGULATE_OUTPUT should not flow.
		let mut a = atmosphere(10.0, 293.0);
		let mut b = atmosphere(10000.0, 293.0);
		let params = DeviceParams::PassiveGate {
			mode: Regulate::Output,
			target_kpa: 50.0,
			max_rate_l_s: 1000.0,
		};
		let r = step(&params, &mut a, 100.0, &mut b, 1000.0, 1.0);
		assert_eq!(r.moles, 0.0);
	}

	#[test]
	fn passive_gate_output_mode_stops_at_target() {
		let mut a = atmosphere(100_000.0, 293.0);
		let mut b = PipeGas::default();
		let params = DeviceParams::PassiveGate {
			mode: Regulate::Output,
			target_kpa: 101.325,
			max_rate_l_s: 5000.0,
		};
		let before = total(&a) + total(&b);
		for _ in 0..2000 {
			let _ = step(&params, &mut a, 10_000.0, &mut b, 1000.0, 1.0);
		}
		assert!((total(&a) + total(&b) - before).abs() < 1e-3);
		assert!(pressure(&b, 1000.0) <= 101.325 + 1.0);
	}

	#[test]
	fn vent_pump_release_bounded_by_max_pressure() {
		let mut turf = atmosphere(10.0, 293.0);
		let mut network = atmosphere(100_000.0, 293.0);
		let params = DeviceParams::VentPump {
			mode: VentMode::Release,
			min_kpa: 0.0,
			max_kpa: 101.325,
			max_rate_l_s: 10_000.0,
		};
		for _ in 0..500 {
			let _ = step(&params, &mut turf, 2500.0, &mut network, 100_000.0, 1.0);
		}
		assert!(pressure(&turf, 2500.0) <= 101.325 + 1.0);
	}

	#[test]
	fn vent_pump_siphon_bounded_by_min_pressure() {
		let mut turf = atmosphere(100_000.0, 293.0);
		let mut network = PipeGas::default();
		let params = DeviceParams::VentPump {
			mode: VentMode::Siphon,
			min_kpa: 0.0,
			max_kpa: 1000.0,
			max_rate_l_s: 50_000.0,
		};
		for _ in 0..500 {
			let _ = step(&params, &mut turf, 2500.0, &mut network, 100_000.0, 1.0);
		}
		assert!(pressure(&turf, 2500.0) <= 0.5, "siphoned down to the minimum");
	}

	#[test]
	fn scrubber_filters_only_masked_gas() {
		let mut a = atmosphere(1000.0, 293.0);
		let mut b = PipeGas::default();
		let co2_before = a.moles[GAS_CARBON_DIOXIDE];
		let o2_before = a.moles[GAS_OXYGEN];
		let params = DeviceParams::Scrubber {
			mask: 1 << GAS_CARBON_DIOXIDE,
			rate_l_s: 200.0,
			siphon: false,
		};
		let _ = step(&params, &mut a, 1000.0, &mut b, 1000.0, 1.0);
		assert!(b.moles[GAS_CARBON_DIOXIDE] > 0.0, "scrubbed co2 into the output");
		assert_eq!(b.moles[GAS_OXYGEN], 0.0, "left o2 behind");
		assert!((a.moles[GAS_OXYGEN] - o2_before).abs() < 1e-9, "o2 untouched on input");
		assert!(a.moles[GAS_CARBON_DIOXIDE] < co2_before);
	}

	#[test]
	fn scrubber_siphon_moves_everything() {
		let mut a = atmosphere(1000.0, 293.0);
		let mut b = PipeGas::default();
		let params = DeviceParams::Scrubber {
			mask: 0,
			rate_l_s: 200.0,
			siphon: true,
		};
		let _ = step(&params, &mut a, 1000.0, &mut b, 1000.0, 1.0);
		assert!(b.moles[GAS_OXYGEN] > 0.0);
		assert!(b.moles[GAS_CARBON_DIOXIDE] > 0.0);
	}

	#[test]
	fn filter_conserves_mass_and_energy() {
		let mut a = atmosphere(1000.0, 350.0);
		let mut b = PipeGas::default();
		let before_moles = total(&a) + total(&b);
		let before_energy = a.energy + b.energy;
		let params = DeviceParams::Filter {
			mask: 1 << GAS_OXYGEN,
			rate_l_s: 500.0,
		};
		let _ = step(&params, &mut a, 1000.0, &mut b, 1000.0, 1.0);
		assert!((total(&a) + total(&b) - before_moles).abs() < 1e-9);
		assert!((a.energy + b.energy - before_energy).abs() < 1e-6);
	}

	#[test]
	fn heat_exchanger_moves_energy_not_gas() {
		let mut a = atmosphere(1000.0, 400.0);
		let mut b = atmosphere(1000.0, 250.0);
		let moles_before = (total(&a), total(&b));
		let params = DeviceParams::HeatExchanger { conductance_w_k: 50.0 };
		for _ in 0..2000 {
			let _ = step(&params, &mut a, 1000.0, &mut b, 1000.0, 1.0);
		}
		assert_eq!((total(&a), total(&b)), moles_before, "no gas moves");
		assert!(a.temperature_now() < 400.0);
		assert!(b.temperature_now() > 250.0);
		assert!(
			(a.temperature_now() - b.temperature_now()).abs() < 5.0,
			"converges towards equilibrium: {} vs {}",
			a.temperature_now(),
			b.temperature_now()
		);
	}

	#[test]
	fn heat_exchanger_does_not_overshoot_equilibrium() {
		let mut a = atmosphere(10.0, 400.0);
		let mut b = atmosphere(100_000.0, 250.0);
		let params = DeviceParams::HeatExchanger {
			conductance_w_k: 1_000_000.0,
		};
		let _ = step(&params, &mut a, 10.0, &mut b, 100_000.0, 1.0);
		assert!(a.temperature_now() >= 249.0, "did not undershoot past b's temperature");
	}

	#[test]
	fn pressure_regulator_releases_towards_target_and_conserves() {
		let mut tank = atmosphere(1_000_000.0, 293.0);
		let mut region = PipeGas::default();
		let before = total(&tank) + total(&region);
		let params = DeviceParams::PressureRegulator { release_kpa: 101.325 };
		for _ in 0..2000 {
			let _ = step(&params, &mut tank, 100.0, &mut region, 1000.0, 1.0);
		}
		assert!((total(&tank) + total(&region) - before).abs() < 1e-3);
		assert!(pressure(&region, 1000.0) <= 101.325 + 1.0);
	}

	#[test]
	fn none_is_a_no_op() {
		let mut a = atmosphere(100.0, 293.0);
		let mut b = PipeGas::default();
		let before = total(&a);
		let r = step(&DeviceParams::None, &mut a, 100.0, &mut b, 100.0, 1.0);
		assert_eq!(r, StepReport::default());
		assert_eq!(total(&a), before);
	}
}
