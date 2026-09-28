/datum/event/blob
	announceWhen	= 12
	endWhen			= 120

	var/tmp/Blob_handle


/datum/event/blob/start()
	var/turf/T = pick(GLOB.blobstart)
	if(!T)
		kill()
		return

	Blob_handle = om_handle(new /obj/structure/blob/core/random_medium(T))


/datum/event/blob/tick()
	if(!Blob() || !Blob().loc)
		Blob_handle = null
		kill()
		return

/// LC-refs: the Blob this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/event/blob/proc/Blob() as /obj/structure/blob/core
	return om_resolve(Blob_handle)
