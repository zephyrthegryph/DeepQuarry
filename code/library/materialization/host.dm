// The existing atoms system remains the owner of map-load batches and atom initialization.
/datum/materialization_host/map_loading()
	return SSatoms?.map_loading()

/datum/materialization_host/batch_defer(kind, atom/member)
	return SSatoms?.batch_defer(kind, member)

/datum/materialization_host/frame_running()
	return !isnull(SSatoms?.active_batch)

/datum/materialization_host/frame_note_index_row(new_target)
	var/datum/materialize_batch/batch = SSatoms?.active_batch
	if(!batch)
		return
	batch.owner.rel_index_queued++
	if(new_target)
		batch.owner.rel_index_targets++

/datum/materialization_host/frame_note_stat_deferred(new_target)
	var/datum/materialize_batch/batch = SSatoms?.active_batch
	if(!batch)
		return
	batch.owner.stat_settles_queued++
	if(new_target)
		batch.owner.stat_settle_targets++

/datum/materialization_host/after_init_wait(datum/holder)
	SSatoms.after_init_wait(holder)
