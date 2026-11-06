/obj/effect/meteor_falling
	name = "meteor"
	desc = "The sky is falling!"
	icon = 'icons/obj/meteor.dmi'
	icon_state = "large"
	anchored = TRUE

CAPABILITIES(/obj/effect/meteor_falling)
	after_init(0, then(PROC_REF(start_falling)))

/obj/effect/meteor_falling/proc/start_falling(datum/act/timer/A)
	SpinAnimation()
	meteor_fall()

/obj/effect/meteor_falling/proc/meteor_fall()
	var/turf/current = get_turf(src)
	if(isopenturf(current))
		var/turf/below = GetBelow(src)
		if(!below)
			meteor_impact()
			return
		if(below.density)
			meteor_impact()
			return
		for(var/atom/movable/A in turf_contents_of_type(current, /atom/movable))
			A.ex_act(2) //Let's have it be heavy, but not devistation in case it hits walls or something.
		forceMove(below)
		meteor_fall()
		return
	meteor_impact()

/obj/effect/meteor_falling/proc/meteor_impact()
	var/turf/current = get_turf(src)
	explosion(current, -1, 2, 4, 8, 0) //Was previously 2,4,6,10. Way too big.
	anim(get_step(current,SOUTHWEST),, 'icons/effects/96x96.dmi',, "explosion")
	new /obj/structure/meteorite(current)

	var/datum/planet/impacted
	for(var/datum/planet/P in planets_planets())
		if(current.z in P.expected_z_levels)
			impacted = P
			break
	if(impacted)
		for(var/mob/living/L in REGISTRY_MEMBERS(REGISTRY_MOBS))
			if(!istype(L))
				continue
			var/turf/mob_turf = get_turf(L)
			if(!mob_turf || !(mob_turf.z in impacted.expected_z_levels))
				continue
			if(L.client)
				to_chat(L, span_danger("The ground lurches beneath you!"))
				shake_camera(L, 6, 1)
				if(!L.has_status(STAT_DEAFENED))
					L << 'sound/effects/explosionfar.ogg'
	spent(src)
