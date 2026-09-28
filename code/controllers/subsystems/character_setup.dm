SUBSYSTEM_DEF(character_setup)
	name = "Character Setup"
	flags = SS_NO_INIT | SS_NO_FIRE // save queue: /datum/om/behaviour/world/feature/character_setup

	var/list/prefs_awaiting_setup = list()
	var/list/preferences_datums = list()
	var/list/newplayers_requiring_init = list()

	var/list/save_queue = list()
/*
/datum/controller/subsystem/character_setup/Initialize()
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
/datum/controller/subsystem/character_setup/lane_step(resumed)
	while(length(save_queue))
		var/datum/preferences/prefs = save_queue[length(save_queue)]
		save_queue.len--

		// Can't save prefs without client, because the sanitize functions will be
		// unable to validate their whitelist status due to being unable to check
		// 'holder' admin status, etc. Will result in Bad Times.
		if(!QDELETED(prefs) && prefs.client())
			prefs.save_preferences()

		if(TICK_CHECK)
			return FALSE
	return TRUE

/datum/controller/subsystem/character_setup/proc/queue_preferences_save(datum/preferences/prefs)
	if(!prefs)
		return
	save_queue |= prefs
