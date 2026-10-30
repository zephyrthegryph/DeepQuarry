/*!
 * Copyright (c) 2020 Aleksej Komarov
 * SPDX-License-Identifier: MIT
 */

// The chat delivery system (was SSchat): queued chat payloads go out every tick, parked
// while nothing is queued.
SYSTEM_DEF(chat)
	name = "Chat"
	periodic_runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT

	/// Assosciates a ckey with a list of messages to send to them.
	var/list/list/datum/chat_payload/client_to_payloads = list()

	/// Associates a ckey with an assosciative list of their last CHAT_RELIABILITY_HISTORY_SIZE messages.
	var/list/list/datum/chat_payload/client_to_reliability_history = list()

	/// Assosciates a ckey with their next sequence number.
	var/list/client_to_sequence_number = list()

/// The one point every chat message to a client goes through (to_chat, to_chat_immediate and message_admins all end in queue()/send_immediate()):
/// the HREF_TOKEN_PLACEHOLDER of its links becomes this client's own admin token, or nothing for a player (href_deliver()). The message list is
/// shared by every target of one call, so a copy is made only when the placeholder is present.
/datum/system/chat/proc/generate_payload(client/target, list/message_data)
	for(var/field in list("html", "text"))
		var/original = message_data[field]
		if(!istext(original) || !findtext(original, HREF_TOKEN_PLACEHOLDER))
			continue
		var/delivered = href_deliver(target, original)
		message_data = message_data.Copy()
		message_data[field] = delivered
	var/sequence = client_to_sequence_number[target.ckey]
	client_to_sequence_number[target.ckey] += 1

	var/datum/chat_payload/payload = new
	payload.sequence = sequence
	payload.content = message_data

	if(!(target.ckey in client_to_reliability_history))
		client_to_reliability_history[target.ckey] = list()
	var/list/client_history = client_to_reliability_history[target.ckey]
	client_history["[sequence]"] = payload

	if(length(client_history) > CHAT_RELIABILITY_HISTORY_SIZE)
		var/oldest = text2num(client_history[1])
		for(var/index in 2 to length(client_history))
			var/test = text2num(client_history[index])
			if(test < oldest)
				oldest = test
		client_history -= "[oldest]"
	return payload

/datum/system/chat/proc/send_payload_to_client(client/target, datum/chat_payload/payload)
	target.tgui_panel.window.send_message("chat/message", payload.into_message())
	SEND_TEXT(target, payload.get_content_as_html())

/datum/system/chat/reactions()
	. = ..()
	. += every(WORK_EVERY_TICK, PROC_REF(send_queued), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/// Sends the queued payloads; parks the item when nothing is queued.
/datum/system/chat/proc/send_queued(dt)
	for(var/ckey in client_to_payloads)
		var/client/target = GLOB.directory[ckey]
		if(isnull(target)) // verify client still exists
			LAZYREMOVE(client_to_payloads, ckey)
			continue

		for(var/datum/chat_payload/payload as anything in client_to_payloads[ckey])
			send_payload_to_client(target, payload)
		LAZYREMOVE(client_to_payloads, ckey)

		if(KERNEL_OVER_BUDGET)
			return STEP_YIELD
	return length(client_to_payloads) ? STEP_DONE : STEP_PARK
