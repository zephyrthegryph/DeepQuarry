/obj/effect/effect/sparks/confetti
	name = "confetti"
	icon = 'icons/effects/effects_vr.dmi'
	icon_state = "confetti"

/obj/effect/effect/sparks/confetti/Initialize(mapload)
	. = ..()
	playsound(src, "sound/items/confetti.ogg", 100, 1)

/datum/effect/effect/system/confetti_spread
	var/total_sparks = 0 // To stop it being spammed and lagging!

/datum/effect/effect/system/confetti_spread/set_up(n = 3, c = 0, loca)
	if(n > 10)
		n = 10
	number = n
	cardinals = c
	if(istype(loca, /turf/))
		location = loca
	else
		location = get_turf(loca)

/datum/effect/effect/system/confetti_spread/proc/emit_one_confetti_spark()
	if(holder)
		src.location = get_turf(holder)
	var/obj/effect/effect/sparks/confetti = new /obj/effect/effect/sparks/confetti(src.location)
	src.total_sparks++
	var/direction
	if(src.cardinals)
		direction = pick(GLOB.cardinal)
	else
		direction = pick(GLOB.alldirs)
	for(var/i=0, i<pick(1,2,3), i++)
		sleep(5)
		step(confetti,direction)
	addtimer(CALLBACK(src, PROC_REF(dec_confetti_sparks)), 20)

/datum/effect/effect/system/confetti_spread/proc/dec_confetti_sparks()
	src.total_sparks--

/datum/effect/effect/system/confetti_spread/start()
	var/i = 0
	for(i=0, i<src.number, i++)
		if(src.total_sparks > 20)
			return
		INVOKE_ASYNC(src, PROC_REF(emit_one_confetti_spark))
