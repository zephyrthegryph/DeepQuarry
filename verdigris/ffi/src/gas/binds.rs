//! The legacy `/datum/gas_mixture` binds: DM's gas API over [`mix`]'s
//! handles (every bind loads, changes and stores through `with_mix*`).

use byondapi::prelude::*;
use eyre::Result;
use vg_gas::gas::constants::{GAS_MIN_MOLES, MINIMUM_MOLES_DELTA_TO_MOVE};
use vg_gas::gas::{self, Mixture, constants, gas_idx_from_string};
use vg_gas::power_budget;
use vg_heat::components::gas_kind;
use vg_heat::GasCoupling;

use super::mix::{self, MixRef, with_mix, with_mix_mut, with_mixes_mut, with_mixes2};
use super::parser;

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
    if let Ok(MixRef::Main(slot)) = MixRef::of(&src) {
        mix::free(slot);
    }
    target.store(&mut src)?;
    Ok(ByondValue::null())
}

/// Args: (ms). Runs callbacks until time limit is reached. If time limit is omitted, runs all callbacks.
#[auxmacros::bind("/proc/process_atmos_callbacks")]
fn atmos_callback_handle(remaining: ByondValue) -> Result<ByondValue> {
    auxcallback::callback_processing_hook(remaining)
}

/// Drains dependency notifications and captures the control-relevant gas
/// state in one pass, so sleeping devices evaluate thresholds without
/// crossing the FFI once per value. Flat stride (`GAS_OBSERVATION_STRIDE`):
/// watch handle, mixture id, mask, revision, pressure, temperature, volume,
/// o2, co2, plasma, methane, n2o, volatile_fuel, miasma, zauker, total_moles.
/// Taken by [`crate::frame`], which reports each as a CHANGED record; there is
/// no DM bind.
pub(crate) fn take_observations() -> Vec<f32> {
    mix::drain_observations()
}

/// DM watch `handle` (a `/datum/native_watch/gas`) watches mixture `id`
/// for `interest_mask` (`GAS_DEPENDENCY_*`) changes.
#[auxmacros::bind("/proc/watch_dirty_gas_mixture")]
fn watch_dirty_gas_mixture(
    id: ByondValue,
    handle: ByondValue,
    interest_mask: ByondValue,
) -> Result<ByondValue> {
    let id = id.get_number()? as u32;
    let handle = crate::world::whole(&handle, "watch handle")?;
    let mask = interest_mask.get_number()? as u8;
    mix::watch_dirty(id, handle, mask);
    Ok(ByondValue::null())
}

/// Drops DM watch `handle`'s dependency watch.
#[auxmacros::bind("/proc/unwatch_dirty_gas_mixture")]
fn unwatch_dirty_gas_mixture(handle: ByondValue) -> Result<ByondValue> {
    mix::unwatch_dirty(crate::world::whole(&handle, "watch handle")?);
    Ok(ByondValue::null())
}

/// Gives a new `/datum/gas_mixture` a main-owned slot sized from its
/// `initial_volume`, and writes the handle into it.
#[auxmacros::bind("/datum/gas_mixture/proc/__gasmixture_register")]
fn register_gasmixture_hook(mut src: ByondValue) -> Result<ByondValue> {
    let volume = src.read_number_id(byond_string!("initial_volume"))?;
    let slot = mix::alloc(Mixture::from_vol(volume))?;
    MixRef::Main(slot).store(&mut src)?;
    Ok(ByondValue::null())
}

/// Frees every main-owned slot whose datum is not in `mixtures` (a list of
/// every live `/datum/gas_mixture`); `/world/New()` calls it once. Returns
/// the number of slots freed. See [`mix::retain`].
#[auxmacros::bind("/proc/gas_retain_mixtures")]
fn gas_retain_mixtures(mixtures: ByondValue) -> Result<ByondValue> {
    let keep: std::collections::HashSet<u32> = mixtures
        .iter()?
        .filter_map(|(m, _)| match MixRef::of(&m) {
            Ok(MixRef::Main(slot)) => Some(slot),
            _ => None,
        })
        .collect();
    #[allow(clippy::cast_precision_loss)]
    Ok((mix::retain(&keep) as f32).into())
}

/// Frees a mixture's main-owned slot. Turf and pipe gas outlive their datums
/// (the cell and the region own it).
#[auxmacros::bind("/datum/gas_mixture/proc/__gasmixture_unregister")]
fn unregister_gasmixture_hook(src: ByondValue) -> Result<ByondValue> {
    if let Ok(MixRef::Main(slot)) = MixRef::of(&src) {
        mix::free(slot);
    }
    Ok(ByondValue::null())
}

/// The mixture's gas revision (bumped whenever its gas changes).
#[auxmacros::bind("/datum/gas_mixture/proc/revision")]
fn hook_mix_revision(src: ByondValue) -> Result<ByondValue> {
    let r = MixRef::of(&src)?;
    #[allow(clippy::cast_precision_loss)]
    Ok(((mix::revision(r) & 0x00FF_FFFF) as f32).into())
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
    let values = {
        let mut values = Vec::with_capacity(refs.len() * stride);
        for r in &refs {
            let Some(mix) = r.and_then(mix::load) else {
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
    };
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
    let pertinent_gases = gases_with_flag(flag);
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
    let pertinent_gases = gases_with_flag(flag);
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
    with_mixes2(&src, &other, |gas_one, gas_two| {
        Ok((gas_one.temperature_compare(gas_two)
            || gas_one.compare_with(gas_two, MINIMUM_MOLES_DELTA_TO_MOVE))
        .into())
    })
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

/// Args: (src, sink, target_kpa, max_moles, gases_mask). Moves gas from `src` into
/// `sink` until the sink reaches `target_kpa` (an exact ideal-gas solve, with
/// mixing temperature), never more than `max_moles` (`null` or <= 0: no cap)
/// and only the gases in `gases_mask` (a `1 << gas_id` bitset, 0: all).
/// Returns the moles moved. Replaces the DM `gas_pressure_calculate` solvers.
#[auxmacros::bind("/proc/vg_transfer_to_pressure")]
fn transfer_to_pressure(
    src: ByondValue,
    sink: ByondValue,
    target_kpa: ByondValue,
    max_moles: ByondValue,
    gases_mask: ByondValue,
) -> Result<ByondValue> {
    let target = target_kpa.get_number()?;
    let cap = if max_moles.is_null() {
        f32::INFINITY
    } else {
        let m = max_moles.get_number()?;
        if m > 0.0 { m } else { f32::INFINITY }
    };
    #[allow(clippy::cast_sign_loss, clippy::cast_possible_truncation)]
    let mask = gases_mask.get_number().unwrap_or(0.0) as u32;
    with_mixes_mut(&src, &sink, |from, to| {
        let needed = from.moles_to_pressure(to, target, mask, 0.0).min(cap);
        Ok(ByondValue::from(
            from.transfer_masked_into(to, mask, needed),
        ))
    })
}

/// Args: (src, sink, target_kpa, gases_mask, sink_volume_mod). Read-only: the moles
/// of `gases_mask` that would bring `sink` (its volume enlarged by
/// `sink_volume_mod` litres, for a networked sink) to `target_kpa`.
#[auxmacros::bind("/proc/vg_moles_to_pressure")]
fn moles_to_pressure(
    src: ByondValue,
    sink: ByondValue,
    target_kpa: ByondValue,
    gases_mask: ByondValue,
    sink_volume_mod: ByondValue,
) -> Result<ByondValue> {
    let target = target_kpa.get_number()?;
    #[allow(clippy::cast_sign_loss, clippy::cast_possible_truncation)]
    let mask = gases_mask.get_number().unwrap_or(0.0) as u32;
    let vol_mod = sink_volume_mod.get_number().unwrap_or(0.0);
    let (a, b) = (MixRef::of(&src)?, MixRef::of(&sink)?);
    let (from, to) = (mix::load_or_err(a)?, mix::load_or_err(b)?);
    Ok(ByondValue::from(
        from.moles_to_pressure(&to, target, mask, vol_mod),
    ))
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
    let results = {
        parsed
            .into_iter()
            .map(|(source, sink, requested)| {
                let (Some(source), Some(sink)) = (source, sink) else {
                    return 0.0;
                };
                if source == sink || requested <= 0.0 {
                    return 0.0;
                }
                let (Some(src_before), Some(sink_before)) = (mix::load(source), mix::load(sink))
                else {
                    return 0.0;
                };
                let actual = requested.min(src_before.total_moles()).max(0.0);
                if actual > 0.0 {
                    let (mut a, mut b) = (src_before.clone(), sink_before.clone());
                    b.merge(&a.remove(actual));
                    mix::store(source, &src_before, &a);
                    mix::store(sink, &sink_before, &b);
                }
                actual
            })
            .map(ByondValue::from)
            .collect::<Vec<_>>()
    };
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
    let results = {
        parsed
            .into_iter()
            .map(|(pipe_ref, env_ref, share_volume)| {
                let (Some(pipe_ref), Some(env_ref)) = (pipe_ref, env_ref) else {
                    return false;
                };
                if pipe_ref == env_ref || share_volume <= 0.0 {
                    return false;
                }
                let (Some(pipe_before), Some(env_before)) =
                    (mix::load(pipe_ref), mix::load(env_ref))
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
                            .abs()
                            > 0.001
                    });
                mix::store(pipe_ref, &pipe_before, &pipe);
                mix::store(env_ref, &env_before, &environment);
                pressure_residual || temperature_residual || composition_residual
            })
            .map(|residual| ByondValue::from(f32::from(u8::from(residual))))
            .collect::<Vec<_>>()
    };
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
    {
        let loaded: Vec<(MixRef, Mixture)> = refs
            .iter()
            .filter_map(|&r| Some((r, mix::load(r)?)))
            .collect();
        let mut tot = Mixture::new();
        let mut tot_vol: f64 = 0.0;
        for (_, m) in &loaded {
            tot.merge(m);
            tot_vol += f64::from(m.volume);
        }
        if tot_vol <= 0.0 {
            return Ok(ByondValue::null());
        }
        for (r, before) in loaded {
            let mut after = before.clone();
            after.copy_from_mutable(&tot);
            after.multiply((f64::from(before.volume) / tot_vol) as f32);
            mix::store(r, &before, &after);
        }
    }

    Ok(ByondValue::null())
}

/// Returns: the amount of gas mixtures that are attached to a byond gas mixture.
#[auxmacros::bind("/datum/controller/subsystem/air/proc/get_amt_gas_mixes")]
fn hook_amt_gas_mixes() -> Result<ByondValue> {
    Ok((mix::counts().0 as f32).into())
}

/// Returns: the total amount of gas mixtures in the arena, including "free" ones.
#[auxmacros::bind("/datum/controller/subsystem/air/proc/get_max_gas_mixes")]
fn hook_max_gas_mixes() -> Result<ByondValue> {
    Ok((mix::counts().1 as f32).into())
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
    let (rs, rf, rc) = (
        MixRef::of(&source)?,
        MixRef::of(&sink_filtered)?,
        MixRef::of(&sink_clean)?,
    );
    #[allow(clippy::cast_sign_loss, clippy::cast_possible_truncation)]
    let filtering = filtering.get_number()? as u32;
    let requested = (!requested.is_null())
        .then(|| requested.get_number())
        .transpose()?;
    let available_power = (!available_power.is_null())
        .then(|| available_power.get_number())
        .transpose()?;
    let efficiency = efficiency.get_number()?;
    let result = (|| {
        let source_mix = mix::load_or_err(rs)?;
        let sink_filtered_mix = mix::load_or_err(rf)?;
        let sink_clean_mix = mix::load_or_err(rc)?;
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
    })()?;
    let Some(result) = result else {
        return Ok(ByondValue::null());
    };
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
    let requested = (!requested.is_null())
        .then(|| requested.get_number())
        .transpose()?;
    let available_power = (!available_power.is_null())
        .then(|| available_power.get_number())
        .transpose()?;
    let efficiency = efficiency.get_number()?;
    let refs = sources
        .iter()?
        .map(|(mix, ratio)| Ok((MixRef::of(&mix)?, ratio.get_number()?)))
        .collect::<Result<Vec<(MixRef, f32)>>>()?;
    let result = (|| {
        let mixtures = refs
            .iter()
            .map(|&(r, _)| mix::load_or_err(r))
            .collect::<Result<Vec<Mixture>, _>>()?;
        let sink_mix = mix::load_or_err(rsink)?;
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
    })()?;
    let Some(result) = result else {
        return Ok(ByondValue::null());
    };
    let mut flat = vec![
        ByondValue::from(result.total_transfer_moles),
        ByondValue::from(result.power_draw),
    ];
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
    let requested = (!requested.is_null())
        .then(|| requested.get_number())
        .transpose()?;
    let available_power = (!available_power.is_null())
        .then(|| available_power.get_number())
        .transpose()?;
    let efficiency = efficiency.get_number()?;
    #[allow(clippy::cast_sign_loss, clippy::cast_possible_truncation)]
    let refs = outputs
        .iter()?
        .map(|(mix, mask)| Ok((MixRef::of(&mix)?, mask.get_number()? as u32)))
        .collect::<Result<Vec<(MixRef, u32)>>>()?;
    let result = (|| {
        let source_mix = mix::load_or_err(rs)?;
        let sink_clean_mix = mix::load_or_err(rc)?;
        let sinks = refs
            .iter()
            .map(|&(r, _)| mix::load_or_err(r))
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
    })()?;
    let Some(result) = result else {
        return Ok(ByondValue::null());
    };
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

/// An optional number argument (`null` is `None`).
fn opt_number(v: &ByondValue) -> Result<Option<f32>> {
    (!v.is_null())
        .then(|| v.get_number())
        .transpose()
        .map_err(Into::into)
}

/// [`pump`] mode: an active pump that moves the gas.
/// @dm-define VG_PUMP_ACTIVE
#[allow(dead_code)] // a DM define only
pub const PUMP_ACTIVE: i32 = 0;
/// [`pump`] mode: a passive (pressure-equalising) pump that moves the gas.
/// @dm-define VG_PUMP_PASSIVE
pub const PUMP_PASSIVE: i32 = 1;
/// [`pump`] mode: an active pump that only plans; the caller queues the move.
/// @dm-define VG_PUMP_PLAN
pub const PUMP_PLAN: i32 = 2;

/// One gas pump (`pump_gas()` and `pump_gas_passive()`'s whole maths).
/// Args: (source, sink, requested, available_power, efficiency, mode).
/// `requested`/`available_power` are `null` for uncapped; `efficiency` is
/// `ATMOS_PUMP_EFFICIENCY * material_pump_efficiency() / 0.8` (the caller's
/// material hook, applied before the call). `mode`: 0 an active pump that
/// moves the gas, 1 a passive (pressure-equalising) one that moves it, 2 an
/// active pump that only plans (the caller queues the move).
/// Returns `list(moles, power_draw, flow_volume)`, or `null` when nothing
/// should move (`pump_gas()`'s `-1`).
#[auxmacros::bind("/proc/vg_pump")]
fn pump(
    source: ByondValue,
    sink: ByondValue,
    requested: ByondValue,
    available_power: ByondValue,
    efficiency: ByondValue,
    mode: ByondValue,
) -> Result<ByondValue> {
    let requested = opt_number(&requested)?;
    let available_power = opt_number(&available_power)?;
    let efficiency = efficiency.get_number()?;
    #[allow(clippy::cast_possible_truncation)]
    let mode = mode.get_number()? as i32;
    let passive = mode == PUMP_PASSIVE;
    let plan_only = mode == PUMP_PLAN;
    let plan = with_mixes_mut(&source, &sink, |from, to| {
        let plan = power_budget::pump_plan(
            from,
            to,
            requested,
            available_power,
            efficiency,
            constants::MINIMUM_MOLES_TO_PUMP,
            passive,
        );
        if let (Some(p), false) = (plan, plan_only) {
            to.merge(&from.remove(p.moles));
        }
        Ok(plan)
    })?;
    let Some(plan) = plan else {
        return Ok(ByondValue::null());
    };
    let list = ByondValue::new_list()?;
    list.write_list(&[
        ByondValue::from(plan.moles),
        ByondValue::from(plan.power_draw),
        ByondValue::from(plan.flow_volume),
    ])?;
    Ok(list)
}

/// One scrubber pass (`scrub_gas()`'s whole maths and movement): moves the
/// gases of `mask` (`1 << gas_id`) from `source` to `sink`, each in
/// proportion to its share, within `requested` moles and `available_power`.
/// Args: (source, sink, mask, requested, available_power, efficiency).
/// Returns `list(moles, power_draw, flow_volume)`, or `null` when the budget
/// allows nothing (the trace of a nearly-clean mix still moves).
#[auxmacros::bind("/proc/vg_scrub")]
fn scrub(
    source: ByondValue,
    sink: ByondValue,
    mask: ByondValue,
    requested: ByondValue,
    available_power: ByondValue,
    efficiency: ByondValue,
) -> Result<ByondValue> {
    let requested = opt_number(&requested)?;
    let available_power = opt_number(&available_power)?;
    let efficiency = efficiency.get_number()?;
    #[allow(clippy::cast_sign_loss, clippy::cast_possible_truncation)]
    let mask = mask.get_number()? as u32;
    let plan = with_mixes_mut(&source, &sink, |from, to| {
        let (plan, trace) = power_budget::scrub_plan(
            from,
            to,
            mask,
            requested,
            available_power,
            efficiency,
            constants::MINIMUM_MOLES_TO_FILTER,
        );
        for (g, n) in trace {
            from.transfer_masked_into(to, 1 << g, n);
        }
        if let Some(p) = &plan {
            for &(g, n) in &p.gases {
                from.transfer_masked_into(to, 1 << g, n);
            }
        }
        Ok(plan)
    })?;
    let Some(plan) = plan else {
        return Ok(ByondValue::null());
    };
    let list = ByondValue::new_list()?;
    list.write_list(&[
        ByondValue::from(plan.moles),
        ByondValue::from(plan.power_draw),
        ByondValue::from(plan.flow_volume),
    ])?;
    Ok(list)
}

/// `calculate_specific_power()`: the power (W/mol) to move one mole of
/// `source`'s mixture into `sink`.
#[auxmacros::bind("/proc/vg_specific_power")]
fn specific_power(source: ByondValue, sink: ByondValue) -> Result<ByondValue> {
    let (a, b) = (MixRef::of(&source)?, MixRef::of(&sink)?);
    let (from, to) = (mix::load_or_err(a)?, mix::load_or_err(b)?);
    Ok(ByondValue::from(power_budget::pump_specific_power(
        &from, &to,
    )))
}

/// A pipe mixture's contact with another thermal body, as the heat domain's [`GasCoupling`] makes it: the
/// conductance that exchanges `conductivity` of the temperature difference in one second between the `share_volume`
/// of `air` in contact and the other body, run through the coupling's own exchange kernel. Returns the joules that
/// left `air` (negative: it gained); `air` is changed by them.
fn pipe_contact(
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
    let coupling = GasCoupling {
        body: 0,
        kind: gas_kind::MIXTURE,
        target: 0,
        conductance: GasCoupling::conductance_for_fraction(
            f64::from(conductivity),
            partial,
            other_capacity,
            1.0,
        ),
        slot: 1,
    };
    let heat = coupling.exchange(
        (air.get_temperature(), partial),
        (other_temperature, other_capacity),
        1.0,
    );
    air.adjust_heat(-heat);
    heat
}

/// Heat exchange between the share of a pipe mixture in contact and another
/// body: `pipeline.temperature_interact()`'s one exchange, the heat domain's
/// `GasCoupling` kernel ([`pipe_contact`]). Args: (air,
/// other_air, share_volume, conductivity, other_temperature, other_capacity).
/// With an `other_air` mixture its temperature and capacity are read (the
/// last two are ignored) and it gains what `air` loses; otherwise the last
/// two describe the other body (a wall's solid). Returns the joules that
/// left `air` (the caller credits a wall's heat cell).
#[auxmacros::bind("/proc/vg_thermal_exchange")]
fn thermal_exchange(
    air: ByondValue,
    other_air: ByondValue,
    share_volume: ByondValue,
    conductivity: ByondValue,
    other_temperature: ByondValue,
    other_capacity: ByondValue,
) -> Result<ByondValue> {
    let share = share_volume.get_number()?;
    let k = conductivity.get_number()?;
    if other_air.is_null() {
        let (t, c) = (
            other_temperature.get_number()?,
            other_capacity.get_number()?,
        );
        let heat = with_mix_mut(&air, |a| {
            Ok(pipe_contact(a, share, k, t, c))
        })?;
        return Ok(ByondValue::from(heat));
    }
    let heat = with_mixes_mut(&air, &other_air, |a, b| {
        let (t, c) = (b.get_temperature(), b.heat_capacity());
        let heat = pipe_contact(a, share, k, t, c);
        if heat != 0.0 && c > 0.0 {
            b.adjust_heat(heat);
        }
        Ok(heat)
    })?;
    Ok(ByondValue::from(heat))
}

/// The gases whose registry `flags` include `flag`.
fn gases_with_flag(flag: u32) -> Vec<usize> {
    vg_gas::gate::with(|g| {
        g.gases
            .iter()
            .enumerate()
            .filter(|(_, gas)| gas.flags & flag != 0)
            .map(|(i, _)| i)
            .collect()
    })
}

#[cfg(test)]
mod pipe_contact_tests {
    use super::*;

    fn air(moles: f32, kelvin: f32) -> Mixture {
        let mut m = Mixture::from_vol(2500.0);
        m.set_moles(0, moles);
        m.set_temperature(kelvin);
        m
    }

    #[test]
    fn a_pipe_contact_moves_its_share_of_the_series_difference_and_books_the_heat() {
        let mut a = air(100.0, 400.0);
        let before = a.thermal_energy();
        let other = air(100.0, 300.0);
        let (ta, tb) = (a.get_temperature(), other.get_temperature());
        let (ca, cb) = (a.heat_capacity(), other.heat_capacity());
        let heat = pipe_contact(&mut a, 2500.0, 0.5, tb, cb);
        let series = ca * cb / (ca + cb);
        assert!((heat - 0.5 * (ta - tb) * series).abs() < 1.0, "half the difference: {heat}");
        assert!((a.thermal_energy() - (before - heat)).abs() < 1.0);
    }

    #[test]
    fn a_contact_with_nothing_to_exchange_with_moves_nothing() {
        let mut a = air(100.0, 400.0);
        assert_eq!(pipe_contact(&mut a, 2500.0, 0.5, 300.0, 0.0), 0.0);
        assert_eq!(a.get_temperature(), 400.0);
    }
}
