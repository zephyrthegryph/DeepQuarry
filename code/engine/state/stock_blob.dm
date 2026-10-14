/proc/dq_stock_blob(atom/movable/thing)
	if(!istype(thing) || QDELETED(thing) || length(thing.contents))
		return null
	if(length(state_running_blockers(thing)))
		return null
	return state_serialize(thing, STATE_FULL)
