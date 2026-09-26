//! vg-gas: the gas domain (`simulation.md` §4). Turf gas runs on the R6
//! field framework (`cell.rs`, `world.rs`), pipes on the R7 network
//! framework (`pipes.rs`), and every `/datum/gas_mixture` is a handle into
//! the gas world (`world.rs`), whoever owns the gas. The DM gas API is the
//! set of binds below.

pub mod cell;
pub mod device;
pub mod gas;
pub mod gate;
pub mod laws;
pub mod kind;
mod parser;
pub mod pipes;
pub mod planet;
pub mod power_budget;
mod reaction;
pub mod turf;
pub mod world;

use byondapi::prelude::*;
use eyre::Result;
use gas::constants::{ReactionReturn, GAS_MIN_MOLES, MINIMUM_MOLES_DELTA_TO_MOVE};
use gas::{
	amt_gases, constants, gas_idx_from_string, missing, tot_gases, types, with_gas_info, with_mix,
	with_mix_mut, with_mixes, with_mixes_mut, Mixture,
};
use world::{with_world, MixRef};

/// Reads a `GAS_ID_*` `ByondValue`, then defers to the pure lookup
/// (`gas/types.rs`'s own docs, `rust_architecture.md` step 6 decision 1):
/// this thin wrapper is the only reason `react_hook`'s callers below still
/// need `byondapi` at all for gas indices, pending `lib.rs`'s own move to
/// `ffi/src/gas.rs`.
fn gas_idx_from_value(value: &ByondValue) -> Result<gas::GasIDX> {
	let raw = value
		.get_number()
		.map_err(|_| eyre::eyre!("gas IDs are numbers (GAS_ID_*), got {value:?}"))?;
	gas::gas_idx_from_value(raw)
}

thread_local! {
	/// The DM `/datum/gas_reaction` for each reaction id (pending `lib.rs`'s
	/// own move to `ffi/src/gas.rs`, `rust_architecture.md` step 6 decision
	/// 1: reactions stay in DM, `AGENTS.md`, so this table of live
	/// references is inherently `byondapi` and can't live in `reaction.rs`
	/// now that that module is pure).
	static REACTION_VALUES: std::cell::RefCell<std::collections::HashMap<reaction::ReactionIdentifier, ByondValue>> = std::cell::RefCell::default();
}

/// Runs a reaction given a `ReactionIdentifier`, calling back into the live
/// `/datum/gas_reaction` `auxtools_atmos_init`/`auxtools_update_reactions`
/// cached above.
///
/// # Errors
/// If the reaction itself has a runtime.
fn react_by_id(
	id: reaction::ReactionIdentifier,
	src: ByondValue,
	holder: ByondValue,
) -> Result<ByondValue> {
	use eyre::Context;
	REACTION_VALUES.with_borrow(|r| {
		r.get(&id).map_or_else(
			|| Err(eyre::eyre!("Reaction with invalid id")),
			|reaction| {
				reaction
					.call_id(byond_string!("react"), &[src, holder])
					.wrap_err("calling byond side react in react_by_id")
			},
		)
	})
}

/// Reads DM's `SSair.gas_reactions` into the pure registry
/// (`gas::types::install_reactions`), caching each live reaction reference
/// for [`react_by_id`].
fn load_reactions() -> Result<()> {
	use eyre::Context;
	use float_ord::FloatOrd;
	use reaction::{Reaction, ReactionPriority};
	use std::collections::BTreeMap;

	let gas_reactions = ByondValue::new_global_ref()
		.read_var_id(byond_string!("SSair"))
		.wrap_err("load_reactions: couldn't read global SSair")?
		.read_var_id(byond_string!("gas_reactions"))
		.wrap_err("load_reactions: SSair has no gas_reactions var")?;
	let mut cache: BTreeMap<ReactionPriority, Reaction> = BTreeMap::new();
	for (reaction, _) in gas_reactions
		.iter()
		.wrap_err("load_reactions: SSair.gas_reactions is not a list")?
	{
		let priority: ReactionPriority = FloatOrd(
			reaction
				.read_number_id(byond_string!("priority"))
				.map_err(|_| eyre::eyre!("Reaction priority must be a number!"))?,
		);
		let string_id = reaction
			.read_string_id(byond_string!("id"))
			.map_err(|_| eyre::eyre!("Reaction id must be a string!"))?;
		let id = {
			use std::hash::{Hash, Hasher};
			let mut state = rustc_hash::FxHasher::default();
			string_id.as_bytes().hash(&mut state);
			state.finish()
		};
		let Some(min_reqs) = reaction
			.read_var_id(byond_string!("min_requirements"))
			.ok()
			.filter(ByondValue::is_list)
		else {
			return Err(eyre::eyre!(
				"Reaction {string_id} doesn't have a gas requirements list!"
			));
		};
		let mut min_gas_reqs: Vec<(gas::GasIDX, f32)> = Vec::new();
		for i in 0..gas::total_num_gases() {
			let Some(path) = gas::gas_path(i) else { continue };
			if let Ok(req_amount) = min_reqs.read_list_index(path).and_then(|v| v.get_number()) {
				min_gas_reqs.push((i, req_amount));
			}
		}
		let read_req = |key: &str| min_reqs.read_list_index(key).ok().and_then(|v| v.get_number().ok());
		let parsed = Reaction::new(
			id,
			priority,
			read_req("TEMP"),
			read_req("MAX_TEMP"),
			read_req("ENER"),
			read_req("FIRE_REAGENTS"),
			min_gas_reqs,
		);
		if cache.contains_key(&parsed.get_priority()) {
			let priority = parsed.get_priority().0;
			let sender = auxcallback::byond_callback_sender();
			drop(sender.try_send(Box::new(move || Err(eyre::eyre!("Duplicate reaction priority {priority}, this reaction will be ignored!")))));
			continue;
		}
		REACTION_VALUES.with_borrow_mut(|r| r.insert(id, reaction));
		cache.insert(parsed.get_priority(), parsed);
	}
	gas::types::install_reactions(cache);
	Ok(())
}

/// Registers gases, and get reaction infos for auxmos, only call when ssair is initing.
#[auxmacros::bind("/proc/auxtools_atmos_init")]
fn hook_init(gas_data: ByondValue) -> Result<ByondValue> {
	use eyre::Context;
	use gas::types::GasType;

	let data = gas_data.read_var_id(byond_string!("datums"))?;
	let gases = data
		.iter()?
		.map(|(_, gas_datum)| {
			let path = gas_datum.read_string_id(byond_string!("id"))?;
			let idx = gas::gas_id_for_path(&path).ok_or_else(|| eyre::eyre!("{path} has no ID in verdigris gas/ids.rs"))?;
			if let Ok(dm_idx) = gas_datum.read_number_id(byond_string!("idx")) {
				#[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
				if dm_idx as gas::GasIDX != idx {
					return Err(eyre::eyre!("{path}: DM idx {dm_idx} disagrees with GAS_PATHS ID {idx}"));
				}
			}
			let fire_info = if let Ok(temperature) = gas_datum.read_number_id(byond_string!("oxidation_temperature")) {
				gas::types::FireInfo::Oxidation(gas::types::OxidationInfo::new(temperature, gas_datum.read_number_id(byond_string!("oxidation_rate"))?))
			} else if let Ok(temperature) = gas_datum.read_number_id(byond_string!("fire_temperature")) {
				gas::types::FireInfo::Fuel(gas::types::FuelInfo::new(temperature, gas_datum.read_number_id(byond_string!("fire_burn_rate"))?))
			} else {
				gas::types::FireInfo::None
			};
			let fire_products = gas_datum.read_var_id(byond_string!("fire_products")).ok().and_then(|product_info| {
				if product_info.is_list() {
					Some(gas::types::FireProductInfo::Generic(
						product_info
							.iter()
							.ok()?
							.filter_map(|(k, v)| k.get_string().ok().and_then(|s| v.get_number().ok().map(|amt| (gas::types::GasRef::Deferred(s), amt))))
							.collect(),
					))
				} else if product_info.is_num() {
					Some(gas::types::FireProductInfo::Plasma)
				} else {
					None
				}
			});
			Ok(GasType::new(
				idx,
				path.clone().into_boxed_str(),
				gas_datum.read_string_id(byond_string!("name"))?.into_boxed_str(),
				gas_datum.read_number_id(byond_string!("flags")).unwrap_or_default() as u32,
				gas_datum.read_number_id(byond_string!("specific_heat"))?,
				gas_datum.read_number_id(byond_string!("molar_mass")).unwrap_or_default(),
				gas_datum.read_number_id(byond_string!("fusion_power")).unwrap_or_default(),
				gas_datum.read_number_id(byond_string!("moles_visible")).ok(),
				gas_datum.read_number_id(byond_string!("enthalpy")).unwrap_or_default(),
				gas_datum.read_number_id(byond_string!("fire_radiation_released")).unwrap_or_default(),
				fire_info,
				fire_products,
			))
		})
		.collect::<Result<Vec<_>>>()
		.wrap_err("auxtools_atmos_init failed to register gas")?;
	gas::types::install_gases(gases)?;
	load_reactions()?;
	Ok(true.into())
}

/// For updating reaction informations for auxmos, only call this when it is changed.
#[auxmacros::bind("/datum/controller/subsystem/air/proc/auxtools_update_reactions")]
fn update_reactions() -> Result<ByondValue> {
	load_reactions()?;
	Ok(true.into())
}

/// For updating reagent gas fire products, do not use for now.
#[auxmacros::bind("/proc/finalize_gas_refs")]
fn finalize_gas_refs() -> Result<ByondValue> {
	gas::update_gas_refs()?;
	Ok(ByondValue::null())
}


/// Binds a gas mixture datum to a pipe region's gas (the handle from
/// `vg_pipe_upsert`/`vg_pipe_commit`, `verdigris/ffi/src/pipes.rs`). The
/// datum's own slot is freed.
#[auxmacros::bind("/datum/gas_mixture/proc/__bind_handle")]
fn bind_handle(mut src: ByondValue, handle: ByondValue) -> Result<ByondValue> {
	let Some(target) = MixRef::from_f32(handle.get_number()?) else {
		eyre::bail!("invalid gas handle {handle:?}");
	};
	if !matches!(target, MixRef::Pipe(_)) {
		eyre::bail!("only pipe region handles can be bound");
	}
	with_world(|w| {
		if let Ok(MixRef::Main(slot)) = MixRef::of(&src) {
			w.mains.free(slot);
		}
	});
	target.store(&mut src)?;
	Ok(ByondValue::null())
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
	#[allow(clippy::cast_precision_loss)]
	let changes = with_world(world::GasWorld::drain_dirty)
		.into_iter()
		.flat_map(|(id, mask)| {
			[
				ByondValue::from(id as f32),
				ByondValue::from(f32::from(mask)),
			]
		})
		.collect::<Vec<_>>();
	let list = ByondValue::new_list()?;
	list.write_list(&changes)?;
	Ok(list)
}

/// Floats per record returned by `drain_dirty_gas_observations`.
/// @dm-define GAS_DEPENDENCY_OBSERVATION_STRIDE
pub const GAS_OBSERVATION_STRIDE: usize = 15;

/// Drains dirty notifications and captures the control-relevant gas state in
/// one call, so sleeping air alarms evaluate thresholds without crossing the
/// FFI once per value. Flat stride: id, mask, revision, pressure,
/// temperature, volume, o2, co2, plasma, methane, n2o, volatile_fuel,
/// miasma, zauker, total_moles.
#[auxmacros::bind("/proc/drain_dirty_gas_observations")]
fn drain_dirty_gas_observations() -> Result<ByondValue> {
	let values = with_world(world::GasWorld::drain_observations);
	let list = ByondValue::new_list()?;
	list.write_list(&values.into_iter().map(ByondValue::from).collect::<Vec<_>>())?;
	Ok(list)
}

#[auxmacros::bind("/proc/watch_dirty_gas_mixture")]
fn watch_dirty_gas_mixture(id: ByondValue, interest_mask: ByondValue) -> Result<ByondValue> {
	let (id, mask) = (id.get_number()? as u32, interest_mask.get_number()? as u8);
	with_world(|w| w.watch_dirty(id, mask));
	Ok(ByondValue::null())
}

#[auxmacros::bind("/proc/unwatch_dirty_gas_mixture")]
fn unwatch_dirty_gas_mixture(id: ByondValue) -> Result<ByondValue> {
	let id = id.get_number()? as u32;
	with_world(|w| w.unwatch_dirty(id));
	Ok(ByondValue::null())
}

/// `list(main mixtures live, main slots, pipe regions, pipe ports,
/// registered turf cells, gas frames, pending callbacks, heat frames, heat
/// bodies, heat frame us)` for SSair's stat panel.
#[auxmacros::bind("/datum/controller/subsystem/air/proc/auxmos_diagnostics")]
fn auxmos_diagnostics() -> Result<ByondValue> {
	let gas = turf::diagnostics();
	// Heat's own diagnostics moved to vg-ffi (`rust_architecture.md` step 4);
	// pipe region/port counts moved there too (step 5, alongside the pipe
	// network itself): this crate no longer hosts either to report on. Kept
	// as zeros, not removed, so this list's width (and every existing
	// index into it) stays the same for callers that haven't moved to a
	// `vg_pipe_*`/`vg_heat_*` diagnostics bind instead.
	let heat = (0, 0, 0);
	let pipes = (0, 0);
	#[allow(clippy::cast_precision_loss)]
	let values = gas
		.into_iter()
		.chain([
			auxcallback::pending_callbacks(),
			heat.0,
			heat.1,
			heat.2 as usize,
			pipes.0,
			pipes.1,
		])
		.map(|value| ByondValue::from(value as f32))
		.collect::<Vec<_>>();
	let list = ByondValue::new_list()?;
	list.write_list(&values)?;
	Ok(list)
}

/// Gives a new `/datum/gas_mixture` a main-owned slot sized from its
/// `initial_volume`, and writes the handle into it.
#[auxmacros::bind("/datum/gas_mixture/proc/__gasmixture_register")]
fn register_gasmixture_hook(mut src: ByondValue) -> Result<ByondValue> {
	let volume = src.read_number_id(byond_string!("initial_volume"))?;
	let slot = with_world(|w| w.mains.alloc(Mixture::from_vol(volume)))?;
	MixRef::Main(slot).store(&mut src)?;
	Ok(ByondValue::null())
}

/// Frees a mixture's main-owned slot. Turf and pipe gas outlive their datums
/// (the cell and the region own it).
#[auxmacros::bind("/datum/gas_mixture/proc/__gasmixture_unregister")]
fn unregister_gasmixture_hook(src: ByondValue) -> Result<ByondValue> {
	if let Ok(r) = MixRef::of(&src) {
		with_world(|w| {
			if let MixRef::Main(slot) = r {
				w.unwatch_dirty(r.id());
				w.mains.free(slot);
			}
		});
	}
	Ok(ByondValue::null())
}

/// The mixture's gas revision (bumped whenever its gas changes).
#[auxmacros::bind("/datum/gas_mixture/proc/revision")]
fn hook_mix_revision(src: ByondValue) -> Result<ByondValue> {
	let r = MixRef::of(&src)?;
	#[allow(clippy::cast_precision_loss)]
	Ok(with_world(|w| (w.revision(r) & 0x00FF_FFFF) as f32).into())
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
	with_mixes_mut(&src, &giver, |src_mix, giver_mix| {
		src_mix.merge(giver_mix);
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
	with_mixes_mut(&src, &giver, |src_mix, giver_mix| {
		src_mix.copy_from_mutable(giver_mix);
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
	let refs = mixtures
		.get_list_values()?
		.iter()
		.map(|mix| MixRef::of(mix).ok())
		.collect::<Vec<_>>();
	let stride = GAS_READ_HEADER + gas::GAS_COUNT;
	let values = with_world(|w| {
		let mut values = Vec::with_capacity(refs.len() * stride);
		for r in &refs {
			let Some(mix) = r.and_then(|r| w.load(r)) else {
				values.extend(std::iter::repeat_n(0.0, stride));
				continue;
			};
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
	if args.len().is_multiple_of(2) {
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

/// Flat operation list: source handle, sink handle, requested moles. Returns
/// one actual mole count per operation after shared-source clamping.
#[auxmacros::bind("/proc/auxmos_batch_transfer")]
fn batch_transfer_hook(operations: ByondValue) -> Result<ByondValue> {
	// `values()` walks the numbered positions directly (handle 0 is valid).
	let values = operations.values()?.collect::<Vec<_>>();
	let parsed = values
		.chunks_exact(3)
		.map(|operation| {
			let source = MixRef::from_f32(operation[0].get_number().unwrap_or(-1.0));
			let sink = MixRef::from_f32(operation[1].get_number().unwrap_or(-1.0));
			(source, sink, operation[2].get_number().unwrap_or(0.0))
		})
		.collect::<Vec<_>>();
	let results = with_world(|w| {
		parsed
			.into_iter()
			.map(|(source, sink, requested)| {
				let (Some(source), Some(sink)) = (source, sink) else {
					return 0.0;
				};
				if source == sink || requested <= 0.0 {
					return 0.0;
				}
				let (Some(src_before), Some(sink_before)) = (w.load(source), w.load(sink)) else {
					return 0.0;
				};
				let actual = requested.min(src_before.total_moles()).max(0.0);
				if actual > 0.0 {
					let (mut a, mut b) = (src_before.clone(), sink_before.clone());
					b.merge(&a.remove(actual));
					w.store(source, &src_before, &a);
					w.store(sink, &sink_before, &b);
				}
				actual
			})
			.map(ByondValue::from)
			.collect::<Vec<_>>()
	});
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
			(
				MixRef::of(&operation[0]).ok(),
				MixRef::of(&operation[1]).ok(),
				operation[2].get_number().unwrap_or(0.0),
			)
		})
		.collect::<Vec<_>>();
	let results = with_world(|w| {
		parsed
			.into_iter()
			.map(|(pipe_ref, env_ref, share_volume)| {
				let (Some(pipe_ref), Some(env_ref)) = (pipe_ref, env_ref) else {
					return false;
				};
				if pipe_ref == env_ref || share_volume <= 0.0 {
					return false;
				}
				let (Some(pipe_before), Some(env_before)) = (w.load(pipe_ref), w.load(env_ref))
				else {
					return false;
				};
				let (mut pipe, mut environment) = (pipe_before.clone(), env_before.clone());
				let pipe_volume = pipe.volume.max(1.0);
				let environment_volume = environment.volume.max(1.0);
				let sample = pipe.remove_ratio((share_volume / pipe_volume).clamp(0.0, 1.0));
				environment.merge(&sample);
				let reclaimed = environment.remove_ratio(
					(share_volume / (share_volume + environment_volume)).clamp(0.0, 1.0),
				);
				pipe.merge(&reclaimed);
				let pipe_moles = pipe.total_moles();
				let environment_moles = environment.total_moles();
				let pressure_residual =
					(pipe.return_pressure() - environment.return_pressure()).abs() > 0.1;
				let temperature_residual =
					(pipe.get_temperature() - environment.get_temperature()).abs() > 0.1;
				let composition_residual = pipe_moles > GAS_MIN_MOLES
					&& environment_moles > GAS_MIN_MOLES
					&& (0..gas::GAS_COUNT).any(|gas| {
						(pipe.get_moles(gas) / pipe_moles
							- environment.get_moles(gas) / environment_moles)
							.abs() > 0.001
					});
				w.store(pipe_ref, &pipe_before, &pipe);
				w.store(env_ref, &env_before, &environment);
				pressure_residual || temperature_residual || composition_residual
			})
			.map(|residual| ByondValue::from(f32::from(u8::from(residual))))
			.collect::<Vec<_>>()
	});
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
	with_mixes_mut(&src, &total, |src_gas, total_gas| {
		let vol = src_gas.volume;
		src_gas.copy_from_mutable(total_gas);
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

/// Args: (list). Takes every gas in the list and makes them all identical, scaled to their respective volumes. The total heat and amount of substance in all of the combined gases is conserved.
#[auxmacros::bind("/proc/equalize_all_gases_in_list")]
fn equalize_all_hook(gas_list: ByondValue) -> Result<ByondValue> {
	let mut refs = gas_list
		.iter()?
		.filter_map(|(value, _)| MixRef::of(&value).ok())
		.collect::<Vec<_>>();
	refs.sort_unstable_by_key(|r| r.id());
	refs.dedup();
	with_world(|w| {
		let loaded: Vec<(MixRef, Mixture)> =
			refs.iter().filter_map(|&r| Some((r, w.load(r)?))).collect();
		let mut tot = Mixture::new();
		let mut tot_vol: f64 = 0.0;
		for (_, m) in &loaded {
			tot.merge(m);
			tot_vol += f64::from(m.volume);
		}
		if tot_vol <= 0.0 {
			return;
		}
		for (r, before) in loaded {
			let mut after = before.clone();
			after.copy_from_mutable(&tot);
			after.multiply((f64::from(before.volume) / tot_vol) as f32);
			w.store(r, &before, &after);
		}
	});
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

/// A filter device's entropy-limited power budget
/// (`_atmospherics_helpers.dm`'s `filter_gas()`, `power_budget.rs`'s
/// `filter_transfer` -- ported maths, unchanged). `filtering` is a
/// `1 << gas_id` bitset; `requested`/`available_power` are `null` for
/// `filter_gas()`'s own `null` (uncapped); `efficiency` is
/// `ATMOS_FILTER_EFFICIENCY * material_pump_efficiency()/0.8` (or plain
/// `ATMOS_FILTER_EFFICIENCY`), computed by the caller exactly as before --
/// this bind only replaces the rate-limiting arithmetic, never the actual
/// gas movement (a caller-owned pair of `DeviceFlow` rows does that).
/// Returns `list(total_transfer_moles, filterable_moles,
/// unfilterable_moles, power_draw)`, or `null` when nothing should move.
#[auxmacros::bind("/proc/vg_filter_transfer")]
fn filter_transfer(
	source: ByondValue,
	sink_filtered: ByondValue,
	sink_clean: ByondValue,
	filtering: ByondValue,
	requested: ByondValue,
	available_power: ByondValue,
	efficiency: ByondValue,
) -> Result<ByondValue> {
	let (rs, rf, rc) = (MixRef::of(&source)?, MixRef::of(&sink_filtered)?, MixRef::of(&sink_clean)?);
	#[allow(clippy::cast_sign_loss, clippy::cast_possible_truncation)]
	let filtering = filtering.get_number()? as u32;
	let requested = (!requested.is_null()).then(|| requested.get_number()).transpose()?;
	let available_power = (!available_power.is_null()).then(|| available_power.get_number()).transpose()?;
	let efficiency = efficiency.get_number()?;
	let result = with_world(|w| {
		let source_mix = w.load(rs).ok_or_else(|| missing(rs))?;
		let sink_filtered_mix = w.load(rf).ok_or_else(|| missing(rf))?;
		let sink_clean_mix = w.load(rc).ok_or_else(|| missing(rc))?;
		Ok::<_, eyre::Report>(power_budget::filter_transfer(
			&source_mix,
			&sink_filtered_mix,
			&sink_clean_mix,
			filtering,
			requested,
			available_power,
			efficiency,
			constants::MINIMUM_MOLES_TO_FILTER,
		))
	})?;
	let Some(result) = result else { return Ok(ByondValue::null()) };
	let list = ByondValue::new_list()?;
	list.write_list(&[
		ByondValue::from(result.total_transfer_moles),
		ByondValue::from(result.filterable_moles),
		ByondValue::from(result.unfilterable_moles),
		ByondValue::from(result.power_draw),
	])?;
	Ok(list)
}

/// A mixer device's entropy-limited power budget
/// (`_atmospherics_helpers.dm`'s `mix_gas()`, `power_budget.rs`'s
/// `mix_transfer` -- ported maths, unchanged). `sources` is a DM assoc
/// list, `/datum/gas_mixture` -> mix ratio (every ratio must sum to 1, as
/// `mix_gas()` required); `requested`/`available_power`/`efficiency` as
/// [`filter_transfer`]. Returns `list(total_transfer_moles,
/// power_draw, source_1_moles, source_2_moles, ...)` in `sources`' own
/// iteration order, or `null` when nothing should move.
#[auxmacros::bind("/proc/vg_mix_transfer")]
fn mix_transfer(
	sources: ByondValue,
	sink: ByondValue,
	requested: ByondValue,
	available_power: ByondValue,
	efficiency: ByondValue,
) -> Result<ByondValue> {
	let rsink = MixRef::of(&sink)?;
	let requested = (!requested.is_null()).then(|| requested.get_number()).transpose()?;
	let available_power = (!available_power.is_null()).then(|| available_power.get_number()).transpose()?;
	let efficiency = efficiency.get_number()?;
	let refs = sources
		.iter()?
		.map(|(mix, ratio)| Ok((MixRef::of(&mix)?, ratio.get_number()?)))
		.collect::<Result<Vec<(MixRef, f32)>>>()?;
	let result = with_world(|w| {
		let mixtures = refs
			.iter()
			.map(|&(r, _)| w.load(r).ok_or_else(|| missing(r)))
			.collect::<Result<Vec<Mixture>, _>>()?;
		let sink_mix = w.load(rsink).ok_or_else(|| missing(rsink))?;
		let sources: Vec<power_budget::MixSource<'_>> = mixtures
			.iter()
			.zip(&refs)
			.map(|(mixture, &(_, ratio))| power_budget::MixSource { mixture, ratio })
			.collect();
		Ok::<_, eyre::Report>(power_budget::mix_transfer(
			&sources,
			&sink_mix,
			requested,
			available_power,
			efficiency,
			constants::MINIMUM_MOLES_TO_FILTER,
		))
	})?;
	let Some(result) = result else { return Ok(ByondValue::null()) };
	let mut flat = vec![ByondValue::from(result.total_transfer_moles), ByondValue::from(result.power_draw)];
	flat.extend(result.moles.into_iter().map(ByondValue::from));
	let list = ByondValue::new_list()?;
	list.write_list(&flat)?;
	Ok(list)
}

/// The omni filter's N-way generalization of [`filter_transfer`]
/// (`_atmospherics_helpers.dm`'s `filter_gas_multi()`, `power_budget.rs`'s
/// `filter_transfer_multi` -- ported maths, unchanged): `outputs` is a DM
/// assoc list, `/datum/gas_mixture` -> mask (one entry per configured
/// filter port), instead of a single shared `sink_filtered`. `sink_clean`
/// is the omni filter's required `output` port, catching anything no
/// output's mask matches. Returns `list(total_transfer_moles, power_draw,
/// clean_moles, output_1_moles, output_2_moles, ...)` in `outputs`' own
/// iteration order, or `null` when nothing should move.
#[auxmacros::bind("/proc/vg_filter_transfer_multi")]
fn filter_transfer_multi(
	source: ByondValue,
	outputs: ByondValue,
	sink_clean: ByondValue,
	requested: ByondValue,
	available_power: ByondValue,
	efficiency: ByondValue,
) -> Result<ByondValue> {
	let rs = MixRef::of(&source)?;
	let rc = MixRef::of(&sink_clean)?;
	let requested = (!requested.is_null()).then(|| requested.get_number()).transpose()?;
	let available_power = (!available_power.is_null()).then(|| available_power.get_number()).transpose()?;
	let efficiency = efficiency.get_number()?;
	#[allow(clippy::cast_sign_loss, clippy::cast_possible_truncation)]
	let refs = outputs
		.iter()?
		.map(|(mix, mask)| Ok((MixRef::of(&mix)?, mask.get_number()? as u32)))
		.collect::<Result<Vec<(MixRef, u32)>>>()?;
	let result = with_world(|w| {
		let source_mix = w.load(rs).ok_or_else(|| missing(rs))?;
		let sink_clean_mix = w.load(rc).ok_or_else(|| missing(rc))?;
		let sinks = refs
			.iter()
			.map(|&(r, _)| w.load(r).ok_or_else(|| missing(r)))
			.collect::<Result<Vec<Mixture>, _>>()?;
		let outputs: Vec<power_budget::FilterOutput<'_>> = sinks
			.iter()
			.zip(&refs)
			.map(|(sink, &(_, mask))| power_budget::FilterOutput { mask, sink })
			.collect();
		Ok::<_, eyre::Report>(power_budget::filter_transfer_multi(
			&source_mix,
			&outputs,
			&sink_clean_mix,
			requested,
			available_power,
			efficiency,
			constants::MINIMUM_MOLES_TO_FILTER,
		))
	})?;
	let Some(result) = result else { return Ok(ByondValue::null()) };
	let mut flat = vec![
		ByondValue::from(result.total_transfer_moles),
		ByondValue::from(result.power_draw),
		ByondValue::from(result.clean_moles),
	];
	flat.extend(result.moles.into_iter().map(ByondValue::from));
	let list = ByondValue::new_list()?;
	list.write_list(&flat)?;
	Ok(list)
}

#[cfg(test)]
mod tests;
