// gas_store(): a gas mixture the holder owns and starts with (doc/rewrite/lifecycle.md "Starting state").
// Replaces DECLARE_GAS (code/__defines/lifecycle_decl.dm), which stays until the codemod has moved its sites.
//
//	CAPABILITY(/obj/structure/transit_tube_pod, gas_store(nameof(air_contents), CELL_VOLUME, T20C, list(GAS_O2 = O2STANDARD * ONE_ATMOSPHERE * 2, GAS_N2 = N2STANDARD * ONE_ATMOSPHERE)))
//
// At init the holder var gets a new /datum/gas_mixture of `volume` litres at `temp` kelvin holding `gases`
// (list(GAS_X = kPa): moles = P * V / (R * T)), owned by the holder (rel_set: its arena slot goes with it). A var
// already holding a mixture is kept. `volume` and `temp` may name holder vars (nameof(volume)), read per instance.
// With `pressure =` (kPa, or nameof() a holder var) the gases are fractions of that pressure: a pressure tank whose subtypes
// fill to another start_pressure declares gas_store(nameof(air_temporary), nameof(volume), T20C, list(GAS_O2 = 1), pressure = nameof(start_pressure)).
// A subtype with other gases declares gas_store() again on the same var: it replaces the parent's (one per var).

/datum/capability/gas_store
	/// The engine runs on_holder_init() for a type declared in a CAPABILITIES block; a CAPABILITY() line reaches legacy_holder_init() itself.
	holder_hooks = HOLDER_HOOK_INIT
	/// The holder var that owns the mixture.
	var/var_name
	/// Litres, or the name of a holder var.
	var/volume = CELL_VOLUME
	/// Kelvin, or the name of a holder var.
	var/temp = T20C
	/// list(GAS_X = kPa), or null for an empty mixture. Shared: never written after construction.
	var/list/gases
	/// null: the gases are kPa. Else kPa (or a holder var name) the gases are fractions of.
	var/pressure

/**
 * A gas mixture in the holder's var `var_name` (nameof()), made at init: `volume` litres at `temp` kelvin of `gases`
 * (list(GAS_X = kPa)). volume and temp may be nameof() a holder var.
 */
/proc/gas_store(var_name, volume = CELL_VOLUME, temp = T20C, list/gases = null, pressure = null)
	var/datum/capability/gas_store/C = new
	C.var_name = var_name
	C.volume = volume
	C.temp = temp
	C.gases = length(gases) ? gases.Copy() : null
	C.pressure = pressure
	C.key = "gas_store:[var_name]"
	return C

/datum/capability/gas_store/owned()
	. = ..()
	. += owns(var_name, type = /datum/gas_mixture)

/datum/capability/gas_store/legacy_holder_init(atom/holder, mapload)
	if(!(var_name in holder.vars))
		stack_trace("gas_store([var_name]) on [holder.type], which has no such var")
		return
	if(isdatum(holder.vars[var_name]))
		return
	var/litres = istext(volume) ? holder.vars[volume] : volume
	var/kelvin = (istext(temp) ? holder.vars[temp] : temp) || T20C
	var/datum/gas_mixture/mix = new /datum/gas_mixture(litres)
	heat_set(mix, kelvin)
	var/scale = isnull(pressure) ? 1 : (istext(pressure) ? holder.vars[pressure] : pressure)
	for(var/gas_id in gases)
		mix.adjust_gas(gas_id, gases[gas_id] * scale * litres / (R_IDEAL_GAS_EQUATION * kelvin))
	rel_set(holder, var_name, mix)

/// The engine form of the init: the same mixture, made once (a var already holding one is kept, so a table type running both forms makes one).
/datum/capability/gas_store/on_holder_init(datum/act/eval/A)
	legacy_holder_init(A.holder, A.mapload)
