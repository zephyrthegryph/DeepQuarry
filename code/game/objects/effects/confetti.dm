/obj/effect/effect/sparks/confetti
	name = "confetti"
	icon = 'icons/effects/effects_vr.dmi'
	icon_state = "confetti"

CAPABILITIES(/obj/effect/effect/sparks/confetti)
	after_init(0, then(PROC_REF(init_confetti_sound)))

/obj/effect/effect/sparks/confetti/proc/init_confetti_sound(datum/act/timer/A)
	playsound(src, "sound/items/confetti.ogg", 100, 1)


/datum/effect/effect/system/confetti_spread
	var/total_sparks = 0 // To stop it being spammed and lagging!

/datum/effect/effect/system/confetti_spread/set_up(n = 3, c = 0, loca)
	if(n > 10)
		n = 10
	number = n
	cardinals = c
	if(istype(loca, /turf/))
		rel_set(src, nameof(location), loca)
	else
		rel_set(src, nameof(location), get_turf(loca))

/datum/effect/effect/system/confetti_spread/proc/emit_one_confetti_spark()
	if(holder)
		rel_set(src, nameof(location), get_turf(holder))
	var/obj/effect/effect/sparks/confetti = new /obj/effect/effect/sparks/confetti(src.get_location())
	src.total_sparks++
	var/direction
	if(src.cardinals)
		direction = pick(GLOB.cardinal)
	else
		direction = pick(GLOB.alldirs)
	var/steps = pick(1,2,3)
	confetti.drift(direction, steps, 5)
	after(src, 2 SECONDS + steps * 0.5 SECONDS, PROC_REF(dec_confetti_sparks))

/datum/effect/effect/system/confetti_spread/proc/dec_confetti_sparks()
	src.total_sparks--

/datum/effect/effect/system/confetti_spread/start()
	var/i = 0
	for(i=0, i<src.number, i++)
		if(src.total_sparks > 20)
			return
		emit_one_confetti_spark()
