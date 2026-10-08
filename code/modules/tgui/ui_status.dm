// A window's status is event-driven (doc/rewrite/final_api.html section 13 "ui_window()"; section 7, phase R).
//
// Interactive, update-only and closed come from the window's state (tgui_status(): the user's range to the host, consciousness, hands,
// the host being in reach). Nothing polls it: the window observes the keys that decide it and, when one is published, queues a status
// re-check for phase R (code/modules/tgui/ui_push.dm), where many changes in one tick make one check:
//
//   the user:  its location (ATOM_KEY_LOC, MOB_KEY_LOC), stat, status, hands, equipment, conditions, client, anchoring, and the
//              STAT_CAN_ACT stat (a hold that takes away the ability to act)
//   the host:  its location (ATOM_KEY_LOC, MOB_KEY_LOC), when it is a movable that is not the user (a machine carried away, a held item put down)
//
// The window also holds the host at RELEVANCE_WATCHED while it is open, so a host that parks its work by relevance keeps running for
// a window that shows it. Either end being deleted queues a check too (participant_gone()), and the check closes the window.

/// The keys of a mob that decide the status of a window it is using (filled on first use: the stat defs exist by then).
GLOBAL_LIST_EMPTY(ui_status_user_keys)

/proc/ui_status_user_keys()
	if(!length(GLOB.ui_status_user_keys))
		GLOB.ui_status_user_keys = list(ATOM_KEY_LOC, MOB_KEY_LOC, MOB_KEY_STATUS, MOB_KEY_HANDS, MOB_KEY_EQUIPMENT, MOB_KEY_CONDITIONS, MOB_KEY_CLIENT, nameof(/mob::stat), nameof(/atom/movable::anchored))
		var/datum/stat_def/can_act = stat_def_of(STAT_CAN_ACT)
		if(can_act)
			GLOB.ui_status_user_keys += can_act.stat_key
			GLOB.ui_status_user_keys += can_act.name // a stat with a var publishes under the var's name (stat recompute: changed(E, 0, name))
	return GLOB.ui_status_user_keys

/// The keys of a window's host that decide its status: it moved.
GLOBAL_LIST_INIT(ui_status_host_keys, list(ATOM_KEY_LOC, MOB_KEY_LOC))

/// The reaction the window observes its user and host with (one per window, so it can be taken back).
/datum/tgui/proc/status_trigger_for(list/keys)
	return on_change(keys, TYPE_PROC_REF(/datum/tgui, status_changed))

/// Starts watching what decides this window's status. Re-callable (a transfer to another mob): the old watches are dropped first.
/datum/tgui/proc/status_watch()
	status_unwatch()
	var/mob/watched_user = user
	if(QDELETED(src) || QDELETED(watched_user))
		return
	observe(watched_user, status_trigger_for(ui_status_user_keys()), src, TYPE_PROC_REF(/datum/tgui, status_changed))
	var/datum/owner_obj = src_object()
	var/datum/host = QDELETED(owner_obj) ? null : owner_obj.tgui_host(watched_user)
	if(host && host != watched_user && ismovable(host))
		observe(host, status_trigger_for(GLOB.ui_status_host_keys), src, TYPE_PROC_REF(/datum/tgui, status_changed))
	if(!QDELETED(owner_obj))
		hold(owner_obj, STAT_RELEVANCE, RELEVANCE_WATCHED, src)
	log_tgui(watched_user, "status watching user[host ? " and host [host]" : ""]", context = "ui_status/status_watch")

/// Stops watching: the observations on the user and the host end, and the host no longer has to be relevant for this window.
/datum/tgui/proc/status_unwatch()
	unobserve_reactions(src)
	var/datum/owner_obj = src_object()
	if(!QDELETED(owner_obj))
		release(owner_obj, STAT_RELEVANCE, src)

/// Something that decides the status changed (observe() handler, called at the drain with the source and the keys): one check in phase R.
/datum/tgui/proc/status_changed(datum/source, list/keys)
	if(closing || QDELETED(src))
		return
	ui_push_queue(src, UI_PUSH_STATUS)
