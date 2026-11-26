/obj/effect/step_trigger/teleporter/to_mining
	icon = 'icons/obj/structures/stairs_64x64.dmi'
	icon_state = ""
	invisibility = INVISIBILITY_NONE
	plane = TURF_PLANE
	layer = ABOVE_TURF_LAYER

/obj/effect/step_trigger/teleporter/from_mining
	icon = 'icons/obj/structures/stairs_64x64.dmi'
	icon_state = ""
	invisibility = INVISIBILITY_NONE
	plane = TURF_PLANE
	layer = ABOVE_TURF_LAYER

/obj/effect/step_trigger/teleporter/to_solars
	icon = 'icons/obj/structures/stairs_64x64.dmi'
	icon_state = ""
	invisibility = INVISIBILITY_NONE

/obj/effect/step_trigger/teleporter/from_solars
	icon = 'icons/obj/structures/stairs_64x64.dmi'
	icon_state = ""
	invisibility = INVISIBILITY_NONE

/obj/effect/step_trigger/teleporter/wild
	icon = 'icons/obj/structures/stairs_64x64.dmi'
	icon_state = ""
	invisibility = INVISIBILITY_NONE

/obj/effect/step_trigger/teleporter/to_underdark
	icon = 'icons/obj/structures/stairs_64x64.dmi'
	icon_state = ""
	invisibility = INVISIBILITY_NONE

/obj/effect/step_trigger/teleporter/from_underdark
	icon = 'icons/obj/structures/stairs_64x64.dmi'
	icon_state = ""
	invisibility = INVISIBILITY_NONE

/obj/effect/step_trigger/teleporter/to_plains
	icon = 'icons/obj/structures/stairs_64x64.dmi'
	icon_state = ""
	invisibility = INVISIBILITY_NONE

/obj/effect/step_trigger/teleporter/from_plains
	icon = 'icons/obj/structures/stairs_64x64.dmi'
	icon_state = ""
	invisibility = INVISIBILITY_NONE

/obj/effect/step_trigger/teleporter/planetary_fall/virgo3b

/obj/effect/step_trigger/lost_in_space
	icon = 'icons/obj/structures/stairs_64x64.dmi'
	icon_state = ""
	invisibility = INVISIBILITY_NONE
	var/deathmessage = "You drift off into space, floating alone in the void until your life support runs out."

/obj/effect/step_trigger/lost_in_space/Trigger(atom/movable/A) //replacement for shuttle dump zones because there's no empty space levels to dump to
	if(ismob(A))
		to_chat(A, span_danger("[deathmessage]"))
	spent(A)

/obj/effect/step_trigger/lost_in_space/bluespace
	deathmessage = "Everything goes blue as your component particles are scattered throughout the known and unknown universe."
	var/last_sound = 0

/obj/effect/step_trigger/lost_in_space/bluespace/Trigger(A)
	if(ELAPSED(src, last_sound, CLOCK_WORLD) > 5 SECONDS)
		STAMP(src, last_sound, CLOCK_WORLD)
		play_sfx(src, SFX_EFFECTS_SUPERMATTER, 1.5)
	if(ismob(A) && prob(5))//lucky day
		var/destturf = locate(rand(5,world.maxx-5),rand(5,world.maxy-5),pick(using_map.station_levels))
		do_teleport(A, destturf, 0, 1, asoundin = 'sound/effects/phasein.ogg')
	else
		return ..()

//"Red" Armory Door
/obj/machinery/door/airlock/security/armory
	name = "Red Armory"

/obj/machinery/door/airlock/security/armory/allowed(mob/user)
	if(get_security_level() in list("green","blue"))
		return FALSE

	return ..(user)

//Tether-unique network cameras
/obj/machinery/camera/network/tether
	network = list(NETWORK_TETHER)

/obj/machinery/camera/network/outside
	network = list(NETWORK_OUTSIDE)

// Landmarks for wildlife events


// SD Things

/obj/machinery/camera/network/halls
	network = list(NETWORK_HALLS)

/obj/item/multitool/scioutpost
	name = "science outpost linked multitool"
	desc = "It has the data for the science outpost's quantum pad pre-loaded... assuming you didn't override it."

/obj/item/multitool/scioutpost/proc/find_outpost_pad()
	for(var/obj/machinery/power/quantumpad/scioutpost/outpost in world)
		rel_set(src, nameof(connectable), outpost)
		if(connectable())
			set_icon_state("multitool_red")
		return

/obj/machinery/power/quantumpad/scioutpost


/obj/machinery/atmospherics/unary/vent_pump/positive
	use_power = USE_POWER_IDLE
	icon_state = "map_vent_out"
	init_external_pressure_bound = ONE_ATMOSPHERE * 1.1

/obj/machinery/computer/shuttle_control/aerostat_shuttle
	name = "aerostat ferry control console"
	shuttle_tag = "Aerostat Ferry"

/obj/structure/old_roboprinter
	name = "old drone fabricator"
	desc = "Built like a tank, still working after so many years."
	icon = 'icons/obj/machines/drone_fab.dmi'
	icon_state = "drone_fab_idle"
	anchored = TRUE
	density = TRUE

/obj/structure/metal_edge
	name = "metal underside"
	desc = "A metal wall that extends downwards."
	icon = 'icons/turf/cliff.dmi'
	icon_state = "metal"
	anchored = TRUE
	density = FALSE


// === merged from maps/ during hard-fork flatten ===
/////////////////////////////////////////////////////////////////////////////////////
// Add objects that will be used in ALL away missions. Keep area specific stuff separate.
/obj/sc_away_spawner
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
	/// Is it still rolling spawns? The every() below runs while it is.
	var/spawning = FALSE

TRACKED(/obj/sc_away_spawner, spawning)

/// A spawner with no mobs to pick from is deleted; the rest start rolling (setup hook).
/obj/sc_away_spawner/proc/start_rolling(mapload)
	if(!LAZYLEN(mobs_to_pick_from))
		log_mapping("Mob spawner at [x],[y],[z] ([get_area(src)]) had no mobs_to_pick_from set on it!")
		flags |= ATOM_INITIALIZED
		return INITIALIZE_HINT_QDEL
	set_spawning(TRUE)

CAPABILITIES(/obj/sc_away_spawner)
	setup(PROC_REF(start_rolling), mapload = TRUE)
	every(2 SECONDS, then(PROC_REF(spawner_step)), when = nameof(spawning))

/// Every 2 s while it has mobs left to roll: waits out a living mob and a watching player, then rolls a spawn.
/obj/sc_away_spawner/proc/spawner_step(datum/act/A)
	if(my_mob && my_mob.stat != DEAD)
		return //No need

	if(LAZYLEN(loc.human_mobs(world.view)))
		return //I'll wait.

	if(prob(prob_spawn))
		prob_spawn -= prob_fall
		var/picked_type = pickweight(mobs_to_pick_from)
		my_mob = new picked_type(get_turf(src))
		my_mob.set_low_priority(TRUE)

		if(faction)
			my_mob.set_faction(faction)

		if(atmos_comp)
			var/turf/T = get_turf(src)
			var/datum/gas_mixture/env = T.return_air()
			if(env)
				var/env_temp = env.return_temperature()
				my_mob.minbodytemp = env_temp * 0.8
				my_mob.maxbodytemp = env_temp * 1.2

				my_mob.min_oxy = LINDA_GAS_AMT(env, GAS_O2) * 0.8
				my_mob.min_tox = LINDA_GAS_AMT(env, GAS_PHORON) * 0.8
				my_mob.min_n2 = LINDA_GAS_AMT(env, GAS_N2) * 0.8
				my_mob.min_co2 = LINDA_GAS_AMT(env, GAS_CO2) * 0.8
				my_mob.max_oxy = LINDA_GAS_AMT(env, GAS_O2) * 1.2
				my_mob.max_tox = LINDA_GAS_AMT(env, GAS_PHORON) * 1.2
				my_mob.max_n2 = LINDA_GAS_AMT(env, GAS_N2) * 1.2
				my_mob.max_co2 = LINDA_GAS_AMT(env, GAS_CO2) * 1.2
/* // AI TEMPORARY REMOVAL
		if(guard)
			my_mob.returns_home = TRUE
			my_mob.wander_distance = guard
*/
		return
	else
		set_spawning(FALSE)
		depleted = TRUE
		return

/obj/effect/map_effect/portal/master/side_a/retreat_west
	portal_id = "retreat_west"

/obj/effect/map_effect/portal/master/side_b/retreat_west
	portal_id = "retreat_west"

/obj/effect/map_effect/portal/master/side_a/retreat_east
	portal_id = "retreat_east"

/obj/effect/map_effect/portal/master/side_b/retreat_east
	portal_id = "retreat_east"

/obj/machinery/smartfridge/survival_pod/casino
	icon = 'icons/obj/vending.dmi'
	icon_base = "smartfridge"
	icon_contents = "boxes"
	icon_state = "smartfridge"
	name = "Advanced storage"

CAPABILITIES(/obj/item/multitool/scioutpost)
	setup(PROC_REF(find_outpost_pad))
