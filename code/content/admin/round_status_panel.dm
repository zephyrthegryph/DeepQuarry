// Round Status admin panel — proper structured TGUI.
//
// Replaces the legacy `/datum/admins/proc/check_antagonists` HTML page +
// `/datum/admins/Topic` href dispatch. The DM side ships *structured*
// ui_data (shuttle state machine, round timer, delay flag, antag
// blocks) and ui_act ops handle each action natively. There are no
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

/// The window (code/content/admin/topic/admin_topic_panels.dm has the same shuttle and delay ops for the legacy hrefs). Each action keeps its
/// right: call/recall need R_ADMIN|R_EVENT, the timer and delay actions R_SERVER; the window's rights are the union.
CAPABILITIES(/datum/round_status_panel)
	ref_one(nameof(owner_admin))
	extend(TAG_UI, needs(req(PROC_REF(ui_gate), silent = TRUE)))
	interface("RoundStatusPanel", title = "Round Status", rights = R_ADMIN|R_EVENT|R_SERVER)
	op("refresh_antags", ui_act("refresh_antags"), then(PROC_REF(ui_act_refresh_antags)))
	op("call_shuttle", ui_act("call_shuttle"), needs(req_rights(R_ADMIN|R_EVENT), req(PROC_REF(shuttle_not_blob))), then(PROC_REF(ui_act_call_shuttle)))
	op("recall_shuttle", ui_act("recall_shuttle"), needs(req_rights(R_ADMIN|R_EVENT)), then(PROC_REF(ui_act_recall_shuttle)))
	op("edit_shuttle_time", ui_act("edit_shuttle_time"), needs(req_rights(R_SERVER), req(PROC_REF(shuttle_counting))), asks(/datum/prompt/number, fields = list("question" = "Enter new shuttle launch countdown (seconds):", "title" = "Edit Shuttle Launch Time", "default" = computed(PROC_REF(shuttle_launch_default)), "min_value" = 0, "timeout" = 0), step = "launch", when = PROC_REF(shuttle_is_launching)), asks(/datum/prompt/number, fields = list("question" = "Enter new shuttle arrival time (seconds):", "title" = "Edit Shuttle Arrival Time", "default" = computed(PROC_REF(shuttle_arrival_default)), "min_value" = 0, "timeout" = 0), step = "arrive", when = PROC_REF(shuttle_is_arriving)), then(PROC_REF(ui_act_edit_shuttle_time)))
	op("toggle_delay_end", ui_act("toggle_delay_end"), needs(req_rights(R_SERVER)), then(PROC_REF(ui_act_toggle_delay_end)))
	op("antag_pp", ui_act("antag_pp", arg("ref", schema_text(4096))), then(PROC_REF(ui_act_antag_pp)))
	op("antag_pm", ui_act("antag_pm", arg("ref", schema_text(4096))), then(PROC_REF(ui_act_antag_pm)))
	op("antag_tp", ui_act("antag_tp", arg("ref", schema_text(4096))), needs(req(PROC_REF(round_in_progress))), then(PROC_REF(ui_act_antag_tp)))

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
	set_shown_antag_blocks(blocks)

/datum/round_status_panel/tgui_close(mob/user)
	SStgui.close_uis(src)
	spent(src, user)

/// /datum/round_status_panel's window data.
/datum/round_status_panel/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["mode_name"] = ticker_mode()?.name || "(none)"
	data["round_duration"] = roundduration2text()
	data["delay_end"] = !!SSticker?.delay_end

	var/list/shuttle_data = list()
	if(!SSemergency_shuttle.online())
		shuttle_data["state"] = SHUTTLE_STATE_IDLE
	else if(emergency_shuttle_wait_for_launch())
		shuttle_data["state"] = SHUTTLE_STATE_COUNTING_DOWN
		var/timeleft = SSemergency_shuttle.estimate_launch_time()
		shuttle_data["time_left_seconds"] = timeleft
		shuttle_data["time_left_display"] = format_shuttle_timer(timeleft)
	else if(SSemergency_shuttle.has_arrival_countdown())
		shuttle_data["state"] = SHUTTLE_STATE_ARRIVING
		var/timeleft = SSemergency_shuttle.estimate_arrival_time()
		shuttle_data["time_left_seconds"] = timeleft
		shuttle_data["time_left_display"] = format_shuttle_timer(timeleft)
		shuttle_data["can_recall"] = SSemergency_shuttle.can_call() || SSemergency_shuttle.can_recall()
	else if(SSemergency_shuttle.is_warming_up())
		shuttle_data["state"] = SHUTTLE_STATE_WARMUP
	else
		shuttle_data["state"] = SHUTTLE_STATE_IDLE
	data["shuttle"] = shuttle_data

	data["antag_blocks"] = shown_antag_blocks || list()
	return data

/datum/round_status_panel/proc/format_shuttle_timer(seconds)
	return "[(seconds / 60) % 60]:[add_zero(num2text(seconds % 60), 2)]"

MSG_DEF_SELF(round_status/blob, "You can't call the shuttle during blob!")
MSG_DEF_SELF(round_status/not_counting, "The shuttle is neither counting down to launch nor is it in transit. Please try again when it is.")
MSG_DEF_SELF(round_status/not_started, "The game hasn't started yet!")

/// The panel works only while the admin holder it belongs to exists (an answer to nobody is dropped silently).
/datum/round_status_panel/proc/ui_gate(datum/act/op/A)
	return owner_admin ? null : /datum/msg/req_silent

/// req: no calling the shuttle during blob.
/datum/round_status_panel/proc/shuttle_not_blob(datum/act/op/A)
	return (ticker_mode()?.name == "blob") ? MSG(round_status/blob) : null

/// req: the round has a game mode running.
/datum/round_status_panel/proc/round_in_progress(datum/act/op/A)
	return (SSticker && ticker_mode()) ? null : MSG(round_status/not_started)

/// What the shuttle is counting down to: "launch", "arrive", or null while it is neither.
/datum/round_status_panel/proc/shuttle_countdown_kind()
	if(emergency_shuttle_wait_for_launch())
		return "launch"
	if(read_once(SSemergency_shuttle.has_arrival_countdown()))
		return "arrive"
	return null

/// req: the shuttle is counting down to launch or arrival.
/datum/round_status_panel/proc/shuttle_counting(datum/act/op/A)
	return shuttle_countdown_kind() ? null : MSG(round_status/not_counting)

/// when: the shuttle is counting down to launch.
/datum/round_status_panel/proc/shuttle_is_launching(datum/act/op/A)
	return shuttle_countdown_kind() == "launch"

/// when: the shuttle is in transit with an arrival time.
/datum/round_status_panel/proc/shuttle_is_arriving(datum/act/op/A)
	return shuttle_countdown_kind() == "arrive"

/datum/round_status_panel/proc/shuttle_launch_default(datum/act/op/A)
	return SSemergency_shuttle.estimate_launch_time()

/datum/round_status_panel/proc/shuttle_arrival_default(datum/act/op/A)
	return SSemergency_shuttle.estimate_arrival_time()

/datum/round_status_panel/proc/ui_act_refresh_antags(datum/act/op/A)
	snapshot_antag_blocks()
	return TRUE

/datum/round_status_panel/proc/ui_act_call_shuttle(datum/act/op/A)
	var/mob/user = A.actor
	if(!SSticker || !SSemergency_shuttle.location())
		return FALSE
	if(SSemergency_shuttle.can_call())
		SSemergency_shuttle.call_evac()
		log_and_message_admins("called the Emergency Shuttle to the station.", user)
	return TRUE

/datum/round_status_panel/proc/ui_act_recall_shuttle(datum/act/op/A)
	var/mob/user = A.actor
	if(!SSticker || !SSemergency_shuttle.location())
		return FALSE
	if(SSemergency_shuttle.can_recall())
		SSemergency_shuttle.recall()
		log_and_message_admins("sent the Emergency Shuttle back.", user)
	return TRUE

/datum/round_status_panel/proc/ui_act_edit_shuttle_time(datum/act/op/A)
	var/mob/user = A.actor
	var/kind = shuttle_countdown_kind()
	if(kind == "launch")
		var/new_time_left = A.step_value("launch")
		if(isnull(new_time_left))
			return FALSE
		SSemergency_shuttle.edit_launch_countdown(new_time_left)
		log_and_message_admins("edited the Emergency Shuttle's launch time to [new_time_left] seconds.", user)
	else if(kind == "arrive")
		var/new_time_left = A.step_value("arrive")
		if(isnull(new_time_left))
			return FALSE
		SSemergency_shuttle.edit_arrival_countdown(new_time_left)
		log_and_message_admins("edited the Emergency Shuttle's arrival time to [new_time_left] seconds.", user)
	else
		return FALSE
	return TRUE

/datum/round_status_panel/proc/ui_act_toggle_delay_end(datum/act/op/A)
	var/mob/user = A.actor
	SSticker.toggle_round_end_delay()
	log_and_message_admins("[ticker_delay_end() ? "delayed the round end" : "has made the round end normally"].", user)
	return TRUE

// Antag-row actions: PP / PM / TP for an antagonist's mob.

/datum/round_status_panel/proc/ui_act_antag_pp(datum/act/op/A, ref)
	var/mob/user = A.actor
	var/mob/M = ui_token(ref, null, /mob)
	if(M && user.client)
		SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/show_player_panel, M)
	return TRUE

/datum/round_status_panel/proc/ui_act_antag_pm(datum/act/op/A, ref)
	var/mob/user = A.actor
	var/mob/M = ui_token(ref, null, /mob)
	if(M && user.client)
		user.client.cmd_admin_pm(M)
	return TRUE

/datum/round_status_panel/proc/ui_act_antag_tp(datum/act/op/A, ref)
	var/mob/user = A.actor
	var/mob/M = ui_token(ref, null, /mob)
	if(M && user.client)
		SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/show_traitor_panel, M)
	return TRUE

// /datum/admins extension: each admin owns one panel datum lazily.
/datum/admins
	var/datum/round_status_panel/round_status_panel

/datum/admins/proc/open_round_status_panel(mob/user)
	if(!(SSticker && round_game_state() >= GAME_STATE_PLAYING))
		tgui_alert_async(user, "The game hasn't started yet!")
		return
	if(!round_status_panel)
		rel_set(src, nameof(round_status_panel), new /datum/round_status_panel(src))
	round_status_panel.tgui_interact(user)

#undef SHUTTLE_STATE_IDLE
#undef SHUTTLE_STATE_COUNTING_DOWN
#undef SHUTTLE_STATE_ARRIVING
#undef SHUTTLE_STATE_WARMUP
