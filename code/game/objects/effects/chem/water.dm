/obj/effect/effect/water
	name = "water"
	icon = 'icons/effects/effects.dmi'
	icon_state = "extinguish"
	mouse_opacity = 0
	pass_flags = PASSTABLE | PASSGRILLE | PASSBLOB
	/// Steps the spray still takes towards spray_target.
	var/steps_left = 0
	/// Deciseconds between steps.
	var/step_delay = 5

/// Where the spray is heading; while set, step_process() runs every step_delay.
OM_FIELD_TYPED(/obj/effect/effect/water, turf, spray_target, null, CHANGE_EXPLICIT)
DECLARE_REF(/obj/effect/effect/water, "spray_target", STATIC, null) // a turf: the world owns it
DECLARE_REPEAT(/obj/effect/effect/water, "step_delay", step_process, "spray_target")

/obj/effect/effect/water/Initialize(mapload)
	. = ..()
	expire(15 SECONDS)

/obj/effect/effect/water/proc/set_color() // Call it after you move reagents to it
	icon += reagents.get_color()

/obj/effect/effect/water/proc/set_up(turf/target, step_count = 5, delay = 5)
	if(!target)
		return
	steps_left = step_count
	step_delay = delay
	set_spray_target(target)
	step_process()

/// Ends the spray's travel (the declared repeat stops with spray_target).
/obj/effect/effect/water/proc/stop_spray()
	set_spray_target(null)
	return REPEAT_STOP

/obj/effect/effect/water/proc/step_process()
	var/turf/target = spray_target
	if(!target)
		return REPEAT_STOP
	steps_left--
	if(!loc)
		qdel(src)
		return REPEAT_STOP
	step_towards(src, target)
	var/turf/T = get_turf(src)
	if(T && reagents)
		reagents.touch_turf(T, reagents.total_volume)
		var/mob/M
		for(var/atom/A in turf_contents_of_type(T, /atom))
			if(!ismob(A) && A.simulated) // Mobs are handled differently
				reagents.touch(A, reagents.total_volume)
			else if(ismob(A) && !M)
				M = A
		if(M)
			reagents.splash(M, reagents.total_volume)
			expire(1 SECOND)
			return stop_spray()
		if(T == get_turf(target))
			expire(1 SECOND)
			return stop_spray()

	if(steps_left > 0)
		return
	expire(1 SECOND)
	return stop_spray()

/obj/effect/effect/water/Move(turf/newloc)
	if(newloc.density)
		return 0
	. = ..()

/obj/effect/effect/water/Bump(atom/A)
	if(reagents)
		reagents.touch(A)
	return ..()

//Used by spraybottles.
/obj/effect/effect/water/chempuff
	name = "chemicals"
	icon = 'icons/obj/chempuff.dmi'
	icon_state = ""
