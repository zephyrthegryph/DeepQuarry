//The UI portion. Should probably be made its own thing/made into a NanoUI thing later.
/datum/world_service/events
	var/window_x = 700
	var/window_y = 600
	var/report_at_round_end = 0
	var/table_options = " align='center'"
	var/row_options1 = " width='85px'"
	var/row_options2 = " width='260px'"
	var/row_options3 = " width='150px'"
	var/tmp/datum/event_container/selected_event_container

/datum/world_service/events/proc/Interact(mob/living/user)
	// structured TGUI Event Manager panel (see
	// code/modules/admin/event_manager_panel.dm). Re-uses
	// the per-subsystem panel datum so the Topic-handler fall-through
	// refresh (`Interact(usr)`) just updates the open window via
	// SStgui.update_uis instead of opening a duplicate.
	if(!tgui_event_manager_panel)
		own_set(src, "tgui_event_manager_panel", new /datum/event_manager_panel)
	tgui_event_manager_panel.tgui_interact(user)
	SStgui.update_uis(tgui_event_manager_panel)

/datum/world_service/events/proc/GetInteractWindow()
	var/html = "<A align='right' href='byond://?src=\ref[src];refresh=1'>Refresh</A>"
	html += "<A align='right' href='byond://?src=\ref[src];pause_all=[!CONFIG_GET(flag/allow_random_events)]'>Pause All - [CONFIG_GET(flag/allow_random_events) ? "Pause" : "Resume"]</A>"

	if(selected_event_container())
		var/event_time = max(0, selected_event_container().next_event_time - world.time)
		html += "<A align='right' href='byond://?src=\ref[src];back=1'>Back</A><br>"
		html += "Time till start: [round(event_time / 600, 0.1)]<br>"
		html += "<div class='block'>"
		html += "<h2>Available [GLOB.severity_to_string[selected_event_container().severity]] Events (queued & running events will not be displayed)</h2>"
		html += "<table[table_options]>"
		html += "<tr><td[row_options2]>Name </td><td>Weight </td><td>MinWeight </td><td>MaxWeight </td><td>OneShot </td><td>Enabled </td><td>" + span_alert("CurrWeight") + " </td><td>Remove</td></tr>"
		var/list/active_with_role = number_active_with_role()
		for(var/datum/event_meta/EM in selected_event_container().available_events)
			html += "<tr>"
			html += "<td>[EM.name]</td>"
			html += "<td><A align='right' href='byond://?src=\ref[src];set_weight=\ref[EM]'>[EM.weight]</A></td>"
			html += "<td>[EM.min_weight]</td>"
			html += "<td>[EM.max_weight]</td>"
			html += "<td><A align='right' href='byond://?src=\ref[src];toggle_oneshot=\ref[EM]'>[EM.one_shot]</A></td>"
			html += "<td><A align='right' href='byond://?src=\ref[src];toggle_enabled=\ref[EM]'>[EM.enabled]</A></td>"
			html += "<td>" + span_alert("[selected_event_container().get_weight(EM, active_with_role)]") + "</td>"
			html += "<td><A align='right' href='byond://?src=\ref[src];remove=\ref[EM];EC=\ref[selected_event_container()]'>Remove</A></td>"
			html += "</tr>"
		html += "</table>"
		html += "</div>"

		html += "<div class='block'>"
		html += "<h2>Add Event</h2>"
		html += "<table[table_options]>"
		html += "<tr><td[row_options2]>Name</td><td[row_options2]>Type</td><td[row_options1]>Weight</td><td[row_options1]>OneShot</td></tr>"
		html += "<tr>"
		html += "<td><A align='right' href='byond://?src=\ref[src];set_name=\ref[new_event]'>[new_event.name ? new_event.name : "Enter Event"]</A></td>"
		html += "<td><A align='right' href='byond://?src=\ref[src];set_type=\ref[new_event]'>[new_event.event_type ? new_event.event_type : "Select Type"]</A></td>"
		html += "<td><A align='right' href='byond://?src=\ref[src];set_weight=\ref[new_event]'>[new_event.weight ? new_event.weight : 0]</A></td>"
		html += "<td><A align='right' href='byond://?src=\ref[src];toggle_oneshot=\ref[new_event]'>[new_event.one_shot]</A></td>"
		html += "</tr>"
		html += "</table>"
		html += "<A align='right' href='byond://?src=\ref[src];add=\ref[selected_event_container()]'>Add</A><br>"
		html += "</div>"
	else
		html += "<A align='right' href='byond://?src=\ref[src];toggle_report=1'>Round End Report: [report_at_round_end ? "On": "Off"]</A><br>"
		html += "<div class='block'>"
		html += "<h2>Event Start</h2>"

		html += "<table[table_options]>"
		html += "<tr><td[row_options1]>Severity</td><td[row_options1]>Starts At</td><td[row_options1]>Starts In</td><td[row_options3]>Adjust Start</td><td[row_options1]>Pause</td><td[row_options1]>Interval Mod</td></tr>"
		for(var/severity = EVENT_LEVEL_MUNDANE to EVENT_LEVEL_MAJOR)
			var/datum/event_container/EC = event_containers[severity]
			var/next_event_at = max(0, EC.next_event_time - world.time)
			html += "<tr>"
			html += "<td>[GLOB.severity_to_string[severity]]</td>"
			html += "<td>[worldtime2stationtime(max(EC.next_event_time, world.time))]</td>"
			html += "<td>[round(next_event_at / 600, 0.1)]</td>"
			html += "<td>"
			html +=   "<A align='right' href='byond://?src=\ref[src];dec_timer=2;event=\ref[EC]'>--</A>"
			html +=   "<A align='right' href='byond://?src=\ref[src];dec_timer=1;event=\ref[EC]'>-</A>"
			html +=   "<A align='right' href='byond://?src=\ref[src];inc_timer=1;event=\ref[EC]'>+</A>"
			html +=   "<A align='right' href='byond://?src=\ref[src];inc_timer=2;event=\ref[EC]'>++</A>"
			html += "</td>"
			html += "<td>"
			html +=   "<A align='right' href='byond://?src=\ref[src];pause=\ref[EC]'>[EC.delayed ? "Resume" : "Pause"]</A>"
			html += "</td>"
			html += "<td>"
			html +=   "<A align='right' href='byond://?src=\ref[src];interval=\ref[EC]'>[EC.delay_modifier]</A>"
			html += "</td>"
			html += "</tr>"
		html += "</table>"
		html += "</div>"

		html += "<div class='block'>"
		html += "<h2>Next Event</h2>"
		html += "<table[table_options]>"
		html += "<tr><td[row_options1]>Severity</td><td[row_options2]>Name</td><td[row_options3]>Event Rotation</td><td>Clear</td></tr>"
		for(var/severity = EVENT_LEVEL_MUNDANE to EVENT_LEVEL_MAJOR)
			var/datum/event_container/EC = event_containers[severity]
			var/datum/event_meta/EM = EC.next_event()
			html += "<tr>"
			html += "<td>[GLOB.severity_to_string[severity]]</td>"
			html += "<td><A align='right' href='byond://?src=\ref[src];select_event=\ref[EC]'>[EM ? EM.name : "Random"]</A></td>"
			html += "<td><A align='right' href='byond://?src=\ref[src];view_events=\ref[EC]'>View</A></td>"
			html += "<td><A align='right' href='byond://?src=\ref[src];clear=\ref[EC]'>Clear</A></td>"
			html += "</tr>"
		html += "</table>"
		html += "</div>"

		html += "<div class='block'>"
		html += "<h2>Running Events</h2>"
		html += "Estimated times, affected by process scheduler delays."
		html += "<table[table_options]>"
		html += "<tr><td[row_options1]>Severity</td><td[row_options2]>Name</td><td[row_options1]>Ends At</td><td[row_options1]>Ends In</td><td[row_options3]>Stop</td></tr>"
		for(var/datum/event/E in active_events())
			if(!E.event_meta())
				continue
			var/datum/event_meta/EM = E.event_meta()
			var/ends_at = E.startedAt + (E.lastProcessAt() * 20)	// A best estimate, based on how often the alarm manager processes
			var/ends_in = max(0, round((ends_at - world.time) / 600, 0.1))
			html += "<tr>"
			html += "<td>[GLOB.severity_to_string[EM.severity]]</td>"
			html += "<td>[EM.name]</td>"
			html += "<td>[worldtime2stationtime(ends_at)]</td>"
			html += "<td>[ends_in]</td>"
			html += "<td><A align='right' href='byond://?src=\ref[src];stop=\ref[E]'>Stop</A></td>"
			html += "</tr>"
		html += "</table>"
		html += "</div>"

	return html

/datum/world_service/events/Topic(href, href_list)
	if(..())
		return

	if(href_list["toggle_report"])
		report_at_round_end = !report_at_round_end
		log_and_message_admins("has [report_at_round_end ? "enabled" : "disabled"] the round end event report.")
	else if(href_list["dec_timer"])
		var/datum/event_container/EC = locate(href_list["event"])
		var/decrease = 60 * (10 ** text2num(href_list["dec_timer"]))
		EC.next_event_time -= decrease
		log_and_message_admins("decreased timer for [GLOB.severity_to_string[EC.severity]] events by [decrease/600] minute(s).")
	else if(href_list["inc_timer"])
		var/datum/event_container/EC = locate(href_list["event"])
		var/increase = 60 * (10 ** text2num(href_list["inc_timer"]))
		EC.next_event_time += increase
		log_and_message_admins("increased timer for [GLOB.severity_to_string[EC.severity]] events by [increase/600] minute(s).")
	else if(href_list["select_event"])
		var/datum/event_container/EC = locate(href_list["select_event"])
		EC.SelectEvent()
	else if(href_list["pause"])
		var/datum/event_container/EC = locate(href_list["pause"])
		EC.delayed = !EC.delayed
		log_and_message_admins("has [EC.delayed ? "paused" : "resumed"] countdown for [GLOB.severity_to_string[EC.severity]] events.")
	else if(href_list["pause_all"])
		CONFIG_SET(flag/allow_random_events, text2num(href_list["pause_all"]))
		log_and_message_admins("has [CONFIG_GET(flag/allow_random_events) ? "resumed" : "paused"] countdown for all events.")
	else if(href_list["interval"])
		var/delay = topic_ask(usr, href_list, "k160", /datum/om/prompt/number, message = "Enter delay modifier. A value less than one means events fire more often, higher than one less often.", title = "Set Interval Modifier")
		if(isnull(delay))
			return
		if(delay && delay > 0)
			var/datum/event_container/EC = locate(href_list["interval"])
			EC.delay_modifier = delay
			log_and_message_admins("has set the interval modifier for [GLOB.severity_to_string[EC.severity]] events to [EC.delay_modifier].")
	else if(href_list["stop"])
		var/_answer_k166 = topic_ask(usr, href_list, "k166", /datum/om/prompt/choice/alert, message = "Stopping an event may have unintended side-effects. Continue?", title = "Stopping Event!", choices = list("Yes","No"))
		if(isnull(_answer_k166))
			return
		if(_answer_k166 != "Yes")
			return
		var/datum/event/E = locate(href_list["stop"])
		var/datum/event_meta/EM = E.event_meta()
		log_and_message_admins("has stopped the [GLOB.severity_to_string[EM.severity]] event '[EM.name]'.")
		E.kill()
	else if(href_list["view_events"])
		rel_set(src, "selected_event_container", locate(href_list["view_events"]))
	else if(href_list["back"])
		rel_clear(src, "selected_event_container")
	else if(href_list["set_name"])
		var/name = topic_ask(usr, href_list, "k177", /datum/om/prompt/text, message = "Enter event name.", title = "Set Name", max_length = MAX_LNAME_LEN)
		if(isnull(name))
			return
		if(name)
			var/datum/event_meta/EM = locate(href_list["set_name"])
			EM.name = name
	else if(href_list["set_type"])
		var/type = topic_ask(usr, href_list, "k182", /datum/om/prompt/choice, message = "Select event type.", title = "Select", choices = allEvents)
		if(isnull(type))
			return
		if(type)
			var/datum/event_meta/EM = locate(href_list["set_type"])
			EM.event_type = type
	else if(href_list["set_weight"])
		var/weight = topic_ask(usr, href_list, "k187", /datum/om/prompt/number, message = "Enter weight. A higher value means higher chance for the event of being selected.", title = "Set Weight")
		if(isnull(weight))
			return
		if(weight && weight > 0)
			var/datum/event_meta/EM = locate(href_list["set_weight"])
			EM.weight = weight
			if(EM != new_event)
				log_and_message_admins("has changed the weight of the [GLOB.severity_to_string[EM.severity]] event '[EM.name]' to [EM.weight].")
	else if(href_list["toggle_oneshot"])
		var/datum/event_meta/EM = locate(href_list["toggle_oneshot"])
		EM.one_shot = !EM.one_shot
		if(EM != new_event)
			log_and_message_admins("has [EM.one_shot ? "set" : "unset"] the oneshot flag for the [GLOB.severity_to_string[EM.severity]] event '[EM.name]'.")
	else if(href_list["toggle_enabled"])
		var/datum/event_meta/EM = locate(href_list["toggle_enabled"])
		EM.enabled = !EM.enabled
		log_and_message_admins("has [EM.enabled ? "enabled" : "disabled"] the [GLOB.severity_to_string[EM.severity]] event '[EM.name]'.")
	else if(href_list["remove"])
		var/_answer_k203 = topic_ask(usr, href_list, "k203", /datum/om/prompt/choice/alert, message = "This will remove the event from rotation. Continue?", title = "Removing Event!", choices = list("Yes","No"))
		if(isnull(_answer_k203))
			return
		if(_answer_k203 != "Yes")
			return
		var/datum/event_meta/EM = locate(href_list["remove"])
		var/datum/event_container/EC = locate(href_list["EC"])
		EC.available_events -= EM
		log_and_message_admins("has removed the [GLOB.severity_to_string[EM.severity]] event '[EM.name]'.")
	else if(href_list["add"])
		if(!new_event.name || !new_event.event_type)
			return
		var/_answer_k212 = topic_ask(usr, href_list, "k212", /datum/om/prompt/choice/alert, message = "This will add a new event to the rotation. Continue?", title = "Add Event!", choices = list("Yes","No"))
		if(isnull(_answer_k212))
			return
		if(_answer_k212 != "Yes")
			return
		new_event.severity = selected_event_container().severity
		selected_event_container().available_events += new_event
		log_and_message_admins("has added \a [GLOB.severity_to_string[new_event.severity]] event '[new_event.name]' of type [new_event.event_type] with weight [new_event.weight].")
		own_set(src, "new_event", new /datum/event_meta)
	else if(href_list["clear"])
		var/datum/event_container/EC = locate(href_list["clear"])
		if(EC.next_event())
			log_and_message_admins("has dequeued the [GLOB.severity_to_string[EC.severity]] event '[EC.next_event().name]'.")
			rel_clear(EC, "next_event")

	Interact(usr)

ADMIN_VERB(forceEvent, R_DEBUG, "Trigger Event (Debug Only)", "Immediately triggers an event.", ADMIN_CATEGORY_DEBUG_DANGEROUS, type in GLOB.event_service.allEvents)
	if(!ispath(type))
		return
	new type(new /datum/event_meta(EVENT_LEVEL_MAJOR))
	message_admins("[key_name_admin(user)] has triggered an event. ([type])")

ADMIN_VERB(event_manager_panel, R_ADMIN|R_EVENT, "Event Manager Panel", "Opens the event manager panel.", ADMIN_CATEGORY_EVENTS)
	GLOB.event_service.Interact(user)
	feedback_add_details("admin_verb","EMP") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/// Accessor for the selected_event_container var.
/datum/world_service/events/proc/selected_event_container() as /datum/event_container
	return selected_event_container
