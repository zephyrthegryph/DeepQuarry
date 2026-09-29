/area/looking_glass
	name = "make a subtype"

	var/tmp/obj/effect/landmark/looking_glass/our_landmark
	var/list/our_turfs
	var/list/our_optional_turfs

	var/lg_id

	var/active = FALSE

/area/looking_glass/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(our_landmark), locate_within(src, /obj/effect/landmark/looking_glass))
	if(!our_landmark())
		log_mapping("Looking glass area [name] couldn't find a landmark")
	for(var/turf/simulated/floor/looking_glass/lgt in area_contents_of_type(src, /turf/simulated/floor/looking_glass))
		rel_add(src, nameof(our_turfs), lgt)
		if(lgt.optional)
			rel_add(src, nameof(our_optional_turfs), lgt)

/area/looking_glass/Entered(atom/movable/AM)
	if(isliving(AM))
		var/mob/living/L = AM
		if(L.client)
			our_landmark()?.gain_viewer(L.client)

/area/looking_glass/Exited(atom/movable/AM)
	if(isliving(AM))
		var/mob/living/L = AM
		if(L.client)
			our_landmark()?.lose_viewer(L.client)

/area/looking_glass/proc/begin_program(image/newimage)
	if(!active)
		for(var/turf/simulated/floor/looking_glass/lgt as anything in our_turfs)
			lgt.activate()

	our_landmark()?.take_image(newimage)
	active = TRUE

/area/looking_glass/proc/end_program()
	if(active)
		for(var/turf/simulated/floor/looking_glass/lgt as anything in our_turfs)
			lgt.deactivate()

	active = FALSE

	if(our_landmark())
		om_after(our_landmark(), 2 SECONDS, TYPE_PROC_REF(/obj/effect/landmark/looking_glass, drop_image))

/area/looking_glass/proc/toggle_optional(transparent)
	for(var/turf/simulated/floor/looking_glass/lgt as anything in our_optional_turfs)
		lgt.center = !transparent
		if(active)
			lgt.deactivate()
			om_after(lgt, 3 SECONDS, TYPE_PROC_REF(/turf/simulated/floor/looking_glass, activate))


/// Accessor for the our_landmark var.
/area/looking_glass/proc/our_landmark() as /obj/effect/landmark/looking_glass
	return our_landmark
