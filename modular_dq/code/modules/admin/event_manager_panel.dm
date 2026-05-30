// Event Manager admin panel — structured TGUI.
//
// Two views in one window: the container list (severity timers + next
// events + running events) and a per-container "available events" list
// reached via View. The structured tgui_data mirrors both views; React
// switches on `selected_severity` being set or null.
//
// Actions dispatch through the existing SSevents Topic handler so the
// behaviour, validation and admin logging are identical to the legacy
// panel. SStgui.update_uis refreshes the panel after each action.

/datum/event_manager_panel

/datum/event_manager_panel/Destroy()
	if(SSevents?.tgui_event_manager_panel == src)
		SSevents.tgui_event_manager_panel = null
	return ..()

/datum/event_manager_panel/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN|R_EVENT)

/datum/event_manager_panel/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "EventManagerPanel", "Event Manager")
		ui.open()

/datum/event_manager_panel/tgui_close(mob/user)
	SStgui.close_uis(src)
	qdel(src)

/datum/event_manager_panel/tgui_data(mob/user)
	var/list/data = list()
	data["events_paused"] = !CONFIG_GET(flag/allow_random_events)
	data["report_at_round_end"] = !!SSevents.report_at_round_end

	if(SSevents.selected_event_container)
		var/datum/event_container/EC = SSevents.selected_event_container
		var/event_time = max(0, EC.next_event_time - world.time)
		data["selected_severity"] = GLOB.severity_to_string[EC.severity]
		data["selected_time_left_minutes"] = round(event_time / 600, 0.1)
		var/list/avail = list()
		var/list/active_with_role = number_active_with_role()
		for(var/datum/event_meta/EM in EC.available_events)
			avail += list(list(
				"ref" = "\ref[EM]",
				"name" = EM.name,
				"weight" = EM.weight,
				"min_weight" = EM.min_weight,
				"max_weight" = EM.max_weight,
				"one_shot" = !!EM.one_shot,
				"enabled" = !!EM.enabled,
				"current_weight" = EC.get_weight(EM, active_with_role),
			))
		data["available_events"] = avail
		var/datum/event_meta/NE = SSevents.new_event
		data["new_event"] = list(
			"ref" = "\ref[NE]",
			"name" = NE.name,
			"type" = NE.event_type ? "[NE.event_type]" : null,
			"weight" = NE.weight || 0,
			"one_shot" = !!NE.one_shot,
		)
		data["selected_container_ref"] = "\ref[EC]"
	else
		data["selected_severity"] = null
		var/list/severities = list()
		var/list/next_events = list()
		for(var/severity = EVENT_LEVEL_MUNDANE to EVENT_LEVEL_MAJOR)
			var/datum/event_container/EC = SSevents.event_containers[severity]
			var/next_event_at = max(0, EC.next_event_time - world.time)
			severities += list(list(
				"ref" = "\ref[EC]",
				"severity" = GLOB.severity_to_string[severity],
				"starts_at" = worldtime2stationtime(max(EC.next_event_time, world.time)),
				"starts_in_minutes" = round(next_event_at / 600, 0.1),
				"delayed" = !!EC.delayed,
				"delay_modifier" = EC.delay_modifier,
			))
			next_events += list(list(
				"ref" = "\ref[EC]",
				"severity" = GLOB.severity_to_string[severity],
				"queued_name" = EC.next_event ? EC.next_event.name : null,
			))
		data["severities"] = severities
		data["next_events"] = next_events
		var/list/running = list()
		for(var/datum/event/E in SSevents.active_events)
			if(!E.event_meta)
				continue
			var/datum/event_meta/EM = E.event_meta
			var/ends_at = E.startedAt + (E.lastProcessAt() * 20)
			var/ends_in = max(0, round((ends_at - world.time) / 600, 0.1))
			running += list(list(
				"ref" = "\ref[E]",
				"severity" = GLOB.severity_to_string[EM.severity],
				"name" = EM.name,
				"ends_at" = worldtime2stationtime(ends_at),
				"ends_in_minutes" = ends_in,
			))
		data["running_events"] = running
	return data

// Forwards an action to the existing SSevents Topic handler so the
// validation/logging stays in one place. Each call refreshes the panel.
/datum/event_manager_panel/proc/forward(list/href_list)
	SSevents.Topic("", href_list)
	SStgui.update_uis(src)

/datum/event_manager_panel/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	if(!check_rights(R_ADMIN|R_EVENT))
		return

	switch(action)
		if("pause_all")
			forward(list("pause_all" = "[CONFIG_GET(flag/allow_random_events) ? 0 : 1]"))
			return TRUE
		if("toggle_report")
			forward(list("toggle_report" = "1"))
			return TRUE
		if("inc_timer")
			forward(list("inc_timer" = "[params["amount"]]", "event" = "[params["ref"]]"))
			return TRUE
		if("dec_timer")
			forward(list("dec_timer" = "[params["amount"]]", "event" = "[params["ref"]]"))
			return TRUE
		if("toggle_pause")
			forward(list("pause" = "[params["ref"]]"))
			return TRUE
		if("set_interval")
			forward(list("interval" = "[params["ref"]]"))
			return TRUE
		if("select_event")
			forward(list("select_event" = "[params["ref"]]"))
			return TRUE
		if("clear_event")
			forward(list("clear" = "[params["ref"]]"))
			return TRUE
		if("view_events")
			forward(list("view_events" = "[params["ref"]]"))
			return TRUE
		if("back")
			forward(list("back" = "1"))
			return TRUE
		if("stop_event")
			forward(list("stop" = "[params["ref"]]"))
			return TRUE
		if("set_name")
			forward(list("set_name" = "[params["ref"]]"))
			return TRUE
		if("set_type")
			forward(list("set_type" = "[params["ref"]]"))
			return TRUE
		if("set_weight")
			forward(list("set_weight" = "[params["ref"]]"))
			return TRUE
		if("toggle_oneshot")
			forward(list("toggle_oneshot" = "[params["ref"]]"))
			return TRUE
		if("toggle_enabled")
			forward(list("toggle_enabled" = "[params["ref"]]"))
			return TRUE
		if("remove_event")
			forward(list("remove" = "[params["ref"]]", "EC" = "[params["container_ref"]]"))
			return TRUE
		if("add_event")
			forward(list("add" = "[params["container_ref"]]"))
			return TRUE


/datum/controller/subsystem/events
	var/datum/event_manager_panel/tgui_event_manager_panel
