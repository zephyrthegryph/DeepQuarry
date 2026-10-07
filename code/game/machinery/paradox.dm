/obj/machinery/paradoxrift
	name = "Paradoxical Rift Generator"
	idle_power_usage = 2500000
	use_power = USE_POWER_OFF
	icon = 'icons/obj/machines/defense.dmi'
	icon_state = "paradox"
	circuit = /obj/item/circuitboard/paradoxrift
	var/build_eff = 1
	var/loot_eff = 1
	var/chaos_eff = 1

/// Unpowered: the rift spills loot only while it has no power.
OM_DERIVE_FIELD(/obj/machinery/paradoxrift, unpowered, list("stat"))
/obj/machinery/paradoxrift/proc/unpowered()
	return power_lost()

/obj/item/circuitboard/paradoxrift
	name = "paradox rift generator circuit"
	build_path = /obj/machinery/paradoxrift
	board_type = new /datum/frame/frame_types/machine
	req_components = list(
							/obj/item/stack/cable_coil = 10,
							/obj/item/stock_parts/capacitor = 4,
							/obj/item/stock_parts/manipulator = 6,
							/obj/item/stock_parts/scanning_module = 10)
	hidden = TRUE //This needs a rework before it's enabled.

/obj/machinery/paradoxrift/RefreshParts()
	..()
	var/man_rating = get_part_rating(/obj/item/stock_parts/manipulator)
	var/scan_rating = get_part_rating(/obj/item/stock_parts/scanning_module)
	var/cap_rating = get_part_rating(/obj/item/stock_parts/capacitor)

	build_eff = man_rating
	loot_eff = scan_rating
	chaos_eff = cap_rating


/// Spills loot while unpowered (the declaration above runs it only then).
// Its periodic work: work_step() while it is started (code/library/machine/started_work.dm).
CAPABILITIES(/obj/machinery/paradoxrift)
	started_work(step = PROC_REF(work_step), starts = TRUE, gate = PROC_REF(unpowered), wakes_on = list(STAT_OPERABLE), unpowered = TRUE)

/obj/machinery/paradoxrift/proc/work_step(datum/act/timer/A)
	if(prob(0.5*build_eff))
		if(prob(3*loot_eff))
			new /obj/random/greaterportalloot (src.loc)
			if(prob(30/chaos_eff))
				new /obj/random/mob/interspace (src.loc)
		else
			new /obj/random/portalloot (src.loc)
			if(prob(15/chaos_eff))
				new /obj/random/mob/interspace (src.loc)


/obj/random/portalloot
	name = "Random Portal Loot"
	desc = "This is a random goodie from the void."
	icon_state = "medicalkit"

DECLARE_LOOT(/obj/random/portalloot, LOOT_TABLE(\
	/obj/item/stock_parts/capacitor, \
	/obj/item/stock_parts/manipulator, \
	/obj/item/stock_parts/scanning_module, \
	/obj/item/stock_parts/matter_bin, \
	/obj/item/stock_parts/micro_laser, \
	/obj/item/stack/material/phoron, \
	/obj/item/stack/material/deuterium, \
	/obj/item/stack/material/tritium, \
	/obj/item/stack/material/uranium))

/obj/random/greaterportalloot
	name = "Random Greater Portal Loot"
	desc = "This is a random goodie from the void."
	icon_state = "medicalkit"

DECLARE_LOOT(/obj/random/greaterportalloot, LOOT_TABLE(\
	/obj/item/stock_parts/capacitor = 6, \
	/obj/item/stock_parts/manipulator = 6, \
	/obj/item/stock_parts/scanning_module = 6, \
	/obj/item/stock_parts/matter_bin = 6, \
	/obj/item/stock_parts/micro_laser = 6, \
	/obj/random/smes_coil = 4, \
	/obj/random/bomb_supply = 4, \
	/obj/random/powercell = 4, \
	/obj/random/tool/powermaint = 4, \
	/obj/item/rcd = 1, \
	/obj/item/rcd/advanced = 4, \
	/obj/vehicle/bike/random = 1, \
	/obj/vehicle/train/engine/quadbike/random = 1, \
	/obj/random/material = 4, \
	/obj/random/material/refined = 4, \
	/obj/random/material/precious = 4, \
	/obj/random/bluespace = 1, \
	/obj/random/tool/alien = 4, \
	/obj/item/circuitboard/paradoxrift = 1, \
	/obj/item/prop/alien/junk = 4))

/obj/random/mob/interspace
	name = "Random Interspace"
	desc = "This is a random mob from space or inbetween space."
	icon_state = "humanoid"

	mob_faction = "demon"
	mob_returns_home = 1
	mob_wander_distance = 7

DECLARE_LOOT(/obj/random/mob/interspace, LOOT_TABLE(\
	/mob/living/simple_mob/vore/sonadile = 5, \
	/mob/living/simple_mob/vore/solargrub = 30, \
	/mob/living/simple_mob/vore/stalker = 5, \
	/mob/living/simple_mob/vore/bigdragon = 1, \
	/mob/living/simple_mob/humanoid/cultist/magus/rift = 1, \
	/mob/living/simple_mob/vore/cryptdrake = 1, \
	/mob/living/simple_mob/vore/demonAI = 15, \
	/mob/living/simple_mob/shadekin = 25, \
	/mob/living/simple_mob/vore/sect_queen = 15, \
	/mob/living/simple_mob/vore/sect_drone = 25, \
	/mob/living/simple_mob/vore/aggressive/deathclaw = 25, \
	/mob/living/simple_mob/vore/aggressive/corrupthound = 25, \
	/mob/living/simple_mob/metroid/juvenile/super = 15, \
	/mob/living/simple_mob/animal/space/carp = 25, \
	/mob/living/simple_mob/animal/space/carp/large = 15, \
	/mob/living/simple_mob/animal/space/carp/large/huge = 15, \
	/mob/living/simple_mob/animal/space/carp/puffer = 25, \
	/mob/living/simple_mob/animal/space/alien = 25, \
	/mob/living/simple_mob/animal/space/alien/sentinel = 15, \
	/mob/living/simple_mob/vore/pakkun = 25, \
	/mob/living/simple_mob/vore/scel = 25, \
	/mob/living/simple_mob/vore/vore_hostile/abyss_lurker = 5))


/// Whether its work starts at initialization (started_work(starts =)).
/obj/machinery/paradoxrift/step_start_condition()
	return power_lost()
