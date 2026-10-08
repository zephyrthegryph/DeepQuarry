// The existing atoms system remains the owner of map-load batches and atom initialization.
/datum/materialization_host/map_loading()
	return SSatoms?.map_loading()

/datum/materialization_host/batch_defer(kind, atom/member)
	return SSatoms?.batch_defer(kind, member)

/datum/materialization_host/after_init_wait(datum/holder)
	SSatoms.after_init_wait(holder)
