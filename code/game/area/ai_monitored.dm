/area/ai_monitored
	name = "AI Monitored Area"
	var/obj/machinery/camera/motioncamera


/area/ai_monitored/Initialize(mapload)
	. = ..()
	// locate and store the motioncamera
	for (var/obj/machinery/camera/M in area_contents_of_type(src, /obj/machinery/camera))
		if(M.isMotion())
			rel_set(src, nameof(motioncamera), M)
			rel_set(M, nameof(M.area_motion), src)

/area/ai_monitored/Entered(atom/movable/O)
	..()
	if (ismob(O) && motioncamera())
		motioncamera().newTarget(O)

/area/ai_monitored/Exited(atom/movable/O)
	..()
	if (ismob(O) && motioncamera())
		motioncamera().lostTarget(O)

/// Motioncamera (a relation view).
/area/ai_monitored/proc/motioncamera() as /obj/machinery/camera
	return motioncamera
