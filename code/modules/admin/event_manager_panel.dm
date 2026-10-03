// Event Manager admin panel — structured TGUI.
//
// Two views in one window: the container list (severity timers + next
// events + running events) and a per-container "available events" list
// reached via View. The structured tgui_data mirrors both views; React
// switches on `selected_severity` being set or null.
//
// Actions act on the event service directly; every ref from the UI is
// looked up only among the service's own containers, events and metas.

/datum/event_manager_panel

// the event service forgets its manager panel.
/datum/event_manager_panel/lifecycle_dematerialize()
	if(GLOB.event_service?.tgui_event_manager_panel == src)
		rel_clear(GLOB.event_service, nameof(/datum/world_service/events::tgui_event_manager_panel))
	..()

DECLARE_UI_STATE(/datum/event_manager_panel, ADMIN_STATE(R_ADMIN|R_EVENT))

DECLARE_UI(/datum/event_manager_panel, "EventManagerPanel", UI_TITLE("Event Manager"))

/datum/event_manager_panel/tgui_close(mob/user)
	SStgui.close_uis(src)
	qdel(src)

UI_DATA_REPLACE(/datum/event_manager_panel, "merge:ui_data_datum_event_manager_panel{events_paused:bool,report_at_round_end:bool,selected_severity:unknown,selected_time_left_minutes:num,available_events:list,new_event:list,selected_container_ref:text,severities:list,next_events:list,running_events:list}")

/// The computed part of /datum/event_manager_panel's window data (declared on its UI_DATA row).
/datum/event_manager_panel/proc/ui_data_datum_event_manager_panel(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["events_paused"] = !CONFIG_GET(flag/allow_random_events)
	data["report_at_round_end"] = !!GLOB.event_service.report_at_round_end

	if(GLOB.event_service.selected_event_container())
		var/datum/event_container/EC = GLOB.event_service.selected_event_container()
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
		var/datum/event_meta/NE = GLOB.event_service.new_event
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
			var/datum/event_container/EC = GLOB.event_service.event_containers[severity]
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
				"queued_name" = EC.next_event() ? EC.next_event().name : null,
			))
		data["severities"] = severities
		data["next_events"] = next_events
		var/list/running = list()
		for(var/datum/event/E in GLOB.event_service.active_events())
			if(!E.event_meta())
				continue
			var/datum/event_meta/EM = E.event_meta()
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

/// The event containers (the service's severity containers), for the UI's container refs.
/datum/event_manager_panel/proc/event_containers()
	return GLOB.event_service.event_containers

/// The editable event metas, for the UI's meta refs: the selected container's events and the
/// draft new event.
/datum/event_manager_panel/proc/editable_metas()
	. = list()
	var/datum/event_meta/NE = GLOB.event_service.new_event
	if(NE)
		. += NE
	var/datum/event_container/EC = GLOB.event_service.selected_event_container()
	if(EC)
		. += EC.available_events

/// Every container's events, for remove_event (checked against the named container).
/datum/event_manager_panel/proc/all_available_events()
	. = list()
	for(var/datum/event_container/EC as anything in GLOB.event_service.event_containers)
		. += EC.available_events

/// The running events, for the UI's stop_event refs.
/datum/event_manager_panel/proc/active_events()
	return GLOB.event_service.active_events()

/datum/event_manager_panel/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!check_rights(R_ADMIN|R_EVENT))
		return FALSE
	return TRUE

UI_ACT(/datum/event_manager_panel, "pause_all", ui_act_pause_all)
UI_ACT_PROC(/datum/event_manager_panel, ui_act_pause_all)
	CONFIG_SET(flag/allow_random_events, !CONFIG_GET(flag/allow_random_events))
	log_and_message_admins("has [CONFIG_GET(flag/allow_random_events) ? "resumed" : "paused"] countdown for all events.", user)
	return TRUE

UI_ACT(/datum/event_manager_panel, "toggle_report", ui_act_toggle_report)
UI_ACT_PROC(/datum/event_manager_panel, ui_act_toggle_report)
	var/datum/world_service/events/service = GLOB.event_service
	service.report_at_round_end = !service.report_at_round_end
	log_and_message_admins("has [service.report_at_round_end ? "enabled" : "disabled"] the round end event report.", user)
	return TRUE

UI_ACT(/datum/event_manager_panel, "inc_timer", ui_act_inc_timer, UI_ARG_NUM("amount"), UI_ARG_REF("ref", "proc:event_containers", /datum/event_container))
UI_ACT(/datum/event_manager_panel, "dec_timer", ui_act_inc_timer, UI_ARG_NUM("amount"), UI_ARG_REF("ref", "proc:event_containers", /datum/event_container))
UI_ACT_PROC(/datum/event_manager_panel, ui_act_inc_timer)
	var/datum/event_container/EC = params["ref"]
	var/amount = params["amount"]
	if(!EC || !isnum(amount))
		return
	var/change = 60 * (10 ** clamp(round(amount), 0, 2))
	if(action == "inc_timer")
		EC.next_event_time += change
		log_and_message_admins("increased timer for [GLOB.severity_to_string[EC.severity]] events by [change/600] minute(s).", user)
	else
		EC.next_event_time -= change
		log_and_message_admins("decreased timer for [GLOB.severity_to_string[EC.severity]] events by [change/600] minute(s).", user)
	return TRUE

UI_ACT(/datum/event_manager_panel, "toggle_pause", ui_act_toggle_pause, UI_ARG_REF("ref", "proc:event_containers", /datum/event_container))
UI_ACT_PROC(/datum/event_manager_panel, ui_act_toggle_pause)
	var/datum/event_container/EC = params["ref"]
	if(!EC)
		return
	EC.delayed = !EC.delayed
	log_and_message_admins("has [EC.delayed ? "paused" : "resumed"] countdown for [GLOB.severity_to_string[EC.severity]] events.", user)
	return TRUE

UI_ACT(/datum/event_manager_panel, "set_interval", ui_act_set_interval, UI_ARG_REF("ref", "proc:event_containers", /datum/event_container))
UI_ACT_PROC(/datum/event_manager_panel, ui_act_set_interval)
	var/datum/event_container/EC = params["ref"]
	if(!EC)
		return
	var/delay = act_ask(user, action, params, ui, "interval", /datum/om/prompt/number, message = "Enter delay modifier. A value less than one means events fire more often, higher than one less often.", title = "Set Interval Modifier")
	if(!isnum(delay) || delay <= 0)
		return
	EC.delay_modifier = delay
	log_and_message_admins("has set the interval modifier for [GLOB.severity_to_string[EC.severity]] events to [EC.delay_modifier].", user)
	return TRUE

UI_ACT(/datum/event_manager_panel, "select_event", ui_act_select_event, UI_ARG_REF("ref", "proc:event_containers", /datum/event_container))
UI_ACT_PROC(/datum/event_manager_panel, ui_act_select_event)
	var/datum/event_container/EC = params["ref"]
	if(!EC)
		return
	EC.SelectEvent(user)
	return TRUE

UI_ACT(/datum/event_manager_panel, "clear_event", ui_act_clear_event, UI_ARG_REF("ref", "proc:event_containers", /datum/event_container))
UI_ACT_PROC(/datum/event_manager_panel, ui_act_clear_event)
	var/datum/event_container/EC = params["ref"]
	if(!EC)
		return
	if(EC.next_event())
		log_and_message_admins("has dequeued the [GLOB.severity_to_string[EC.severity]] event '[EC.next_event().name]'.", user)
		rel_clear(EC, nameof(/datum/event_container::next_event))
	return TRUE

UI_ACT(/datum/event_manager_panel, "view_events", ui_act_view_events, UI_ARG_REF("ref", "proc:event_containers", /datum/event_container))
UI_ACT_PROC(/datum/event_manager_panel, ui_act_view_events)
	var/datum/world_service/events/service = GLOB.event_service
	var/datum/event_container/EC = params["ref"]
	if(!EC)
		return
	rel_set(service, nameof(/datum/world_service/events::selected_event_container), EC)
	return TRUE

UI_ACT(/datum/event_manager_panel, "back", ui_act_back)
UI_ACT_PROC(/datum/event_manager_panel, ui_act_back)
	var/datum/world_service/events/service = GLOB.event_service
	rel_clear(service, nameof(/datum/world_service/events::selected_event_container))
	return TRUE

UI_ACT(/datum/event_manager_panel, "stop_event", ui_act_stop_event, UI_ARG_REF("ref", "proc:active_events", /datum/event))
UI_ACT_PROC(/datum/event_manager_panel, ui_act_stop_event)
	var/datum/event/E = params["ref"]
	if(!E)
		return
	var/answer = act_ask(user, action, params, ui, "stop", /datum/om/prompt/choice/alert, message = "Stopping an event may have unintended side-effects. Continue?", title = "Stopping Event!", choices = list("Yes","No"))
	if(answer != "Yes" || QDELETED(E))
		return
	var/datum/event_meta/EM = E.event_meta()
	log_and_message_admins("has stopped the [GLOB.severity_to_string[EM.severity]] event '[EM.name]'.", user)
	E.kill()
	return TRUE

UI_ACT(/datum/event_manager_panel, "set_name", ui_act_set_name, UI_ARG_REF("ref", "proc:editable_metas", /datum/event_meta))
UI_ACT_PROC(/datum/event_manager_panel, ui_act_set_name)
	var/datum/event_meta/EM = params["ref"]
	if(!EM)
		return
	var/name = act_ask(user, action, params, ui, "name", /datum/om/prompt/text, message = "Enter event name.", title = "Set Name", max_length = MAX_LNAME_LEN)
	if(!name)
		return
	EM.name = name
	return TRUE

UI_ACT(/datum/event_manager_panel, "set_type", ui_act_set_type, UI_ARG_REF("ref", "proc:editable_metas", /datum/event_meta))
UI_ACT_PROC(/datum/event_manager_panel, ui_act_set_type)
	var/datum/world_service/events/service = GLOB.event_service
	var/datum/event_meta/EM = params["ref"]
	if(!EM)
		return
	var/type = act_ask(user, action, params, ui, "type", /datum/om/prompt/choice, message = "Select event type.", title = "Select", choices = service.allEvents)
	if(!type)
		return
	EM.event_type = type
	return TRUE

UI_ACT(/datum/event_manager_panel, "set_weight", ui_act_set_weight, UI_ARG_REF("ref", "proc:editable_metas", /datum/event_meta))
UI_ACT_PROC(/datum/event_manager_panel, ui_act_set_weight)
	var/datum/world_service/events/service = GLOB.event_service
	var/datum/event_meta/EM = params["ref"]
	if(!EM)
		return
	var/weight = act_ask(user, action, params, ui, "weight", /datum/om/prompt/number, message = "Enter weight. A higher value means higher chance for the event of being selected.", title = "Set Weight")
	if(!isnum(weight) || weight <= 0)
		return
	EM.weight = weight
	if(EM != service.new_event)
		log_and_message_admins("has changed the weight of the [GLOB.severity_to_string[EM.severity]] event '[EM.name]' to [EM.weight].", user)
	return TRUE

UI_ACT(/datum/event_manager_panel, "toggle_oneshot", ui_act_toggle_oneshot, UI_ARG_REF("ref", "proc:editable_metas", /datum/event_meta))
UI_ACT_PROC(/datum/event_manager_panel, ui_act_toggle_oneshot)
	var/datum/world_service/events/service = GLOB.event_service
	var/datum/event_meta/EM = params["ref"]
	if(!EM)
		return
	EM.one_shot = !EM.one_shot
	if(EM != service.new_event)
		log_and_message_admins("has [EM.one_shot ? "set" : "unset"] the oneshot flag for the [GLOB.severity_to_string[EM.severity]] event '[EM.name]'.", user)
	return TRUE

UI_ACT(/datum/event_manager_panel, "toggle_enabled", ui_act_toggle_enabled, UI_ARG_REF("ref", "proc:editable_metas", /datum/event_meta))
UI_ACT_PROC(/datum/event_manager_panel, ui_act_toggle_enabled)
	var/datum/event_meta/EM = params["ref"]
	if(!EM)
		return
	EM.enabled = !EM.enabled
	log_and_message_admins("has [EM.enabled ? "enabled" : "disabled"] the [GLOB.severity_to_string[EM.severity]] event '[EM.name]'.", user)
	return TRUE

UI_ACT(/datum/event_manager_panel, "remove_event", ui_act_remove_event, UI_ARG_REF("container_ref", "proc:event_containers", /datum/event_container), UI_ARG_REF("ref", "proc:all_available_events", /datum/event_meta))
UI_ACT_PROC(/datum/event_manager_panel, ui_act_remove_event)
	var/datum/event_container/EC = params["container_ref"]
	if(!EC)
		return
	var/datum/event_meta/EM = params["ref"]
	if(!EM || !(EM in EC.available_events))
		return
	var/answer = act_ask(user, action, params, ui, "remove", /datum/om/prompt/choice/alert, message = "This will remove the event from rotation. Continue?", title = "Removing Event!", choices = list("Yes","No"))
	if(answer != "Yes")
		return
	rel_remove(EC, nameof(/datum/event_container::available_events), EM)
	log_and_message_admins("has removed the [GLOB.severity_to_string[EM.severity]] event '[EM.name]'.", user)
	return TRUE

UI_ACT(/datum/event_manager_panel, "add_event", ui_act_add_event)
UI_ACT_PROC(/datum/event_manager_panel, ui_act_add_event)
	var/datum/world_service/events/service = GLOB.event_service
	var/datum/event_container/EC = service.selected_event_container()
	var/datum/event_meta/NE = service.new_event
	if(!EC || !NE?.name || !NE.event_type)
		return
	var/answer = act_ask(user, action, params, ui, "add", /datum/om/prompt/choice/alert, message = "This will add a new event to the rotation. Continue?", title = "Add Event!", choices = list("Yes","No"))
	if(answer != "Yes" || NE != service.new_event)
		return
	NE.severity = EC.severity
	// The container adopts the drafted meta; the service starts a fresh draft below.
	own_transfer(service, nameof(/datum/world_service/events::new_event), EC, nameof(/datum/event_container::event_pool))
	rel_add(EC, nameof(/datum/event_container::available_events), NE)
	log_and_message_admins("has added \a [GLOB.severity_to_string[NE.severity]] event '[NE.name]' of type [NE.event_type] with weight [NE.weight].", user)
	own_set(service, nameof(/datum/world_service/events::new_event), new /datum/event_meta)
	return TRUE

/datum/world_service/events
	var/datum/event_manager_panel/tgui_event_manager_panel

