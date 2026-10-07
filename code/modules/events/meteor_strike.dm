/datum/event/meteor_strike
	announceWhen = 1
	var/tmp/turf/strike_target

/datum/event/meteor_strike/setup()
	startWhen = rand(8,15)
	if(LAZYLEN(using_map.meteor_strike_areas))
		rel_set(src, nameof(strike_target), pick(get_area_turfs(pick(using_map.meteor_strike_areas))))

	if(!strike_target())
		kill()

/datum/event/meteor_strike/announce()
	GLOB.command_announcement.Announce("A meteoroid has been detected entering the atmosphere on a trajectory that will terminate near the surface facilty. Brace for impact.", "NanoTrasen Orbital Monitoring")

/datum/event/meteor_strike/start()
	new /obj/effect/meteor_falling(strike_target())

/obj/effect/meteor_falling
	name = "meteor"
	desc = "The sky is falling!"
	icon = 'icons/obj/meteor.dmi'
	icon_state = "large"
	anchored = TRUE

/obj/effect/meteor_falling/Initialize(mapload)
	. = ..()
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
	for(var/datum/planet/P in SSplanets.planets)
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

/obj/structure/meteorite
	resistance_flags = BOMB_PROOF
	name = "meteorite"
	desc = "A big hunk of star-stuff."
	icon = 'icons/obj/meteor.dmi'
	icon_state = "large"
	density = TRUE

CAPABILITIES(/obj/structure/meteorite)
	climb()
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

// ALLOW(init/INSTANCE_STATE): rolls the ore or artifact this meteorite holds
/obj/structure/meteorite/Initialize(mapload)
	. = ..()
	icon = turn(icon, 90)
	switch(rand(1,100))
		if(1 to 60)
			for(var/i=1 to rand(12,36))
				new /obj/item/ore/iron(src)
		if(61 to 90)
			for(var/i=1 to rand(8,24))
				new /obj/item/ore/silver(src)
				new /obj/item/ore/gold(src)
				new /obj/item/ore/osmium(src)
				new /obj/item/ore/diamond(src)
		if(91 to 100)
			new /obj/machinery/artifact(src)

/obj/structure/meteorite/proc/break_apart_done(mob/M)
	act_message(M, src, MSG_SELF(span_warning("You break apart %T%.")), MSG_OTHERS(span_warning("%U% breaks apart %T%.")))
	for(var/obj/O in contents_of(src))
		O.forceMove(get_turf(src))
	destroyed(src, M, BRUTE)

/// Old attackby.
/obj/structure/meteorite/proc/interaction_item(datum/act/op/A)
	var/mob/M = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/pickaxe))
		var/obj/item/pickaxe/P = I
		act_message(M, src, MSG_SELF(span_warning("You start [P.drill_verb] %T%.")), MSG_OTHERS(span_warning("%U% starts [P.drill_verb] %T%.")))

		task_timed(M, P.digspeed*3, src, src, PROC_REF(break_apart_done), list(M))
		return OP_PASS
	return OP_PASS

/// Accessor for the strike_target var.
/datum/event/meteor_strike/proc/strike_target() as /turf
	return strike_target
