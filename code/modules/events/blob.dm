/datum/event/blob
	announceWhen	= 12
	endWhen			= 120

	var/tmp/obj/structure/blob/core/Blob


/datum/event/blob/start()
	var/turf/T = pick(GLOB.blobstart)
	if(!T)
		kill()
		return

	rel_set(src, "Blob", new /obj/structure/blob/core/random_medium(T))


/datum/event/blob/tick()
	if(!Blob() || !Blob().loc)
		rel_clear(src, "Blob")
		kill()
		return

/// LC-refs: the Blob this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/event/blob/proc/Blob() as /obj/structure/blob/core
	return Blob
