/area/looking_glass
	name = "make a subtype"

	var/obj/effect/landmark/looking_glass/our_landmark
	var/list/our_turfs
	var/list/our_optional_turfs

	var/lg_id

	var/active = FALSE

/area/looking_glass/Initialize(mapload)
	. = ..()
	our_landmark = locate() in src
	if(!our_landmark)
		log_mapping("Looking glass area [name] couldn't find a landmark")
	for(var/turf/simulated/floor/looking_glass/lgt in src)
		LAZYADD(our_turfs, lgt)
		if(lgt.optional)
			LAZYADD(our_optional_turfs, lgt)

/area/looking_glass/Destroy()
	our_landmark = null
	LAZYCLEARLIST(our_turfs)
	return ..()

/area/looking_glass/Entered(atom/movable/AM)
	if(isliving(AM))
		var/mob/living/L = AM
		if(L.client)
			our_landmark?.gain_viewer(L.client)

/area/looking_glass/Exited(atom/movable/AM)
	if(isliving(AM))
		var/mob/living/L = AM
		if(L.client)
			our_landmark?.lose_viewer(L.client)

/area/looking_glass/proc/begin_program(image/newimage)
	if(!active)
		for(var/turf/simulated/floor/looking_glass/lgt as anything in our_turfs)
			lgt.activate()

	our_landmark?.take_image(newimage)
	active = TRUE

/area/looking_glass/proc/end_program()
	if(active)
		for(var/turf/simulated/floor/looking_glass/lgt as anything in our_turfs)
			lgt.deactivate()

	active = FALSE

	spawn(2 SECONDS)
		our_landmark?.drop_image()

/area/looking_glass/proc/toggle_optional(transparent)
	for(var/turf/simulated/floor/looking_glass/lgt as anything in our_optional_turfs)
		lgt.center = !transparent
		if(active)
			lgt.deactivate()
			spawn(3 SECONDS)
				lgt.activate()

