/*
 * gas_mixture.dm — arena-backed (auxmos) implementation.
 *
 * Gas data no longer lives in a DM assoc list. Each /datum/gas_mixture is a
 * HANDLE into the Rust auxmos arena (index stored in _extools_pointer_gasmixture).
 * All moles/temperature/volume math runs in Rust; the DM procs below are thin
 * routes over the auxmos FFI binds (call_ext(VERDIGRIS, "byond:<hook>_ffi")(...)),
 * or DM logic layered on top of the arena-backed getters.
 *
 * `temperature` and `volume` remain as DM mirror vars for legacy direct READERS.
 * READS of .temperature/.volume are left as-is (SSair keeps them fresh). WRITES
 * go through set_temperature()/set_volume(). Procs here that mutate temperature
 * refresh the DM mirror after calling the bind.
 *
 * Gas identity: auxmos binds take gas args as BYOND STRINGS. Callers pass a
 * /datum/gas TYPE PATH, so every bind route stringifies with "[gas_type]".
 * Passing a raw type path to a bind panic-crashes (get_strid().unwrap()).
 *
 * The DM turf-sharing engine (share/archive/temperature_share DM math) is DELETED
 * — auxmos' Rust turf processing replaces it.
 */

GLOBAL_LIST_INIT(meta_gas_info, meta_gas_list()) //see ATMOSPHERICS/gas_types.dm
// Constant per-gas template table. The mixture 'gases' assoc list is gone (moles
// live in the Rust arena), but this cache is still a shared constant table read by
// GAS_TYPE_COUNT / the GAS_2_LIST helpers, so it is kept.
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
	/// The temperature of the gas mix in kelvin. MIRROR of the arena value, kept
	/// fresh for legacy direct readers. Authoritative copy lives in Rust.
	var/temperature = TCMB
	/// Volume in liters. MIRROR of the arena value (authoritative copy in Rust).
	var/volume = CELL_VOLUME
	/// The last tick this gas mixture shared on. A counter that turfs use to manage activity
	var/last_share = 0
	/// Tells us what reactions have happened in our gasmix. Assoc list of reaction - moles reacted pair.
	var/list/reaction_results
	/// Whether to call garbage_collect() on the sharer during shares, used for immutable mixtures
	var/gc_share = FALSE
	/// When this gas mixture was last touched by pipeline processing
	/// I am sorry
	var/pipeline_cycle = -1
	/// auxmos arena handle: index into the Rust gas-mixture arena, written by
	/// register_gasmixture_hook_ffi (verdigris GasArena::register_mix). Null until
	/// registered. See doc/atmos_migration.md.
	var/_extools_pointer_gasmixture
	/// Volume the mixture was created with; read by register_mix to size the
	/// Rust-side mixture. Kept in sync with `volume` at New().
	var/initial_volume

/datum/gas_mixture/New(volume)
	if(!isnull(volume))
		src.volume = volume
	if(src.volume <= 0)
		stack_trace("Created a gas mixture with zero volume!")
	initial_volume = src.volume
	reaction_results = new
	// Register the mixture in the Rust arena. Reads initial_volume, writes
	// _extools_pointer_gasmixture.
	call_ext(VERDIGRIS, "byond:register_gasmixture_hook_ffi")(src)

/datum/gas_mixture/Destroy()
	// Free the arena slot for reuse.
	call_ext(VERDIGRIS, "byond:unregister_gasmixture_hook_ffi")(src)
	return ..()

//gas presence procs — the arena auto-manages gas presence, so the old
//assert/add/garbage_collect family are no-ops kept for caller compatibility.

///assert_gas(gas_id) - NO-OP. The arena auto-creates gases on first write.
/datum/gas_mixture/proc/assert_gas(gas_id)
	return

///assert_gases(args) - NO-OP. The arena auto-manages presence.
/datum/gas_mixture/proc/assert_gases(...)
	return

///add_gas(gas_id) - NO-OP. The arena auto-creates gases on first write.
/datum/gas_mixture/proc/add_gas(gas_id)
	return

///add_gases(args) - NO-OP. The arena auto-manages presence.
/datum/gas_mixture/proc/add_gases(...)
	return

///garbage_collect() - NO-OP. The arena drops empty gases automatically.
/datum/gas_mixture/proc/garbage_collect(list/tocheck)
	return

//PV = nRT

///joules per kelvin
/datum/gas_mixture/proc/heat_capacity(data = MOLES)
	return call_ext(VERDIGRIS, "byond:heat_cap_hook_ffi")(src)

/// Same as above except vacuums return HEAT_CAPACITY_VACUUM
/datum/gas_mixture/turf/heat_capacity(data = MOLES)
	. = call_ext(VERDIGRIS, "byond:heat_cap_hook_ffi")(src)
	if(!.)
		. += HEAT_CAPACITY_VACUUM //we want vacuums in turfs to have the same heat capacity as space

/// Returns the heat capacity of a single gas in the mixture, in J/K.
/datum/gas_mixture/proc/partial_heat_capacity(gas_id)
	return call_ext(VERDIGRIS, "byond:partial_heat_capacity_ffi")(src, "[gas_id]")

/// Calculate moles
/datum/gas_mixture/proc/total_moles()
	return call_ext(VERDIGRIS, "byond:total_moles_hook_ffi")(src)

/// Returns the moles of a single gas in the mixture.
/datum/gas_mixture/proc/get_moles(gas_id)
	return call_ext(VERDIGRIS, "byond:get_moles_hook_ffi")(src, "[gas_id]")

/// Sets the moles of a single gas in the mixture.
/datum/gas_mixture/proc/set_moles(gas_id, amount)
	return call_ext(VERDIGRIS, "byond:set_moles_hook_ffi")(src, "[gas_id]", amount)

/// Adjusts the moles of a single gas by the given (signed) amount.
/datum/gas_mixture/proc/adjust_moles(gas_id, amount)
	return call_ext(VERDIGRIS, "byond:adjust_moles_hook_ffi")(src, "[gas_id]", amount)

/// Returns the list of gas ids present in the mixture (assoc id -> moles).
/// Returns the /datum/gas TYPE PATHS present in the mixture. The Rust bind
/// returns the registered STRING ids (which we register as type-path text, e.g.
/// "/datum/gas/plasma"), so convert each back to a path so callers get the same
/// type-path contract the old DM gases[] keys had (meta_gas_info/get_moles all
/// key by type path).
/datum/gas_mixture/proc/get_gases()
	var/list/ids = call_ext(VERDIGRIS, "byond:get_gases_hook_ffi")(src)
	. = list()
	if(!islist(ids))
		return
	// Build an ASSOC list gas-type-path -> moles. Iterating it (for(g in ...))
	// still yields the type-path keys, so the many iterate-only callers are
	// unchanged; callers that read the value (cached[g]) now get the mole count
	// instead of null. The Rust bind returns registered STRING ids (type-path
	// text, e.g. "/datum/gas/plasma"); convert each back to a path for the key
	// (meta_gas_info / get_moles all key by type path) and read its moles by the
	// same string id we got back.
	for(var/id in ids)
		var/gas_path = text2path(id)
		if(gas_path)
			.[gas_path] = call_ext(VERDIGRIS, "byond:get_moles_hook_ffi")(src, id)

/// Checks to see if gas amount exists in mixture.
/datum/gas_mixture/proc/has_gas(gas_id, amount=0)
	return amount < (call_ext(VERDIGRIS, "byond:get_moles_hook_ffi")(src, "[gas_id]") || 0)

/// Calculate pressure in kilopascals
/datum/gas_mixture/proc/return_pressure()
	return call_ext(VERDIGRIS, "byond:return_pressure_hook_ffi")(src)

/// Calculate temperature in kelvins
/datum/gas_mixture/proc/return_temperature()
	return call_ext(VERDIGRIS, "byond:return_temperature_hook_ffi")(src)

/// Calculate volume in liters
/datum/gas_mixture/proc/return_volume()
	return max(0, call_ext(VERDIGRIS, "byond:return_volume_hook_ffi")(src))

/// Gets the gas visuals for everything in this mixture
/datum/gas_mixture/proc/return_visuals(turf/z_context)
	var/list/output
	var/offset = GET_TURF_PLANE_OFFSET(z_context) + 1
	var/list/cached_gases = get_gases()
	for(var/id in cached_gases)
		if(GLOB.nonoverlaying_gases[id])
			continue
		var/list/gas_meta = GLOB.meta_gas_info[id]
		if(!gas_meta)
			continue
		var/moles = cached_gases[id]
		if(moles <= gas_meta[META_GAS_MOLES_VISIBLE])
			continue
		var/list/gas_overlay = gas_meta[META_GAS_OVERLAY][offset]
		LAZYADD(output, gas_overlay[min(TOTAL_VISIBLE_STATES, CEILING(moles / MOLES_GAS_VISIBLE_STEP, 1))])
	return output

/// Calculate thermal energy in joules
/datum/gas_mixture/proc/thermal_energy()
	return call_ext(VERDIGRIS, "byond:thermal_energy_hook_ffi")(src)

///Merges all air from giver into self. Does NOT modify giver. Returns: TRUE if we are mutable.
/datum/gas_mixture/proc/merge(datum/gas_mixture/giver)
	if(!giver)
		return FALSE
	. = call_ext(VERDIGRIS, "byond:merge_hook_ffi")(src, giver)
	src.temperature = call_ext(VERDIGRIS, "byond:return_temperature_hook_ffi")(src)
	SEND_SIGNAL(src, COMSIG_GASMIX_MERGED)

// Set the gas specie within the gas mix to a set amount, if there is none it will be created at the target temp
/datum/gas_mixture/proc/set_gas(gas_specie, amount)
	return call_ext(VERDIGRIS, "byond:set_moles_hook_ffi")(src, "[gas_specie]", amount)

/datum/gas_mixture/proc/set_temperature(target_temp)
	. = call_ext(VERDIGRIS, "byond:set_temperature_hook_ffi")(src, target_temp)
	// Read back — the bind clamps to TCMB, so mirror the authoritative value.
	src.temperature = call_ext(VERDIGRIS, "byond:return_temperature_hook_ffi")(src)

/datum/gas_mixture/proc/set_volume(vol)
	. = call_ext(VERDIGRIS, "byond:set_volume_hook_ffi")(src, vol)
	src.volume = vol

/// Add a specific amount of moles to specified gas or add a new gas to the mix
/// amount is added so make it negative to remove
/datum/gas_mixture/proc/adjust_gas(gas, amount)
	return call_ext(VERDIGRIS, "byond:adjust_moles_hook_ffi")(src, "[gas]", QUANTIZE(amount))

/// Add a specific amount of moles to all the gasses present or add a new gas to the mix
///gases_moles is an associative list of gas species to their amount to be added
/datum/gas_mixture/proc/adjust_multiple_gases(list/gases_moles)
	for(var/gas_specie in gases_moles)
		call_ext(VERDIGRIS, "byond:adjust_moles_hook_ffi")(src, "[gas_specie]", gases_moles[gas_specie])

/// Modify the gas list as to convert moles of gas species A to gas species B
/// reactant and product are the gas species to convert and conversion_amount is the amount to be converted
/datum/gas_mixture/proc/convert_gas(datum/gas/reactant, datum/gas/product, conversion_amount)
	var/amount = QUANTIZE(conversion_amount)
	call_ext(VERDIGRIS, "byond:adjust_moles_hook_ffi")(src, "[reactant]", -amount)
	call_ext(VERDIGRIS, "byond:adjust_moles_hook_ffi")(src, "[product]", amount)

///Proportionally removes amount of gas from the gas_mixture.
///Returns: gas_mixture with the gases removed
/datum/gas_mixture/proc/remove(amount)
	var/sum = call_ext(VERDIGRIS, "byond:total_moles_hook_ffi")(src)
	amount = min(amount, sum) //Can not take more air than tile has!
	if(amount <= 0)
		return null
	var/datum/gas_mixture/removed = new type(volume)
	call_ext(VERDIGRIS, "byond:remove_hook_ffi")(src, removed, amount)
	removed.temperature = call_ext(VERDIGRIS, "byond:return_temperature_hook_ffi")(removed)
	SEND_SIGNAL(src, COMSIG_GASMIX_REMOVED)
	return removed

///Proportionally removes ratio of gas from the gas_mixture.
///Returns: gas_mixture with the gases removed
/datum/gas_mixture/proc/remove_ratio(ratio)
	var/datum/gas_mixture/removed = new type(volume)
	if(ratio <= 0)
		return removed
	ratio = min(ratio, 1)
	call_ext(VERDIGRIS, "byond:remove_ratio_hook_ffi")(src, removed, ratio)
	removed.temperature = call_ext(VERDIGRIS, "byond:return_temperature_hook_ffi")(removed)
	SEND_SIGNAL(src, COMSIG_GASMIX_REMOVED)
	return removed

///Removes an amount of a specific gas from the gas_mixture.
///Returns: gas_mixture with the gas removed
/datum/gas_mixture/proc/remove_specific(gas_id, amount)
	amount = min(amount, call_ext(VERDIGRIS, "byond:get_moles_hook_ffi")(src, "[gas_id]"))
	if(amount <= 0)
		return null
	var/datum/gas_mixture/removed = new type
	removed.temperature = call_ext(VERDIGRIS, "byond:return_temperature_hook_ffi")(src)
	call_ext(VERDIGRIS, "byond:set_temperature_hook_ffi")(removed, removed.temperature)
	call_ext(VERDIGRIS, "byond:set_moles_hook_ffi")(removed, "[gas_id]", amount)
	call_ext(VERDIGRIS, "byond:adjust_moles_hook_ffi")(src, "[gas_id]", -amount)
	return removed

/datum/gas_mixture/proc/remove_specific_ratio(gas_id, ratio)
	if(ratio <= 0)
		return null
	ratio = min(ratio, 1)
	var/datum/gas_mixture/removed = new type
	removed.temperature = call_ext(VERDIGRIS, "byond:return_temperature_hook_ffi")(src)
	call_ext(VERDIGRIS, "byond:set_temperature_hook_ffi")(removed, removed.temperature)
	var/amount = QUANTIZE(call_ext(VERDIGRIS, "byond:get_moles_hook_ffi")(src, "[gas_id]") * ratio)
	call_ext(VERDIGRIS, "byond:set_moles_hook_ffi")(removed, "[gas_id]", amount)
	call_ext(VERDIGRIS, "byond:adjust_moles_hook_ffi")(src, "[gas_id]", -amount)
	return removed

///Distributes the contents of two mixes equally between themselves
//Returns: bool indicating whether gases moved between the two mixes
/datum/gas_mixture/proc/equalize(datum/gas_mixture/other)
	. = call_ext(VERDIGRIS, "byond:equalize_with_hook_ffi")(src, other)
	// equalize_with mutates temperature on both sides; refresh mirrors.
	src.temperature = call_ext(VERDIGRIS, "byond:return_temperature_hook_ffi")(src)
	other.temperature = call_ext(VERDIGRIS, "byond:return_temperature_hook_ffi")(other)

///Creates new, identical gas mixture
///Returns: duplicate gas mixture
/datum/gas_mixture/proc/copy()
	var/datum/gas_mixture/copy = new type
	call_ext(VERDIGRIS, "byond:copy_from_hook_ffi")(copy, src)
	copy.temperature = call_ext(VERDIGRIS, "byond:return_temperature_hook_ffi")(copy)
	return copy

///Copies variables from sample
///Returns: TRUE if we are mutable, FALSE otherwise
/datum/gas_mixture/proc/copy_from(datum/gas_mixture/sample)
	. = call_ext(VERDIGRIS, "byond:copy_from_hook_ffi")(src, sample)
	src.temperature = call_ext(VERDIGRIS, "byond:return_temperature_hook_ffi")(src)
	return TRUE

///Copies variables from sample, moles multiplicated by partial
///Returns: TRUE if we are mutable, FALSE otherwise
/datum/gas_mixture/proc/copy_from_ratio(datum/gas_mixture/sample, partial = 1)
	call_ext(VERDIGRIS, "byond:copy_from_hook_ffi")(src, sample)
	if(partial != 1)
		call_ext(VERDIGRIS, "byond:multiply_hook_ffi")(src, partial)
	src.temperature = call_ext(VERDIGRIS, "byond:return_temperature_hook_ffi")(src)
	return TRUE

///Compares sample to self to see if within acceptable ranges that group processing may be enabled
///Returns: TRUE if the mixtures differ enough to warrant processing, FALSE otherwise
/datum/gas_mixture/proc/compare(datum/gas_mixture/sample)
	return call_ext(VERDIGRIS, "byond:compare_hook_ffi")(src, sample)

///Performs various reactions such as combustion and fabrication
/// Runs DM gas reactions against this mixture. Reactions stay in DM (user
/// decision); this dispatcher checks each /datum/gas_reaction's requirements via
/// arena getters and calls its react() (whose body was ported onto arena
/// accessors). auxmos' own reaction engine is NOT used (SSair.gas_reactions is
/// emptied during auxtools_atmos_init so hook_init doesn't parse it).
/datum/gas_mixture/proc/react(datum/holder)
	. = NO_REACTION
	var/list/reactions = SSair.gas_reactions
	if(!length(reactions))
		return
	var/temp = return_temperature()
	// Hypernoblium suppresses all reactions (parity with the old react()).
	if(get_moles(/datum/gas/hypernoblium) >= REACTION_OPPRESSION_THRESHOLD && temp > REACTION_OPPRESSION_MIN_TEMP)
		return STOP_REACTIONS
	for(var/datum/gas_reaction/reaction as anything in reactions)
		var/list/reqs = reaction.requirements
		if(!reqs)
			continue
		if((reqs["MIN_TEMP"] && temp < reqs["MIN_TEMP"]) || (reqs["MAX_TEMP"] && temp > reqs["MAX_TEMP"]))
			continue
		var/satisfied = TRUE
		for(var/id in reqs)
			if(id == "MIN_TEMP" || id == "MAX_TEMP")
				continue
			if(get_moles(id) < reqs[id])
				satisfied = FALSE
				break
		if(!satisfied)
			continue
		. |= reaction.react(src, holder)
		if(. & STOP_REACTIONS)
			return

/**
 * Returns the partial pressure of the gas in the breath based on BREATH_VOLUME
 * eg:
 * Plas_PP = get_breath_partial_pressure(gas_mixture.get_moles(/datum/gas/plasma))
 * O2_PP = get_breath_partial_pressure(gas_mixture.get_moles(/datum/gas/oxygen))
 * get_breath_partial_pressure(gas_mole_count) --> PV = nRT, P = nRT/V
 *
 * 10/20*5 = 2.5
 * 10 = 2.5/5*20
 */
/datum/gas_mixture/proc/get_breath_partial_pressure(gas_mole_count)
	return (gas_mole_count * R_IDEAL_GAS_EQUATION * temperature) / BREATH_VOLUME

/**
 * Counts how much pressure will there be if we impart MOLAR_ACCURACY amounts of our gas to the output gasmix.
 * We do all of this without actually transferring it so don't worry about it changing the gasmix.
 * Returns: Resulting pressure (number).
 * Args:
 * - output_air (gasmix).
 */
/datum/gas_mixture/proc/gas_pressure_minimum_transfer(datum/gas_mixture/output_air)
	// Cache the full-list passes so we don't walk the gaslist multiple times.
	var/our_moles = total_moles()
	var/resulting_energy = output_air.thermal_energy() + (MOLAR_ACCURACY / our_moles * thermal_energy())
	var/resulting_capacity = output_air.heat_capacity() + (MOLAR_ACCURACY / our_moles * heat_capacity())
	return (output_air.total_moles() + MOLAR_ACCURACY) * R_IDEAL_GAS_EQUATION * (resulting_energy / resulting_capacity) / output_air.volume


/** Returns the amount of gas to be pumped to a specific container.
 * Args:
 * - output_air. The gas mix we want to pump to.
 * - target_pressure. The target pressure we want.
 * - ignore_temperature. Returns a cheaper form of gas calculation, useful if the temperature difference between the two gasmixes is low or nonexistent.
 */
/datum/gas_mixture/proc/gas_pressure_calculate(datum/gas_mixture/output_air, target_pressure, ignore_temperature = FALSE)
	// So we don't need to iterate the gaslist multiple times.
	var/our_moles = total_moles()
	var/output_moles = output_air.total_moles()
	var/output_pressure = output_air.return_pressure()

	if(our_moles <= 0 || temperature <= 0)
		return FALSE

	var/pressure_delta = 0
	if(output_air.temperature <= 0 || output_moles <= 0)
		ignore_temperature = TRUE
		pressure_delta = target_pressure
	else
		pressure_delta = target_pressure - output_pressure

	if(pressure_delta < 0.01 || gas_pressure_minimum_transfer(output_air) > target_pressure)
		return FALSE

	if(ignore_temperature)
		return (pressure_delta*output_air.volume)/(temperature * R_IDEAL_GAS_EQUATION)

	// Lower and upper bound for the moles we must transfer to reach the pressure. The answer is bound to be here somewhere.
	var/pv = target_pressure * output_air.volume
	/// The PV/R part in the equation we will use later. Counted early because pv/(r*t) might not be equal to pv/r/t, messing our lower and upper limit.
	var/pvr = pv / R_IDEAL_GAS_EQUATION
	// These works by assuming our gas has extremely high heat capacity
	// and the resultant gasmix will hit either the highest or lowest temperature possible.

	/// This is the true lower limit, but numbers still can get lower than this due to floats.
	var/lower_limit = max((pvr / max(temperature, output_air.temperature)) - output_moles, 0)
	var/upper_limit = (pvr / min(temperature, output_air.temperature)) - output_moles // In theory this should never go below zero, the pressure_delta check above should account for this.

	lower_limit = max(lower_limit - ATMOS_PRESSURE_ERROR_TOLERANCE, 0)
	upper_limit += ATMOS_PRESSURE_ERROR_TOLERANCE

	/*
	 * We have PV=nRT as a nice formula, we can rearrange it into nT = PV/R
	 * But now both n and T can change, since any incoming moles also change our temperature.
	 * So we need to unify both our n and T, somehow.
	 *
	 * We can rewrite T as (our old thermal energy + incoming thermal energy) divided by (our old heat capacity + incoming heat capacity)
	 * T = (W1 + n/N2 * W2) / (C1 + n/N2 * C2). C being heat capacity, W being work, N being total moles.
	 *
	 * In total we now have our equation be: (N1 + n) * (W1 + n/N2 * W2) / (C1 + n/N2 * C2) = PV/R
	 * Now you can rearrange this and find out that it's a quadratic equation and pretty much solvable with the formula. Will be a bit messy though.
	 *
	 * W2/N2n^2 +
	 * (N1*W2/N2)n + W1n - ((PV/R)*C2/N2)n +
	 * (-(PV/R)*C1) + N1W1 = 0
	 *
	 * We will represent each of these terms with A, B, and C. A for the n^2 part, B for the n^1 part, and C for the n^0 part.
	 * We then put this into the famous (-b +/- sqrt(b^2-4ac)) / 2a formula.
	 *
	 * Oh, and one more thing. By "our" we mean the gasmix in the argument. We are the incoming one here. We are number 2, target is number 1.
	 * If all this counting fucks up, we revert first to Newton's approximation, then the old simple formula.
	 */

	// Our thermal energy and moles
	var/w2 = thermal_energy()
	var/n2 = our_moles
	var/c2 = heat_capacity()

	// Target thermal energy and moles
	var/w1 = output_air.thermal_energy()
	var/n1 = output_moles
	var/c1 = output_air.heat_capacity()

	/// x^2 in the quadratic
	var/a_value = w2/n2
	/// x^1 in the quadratic
	var/b_value = ((n1*w2)/n2) + w1 - (pvr*c2/n2)
	/// x^0 in the quadratic
	var/c_value = (-1*pvr*c1) + n1 * w1

	. = gas_pressure_quadratic(a_value, b_value, c_value, lower_limit, upper_limit)
	if(.)
		return
	. = gas_pressure_approximate(a_value, b_value, c_value, lower_limit, upper_limit)
	if(.)
		return
	// Inaccurate and will probably explode but whatever.
	return (pressure_delta*output_air.volume)/(temperature * R_IDEAL_GAS_EQUATION)

/// Actually tries to solve the quadratic equation.
/// Do mind that the numbers can get very big and might hit BYOND's single point float limit.
/datum/gas_mixture/proc/gas_pressure_quadratic(a, b, c, lower_limit, upper_limit)
	var/solution
	if(IS_FINITE(a) && IS_FINITE(b) && IS_FINITE(c))
		solution = max(SolveQuadratic(a, b, c))
		if(solution > lower_limit && solution < upper_limit) //SolveQuadratic can return empty lists so be careful here
			return solution
	stack_trace("Failed to solve pressure quadratic equation. A: [a]. B: [b]. C:[c]. Current value = [solution]. Expected lower limit: [lower_limit]. Expected upper limit: [upper_limit].")
	return FALSE

/// Approximation of the quadratic equation using Newton-Raphson's Method.
/// We use the slope of an approximate value to get closer to the root of a given equation.
/datum/gas_mixture/proc/gas_pressure_approximate(a, b, c, lower_limit, upper_limit)
	var/solution
	if(IS_FINITE(a) && IS_FINITE(b) && IS_FINITE(c))
		// We start at the extrema of the equation, added by a number.
		// This way we will hopefully always converge on the positive root, while starting at a reasonable number.
		solution = (-b / (2 * a)) + 200
		for (var/iteration in 1 to ATMOS_PRESSURE_APPROXIMATION_ITERATIONS)
			var/diff = (a*solution**2 + b*solution + c) / (2*a*solution + b) // f(sol) / f'(sol)
			solution -= diff // xn+1 = xn - f(sol) / f'(sol)
			if(abs(diff) < MOLAR_ACCURACY && (solution > lower_limit) && (solution < upper_limit))
				return solution
	stack_trace("Newton's Approximation for pressure failed after [ATMOS_PRESSURE_APPROXIMATION_ITERATIONS] iterations. A: [a]. B: [b]. C:[c]. Current value: [solution]. Expected lower limit: [lower_limit]. Expected upper limit: [upper_limit].")
	return FALSE

/// Pumps gas from src to output_air. Amount depends on target_pressure
/datum/gas_mixture/proc/pump_gas_to(datum/gas_mixture/output_air, target_pressure, specific_gas = null, datum/gas_mixture/output_pipenet_air = null)
	var/datum/gas_mixture/input_air = specific_gas ? remove_specific_ratio(specific_gas, 1) : src
	var/temperature_delta = abs(input_air.temperature - output_air.temperature)
	var/datum/gas_mixture/removed

	var/transfer_moles_output = input_air.gas_pressure_calculate(output_air, target_pressure, temperature_delta <= 5)
	var/transfer_moles_pipenet = output_pipenet_air?.volume ? input_air.gas_pressure_calculate(output_pipenet_air, target_pressure, temperature_delta <= 5) : 0
	var/transfer_moles = max(transfer_moles_output, transfer_moles_pipenet)

	if(specific_gas)
		removed = input_air.remove_specific(specific_gas, transfer_moles)
		merge(input_air) // Merge the remaining gas back to the input node
	else
		removed = input_air.remove(transfer_moles)

	if(!removed)
		return FALSE

	output_air.merge(removed)
	return removed

/// Releases gas from src to output air. This means that it can not transfer air to gas mixture with higher pressure.
/datum/gas_mixture/proc/release_gas_to(datum/gas_mixture/output_air, target_pressure, rate=1, datum/gas_mixture/output_pipenet_air = null)
	var/output_starting_pressure = output_air.return_pressure()
	var/input_starting_pressure = return_pressure()

	//Need at least 10 KPa difference to overcome friction in the mechanism
	if(output_starting_pressure >= min(target_pressure, input_starting_pressure-10))
		return FALSE
	//Can not have a pressure delta that would cause output_pressure > input_pressure
	target_pressure = output_starting_pressure + min(target_pressure - output_starting_pressure, (input_starting_pressure - output_starting_pressure)/2)
	var/temperature_delta = abs(temperature - output_air.temperature)

	var/transfer_moles_output = gas_pressure_calculate(output_air, target_pressure, temperature_delta <= 5)
	var/transfer_moles_pipenet = output_pipenet_air?.volume ? gas_pressure_calculate(output_pipenet_air, target_pressure, temperature_delta <= 5) : 0
	var/transfer_moles = max(transfer_moles_output, transfer_moles_pipenet)

	//Actually transfer the gas
	var/datum/gas_mixture/removed = remove(transfer_moles * rate)

	if(!removed)
		return FALSE

	output_air.merge(removed)
	return TRUE

// /datum/gas_mixture/proc/electrolyze removed. /tg/'s electrolyzer
// machinery (which is the only caller) isn't ported to DQ; the proc had no
// live callers, and keeping it required /datum/electrolyzer_reaction +
// GLOB.electrolyzer_reactions stubs in tg_infra_compat. Re-add this proc
// when porting /tg/ electrolyzer machinery.

/// Convert a gas mixture to a string (ie. "o2=22;n2=82;TEMP=180")
/// Rounds all temperature and gases to 0.01 and skips any gases less than that amount
/datum/gas_mixture/proc/to_string()
	var/rounded_temp = round(temperature, 0.01)

	var/list/atmos_contents = list()
	var/temperature_str = "TEMP=[num2text(rounded_temp)]"

	var/list/cached_gases = get_gases()
	if(!length(cached_gases) || total_moles() < 0.01)
		return temperature_str

	for(var/gas_path in cached_gases)
		var/gas_moles = round(cached_gases[gas_path], 0.01)
		if(gas_moles < 0.01)
			continue
		var/list/gas_meta = GLOB.meta_gas_info[gas_path]
		var/gas_id = gas_meta ? gas_meta[META_GAS_ID] : "[gas_path]"
		atmos_contents += "[gas_id]=[num2text(gas_moles)]"

	atmos_contents += temperature_str
	return atmos_contents.Join(";")
