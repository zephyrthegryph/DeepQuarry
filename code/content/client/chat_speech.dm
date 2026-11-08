// Speech from the chat input row (tgui/packages/tgui-panel/input): the one place a player types what they say. Every speech hotkey
// (Say, Me, Whisper, Subtle, OOC, LOOC, Radio) focuses the row in its channel (chat_focus_input(), chat_column.dm); the chat panel
// forwards the row's messages here. `open`/`close` bracket the typing, `thinking`/`typing` drive the bubble over the head, `entry`
// speaks. The say popup (tgui-say) is gone.

/// Whether the chat input row has focus: the speaker may show a thinking or typing bubble.
/client/var/tmp/chat_speech_open = FALSE

/// The chat input row's messages. TRUE when `type` was one of them.
/client/proc/chat_speech_message(type, payload, href_list)
	switch(type)
		if("open")
			chat_speech_open = TRUE
			send_chat_language_rules()
			chat_send_input_state()
			var/channel = payload?["channel"]
			if(channel != OOC_CHANNEL && channel != LOOC_CHANNEL && channel != ADMIN_CHANNEL)
				start_thinking(channel)
			return TRUE
		if("close")
			chat_speech_open = FALSE
			stop_thinking()
			return TRUE
		if("thinking")
			if(payload?["visible"] == TRUE && chat_speech_open)
				start_thinking(payload["channel"])
			else if(payload?["visible"] == FALSE)
				stop_thinking(payload["channel"])
			return TRUE
		if("typing")
			if(chat_speech_open)
				start_typing(payload?["channel"])
			return TRUE
		if("entry")
			var/id = href_list?["packetId"]
			if(!isnull(id))
				payload = tgui_panel?.handle_packets(id, href_list["totalPackets"], href_list["packet"], mob)
				if(!payload)
					return TRUE
			chat_speech_entry(payload)
			return TRUE
		if("lenwarn")
			to_chat(src, span_warning(span_bold("Warning") + ": Message with [payload?["length"]] exceeded the maximum length of [payload?["maxlength"]]."))
			return TRUE
	return FALSE

/// The data the row's live preview parses with (the preview is always on). Sent when the row opens: the mob, its languages and its
/// keys change between messages.
/client/proc/send_chat_language_rules()
	if(!mob || !tgui_panel?.is_ready())
		return
	tgui_panel.window.send_message("chat/languageRules", list(
		"rules" = mob.say_language_rules(),
		"preview" = TRUE,
	))

/// Speaks an entry in its channel.
/client/proc/chat_speech_entry(payload)
	if(!payload?["channel"] || !payload["entry"])
		CRASH("[mob] entered in a null payload to the chat input.")
	if(length(payload["entry"]) > MAX_MESSAGE_LEN)
		CRASH("[mob] has entered more characters than allowed into the chat input")
	if(!mob)
		return FALSE
	var/entry = payload["entry"]
	switch(payload["channel"])
		if(SAY_CHANNEL)
			mob.say_verb(entry)
		if(RADIO_CHANNEL)
			mob.say_verb(";" + entry)
		if(ME_CHANNEL)
			mob.me_verb(entry)
		if(WHIS_CHANNEL)
			mob.whisper(entry)
		if(SUBTLE_CHANNEL)
			mob.me_verb_subtle(entry)
		if(OOC_CHANNEL)
			ooc(entry)
		if(LOOC_CHANNEL)
			looc(entry)
		if(ADMIN_CHANNEL)
			if(admin_require(src, R_ADMIN, "check_rights in [callee.proc]", show_msg = FALSE))
				SSadmin_verbs.dynamic_invoke_verb(src, /datum/admin_verb/cmd_admin_say, entry)
		else
			return FALSE
	return TRUE

/// The lobby's only chat input channel. Callers read it, never change it.
GLOBAL_LIST_INIT(chat_lobby_channels, list(OOC_CHANNEL))

/// The channels this client's mob can speak in right now, in the row's order (/mob/proc/chat_input_channels()); OOC with no mob.
/client/proc/chat_available_channels()
	return mob ? mob.chat_input_channels() : GLOB.chat_lobby_channels

/// The channels this mob's player can speak in now: the lobby has OOC only; a body adds Say, Me and LOOC; a living one Whisper and
/// Subtle; Radio needs a radio it can talk through (chat_radio_sets(), the same headsets its prefixes come from).
/mob/proc/chat_input_channels()
	if(isnewplayer(src))
		return GLOB.chat_lobby_channels
	. = list(SAY_CHANNEL)
	if(isliving(src) && length(chat_radio_sets()))
		. += RADIO_CHANNEL
	. += ME_CHANNEL
	if(isliving(src))
		. += WHIS_CHANNEL
		. += SUBTLE_CHANNEL
	. += OOC_CHANNEL
	. += LOOC_CHANNEL

/// Tells the chat input row what the speaker can use now: its channels and its radio prefixes. Sent when the chat page is ready, when the
/// client takes a mob (lobby, spawn, ghost, transfer) and when the row opens.
/client/proc/chat_send_input_state()
	if(!tgui_panel?.is_ready())
		return
	var/list/channels = chat_available_channels()
	tgui_panel.window.send_message("chat/channels", list("channels" = channels))
	log_tgui(src, "Chat input channels sent: [jointext(channels, ",")].", context = "chat_float")
	chat_send_radio_options()

/mob/Login()
	. = ..()
	client?.chat_send_input_state()
