// Away-mission mob spawner.
//
// Lazily spawns a simple_mob on its turf and re-spawns once the previous one
// dies, with a decaying chance so a nest eventually depletes. Used by live
// submaps (maps/submaps/space_rocks/* asteroid nests) and the area subtypes in
// maps/common/common_things.dm.
//
// The implementation originally lived in the (now-removed) offmap glue
// maps/offmap/common_offmaps.dm. It was temporarily replaced by a vars-only
// stub in code/modules/map_stubs/map_stubs.dm, which silently disabled every
// spawner that live maps still place; this restores the real Initialize() +
// process() behaviour. The /shadekin subtype is intentionally not ported — the
// shadekin mob and its icon were removed from this fork.

/obj/tether_away_spawner
	name = "RENAME ME, JERK"
	desc = "Spawns the mobs!"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x"
	invisibility = INVISIBILITY_ABSTRACT
	mouse_opacity = 0
	density = 0
	anchored = 1

	//Weighted with values (not %chance, but relative weight)
	//Can be left value-less for all equally likely
	var/list/mobs_to_pick_from

	//When the below chance fails, the spawner is marked as depleted and stops spawning
	var/prob_spawn = 100	//Chance of spawning a mob whenever they don't have one
	var/prob_fall = 5		//Above decreases by this much each time one spawns

	//Settings to help mappers/coders have their mobs do what they want in this case
	var/faction				//To prevent infighting if it spawns various mobs, set a faction
	var/atmos_comp			//TRUE will set all their survivability to be within 20% of the current air
	//var/guard				//# will set the mobs to remain nearby their spawn point within this dist

	//Internal use only
	var/mob/living/simple_mob/my_mob
	var/depleted = FALSE

/obj/tether_away_spawner/Initialize(mapload)
	. = ..()

	if(!LAZYLEN(mobs_to_pick_from))
		log_mapping("Mob spawner at [x],[y],[z] ([get_area(src)]) had no mobs_to_pick_from set on it!")
		flags |= ATOM_INITIALIZED
		return INITIALIZE_HINT_QDEL
	START_PROCESSING(SSobj, src)

/obj/tether_away_spawner/process()
	if(my_mob && my_mob.stat != DEAD)
		return //No need

	for(var/mob/living/L in view(src,world.view))
		if(L.client)
			return //I'll wait.

	if(prob(prob_spawn))
		prob_spawn -= prob_fall
		var/picked_type = pickweight(mobs_to_pick_from)
		my_mob = new picked_type(get_turf(src))
		my_mob.low_priority = TRUE

		if(faction)
			my_mob.faction = faction

		if(atmos_comp)
			var/turf/T = get_turf(src)
			var/datum/gas_mixture/env = T.return_air()
			if(env)
				if(my_mob.minbodytemp > env.temperature)
					my_mob.minbodytemp = env.temperature * 0.8
				if(my_mob.maxbodytemp < env.temperature)
					my_mob.maxbodytemp = env.temperature * 1.2

				// LINDA gas reads (post-atmos-rewrite): direct env.gas[...] list
				// access is gone; LINDA_GAS_AMT(mix, id) returns a gas's moles.
				if(my_mob.min_oxy)
					my_mob.min_oxy = LINDA_GAS_AMT(env, GAS_O2) * 0.8
				if(my_mob.min_tox)
					my_mob.min_tox = LINDA_GAS_AMT(env, GAS_PHORON) * 0.8
				if(my_mob.min_n2)
					my_mob.min_n2 = LINDA_GAS_AMT(env, GAS_N2) * 0.8
				if(my_mob.min_co2)
					my_mob.min_co2 = LINDA_GAS_AMT(env, GAS_CO2) * 0.8
				if(my_mob.max_oxy)
					my_mob.max_oxy = LINDA_GAS_AMT(env, GAS_O2) * 1.2
				if(my_mob.max_tox)
					my_mob.max_tox = LINDA_GAS_AMT(env, GAS_PHORON) * 1.2
				if(my_mob.max_n2)
					my_mob.max_n2 = LINDA_GAS_AMT(env, GAS_N2) * 1.2
				if(my_mob.max_co2)
					my_mob.max_co2 = LINDA_GAS_AMT(env, GAS_CO2) * 1.2
		return
	else
		STOP_PROCESSING(SSobj, src)
		depleted = TRUE
		return
