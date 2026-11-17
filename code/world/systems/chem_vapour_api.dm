// The chem vapour system's API (code/world/systems/chem_vapour.dm declares the system and the layer).
//
//   chem_vapour_add(turf, reagent id, units, kelvin)   puts vapour on a tile; returns the units taken
//   chem_vapour_take(turf, fraction, most)             takes vapour for a breath: reagent id => units
//   chem_vapour_total_at(turf)                         units of vapour on a tile (0 for none)
//   chem_vapour_tiles()                                how many tiles hold vapour
//   chem_vapour_ignite_at(turf, kelvin)                a flame: burns the flammable vapour there; TRUE if it burned

/proc/chem_vapour_add(turf/T, id, units, kelvin)
	return SSchem_vapour.add_vapour(T, id, units, kelvin)

/proc/chem_vapour_take(turf/T, fraction, most)
	return SSchem_vapour.take_vapour(T, fraction, most)

/proc/chem_vapour_total_at(turf/T)
	var/datum/vapour_cell/cell = SSchem_vapour.cell_at(T)
	return cell ? cell.total() : 0

/// The reagent with the most units in the vapour on `T`, or null.
/proc/chem_vapour_main_reagent_at(turf/T)
	var/datum/vapour_cell/cell = SSchem_vapour.cell_at(T)
	if(!cell)
		return null
	var/best
	var/most = 0
	for(var/id in cell.units)
		if(cell.units[id] > most)
			most = cell.units[id]
			best = id
	return best

/proc/chem_vapour_tiles()
	return length(SSchem_vapour.cells)

/// Units of vapour the bounds have refused since boot (a full layer, a full tile).
/proc/chem_vapour_refused()
	return SSchem_vapour.units_refused

/proc/chem_vapour_ignite_at(turf/T, kelvin)
	return SSchem_vapour.ignite_at(T, kelvin)
