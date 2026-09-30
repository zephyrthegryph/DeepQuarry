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
	let molar_mass = crate::gate::with(|g| g.gases.get(idx).map_or(0.0, |gas| gas.molar_mass));
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
	let air_temperature = if sink_temperature > 0.0 {
		sink_temperature
	} else {
		source.get_temperature()
	};
	let specific_entropy = specific_entropy_gas(idx, sink) - specific_entropy_gas(idx, source);
	if specific_entropy < 0.0 {
		-specific_entropy * air_temperature
	} else {
		0.0
	}
}

/// `_atmospherics_helpers.dm`'s `calculate_specific_power()`: the
/// whole-mixture version `mix_gas()` uses (one figure per source, not one
/// per gas -- a mixer doesn't split a source's own composition).
fn specific_power(source: &Mixture, sink: &Mixture) -> f32 {
	let sink_temperature = sink.get_temperature();
	let air_temperature = if sink_temperature > 0.0 {
		sink_temperature
	} else {
		source.get_temperature()
	};
	let specific_entropy = specific_entropy(sink) - specific_entropy(source);
	if specific_entropy < 0.0 {
		-specific_entropy * air_temperature
	} else {
		0.0
	}
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
		total_mixing_moles =
			Some(total_mixing_moles.map_or(this_mixing_moles, |m: f32| m.min(this_mixing_moles)));
		let power = specific_power(src.mixture, sink) * src.ratio / efficiency;
		source_specific_power.push(power);
		total_specific_power += power;
	}

	let total_mixing_moles = total_mixing_moles?;
	if total_mixing_moles < min_moles_to_filter {
		return None;
	}

	let mut total_transfer_moles =
		requested.map_or(total_mixing_moles, |r| r.min(total_mixing_moles));
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

	Some(MixTransfer {
		total_transfer_moles,
		moles,
		power_draw,
	})
}

// ---------------------------------------------------------------------------
// Pumps, scrubbers, equalisation and thermal exchange: the rest of the DM
// atmos helpers' maths (`_atmospherics_helpers.dm`), now one place.
// ---------------------------------------------------------------------------

/// `calculate_specific_power()`: the power (W/mol) to move one mole of
/// `source`'s mixture into `sink` (zero when the move is downhill).
#[must_use]
pub fn pump_specific_power(source: &Mixture, sink: &Mixture) -> f32 {
	specific_power(source, sink)
}

/// `calculate_equalize_moles()`: the moles that would bring `source` and
/// `sink` to one pressure, taking both temperatures as unchanged.
#[must_use]
pub fn equalize_moles(source: &Mixture, sink: &Mixture) -> f32 {
	let source_temperature = source.get_temperature();
	if source_temperature == 0.0 || source.volume <= 0.0 || sink.volume <= 0.0 {
		return 0.0;
	}
	(source.return_pressure() - sink.return_pressure())
		/ (R_IDEAL_GAS_EQUATION
			* (source_temperature / source.volume + sink.get_temperature() / sink.volume))
}

/// A pump's plan, from [`pump_plan`].
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct PumpTransfer {
	/// Moles to move from source to sink.
	pub moles: f32,
	/// Power drawn moving them (W over one second).
	pub power_draw: f32,
	/// The source volume the moved moles represent (litres): the flow meter.
	pub flow_volume: f32,
}

/// `pump_gas()` / `pump_gas_passive()` minus the movement: how much of
/// `source` moves into `sink` and what it costs. `requested` caps the moles
/// (`None`: all of them), `available_power` caps the moles by the entropy
/// cost (`None`: uncapped); `efficiency` divides the specific power
/// (`ATMOS_PUMP_EFFICIENCY * material_pump_efficiency()/0.8`). A `passive`
/// pump is capped by pressure equalisation instead and draws nothing.
/// `None` is `pump_gas()`'s `-1`.
#[must_use]
pub fn pump_plan(
	source: &Mixture,
	sink: &Mixture,
	requested: Option<f32>,
	available_power: Option<f32>,
	efficiency: f32,
	min_moles: f32,
	passive: bool,
) -> Option<PumpTransfer> {
	let source_moles = source.total_moles();
	if source_moles < min_moles {
		return None;
	}
	let mut moles = requested.map_or(source_moles, |r| r.min(source_moles));
	let mut specific = 0.0;
	if passive {
		moles = moles.min(equalize_moles(source, sink));
	} else {
		specific = specific_power(source, sink) / efficiency;
		if let Some(power) = available_power {
			if specific > 0.0 {
				moles = moles.min(power / specific);
			}
		}
	}
	if moles.is_nan() || moles < min_moles {
		return None;
	}
	Some(PumpTransfer {
		moles,
		power_draw: specific * moles,
		flow_volume: moles / source_moles * source.volume,
	})
}

/// A scrubber's plan, from [`scrub_plan`].
#[derive(Clone, Debug, PartialEq)]
pub struct ScrubTransfer {
	/// `(gas, moles)` to move, each scrubbed gas in proportion to its share.
	pub gases: Vec<(usize, f32)>,
	/// Every gas of the filter below the trace threshold, moved whole
	/// regardless of the budget (the remainder of a nearly-cleaned mix).
	pub trace: Vec<(usize, f32)>,
	/// Total moles scrubbed (`gases`' sum).
	pub moles: f32,
	/// Power drawn (W over one second).
	pub power_draw: f32,
	/// The source volume the scrubbed moles represent (litres).
	pub flow_volume: f32,
}

/// `scrub_gas()` minus the movement. `filtering` is a `1 << gas_id` set;
/// `min_moles` is `MINIMUM_MOLES_TO_FILTER`. The trace moves are reported
/// even when the budget is `None` (`scrub_gas()` did them before it decided).
#[must_use]
pub fn scrub_plan(
	source: &Mixture,
	sink: &Mixture,
	filtering: u32,
	requested: Option<f32>,
	available_power: Option<f32>,
	efficiency: f32,
	min_moles: f32,
) -> (Option<ScrubTransfer>, Vec<(usize, f32)>) {
	let source_moles = source.total_moles();
	if source_moles < min_moles {
		return (None, Vec::new());
	}
	let moles = source.moles_array();
	let mut trace = Vec::new();
	let mut present: Vec<(usize, f32, f32)> = Vec::new(); // gas, moles, specific power
	let mut total_filterable = 0.0;
	for (g, &n) in moles.iter().enumerate() {
		if filtering & (1 << g) == 0 || n <= 0.0 {
			continue;
		}
		if n < min_moles {
			trace.push((g, n));
			continue;
		}
		let power = specific_power_gas(g, source, sink) / efficiency;
		present.push((g, n, power));
		total_filterable += n;
	}
	if total_filterable < min_moles {
		return (None, trace);
	}
	let total_specific_power: f32 = present
		.iter()
		.map(|&(_, n, p)| p * n / total_filterable)
		.sum();
	let mut total = requested.map_or(total_filterable, |r| r.min(total_filterable));
	if let Some(power) = available_power {
		if total_specific_power > 0.0 {
			total = total.min(power / total_specific_power);
		}
	}
	if total < min_moles {
		return (None, trace);
	}
	let mut gases = Vec::with_capacity(present.len());
	let mut power_draw = 0.0;
	let mut moved = 0.0;
	for &(g, n, p) in &present {
		let t = n.min(total * (n / total_filterable));
		power_draw += p * t;
		moved += t;
		gases.push((g, t));
	}
	(
		Some(ScrubTransfer {
			gases,
			trace: trace.clone(),
			moles: moved,
			power_draw,
			flow_volume: total / source_moles * source.volume,
		}),
		trace,
	)
}

/// Heat exchange between `air` (the share of it, `share_volume` of its own
/// volume, in contact) and something else at `other_temperature` with
/// `other_capacity` J/K (another mixture's, or a wall's): moves
/// `conductivity * dT * series capacity` joules, `air` losing what the
/// other gains. Returns the joules that left `air` (negative: it gained).
/// `pipeline.temperature_interact()`'s one formula.
#[must_use]
pub fn thermal_exchange(
	air: &mut Mixture,
	share_volume: f32,
	conductivity: f32,
	other_temperature: f32,
	other_capacity: f32,
) -> f32 {
	let total = air.heat_capacity();
	if air.volume <= 0.0 || total <= 0.0 {
		return 0.0;
	}
	let partial = total * (share_volume / air.volume);
	if !(other_capacity > 0.0 && partial > 0.0) {
		return 0.0;
	}
	let heat = conductivity
		* (air.get_temperature() - other_temperature)
		* (partial * other_capacity / (partial + other_capacity));
	air.adjust_heat(-heat);
	heat
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

	fn install_gases() {}

	#[test]
	fn filter_moves_only_the_masked_gas_and_conserves_the_split() {
		install_gases();
		let source = air(200.0, 200.0, 0.0, 293.15);
		let sink_filtered = air(0.0, 0.0, 0.0, 293.15);
		let sink_clean = air(0.0, 0.0, 0.0, 293.15);
		let mask = 1 << GAS_CARBON_DIOXIDE;
		let result = filter_transfer(
			&source,
			&sink_filtered,
			&sink_clean,
			mask,
			Some(100.0),
			None,
			1.0,
			0.04,
		)
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
		assert_eq!(
			filter_transfer(
				&source,
				&sink_filtered,
				&sink_clean,
				0,
				None,
				None,
				1.0,
				0.04
			),
			None
		);
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
		let unconstrained = filter_transfer(
			&source,
			&sink_filtered,
			&sink_clean,
			mask,
			Some(1000.0),
			None,
			1.0,
			0.04,
		)
		.expect("unconstrained transfer succeeds")
		.total_transfer_moles;
		let starved = filter_transfer(
			&source,
			&sink_filtered,
			&sink_clean,
			mask,
			Some(1000.0),
			Some(0.0),
			1.0,
			0.04,
		);
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
		let sources = [
			MixSource {
				mixture: &a,
				ratio: 0.3,
			},
			MixSource {
				mixture: &b,
				ratio: 0.7,
			},
		];
		let result =
			mix_transfer(&sources, &sink, Some(100.0), None, 1.0, 0.04).expect("enough gas to mix");
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
			FilterOutput {
				mask: 1 << GAS_OXYGEN,
				sink: &o2_sink,
			},
			FilterOutput {
				mask: 1 << GAS_CARBON_DIOXIDE,
				sink: &co2_sink,
			},
		];
		let result = filter_transfer_multi(&source, &outputs, &clean, Some(300.0), None, 1.0, 0.04)
			.expect("enough gas to filter");
		assert!((result.total_transfer_moles - 300.0).abs() < 1e-3);
		assert!((result.moles[0] - 200.0).abs() < 1e-3);
		assert!((result.moles[1] - 200.0).abs() < 1e-3);
		assert!((result.clean_moles - 200.0).abs() < 1e-3);
	}

	#[test]
	fn a_pump_moves_what_the_power_allows_and_conserves_moles() {
		let source = air(200.0, 0.0, 0.0, 293.15);
		let sink = air(500.0, 0.0, 0.0, 293.15);
		let unlimited = pump_plan(&source, &sink, Some(50.0), None, 1.0, 0.01, false).unwrap();
		assert!((unlimited.moles - 50.0).abs() < 1e-3);
		assert!(unlimited.power_draw > 0.0, "moving gas uphill costs power");
		let budget = unlimited.power_draw * 0.5;
		let limited =
			pump_plan(&source, &sink, Some(50.0), Some(budget), 1.0, 0.01, false).unwrap();
		assert!(limited.moles < unlimited.moles);
		assert!(
			limited.power_draw <= budget * 1.001,
			"{limited:?} within {budget}"
		);
	}

	#[test]
	fn a_passive_pump_stops_at_equal_pressure_and_draws_nothing() {
		let source = air(400.0, 0.0, 0.0, 293.15);
		let sink = air(100.0, 0.0, 0.0, 293.15);
		let plan = pump_plan(&source, &sink, None, None, 1.0, 0.01, true).unwrap();
		assert_eq!(plan.power_draw, 0.0);
		// Equal volumes and temperatures: half the difference moves.
		assert!((plan.moles - 150.0).abs() < 0.5, "{plan:?}");
		let level = air(100.0, 0.0, 0.0, 293.15);
		assert!(pump_plan(&level, &level, None, None, 1.0, 0.01, true).is_none());
	}

	#[test]
	fn a_scrubber_takes_only_the_filtered_gas_in_proportion() {
		let source = air(100.0, 60.0, 20.0, 293.15);
		let sink = air(0.0, 0.0, 0.0, 293.15);
		let mask = (1 << GAS_CARBON_DIOXIDE) | (1 << GAS_PLASMA);
		let (plan, trace) = scrub_plan(&source, &sink, mask, Some(40.0), None, 1.0, 0.04);
		let plan = plan.expect("plenty to scrub");
		assert!(trace.is_empty());
		assert!((plan.moles - 40.0).abs() < 1e-3, "{plan:?}");
		let co2 = plan
			.gases
			.iter()
			.find(|g| g.0 == GAS_CARBON_DIOXIDE)
			.unwrap()
			.1;
		let plasma = plan.gases.iter().find(|g| g.0 == GAS_PLASMA).unwrap().1;
		assert!(
			(co2 / plasma - 3.0).abs() < 1e-2,
			"shares follow the mix: {co2} {plasma}"
		);
		assert!(plan.gases.iter().all(|g| g.0 != GAS_OXYGEN));
	}

	#[test]
	fn a_scrubber_moves_the_trace_even_when_nothing_else_moves() {
		let source = air(100.0, 0.01, 0.0, 293.15);
		let sink = air(0.0, 0.0, 0.0, 293.15);
		let (plan, trace) = scrub_plan(
			&source,
			&sink,
			1 << GAS_CARBON_DIOXIDE,
			None,
			None,
			1.0,
			0.04,
		);
		assert!(plan.is_none());
		assert_eq!(trace.len(), 1);
		assert!((trace[0].1 - 0.01).abs() < 1e-6);
	}

	#[test]
	fn thermal_exchange_conserves_energy_between_two_mixtures() {
		let mut a = air(100.0, 0.0, 0.0, 400.0);
		let b = air(100.0, 0.0, 0.0, 300.0);
		let (total_before, other_before) = (a.thermal_energy(), b.thermal_energy());
		let heat = thermal_exchange(&mut a, 2500.0, 0.5, b.get_temperature(), b.heat_capacity());
		assert!(heat > 0.0);
		assert!((a.thermal_energy() - (total_before - heat)).abs() < 1.0);
		assert!((other_before + heat) > other_before);
	}

	#[test]
	fn thermal_exchange_with_nothing_to_exchange_with_moves_nothing() {
		let mut a = air(100.0, 0.0, 0.0, 400.0);
		assert_eq!(thermal_exchange(&mut a, 2500.0, 0.5, 300.0, 0.0), 0.0);
		assert_eq!(a.get_temperature(), 400.0);
	}
}
