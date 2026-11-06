/datum/spell/aoe_turf/conjure/pylon
	name = "Red Pylon"
	desc = "This spell conjures a fragile crystal from Nar-Sie's realm. Makes for a convenient light source."

	charge_max = 200
	spell_flags = CONSTRUCT_CHECK
	invocation = "none"
	invocation_type = SpI_NONE
	range = 0

	summon_type = list(/obj/structure/cult/pylon)

	hud_state = "const_pylon"

/datum/spell/aoe_turf/conjure/pylon/cast(list/targets, mob/user)
	..()
	var/turf/spawn_place = pick(targets)
	for(var/obj/structure/cult/pylon/P in turf_contents_of_type(spawn_place, /obj/structure/cult/pylon))
		if(P.isbroken)
			P.repair(user)
		continue
	return
