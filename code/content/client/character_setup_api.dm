// The character setup system's API (code/modules/client/preferences_save_service.dm declares the system).
//
//   SScharacter_setup.queue_preferences_save(prefs)   write `prefs` on the next save pass (use it when several preferences change at once)

/datum/system/character_setup/proc/queue_preferences_save(datum/preferences/prefs)
	if(!prefs)
		return
	rel_add(src, nameof(save_queue), prefs)
	wake_work_item(PROC_REF(save_queued))
