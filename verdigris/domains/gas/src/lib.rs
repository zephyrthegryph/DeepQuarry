pub mod gas;
mod parser;
pub mod pipenets;
mod reaction;
#[cfg(feature = "turf_processing")]
pub mod turfs;

use byondapi::prelude::*;
use eyre::Result;
use gas::constants::{ReactionReturn, GAS_MIN_MOLES, MINIMUM_MOLES_DELTA_TO_MOVE};
use gas::{
	amt_gases, constants, gas_idx_from_string, gas_idx_from_value, tot_gases, types, with_gas_info,
	with_mix, with_mix_mut, with_mixes, with_mixes_custom, with_mixes_mut, GasArena, Mixture,
};
use pipenets::PIPE_TOPOLOGY;
use reaction::react_by_id;

// global_allocator declaration removed (was mimalloc::MiMalloc). A cdylib
// can have only one global_allocator and auxmos is now linked as an rlib into
// libverdigris.so; the verdigris crate sets the allocator (or the system default
// applies). See code/ATMOSPHERICS/README.md.

static _SIMD_DETECTED: ::std::sync::OnceLock<bool> = ::std::sync::OnceLock::new();

/// Apply one complete DM pipe-topology transaction and return the authoritative
/// connected regions. Input is compact text with semicolon-delimited,
/// comma-separated four-number records:
/// `opcode, first, second_or_mixture, volume` where opcodes are upsert=1,
/// remove=2, connect=3, disconnect=4, clear=5, bind-region-mixture=6,
/// remove-to-mixture=7. Output
/// repeats a variable record:
/// `region, port_count, prior_count, source_count, volume, ports...,
/// prior_region/volume pairs...,
/// source_mixture/ratio pairs...`. No gas rebinding is visible until the entire
/// batch commits.
#[auxmacros::bind("/proc/auxmos_pipenet_topology_batch")]
fn pipenet_topology_batch(operations: ByondValue) -> Result<ByondValue> {
	let encoded = operations.get_string()?;
	let mut topology = PIPE_TOPOLOGY.lock();
	for (operation_index, record) in encoded.split_terminator(';').enumerate() {
		let fields = record.split(',').collect::<Vec<_>>();
		if fields.len() != 4 {
			eyre::bail!(
				"pipenet operation {operation_index} does not contain four fields: {record}"
			);
		}
		let parse = |index: usize| -> Result<f32> {
			fields[index].parse::<f32>().map_err(|error| {
				eyre::eyre!(
					"invalid pipenet number '{}' at operation {operation_index}: {error}",
					fields[index]
				)
			})
		};
		let opcode = parse(0)? as u8;
		match opcode {
			1 => topology.upsert_port(parse(1)? as u32, parse(2)? as usize, parse(3)?),
			2 => topology.remove_port(parse(1)? as u32),
			3 => {
				let first = parse(1)? as u32;
				let second = parse(2)? as u32;
				if !topology.connect(first, second) {
					eyre::bail!("invalid pipenet connection {first}<->{second}");
				}
			}
			4 => topology.disconnect(parse(1)? as u32, parse(2)? as u32),
			5 => topology.clear(),
			6 => {
				let first = parse(1)? as u32;
				let second = parse(2)? as usize;
				if !topology.bind_region_mixture(first, second) {
					eyre::bail!("cannot bind missing pipenet region {first}");
				}
			}
			7 => topology.remove_port_to(parse(1)? as u32, parse(2)? as usize, parse(3)?),
			_ => eyre::bail!(
				"unknown pipenet topology opcode {opcode} at operation {operation_index}: {record}"
			),
		}
	}
	let transitions = topology.commit();
	let mut result = Vec::new();
	for transition in transitions {
		if let Some(detached_target) = transition.detached_target {
			result.extend([
				ByondValue::from(0.0),
				ByondValue::from(1.0),
				ByondValue::from(0.0),
				ByondValue::from(transition.sources.len() as f32),
				ByondValue::from(transition.total_volume),
				ByondValue::from(detached_target as f32),
			]);
			result.extend(transition.sources.into_iter().flat_map(|source| {
				[
					ByondValue::from(source.mixture as f32),
					ByondValue::from(source.ratio),
				]
			}));
			continue;
		}
		result.extend([
			ByondValue::from(transition.region as f32),
			ByondValue::from(transition.ports.len() as f32),
			ByondValue::from(transition.prior_regions.len() as f32),
			ByondValue::from(transition.sources.len() as f32),
			ByondValue::from(if transition.retired {
				-1.0
			} else {
				transition.total_volume
			}),
		]);
		result.extend(
			transition
				.ports
				.into_iter()
				.map(|value| ByondValue::from(value as f32)),
		);
		result.extend(
			transition
				.prior_regions
				.into_iter()
				.flat_map(|(region, volume)| {
					[ByondValue::from(region as f32), ByondValue::from(volume)]
				}),
		);
		result.extend(transition.sources.into_iter().flat_map(|source| {
			[
				ByondValue::from(source.mixture as f32),
				ByondValue::from(source.ratio),
			]
		}));
	}
	let list = ByondValue::new_list()?;
	list.write_list(&result)?;
	Ok(list)
}

/// Materialize the gas recipes returned by `auxmos_pipenet_topology_batch` and
/// bind their public arena mixtures. Input is semicolon-delimited text and each
/// comma-separated record repeats:
/// `region, target_mixture, volume, source_count, source_mixture/ratio pairs...`.
/// Every source is snapshotted before any target changes and all bindings become
/// authoritative only after the gas transaction succeeds.
#[auxmacros::bind("/proc/auxmos_pipenet_publish_regions")]
fn pipenet_publish_regions(publications: ByondValue) -> Result<ByondValue> {
	let encoded = publications.get_string()?;
	let mut recipes = Vec::new();
	let mut bindings = Vec::new();
	for (record_index, record) in encoded.split_terminator(';').enumerate() {
		let fields = record.split(',').collect::<Vec<_>>();
		if fields.len() < 4 {
			eyre::bail!("truncated pipenet publication header at record {record_index}");
		}
		let parse = |index: usize| -> Result<f32> {
			fields[index].parse::<f32>().map_err(|error| {
				eyre::eyre!(
					"invalid pipenet publication number '{}' at record {record_index}: {error}",
					fields[index]
				)
			})
		};
		let region = parse(0)? as u32;
		let target = parse(1)? as usize;
		let volume = parse(2)?;
		let source_count = parse(3)? as usize;
		if fields.len() != 4 + source_count.saturating_mul(2) {
			eyre::bail!("pipenet publication {record_index} has the wrong source field count");
		}
		let mut sources = Vec::with_capacity(source_count);
		for source_index in 0..source_count {
			let offset = 4 + source_index * 2;
			sources.push((parse(offset)? as usize, parse(offset + 1)?));
		}
		recipes.push((target, volume, sources));
		if region != 0 {
			bindings.push((region, target));
		}
	}
	let mut topology = PIPE_TOPOLOGY.lock();
	GasArena::rebalance_pipe_regions(&recipes)?;
	for (region, mixture) in bindings {
		if !topology.bind_region_mixture(region, mixture) {
			eyre::bail!("cannot publish missing pipenet region {region}");
		}
	}
	Ok(ByondValue::from(true))
}

#[cfg(feature = "tracy")]
#[byondapi::init]
pub fn init_eyre() {
	use tracing_subscriber::layer::SubscriberExt;

	tracing::subscriber::set_global_default(
		tracing_subscriber::registry().with(tracing_tracy::TracyLayer::default()),
	)
	.expect("setup tracy layer");
}

/// Args: (ms). Runs callbacks until time limit is reached. If time limit is omitted, runs all callbacks.
#[auxmacros::bind("/proc/process_atmos_callbacks")]
fn atmos_callback_handle(remaining: ByondValue) -> Result<ByondValue> {
	auxcallback::callback_processing_hook(remaining)
}

#[auxmacros::bind("/proc/drain_dirty_gas_mixtures")]
fn drain_dirty_gas_mixtures() -> Result<ByondValue> {
	let changes = GasArena::take_dirty_mixtures()
		.into_iter()
		.flat_map(|(id, mask)| [ByondValue::from(id as f32), ByondValue::from(mask as f32)])
		.collect::<Vec<_>>();
	let list = ByondValue::new_list()?;
	list.write_list(&changes)?;
	Ok(list)
}

/// Floats per record returned by `drain_dirty_gas_observations`.
/// @dm-define GAS_DEPENDENCY_OBSERVATION_STRIDE
pub const GAS_OBSERVATION_STRIDE: usize = 15;

/// Drains dirty notifications and captures the control-relevant gas state under
/// one publication read transaction. This lets hundreds of sleeping air alarms
/// evaluate thresholds without each crossing the FFI boundary seven times.
/// Flat stride: id, mask, revision, pressure, temperature, volume,
/// o2, co2, plasma, methane, n2o, volatile_fuel, miasma, zauker, total_moles.
#[auxmacros::bind("/proc/drain_dirty_gas_observations")]
fn drain_dirty_gas_observations() -> Result<ByondValue> {
	let changes = GasArena::take_dirty_mixtures();
	let gas_indices = [
		gas::GAS_OXYGEN,
		gas::GAS_CARBON_DIOXIDE,
		gas::GAS_PLASMA,
		gas::GAS_METHANE,
		gas::GAS_NITROUS_OXIDE,
		gas::GAS_VOLATILE_FUEL,
		gas::GAS_MIASMA,
		gas::GAS_ZAUKER,
	];
	let values = GasArena::with_all_mixtures(|gases| {
		let mut values = Vec::with_capacity(changes.len() * GAS_OBSERVATION_STRIDE);
		for &(id, mask) in &changes {
			let Some(mixture) = gases.get(id) else {
				continue;
			};
			let mixture = mixture.read();
			values.extend([
				id as f32,
				mask as f32,
				GasArena::revision(id) as f32,
				mixture.return_pressure(),
				mixture.get_temperature(),
				mixture.volume,
			]);
			values.extend(gas_indices.iter().map(|&gas| mixture.get_moles(gas)));
			values.push(mixture.total_moles());
		}
		values
	});
	let list = ByondValue::new_list()?;
	list.write_list(&values.into_iter().map(ByondValue::from).collect::<Vec<_>>())?;
	Ok(list)
}

#[auxmacros::bind("/proc/watch_dirty_gas_mixture")]
fn watch_dirty_gas_mixture(id: ByondValue, interest_mask: ByondValue) -> Result<ByondValue> {
	GasArena::watch_dirty_mixture(id.get_number()? as usize, interest_mask.get_number()? as u8);
	Ok(ByondValue::null())
}

#[auxmacros::bind("/proc/unwatch_dirty_gas_mixture")]
fn unwatch_dirty_gas_mixture(id: ByondValue) -> Result<ByondValue> {
	GasArena::unwatch_dirty_mixture(id.get_number()? as usize);
	Ok(ByondValue::null())
}

#[cfg(feature = "turf_processing")]
#[auxmacros::bind("/datum/controller/subsystem/air/proc/auxmos_diagnostics")]
fn auxmos_diagnostics() -> Result<ByondValue> {
	let gas = GasArena::diagnostics();
	let turf = turfs::turf_arena_diagnostics();
	#[cfg(feature = "heat")]
	let heat = turfs::heat::heat_diagnostics();
	#[cfg(not(feature = "heat"))]
	let heat = (0, 0, 0);
	let values = [
		gas.0,
		gas.1,
		gas.2,
		gas.3,
		gas.4,
		gas.5,
		turf.0,
		turf.1,
		turf.2,
		turf.3,
		turfs::pending_active_turfs(),
		auxcallback::pending_callbacks(),
		heat.0,
		heat.1,
		heat.2 as usize,
		turf.4,
		turf.5,
	]
	.into_iter()
	.map(|value| ByondValue::from(value as f32))
	.collect::<Vec<_>>();
	let list = ByondValue::new_list()?;
	list.write_list(&values)?;
	Ok(list)
}

/// Fills in the first unused slot in the gas mixtures vector, or adds another one, then sets the argument ByondValue to point to it.
#[auxmacros::bind("/datum/gas_mixture/proc/__gasmixture_register")]
fn register_gasmixture_hook(src: ByondValue) -> Result<ByondValue> {
	gas::GasArena::register_mix(src)
}

/// Adds the gas mixture's ID to the queue of mixtures that have been deleted, to be reused later.
/// This version is only if auxcleanup is not being used; it should be called from /datum/gas_mixture/Del.
#[auxmacros::bind("/datum/gas_mixture/proc/__gasmixture_unregister")]
fn unregister_gasmixture_hook(src: ByondValue) -> Result<ByondValue> {
	gas::GasArena::unregister_mix(&src);
	Ok(ByondValue::null())
}

/// Returns: Heat capacity, in J/K (probably).
#[auxmacros::bind("/datum/gas_mixture/proc/heat_capacity")]
fn heat_cap_hook(src: ByondValue) -> Result<ByondValue> {
	with_mix(&src, |mix| Ok(mix.heat_capacity().into()))
}

/// Args: (min_heat_cap). Sets the mix's minimum heat capacity.
#[auxmacros::bind("/datum/gas_mixture/proc/set_min_heat_capacity")]
fn min_heat_cap_hook(src: ByondValue, arg_min: ByondValue) -> Result<ByondValue> {
	let min = arg_min.get_number()?;
	with_mix_mut(&src, |mix| {
		mix.set_min_heat_capacity(min);
		Ok(ByondValue::null())
	})
}

/// Returns: Amount of substance, in moles.
#[auxmacros::bind("/datum/gas_mixture/proc/total_moles")]
fn total_moles_hook(src: ByondValue) -> Result<ByondValue> {
	with_mix(&src, |mix| Ok(mix.total_moles().into()))
}

/// Returns: the mix's pressure, in kilopascals.
#[auxmacros::bind("/datum/gas_mixture/proc/return_pressure")]
fn return_pressure_hook(src: ByondValue) -> Result<ByondValue> {
	with_mix(&src, |mix| Ok(mix.return_pressure().into()))
}

/// Returns: the mix's temperature, in kelvins.
#[auxmacros::bind("/datum/gas_mixture/proc/return_temperature")]
fn return_temperature_hook(src: ByondValue) -> Result<ByondValue> {
	with_mix(&src, |mix| Ok(mix.get_temperature().into()))
}

/// Returns: the mix's volume, in liters.
#[auxmacros::bind("/datum/gas_mixture/proc/return_volume")]
fn return_volume_hook(src: ByondValue) -> Result<ByondValue> {
	with_mix(&src, |mix| Ok(mix.volume.into()))
}

/// Returns: the mix's thermal energy, the product of the mixture's heat capacity and its temperature.
#[auxmacros::bind("/datum/gas_mixture/proc/thermal_energy")]
fn thermal_energy_hook(src: ByondValue) -> Result<ByondValue> {
	with_mix(&src, |mix| Ok(mix.thermal_energy().into()))
}

/// Args: (mixture). Merges the gas from the giver into src, without modifying the giver mix.
#[auxmacros::bind("/datum/gas_mixture/proc/merge")]
fn merge_hook(src: ByondValue, giver: ByondValue) -> Result<ByondValue> {
	with_mixes_custom(&src, &giver, |src_mix, giver_mix| {
		src_mix.write().merge(&giver_mix.read());
		Ok(ByondValue::null())
	})
}

/// Args: (mixture, ratio). Takes the given ratio of gas from src and puts it into the argument mixture. Ratio is a number between 0 and 1.
#[auxmacros::bind("/datum/gas_mixture/proc/__remove_ratio")]
fn remove_ratio_hook(
	src: ByondValue,
	into: ByondValue,
	ratio_arg: ByondValue,
) -> Result<ByondValue> {
	let ratio = ratio_arg.get_number().unwrap_or_default();
	with_mixes_mut(&src, &into, |src_mix, into_mix| {
		src_mix.remove_ratio_into(ratio, into_mix);
		Ok(ByondValue::null())
	})
}

/// Args: (mixture, amount). Takes the given amount of gas from src and puts it into the argument mixture. Amount is amount of substance in moles.
#[auxmacros::bind("/datum/gas_mixture/proc/__remove")]
fn remove_hook(src: ByondValue, into: ByondValue, amount_arg: ByondValue) -> Result<ByondValue> {
	let amount = amount_arg.get_number().unwrap_or_default();
	with_mixes_mut(&src, &into, |src_mix, into_mix| {
		src_mix.remove_into(amount, into_mix);
		Ok(ByondValue::null())
	})
}

/// Arg: (mixture). Makes src into a copy of the argument mixture.
#[auxmacros::bind("/datum/gas_mixture/proc/copy_from")]
fn copy_from_hook(src: ByondValue, giver: ByondValue) -> Result<ByondValue> {
	with_mixes_custom(&src, &giver, |src_mix, giver_mix| {
		src_mix.write().copy_from_mutable(&giver_mix.read());
		Ok(ByondValue::null())
	})
}

/// Returns: a flat list `id, moles, id, moles, ...` of every gas present in the
/// mixture, with numeric `GAS_ID_*` IDs. One call replaces a get_gases() plus a
/// get_moles() per gas.
#[auxmacros::bind("/datum/gas_mixture/proc/get_gases")]
fn get_gases_hook(src: ByondValue) -> Result<ByondValue> {
	with_mix(&src, |mix| {
		let mut flat = Vec::new();
		mix.for_each_gas(|idx, moles| {
			if moles > GAS_MIN_MOLES {
				flat.push(ByondValue::from(idx as f32));
				flat.push(ByondValue::from(moles));
			}
			Ok(())
		})?;
		let list = ByondValue::new_list()?;
		list.write_list(&flat)?;
		Ok(list)
	})
}

/// Floats per mixture in `read_mixtures`: pressure, temperature, volume,
/// total moles, heat capacity, then the moles of every gas by ID.
/// @dm-define GAS_READ_HEADER
pub const GAS_READ_HEADER: usize = 5;

/// Batched read. Args: (list of gas mixtures). Returns one flat list with, for
/// each mixture in order, `GAS_READ_HEADER` floats (pressure, temperature,
/// volume, total moles, heat capacity) followed by `GAS_ID_COUNT` mole counts.
/// A null or unregistered entry reads as all zeroes. Used by DM loops that used
/// to call several getters per mixture.
#[auxmacros::bind("/proc/read_mixtures")]
fn read_mixtures(mixtures: ByondValue) -> Result<ByondValue> {
	// get_list_values, not iter(): iter() stops at the first null entry.
	let ids = mixtures
		.get_list_values()?
		.iter()
		.map(|mix| {
			mix.read_number_id(byond_string!("_extools_pointer_gasmixture"))
				.ok()
				.map(|n| n as usize)
		})
		.collect::<Vec<_>>();
	let stride = GAS_READ_HEADER + gas::GAS_COUNT;
	let values = GasArena::with_all_mixtures(|all| {
		let mut values = Vec::with_capacity(ids.len() * stride);
		for id in &ids {
			let Some(mix) = id.and_then(|id| all.get(id)) else {
				values.extend(std::iter::repeat_n(0.0, stride));
				continue;
			};
			let mix = mix.read();
			values.extend([
				mix.return_pressure(),
				mix.get_temperature(),
				mix.volume,
				mix.total_moles(),
				mix.heat_capacity(),
			]);
			values.extend((0..gas::GAS_COUNT).map(|gas| mix.get_moles(gas)));
		}
		values
	});
	let list = ByondValue::new_list()?;
	list.write_list(&values.into_iter().map(ByondValue::from).collect::<Vec<_>>())?;
	Ok(list)
}

/// Args: (temperature). Sets the temperature of the mixture. Will be set to 2.7 if it's too low.
#[auxmacros::bind("/datum/gas_mixture/proc/set_temperature")]
fn set_temperature_hook(src: ByondValue, arg_temp: ByondValue) -> Result<ByondValue> {
	let v = arg_temp.get_number()?;
	if v.is_finite() {
		with_mix_mut(&src, |mix| {
			mix.set_temperature(v.max(2.7));
			Ok(ByondValue::null())
		})
	} else {
		Err(eyre::eyre!(
			"Attempted to set a temperature to a number that is NaN or infinite."
		))
	}
}

/// Args: (gas_id). Returns the heat capacity from the given gas, in J/K (probably).
#[auxmacros::bind("/datum/gas_mixture/proc/partial_heat_capacity")]
fn partial_heat_capacity(src: ByondValue, gas_id: ByondValue) -> Result<ByondValue> {
	with_mix(&src, |mix| {
		Ok(mix
			.partial_heat_capacity(gas_idx_from_value(&gas_id)?)
			.into())
	})
}

/// Args: (volume). Sets the volume of the gas.
#[auxmacros::bind("/datum/gas_mixture/proc/set_volume")]
fn set_volume_hook(src: ByondValue, vol_arg: ByondValue) -> Result<ByondValue> {
	let volume = vol_arg.get_number()?;
	with_mix_mut(&src, |mix| {
		mix.volume = volume;
		Ok(ByondValue::null())
	})
}

/// Args: (gas_id). Returns: the amount of substance of the given gas, in moles.
#[auxmacros::bind("/datum/gas_mixture/proc/get_moles")]
fn get_moles_hook(src: ByondValue, gas_id: ByondValue) -> Result<ByondValue> {
	with_mix(&src, |mix| {
		Ok(mix.get_moles(gas_idx_from_value(&gas_id)?).into())
	})
}

/// Args: (gas_id, moles). Sets the amount of substance of the given gas, in moles.
#[auxmacros::bind("/datum/gas_mixture/proc/set_moles")]
fn set_moles_hook(src: ByondValue, gas_id: ByondValue, amt_val: ByondValue) -> Result<ByondValue> {
	let vf = amt_val.get_number()?;
	if !vf.is_finite() {
		return Err(eyre::eyre!("Attempted to set moles to NaN or infinity."));
	}
	if vf < 0.0 {
		return Err(eyre::eyre!("Attempted to set moles to a negative number."));
	}
	with_mix_mut(&src, |mix| {
		mix.set_moles(gas_idx_from_value(&gas_id)?, vf);
		Ok(ByondValue::null())
	})
}
/// Args: (gas_id, moles). Adjusts the given gas's amount by the given amount, e.g. (GAS_O2, -0.1) will remove 0.1 moles of oxygen from the mixture.
#[auxmacros::bind("/datum/gas_mixture/proc/adjust_moles")]
fn adjust_moles_hook(
	src: ByondValue,
	id_val: ByondValue,
	num_val: ByondValue,
) -> Result<ByondValue> {
	let vf = num_val.get_number().unwrap_or_default();
	with_mix_mut(&src, |mix| {
		mix.adjust_moles(gas_idx_from_value(&id_val)?, vf);
		Ok(ByondValue::null())
	})
}

/// Args: (gas_id, moles, temp). Adjusts the given gas's amount by the given amount, with that gas being treated as if it is at the given temperature.
#[auxmacros::bind("/datum/gas_mixture/proc/adjust_moles_temp")]
fn adjust_moles_temp_hook(
	src: ByondValue,
	id_val: ByondValue,
	num_val: ByondValue,
	temp_val: ByondValue,
) -> Result<ByondValue> {
	let vf = num_val.get_number().unwrap_or_default();
	let temp = temp_val.get_number().unwrap_or(2.7);
	if vf < 0.0 {
		return Err(eyre::eyre!(
			"Attempted to add a negative gas in adjust_moles_temp."
		));
	}
	if !vf.is_normal() {
		return Ok(ByondValue::null());
	}
	let mut new_mix = Mixture::new();
	new_mix.set_moles(gas_idx_from_value(&id_val)?, vf);
	new_mix.set_temperature(temp);
	with_mix_mut(&src, |mix| {
		mix.merge(&new_mix);
		Ok(ByondValue::null())
	})
}

/// Args: (gas_id_1, amount_1, gas_id_2, amount_2, ...). As adjust_moles, but with variadic arguments.
#[auxmacros::bind_raw_args("/datum/gas_mixture/proc/adjust_multi")]
fn adjust_multi_hook() -> Result<ByondValue> {
	if args.len() % 2 == 0 {
		Err(eyre::eyre!(
			"Incorrect arg len for adjust_multi (is even, must be odd to account for src)."
		))
	} else if let Some((src, rest)) = args.split_first() {
		let adjustments = rest
			.chunks(2)
			.filter_map(|chunk| {
				(chunk.len() == 2)
					.then(|| {
						gas_idx_from_value(&chunk[0])
							.ok()
							.map(|idx| (idx, chunk[1].get_number().unwrap_or_default()))
					})
					.flatten()
			})
			.collect::<Vec<_>>();
		with_mix_mut(src, |mix| {
			mix.adjust_multi(&adjustments);
			Ok(ByondValue::null())
		})
	} else {
		Err(eyre::eyre!("Invalid number of args for adjust_multi"))
	}
}

/// Args: (amount). Adds the given amount to each gas.
#[auxmacros::bind("/datum/gas_mixture/proc/add")]
fn add_hook(src: ByondValue, num_val: ByondValue) -> Result<ByondValue> {
	let vf = num_val.get_number().unwrap_or_default();
	with_mix_mut(&src, |mix| {
		mix.add(vf);
		Ok(ByondValue::null())
	})
}

/// Args: (amount). Subtracts the given amount from each gas.
#[auxmacros::bind("/datum/gas_mixture/proc/subtract")]
fn subtract_hook(src: ByondValue, num_val: ByondValue) -> Result<ByondValue> {
	let vf = num_val.get_number().unwrap_or_default();
	with_mix_mut(&src, |mix| {
		mix.add(-vf);
		Ok(ByondValue::null())
	})
}

/// Args: (coefficient). Multiplies all gases by this amount.
#[auxmacros::bind("/datum/gas_mixture/proc/multiply")]
fn multiply_hook(src: ByondValue, num_val: ByondValue) -> Result<ByondValue> {
	let vf = num_val.get_number().unwrap_or(1.0);
	with_mix_mut(&src, |mix| {
		mix.multiply(vf);
		Ok(ByondValue::null())
	})
}

/// Args: (coefficient). Divides all gases by this amount.
#[auxmacros::bind("/datum/gas_mixture/proc/divide")]
fn divide_hook(src: ByondValue, num_val: ByondValue) -> Result<ByondValue> {
	let vf = num_val.get_number().unwrap_or(1.0).recip();
	with_mix_mut(&src, |mix| {
		mix.multiply(vf);
		Ok(ByondValue::null())
	})
}

/// Args: (mixture, flag, amount). Takes `amount` from src that have the given `flag` and puts them into the given `mixture`. Returns: 0 if gas didn't have any with that flag, 1 if it did.
#[auxmacros::bind("/datum/gas_mixture/proc/__remove_by_flag")]
fn remove_by_flag_hook(
	src: ByondValue,
	into: ByondValue,
	flag_val: ByondValue,
	amount_val: ByondValue,
) -> Result<ByondValue> {
	let flag = flag_val.get_number().map_or(0, |n: f32| n as u32);
	let amount = amount_val.get_number().unwrap_or(0.0);
	let pertinent_gases = with_gas_info(|gas_info| {
		gas_info
			.iter()
			.filter(|g| g.flags & flag != 0)
			.map(|g| g.idx)
			.collect::<Vec<_>>()
	});
	if pertinent_gases.is_empty() {
		return Ok(false.into());
	}
	with_mixes_mut(&src, &into, |src_gas, dest_gas| {
		let tot = src_gas.total_moles();
		src_gas.transfer_gases_to(amount / tot, &pertinent_gases, dest_gas);
		Ok(true.into())
	})
}
/// Args: (flag). As get_gases(), but only returns gases with the given flag.
#[auxmacros::bind("/datum/gas_mixture/proc/get_by_flag")]
fn get_by_flag_hook(src: ByondValue, flag_val: ByondValue) -> Result<ByondValue> {
	let flag = flag_val.get_number().map_or(0, |n: f32| n as u32);
	let pertinent_gases = with_gas_info(|gas_info| {
		gas_info
			.iter()
			.filter(|g| g.flags & flag != 0)
			.map(|g| g.idx)
			.collect::<Vec<_>>()
	});
	if pertinent_gases.is_empty() {
		return Ok(0.0.into());
	}
	with_mix(&src, |mix| {
		Ok(pertinent_gases
			.iter()
			.fold(0.0, |acc, idx| acc + mix.get_moles(*idx))
			.into())
	})
}

/// Args: (mixture, ratio, gas_list). Takes gases given by `gas_list` and moves `ratio` amount of those gases from `src` into `mixture`.
#[auxmacros::bind("/datum/gas_mixture/proc/scrub_into")]
fn scrub_into_hook(
	src: ByondValue,
	into: ByondValue,
	ratio_v: ByondValue,
	gas_list: ByondValue,
) -> Result<ByondValue> {
	let ratio = ratio_v.get_number()?;
	if !gas_list.is_list() {
		return Err(eyre::eyre!("Non-list gas_list passed to scrub_into!"));
	}
	if gas_list.builtin_length()?.get_number()? as u32 == 0 {
		return Ok(false.into());
	}
	let gas_scrub_vec = gas_list
		.iter()?
		.filter_map(|(k, _)| gas_idx_from_value(&k).ok())
		.collect::<Vec<_>>();
	with_mixes_mut(&src, &into, |src_gas, dest_gas| {
		src_gas.transfer_gases_to(ratio, &gas_scrub_vec, dest_gas);
		Ok(true.into())
	})
}

/// Marks the mix as immutable, meaning it will never change. This cannot be undone.
#[auxmacros::bind("/datum/gas_mixture/proc/mark_immutable")]
fn mark_immutable_hook(src: ByondValue) -> Result<ByondValue> {
	with_mix_mut(&src, |mix| {
		mix.mark_immutable();
		Ok(ByondValue::null())
	})
}

/// Clears the gas mixture my removing all of its gases.
#[auxmacros::bind("/datum/gas_mixture/proc/clear")]
fn clear_hook(src: ByondValue) -> Result<ByondValue> {
	with_mix_mut(&src, |mix| {
		mix.clear();
		Ok(ByondValue::null())
	})
}

/// Returns: true if the two mixtures are different enough for processing, false otherwise.
#[auxmacros::bind("/datum/gas_mixture/proc/compare")]
fn compare_hook(src: ByondValue, other: ByondValue) -> Result<ByondValue> {
	with_mixes(&src, &other, |gas_one, gas_two| {
		Ok((gas_one.temperature_compare(gas_two)
			|| gas_one.compare_with(gas_two, MINIMUM_MOLES_DELTA_TO_MOVE))
		.into())
	})
}

/// Args: (holder). Runs all reactions on this gas mixture. Holder is used by the reactions, and can be any arbitrary datum or null.
#[auxmacros::bind("/datum/gas_mixture/proc/react")]
fn react_hook(src: ByondValue, holder: ByondValue) -> Result<ByondValue> {
	let mut ret = ReactionReturn::NO_REACTION;
	let reactions = with_mix(&src, |mix| Ok(mix.all_reactable()))?;
	for reaction in reactions {
		ret |= ReactionReturn::from_bits_truncate(
			react_by_id(reaction, src, holder)?
				.get_number()
				.unwrap_or_default() as u32,
		);
		if ret.contains(ReactionReturn::STOP_REACTIONS) {
			return Ok((ret.bits() as f32).into());
		}
	}
	Ok((ret.bits() as f32).into())
}

/// Args: (heat). Adds a given amount of heat to the mixture, i.e. in joules taking into account capacity.
#[auxmacros::bind("/datum/gas_mixture/proc/adjust_heat")]
fn adjust_heat_hook(src: ByondValue, temp: ByondValue) -> Result<ByondValue> {
	with_mix_mut(&src, |mix| {
		mix.adjust_heat(temp.get_number()?);
		Ok(ByondValue::null())
	})
}

/// Args: (mixture, amount). Takes the `amount` given and transfers it from `src` to `mixture`.
#[auxmacros::bind("/datum/gas_mixture/proc/transfer_to")]
fn transfer_hook(src: ByondValue, other: ByondValue, moles: ByondValue) -> Result<ByondValue> {
	with_mixes_mut(&src, &other, |our_mix, other_mix| {
		other_mix.merge(&our_mix.remove(moles.get_number()?));
		Ok(ByondValue::null())
	})
}

/// Flat operation list: source arena ID, sink arena ID, requested moles. Returns
/// one actual mole count per operation after shared-source clamping.
#[auxmacros::bind("/proc/auxmos_batch_transfer")]
fn batch_transfer_hook(operations: ByondValue) -> Result<ByondValue> {
	// Arena ID zero is valid. `ByondValue::iter()` also probes each element as
	// an associative-list key; probing list[0] terminates that iterator, making
	// any batch whose first source is arena slot zero appear empty. `values()`
	// walks the numbered list positions directly and accepts every valid ID.
	let values = operations.values()?.collect::<Vec<_>>();
	let parsed = values
		.chunks_exact(3)
		.map(|operation| {
			let source = operation[0].get_number().unwrap_or(-1.0) as usize;
			let sink = operation[1].get_number().unwrap_or(-1.0) as usize;
			(source, sink, operation[2].get_number().unwrap_or(0.0))
		})
		.collect::<Vec<_>>();
	let results = GasArena::batch_transfer(&parsed)
		.into_iter()
		.map(ByondValue::from)
		.collect::<Vec<_>>();
	let list = ByondValue::new_list()?;
	list.write_list(&results)?;
	Ok(list)
}

/// Flat operation list: pipe mixture, environment mixture, exposed pipe
/// volume. Returns one boolean residual per exposed face.
#[auxmacros::bind("/proc/auxmos_batch_mingle")]
fn batch_mingle_hook(operations: ByondValue) -> Result<ByondValue> {
	let values = operations
		.iter()?
		.map(|(value, _)| value)
		.collect::<Vec<_>>();
	let parsed = values
		.chunks_exact(3)
		.map(|operation| {
			let pipe = operation[0]
				.read_number_id(byond_string!("_extools_pointer_gasmixture"))
				.unwrap_or(-1.0) as usize;
			let environment = operation[1]
				.read_number_id(byond_string!("_extools_pointer_gasmixture"))
				.unwrap_or(-1.0) as usize;
			(pipe, environment, operation[2].get_number().unwrap_or(0.0))
		})
		.collect::<Vec<_>>();
	let results = GasArena::batch_mingle(&parsed)
		.into_iter()
		.map(|residual| ByondValue::from(residual as u8 as f32))
		.collect::<Vec<_>>();
	let list = ByondValue::new_list()?;
	list.write_list(&results)?;
	Ok(list)
}

/// Args: (mixture, ratio). Transfers `ratio` of `src` to `mixture`.
#[auxmacros::bind("/datum/gas_mixture/proc/transfer_ratio_to")]
fn transfer_ratio_hook(
	src: ByondValue,
	other: ByondValue,
	ratio: ByondValue,
) -> Result<ByondValue> {
	with_mixes_mut(&src, &other, |our_mix, other_mix| {
		other_mix.merge(&our_mix.remove_ratio(ratio.get_number()?));
		Ok(ByondValue::null())
	})
}

/// Args: (mixture). Makes `src` a copy of `mixture`, with volumes taken into account.
#[auxmacros::bind("/datum/gas_mixture/proc/equalize_with")]
fn equalize_with_hook(src: ByondValue, total: ByondValue) -> Result<ByondValue> {
	with_mixes_custom(&src, &total, |src_lock, total_lock| {
		let src_gas = &mut src_lock.write();
		let vol = src_gas.volume;
		let total_gas = total_lock.read();
		src_gas.copy_from_mutable(&total_gas);
		src_gas.multiply(vol / total_gas.volume);
		Ok(ByondValue::null())
	})
}

/// Args: (temperature). Returns: how much fuel for fire is in the mixture at the given temperature. If temperature is omitted, just uses current temperature instead.
#[auxmacros::bind("/datum/gas_mixture/proc/get_fuel_amount")]
fn fuel_amount_hook(src: ByondValue, temp: ByondValue) -> Result<ByondValue> {
	with_mix(&src, |air| {
		Ok(temp
			.get_number()
			.ok()
			.map_or_else(
				|| air.get_fuel_amount(),
				|new_temp| {
					let mut test_air = air.copy_to_mutable();
					test_air.set_temperature(new_temp);
					test_air.get_fuel_amount()
				},
			)
			.into())
	})
}

/// Args: (temperature). Returns: how much oxidizer for fire is in the mixture at the given temperature. If temperature is omitted, just uses current temperature instead.
#[auxmacros::bind("/datum/gas_mixture/proc/get_oxidation_power")]
fn oxidation_power_hook(src: ByondValue, temp: ByondValue) -> Result<ByondValue> {
	with_mix(&src, |air| {
		Ok(temp
			.get_number()
			.ok()
			.map_or_else(
				|| air.get_oxidation_power(),
				|new_temp| {
					let mut test_air = air.clone();
					test_air.set_temperature(new_temp);
					test_air.get_oxidation_power()
				},
			)
			.into())
	})
}

/// Args: (mixture, ratio, one_way). Shares the given `ratio` of `src` with `mixture`, and, unless `one_way` is truthy, vice versa.
#[cfg(feature = "zas_hooks")]
#[auxmacros::bind("/datum/gas_mixture/proc/share_ratio")]
fn share_ratio_hook(
	other_gas: ByondValue,
	ratio_val: ByondValue,
	one_way_val: ByondValue,
) -> Result<ByondValue> {
	let one_way = one_way_val.as_bool().unwrap_or(false);
	let ratio = ratio_val.as_number().ok().map_or(0.6);
	let mut inbetween = Mixture::new();
	if one_way {
		with_mixes_custom(src, other_gas, |src_lock, other_lock| {
			let src_mix = src_lock.write();
			let other_mix = other_lock.read();
			inbetween.copy_from_mutable(other_mix);
			inbetween.multiply(ratio);
			inbetween.merge(&src_mix.remove_ratio(ratio));
			inbetween.multiply(0.5);
			src_mix.merge(inbetween);
			Ok(ByondValue::from(
				src_mix.temperature_compare(other_mix)
					|| src_mix.compare_with(other_mix, MINIMUM_MOLES_DELTA_TO_MOVE),
			))
		})
	} else {
		with_mixes_mut(src, other_gas, |src_mix, other_mix| {
			src_mix.remove_ratio_into(ratio, &mut inbetween);
			inbetween.merge(&other_mix.remove_ratio(ratio));
			inbetween.multiply(0.5);
			src_mix.merge(inbetween);
			other_mix.merge(inbetween);
			Ok(ByondValue::from(
				src_mix.temperature_compare(other_mix)
					|| src_mix.compare_with(other_mix, MINIMUM_MOLES_DELTA_TO_MOVE),
			))
		})
	}
}

fn mixture_ids_from_byond_list(gas_list: ByondValue) -> Result<Vec<usize>> {
	use std::collections::BTreeSet;
	Ok(gas_list
		.iter()?
		.filter_map(|(value, _)| {
			value
				.read_number_id(byond_string!("_extools_pointer_gasmixture"))
				.ok()
				.map(|f| f as usize)
		})
		.collect::<BTreeSet<_>>()
		.into_iter()
		.collect())
}

/// B14: this used to write through `with_all_mixtures`, which skips the mutation
/// gate, so a concurrent solver publication could overwrite (or be overwritten by)
/// the equalized values. It now holds the gate for the read, the writes and the
/// revision bumps.
fn equalize_mixture_ids(gas_list: &[usize]) {
	GasArena::with_all_mixtures_mut(move |all_mixtures| {
		let mut tot = gas::Mixture::new();
		let mut tot_vol: f64 = 0.0;
		gas_list
			.iter()
			.filter_map(|&id| all_mixtures.get(id))
			.for_each(|src_gas_lock| {
				let src_gas = src_gas_lock.read();
				tot.merge(&src_gas);
				tot_vol += f64::from(src_gas.volume);
			});
		if tot_vol <= 0.0 {
			return;
		}
		for (id, dest_gas_lock) in gas_list
			.iter()
			.filter_map(|&id| all_mixtures.get(id).map(|mixture| (id, mixture)))
		{
			let (before, after) = {
				let dest_gas = &mut dest_gas_lock.write();
				let before = GasArena::change_signature(dest_gas);
				let vol = dest_gas.volume; // don't wanna borrow it in the below
				dest_gas.copy_from_mutable(&tot);
				dest_gas.multiply((f64::from(vol) / tot_vol) as f32);
				(before, GasArena::change_signature(dest_gas))
			};
			GasArena::bump_revision(id);
			GasArena::mark_dirty_if_changed(id, before, after);
		}
	});
}

/// Args: (list). Takes every gas in the list and makes them all identical, scaled to their respective volumes. The total heat and amount of substance in all of the combined gases is conserved.
#[auxmacros::bind("/proc/equalize_all_gases_in_list")]
fn equalize_all_hook(gas_list: ByondValue) -> Result<ByondValue> {
	let gas_list = mixture_ids_from_byond_list(gas_list)?;
	equalize_mixture_ids(&gas_list);
	Ok(ByondValue::null())
}

/// Returns: the amount of gas mixtures that are attached to a byond gas mixture.
#[auxmacros::bind("/datum/controller/subsystem/air/proc/get_amt_gas_mixes")]
fn hook_amt_gas_mixes() -> Result<ByondValue> {
	Ok((amt_gases() as f32).into())
}

/// Returns: the total amount of gas mixtures in the arena, including "free" ones.
#[auxmacros::bind("/datum/controller/subsystem/air/proc/get_max_gas_mixes")]
fn hook_max_gas_mixes() -> Result<ByondValue> {
	Ok((tot_gases() as f32).into())
}
/// Returns: true. Parses gas strings like "o2=2500;plasma=5000;TEMP=370" and turns src mixes into the parsed gas mixture, invalid patterns will be ignored
#[auxmacros::bind("/datum/gas_mixture/proc/__auxtools_parse_gas_string")]
fn parse_gas_string(src: ByondValue, string: ByondValue) -> Result<ByondValue> {
	let actual_string = string.get_string()?;

	let (_, vec) = parser::parse_gas_string(&actual_string)
		.map_err(|_| eyre::eyre!(format!("Failed to parse gas string: {actual_string}")))?;

	with_mix_mut(&src, move |air| {
		air.clear();
		for (gas, moles) in vec.iter() {
			if let Ok(idx) = gas_idx_from_string(gas) {
				if (*moles).is_normal() && *moles > 0.0 {
					air.set_moles(idx, *moles)
				}
			} else if gas.contains("TEMP") {
				let mut checked_temp = *moles;
				if !checked_temp.is_normal() || checked_temp < constants::TCMB {
					checked_temp = constants::TCMB
				}
				air.set_temperature(checked_temp)
			} else {
				return Err(eyre::eyre!(format!("Unknown gas id: {gas}")));
			}
		}
		Ok(())
	})?;
	Ok(true.into())
}
