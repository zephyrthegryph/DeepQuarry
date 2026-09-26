//! Atmos device flow laws (M2, `simulation.md` §5): one generic [`Flow`]
//! plus [`step_valve`] for a valve's gate, replacing the earlier eleven
//! hand-written laws (pump, volume pump, passive gate, vent pump,
//! scrubber, filter, injector, pressure regulator were each their own
//! variant with their own copy of the ideal-gas math). A device's actual
//! `Flow`/valve values are declared as data on
//! [`crate::kind::device::DeviceFlow`]/[`crate::kind::device::DeviceValve`]
//! components (`rust_architecture.md` §8.5 step 6's pipe-device redesign,
//! replacing the old packed `DeviceParams`/`kind, p0..p3` wire encoding);
//! this module only has the maths, unchanged. Every device in the table in
//! `simulation.md` §5 is one of these two shapes:
//!
//! | Device | Shape |
//! |---|---|
//! | Pump | `Flow { rate: Power, direction: Forced, stop: Some(B AtLeast target) }` |
//! | Volume pump | `Flow { rate: Volume, direction: Forced, stop: Some(B AtLeast max) }` (or `None` when overclocked) |
//! | Passive gate | `Flow { rate: Volume, direction: Forced or Downhill, stop: per mode }` |
//! | Valve, shutoff valve | [`step_valve`]`(open)` |
//! | Vent pump | `Flow { rate: Volume, direction: Forced, stop: Some(turf-side target) }` |
//! | Scrubber, filter | `Flow { gases: mask, rate: Volume, direction: Forced, stop: None }` |
//! | Injector | `Flow { rate: Volume, direction: Forced, stop: None }` |
//! | Canister/connector regulator | `Flow { rate: Unlimited, direction: Forced, stop: Some(B AtLeast release) }` |
//!
//! The heat exchanger is not a gas law: real heat exchange is a `vg-heat`
//! coupling between the two sides' solids/mixtures, not a pipe-network
//! device edge (`simulation.md` §5's M2 follow-up item 3) - `device.rs`
//! only moves gas.
//!
//! The ideal-gas helpers (pressure, moles-for-a-volume, masked transfer)
//! live once, as [`crate::pipes::PipeGas`] methods, instead of five
//! per-law copies; [`Flow::step`] is arithmetic over the `stop`/`rate`
//! shape plus those methods.

use crate::gas::constants::R_IDEAL_GAS_EQUATION;
use crate::pipes::PipeGas;

/// How much a [`Flow`] may move per second.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Rate {
	/// A volume (L/s) of the source's current density.
	Volume(f32),
	/// A flat mole rate (mol/s).
	Moles(f32),
	/// Isothermal compression power (W): `n R T ln(P2/P1)` bounds the
	/// moles moved (a pump working against its own target).
	Power(f32),
	/// No cap besides `stop` and (for [`Direction::Downhill`]) the
	/// pressure gradient itself.
	Unlimited,
}

/// Whether a [`Flow`] moves regardless of the pressure gradient, or only
/// while its source is the higher-pressure side.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Direction {
	/// Moves every tick `stop` still allows, ignoring which side is
	/// higher (a pump pushing against its own target; a scrubber pulling
	/// regardless of pressure).
	#[default]
	Forced,
	/// Moves from whichever side is higher pressure into the other, and
	/// not at all when they're equal (a valve, an unregulated passive
	/// gate). Only meaningful with `stop: None` - a `Downhill` flow with a
	/// `stop` target uses the target to pick source and destination
	/// instead (see [`Flow::step`]).
	Downhill,
}

/// Which endpoint a [`Target`] is measured on.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Side {
	A,
	B,
}

/// How a [`Target`] compares its side's pressure to `kpa`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Cmp {
	/// Flow continues while `side` is below `kpa` (a goal to reach, or a
	/// ceiling not to exceed - the stop condition is the same either way:
	/// halt once `side >= kpa`). Gas moves *into* `side`.
	AtLeast,
	/// Flow continues while `side` is above `kpa` (draining down to a
	/// floor). Gas moves *out of* `side`.
	AtMost,
}

/// Where a [`Flow`] stops itself: gas moves toward satisfying this (which
/// also picks the flow's source and destination when `stop` is set - see
/// [`Flow::step`]), and the edge reports `target_reached` once it's met.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Target {
	pub side: Side,
	pub cmp: Cmp,
	pub kpa: f32,
}

/// A generic flow law: moves the gases in `gases` (a `1 << gas_id`
/// bitset; 0 means every gas) at up to `rate`, until `stop` is satisfied.
///
/// Source and destination aren't fixed to `a`/`b`: with a `stop` target,
/// gas always moves toward satisfying it (into the target side for
/// `AtLeast`, out of it for `AtMost`), whichever of `a`/`b` that turns out
/// to be - this is what lets a vent pump's `a` stay "the turf" for both
/// its release and siphon modes instead of needing the caller to swap
/// endpoints per mode. With no `stop`, `Forced` always moves `a` -> `b`
/// (an injector, a siphoning scrubber); `Downhill` moves from whichever of
/// `a`/`b` is higher pressure (a valve, an unregulated passive gate).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Flow {
	pub gases: u32,
	pub rate: Rate,
	pub direction: Direction,
	pub stop: Option<Target>,
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
	/// The stop target (if any) is satisfied and flow halted this tick.
	pub target_reached: bool,
}

/// Runs one [`Flow`] for `dt` seconds, moving gas (and energy) between `a`
/// and `b` in place. Returns what happened. A device entity may carry
/// several `Flow`s (`kind::device::DeviceFlow`'s own docs -- a filter is a
/// passthrough flow plus a filtered one, a mixer two input flows); the
/// caller (`ffi/src/pipes.rs`) runs each in turn on the same pair.
#[must_use]
pub fn step(flow: &Flow, a: &mut PipeGas, vol_a: f64, b: &mut PipeGas, vol_b: f64, dt: f32) -> StepReport {
	if dt <= 0.0 {
		return StepReport::default();
	}
	flow.step(a, vol_a, b, vol_b, dt)
}

/// Runs a device's valve gate (`kind::device::DeviceValve`): equalizes `a`
/// and `b` while `open`, otherwise moves nothing. Not a [`Flow`] itself: a
/// valve's "law" is really the pipe network's own topology merge on
/// connect (which already equalizes the regions it bridges); this only
/// covers the one tick before that merge's next commit catches up.
#[must_use]
pub fn step_valve(open: bool, a: &mut PipeGas, vol_a: f64, b: &mut PipeGas, vol_b: f64) -> StepReport {
	if !open {
		return StepReport::default();
	}
	let moved = equalize(a, vol_a, b, vol_b);
	StepReport {
		moles: moved,
		..Default::default()
	}
}

/// Moves gas from the higher- to the lower-pressure side until both are
/// equal (a valve). Not part of `Flow`: a valve's "law" is really M1b's
/// region merge on connect, this only covers the one tick before that
/// merge's next commit catches up.
fn equalize(a: &mut PipeGas, vol_a: f64, b: &mut PipeGas, vol_b: f64) -> f64 {
	let (pa, pb) = (a.pressure(vol_a), b.pressure(vol_b));
	if (pa - pb).abs() < 0.01 || vol_a <= 0.0 || vol_b <= 0.0 {
		return 0.0;
	}
	let (from, to, vol_from, vol_to, sign): (&mut PipeGas, &mut PipeGas, f64, f64, f64) = if pa > pb {
		(a, b, vol_a, vol_b, 1.0)
	} else {
		(b, a, vol_b, vol_a, -1.0)
	};
	let t = from.temperature_now().max(1.0);
	let delta_p = (from.pressure(vol_from) - to.pressure(vol_to)).max(0.0);
	let moles =
		f64::from(delta_p) * (vol_from * vol_to / (vol_from + vol_to)) / (f64::from(R_IDEAL_GAS_EQUATION) * f64::from(t));
	from.transfer_masked(to, 0, moles) * sign
}

impl Flow {
	/// See the struct docs for how `stop` picks source/destination.
	fn step(&self, a: &mut PipeGas, vol_a: f64, b: &mut PipeGas, vol_b: f64, dt: f32) -> StepReport {
		let (pa, pb) = (a.pressure(vol_a), b.pressure(vol_b));

		// `from_is_a`: which side gas leaves. `needed`: moles still wanted
		// to satisfy `stop` (infinite with no stop, capped instead by
		// `Downhill`'s own equalize-point below). `target_kpa`: with a
		// `stop`, the absolute pressure a `Rate::Power` flow is doing
		// compression work against (the pump's design duty), not
		// whatever the destination's instantaneous pressure happens to
		// be - using the instantaneous pressure would make a pump's
		// power draw (and so its cap) collapse toward zero the moment the
		// destination is still near-empty, since compressing into a
		// near-vacuum looks like almost no work.
		let (from_is_a, needed, target_kpa) = match self.stop {
			Some(target) => {
				let side_is_a = target.side == Side::A;
				let side_p = if side_is_a { pa } else { pb };
				let gap = match target.cmp {
					Cmp::AtLeast => target.kpa - side_p,
					Cmp::AtMost => side_p - target.kpa,				};
				if gap <= 0.01 {
					return StepReport {
						target_reached: true,
						..Default::default()
					};
				}
				// AtLeast fills `side` (source is the other one); AtMost
				// drains it (source is `side` itself). Either way `needed` is
				// exact: it's `pV = nRT` solved on the TARGET side's own
				// fixed volume for the moles that land it exactly on `kpa`,
				// using the flow's temperature (the source's - which is the
				// target's own temperature too, on an AtMost drain, since
				// target and source are the same side there).
				let dest_is_a = side_is_a == matches!(target.cmp, Cmp::AtLeast);
				let t_flow = (if dest_is_a { &*b } else { &*a }).temperature_now().max(1.0);
				let vol_side = if side_is_a { vol_a } else { vol_b };
				let needed =
					f64::from(gap) * vol_side / (f64::from(R_IDEAL_GAS_EQUATION) * f64::from(t_flow));
				(!dest_is_a, needed, Some(target.kpa))
			}
			None => match self.direction {
				Direction::Forced => (true, f64::INFINITY, None),
				Direction::Downhill => {
					if (pa - pb).abs() <= 0.01 {
						return StepReport::default();
					}
					let from_is_a = pa > pb;
					// No fixed target: converges the two sides towards each
					// other (the same physics as `equalize`), so the moles
					// moved this tick can't itself overshoot past
					// equilibrium even when the rate cap is generous.
					let (vol_from, vol_to) = if from_is_a { (vol_a, vol_b) } else { (vol_b, vol_a) };
					let t_flow = (if from_is_a { &*a } else { &*b }).temperature_now().max(1.0);
					let vol_pair = vol_from * vol_to / (vol_from + vol_to).max(1e-9);
					let needed = f64::from((pa - pb).abs()) * vol_pair
						/ (f64::from(R_IDEAL_GAS_EQUATION) * f64::from(t_flow));
					(from_is_a, needed, None)
				}
			},
		};

		let (from, to, vol_from, vol_to): (&mut PipeGas, &mut PipeGas, f64, f64) = if from_is_a {
			(a, b, vol_a, vol_b)
		} else {
			(b, a, vol_b, vol_a)
		};

		let p_from = from.pressure(vol_from);
		let mut power_w = 0.0;
		let cap = match self.rate {
			Rate::Volume(l_s) => from.moles_for_volume(vol_from, f64::from(l_s) * f64::from(dt)),
			Rate::Moles(mol_s) => f64::from(mol_s) * f64::from(dt),
			Rate::Power(power) => {
				let t = from.temperature_now().max(1.0);
				let target = target_kpa.unwrap_or(p_from.max(to.pressure(vol_to)));
				let ratio = (target.max(p_from) / p_from.max(0.01)).max(1.0 + 1e-6);
				let work_per_mole = f64::from(R_IDEAL_GAS_EQUATION) * f64::from(t) * f64::from(ratio.ln());
				let budget = f64::from(power) * f64::from(dt);
				power_w = power;
				if work_per_mole > 0.0 {
					budget / work_per_mole
				} else {
					f64::INFINITY
				}
			}
			Rate::Unlimited => f64::INFINITY,
		};

		let moles = needed.min(cap).min(from.masked_total(self.gases));
		if moles <= 0.0 {
			return StepReport::default();
		}
		let moved = from.transfer_masked(to, self.gases, moles);
		let used_power = if matches!(self.rate, Rate::Power(_)) && moved > 0.0 {
			(power_w * (moved / cap.max(1e-12)) as f32).min(power_w)
		} else {
			0.0
		};
		StepReport {
			moles: if from_is_a { moved } else { -moved },
			power_w: used_power,
			target_reached: false,
		}
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

	fn pump(target_kpa: f32, power_w: f32) -> Flow {
		Flow {
			gases: 0,
			rate: Rate::Power(power_w),
			direction: Direction::Forced,
			stop: Some(Target {
				side: Side::B,
				cmp: Cmp::AtLeast,
				kpa: target_kpa,
			}),
		}
	}

	fn volume_pump(rate_l_s: f32, max_output_kpa: f32) -> Flow {
		Flow {
			gases: 0,
			rate: Rate::Volume(rate_l_s),
			direction: Direction::Forced,
			stop: (max_output_kpa > 0.0).then_some(Target {
				side: Side::B,
				cmp: Cmp::AtLeast,
				kpa: max_output_kpa,
			}),
		}
	}

	fn passive_gate_output(target_kpa: f32, max_rate_l_s: f32) -> Flow {
		Flow {
			gases: 0,
			rate: Rate::Volume(max_rate_l_s),
			direction: Direction::Forced,
			stop: Some(Target {
				side: Side::B,
				cmp: Cmp::AtLeast,
				kpa: target_kpa,
			}),
		}
	}

	fn passive_gate_input(target_kpa: f32, max_rate_l_s: f32) -> Flow {
		Flow {
			gases: 0,
			rate: Rate::Volume(max_rate_l_s),
			direction: Direction::Forced,
			stop: Some(Target {
				side: Side::A,
				cmp: Cmp::AtMost,
				kpa: target_kpa,
			}),
		}
	}

	fn passive_gate_equalize(max_rate_l_s: f32) -> Flow {
		Flow {
			gases: 0,
			rate: Rate::Volume(max_rate_l_s),
			direction: Direction::Downhill,
			stop: None,
		}
	}

	/// `a` is always the turf side, matching the pipe network's own fixed
	/// `Endpoint::Cell(_) == a` convention - `stop` alone decides which way
	/// gas actually moves (see `Flow`'s docs).
	fn vent_release(max_kpa: f32, max_rate_l_s: f32) -> Flow {
		Flow {
			gases: 0,
			rate: Rate::Volume(max_rate_l_s),
			direction: Direction::Forced,
			stop: Some(Target {
				side: Side::A,
				cmp: Cmp::AtLeast,
				kpa: max_kpa,
			}),
		}
	}

	fn vent_siphon(min_kpa: f32, max_rate_l_s: f32) -> Flow {
		Flow {
			gases: 0,
			rate: Rate::Volume(max_rate_l_s),
			direction: Direction::Forced,
			stop: Some(Target {
				side: Side::A,
				cmp: Cmp::AtMost,
				kpa: min_kpa,
			}),
		}
	}

	fn scrubber(mask: u32, rate_l_s: f32) -> Flow {
		Flow {
			gases: mask,
			rate: Rate::Volume(rate_l_s),
			direction: Direction::Forced,
			stop: None,
		}
	}

	fn regulator(release_kpa: f32) -> Flow {
		Flow {
			gases: 0,
			rate: Rate::Unlimited,
			direction: Direction::Forced,
			stop: Some(Target {
				side: Side::B,
				cmp: Cmp::AtLeast,
				kpa: release_kpa,
			}),
		}
	}

	#[test]
	fn equalize_closed_moves_nothing() {
		let mut a = atmosphere(100.0, 293.0);
		let mut b = PipeGas::default();
		let before = total(&a) + total(&b);
		let r = step_valve(false, &mut a, 100.0, &mut b, 100.0);
		assert_eq!(r.moles, 0.0);
		assert!((total(&a) + total(&b) - before).abs() < 1e-9);
		assert!((total(&b)).abs() < 1e-9);
	}

	#[test]
	fn equalize_open_equalizes_and_conserves() {
		let mut a = atmosphere(100.0, 293.0);
		let mut b = PipeGas::default();
		let before = total(&a) + total(&b);
		for _ in 0..500 {
			let _ = step_valve(true, &mut a, 100.0, &mut b, 100.0);
		}
		assert!((total(&a) + total(&b) - before).abs() < 1e-6, "conserves mass");
		assert!((total(&a) - total(&b)).abs() < 0.5, "equalized: {} vs {}", total(&a), total(&b));
	}

	#[test]
	fn pump_moves_towards_target_and_conserves() {
		let mut a = atmosphere(1000.0, 293.0);
		let mut b = PipeGas::default();
		let before = total(&a) + total(&b);
		let params = pump(101.325, 5000.0);
		for _ in 0..200 {
			let _ = step(&params, &mut a, 1000.0, &mut b, 1000.0, 1.0);
		}
		assert!((total(&a) + total(&b) - before).abs() < 1e-6);
		let pb = b.pressure(1000.0);
		assert!(pb <= 101.325 + 0.5, "does not overshoot target: {pb}");
		assert!(pb > 50.0, "made real progress towards target: {pb}");
	}

	#[test]
	fn pump_at_target_stalls() {
		let mut a = atmosphere(10.0, 293.0);
		let mut b = atmosphere(10000.0, 293.0);
		let params = pump(50.0, 5000.0);
		let r = step(&params, &mut a, 1.0, &mut b, 1000.0, 1.0);
		assert_eq!(r.moles, 0.0);
		assert!(r.target_reached);
	}

	#[test]
	fn pump_is_power_limited() {
		let mut a = atmosphere(10.0, 293.0);
		let mut b = PipeGas::default();
		let params = pump(1000.0, 1.0);
		let r = step(&params, &mut a, 1000.0, &mut b, 1000.0, 1.0);
		assert!(r.moles > 0.0);
		assert!(r.power_w <= 1.0 + 1e-3, "power draw stays within the rating");
		assert!(b.pressure(1000.0) < 1.0, "low power moves very little gas in one tick");
	}

	#[test]
	fn volume_pump_moves_fixed_rate() {
		let mut a = atmosphere(1000.0, 293.0);
		let mut b = PipeGas::default();
		let before_a = total(&a);
		let r = step(&volume_pump(200.0, 0.0), &mut a, 1000.0, &mut b, 1000.0, 1.0);
		assert!(r.moles > 0.0);
		assert!((total(&a) - (before_a - r.moles)).abs() < 1e-9);
		assert!((total(&b) - r.moles).abs() < 1e-9);
	}

	#[test]
	fn volume_pump_refuses_above_max_output_pressure() {
		let mut a = atmosphere(1000.0, 293.0);
		let mut b = atmosphere(100_000.0, 293.0);
		let r = step(&volume_pump(200.0, 101.325), &mut a, 1000.0, &mut b, 1000.0, 1.0);
		assert_eq!(r.moles, 0.0);
		assert!(r.target_reached);
	}

	#[test]
	fn volume_pump_uncapped_ignores_output_pressure() {
		let mut a = atmosphere(1000.0, 293.0);
		let mut b = atmosphere(100_000.0, 293.0);
		let r = step(&volume_pump(200.0, 0.0), &mut a, 1000.0, &mut b, 1000.0, 1.0);
		assert!(r.moles > 0.0);
	}

	#[test]
	fn passive_gate_locked_direction_does_not_reverse() {
		let mut a = atmosphere(10.0, 293.0);
		let mut b = atmosphere(10000.0, 293.0);
		let r = step(&passive_gate_output(50.0, 1000.0), &mut a, 100.0, &mut b, 1000.0, 1.0);
		assert_eq!(r.moles, 0.0);
	}

	#[test]
	fn passive_gate_output_mode_stops_at_target() {
		let mut a = atmosphere(100_000.0, 293.0);
		let mut b = PipeGas::default();
		let params = passive_gate_output(101.325, 5000.0);
		let before = total(&a) + total(&b);
		for _ in 0..2000 {
			let _ = step(&params, &mut a, 10_000.0, &mut b, 1000.0, 1.0);
		}
		assert!((total(&a) + total(&b) - before).abs() < 1e-3);
		assert!(b.pressure(1000.0) <= 101.325 + 1.0);
	}

	#[test]
	fn passive_gate_input_mode_drains_down_to_target() {
		let mut a = atmosphere(100_000.0, 293.0);
		let mut b = PipeGas::default();
		let params = passive_gate_input(101.325, 5000.0);
		for _ in 0..2000 {
			let _ = step(&params, &mut a, 10_000.0, &mut b, 100_000.0, 1.0);
		}
		assert!(a.pressure(10_000.0) >= 101.325 - 1.0 && a.pressure(10_000.0) <= 101.325 + 1.0);
	}

	#[test]
	fn passive_gate_equalize_mode_conserves_and_never_reverses() {
		let mut a = atmosphere(100.0, 293.0);
		let mut b = PipeGas::default();
		let before = total(&a) + total(&b);
		for _ in 0..500 {
			let _ = step(&passive_gate_equalize(1000.0), &mut a, 100.0, &mut b, 100.0, 1.0);
		}
		assert!((total(&a) + total(&b) - before).abs() < 1e-6);
		assert!((total(&a) - total(&b)).abs() < 0.5);
		// Never reverses: b starts empty and a never goes negative.
		assert!(total(&a) >= 0.0 && total(&b) >= 0.0);
	}

	#[test]
	fn vent_pump_release_bounded_by_max_pressure() {
		let mut turf = atmosphere(10.0, 293.0);
		let mut network = atmosphere(100_000.0, 293.0);
		let params = vent_release(101.325, 10_000.0);
		for _ in 0..500 {
			let _ = step(&params, &mut turf, 2500.0, &mut network, 100_000.0, 1.0);
		}
		assert!(turf.pressure(2500.0) <= 101.325 + 1.0);
	}

	#[test]
	fn vent_pump_siphon_bounded_by_min_pressure() {
		let mut turf = atmosphere(100_000.0, 293.0);
		let mut network = PipeGas::default();
		let params = vent_siphon(0.0, 50_000.0);
		for _ in 0..500 {
			let _ = step(&params, &mut turf, 2500.0, &mut network, 100_000.0, 1.0);
		}
		assert!(turf.pressure(2500.0) <= 0.5, "siphoned down to the minimum");
	}

	#[test]
	fn scrubber_filters_only_masked_gas() {
		let mut a = atmosphere(1000.0, 293.0);
		let mut b = PipeGas::default();
		let co2_before = a.moles[GAS_CARBON_DIOXIDE];
		let o2_before = a.moles[GAS_OXYGEN];
		let r = step(&scrubber(1 << GAS_CARBON_DIOXIDE, 200.0), &mut a, 1000.0, &mut b, 1000.0, 1.0);
		assert!(r.moles > 0.0);
		assert!(b.moles[GAS_CARBON_DIOXIDE] > 0.0, "scrubbed co2 into the output");
		assert_eq!(b.moles[GAS_OXYGEN], 0.0, "left o2 behind");
		assert!((a.moles[GAS_OXYGEN] - o2_before).abs() < 1e-9, "o2 untouched on input");
		assert!(a.moles[GAS_CARBON_DIOXIDE] < co2_before);
	}

	#[test]
	fn scrubber_siphon_mask_zero_moves_everything() {
		let mut a = atmosphere(1000.0, 293.0);
		let mut b = PipeGas::default();
		let _ = step(&scrubber(0, 200.0), &mut a, 1000.0, &mut b, 1000.0, 1.0);
		assert!(b.moles[GAS_OXYGEN] > 0.0);
		assert!(b.moles[GAS_CARBON_DIOXIDE] > 0.0);
	}

	#[test]
	fn filter_conserves_mass_and_energy() {
		let mut a = atmosphere(1000.0, 350.0);
		let mut b = PipeGas::default();
		let before_moles = total(&a) + total(&b);
		let before_energy = a.energy + b.energy;
		let _ = step(&scrubber(1 << GAS_OXYGEN, 500.0), &mut a, 1000.0, &mut b, 1000.0, 1.0);
		assert!((total(&a) + total(&b) - before_moles).abs() < 1e-9);
		assert!((a.energy + b.energy - before_energy).abs() < 1e-6);
	}

	#[test]
	fn pressure_regulator_releases_towards_target_and_conserves() {
		let mut tank = atmosphere(1_000_000.0, 293.0);
		let mut region = PipeGas::default();
		let before = total(&tank) + total(&region);
		let params = regulator(101.325);
		for _ in 0..2000 {
			let _ = step(&params, &mut tank, 100.0, &mut region, 1000.0, 1.0);
		}
		assert!((total(&tank) + total(&region) - before).abs() < 1e-3);
		assert!(region.pressure(1000.0) <= 101.325 + 1.0);
	}

	// The rest of this module ports what used to be `DeviceParams::decode`'s
	// wire-format tests onto `kind::device::DeviceFlow::flow()`, the
	// declarative rows that replaced it (`rust_architecture.md` §8.5 step
	// 6's pipe-device redesign): each checks that a `DeviceFlow` built the
	// way a real device would configure it decodes to the same `Flow` the
	// hand-built helpers above already exercise end to end.
	use crate::kind::device::{direction, rate_kind, stop_cmp, stop_side, DeviceFlow};

	fn row(gases: u32, rate_kind: u8, rate: f32, direction: u8, stop_side: u8, stop_cmp: u8, stop_kpa: f32) -> DeviceFlow {
		DeviceFlow {
			device: 0,
			gases,
			rate_kind,
			rate,
			direction,
			stop_side,
			stop_cmp,
			stop_kpa,
		}
	}

	#[test]
	fn flow_row_pump_matches_the_hand_built_law() {
		let r = row(0, rate_kind::POWER, 5000.0, direction::FORCED, stop_side::B, stop_cmp::AT_LEAST, 101.325);
		assert_eq!(r.flow(), pump(101.325, 5000.0));
	}

	#[test]
	fn flow_row_volume_pump_uncapped_when_stop_is_none() {
		let r = row(0, rate_kind::VOLUME, 200.0, direction::FORCED, stop_side::B, stop_cmp::NONE, 0.0);
		assert_eq!(r.flow().stop, None);
	}

	#[test]
	fn flow_row_passive_gate_modes() {
		let output = row(0, rate_kind::VOLUME, 5000.0, direction::FORCED, stop_side::B, stop_cmp::AT_LEAST, 101.325);
		assert_eq!(output.flow(), passive_gate_output(101.325, 5000.0));
		let input = row(0, rate_kind::VOLUME, 5000.0, direction::FORCED, stop_side::A, stop_cmp::AT_MOST, 101.325);
		assert_eq!(input.flow(), passive_gate_input(101.325, 5000.0));
		let equalize = row(0, rate_kind::VOLUME, 5000.0, direction::DOWNHILL, stop_side::A, stop_cmp::NONE, 0.0);
		assert_eq!(equalize.flow(), passive_gate_equalize(5000.0));
	}

	#[test]
	fn flow_row_vent_pump_modes() {
		let release = row(0, rate_kind::VOLUME, 10_000.0, direction::FORCED, stop_side::A, stop_cmp::AT_LEAST, 101.325);
		assert_eq!(release.flow(), vent_release(101.325, 10_000.0));
		let siphon = row(0, rate_kind::VOLUME, 10_000.0, direction::FORCED, stop_side::A, stop_cmp::AT_MOST, 0.0);
		assert_eq!(siphon.flow(), vent_siphon(0.0, 10_000.0));
	}

	#[test]
	fn flow_row_scrubber_filters_by_mask() {
		let mask = 1u32 << GAS_CARBON_DIOXIDE;
		let r = row(mask, rate_kind::VOLUME, 200.0, direction::FORCED, stop_side::A, stop_cmp::NONE, 0.0);
		assert_eq!(r.flow(), scrubber(mask, 200.0));
	}

	#[test]
	fn flow_row_regulator() {
		let r = row(0, rate_kind::UNLIMITED, 0.0, direction::FORCED, stop_side::B, stop_cmp::AT_LEAST, 101.325);
		assert_eq!(r.flow(), regulator(101.325));
	}
}
