// The world loader supplies batching and initialization delivery through this interface.
/datum/materialization_host

GLOBAL_DATUM(materialization_host, /datum/materialization_host)

/proc/materialization_host()
	RETURN_TYPE(/datum/materialization_host)
	if(!GLOB.materialization_host)
		GLOB.materialization_host = new /datum/materialization_host
	return GLOB.materialization_host

/datum/materialization_host/proc/map_loading()
	return FALSE

/datum/materialization_host/proc/batch_defer(kind, atom/member)
	return FALSE

/datum/materialization_host/proc/after_init_wait(datum/holder)
	after_init_arm(holder, FALSE)
