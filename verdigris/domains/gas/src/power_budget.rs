//! Entropy-limited power budget for a filter or mixer device
//! (`rust_architecture.md` §8.5 step 6's filter/mixer slice): the maths
//! `_atmospherics_helpers.dm`'s `filter_gas()`/`mix_gas()` used to run in
//! DM (`specific_entropy_gas()`, `xgm_compat.dm`), ported here verbatim so
//! DM can give a filter's two `DeviceFlow` rows (filtered + passthrough)
//! or a mixer's two input rows a plain `Rate::Moles` per tick instead of
//! moving gas itself.
//!
//! What stays in DM: a device's own `material_pump_power()`/
//! `material_pump_efficiency()` (material-engineering hooks that adjust
//! `available_power`/`efficiency` before calling in here) and the actual
//! gas movement (an ordinary `DeviceFlow` row, run by `device::step` like
//! any other device edge) -- this module only replaces the entropy-based
//! rate-limiting arithmetic that used to gate `filter_gas()`/`mix_gas()`.

use crate::gas::constants::R_IDEAL_GAS_EQUATION;
use crate::gas::ids::GAS_COUNT as N;
use crate::gas::mixture::Mixture;

/// XGM's fallback "no gas here" entropy (`xgm_compat.dm`'s
/// `SPECIFIC_ENTROPY_VACUUM`).
const SPECIFIC_ENTROPY_VACUUM: f32 = 150.0;
/// `xgm_compat.dm`'s `IDEAL_GAS_ENTROPY_CONSTANT`.
const IDEAL_GAS_ENTROPY_CONSTANT: f32 = 1164.0;

/// `xgm_compat.dm`'s `specific_entropy_gas()`: the specific entropy (an
/// energy-per-mole-per-kelvin figure `specific_power_gas` differences to
/// get a per-mole moving cost) of gas `idx` alone, at `mix`'s current
/// temperature/volume/moles.
fn specific_entropy_gas(idx: usize, mix: &Mixture) -> f32 {
	let (temperature, volume) = (mix.get_temperature(), mix.volume);
	if temperature <= 0.0 || volume <= 0.0 {
		return SPECIFIC_ENTROPY_VACUUM;
	}
	let n = mix.moles_array()[idx];
	if n <= 0.0 {
		return SPECIFIC_ENTROPY_VACUUM;
	}
	let molar_mass = crate::gas::types::molar_mass(idx);
	let specific_heat = crate::cell::SPECIFIC_HEATS.get(idx).copied().unwrap_or(0.0);
	if molar_mass <= 0.0 || specific_heat <= 0.0 {
		return R_IDEAL_GAS_EQUATION * ((volume / n).ln() + 1.5 * temperature.ln()) + 15.0;
	}
	let inner = (IDEAL_GAS_ENTROPY_CONSTANT * volume / (n * temperature))
		* (molar_mass * specific_heat * temperature).powf(2.0 / 3.0)
		+ 1.0;
	R_IDEAL_GAS_EQUATION * (inner.ln() + 15.0)
}

/// `xgm_compat.dm`'s `specific_entropy()`: `mix`'s whole-mixture specific
/// entropy, the mole-weighted average of every gas's own.
fn specific_entropy(mix: &Mixture) -> f32 {
	let n_total = mix.moles_array().iter().sum::<f32>();
	if n_total <= 0.0 {
		return SPECIFIC_ENTROPY_VACUUM;
	}
	let moles = mix.moles_array();
	let sum: f32 = (0..N)
		.filter(|&i| moles[i] > 0.0)
		.map(|i| moles[i] * specific_entropy_gas(i, mix))
		.sum();
	sum / n_total
}

/// `_atmospherics_helpers.dm`'s `calculate_specific_power_gas()`: the
/// power (W/mol) needed to move one mole of gas `idx` from `source` to
/// `sink`. Zero when moving it actually releases entropy (a downhill
/// move needs no work).
fn specific_power_gas(idx: usize, source: &Mixture, sink: &Mixture) -> f32 {
	let sink_temperature = sink.get_temperature();
	let air_temperature = if sink_temperature > 0.0 { sink_temperature } else { source.get_temperature() };
	let specific_entropy = specific_entropy_gas(idx, sink) - specific_entropy_gas(idx, source);
	if specific_entropy < 0.0 { -specific_entropy * air_temperature } else { 0.0 }
}

/// `_atmospherics_helpers.dm`'s `calculate_specific_power()`: the
/// whole-mixture version `mix_gas()` uses (one figure per source, not one
/// per gas -- a mixer doesn't split a source's own composition).
fn specific_power(source: &Mixture, sink: &Mixture) -> f32 {
	let sink_temperature = sink.get_temperature();
	let air_temperature = if sink_temperature > 0.0 { sink_temperature } else { source.get_temperature() };
	let specific_entropy = specific_entropy(sink) - specific_entropy(source);
	if specific_entropy < 0.0 { -specific_entropy * air_temperature } else { 0.0 }
}

/// A filter's computed per-tick transfer, from [`filter_transfer`].
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct FilterTransfer {
	/// Total moles to remove from `source` this tick (proportional across
	/// every gas, exactly as `filter_gas()`'s single `source.remove()`
	/// was): split the two `DeviceFlow` rows' `Rate::Moles` by
	/// `filterable_moles`/`unfilterable_moles`'s share of this.
	pub total_transfer_moles: f32,
	/// `source`'s current filterable moles (the `filtering` mask's gases).
	pub filterable_moles: f32,
	/// `source`'s current unfilterable moles (everything else).
	pub unfilterable_moles: f32,
	/// Power actually drawn this tick (W), for `use_power()`/UI billing.
	pub power_draw: f32,
}

/// `_atmospherics_helpers.dm`'s `filter_gas()`, minus the actual gas
/// movement (a caller-owned `DeviceFlow` pair does that): `filtering` is a
/// `1 << gas_id` bitset of which gases go to `sink_filtered` (everything
/// else goes to `sink_clean`); `requested`/`available_power` are
/// `total_transfer_moles`/`available_power` there (already adjusted for
/// the device's own `material_pump_power()`); `efficiency` is
/// `ATMOS_FILTER_EFFICIENCY * material_pump_efficiency()/0.8` (or `1.0`
/// with no material multiplier), computed by the caller exactly as before.
/// `None` is `filter_gas()`'s `-1`: too little gas or power to move
/// anything meaningful this tick.
#[must_use]
#[allow(clippy::too_many_arguments)]
pub fn filter_transfer(
	source: &Mixture,
	sink_filtered: &Mixture,
	sink_clean: &Mixture,
	filtering: u32,
	requested: Option<f32>,
	available_power: Option<f32>,
	efficiency: f32,
	min_moles_to_filter: f32,
) -> Option<FilterTransfer> {
	let moles = source.moles_array();
	let source_total: f32 = moles.iter().sum();
	if source_total < min_moles_to_filter {
		return None;
	}

	let mut total_specific_power = 0.0;
	let mut filterable_moles = 0.0;
	let mut unfilterable_moles = 0.0;
	for (idx, &n) in moles.iter().enumerate() {
		if n < min_moles_to_filter {
			continue;
		}
		let filtered = filtering & (1 << idx) != 0;
		let sink = if filtered { sink_filtered } else { sink_clean };
		let specific_power = specific_power_gas(idx, source, sink) / efficiency;
		if filtered {
			filterable_moles += n;
		} else {
			unfilterable_moles += n;
		}
		total_specific_power += specific_power * (n / source_total);
	}

	let mut total_transfer_moles = requested.unwrap_or(source_total).min(source_total);
	if let Some(power) = available_power {
		if total_specific_power > 0.0 {
			total_transfer_moles = total_transfer_moles.min(power / total_specific_power);
		}
	}
	if total_transfer_moles < min_moles_to_filter {
		return None;
	}

	Some(FilterTransfer {
		total_transfer_moles,
		filterable_moles,
		unfilterable_moles,
		// filter_gas() sums specific_power_gas[g] * removed_amount(g) over
		// every gas; removed is an exact proportional (total_transfer_moles /
		// source_total) copy of source, so this collapses to
		// total_specific_power (already that same ratio-weighted sum, per
		// mole of INPUT gas) times the moles actually moved.
		power_draw: total_specific_power * total_transfer_moles,
	})
}

/// One of [`filter_transfer_multi`]'s named outputs: gases in `mask` go to
/// `sink` (the omni filter's per-gas ports; each currently configured for
/// exactly one gas, but this supports any mask).
#[derive(Clone, Copy)]
pub struct FilterOutput<'a> {
	pub mask: u32,
	pub sink: &'a Mixture,
}

/// An omni filter's computed per-tick transfer, from [`filter_transfer_multi`].
#[derive(Clone, Debug, PartialEq)]
pub struct FilterMultiTransfer {
	pub total_transfer_moles: f32,
	pub power_draw: f32,
	/// Per output (same order as the input slice): its share of `source`'s
	/// current moles among the gases its mask matches.
	pub moles: Vec<f32>,
	/// Whatever matched no output's mask, moved to the catch-all sink.
	pub clean_moles: f32,
}

/// `_atmospherics_helpers.dm`'s `filter_gas_multi()`, minus the actual gas
/// movement: the omni filter's N-way generalization of [`filter_transfer`]
/// -- one sink per configured gas port instead of one shared "filtered"
/// sink, plus a catch-all `sink_clean` for anything unmatched (`output`,
/// the omni filter's own required output port). `None` is
/// `filter_gas_multi()`'s `-1`.
#[must_use]
#[allow(clippy::too_many_arguments)]
pub fn filter_transfer_multi(
	source: &Mixture,
	outputs: &[FilterOutput<'_>],
	sink_clean: &Mixture,
	requested: Option<f32>,
	available_power: Option<f32>,
	efficiency: f32,
	min_moles_to_filter: f32,
) -> Option<FilterMultiTransfer> {
	let moles = source.moles_array();
	let source_total: f32 = moles.iter().sum();
	if source_total < min_moles_to_filter {
		return None;
	}

	let mut total_specific_power = 0.0;
	let mut output_moles = vec![0.0_f32; outputs.len()];
	let mut clean_moles = 0.0;
	for (idx, &n) in moles.iter().enumerate() {
		if n < min_moles_to_filter {
			continue;
		}
		let bit = 1_u32 << idx;
		let matched = outputs.iter().position(|o| o.mask & bit != 0);
		let sink = matched.map_or(sink_clean, |i| outputs[i].sink);
		let specific_power = specific_power_gas(idx, source, sink) / efficiency;
		match matched {
			Some(i) => output_moles[i] += n,
			None => clean_moles += n,
		}
		total_specific_power += specific_power * (n / source_total);
	}

	let mut total_transfer_moles = requested.unwrap_or(source_total).min(source_total);
	if let Some(power) = available_power {
		if total_specific_power > 0.0 {
			total_transfer_moles = total_transfer_moles.min(power / total_specific_power);
		}
	}
	if total_transfer_moles < min_moles_to_filter {
		return None;
	}

	Some(FilterMultiTransfer {
		total_transfer_moles,
		power_draw: total_specific_power * total_transfer_moles,
		moles: output_moles,
		clean_moles,
	})
}

/// One `mix_gas()` input: its mixture and its fixed mix ratio (every
/// source's ratio must sum to 1, same as DM's `mix_sources` list).
#[derive(Clone, Copy)]
pub struct MixSource<'a> {
	pub mixture: &'a Mixture,
	pub ratio: f32,
}

/// A mixer's computed per-tick transfer, from [`mix_transfer`]: one moles
/// figure per source (`sources`' order), scale each source's `DeviceFlow`
/// row's `Rate::Moles` by `moles[i] / dt`.
#[derive(Clone, Debug, PartialEq)]
pub struct MixTransfer {
	pub total_transfer_moles: f32,
	/// Per source (same order as the input slice): `total_transfer_moles * ratio`.
	pub moles: Vec<f32>,
	/// Power actually drawn this tick (W), for `use_power()`/UI billing.
	pub power_draw: f32,
}

/// `_atmospherics_helpers.dm`'s `mix_gas()`, minus the actual gas movement
/// (a caller-owned `DeviceFlow` per source does that). `None` is
/// `mix_gas()`'s `-1`.
#[must_use]
pub fn mix_transfer(
	sources: &[MixSource<'_>],
	sink: &Mixture,
	requested: Option<f32>,
	available_power: Option<f32>,
	efficiency: f32,
	min_moles_to_filter: f32,
) -> Option<MixTransfer> {
	if sources.is_empty() {
		return None;
	}

	let mut total_specific_power = 0.0;
	let mut total_mixing_moles: Option<f32> = None;
	let mut source_specific_power = Vec::with_capacity(sources.len());
	for src in sources {
		let source_total = src.mixture.moles_array().iter().sum::<f32>();
		if source_total < min_moles_to_filter {
			return None;
		}
		if src.ratio == 0.0 {
			source_specific_power.push(0.0);
			continue;
		}
		let this_mixing_moles = source_total / src.ratio;
		total_mixing_moles = Some(total_mixing_moles.map_or(this_mixing_moles, |m: f32| m.min(this_mixing_moles)));
		let power = specific_power(src.mixture, sink) * src.ratio / efficiency;
		source_specific_power.push(power);
		total_specific_power += power;
	}

	let total_mixing_moles = total_mixing_moles?;
	if total_mixing_moles < min_moles_to_filter {
		return None;
	}

	let mut total_transfer_moles = requested.map_or(total_mixing_moles, |r| r.min(total_mixing_moles));
	if let Some(power) = available_power {
		if total_specific_power > 0.0 {
			total_transfer_moles = total_transfer_moles.min(power / total_specific_power);
		}
	}
	if total_transfer_moles < min_moles_to_filter {
		return None;
	}

	let mut power_draw = 0.0;
	let moles = sources
		.iter()
		.zip(&source_specific_power)
		.map(|(src, &power)| {
			if src.ratio == 0.0 {
				return 0.0;
			}
			let transfer = total_transfer_moles * src.ratio;
			power_draw += transfer * power;
			transfer
		})
		.collect();

	Some(MixTransfer { total_transfer_moles, moles, power_draw })
}

#[cfg(test)]
mod tests {
	use super::*;
	use crate::gas::ids::{GAS_CARBON_DIOXIDE, GAS_OXYGEN, GAS_PLASMA};

	fn air(o2: f32, co2: f32, plasma: f32, temperature: f32) -> Mixture {
		let mut moles = [0.0_f32; N];
		moles[GAS_OXYGEN] = o2;
		moles[GAS_CARBON_DIOXIDE] = co2;
		moles[GAS_PLASMA] = plasma;
		Mixture::from_parts(&moles, temperature, 2500.0, false)
	}

	fn install_gases() {
		if crate::gas::types::total_num_gases() > 0 {
			return;
		}
		crate::gas::types::set_gas_statics_manually();
		for i in 0..N {
			crate::gas::types::register_gas_manually(Box::leak(i.to_string().into_boxed_str()), crate::cell::SPECIFIC_HEATS[i]);
		}
	}

	#[test]
	fn filter_moves_only_the_masked_gas_and_conserves_the_split() {
		install_gases();
		let source = air(200.0, 200.0, 0.0, 293.15);
		let sink_filtered = air(0.0, 0.0, 0.0, 293.15);
		let sink_clean = air(0.0, 0.0, 0.0, 293.15);
		let mask = 1 << GAS_CARBON_DIOXIDE;
		let result = filter_transfer(&source, &sink_filtered, &sink_clean, mask, Some(100.0), None, 1.0, 0.04)
			.expect("enough gas to filter");
		assert!((result.total_transfer_moles - 100.0).abs() < 1e-3);
		assert!((result.filterable_moles - 200.0).abs() < 1e-3);
		assert!((result.unfilterable_moles - 200.0).abs() < 1e-3);
	}

	#[test]
	fn filter_returns_none_below_the_minimum() {
		install_gases();
		let source = air(0.01, 0.0, 0.0, 293.15);
		let sink_filtered = air(0.0, 0.0, 0.0, 293.15);
		let sink_clean = air(0.0, 0.0, 0.0, 293.15);
		assert_eq!(filter_transfer(&source, &sink_filtered, &sink_clean, 0, None, None, 1.0, 0.04), None);
	}

	#[test]
	fn filter_available_power_never_exceeds_the_unconstrained_transfer() {
		install_gases();
		// A big temperature/density gap gives moving gas a nonzero entropy
		// cost one way or the other; whichever direction it is, a zero
		// power budget must never move more than an unconstrained one does.
		let source = air(1000.0, 0.0, 0.0, 400.0);
		let sink_filtered = air(0.0, 0.0, 0.0, 80.0);
		let sink_clean = air(0.0, 0.0, 0.0, 293.15);
		let mask = 1 << GAS_OXYGEN;
		let unconstrained = filter_transfer(&source, &sink_filtered, &sink_clean, mask, Some(1000.0), None, 1.0, 0.04)
			.expect("unconstrained transfer succeeds")
			.total_transfer_moles;
		let starved = filter_transfer(&source, &sink_filtered, &sink_clean, mask, Some(1000.0), Some(0.0), 1.0, 0.04);
		let starved_moles = starved.map_or(0.0, |r| r.total_transfer_moles);
		assert!(starved_moles <= unconstrained + 1e-6);
		assert!(unconstrained > 0.0);
	}

	#[test]
	fn mixer_splits_by_ratio_and_sums_to_the_total() {
		install_gases();
		let a = air(500.0, 0.0, 0.0, 293.15);
		let b = air(0.0, 500.0, 0.0, 293.15);
		let sink = air(0.0, 0.0, 0.0, 293.15);
		let sources = [MixSource { mixture: &a, ratio: 0.3 }, MixSource { mixture: &b, ratio: 0.7 }];
		let result = mix_transfer(&sources, &sink, Some(100.0), None, 1.0, 0.04).expect("enough gas to mix");
		assert!((result.total_transfer_moles - 100.0).abs() < 1e-3);
		assert!((result.moles[0] - 30.0).abs() < 1e-3);
		assert!((result.moles[1] - 70.0).abs() < 1e-3);
	}

	#[test]
	fn mixer_returns_none_with_no_sources() {
		install_gases();
		let sink = air(0.0, 0.0, 0.0, 293.15);
		assert_eq!(mix_transfer(&[], &sink, None, None, 1.0, 0.04), None);
	}

	#[test]
	fn filter_multi_splits_by_output_mask_with_a_catch_all_clean_sink() {
		install_gases();
		let source = air(200.0, 200.0, 200.0, 293.15);
		let o2_sink = air(0.0, 0.0, 0.0, 293.15);
		let co2_sink = air(0.0, 0.0, 0.0, 293.15);
		let clean = air(0.0, 0.0, 0.0, 293.15);
		let outputs = [
			FilterOutput { mask: 1 << GAS_OXYGEN, sink: &o2_sink },
			FilterOutput { mask: 1 << GAS_CARBON_DIOXIDE, sink: &co2_sink },
		];
		let result = filter_transfer_multi(&source, &outputs, &clean, Some(300.0), None, 1.0, 0.04)
			.expect("enough gas to filter");
		assert!((result.total_transfer_moles - 300.0).abs() < 1e-3);
		assert!((result.moles[0] - 200.0).abs() < 1e-3);
		assert!((result.moles[1] - 200.0).abs() < 1e-3);
		assert!((result.clean_moles - 200.0).abs() < 1e-3);
	}
}
