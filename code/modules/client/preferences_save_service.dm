// The preference save world service (was SScharacter_setup): queued saves are written every
// second on the background lane, parked while the queue is empty.
GLOBAL_DATUM_INIT(character_setup_service, /datum/world_service/character_setup, new)

/datum/world_service/character_setup
	name = "Character Setup"
	lane = /datum/om/behaviour/world/character_setup
	on_demand = TRUE

	var/list/prefs_awaiting_setup = list()
	var/list/preferences_datums = list()
	var/list/newplayers_requiring_init = list()

	/// Preferences waiting to be saved, as a weak list (REF_WEAK_LIST): the client owns them.
	var/list/save_queue
/*
/datum/world_service/character_setup/Initialize()
	while(length(prefs_awaiting_setup))
		var/datum/preferences/prefs = prefs_awaiting_setup[length(prefs_awaiting_setup)]
		prefs_awaiting_setup.len--
		prefs.setup()
	while(length(newplayers_requiring_init))
		var/mob/new_player/new_player = newplayers_requiring_init[length(newplayers_requiring_init)]
		newplayers_requiring_init.len--
		new_player.deferred_login()
	. = ..()
*/	//Might be useful if we ever switch to Bay prefs.
/datum/world_service/character_setup/service_step(resumed)
	while(length(save_queue))
		var/datum/preferences/prefs = om_resolve(save_queue[length(save_queue)])
		save_queue.len--

		// Can't save prefs without client, because the sanitize functions will be
		// unable to validate their whitelist status due to being unable to check
		// 'holder' admin status, etc. Will result in Bad Times.
		if(!QDELETED(prefs) && prefs.client())
			prefs.save_preferences()

		if(TICK_CHECK)
			return FALSE
	return TRUE

/datum/world_service/character_setup/proc/queue_preferences_save(datum/preferences/prefs)
	if(!prefs)
		return
	WEAK_LIST_ADD(save_queue, prefs)
	demand()

/datum/world_service/character_setup/has_work()
	return length(save_queue)

/datum/world_service/character_setup/stat_line()
	return "Save queue: [length(save_queue)]"

/// preference saves
/datum/om/behaviour/world/character_setup
	name = "world: preference saves"
	every = 1 SECOND
	lane = LANE_BACKGROUND
	runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT

/datum/om/behaviour/world/character_setup/service()
	return GLOB.character_setup_service

/// Pending saves: drained by service_step(); deleted prefs are skipped there.
REF_WEAK_LIST(/datum/world_service/character_setup, "save_queue")
