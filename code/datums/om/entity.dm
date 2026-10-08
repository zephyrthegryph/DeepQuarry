// Legacy type and global spellings forward to the actual time-engine foundation.

/datum/om/rec
	parent_type = /datum/scheduler_record

/proc/om_rec_of(datum/E)
	return scheduler_record_of(arglist(args))

/proc/om_cache_scan(datum/om/type_table/T, datum/E)
	return entity_cache_scan(arglist(args))

/proc/om_cache_clear(datum/E, list/rules, key, bits)
	return entity_cache_clear(arglist(args))

/proc/om_start(datum/E)
	return entity_start(arglist(args))

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

/proc/om_sync(datum/om/rec/rec, i, recheck)
	return entity_sync(arglist(args))

/proc/om_stop_behaviour(datum/om/rec/rec, i)
	return entity_stop_behaviour(arglist(args))

/proc/om_requires_pass(datum/E, datum/om/behaviour/B)
	return entity_requires_pass(arglist(args))

/proc/om_suspended(datum/om/rec/rec)
	return entity_suspended(arglist(args))

/proc/om_sync_all(datum/om/rec/rec, recheck = FALSE)
	return entity_sync_all(arglist(args))

/proc/om_recompute_listen(datum/om/rec/rec)
	return entity_recompute_listen(arglist(args))

/proc/om_observed_mask(datum/om/rec/rec)
	return entity_observed_mask(arglist(args))

/proc/om_raise_change(datum/E, bits, force_refresh = FALSE)
	return entity_raise_change(arglist(args))

/proc/om_dispatch_change(datum/E, bits)
	return entity_dispatch_change(arglist(args))

/proc/om_wake_id(datum/E, bid, bits)
	return entity_wake_id(arglist(args))

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

/proc/om_teardown_links(datum/E)
	return entity_teardown_links(arglist(args))

/proc/om_behaviours_on_destroy(datum/E)
	return entity_behaviours_on_destroy(arglist(args))

/proc/om_teardown_rest(datum/E)
	return entity_teardown_rest(arglist(args))

/proc/om_type_has_decl(path)
	return entity_type_has_decl(arglist(args))

/proc/om_slot_entered(atom/holder, atom/movable/thing, datum/om/relation/slot/def)
	return entity_slot_entered(arglist(args))

/proc/om_slot_left(atom/holder, atom/movable/thing, datum/om/relation/slot/def)
	return entity_slot_left(arglist(args))
