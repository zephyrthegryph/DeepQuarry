// Where boiled-off vapour goes when no condenser catches it (boil_step() in boiling.dm returns it; a heater hands it to a condenser first, then here).
//
// A reagent that is a real gas (GLOB.reagent_vapour_gases: hydrogen, oxygen, nitrogen, water, phoron, welding fuel, chlorine, ammonia) becomes that atmos gas on the
// tile of the heater: CHEM_GAS_MOLES_PER_UNIT moles a unit, at the temperature it left the container at, so it carries its heat into the room's air and the air's own
// behaviour (breathing, fire, visibility, pressure) takes over. Any other reagent's vapour goes into the sparse vapour layer (code/world/systems/chem_vapour.dm).
// Everything is written to the world log under GLOB.chem_trace.

/// Puts `moles` of the atmos gas `gas` at `kelvin` into this turf's air, mixing by heat capacity. Returns the moles the air took (0 for a turf with no air).
/turf/proc/vent_gas(gas, moles, kelvin)
	if(moles <= 0)
		return 0
	var/datum/gas_mixture/air = return_air()
	if(!air)
		return 0
	var/datum/gas/gas_type = GLOB.gas_path_by_idx[GAS_IDX(gas) + 1]
	var/old_capacity = air.heat_capacity()
	var/old_kelvin = air.return_temperature()
	var/added_capacity = moles * initial(gas_type.specific_heat)
	air.adjust_gas(gas, moles)
	if(kelvin > 0 && old_capacity + added_capacity > 0)
		heat_set(air, (old_capacity * old_kelvin + added_capacity * kelvin) / (old_capacity + added_capacity))
	SSair?.add_to_active(src)
	return moles

/// Lets boiled-off vapour (boil_step()'s list: reagent id => list(units, data, kelvin)) out at `where`. A reagent that is a gas enters the air of the tile as that gas;
/// the rest goes into the vapour layer. Returns the units that were let out (into the air or the layer).
/proc/vent_vapour_at(turf/where, list/vapour, source)
	. = 0
	if(!where || !length(vapour))
		return
	for(var/id in vapour)
		var/list/row = vapour[id]
		var/gas = GLOB.reagent_vapour_gases[id]
		if(isnull(gas))
			var/layered = chem_vapour_add(where, id, row[1], row[3])
			. += layered
			if(GLOB.chem_trace)
				log_world("CHEM: [source] vented [round(row[1], 0.001)]u of [id] at [where] into the vapour layer ([round(layered, 0.001)]u taken)")
			continue
		var/taken = where.vent_gas(gas, row[1] * CHEM_GAS_MOLES_PER_UNIT, row[3])
		if(taken <= 0)
			if(GLOB.chem_trace)
				log_world("CHEM: [source] vented [round(row[1], 0.001)]u of [id] at [where]: the tile has no air, so it is gone")
			continue
		. += row[1]
		if(GLOB.chem_trace)
			log_world("CHEM: [source] vented [round(row[1], 0.001)]u of [id] at [where] as [round(taken, 0.001)] mol of [gas] at [round(row[3] - T0C, 0.1)] C")
