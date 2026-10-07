/obj/effect/effect/water
	name = "water"
	icon = 'icons/effects/effects.dmi'
	icon_state = "extinguish"
	mouse_opacity = 0
	pass_flags = PASSTABLE | PASSGRILLE | PASSBLOB
	/// Steps the spray still takes towards spray_target.
	var/steps_left = 0
	/// Actor responsible for player-directed chemical exposure.
	var/mob/spray_actor
	/// Deciseconds between steps.
	var/step_delay = 0.5 SECONDS

/// Where the spray is heading (a relation, set with spraying).
/obj/effect/effect/water/var/turf/spray_target
/// TRUE while the spray travels towards spray_target: step_process() runs every step_delay.
/obj/effect/effect/water/var/spraying = FALSE
TRACKED(/obj/effect/effect/water, spraying)

CAPABILITIES(/obj/effect/effect/water)
	ref_one(nameof(spray_target), /turf)
	every(PROC_REF(spray_delay), then(PROC_REF(step_process)), when = nameof(spraying))

/// The deciseconds between steps.
/obj/effect/effect/water/proc/spray_delay(datum/act/A)
	return step_delay

/obj/effect/effect/water/Initialize(mapload)
	. = ..()
	expire(15 SECONDS)

/obj/effect/effect/water/proc/set_color() // Call it after you move reagents to it
	icon += reagents.get_color()

/obj/effect/effect/water/proc/set_up(turf/target, step_count = 5, delay = 0.5 SECONDS, mob/user = null)
	if(!target)
		return
	rel_set(src, nameof(spray_actor), user)
	steps_left = step_count
	step_delay = delay
	rel_set(src, nameof(spray_target), target)
	set_spraying(TRUE)
	step_process()

/// Ends the spray's travel (the every() parks with spraying).
/obj/effect/effect/water/proc/stop_spray()
	rel_clear(src, nameof(spray_target))
	set_spraying(FALSE)

/obj/effect/effect/water/proc/step_process(datum/act/timer/timer)
	var/turf/target = spray_target
	if(!target)
		return
	steps_left--
	if(!loc)
		consume(src)
		return
	step_towards(src, target)
	var/turf/T = get_turf(src)
	if(T && reagents)
		reagents.touch_turf(T, reagents.total_volume)
		var/mob/M
		for(var/atom/A in turf_contents_of_type(T, /atom))
			if(!ismob(A) && A.simulated) // Mobs are handled differently
				reagents.touch(A, reagents.total_volume, spray_actor)
			else if(ismob(A) && !M)
				M = A
		if(M)
			reagents.splash(M, reagents.total_volume, user = spray_actor)
			expire(1 SECOND)
			stop_spray()
			return
		if(T == get_turf(target))
			expire(1 SECOND)
			stop_spray()
			return

	if(steps_left > 0)
		return
	expire(1 SECOND)
	stop_spray()

/obj/effect/effect/water/Move(turf/newloc)
	if(newloc.density)
		return 0
	. = ..()

/obj/effect/effect/water/Bump(atom/A)
	if(reagents)
		reagents.touch(A, user = spray_actor)
	return ..()

//Used by spraybottles.
/obj/effect/effect/water/chempuff
	name = "chemicals"
	icon = 'icons/obj/chempuff.dmi'
	icon_state = ""
