//
//TICKET MANAGER
//

DECLARE_UI(/datum/tickets, "TicketsPanel", UI_TITLE("Tickets"))

DECLARE_UI_STATE(/datum/tickets, GLOB.tgui_mentor_state)

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

UI_DATA_REPLACE(/datum/tickets, "merge:ui_data_datum_tickets{tickets:list,is_admin:num,selected_ticket:unknown}")

/// The computed part of /datum/tickets's window data (declared on its UI_DATA row).
/datum/tickets/proc/ui_data_datum_tickets(mob/user, datum/tgui/ui, datum/tgui_state/state)
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

UI_ACT(/datum/tickets, "legacy", ui_act_legacy)
UI_ACT_PROC(/datum/tickets, ui_act_legacy)
	if(!istype(ui) || QDELETED(ui) || !ismob(ui.user) || QDELETED(ui.user))
		return
	open_request(ui, /datum/prompt/choice/ticket_list_ui, TYPE_PROC_REF(/datum/tgui, ticket_list_answered), answerer = ui.user)

UI_ACT(/datum/tickets, "new_ticket", ui_act_new_ticket)
UI_ACT_PROC(/datum/tickets, ui_act_new_ticket)
	var/list/ckeys = list()
	for(var/client/C in GLOB.clients)
		ckeys += C.key

	var/_answer_k115 = act_ask(ui.user, action, params, ui, "k115", /datum/om/prompt/choice, message = "Please select the ckey of the user.", title = "Select CKEY", choices = ckeys)
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
		to_chat(ui.user, span_warning("Ckey ([ckey]) not online."))
		return

	var/ticket_text = act_ask(ui.user, action, params, ui, "k128", /datum/om/prompt/text, message = "What should the initial text be?", title = "New Ticket")
	if(isnull(ticket_text))
		return
	if(!ticket_text)
		to_chat(ui.user, span_warning("Ticket message cannot be empty."))
		return

	var/level = act_ask(ui.user, action, params, ui, "k133", /datum/om/prompt/choice/alert, message = "Is this ticket Admin-Level or Mentor-Level?", title = "Ticket Level", choices = list("Admin", "Mentor"))
	if(isnull(level))
		return
	if(!level)
		return

	feedback_add_details("admin_verb","Admincreatedticket") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
	if(player.current_ticket())
		var/input = act_ask(ui.user, action, params, ui, "k139", /datum/om/prompt/choice/alert, message = "The player already has a ticket open. Is this for the same issue?", title = "Duplicate?", choices = list("Yes","No"))
		if(isnull(input))
			return
		if(!input)
			return
		if(input == "Yes")
			if(player.current_ticket())
				player.current_ticket().MessageNoRecipient(ticket_text)
				to_chat(ui.user, span_adminnotice("PM to-" + span_bold("Admins") + ": [ticket_text]"))
				return
			else
				to_chat(ui.user, span_warning("Ticket not found, creating new one..."))
		else
			player.current_ticket().AddInteraction("[key_name_admin(ui.user)] opened a new ticket.")
			player.current_ticket().Close(ui.user)

	// Create a new ticket and handle it. You created it afterall!
	var/datum/ticket/T = new /datum/ticket(ticket_text, player, TRUE, level, user)
	if(level == "Admin")
		T.level = 1
	else
		T.level = 0
	T.HandleIssue(ui.user)
	switch(T.level)
		if (0)
			ui.user.client.cmd_mentor_pm(player, ticket_text, T)
		if (1)
			ui.user.client.cmd_admin_pm(player, ticket_text, T)
	. = TRUE

UI_ACT(/datum/tickets, "pick_ticket", ui_act_pick_ticket, UI_ARG_NUM("ticket_id"))
UI_ACT_PROC(/datum/tickets, ui_act_pick_ticket)
	var/datum/ticket/T = ID2Ticket(params["ticket_id"], user)
	ui.user.client.selected_ticket_id = T?.id
	. = TRUE

UI_ACT(/datum/tickets, "retitle_ticket", ui_act_retitle_ticket)
UI_ACT_PROC(/datum/tickets, ui_act_retitle_ticket)
	ui.user.client.selected_ticket().Retitle(user)
	. = TRUE

UI_ACT(/datum/tickets, "reopen_ticket", ui_act_reopen_ticket)
UI_ACT_PROC(/datum/tickets, ui_act_reopen_ticket)
	ui.user.client.selected_ticket().Reopen(ui.user)
	. = TRUE

UI_ACT(/datum/tickets, "undock_ticket", ui_act_undock_ticket)
UI_ACT_PROC(/datum/tickets, ui_act_undock_ticket)
	ui.user.client.selected_ticket().tgui_interact(ui.user)
	ui.user.client.selected_ticket_id = null
	. = TRUE

UI_ACT(/datum/tickets, "send_msg", ui_act_send_msg, UI_ARG_TEXT("msg"))
UI_ACT_PROC(/datum/tickets, ui_act_send_msg)
	if(!params["msg"])
		return

	switch(ui.user.client.selected_ticket().level)
		if (0)
			ui.user.client.cmd_mentor_pm(ui.user.client.selected_ticket().initiator(), params["msg"], ui.user.client.selected_ticket())
		if (1)
			ui.user.client.cmd_admin_pm(ui.user.client.selected_ticket().initiator(), params["msg"], ui.user.client.selected_ticket())
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
	TicketListLegacy(context.request.answerer, context.answer.answer_value)
	SStgui.update_uis(src)

//
//TICKET DATUM
//

DECLARE_UI(/datum/ticket, "Ticket")

/datum/ticket/ui_title(mob/user)
	return "Ticket #[id] - [LinkedReplyName("\ref[src]")]"

DECLARE_UI_STATE(/datum/ticket, GLOB.tgui_mentor_state)

UI_DATA_REPLACE(/datum/ticket, "id", "title=name:text", "level:num", "handler:text", "log=_interactions:list", "merge:ui_data_datum_ticket{name:unknown,ticket_ref:text,state:text,opened_at:num,closed_at:num,opened_at_date:unknown,closed_at_date:unknown,actions:num}")

/// The computed part of /datum/ticket's window data (declared on its UI_DATA row).
/datum/ticket/proc/ui_data_datum_ticket(mob/user, datum/tgui/ui, datum/tgui_state/state)
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

UI_ACT(/datum/ticket, "retitle", ui_act_retitle)
UI_ACT_PROC(/datum/ticket, ui_act_retitle)
	Retitle(user)
	. = TRUE

UI_ACT(/datum/ticket, "reopen", ui_act_reopen)
UI_ACT_PROC(/datum/ticket, ui_act_reopen)
	Reopen(ui.user)
	. = TRUE

UI_ACT(/datum/ticket, "legacy", ui_act_legacy)
UI_ACT_PROC(/datum/ticket, ui_act_legacy)
	TicketPanelLegacy(ui.user)
	. = TRUE

UI_ACT(/datum/ticket, "send_msg", ui_act_send_msg, UI_ARG_TEXT("msg"), UI_ARG_REF("ticket_ref", null, /datum/ticket))
UI_ACT_PROC(/datum/ticket, ui_act_send_msg)
	if(!params["msg"] || !params["ticket_ref"])
		return

	var/datum/ticket/T = params["ticket_ref"]

	switch(level)
		if (0)
			ui.user.client.cmd_mentor_pm(T.initiator(), sanitize(params["msg"]), T)
		if (1)
			ui.user.client.cmd_admin_pm(T.initiator(), sanitize(params["msg"]), T)

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
/datum/tgui/proc/ticket_list_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/tickets/manager = src_object()
	manager.TicketListLegacy(user, context.answer.answer_value)
	SStgui.update_uis(manager)

/datum/prompt/choice/ticket_list_ui
	title = "Tickets"
	question = "Which tickets do you want to list?"
	choices = list("Active", "Closed", "Resolved")
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/ticket_list_ui/recheck_extra()
	var/datum/tgui/original_ui = owner
	if(!istype(original_ui) || QDELETED(original_ui))
		return "gone"
	var/datum/tickets/manager = original_ui.src_object()
	if(!istype(manager) || QDELETED(manager) || QDELETED(answerer))
		return "gone"
	if(original_ui.status != STATUS_INTERACTIVE)
		return "the original window is not interactive"
	if(!manager.ui_act_allowed(original_ui.user, "legacy", original_ui, original_ui.state()))
		return "the listing action is unavailable"
	return null

/datum/prompt/choice/ticket_fallback_list
	question = "Which tickets do you want to list?"
	title = "Tickets"
	choices = list("Active", "Closed", "Resolved")
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/ticket_fallback_list/recheck_extra()
	var/mob/user = answerer
	return !istype(user) || QDELETED(user) ? "gone" : null
