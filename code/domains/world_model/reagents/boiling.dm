// Boiling (the boiling points: code/content/reagents/reagents/boiling_points.dm).
//
// A holder hotter than a reagent's boiling point loses that reagent, gradually: BOIL_RATE_PER_KELVIN units a second for every kelvin above the point (never
// less than BOIL_RATE_MINIMUM while above it). Each unit that boils carries BOIL_LATENT_HEAT joules out of the container, so a container held just above a
// boiling point sits near it while the reagent lasts. Nothing in the world boils by itself: a heater asks for it (boil_step(): the hot plate, the bunsen burner).
//
// The vapour is not a gas and never reaches the air: boil_step() returns it as a list, and the caller either deletes it (the default: it is gone) or hands it to
// a condenser, which collects it into a second container (real distillation). Every boil is written to the world log under GLOB.chem_trace.

/// Boils the contents for `seconds` at the holder's own temperature. Returns the vapour as list(reagent id => list(units, data)), empty when nothing boiled.
/datum/reagents/proc/boil_step(seconds)
	var/list/vapour = list()
	if(!length(reagent_list) || seconds <= 0)
		return vapour
	var/temperature = reaction_temperature()
	var/boiled = 0
	for(var/datum/reagent/R as anything in reagent_list.Copy())
		var/point = R.boiling_point_k()
		if(temperature <= point)
			continue
		var/units = min(R.volume, max(BOIL_RATE_MINIMUM, (temperature - point) * BOIL_RATE_PER_KELVIN) * seconds)
		if(units <= 0)
			continue
		vapour[R.id] = list(units, R.get_data())
		boiled += units
	for(var/id in vapour)
		remove_reagent(id, vapour[id][1], safety = 1)
	if(!boiled)
		return vapour
	if(GLOB.chem_trace)
		var/list/parts = list()
		for(var/id in vapour)
			parts += "[id] [round(vapour[id][1], 0.001)]"
		log_world("CHEM: [my_atom] at [round(temperature - T0C, 0.1)] C boiled off [round(boiled, 0.001)]u ([jointext(parts, ", ")])")
	my_atom?.add_heat(-boiled * BOIL_LATENT_HEAT)
	handle_reactions()
	return vapour

/// Puts boiled-off vapour (boil_step()'s list) into this holder, as far as it fits. Returns the units taken.
/datum/reagents/proc/condense(list/vapour)
	var/taken = 0
	for(var/id in vapour)
		var/list/row = vapour[id]
		var/before = get_reagent_amount(id)
		add_reagent(id, row[1], row[2], safety = 1)
		taken += max(get_reagent_amount(id) - before, 0)
	if(taken > 0)
		handle_reactions()
		if(GLOB.chem_trace)
			log_world("CHEM: [my_atom] condensed [round(taken, 0.001)]u of vapour; mixture now [purity_summary() || "pure"]")
	return taken
