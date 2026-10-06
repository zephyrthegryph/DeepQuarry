//
//PLAYERSIDE TICKET UI
//

/datum/ticket_chat
	var/tmp/datum/ticket/T

CAPABILITIES(/datum/ticket_chat)
	interface("TicketChat", state = nameof(GLOB.tgui_ticket_state))
	op("send_msg", ui_act("send_msg", arg("msg", schema_text(4096))), then(PROC_REF(ui_act_send_msg)))

/datum/ticket_chat/ui_opening(mob/user, datum/tgui/ui)
	user.clear_alert("open ticket")

/datum/ticket_chat/ui_title(mob/user)
	return "Ticket #[T().id] - [T().LinkedReplyName("\ref[T()]")]"

/datum/ticket_chat/tgui_close(mob/user)
	. = ..()
	if(user.client?.current_ticket())
		user.throw_alert("open ticket", /atom/movable/screen/alert/open_ticket)

/// /datum/ticket_chat's window data.
/datum/ticket_chat/ui_data(datum/act/eval/A)
	var/list/data = list()

	data["id"] = T().id

	data["level"] = T().level
	data["handler"] = T().handler

	data["log"] = T()._interactions

	return data

/datum/ticket_chat/proc/ui_act_send_msg(datum/act/op/A, msg)
	var/mob/user = A.actor
	if(!msg)
		return

	var/sane_message = sanitize(msg)
	switch(T().level)
		if (0)
			user.client.cmd_mentor_pm(T().handler_client(), sane_message, T())
			return TRUE
		if (1)
			user.client.cmd_admin_pm(T().handler_client(), sane_message, T())
			return TRUE

	. = TRUE

/// The T this refers to (a relation view: null once that is deleted).
/datum/ticket_chat/proc/T() as /datum/ticket
	return T
