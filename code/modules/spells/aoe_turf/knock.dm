/datum/spell/aoe_turf/knock
	name = "Knock"
	desc = "This spell opens nearby doors and does not require wizard garb."

	school = "transmutation"
	charge_max = 100
	spell_flags = 0
	invocation = "AULIE OXIN FIERA"
	invocation_type = SpI_WHISPER
	range = 3
	cooldown_min = 20 //20 deciseconds reduction per rank

	hud_state = "wiz_knock"

/datum/spell/aoe_turf/knock/cast(list/targets)
	for(var/turf/T in targets)
		for(var/obj/machinery/door/door in contents_of(T))
			after(door, 0.1 SECONDS, TYPE_PROC_REF(/obj/machinery/door, knocked_open))
	return


/// The knock spell unbolts and opens the door.
/obj/machinery/door/proc/knocked_open()
	if(istype(src, /obj/machinery/door/airlock))
		var/obj/machinery/door/airlock/AL = src //casting is important
		set_bolted(AL, FALSE, TRUE)
	open()
