/datum/turf_initializer/proc/InitializeTurf(turf/T)
	return

/area
	var/datum/turf_initializer/turf_initializer = null

/// Runs the area's turf initializer over its simulated turfs.
/area/area_after_init(datum/act/timer/A)
	..()
	if(turf_initializer)
		for(var/turf/simulated/T in area_contents_of_type(src, /turf/simulated))
			turf_initializer.InitializeTurf(T)

