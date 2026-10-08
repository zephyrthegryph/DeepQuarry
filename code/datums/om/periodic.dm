// Legacy entry points keep existing callers on the engine-owned cadence runtime.
/proc/_om_periodic_start(datum/E, P)
	return cadence_start(E, P)

/proc/_om_periodic_stop(datum/E)
	return cadence_stop(E)

/datum/compatibility_periodic_allowed(cadence)
	return sys_periodic_allows(src, cadence) && sys_every_allows(src)

/// A mob moved into a chunk a proximity-gated sleeper watches (sleep_until_mob_near(), code/modules/mob/mob_chunks.dm): its
/// periodic work restarts on its lane.
/atom/movable/proc/proximity_woke(datum/mob_chunk/C, bits)
	if(QDELETED(src) || !proximity_chunks)
		return
	proximity_chunks = unwatch_mob_chunks(src, proximity_chunks, proximity_mask)
	om_task_periodic(src, proximity_lane)
