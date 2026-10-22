// The preference save system (was SScharacter_setup): queued saves are written every
// second on the background lane, parked while the queue is empty.
SYSTEM_DEF(character_setup)
	name = "Character Setup"
	periodic_runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT

	var/list/prefs_awaiting_setup = list()
	var/list/preferences_datums = list()
	var/list/newplayers_requiring_init = list()

	/// Preferences waiting to be saved, a REL_LIST view: the client owns them.
	var/list/save_queue
	/// In-flight character preview renders (owned /datum/dq_preview_poll), see preview_async.dm.
	var/list/preview_polls

CAPABILITIES(/datum/system/character_setup)
	owns_many(nameof(preview_polls))
	ref_many(nameof(save_queue))

/datum/system/character_setup/reactions()
	. = ..()
	. += every(1 SECOND, PROC_REF(save_queued), when = PROC_REF(work_ready), lane = LANE_BACKGROUND)

/// Writes the queued preference saves; parks the item when the queue is empty.
/datum/system/character_setup/proc/save_queued(dt)
	while(length(save_queue))
		var/datum/preferences/prefs = save_queue[length(save_queue)]
		rel_remove(src, nameof(save_queue), prefs)

		// Can't save prefs without client, because the sanitize functions will be
		// unable to validate their whitelist status due to being unable to check
		// 'holder' admin status, etc. Will result in Bad Times.
		if(!QDELETED(prefs) && prefs.client())
			prefs.save_preferences()

		if(KERNEL_OVER_BUDGET)
			return STEP_YIELD
	return length(save_queue) ? STEP_DONE : STEP_PARK

/datum/system/character_setup/stat_entry(msg)
	return "[..()]Save queue: [length(save_queue)]"

/// Pending saves: drained by save_queued(); deleted prefs are skipped there.
