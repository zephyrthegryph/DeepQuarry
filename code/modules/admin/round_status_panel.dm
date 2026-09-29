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
	rel_set(src, "owner_admin", owner_admin)

// The admin holder owns this panel (round_status_panel); owner_admin is a plain relation back.

// The union of every action's rights below: call/recall need R_ADMIN|R_EVENT, the timer and delay actions R_SERVER.
// Each action narrows with admin_require(); the state must be at least as wide as the widest action.
/datum/round_status_panel/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN|R_EVENT|R_SERVER)

/datum/round_status_panel/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		snapshot_antag_blocks()
		ui = new(user, src, "RoundStatusPanel", "Round Status")
		ui.open()

/datum/round_status_panel/proc/snapshot_antag_blocks()
	var/list/blocks = list()
	if(GLOB.antag_service.all_antag_types)
		for(var/antag_type in GLOB.antag_service.all_antag_types)
			var/datum/antagonist/A = GLOB.antag_service.all_antag_types[antag_type]
			var/list/block = A?.get_check_antag_data(owner_admin)
			if(block)
				blocks += list(block)
	shown_antag_blocks = blocks

/datum/round_status_panel/tgui_close(mob/user)
	SStgui.close_uis(src)
	qdel(src)

/datum/round_status_panel/tgui_data(mob/user)
	var/list/data = list()
	data["mode_name"] = SSticker?.mode?.name || "(none)"
	data["round_duration"] = roundduration2text()
	data["delay_end"] = !!SSticker?.delay_end

	var/list/shuttle_data = list()
	if(!GLOB.emergency_shuttle_service.online())
		shuttle_data["state"] = SHUTTLE_STATE_IDLE
	else if(GLOB.emergency_shuttle_service.wait_for_launch)
		shuttle_data["state"] = SHUTTLE_STATE_COUNTING_DOWN
		var/timeleft = GLOB.emergency_shuttle_service.estimate_launch_time()
		shuttle_data["time_left_seconds"] = timeleft
		shuttle_data["time_left_display"] = format_shuttle_timer(timeleft)
	else if(GLOB.emergency_shuttle_service.shuttle.has_arrive_time())
		shuttle_data["state"] = SHUTTLE_STATE_ARRIVING
		var/timeleft = GLOB.emergency_shuttle_service.estimate_arrival_time()
		shuttle_data["time_left_seconds"] = timeleft
		shuttle_data["time_left_display"] = format_shuttle_timer(timeleft)
		shuttle_data["can_recall"] = GLOB.emergency_shuttle_service.can_call() || GLOB.emergency_shuttle_service.can_recall()
	else if(GLOB.emergency_shuttle_service.shuttle.moving_status == SHUTTLE_WARMUP)
		shuttle_data["state"] = SHUTTLE_STATE_WARMUP
	else
		shuttle_data["state"] = SHUTTLE_STATE_IDLE
	data["shuttle"] = shuttle_data

	data["antag_blocks"] = shown_antag_blocks || list()
	return data

/datum/round_status_panel/proc/format_shuttle_timer(seconds)
	return "[(seconds / 60) % 60]:[add_zero(num2text(seconds % 60), 2)]"

/datum/round_status_panel/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	if(!owner_admin)
		return
	switch(action)
		if("refresh_antags")
			snapshot_antag_blocks()
			SStgui.update_uis(src)
			return TRUE
		if("call_shuttle")
			if(!admin_require(ui.user.client, R_ADMIN|R_EVENT, "round_status_panel:[action]"))
				return
			if(SSticker?.mode?.name == "blob")
				tgui_alert_async(ui.user, "You can't call the shuttle during blob!")
				return
			if(!SSticker || !GLOB.emergency_shuttle_service.location())
				return
			if(GLOB.emergency_shuttle_service.can_call())
				GLOB.emergency_shuttle_service.call_evac()
				log_admin("[key_name(ui.user)] called the Emergency Shuttle")
				message_admins(span_blue("[key_name_admin(ui.user)] called the Emergency Shuttle to the station."), 1)
			SStgui.update_uis(src)
			return TRUE

		if("recall_shuttle")
			if(!admin_require(ui.user.client, R_ADMIN|R_EVENT, "round_status_panel:[action]"))
				return
			if(!SSticker || !GLOB.emergency_shuttle_service.location())
				return
			if(GLOB.emergency_shuttle_service.can_recall())
				GLOB.emergency_shuttle_service.recall()
				log_admin("[key_name(ui.user)] sent the Emergency Shuttle back")
				message_admins(span_blue("[key_name_admin(ui.user)] sent the Emergency Shuttle back."), 1)
			SStgui.update_uis(src)
			return TRUE

		if("edit_shuttle_time")
			if(!admin_require(ui.user.client, R_SERVER, "round_status_panel:[action]"))
				return
			if(GLOB.emergency_shuttle_service.wait_for_launch)
				var/new_time_left = act_ask(ui.user, action, params, ui, "a1", /datum/om/prompt/number, message = "Enter new shuttle launch countdown (seconds):", title = "Edit Shuttle Launch Time", default = GLOB.emergency_shuttle_service.estimate_launch_time())
				if(isnull(new_time_left))
					return
				if(isnum(new_time_left))
					EXPIRY_SET(GLOB.emergency_shuttle_service, launch_time, (new_time_left * 10), CLOCK_WORLD)
					log_admin("[key_name(ui.user)] edited the Emergency Shuttle's launch time to [new_time_left]")
					message_admins(span_blue("[key_name_admin(ui.user)] edited the Emergency Shuttle's launch time to [new_time_left * 10]"), 1)
			else if(GLOB.emergency_shuttle_service.shuttle.has_arrive_time())
				var/new_time_left = act_ask(ui.user, action, params, ui, "a2", /datum/om/prompt/number, message = "Enter new shuttle arrival time (seconds):", title = "Edit Shuttle Arrival Time", default = GLOB.emergency_shuttle_service.estimate_arrival_time())
				if(isnull(new_time_left))
					return
				if(isnum(new_time_left))
					EXPIRY_SET(GLOB.emergency_shuttle_service.shuttle, arrive_time, (new_time_left * 10), CLOCK_WORLD)
					log_admin("[key_name(ui.user)] edited the Emergency Shuttle's arrival time to [new_time_left]")
					message_admins(span_blue("[key_name_admin(ui.user)] edited the Emergency Shuttle's arrival time to [new_time_left * 10]"), 1)
			else
				tgui_alert_async(ui.user, "The shuttle is neither counting down to launch nor is it in transit. Please try again when it is.")
			SStgui.update_uis(src)
			return TRUE

		if("toggle_delay_end")
			if(!admin_require(ui.user.client, R_SERVER, "round_status_panel:[action]"))
				return
			SSticker.delay_end = !SSticker.delay_end
			log_admin("[key_name(ui.user)] [SSticker.delay_end ? "delayed the round end" : "has made the round end normally"].")
			message_admins(span_blue("[key_name(ui.user)] [SSticker.delay_end ? "delayed the round end" : "has made the round end normally"]."), 1)
			SStgui.update_uis(src)
			return TRUE

		// Antag-row actions: PP / PM / TP for an antagonist's mob.
		if("antag_pp")
			var/mob/M = locate(params["ref"])
			if(ismob(M) && ui.user?.client)
				SSadmin_verbs.dynamic_invoke_verb(ui.user.client, /datum/admin_verb/show_player_panel, M)
			return TRUE
		if("antag_pm")
			var/mob/M = locate(params["ref"])
			if(ismob(M) && ui.user?.client)
				ui.user.client.cmd_admin_pm(M)
			return TRUE
		if("antag_tp")
			var/mob/M = locate(params["ref"])
			if(!ismob(M))
				return TRUE
			if(!SSticker || !SSticker.mode)
				tgui_alert_async(ui.user, "The game hasn't started yet!")
				return TRUE
			if(ui.user?.client)
				SSadmin_verbs.dynamic_invoke_verb(ui.user.client, /datum/admin_verb/show_traitor_panel, M)
			return TRUE

// /datum/admins extension: each admin owns one panel datum lazily.
/datum/admins
	var/datum/round_status_panel/round_status_panel

/datum/admins/proc/open_round_status_panel(mob/user)
	if(!(SSticker && SSticker.current_state >= GAME_STATE_PLAYING))
		tgui_alert_async(user, "The game hasn't started yet!")
		return
	if(!round_status_panel)
		own_set(src, "round_status_panel", new /datum/round_status_panel(src))
	round_status_panel.tgui_interact(user)

#undef SHUTTLE_STATE_IDLE
#undef SHUTTLE_STATE_COUNTING_DOWN
#undef SHUTTLE_STATE_ARRIVING
#undef SHUTTLE_STATE_WARMUP
