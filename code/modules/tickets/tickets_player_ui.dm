//
//PLAYERSIDE TICKET UI
//

/datum/ticket_chat
	var/tmp/datum/ticket/T

DECLARE_UI(/datum/ticket_chat, "TicketChat")

/datum/ticket_chat/ui_opening(mob/user, datum/tgui/ui)
	user.clear_alert("open ticket")

/datum/ticket_chat/ui_title(mob/user)
	return "Ticket #[T().id] - [T().LinkedReplyName("\ref[T()]")]"

/datum/ticket_chat/tgui_close(mob/user)
	. = ..()
	if(user.client?.current_ticket())
		user.throw_alert("open ticket", /atom/movable/screen/alert/open_ticket)

DECLARE_UI_STATE(/datum/ticket_chat, GLOB.tgui_ticket_state)

UI_DATA_REPLACE(/datum/ticket_chat, "merge:ui_data_datum_ticket_chat{id:num,level:num,handler:text,log:list}")

/// The computed part of /datum/ticket_chat's window data (declared on its UI_DATA row).
/datum/ticket_chat/proc/ui_data_datum_ticket_chat(mob/user, datum/tgui/ui, datum/tgui_state/state)
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
			ui.user.client.cmd_mentor_pm(T().handler_client(), sane_message, T())
			return TRUE
		if (1)
			ui.user.client.cmd_admin_pm(T().handler_client(), sane_message, T())
			return TRUE

	. = TRUE

/// The T this refers to (a relation view: null once that is deleted).
/datum/ticket_chat/proc/T() as /datum/ticket
	return T
