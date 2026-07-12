/*
Gas data (moles per gas, temperature) lives in the Rust auxmos arena. Each
/datum/gas_mixture is a handle: the DM datum holds a slot index written by
__gasmixture_register() into _extools_pointer_gasmixture, and all gas reads/
writes go through the call_ext procs declared in auxmos_bindings.dm.
*/

GLOBAL_LIST_INIT(meta_gas_info, meta_gas_list()) //see ATMOSPHERICS/gas_types.dm
GLOBAL_LIST_INIT(gaslist_cache, init_gaslist_cache())

/proc/init_gaslist_cache()
	var/list/gases = list()
	for(var/id in GLOB.meta_gas_info)
		var/list/cached_gas = new(3)

		gases[id] = cached_gas

		cached_gas[MOLES] = 0
		cached_gas[ARCHIVE] = 0
		cached_gas[GAS_META] = GLOB.meta_gas_info[id]
	return gases

/datum/gas_mixture
	/// Arena slot index written by __gasmixture_register(). Read by Rust to
	/// locate the mixture's data block in the arena. Do not assign directly.
	var/_extools_pointer_gasmixture
	/// Volume captured at New() time so Rust can size the mixture on register.
	var/initial_volume = CELL_VOLUME
	/// Volume in liters.
	var/volume = CELL_VOLUME
	/// The last tick this gas mixture shared on. A counter that turfs use to manage activity.
	var/last_share = 0
	/// Tells us what reactions have happened in our gasmix. Assoc list of reaction - moles reacted pair.
	var/list/reaction_results
	/// Whether to call garbage_collect() on the sharer during shares, used for immutable mixtures.
	var/gc_share = FALSE
	/// When this gas mixture was last touched by pipeline processing.
	var/pipeline_cycle = -1

/datum/gas_mixture/New(volume)
	if(!isnull(volume))
		src.volume = volume
	if(src.volume <= 0)
		stack_trace("Created a gas mixture with zero volume!")
	initial_volume = src.volume
	__gasmixture_register()
	reaction_results = new

/datum/gas_mixture/Del()
	__gasmixture_unregister()
	..()

//
// Handle-model helpers: thin DM wrappers the codebase uses instead of direct
// gas-list access. All real work is delegated to the Rust bindings.
//

/// assert_gas — no-op under the handle model; auxmos auto-creates entries.
/datum/gas_mixture/proc/assert_gas(gas_id)
	return

/// assert_gases — no-op under the handle model.
/datum/gas_mixture/proc/assert_gases(...)
	return

/// add_gas — no-op under the handle model; auxmos auto-creates entries.
/datum/gas_mixture/proc/add_gas(gas_id)
	return

/// add_gases — no-op under the handle model.
/datum/gas_mixture/proc/add_gases(...)
	return

/// garbage_collect — no-op under the handle model; Rust manages zeroed entries.
/datum/gas_mixture/proc/garbage_collect(list/tocheck)
	return

/// Checks to see if gas amount exists in mixture.
/datum/gas_mixture/proc/has_gas(gas_id, amount=0)
	return amount < get_moles(gas_id)

/// Gets the gas visuals for everything in this mixture.
/datum/gas_mixture/proc/return_visuals(turf/z_context)
	var/list/gas_ids = get_gases()
	if(!gas_ids || !length(gas_ids))
		return null
	var/list/output = list()
	var/offset = GET_TURF_PLANE_OFFSET(z_context) + 1
	for(var/gas_id in gas_ids)
		if(GLOB.nonoverlaying_gases[gas_id])
			continue
		var/gas_meta = GLOB.meta_gas_info[gas_id]
		if(!gas_meta)
			continue
		var/moles = get_moles(gas_id)
		if(moles <= gas_meta[META_GAS_MOLES_VISIBLE])
			continue
		var/gas_overlay = gas_meta[META_GAS_OVERLAY][offset]
		output += gas_overlay[min(TOTAL_VISIBLE_STATES, CEILING(moles / MOLES_GAS_VISIBLE_STEP, 1))]
	return output

/// Archive — snapshots current temperature for use in this tick's sharing pass.
/// Under the handle model, temperature archiving is managed internally by Rust.
/// This proc is retained for call-site compatibility but is a no-op here.
/datum/gas_mixture/proc/archive()
	return TRUE

/// Set the gas species within the gas mix to a set amount; creates entry if absent.
/datum/gas_mixture/proc/set_gas(gas_specie, amount)
	set_moles(gas_specie, amount)

/// Add a specific amount of moles to a gas species (negative to remove).
/datum/gas_mixture/proc/adjust_gas(gas, amount)
	if(istext(gas))
		// XGM string-id path — delegate to xgm_compat's adjust_gas override.
		// This proc should not be reached for string gas IDs since xgm_compat.dm
		// overrides /datum/gas_mixture/adjust_gas with the string-aware version.
		return
	adjust_moles(gas, amount)

/// Add moles to multiple gas species; gases_moles is an assoc list of type → delta.
/datum/gas_mixture/proc/adjust_multiple_gases(list/gases_moles)
	for(var/gas_specie in gases_moles)
		adjust_moles(gas_specie, gases_moles[gas_specie])

/// Convert moles of gas species A to gas species B.
/datum/gas_mixture/proc/convert_gas(datum/gas/reactant, datum/gas/product, conversion_amount)
	adjust_moles(reactant, -conversion_amount)
	adjust_moles(product, conversion_amount)

/// Proportionally removes amount of gas from the mixture.
/// Returns: a new gas_mixture with the removed gases.
/datum/gas_mixture/proc/remove(amount)
	var/sum = total_moles()
	amount = min(amount, sum)
	if(amount <= 0)
		return null
	var/datum/gas_mixture/removed = new type(volume)
	__remove(removed, amount)
	SEND_SIGNAL(src, COMSIG_GASMIX_REMOVED)
	return removed

/// Proportionally removes a ratio of gas from the mixture.
/// Returns: a new gas_mixture with the removed gases.
/datum/gas_mixture/proc/remove_ratio(ratio)
	if(ratio <= 0)
		var/datum/gas_mixture/empty = new type(volume)
		return empty
	ratio = min(ratio, 1)
	var/datum/gas_mixture/removed = new type(volume)
	__remove_ratio(removed, ratio)
	SEND_SIGNAL(src, COMSIG_GASMIX_REMOVED)
	return removed

/// Removes a specific amount of a single gas from the mixture.
/// Returns: a new gas_mixture containing only the removed gas.
/datum/gas_mixture/proc/remove_specific(gas_id, amount)
	var/have = get_moles(gas_id)
	amount = min(amount, have)
	if(amount <= 0)
		return null
	var/datum/gas_mixture/removed = new type
	removed.set_temperature(return_temperature())
	adjust_moles(gas_id, -amount)
	removed.set_moles(gas_id, amount)
	return removed

/// Removes a ratio of a specific gas from the mixture.
/// Returns: a new gas_mixture containing only the removed gas.
/datum/gas_mixture/proc/remove_specific_ratio(gas_id, ratio)
	if(ratio <= 0)
		return null
	ratio = min(ratio, 1)
	var/have = get_moles(gas_id)
	var/amount = have * ratio
	var/datum/gas_mixture/removed = new type
	removed.set_temperature(return_temperature())
	adjust_moles(gas_id, -amount)
	removed.set_moles(gas_id, amount)
	return removed

/// Distributes the contents of two mixes equally between themselves.
/// Returns: bool indicating whether gases moved.
/datum/gas_mixture/proc/equalize(datum/gas_mixture/other)
	. = FALSE
	var/t1 = return_temperature()
	var/t2 = other.return_temperature()
	if(abs(t1 - t2) > MINIMUM_TEMPERATURE_DELTA_TO_SUSPEND)
		. = TRUE
		var/self_heat_cap = heat_capacity()
		var/other_heat_cap = other.heat_capacity()
		var/new_temp = (t1 * self_heat_cap + t2 * other_heat_cap) / (self_heat_cap + other_heat_cap)
		set_temperature(new_temp)
		other.set_temperature(new_temp)

	var/min_p_delta = 0.1
	var/total_volume = volume + other.volume
	// Collect all gas ids from both mixes.
	var/list/gas_list_self = get_gases()
	var/list/gas_list_other = other.get_gases()
	var/list/all_gases = list()
	if(gas_list_self)
		for(var/g in gas_list_self)
			all_gases[g] = TRUE
	if(gas_list_other)
		for(var/g in gas_list_other)
			all_gases[g] = TRUE
	var/cur_temp = return_temperature()
	for(var/gas_id in all_gases)
		var/my_n = get_moles(gas_id)
		var/their_n = other.get_moles(gas_id)
		if(abs(my_n / volume - their_n / other.volume) > min_p_delta / (R_IDEAL_GAS_EQUATION * cur_temp))
			. = TRUE
			var/total_n = my_n + their_n
			set_moles(gas_id, total_n * (volume / total_volume))
			other.set_moles(gas_id, total_n * (other.volume / total_volume))

/// Creates a new, identical gas mixture.
/// Returns: duplicate gas mixture.
/datum/gas_mixture/proc/copy()
	var/datum/gas_mixture/result = new type(volume)
	result.copy_from(src)
	return result

/// Copies variables from sample, moles multiplied by partial.
/// Returns: TRUE.
/datum/gas_mixture/proc/copy_from_ratio(datum/gas_mixture/sample, partial = 1)
	clear()
	set_temperature(sample.return_temperature())
	var/list/sample_gases = sample.get_gases()
	if(sample_gases)
		for(var/gas_id in sample_gases)
			set_moles(gas_id, sample.get_moles(gas_id) * partial)
	return TRUE

/// Performs air sharing calculations between two gas_mixtures.
/// share() is commutative — A.share(B) must equal B.share(A) in net exchange.
/// Returns: amount of pressure exchanged (+ if sharer received gas).
/datum/gas_mixture/proc/share(datum/gas_mixture/sharer, our_coeff, sharer_coeff)
	// Snapshot temperatures for this sharing step.
	var/our_archived_temp = return_temperature()
	var/sharer_archived_temp = sharer.return_temperature()
	var/temperature_delta = our_archived_temp - sharer_archived_temp
	var/abs_temperature_delta = abs(temperature_delta)

	var/old_self_heat_capacity = 0
	var/old_sharer_heat_capacity = 0
	if(abs_temperature_delta > MINIMUM_TEMPERATURE_DELTA_TO_CONSIDER)
		old_self_heat_capacity = heat_capacity()
		old_sharer_heat_capacity = sharer.heat_capacity()

	var/heat_capacity_self_to_sharer = 0
	var/heat_capacity_sharer_to_self = 0
	var/moved_moles = 0
	var/abs_moved_moles = 0

	// Collect all gas ids present in either mixture.
	var/list/our_gases = get_gases()
	var/list/sharer_gases = sharer.get_gases()
	var/list/all_gases = list()
	if(our_gases)
		for(var/g in our_gases)
			all_gases[g] = TRUE
	if(sharer_gases)
		for(var/g in sharer_gases)
			all_gases[g] = TRUE

	for(var/gas_id in all_gases)
		var/our_moles = get_moles(gas_id)
		var/their_moles = sharer.get_moles(gas_id)
		var/delta = QUANTIZE(our_moles - their_moles)
		if(!delta)
			continue

		if(delta > 0)
			delta = delta * our_coeff
		else
			delta = delta * sharer_coeff

		if(abs_temperature_delta > MINIMUM_TEMPERATURE_DELTA_TO_CONSIDER)
			var/gas_heat_capacity = delta * GLOB.meta_gas_info[gas_id][META_GAS_SPECIFIC_HEAT]
			if(delta > 0)
				heat_capacity_self_to_sharer += gas_heat_capacity
			else
				heat_capacity_sharer_to_self -= gas_heat_capacity

		adjust_moles(gas_id, -delta)
		sharer.adjust_moles(gas_id, delta)
		moved_moles += delta
		abs_moved_moles += abs(delta)

	last_share = abs_moved_moles

	// Thermal energy transfer.
	if(abs_temperature_delta > MINIMUM_TEMPERATURE_DELTA_TO_CONSIDER)
		var/new_self_heat_capacity = old_self_heat_capacity + heat_capacity_sharer_to_self - heat_capacity_self_to_sharer
		var/new_sharer_heat_capacity = old_sharer_heat_capacity + heat_capacity_self_to_sharer - heat_capacity_sharer_to_self

		if(new_self_heat_capacity > MINIMUM_HEAT_CAPACITY)
			set_temperature((old_self_heat_capacity * our_archived_temp - heat_capacity_self_to_sharer * our_archived_temp + heat_capacity_sharer_to_self * sharer_archived_temp) / new_self_heat_capacity)

		if(new_sharer_heat_capacity > MINIMUM_HEAT_CAPACITY)
			sharer.set_temperature((old_sharer_heat_capacity * sharer_archived_temp - heat_capacity_sharer_to_self * sharer_archived_temp + heat_capacity_self_to_sharer * our_archived_temp) / new_sharer_heat_capacity)
			if(abs(old_sharer_heat_capacity) > MINIMUM_HEAT_CAPACITY)
				if(abs(new_sharer_heat_capacity / old_sharer_heat_capacity - 1) < 0.1)
					temperature_share(sharer, OPEN_HEAT_TRANSFER_COEFFICIENT)

	if(temperature_delta > MINIMUM_TEMPERATURE_TO_MOVE || abs(moved_moles) > MINIMUM_MOLES_DELTA_TO_MOVE)
		var/our_total = total_moles()
		var/their_total = sharer.total_moles()
		return (our_archived_temp * (our_total + moved_moles) - sharer_archived_temp * (their_total - moved_moles)) * R_IDEAL_GAS_EQUATION / volume

/// Returns the partial pressure of a gas amount in BREATH_VOLUME.
/datum/gas_mixture/proc/get_breath_partial_pressure(gas_mole_count)
	return (gas_mole_count * R_IDEAL_GAS_EQUATION * return_temperature()) / BREATH_VOLUME

/// Counts the pressure if MOLAR_ACCURACY moles are transferred to output_air.
/datum/gas_mixture/proc/gas_pressure_minimum_transfer(datum/gas_mixture/output_air)
	var/our_moles = total_moles()
	var/resulting_energy = output_air.thermal_energy() + (MOLAR_ACCURACY / our_moles * thermal_energy())
	var/resulting_capacity = output_air.heat_capacity() + (MOLAR_ACCURACY / our_moles * heat_capacity())
	return (output_air.total_moles() + MOLAR_ACCURACY) * R_IDEAL_GAS_EQUATION * (resulting_energy / resulting_capacity) / output_air.volume

/// Returns the amount of gas to pump to reach target_pressure in output_air.
/datum/gas_mixture/proc/gas_pressure_calculate(datum/gas_mixture/output_air, target_pressure, ignore_temperature = FALSE)
	var/our_moles = total_moles()
	var/output_moles = output_air.total_moles()
	var/output_pressure = output_air.return_pressure()
	var/our_temp = return_temperature()

	if(our_moles <= 0 || our_temp <= 0)
		return FALSE

	var/pressure_delta = 0
	if(output_air.return_temperature() <= 0 || output_moles <= 0)
		ignore_temperature = TRUE
		pressure_delta = target_pressure
	else
		pressure_delta = target_pressure - output_pressure

	if(pressure_delta < 0.01 || gas_pressure_minimum_transfer(output_air) > target_pressure)
		return FALSE

	if(ignore_temperature)
		return (pressure_delta * output_air.volume) / (our_temp * R_IDEAL_GAS_EQUATION)

	var/pv = target_pressure * output_air.volume
	var/pvr = pv / R_IDEAL_GAS_EQUATION
	var/lower_limit = max((pvr / max(our_temp, output_air.return_temperature())) - output_moles, 0)
	var/upper_limit = (pvr / min(our_temp, output_air.return_temperature())) - output_moles

	lower_limit = max(lower_limit - ATMOS_PRESSURE_ERROR_TOLERANCE, 0)
	upper_limit += ATMOS_PRESSURE_ERROR_TOLERANCE

	var/w2 = thermal_energy()
	var/n2 = our_moles
	var/c2 = heat_capacity()

	var/w1 = output_air.thermal_energy()
	var/n1 = output_moles
	var/c1 = output_air.heat_capacity()

	var/a_value = w2 / n2
	var/b_value = ((n1 * w2) / n2) + w1 - (pvr * c2 / n2)
	var/c_value = (-1 * pvr * c1) + n1 * w1

	. = gas_pressure_quadratic(a_value, b_value, c_value, lower_limit, upper_limit)
	if(.)
		return
	. = gas_pressure_approximate(a_value, b_value, c_value, lower_limit, upper_limit)
	if(.)
		return
	return (pressure_delta * output_air.volume) / (our_temp * R_IDEAL_GAS_EQUATION)

/// Solves the quadratic equation for the pressure calculation.
/datum/gas_mixture/proc/gas_pressure_quadratic(a, b, c, lower_limit, upper_limit)
	var/solution
	if(IS_FINITE(a) && IS_FINITE(b) && IS_FINITE(c))
		solution = max(SolveQuadratic(a, b, c))
		if(solution > lower_limit && solution < upper_limit)
			return solution
	stack_trace("Failed to solve pressure quadratic equation. A: [a]. B: [b]. C:[c]. Current value = [solution]. Expected lower limit: [lower_limit]. Expected upper limit: [upper_limit].")
	return FALSE

/// Newton-Raphson approximation for the pressure quadratic.
/datum/gas_mixture/proc/gas_pressure_approximate(a, b, c, lower_limit, upper_limit)
	var/solution
	if(IS_FINITE(a) && IS_FINITE(b) && IS_FINITE(c))
		solution = (-b / (2 * a)) + 200
		for(var/iteration in 1 to ATMOS_PRESSURE_APPROXIMATION_ITERATIONS)
			var/diff = (a * solution**2 + b * solution + c) / (2 * a * solution + b)
			solution -= diff
			if(abs(diff) < MOLAR_ACCURACY && (solution > lower_limit) && (solution < upper_limit))
				return solution
	stack_trace("Newton's Approximation for pressure failed after [ATMOS_PRESSURE_APPROXIMATION_ITERATIONS] iterations. A: [a]. B: [b]. C:[c]. Current value: [solution]. Expected lower limit: [lower_limit]. Expected upper limit: [upper_limit].")
	return FALSE

/// Pumps gas from src to output_air. Amount depends on target_pressure.
/datum/gas_mixture/proc/pump_gas_to(datum/gas_mixture/output_air, target_pressure, specific_gas = null, datum/gas_mixture/output_pipenet_air = null)
	var/datum/gas_mixture/input_air = specific_gas ? remove_specific_ratio(specific_gas, 1) : src
	var/temperature_delta = abs(input_air.return_temperature() - output_air.return_temperature())
	var/datum/gas_mixture/removed

	var/transfer_moles_output = input_air.gas_pressure_calculate(output_air, target_pressure, temperature_delta <= 5)
	var/transfer_moles_pipenet = output_pipenet_air?.volume ? input_air.gas_pressure_calculate(output_pipenet_air, target_pressure, temperature_delta <= 5) : 0
	var/transfer_moles = max(transfer_moles_output, transfer_moles_pipenet)

	if(specific_gas)
		removed = input_air.remove_specific(specific_gas, transfer_moles)
		merge(input_air)
	else
		removed = input_air.remove(transfer_moles)

	if(!removed)
		return FALSE

	output_air.merge(removed)
	return removed

/// Releases gas from src to output_air, only if output pressure is below target.
/datum/gas_mixture/proc/release_gas_to(datum/gas_mixture/output_air, target_pressure, rate = 1, datum/gas_mixture/output_pipenet_air = null)
	var/output_starting_pressure = output_air.return_pressure()
	var/input_starting_pressure = return_pressure()

	if(output_starting_pressure >= min(target_pressure, input_starting_pressure - 10))
		return FALSE
	target_pressure = output_starting_pressure + min(target_pressure - output_starting_pressure, (input_starting_pressure - output_starting_pressure) / 2)
	var/temperature_delta = abs(return_temperature() - output_air.return_temperature())

	var/transfer_moles_output = gas_pressure_calculate(output_air, target_pressure, temperature_delta <= 5)
	var/transfer_moles_pipenet = output_pipenet_air?.volume ? gas_pressure_calculate(output_pipenet_air, target_pressure, temperature_delta <= 5) : 0
	var/transfer_moles = max(transfer_moles_output, transfer_moles_pipenet)

	var/datum/gas_mixture/removed = remove(transfer_moles * rate)
	if(!removed)
		return FALSE

	output_air.merge(removed)
	return TRUE

/// Convert a gas mixture to a string (eg. "o2=22;n2=82;TEMP=180").
/datum/gas_mixture/proc/to_string()
	var/rounded_temp = round(return_temperature(), 0.01)
	var/list/atmos_contents = list()
	var/temperature_str = "TEMP=[num2text(rounded_temp)]"

	var/list/gas_ids = get_gases()
	if(!gas_ids || total_moles() < 0.01)
		return temperature_str

	for(var/gas_id in gas_ids)
		var/gas_moles = round(get_moles(gas_id), 0.01)
		if(gas_moles >= 0.01)
			var/gas_meta = GLOB.meta_gas_info[gas_id]
			var/id_str = gas_meta ? gas_meta[META_GAS_ID] : "[gas_id]"
			atmos_contents += "[id_str]=[num2text(gas_moles)]"

	atmos_contents += temperature_str
	return atmos_contents.Join(";")
