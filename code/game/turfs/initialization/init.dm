/datum/turf_initializer/proc/InitializeTurf(turf/T)
	return

/area
	var/datum/turf_initializer/turf_initializer = null

/area/LateInitialize()
	. = ..()
	if(turf_initializer)
		for(var/turf/simulated/T in area_contents_of_type(src, /turf/simulated))
			turf_initializer.InitializeTurf(T)

REF_OWNED(/area, list("turf_initializer"))
