// Boiling (the boiling points: code/content/reagents/reagents/boiling_points.dm).
//
// Boiling is limited by the heat that reaches the container. A holder hotter than a reagent's boiling point sheds that excess heat as vapour: every unit that
// boils carries BOIL_LATENT_HEAT joules out of the container, so the liquid is held at its boiling point while any of it remains, and a heater that delivers
// P watts boils P / BOIL_LATENT_HEAT units a second (a hotter dial delivers more: code/content/reagents/machinery/hot_plate.dm). A mixture boils its lowest-boiling
// component first. A dissolved gas (a point under 0 C) leaves at BOIL_RATE_DISSOLVED_GAS a second whatever the heat, so a reagent dosed into a warming beaker is
// still there when the beaker reaches the band that uses it. Nothing in the world boils by itself: a heater asks for it (boil_step(): the hot plate, the bunsen burner).
//
// The vapour is not a gas and never reaches the air: boil_step() returns it as a list, and the caller either deletes it (the default: it is gone) or hands it to
// a condenser, which collects it into a second container (real distillation). Every boil is written to the world log under GLOB.chem_trace.

/// Boils the contents for `seconds` at the holder's own temperature. Returns the vapour as list(reagent id => list(units, data)), empty when nothing boiled.
/datum/reagents/proc/boil_step(seconds)
	var/list/vapour = list()
	if(!length(reagent_list) || seconds <= 0)
		return vapour
	if(detonate_peroxide())
		return vapour // heated peroxide went off
	var/temperature = reaction_temperature()
	var/capacity = my_atom ? my_atom.thermal_properties()[THERMAL_CAPACITY] : 0
	var/list/hot = list()
	for(var/datum/reagent/R as anything in reagent_list)
		var/point = R.boiling_point_k()
		if(temperature > point)
			hot[R] = point
	if(!length(hot))
		return vapour
	var/boiled = 0
	var/list/ordered = list()
	for(var/datum/reagent/R as anything in hot)
		ordered += R
	// The lowest boiling point goes first.
	for(var/i in 1 to length(ordered))
		for(var/j in i + 1 to length(ordered))
			if(hot[ordered[j]] < hot[ordered[i]])
				ordered.Swap(i, j)
	var/spare = 0 // joules above the lowest boiling point still to spend: the container is held at that point while its reagent lasts
	if(capacity > 0)
		spare = (temperature - hot[ordered[1]]) * capacity
	for(var/datum/reagent/R as anything in ordered)
		var/point = hot[R]
		var/units
		if(point < T0C)
			units = min(R.volume, BOIL_RATE_DISSOLVED_GAS * seconds)
		else
			// A reagent boils only on the heat above its own point.
			units = min(R.volume, min(spare, max((temperature - point) * capacity, 0)) / BOIL_LATENT_HEAT)
			spare -= units * BOIL_LATENT_HEAT
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
