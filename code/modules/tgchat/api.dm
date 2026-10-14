// The chat system's API (code/modules/tgchat/chat_service.dm declares the system): what other folders call.
//
//   SSchat.queue(target, message_data)            queue a payload for delivery on the next tick (target: client, mob, ckey or a list)
//   SSchat.send_immediate(target, message_data)   deliver now (a disconnecting client, boot)
//   SSchat.handle_resend(client, sequence)        a client asks for a payload again

/datum/system/chat/proc/queue(queue_target, list/message_data)
	var/list/targets = islist(queue_target) ? queue_target : list(queue_target)
	for(var/target in targets)
		var/client/client = CLIENT_FROM_VAR(target)
		if(isnull(client))
			continue
		LAZYADDASSOCLIST(client_to_payloads, client.ckey, generate_payload(client, message_data))
	wake_work_item(PROC_REF(send_queued))

/datum/system/chat/proc/send_immediate(send_target, list/message_data)
	var/list/targets = islist(send_target) ? send_target : list(send_target)
	for(var/target in targets)
		var/client/client = CLIENT_FROM_VAR(target)
		if(isnull(client))
			continue
		send_payload_to_client(client, generate_payload(client, message_data))

/datum/system/chat/proc/handle_resend(client/client, sequence)
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
