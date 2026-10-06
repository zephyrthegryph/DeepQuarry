/obj/effect/expl_particles
	name = "explosive particles"
	icon = 'icons/effects/effects.dmi'
	icon_state = "explosion_particle"
	opacity = 1
	anchored = TRUE
	mouse_opacity = 0

/obj/effect/expl_particles/Initialize(mapload)
	. = ..()
	expire(1.5 SECONDS)

/datum/effect/system/expl_particles
	var/number = 10
	var/turf/location
	var/total_particles = 0

/datum/effect/system/expl_particles/proc/set_up(n = 10, loca)
	number = n
	if(istype(loca, /turf/)) rel_set(src, nameof(location), loca)
	else rel_set(src, nameof(location), get_turf(loca))

/datum/effect/system/expl_particles/proc/emit_one_particle()
	var/obj/effect/expl_particles/expl = new /obj/effect/expl_particles(src.get_location())
	var/direct = pick(GLOB.alldirs)
	expl.drift(direct, pick(1;25,2;50,3,4;200), 1)

/datum/effect/system/expl_particles/proc/start()
	var/i = 0
	for(i=0, i<src.number, i++)
		emit_one_particle()

/obj/effect/explosion
	name = "explosive particles"
	icon = 'icons/effects/96x96.dmi'
	icon_state = "explosion"
	opacity = 1
	anchored = TRUE
	mouse_opacity = 0
	pixel_x = -32
	pixel_y = -32

/obj/effect/explosion/Initialize(mapload)
	. = ..()
	expire(1 SECOND)

/datum/effect/system/explosion
	var/turf/location

/datum/effect/system/explosion/proc/set_up(loca)
	if(istype(loca, /turf/)) rel_set(src, nameof(location), loca)
	else rel_set(src, nameof(location), get_turf(loca))

/datum/effect/system/explosion/proc/start()
	new/obj/effect/explosion( get_location() )
	var/datum/effect/system/expl_particles/P = new/datum/effect/system/expl_particles()
	P.set_up(10,get_location())
	P.start()
	after(src, 0.5 SECONDS, PROC_REF(spread_smoke))

/datum/effect/system/explosion/proc/spread_smoke()
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	var/datum/effect/effect/system/smoke_spread/S = new/datum/effect/effect/system/smoke_spread()
	S.set_up(5,0,get_location(),null)
	S.start()

/datum/effect/system/explosion/smokeless/start()
	new/obj/effect/explosion(get_location())
	var/datum/effect/system/expl_particles/P = new/datum/effect/system/expl_particles()
	P.set_up(10,get_location())
	P.start()

/// Relation view: location (reads null once it is gone).
/datum/effect/system/expl_particles/proc/get_location() as /turf
	return location

/// Relation view: location (reads null once it is gone).
/datum/effect/system/explosion/proc/get_location() as /turf
	return location
