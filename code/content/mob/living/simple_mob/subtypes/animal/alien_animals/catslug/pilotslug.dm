//Pilot Catslug

/mob/living/simple_mob/vore/alienanimals/catslug/custom/pilotslug
	name = "Navigator Purrverick"
	desc = "A black-furred noodley bodied creature with thin arms and legs, and gloomy dark eyes. This one exudes an aura of coolness, they're so cool that their pilot's liscense was suspended."
	tt_desc = "Mollusca Felis Mischefterous"
	color = "#2b2b2b"

	can_wear_hat = TRUE

CAPABILITIES(/mob/living/simple_mob/vore/alienanimals/catslug/custom/pilotslug)
	configure(atom_rules(catalogue_data = list(/datum/category_item/catalogue/fauna/catslug/custom/pilotslug)))
	configure(living_rules(say_list_type = /datum/say_list/catslug/custom/pilotslug))
	rolls(nameof(takes_a_helm), chance(25))
	after_init(0, then(PROC_REF(take_a_helm))) // once the map has loaded: the helms are placed

/// One in four Purrvericks start at a ship's helm (rolls()).
/mob/living/simple_mob/vore/alienanimals/catslug/custom/pilotslug/var/takes_a_helm = FALSE

/// Sits at a random helm on a player level, open to ghosts (after_init()).
/mob/living/simple_mob/vore/alienanimals/catslug/custom/pilotslug/proc/take_a_helm(datum/act/timer/A)
	if(!takes_a_helm)
		return
	var/list/possible_targets = list()
	for(var/obj/machinery/computer/ship/helm/h in world)
		if(QDELETED(h))
			continue
		var/turf/destination = get_turf(h)
		if(destination && (destination.z in using_map.player_levels))
			// Keep one draw entry per helm, including helms sharing a tile.
			possible_targets += destination
	if(!length(possible_targets))
		return
	forceMove(pick(possible_targets))
	set_ghostjoin(TRUE)
