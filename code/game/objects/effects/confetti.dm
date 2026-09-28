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
		location_handle = om_handle(loca)
	else
		location_handle = om_handle(get_turf(loca))

/datum/effect/effect/system/confetti_spread/proc/emit_one_confetti_spark()
	if(holder)
		src.location_handle = om_handle(get_turf(holder))
	var/obj/effect/effect/sparks/confetti = new /obj/effect/effect/sparks/confetti(src.get_location())
	src.total_sparks++
	var/direction
	if(src.cardinals)
		direction = pick(GLOB.cardinal)
	else
		direction = pick(GLOB.alldirs)
	var/steps = pick(1,2,3)
	om_after_drift(confetti, direction, steps, 5)
	om_after(src, 20 + steps * 5, PROC_REF(dec_confetti_sparks))

/datum/effect/effect/system/confetti_spread/proc/dec_confetti_sparks()
	src.total_sparks--

/datum/effect/effect/system/confetti_spread/start()
	var/i = 0
	for(i=0, i<src.number, i++)
		if(src.total_sparks > 20)
			return
		emit_one_confetti_spark()
