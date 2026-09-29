//
//PLAYERSIDE TICKET UI
//

/datum/ticket_chat
	var/tmp/T_handle

DECLARE_UI(/datum/ticket_chat, "TicketChat")

/datum/ticket_chat/ui_opening(mob/user, datum/tgui/ui)
	user.clear_alert("open ticket")

/datum/ticket_chat/ui_title(mob/user)
	return "Ticket #[T().id] - [T().LinkedReplyName("\ref[T()]")]"

/datum/ticket_chat/tgui_close(mob/user)
	. = ..()
	if(user.client?.current_ticket())
		user.throw_alert("open ticket", /atom/movable/screen/alert/open_ticket)

/datum/ticket_chat/tgui_state(mob/user)
	return GLOB.tgui_ticket_state

/datum/ticket_chat/tgui_data(mob/user)
	var/list/data = list()

	data["id"] = T().id

	data["level"] = T().level
	data["handler"] = T().handler

	data["log"] = T()._interactions

	return data

UI_ACT(/datum/ticket_chat, "send_msg", ui_act_send_msg, UI_ARG_TEXT("msg"))
UI_ACT_PROC(/datum/ticket_chat, ui_act_send_msg)
	if(!params["msg"])
		return

	var/sane_message = sanitize(params["msg"])
	switch(T().level)
		if (0)
			ui.user.client.cmd_mentor_pm(om_resolve(T().handler_ref), sane_message, T())
			return TRUE
		if (1)
			ui.user.client.cmd_admin_pm(om_resolve(T().handler_ref), sane_message, T())
			return TRUE

	. = TRUE

/// LC-refs: the T this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/ticket_chat/proc/T() as /datum/ticket
	return om_resolve(T_handle)
