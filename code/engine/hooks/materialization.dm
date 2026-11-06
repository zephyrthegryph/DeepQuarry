// The world loader supplies batching and initialization delivery through this interface.
LIFECYCLE_KEEP_UNLESS_FORCED(/datum/materialization_host)
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

/// TRUE while an init frame runs: a reverse-index row made now is queued (rel_pending) and merged when the frame closes or yields.
/datum/materialization_host/proc/frame_running()
	return FALSE

/// The running frame queued one reverse-index row; `new_target`: its target had none queued yet (the frame's counters).
/datum/materialization_host/proc/frame_note_index_row(new_target)
	return

/datum/materialization_host/proc/after_init_wait(datum/holder)
	after_init_arm(holder, FALSE)
