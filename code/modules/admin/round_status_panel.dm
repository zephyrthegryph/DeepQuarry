// Round Status admin panel — proper structured TGUI.
//
// Replaces the legacy `/datum/admins/proc/check_antagonists` HTML page +
// `/datum/admins/Topic` href dispatch. The DM side ships *structured*
// tgui_data (shuttle state machine, round timer, delay flag, antag
// blocks) and tgui_act handles each action natively. There are no
// embedded byond:// hrefs; clicks become structured `act()` calls.
//
// This is the architectural exemplar for the rest of the admin panels
// currently rendering raw HTML through /datum/html_viewer. Each of
// those should eventually look like this file.

#define SHUTTLE_STATE_IDLE          "idle"
#define SHUTTLE_STATE_COUNTING_DOWN "counting_down"
#define SHUTTLE_STATE_ARRIVING      "arriving"
#define SHUTTLE_STATE_WARMUP        "warmup"

/datum/round_status_panel
	var/datum/admins/owner_admin
	var/list/shown_antag_blocks

/datum/round_status_panel/New(datum/admins/owner_admin)
	..()
	rel_set(src, nameof(owner_admin), owner_admin)

// The admin holder owns this panel (round_status_panel); owner_admin is a plain relation back.

// Foundation UI (doc/rewrite/operations_and_actions.md "UI"): tgui_id opens the window, ui_rights is the union of every
// action's rights (call/recall need R_ADMIN|R_EVENT, the timer and delay actions R_SERVER) and each action narrows with
// admin_require(). Nothing here pushes the window by hand: an act_<x>() that returns TRUE updates it.
/datum/round_status_panel
	tgui_id = "RoundStatusPanel"
	ui_rights = R_ADMIN | R_EVENT | R_SERVER

/datum/round_status_panel/ui_title(mob/user)
	return "Round Status"

/datum/round_status_panel/ui_opening(mob/user, datum/tgui/ui)
	snapshot_antag_blocks()

/datum/round_status_panel/proc/snapshot_antag_blocks()
	var/list/blocks = list()
	if(antag_all_antag_types())
		for(var/antag_type in antag_all_antag_types())
			var/datum/antagonist/A = antag_all_antag_types()[antag_type]
			var/list/block = A?.get_check_antag_data(owner_admin)
			if(block)
				blocks += list(block)
	shown_antag_blocks = blocks

/datum/round_status_panel/tgui_close(mob/user)
	SStgui.close_uis(src)
	spent(src, user)

// ALLOW(sys_tgui_data_override): the foundation UI form: a tgui_data override on purpose, like the APC and the vendor
/datum/round_status_panel/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	.["mode_name"] = SSticker?.mode?.name || "(none)"
	.["round_duration"] = roundduration2text()
	.["delay_end"] = !!SSticker?.delay_end

	var/list/shuttle_data = list()
	if(!SSemergency_shuttle.online())
		shuttle_data["state"] = SHUTTLE_STATE_IDLE
	else if(emergency_shuttle_wait_for_launch())
		shuttle_data["state"] = SHUTTLE_STATE_COUNTING_DOWN
		var/timeleft = SSemergency_shuttle.estimate_launch_time()
		shuttle_data["time_left_seconds"] = timeleft
		shuttle_data["time_left_display"] = format_shuttle_timer(timeleft)
	else if(SSemergency_shuttle.shuttle.has_arrive_time())
		shuttle_data["state"] = SHUTTLE_STATE_ARRIVING
		var/timeleft = SSemergency_shuttle.estimate_arrival_time()
		shuttle_data["time_left_seconds"] = timeleft
		shuttle_data["time_left_display"] = format_shuttle_timer(timeleft)
		shuttle_data["can_recall"] = SSemergency_shuttle.can_call() || SSemergency_shuttle.can_recall()
	else if(SSemergency_shuttle.shuttle.moving_status == SHUTTLE_WARMUP)
		shuttle_data["state"] = SHUTTLE_STATE_WARMUP
	else
		shuttle_data["state"] = SHUTTLE_STATE_IDLE
	.["shuttle"] = shuttle_data

	.["antag_blocks"] = shown_antag_blocks || list()

/datum/round_status_panel/proc/format_shuttle_timer(seconds)
	return "[(seconds / 60) % 60]:[add_zero(num2text(seconds % 60), 2)]"

/// The panel works only while the admin holder it belongs to exists.
/datum/round_status_panel/ui_allowed(mob/user, action)
	return !!owner_admin

/datum/round_status_panel/proc/act_refresh_antags(mob/user)
	snapshot_antag_blocks()
	return TRUE

/datum/round_status_panel/proc/act_call_shuttle(mob/user)
	if(!admin_require(user.client, R_ADMIN|R_EVENT, "round_status_panel:call_shuttle"))
		return FALSE
	if(SSticker?.mode?.name == "blob")
		return refuse(user, "You can't call the shuttle during blob!")
	if(!SSticker || !SSemergency_shuttle.location())
		return FALSE
	if(SSemergency_shuttle.can_call())
		SSemergency_shuttle.call_evac()
		// ALLOW(sys_dx_manual_fingerprint_log): the admin broadcast names the outcome; the dispatcher records only the action, and on every TRUE return
		log_and_message_admins("called the Emergency Shuttle to the station.", user)
	return TRUE

/datum/round_status_panel/proc/act_recall_shuttle(mob/user)
	if(!admin_require(user.client, R_ADMIN|R_EVENT, "round_status_panel:recall_shuttle"))
		return FALSE
	if(!SSticker || !SSemergency_shuttle.location())
		return FALSE
	if(SSemergency_shuttle.can_recall())
		SSemergency_shuttle.recall()
		// ALLOW(sys_dx_manual_fingerprint_log): the admin broadcast names the outcome; the dispatcher records only the action, and on every TRUE return
		log_and_message_admins("sent the Emergency Shuttle back.", user)
	return TRUE

/datum/round_status_panel/proc/act_edit_shuttle_time(mob/user)
	if(!admin_require(user.client, R_SERVER, "round_status_panel:edit_shuttle_time"))
		return FALSE
	if(emergency_shuttle_wait_for_launch())
		var/new_time_left = ask_number(user, "Enter new shuttle launch countdown (seconds):", 0, INFINITY, "Edit Shuttle Launch Time", SSemergency_shuttle.estimate_launch_time())
		if(isnull(new_time_left))
			return FALSE
		EXPIRY_SET(SSemergency_shuttle, launch_time, (new_time_left * 10), CLOCK_WORLD)
		// ALLOW(sys_dx_manual_fingerprint_log): the admin broadcast names the outcome; the dispatcher records only the action, and on every TRUE return
		log_and_message_admins("edited the Emergency Shuttle's launch time to [new_time_left] seconds.", user)
	else if(SSemergency_shuttle.shuttle.has_arrive_time())
		var/new_time_left = ask_number(user, "Enter new shuttle arrival time (seconds):", 0, INFINITY, "Edit Shuttle Arrival Time", SSemergency_shuttle.estimate_arrival_time())
		if(isnull(new_time_left))
			return FALSE
		EXPIRY_SET(SSemergency_shuttle.shuttle, arrive_time, (new_time_left * 10), CLOCK_WORLD)
		// ALLOW(sys_dx_manual_fingerprint_log): the admin broadcast names the outcome; the dispatcher records only the action, and on every TRUE return
		log_and_message_admins("edited the Emergency Shuttle's arrival time to [new_time_left] seconds.", user)
	else
		return refuse(user, "The shuttle is neither counting down to launch nor is it in transit. Please try again when it is.")
	return TRUE

/datum/round_status_panel/proc/act_toggle_delay_end(mob/user)
	if(!admin_require(user.client, R_SERVER, "round_status_panel:toggle_delay_end"))
		return FALSE
	SSticker.delay_end = !ticker_delay_end()
	// ALLOW(sys_dx_manual_fingerprint_log): the admin broadcast names the outcome; the dispatcher records only the action, and on every TRUE return
	log_and_message_admins("[ticker_delay_end() ? "delayed the round end" : "has made the round end normally"].", user)
	return TRUE

// Antag-row actions: PP / PM / TP for an antagonist's mob.

/datum/round_status_panel/proc/act_antag_pp(mob/user, ref)
	var/mob/M = ui_ref(ref, null, /mob)
	if(M && user.client)
		SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/show_player_panel, M)
	return TRUE

/datum/round_status_panel/proc/act_antag_pm(mob/user, ref)
	var/mob/M = ui_ref(ref, null, /mob)
	if(M && user.client)
		user.client.cmd_admin_pm(M)
	return TRUE

/datum/round_status_panel/proc/act_antag_tp(mob/user, ref)
	var/mob/M = ui_ref(ref, null, /mob)
	if(!M)
		return TRUE
	if(!SSticker || !ticker_mode())
		return refuse(user, "The game hasn't started yet!")
	if(user.client)
		SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/show_traitor_panel, M)
	return TRUE

// /datum/admins extension: each admin owns one panel datum lazily.
/datum/admins
	var/datum/round_status_panel/round_status_panel

/datum/admins/proc/open_round_status_panel(mob/user)
	if(!(SSticker && SSticker.current_state >= GAME_STATE_PLAYING))
		tgui_alert_async(user, "The game hasn't started yet!")
		return
	if(!round_status_panel)
		rel_set(src, nameof(round_status_panel), new /datum/round_status_panel(src))
	round_status_panel.tgui_interact(user)

#undef SHUTTLE_STATE_IDLE
#undef SHUTTLE_STATE_COUNTING_DOWN
#undef SHUTTLE_STATE_ARRIVING
#undef SHUTTLE_STATE_WARMUP
