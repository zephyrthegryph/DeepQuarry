// Freezing and melting (the ice reagent: code/content/reagents/reagents/content/drinks/drink_ice.dm; boiling is boiling.dm).
//
// Water held below 0 C freezes into ice and ice above 0 C melts into water, in the lab glassware (a /obj/item/reagent_containers/glass: beaker, bucket, basin; the
// drinks on the bar keep their ice). Each unit that changes phase carries ICE_MELT_LATENT_HEAT joules through the container's heat body (add_heat(): the real
// heat system), so a container of ice and water is held at 0 C while any of the ice remains, and a container chilled below 0 C warms back to 0 C as its water
// freezes. Only as much changes as the heat on hand allows: a few kelvin of excess melts a few units, never more.
//
// phase_step() runs inside handle_reactions() (the beaker's contents settle at the temperature they have now) and from the glass's own two-second timer while it
// holds ice or water with a heat body (code/content/reagents/purification/nesting.dm), so a bath keeps melting after nobody touches it. Every phase change is
// written to the world log under GLOB.chem_trace.

/// Melts the ice that is above 0 C and freezes the water that is below it, as far as the heat in the container allows. Returns the units that changed phase.
/datum/reagents/proc/phase_step()
	var/obj/item/reagent_containers/glass/G = my_atom
	if(!istype(G) || QDELETED(G))
		return 0
	var/datum/reagent/ice = reagent_by_id[REAGENT_ID_ICE]
	var/datum/reagent/water = reagent_by_id[REAGENT_ID_WATER]
	if(!ice && !(water && !isnull(G.heat_body)))
		return 0 // nothing to melt, and water with no heat body is at its surroundings' temperature, which is not a freezer
	var/temperature = G.get_temperature()
	var/list/properties = G.thermal_properties()
	var/capacity = properties[THERMAL_CAPACITY]
	if(!(capacity > 0))
		return 0
	if(ice && temperature > T0C + ICE_PHASE_TOLERANCE)
		var/units = min(ice.volume, (temperature - T0C) * capacity / ICE_MELT_LATENT_HEAT)
		if(units < MINIMUM_CHEMICAL_VOLUME)
			return 0
		remove_reagent(REAGENT_ID_ICE, units, safety = 1)
		add_reagent(REAGENT_ID_WATER, units, safety = 1)
		G.add_heat(-units * ICE_MELT_LATENT_HEAT)
		if(GLOB.chem_trace)
			log_world("CHEM: [G] at [round(temperature - T0C, 0.1)] C melted [round(units, 0.001)]u of ice, taking [round(units * ICE_MELT_LATENT_HEAT)] J out of it (now [round(G.get_temperature() - T0C, 0.1)] C, [round(get_reagent_amount(REAGENT_ID_ICE), 0.001)]u of ice left)")
		return units
	if(water && temperature < T0C - ICE_PHASE_TOLERANCE)
		var/units = min(water.volume, (T0C - temperature) * capacity / ICE_MELT_LATENT_HEAT)
		if(units < MINIMUM_CHEMICAL_VOLUME)
			return 0
		remove_reagent(REAGENT_ID_WATER, units, safety = 1)
		add_reagent(REAGENT_ID_ICE, units, safety = 1)
		G.add_heat(units * ICE_MELT_LATENT_HEAT)
		if(GLOB.chem_trace)
			log_world("CHEM: [G] at [round(temperature - T0C, 0.1)] C froze [round(units, 0.001)]u of water, giving [round(units * ICE_MELT_LATENT_HEAT)] J to it (now [round(G.get_temperature() - T0C, 0.1)] C, [round(get_reagent_amount(REAGENT_ID_ICE), 0.001)]u of ice)")
		return units
	return 0
