//
//TICKET MANAGER
//

CAPABILITIES(/datum/tickets)
	interface("TicketsPanel", title = "Tickets", state = nameof(GLOB.tgui_mentor_state))
	op("legacy", ui_act("legacy"), asks(/datum/prompt/choice/ticket_list_ui, step = "list"), then(PROC_REF(ui_act_legacy)))
	op("new_ticket", ui_act("new_ticket"), asks(/datum/prompt/choice/ticket_create, fields = list("question" = "Please select the ckey of the user.", "title" = "Select CKEY", "choices" = computed(PROC_REF(ticket_ckey_choices))), step = "ckey"), asks(/datum/prompt/text/ticket_create, fields = list("question" = "What should the initial text be?", "title" = "New Ticket"), step = "text"), asks(/datum/prompt/choice/ticket_create, fields = list("question" = "Is this ticket Admin-Level or Mentor-Level?", "title" = "Ticket Level", "choices" = list("Admin", "Mentor"), "buttons" = TRUE), step = "level"), asks(/datum/prompt/choice/ticket_create, fields = list("question" = "The player already has a ticket open. Is this for the same issue?", "title" = "Duplicate?", "choices" = list("Yes", "No"), "buttons" = TRUE), step = "duplicate", when = PROC_REF(ticket_player_has_ticket)), then(PROC_REF(ui_act_new_ticket)))
	op("pick_ticket", ui_act("pick_ticket", arg("ticket_id", num())), then(PROC_REF(ui_act_pick_ticket)))
	op("retitle_ticket", ui_act("retitle_ticket"), then(PROC_REF(ui_act_retitle_ticket)))
	op("reopen_ticket", ui_act("reopen_ticket"), then(PROC_REF(ui_act_reopen_ticket)))
	op("undock_ticket", ui_act("undock_ticket"), then(PROC_REF(ui_act_undock_ticket)))
	op("send_msg", ui_act("send_msg", arg("msg", schema_text(4096))), then(PROC_REF(ui_act_send_msg)))

/datum/tickets/proc/get_ticket_state(state)
	var/ticket_state
	switch(state)
		if(AHELP_ACTIVE)
			ticket_state = "open"
		// TODO: Mentor tickets cannot be resolved
		if(AHELP_RESOLVED)
			ticket_state = "resolved"
		if(AHELP_CLOSED)
			ticket_state = "closed"
		else
			ticket_state = "unknown"

	return ticket_state

/// /datum/tickets's window data.
/datum/tickets/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()
	var/list/tickets = list()

	var/selected_ticket = null

	if(user.client.selected_ticket())
		var/datum/ticket/T = user.client.selected_ticket()
		if(check_rights_for(user.client, (R_ADMIN|R_SERVER|R_MOD)) || (check_rights_for(user.client, R_MENTOR) && T.level < 1))
			selected_ticket = list(
				"id" = T.id,
				"name" = T.LinkedReplyName(),
				"state" = get_ticket_state(T.state),
				"level" = T.level,
				"handler" = T.handler,
				"opened_at" = (world.time - T.opened_at),
				"closed_at" = (world.time - T.closed_at),
				"opened_at_date" = gameTimestamp(wtime = T.opened_at),
				"closed_at_date" = gameTimestamp(wtime = T.closed_at),
				"actions" = T.FullMonty(null, check_rights_for(user.client, (R_ADMIN|R_SERVER|R_MOD))),
				"log" = T._interactions,
			)

	for(var/datum/ticket/T as anything in GLOB.tickets.active_tickets)
		if(check_rights_for(user.client, (R_ADMIN|R_SERVER|R_MOD)) || (check_rights_for(user.client, R_MENTOR) && T.level < 1))
			tickets.Add(list(list(
				"id" = T.id,
				"name" = T.initiator_key_name,
				"state" = get_ticket_state(T.state),
				"level" = T.level,
				"handler" = T.handler,
				"ishandled" = !!T.handler_client(),
				"opened_at" = (world.time - T.opened_at),
				"closed_at" = (world.time - T.closed_at),
				"opened_at_date" = gameTimestamp(wtime = T.opened_at),
				"closed_at_date" = gameTimestamp(wtime = T.closed_at),
			)))

	for(var/datum/ticket/T as anything in GLOB.tickets.closed_tickets)
		if(check_rights_for(user.client, (R_ADMIN|R_SERVER|R_MOD)) || (check_rights_for(user.client, R_MENTOR) && T.level < 1))
			tickets.Add(list(list(
				"id" = T.id,
				"name" = T.initiator_key_name,
				"state" = get_ticket_state(T.state),
				"level" = T.level,
				"handler" = T.handler,
				"ishandled" = !!T.handler_client(),
				"opened_at" = (world.time - T.opened_at),
				"closed_at" = (world.time - T.closed_at),
				"opened_at_date" = gameTimestamp(wtime = T.opened_at),
				"closed_at_date" = gameTimestamp(wtime = T.closed_at),
			)))

	for(var/datum/ticket/T as anything in GLOB.tickets.resolved_tickets)
		if(check_rights_for(user.client, (R_ADMIN|R_SERVER|R_MOD)) || (check_rights_for(user.client, R_MENTOR) && T.level < 1))
			tickets.Add(list(list(
				"id" = T.id,
				"name" = T.initiator_key_name,
				"state" = get_ticket_state(T.state),
				"level" = T.level,
				"handler" = T.handler,
				"ishandled" = !!T.handler_client(),
				"opened_at" = (world.time - T.opened_at),
				"closed_at" = (world.time - T.closed_at),
				"opened_at_date" = gameTimestamp(wtime = T.opened_at),
				"closed_at_date" = gameTimestamp(wtime = T.closed_at),
			)))
	data["tickets"] = tickets
	data["is_admin"] = check_rights_for(user.client, (R_ADMIN|R_SERVER|R_MOD))
	data["selected_ticket"] = selected_ticket

	return data

/datum/tickets/proc/ui_act_legacy(datum/act/op/A)
	var/choice = A.step_value("list")
	if(!choice)
		return
	TicketListLegacy(A.actor, choice)
	return TRUE

/datum/tickets/proc/ui_act_new_ticket(datum/act/op/A)
	var/list/answers = list("k115" = A.step_value("ckey"), "k128" = A.step_value("text"), "k133" = A.step_value("level"), "k139" = A.step_value("duplicate"))
	return new_ticket_stage(A.actor, answers, A.actor)

/datum/tickets/proc/ticket_ckey_choices(datum/act/op/A)
	var/list/ckeys = list()
	for(var/client/C in GLOB.clients)
		ckeys += C.key
	return ckeys

/// The duplicate question opens only when the chosen player already has an open ticket.
/datum/tickets/proc/ticket_player_has_ticket(datum/act/op/A)
	var/ckey = lowertext(A.step_value("ckey"))
	for(var/client/C in GLOB.clients)
		if(C.ckey == ckey)
			return !!C.current_ticket()
	return FALSE

/datum/tickets/proc/new_ticket_stage(mob/user, list/answers, mob/token_actor)
	var/_answer_k115 = answers["k115"]
	if(isnull(_answer_k115))
		return
	var/ckey = lowertext(_answer_k115)
	if(!ckey)
		return

	var/client/player
	for(var/client/C in GLOB.clients)
		if(C.ckey == ckey)
			player = C

	if(!player)
		to_chat(user, span_warning("Ckey ([ckey]) not online."))
		return

	var/ticket_text = answers["k128"]
	if(isnull(ticket_text))
		return
	if(!ticket_text)
		to_chat(user, span_warning("Ticket message cannot be empty."))
		return

	var/level = answers["k133"]
	if(isnull(level))
		return
	if(!level)
		return

	feedback_add_details("admin_verb","Admincreatedticket") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
	if(player.current_ticket())
		var/input = answers["k139"]
		if(isnull(input))
			return
		if(!input)
			return
		if(input == "Yes")
			if(player.current_ticket())
				player.current_ticket().MessageNoRecipient(ticket_text)
				to_chat(user, span_adminnotice("PM to-" + span_bold("Admins") + ": [ticket_text]"))
				return
			else
				to_chat(user, span_warning("Ticket not found, creating new one..."))
		else
			player.current_ticket().AddInteraction("[key_name_admin(user)] opened a new ticket.")
			player.current_ticket().Close(user)

	// Create a new ticket and handle it. You created it afterall!
	var/datum/ticket/T = new /datum/ticket(ticket_text, player, TRUE, level, user, token_actor)
	if(level == "Admin")
		T.level = 1
	else
		T.level = 0
	T.HandleIssue(user)
	switch(T.level)
		if (0)
			user.client.cmd_mentor_pm(player, ticket_text, T)
		if (1)
			user.client.cmd_admin_pm(player, ticket_text, T, token_actor)
	return TRUE

/datum/prompt/choice/ticket_create
	timeout = 0

/datum/prompt/choice/ticket_create/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/ticket_create/refusal(given)
	return null

/datum/prompt/text/ticket_create
	timeout = 0
	max_len = MAX_MESSAGE_LEN

/datum/prompt/text/ticket_create/normalize(given)
	return istext(given) ? given : null

/datum/tickets/proc/ui_act_pick_ticket(datum/act/op/A, ticket_id)
	var/mob/user = A.actor
	var/datum/ticket/T = ID2Ticket(ticket_id, user)
	user.client.selected_ticket_id = T?.id
	. = TRUE

/datum/tickets/proc/ui_act_retitle_ticket(datum/act/op/A)
	var/mob/user = A.actor
	user.client.selected_ticket().Retitle(user)
	. = TRUE

/datum/tickets/proc/ui_act_reopen_ticket(datum/act/op/A)
	var/mob/user = A.actor
	user.client.selected_ticket().Reopen(user)
	. = TRUE

/datum/tickets/proc/ui_act_undock_ticket(datum/act/op/A)
	var/mob/user = A.actor
	user.client.selected_ticket().tgui_interact(user)
	user.client.selected_ticket_id = null
	. = TRUE

/datum/tickets/proc/ui_act_send_msg(datum/act/op/A, msg)
	var/mob/user = A.actor
	if(!msg)
		return

	switch(user.client.selected_ticket().level)
		if (0)
			user.client.cmd_mentor_pm(user.client.selected_ticket().initiator(), msg, user.client.selected_ticket())
		if (1)
			user.client.cmd_admin_pm(user.client.selected_ticket().initiator(), msg, user.client.selected_ticket())
	. = TRUE

/datum/tickets/tgui_fallback(payload, user)
	if(..())
		return

	if(!ismob(user))
		return
	var/mob/actor = user
	if(QDELETED(actor))
		return
	open_request(src, /datum/prompt/choice/ticket_fallback_list, PROC_REF(ticket_fallback_list_answered), answerer = actor)

/datum/tickets/proc/ticket_fallback_list_answered(datum/act/request/context)
	if(!context.answer)
		return
	TicketListLegacy(context.request.answerer, context.answer.value)
	SStgui.update_uis(src)

//
//TICKET DATUM
//

/datum/ticket/ui_title(mob/user)
	return "Ticket #[id] - [LinkedReplyName("\ref[src]")]"

/datum/ticket/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["id"] = id
	data["title"] = name
	data["level"] = level
	data["handler"] = handler
	data["log"] = _interactions
	var/list/merged_1 = ui_data_datum_ticket(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /datum/ticket's window data.
/datum/ticket/proc/ui_data_datum_ticket(mob/user, datum/tgui/_ui, datum/tgui_state/_state)
	var/list/data = list()


	var/ref_src = "\ref[src]"
	data["name"] = LinkedReplyName(ref_src)
	data["ticket_ref"] = ref_src

	switch(state)
		if(AHELP_ACTIVE)
			data["state"] = "open"
		// TODO: Mentor tickets cannot be resolved
		if(AHELP_RESOLVED)
			data["state"] = "resolved"
		if(AHELP_CLOSED)
			data["state"] = "closed"
		else
			data["state"] = "unknown"


	data["opened_at"] = (world.time - opened_at)
	data["closed_at"] = (world.time - closed_at)
	data["opened_at_date"] = gameTimestamp(wtime = opened_at)
	data["closed_at_date"] = gameTimestamp(wtime = closed_at)

	data["actions"] = FullMonty(ref_src, check_rights_for(user.client, (R_ADMIN|R_SERVER|R_MOD)))


	return data

/datum/ticket/proc/ui_act_retitle(datum/act/op/A)
	var/mob/user = A.actor
	Retitle(user)
	. = TRUE

/datum/ticket/proc/ui_act_reopen(datum/act/op/A)
	var/mob/user = A.actor
	Reopen(user)
	. = TRUE

/datum/ticket/proc/ui_act_legacy(datum/act/op/A)
	var/mob/user = A.actor
	TicketPanelLegacy(user)
	. = TRUE

/datum/ticket/proc/ui_act_send_msg(datum/act/op/A, msg, ticket_ref)
	var/mob/user = A.actor
	if(!msg || !ticket_ref)
		return

	var/datum/ticket/T = ticket_ref

	switch(level)
		if (0)
			user.client.cmd_mentor_pm(T.initiator(), sanitize(msg), T)
		if (1)
			user.client.cmd_admin_pm(T.initiator(), sanitize(msg), T)

	. = TRUE

/datum/ticket/tgui_fallback(payload, user)
	if(..())
		return

	TicketPanelLegacy(user)

/datum/ticket/proc/TicketPanelLegacy(mob/user)
	var/list/dat = list("<html><head><title>Ticket #[id]</title></head>")
	var/ref_src = "\ref[src]"
	dat += "<h4>Ticket #[id]: [LinkedReplyName(ref_src)]</h4>"
	dat += "<b>State: "
	switch(state)
		if(AHELP_ACTIVE)
			dat += span_red("OPEN")
		if(AHELP_RESOLVED)
			dat += span_green("RESOLVED")
		if(AHELP_CLOSED)
			dat += "CLOSED"
		else
			dat += "UNKNOWN"
	dat += "</b>[GLOB.TAB][TicketHref("Refresh", ref_src)][GLOB.TAB][TicketHref("Re-Title", ref_src, "retitle")]"
	if(state != AHELP_ACTIVE)
		dat += "[GLOB.TAB][TicketHref("Reopen", ref_src, "reopen")]"
	dat += "<br><br>Opened at: [gameTimestamp(wtime = opened_at)] (Approx [(world.time - opened_at) / 600] minutes ago)"
	if(closed_at)
		dat += "<br>Closed at: [gameTimestamp(wtime = closed_at)] (Approx [(world.time - closed_at) / 600] minutes ago)"
	dat += "<br><br>"
	if(initiator())
		dat += span_bold("Actions:") + " [FullMonty(ref_src, check_rights_for(user.client, (R_ADMIN|R_SERVER|R_MOD)))]<br>"
	else
		dat += span_bold("DISCONNECTED") + "[GLOB.TAB][ClosureLinks(ref_src)]<br>"
	dat += "<br><b>Log:</b><br><br>"
	for(var/I in _interactions)
		dat += "[I]<br>"
	dat += "</html>"
	// structured TGUI AdminReport (fallback path).
	dq_admin_report_html(user, "Ticket #[id]", dat.Join(), src)

/datum/tickets/proc/TicketListLegacy(mob/user, state)
	var/list/dat = list("<html><head><title>[state] Tickets</title></head>")
	var/tickets_found = 0

	if(state == "Active")
		for(var/datum/ticket/T as anything in GLOB.tickets.active_tickets)
			if(!check_rights_for(user.client, (R_ADMIN|R_SERVER|R_MOD)) && T.level > 0)
				continue
			dat += "[T.level == 0 ? "Mentorhelp" : "Adminhelp"] - [T.TicketHref("#[T.id] - [T.initiator_ckey]:  [T.name]")]"
			tickets_found++
	else if(state == "Closed")
		for(var/datum/ticket/T as anything in GLOB.tickets.closed_tickets)
			if(!check_rights_for(user.client, (R_ADMIN|R_SERVER|R_MOD)) && T.level > 0)
				continue
			dat += "[T.level == 0 ? "Mentorhelp" : "Adminhelp"] - [T.TicketHref("#[T.id] - [T.initiator_ckey]:  [T.name]")]"
			tickets_found++
	else if(state == "Resolved")
		for(var/datum/ticket/T as anything in GLOB.tickets.resolved_tickets)
			if(!check_rights_for(user.client, (R_ADMIN|R_SERVER|R_MOD)) && T.level > 0)
				continue
			dat += "[T.level == 0 ? "Mentorhelp" : "Adminhelp"] - [T.TicketHref("#[T.id] - [T.initiator_ckey]:  [T.name]")]"
			tickets_found++

	if(tickets_found == 0)
		dat += "No [state] tickets found."
	dat += "</html>"
	// structured TGUI AdminReport (fallback path).
	dq_admin_report_html(user, "[state] Tickets", dat.Join(), src)

// The original ticket-manager UI owns this scalar selection continuation.
/datum/prompt/choice/ticket_list_ui
	title = "Tickets"
	question = "Which tickets do you want to list?"
	choices = list("Active", "Closed", "Resolved")
	timeout = 0

/datum/prompt/choice/ticket_fallback_list
	question = "Which tickets do you want to list?"
	title = "Tickets"
	choices = list("Active", "Closed", "Resolved")
	timeout = 0

/datum/prompt/choice/ticket_fallback_list/recheck_extra()
	var/mob/user = answerer
	return !istype(user) || QDELETED(user) ? "gone" : null
