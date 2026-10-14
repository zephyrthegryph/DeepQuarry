/// Debug sort retains its original effect on the owner's table iteration order.
/datum/system/garbage/proc/deletion_types(sorted_by_time = FALSE)
	if(sorted_by_time)
		sortTim(items, cmp = GLOBAL_PROC_REF(cmp_qdel_item_time), associative = TRUE)
	var/list/types = list()
	for(var/type in items)
		types += type
	return types

/datum/system/garbage/proc/deletion_statistics(type)
	return items[type]

/datum/system/garbage/proc/set_collection_enabled(enabled)
	can_fire = enabled

/datum/system/garbage/proc/queue_contains_reference(candidate)
	for(var/list/queue in queues)
		if(candidate in queue)
			return TRUE
	return FALSE

/datum/system/garbage/proc/find_failed_references_enabled()
#ifdef REFERENCE_TRACKING
	return find_reference_on_fail_global_toggle
#else
	return FALSE
#endif

/datum/system/garbage/proc/set_reference_capture(enabled)
#ifdef REFERENCE_TRACKING_DEBUG
	should_save_refs = enabled
#endif

/datum/system/garbage/proc/reference_capture_enabled()
#ifdef REFERENCE_TRACKING_DEBUG
	return should_save_refs
#else
	return FALSE
#endif
