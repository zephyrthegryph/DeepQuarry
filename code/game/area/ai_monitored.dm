/area/ai_monitored
	name = "AI Monitored Area"
	var/motioncamera_handle


/area/ai_monitored/Initialize(mapload)
	. = ..()
	// locate and store the motioncamera
	for (var/obj/machinery/camera/M in src)
		if(M.isMotion())
			motioncamera_handle = om_handle(M)
			M.area_motion_handle = om_handle(src)

/area/ai_monitored/Entered(atom/movable/O)
	..()
	if (ismob(O) && motioncamera())
		motioncamera().newTarget(O)

/area/ai_monitored/Exited(atom/movable/O)
	..()
	if (ismob(O) && motioncamera())
		motioncamera().lostTarget(O)

/// LC-refs: motioncamera -- an OM handle (om_handle()), so it reads null once that is deleted.
/area/ai_monitored/proc/motioncamera() as /obj/machinery/camera
	return om_resolve(motioncamera_handle)
