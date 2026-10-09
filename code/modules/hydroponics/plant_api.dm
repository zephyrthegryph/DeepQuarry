// The plant system's API (code/modules/hydroponics/plant_service.dm declares the system).
//
//   SSplants.ready()                       the system, set up on first use (it is lazy)
//   SSplants.register_line(seed)           file a private seed as a new numbered line
//   SSplants.create_random_seed(survive)   a new random seed line (`survive`: able to live on the station)
//   SSplants.add_plant(plant)              a spreading plant joins the growing set and its growth lane
//   SSplants.remove_plant(plant)           it leaves them

/// Typed, so `SSplants.ready().var` reads as the system's own var.
/datum/system/plants/ready()
	RETURN_TYPE(/datum/system/plants)
	return ..()

/// Files a registered copy of the private seed S as a new line (a numbered uid) and returns it.
/// S stays with its holder, renamed to the line, so later harvests don't file it again.
/datum/system/plants/proc/register_line(datum/seed/S)
	if(!S || is_registered(S))
		return S
	var/datum/seed/line = S.copy_line()
	line.uid = length(seeds) + 1
	line.name = "[line.uid]"
	seeds[line.name] = line
	S.uid = line.uid
	S.name = line.name
	return line

// Proc for creating a random seed type.
/datum/system/plants/proc/create_random_seed(survive_on_station)
	var/datum/seed/seed = new()
	seed.randomize()
	seed.uid = length(seeds) + 1
	seed.name = "[seed.uid]"
	seeds[seed.name] = seed

	if(survive_on_station)
		if(seed.consume_gasses)
			seed.consume_gasses[GAS_PHORON] = null
			seed.consume_gasses[GAS_CH4] = null
			seed.consume_gasses[GAS_CO2] = null
		if(seed.chems && !isnull(seed.chems[REAGENT_ID_PACID]))
			seed.chems[REAGENT_ID_PACID] = null // Eating through the hull will make these plants completely inviable, albeit very dangerous.
			seed.chems -= null // Setting to null does not actually remove the entry, which is weird.
		seed.set_trait(TRAIT_IDEAL_HEAT,293)
		seed.set_trait(TRAIT_HEAT_TOLERANCE,20)
		seed.set_trait(TRAIT_IDEAL_LIGHT,8)
		seed.set_trait(TRAIT_LIGHT_TOLERANCE,5)
		seed.set_trait(TRAIT_LOWKPA_TOLERANCE,25)
		seed.set_trait(TRAIT_HIGHKPA_TOLERANCE,200)
	return seed

/datum/system/plants/proc/add_plant(obj/effect/plant/plant)
	if(!QDELETED(plant))
		registry_join(REGISTRY_GROWING_PLANTS, plant)
		plant.set_growing(TRUE)

/datum/system/plants/proc/remove_plant(obj/effect/plant/plant)
	registry_leave(REGISTRY_GROWING_PLANTS, plant)
	plant.set_growing(FALSE)
