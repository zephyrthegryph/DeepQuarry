// Legacy type and global spellings forward to the actual time-engine foundation.

/datum/om/rec
	parent_type = /datum/scheduler_record



/proc/om_cache_clear(datum/E, list/rules, key, bits)
	return entity_cache_clear(arglist(args))


/proc/om_attach(datum/E, B)
	return entity_attach(arglist(args))

/proc/om_detach(datum/E, B)
	return entity_detach(arglist(args))

/proc/om_attached(datum/E, B)
	return entity_attached(arglist(args))

/proc/om_park(datum/E, B)
	return entity_park(arglist(args))

/proc/om_unpark(datum/E, B)
	return entity_unpark(arglist(args))











/proc/om_wake(datum/E, B)
	return entity_wake(arglist(args))

/proc/om_watch(datum/owner, datum/target, mask, B)
	return entity_watch(arglist(args))

/proc/om_unwatch(datum/owner, datum/target, B)
	return entity_unwatch(arglist(args))

/proc/om_bulk_begin()
	return entity_bulk_begin(arglist(args))

/proc/om_bulk_end()
	return entity_bulk_end(arglist(args))






