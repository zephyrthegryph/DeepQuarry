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
	if(SSevents?.tgui_event_manager_panel == src)
		rel_clear(SSevents, nameof(/datum/system/events::tgui_event_manager_panel))
	..()

CAPABILITIES(/datum/event_manager_panel)
	interface("EventManagerPanel", title = "Event Manager", rights = R_ADMIN|R_EVENT)
	op("pause_all", ui_act("pause_all"), then(PROC_REF(ui_act_pause_all)))
	op("toggle_report", ui_act("toggle_report"), then(PROC_REF(ui_act_toggle_report)))
	op("inc_timer", ui_act("inc_timer", arg("amount", num()), arg("ref", schema_ref(/datum/event_container))), then(PROC_REF(ui_act_inc_timer)))
	op("dec_timer", ui_act("dec_timer", arg("amount", num()), arg("ref", schema_ref(/datum/event_container))), then(PROC_REF(ui_act_inc_timer)))
	op("toggle_pause", ui_act("toggle_pause", arg("ref", schema_ref(/datum/event_container))), then(PROC_REF(ui_act_toggle_pause)))
	op("set_interval", ui_act("set_interval", arg("ref", schema_ref(/datum/event_container))), asks(/datum/prompt/number, fields = list("question" = "Enter delay modifier. A value less than one means events fire more often, higher than one less often.", "title" = "Set Interval Modifier", "timeout" = 0), step = "interval"), then(PROC_REF(ui_act_set_interval)))
	op("select_event", ui_act("select_event", arg("ref", schema_ref(/datum/event_container))), then(PROC_REF(ui_act_select_event)))
	op("clear_event", ui_act("clear_event", arg("ref", schema_ref(/datum/event_container))), then(PROC_REF(ui_act_clear_event)))
	op("view_events", ui_act("view_events", arg("ref", schema_ref(/datum/event_container))), then(PROC_REF(ui_act_view_events)))
	op("back", ui_act("back"), then(PROC_REF(ui_act_back)))
	op("stop_event", ui_act("stop_event", arg("ref", schema_ref(/datum/event))), asks(/datum/prompt/choice, fields = list("question" = "Stopping an event may have unintended side-effects. Continue?", "title" = "Stopping Event!", "choices" = list("Yes","No"), "buttons" = TRUE, "timeout" = 0), step = "stop"), then(PROC_REF(ui_act_stop_event)))
	op("set_name", ui_act("set_name", arg("ref", schema_ref(/datum/event_meta))), asks(/datum/prompt/text, fields = list("question" = "Enter event name.", "title" = "Set Name", "max_len" = MAX_LNAME_LEN, "timeout" = 0), step = "name"), then(PROC_REF(ui_act_set_name)))
	op("set_type", ui_act("set_type", arg("ref", schema_ref(/datum/event_meta))), asks(/datum/prompt/choice, fields = list("question" = "Select event type.", "title" = "Select", "choices" = computed(PROC_REF(ui_act_set_type_type_choices)), "timeout" = 0), step = "type"), then(PROC_REF(ui_act_set_type)))
	op("set_weight", ui_act("set_weight", arg("ref", schema_ref(/datum/event_meta))), asks(/datum/prompt/number, fields = list("question" = "Enter weight. A higher value means higher chance for the event of being selected.", "title" = "Set Weight", "timeout" = 0), step = "weight"), then(PROC_REF(ui_act_set_weight)))
	op("toggle_oneshot", ui_act("toggle_oneshot", arg("ref", schema_ref(/datum/event_meta))), then(PROC_REF(ui_act_toggle_oneshot)))
	op("toggle_enabled", ui_act("toggle_enabled", arg("ref", schema_ref(/datum/event_meta))), then(PROC_REF(ui_act_toggle_enabled)))
	op("remove_event", ui_act("remove_event", arg("container_ref", schema_ref(/datum/event_container)), arg("ref", schema_ref(/datum/event_meta))), asks(/datum/prompt/choice, fields = list("question" = "This will remove the event from rotation. Continue?", "title" = "Removing Event!", "choices" = list("Yes","No"), "buttons" = TRUE, "timeout" = 0), step = "remove"), then(PROC_REF(ui_act_remove_event)))
	op("add_event", ui_act("add_event"), asks(/datum/prompt/choice, fields = list("question" = "This will add a new event to the rotation. Continue?", "title" = "Add Event!", "choices" = list("Yes","No"), "buttons" = TRUE, "timeout" = 0), step = "add"), then(PROC_REF(ui_act_add_event)))

/datum/event_manager_panel/tgui_close(mob/user)
	SStgui.close_uis(src)
	spent(src, user)

/// /datum/event_manager_panel's window data.
/datum/event_manager_panel/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["events_paused"] = !CONFIG_GET(flag/allow_random_events)
	data["report_at_round_end"] = !!events_report_at_round_end()

	if(SSevents.selected_event_container())
		var/datum/event_container/EC = SSevents.selected_event_container()
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
		var/datum/event_meta/NE = events_new_event()
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
			var/datum/event_container/EC = events_event_containers()[severity]
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
		for(var/datum/event/E in SSevents.active_events())
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
	return events_event_containers()

/// The editable event metas, for the UI's meta refs: the selected container's events and the
/// draft new event.
/datum/event_manager_panel/proc/editable_metas()
	. = list()
	var/datum/event_meta/NE = events_new_event()
	if(NE)
		. += NE
	var/datum/event_container/EC = SSevents.selected_event_container()
	if(EC)
		. += EC.available_events

/// Every container's events, for remove_event (checked against the named container).
/datum/event_manager_panel/proc/all_available_events()
	. = list()
	for(var/datum/event_container/EC as anything in events_event_containers())
		. += EC.available_events

/// The running events, for the UI's stop_event refs.
/datum/event_manager_panel/proc/active_events()
	return SSevents.active_events()

/datum/event_manager_panel/proc/ui_gate(datum/act/op/A)
	if(!admin_can(A.actor?.client, R_ADMIN|R_EVENT))
		return FALSE
	return TRUE

/datum/event_manager_panel/proc/ui_act_pause_all(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	CONFIG_SET(flag/allow_random_events, !CONFIG_GET(flag/allow_random_events))
	log_and_message_admins("has [CONFIG_GET(flag/allow_random_events) ? "resumed" : "paused"] countdown for all events.", user)
	return TRUE

/datum/event_manager_panel/proc/ui_act_toggle_report(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/datum/system/events/service = SSevents
	service.report_at_round_end = !service.report_at_round_end
	log_and_message_admins("has [service.report_at_round_end ? "enabled" : "disabled"] the round end event report.", user)
	return TRUE

/datum/event_manager_panel/proc/ui_act_inc_timer(datum/act/op/A, amount_arg, ref)
	var/mob/user = A.actor
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	if(!isnull(ref) && !(ref in event_containers()))
		return FALSE
	var/datum/event_container/EC = ref
	var/amount = amount_arg
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

/datum/event_manager_panel/proc/ui_act_toggle_pause(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(!isnull(ref) && !(ref in event_containers()))
		return FALSE
	var/datum/event_container/EC = ref
	if(!EC)
		return
	EC.delayed = !EC.delayed
	log_and_message_admins("has [EC.delayed ? "paused" : "resumed"] countdown for [GLOB.severity_to_string[EC.severity]] events.", user)
	return TRUE

/datum/event_manager_panel/proc/ui_act_set_interval(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(!isnull(ref) && !(ref in event_containers()))
		return FALSE
	var/datum/event_container/EC = ref
	if(!EC)
		return
	var/delay = A.step_value("interval")
	if(!isnum(delay) || delay <= 0)
		return
	EC.delay_modifier = delay
	log_and_message_admins("has set the interval modifier for [GLOB.severity_to_string[EC.severity]] events to [EC.delay_modifier].", user)
	return TRUE

/datum/event_manager_panel/proc/ui_act_select_event(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(!isnull(ref) && !(ref in event_containers()))
		return FALSE
	var/datum/event_container/EC = ref
	if(!EC)
		return
	EC.SelectEvent(user)
	return TRUE

/datum/event_manager_panel/proc/ui_act_clear_event(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(!isnull(ref) && !(ref in event_containers()))
		return FALSE
	var/datum/event_container/EC = ref
	if(!EC)
		return
	if(EC.next_event())
		log_and_message_admins("has dequeued the [GLOB.severity_to_string[EC.severity]] event '[EC.next_event().name]'.", user)
		rel_clear(EC, nameof(/datum/event_container::next_event))
	return TRUE

/datum/event_manager_panel/proc/ui_act_view_events(datum/act/op/A, ref)
	if(!ui_gate(A))
		return FALSE
	if(!isnull(ref) && !(ref in event_containers()))
		return FALSE
	var/datum/system/events/service = SSevents
	var/datum/event_container/EC = ref
	if(!EC)
		return
	rel_set(service, nameof(/datum/system/events::selected_event_container), EC)
	return TRUE

/datum/event_manager_panel/proc/ui_act_back(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	var/datum/system/events/service = SSevents
	rel_clear(service, nameof(/datum/system/events::selected_event_container))
	return TRUE

/datum/event_manager_panel/proc/ui_act_stop_event(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(!isnull(ref) && !(ref in active_events()))
		return FALSE
	var/datum/event/E = ref
	if(!E)
		return
	var/answer = A.step_value("stop")
	if(answer != "Yes" || QDELETED(E))
		return
	var/datum/event_meta/EM = E.event_meta()
	log_and_message_admins("has stopped the [GLOB.severity_to_string[EM.severity]] event '[EM.name]'.", user)
	E.kill()
	return TRUE

/datum/event_manager_panel/proc/ui_act_set_name(datum/act/op/A, ref)
	if(!ui_gate(A))
		return FALSE
	if(!isnull(ref) && !(ref in editable_metas()))
		return FALSE
	var/datum/event_meta/EM = ref
	if(!EM)
		return
	var/name = A.step_value("name")
	if(!name)
		return
	EM.name = name
	return TRUE

/datum/event_manager_panel/proc/ui_act_set_type(datum/act/op/A, ref)
	if(!ui_gate(A))
		return FALSE
	if(!isnull(ref) && !(ref in editable_metas()))
		return FALSE
	var/datum/event_meta/EM = ref
	if(!EM)
		return
	var/type = A.step_value("type")
	if(!type)
		return
	EM.event_type = type
	return TRUE

/datum/event_manager_panel/proc/ui_act_set_weight(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(!isnull(ref) && !(ref in editable_metas()))
		return FALSE
	var/datum/system/events/service = SSevents
	var/datum/event_meta/EM = ref
	if(!EM)
		return
	var/weight = A.step_value("weight")
	if(!isnum(weight) || weight <= 0)
		return
	EM.weight = weight
	if(EM != service.new_event)
		log_and_message_admins("has changed the weight of the [GLOB.severity_to_string[EM.severity]] event '[EM.name]' to [EM.weight].", user)
	return TRUE

/datum/event_manager_panel/proc/ui_act_toggle_oneshot(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(!isnull(ref) && !(ref in editable_metas()))
		return FALSE
	var/datum/system/events/service = SSevents
	var/datum/event_meta/EM = ref
	if(!EM)
		return
	EM.one_shot = !EM.one_shot
	if(EM != service.new_event)
		log_and_message_admins("has [EM.one_shot ? "set" : "unset"] the oneshot flag for the [GLOB.severity_to_string[EM.severity]] event '[EM.name]'.", user)
	return TRUE

/datum/event_manager_panel/proc/ui_act_toggle_enabled(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(!isnull(ref) && !(ref in editable_metas()))
		return FALSE
	var/datum/event_meta/EM = ref
	if(!EM)
		return
	EM.enabled = !EM.enabled
	log_and_message_admins("has [EM.enabled ? "enabled" : "disabled"] the [GLOB.severity_to_string[EM.severity]] event '[EM.name]'.", user)
	return TRUE

/datum/event_manager_panel/proc/ui_act_remove_event(datum/act/op/A, container_ref, ref)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(!isnull(container_ref) && !(container_ref in event_containers()))
		return FALSE
	if(!isnull(ref) && !(ref in all_available_events()))
		return FALSE
	var/datum/event_container/EC = container_ref
	if(!EC)
		return
	var/datum/event_meta/EM = ref
	if(!EM || !(EM in EC.available_events))
		return
	var/answer = A.step_value("remove")
	if(answer != "Yes")
		return
	rel_remove(EC, nameof(/datum/event_container::available_events), EM)
	log_and_message_admins("has removed the [GLOB.severity_to_string[EM.severity]] event '[EM.name]'.", user)
	return TRUE

/datum/event_manager_panel/proc/ui_act_add_event(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/datum/system/events/service = SSevents
	var/datum/event_container/EC = service.selected_event_container()
	var/datum/event_meta/NE = service.new_event
	if(!EC || !NE?.name || !NE.event_type)
		return
	var/answer = A.step_value("add")
	if(answer != "Yes" || NE != service.new_event)
		return
	NE.severity = EC.severity
	// The container adopts the drafted meta; the service starts a fresh draft below.
	rel_move(service, nameof(/datum/system/events::new_event), EC, nameof(/datum/event_container::event_pool))
	rel_add(EC, nameof(/datum/event_container::available_events), NE)
	log_and_message_admins("has added \a [GLOB.severity_to_string[NE.severity]] event '[NE.name]' of type [NE.event_type] with weight [NE.weight].", user)
	rel_set(service, nameof(/datum/system/events::new_event), new /datum/event_meta)
	return TRUE

/datum/system/events
	var/datum/event_manager_panel/tgui_event_manager_panel

// The questions' computed fields (asks()).
/datum/event_manager_panel/proc/ui_act_set_type_type_choices(datum/act/op/A)
	var/datum/system/events/service = SSevents
	return service.allEvents
