// The chat system's API (code/modules/tgchat/chat_service.dm declares the system): what other folders call.
//
//   SSchat.queue(target, message_data)            queue a payload for delivery on the next tick (target: client, mob, ckey or a list)
//   SSchat.send_immediate(target, message_data)   deliver now (a disconnecting client, boot)
//   SSchat.handle_resend(client, sequence)        a client asks for a payload again
//   SSchat.replay(client, after)                  the client's kept messages newer than sequence `after`, again, in order (a chat window that moved)

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
	sequence = text2num("[sequence]")
	var/datum/chat_history/history = client?.chat_history
	if(!history?.take_resend(sequence))
		return // not kept, or we tried but byond said no
	client.chat_window()?.send_message("chat/message", history.find(sequence))

/// The client's kept messages newer than sequence `after` (-1: all of them), sent again in order; the page shows each sequence once.
/datum/system/chat/proc/replay(client/client, after = -1)
	var/datum/chat_history/history = client?.chat_history
	var/datum/tgui_window/window = client?.chat_window()
	if(!history || !window)
		return 0
	var/list/texts = history.since(after)
	for(var/text in texts)
		window.send_message("chat/message", text)
	return length(texts)

/// Forgets a ckey's sequence numbering (a bench or a test that made messages for a stand-in).
/datum/system/chat/proc/forget(ckey)
	client_to_sequence_number -= ckey
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

/// The window the chat is in for this client. Everything the chat is sent (messages, input focus, channels, language rules) goes to it.
/client/proc/chat_window() as /datum/tgui_window
	return chat_window_of(chat_ui_window, tgui_panel?.window)

/// Where the chat is, given its own window and the column page: a floating window while an interface holds it, else the page. Docked,
/// the chat is part of the column page, whose own message bus has it, so the page itself takes its messages; a closed floating window
/// (released back to the pool) is not the chat's.
/proc/chat_window_of(datum/tgui_window/own, datum/tgui_window/page) as /datum/tgui_window
	if(own && !istype(own, /datum/tgui_window/column_part) && own.locked_by())
		return own
	return page

/// The chat's own window, set while it has one (doc/rewrite/proposals/window_system.md section 12).
/client/var/tmp/datum/tgui_window/chat_ui_window

/// The client's recent chat messages (chat_history.dm).
/client/var/tmp/datum/chat_history/chat_history

/// Makes the client's recent-messages ring (on its first message).
/client/proc/make_chat_history() as /datum/chat_history
	rel_set(src, nameof(/client::chat_history), new /datum/chat_history)
	return chat_history
