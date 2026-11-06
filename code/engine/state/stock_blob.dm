/// The state blob a stocked item would be counted as in a stock record, or null when it must stay a real item: it holds nothing, runs nothing (processing,
/// a pending timer) and its state serializes.
/proc/dq_stock_blob(atom/movable/thing)
	if(!istype(thing) || QDELETED(thing) || length(thing.contents))
		return null
	if(thing.datum_flags & DF_ISPROCESSING)
		return null
	var/datum/scheduler_record/rec = thing.sched_rec
	if(length(rec?.timers) || length(rec?.timer_keys))
		return null
	return state_serialize(thing, STATE_FULL)
