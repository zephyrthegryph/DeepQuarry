/datum/spell/aoe_turf/knock/harvester
	name = "Force Doors"
	desc = "Mortal portals are no match for your occult might."

	spell_flags = CONSTRUCT_CHECK

	charge_max = 100
	invocation = ""
	invocation_type = "silent"
	range = 4

	hud_state = "const_knock"

/datum/spell/aoe_turf/knock/harvester/cast(list/targets)
/*	for(var/turf/T in targets) //Disintigrating doors is bad, okay.
		for(var/obj/machinery/door/door in T.contents)
			spawn door.cultify()
	return */
	for(var/turf/T in targets)
		for(var/obj/machinery/door/door in contents_of(T))
			if(istype(door,/obj/machinery/door/airlock))
				var/obj/machinery/door/airlock/AL = door
				AL.unbolt_unweld() //The spirits of the damned care not for your locks, or your welding tools.
			else if(istype(door, /obj/machinery/door/firedoor))
				var/obj/machinery/door/firedoor/FD = door
				FD.set_blocked(0)
			door.open(1)
	return
