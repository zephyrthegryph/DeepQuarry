/datum/event/blob
	announceWhen	= 12
	endWhen			= 120

	var/tmp/obj/structure/blob/core/Blob


/datum/event/blob/start()
	var/turf/T = pick(GLOB.blobstart)
	if(!T)
		kill()
		return

	rel_set(src, nameof(Blob), new /obj/structure/blob/core/random_medium(T))


/datum/event/blob/tick()
	if(!Blob() || !Blob().loc)
		rel_clear(src, nameof(Blob))
		kill()
		return

/// Accessor for the Blob var.
/datum/event/blob/proc/Blob() as /obj/structure/blob/core
	return Blob
