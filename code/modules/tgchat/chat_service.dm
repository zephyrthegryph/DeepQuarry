/*!
 * Copyright (c) 2020 Aleksej Komarov
 * SPDX-License-Identifier: MIT
 */

// The chat delivery world service (was SSchat): queued chat payloads go out every tick, parked
// while nothing is queued.
GLOBAL_DATUM_INIT(chat_service, /datum/world_service/chat, new)

/datum/world_service/chat
	name = "Chat"
	lane = /datum/om/behaviour/world/chat
	on_demand = TRUE

	/// Assosciates a ckey with a list of messages to send to them.
	var/list/list/datum/chat_payload/client_to_payloads = list() // ALLOW(instance_list): d: world service singleton

	/// Associates a ckey with an assosciative list of their last CHAT_RELIABILITY_HISTORY_SIZE messages.
	var/list/list/datum/chat_payload/client_to_reliability_history = list() // ALLOW(instance_list): d: world service singleton

	/// Assosciates a ckey with their next sequence number.
	var/list/client_to_sequence_number = list() // ALLOW(instance_list): d: world service singleton

/datum/world_service/chat/proc/generate_payload(client/target, message_data)
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

/datum/world_service/chat/proc/send_payload_to_client(client/target, datum/chat_payload/payload)
	target.tgui_panel.window.send_message("chat/message", payload.into_message())
	SEND_TEXT(target, payload.get_content_as_html())

/datum/world_service/chat/service_step(resumed)
	for(var/ckey in client_to_payloads)
		var/client/target = GLOB.directory[ckey]
		if(isnull(target)) // verify client still exists
			LAZYREMOVE(client_to_payloads, ckey)
			continue

		for(var/datum/chat_payload/payload as anything in client_to_payloads[ckey])
			send_payload_to_client(target, payload)
		LAZYREMOVE(client_to_payloads, ckey)

		if(TICK_CHECK)
			return FALSE
	return TRUE

/datum/world_service/chat/has_work()
	return length(client_to_payloads)

/datum/world_service/chat/proc/queue(queue_target, list/message_data)
	var/list/targets = islist(queue_target) ? queue_target : list(queue_target)
	for(var/target in targets)
		var/client/client = CLIENT_FROM_VAR(target)
		if(isnull(client))
			continue
		LAZYADDASSOCLIST(client_to_payloads, client.ckey, generate_payload(client, message_data))
	demand()

/datum/world_service/chat/proc/send_immediate(send_target, list/message_data)
	var/list/targets = islist(send_target) ? send_target : list(send_target)
	for(var/target in targets)
		var/client/client = CLIENT_FROM_VAR(target)
		if(isnull(client))
			continue
		send_payload_to_client(client, generate_payload(client, message_data))

/datum/world_service/chat/proc/handle_resend(client/client, sequence)
	var/list/client_history = client_to_reliability_history[client.ckey]
	sequence = "[sequence]"
	if(isnull(client_history) || !(sequence in client_history))
		return

	var/datum/chat_payload/payload = client_history[sequence]
	if(payload.resends > CHAT_RELIABILITY_MAX_RESENDS)
		return // we tried but byond said no

	payload.resends += 1
	send_payload_to_client(client, client_history[sequence])
	/*
	SSblackbox.record_feedback(
		"nested tally",
		"chat_resend_byond_version",
		1,
		list(
			"[client.byond_version]",
			"[client.byond_build]",
		),
	)
	*/

/// chat (was SSchat).
/datum/om/behaviour/world/chat
	name = "world: chat"
	every = 1

/datum/om/behaviour/world/chat/service()
	return GLOB.chat_service
