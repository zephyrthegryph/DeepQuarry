// The chat's place: its pane (outputwindow) is the whole right-hand column, and the column page (tgui-panel/column) holds the chat, the
// stat panel's views and every docked tgui window as windows of one window manager (doc/rewrite/proposals/window_system.md section 12).
// The pane is seated once per connection; it never moves or floats natively. Typing goes through the chat page's input row
// (tgui-panel/input); the panel speaks what it sends (tgui_panel/speech.dm). Every speech hotkey focuses the row in its channel
// (chat_focus_input()).

/// Whether this connection's skin already has the chat pane as the whole column (a re-parent reloads the page, so it is done once).
/client/var/tmp/chat_pane_seated = FALSE

/// The channels a speech hotkey can focus the chat input row in (tgui-panel/input/model.ts INPUT_CHANNELS).
GLOBAL_LIST_INIT(chat_input_channels, list(SAY_CHANNEL, RADIO_CHANNEL, ME_CHANNEL, WHIS_CHANNEL, SUBTLE_CHANNEL, OOC_CHANNEL, LOOC_CHANNEL))

/// Sends a speech hotkey to the chat input row in `channel`; the row hands focus back to the map after sending or on Escape.
/// Returns TRUE when the row took it, FALSE while the chat page is not loaded (the caller falls back to the plain verb prompt).
/client/proc/chat_focus_input(channel)
	if(!(channel in GLOB.chat_input_channels))
		return FALSE
	// A hotkey for a channel the speaker cannot use now (Say in the lobby) is not taken; OOC is always there.
	if(!(channel in chat_available_channels()))
		to_chat(src, span_warning("You can't use [channel] right now."))
		return TRUE
	if(!tgui_panel?.is_ready())
		return FALSE
	chat_window().send_message("chat/focusInput", list("channel" = channel))
	winset(src, SKIN_CHAT_BROWSER, "focus=true")
	log_tgui(src, "Chat input focused in [channel].", context = "chat_float")
	return TRUE

/// The OOC hotkey: the input row in OOC, else the OOC prompt.
/client/verb/ooc_input()
	set name = ".dq-ooc-input"
	set hidden = TRUE

	if(chat_focus_input(OOC_CHANNEL))
		return
	winset(src, null, "command=ooc")

/// The LOOC hotkey: the input row in LOOC, else the LOOC prompt.
/client/verb/looc_input()
	set name = ".dq-looc-input"
	set hidden = TRUE

	if(chat_focus_input(LOOC_CHANNEL))
		return
	winset(src, null, "command=looc")

/// The radio hotkey: the input row in Radio (the department picked last, Common at first), else the say prompt.
/client/verb/radio_input()
	set name = ".dq-radio-input"
	set hidden = TRUE

	if(chat_focus_input(RADIO_CHANNEL))
		return
	mob?.ask_chat_line("Speak on the radio.\nType your message (start with ; or a department key):", "Radio", /mob/verb/say_verb)

/// The chat page is up: the chat pane is seated as the whole column (once: the skin's own layout already is, unless a client kept an
/// older one from a previous connection), the map split and fullscreen are applied, and the lobby page is put back if it was left greyed.
/client/proc/chat_layout_sync()
	if(!prefs)
		return
	map_split_apply()
	fullscreen_apply()
	// The lobby page can be left disabled (greyed) when the previous mob's Logout disables it after the lobby mob enabled it: this runs once
	// the chat page is up, after both, so the lobby is put back whenever the layout settles.
	var/mob/new_player/lobby_mob = mob
	if(istype(lobby_mob) && lobby_mob.lobby_window)
		winset(src, SKIN_LOBBY_BROWSER, "is-disabled=false;is-visible=true")
	if(!chat_pane_seated)
		dx_winget(src, src, SKIN_RPANE_SPLIT, "left;right", PROC_REF(chat_pane_observed))
	else
		tgui_panel?.window?.send_message("chat/layout", list())

/// dx_winget() callback: the column split as the client has it. Seated as the whole column only when it is not already.
/client/proc/chat_pane_observed(split_params)
	chat_pane_seated = TRUE
	if(!chat_pane_is_column(split_params))
		var/params = chat_pane_column_params()
		winset(src, null, params)
		log_tgui(src, "Chat pane: [split_params] -> the whole column. winset: [params]", context = "chat_float")
	// The page sizes its browser to the pane it has now (layout/handlers.ts).
	tgui_panel?.window?.send_message("chat/layout", list())

/// Whether a winget of the column split ("left=..;right=..") already has the chat pane as the whole column.
/proc/chat_pane_is_column(split_params)
	var/list/read = params2list("[split_params]")
	return read["left"] == SKIN_OUTPUT_PANE && !length(read["right"])

/// The winset that makes the chat pane the whole column, whatever the split held (the stat pane or a pane from an older layout).
/proc/chat_pane_column_params()
	return jointext(list(
		"[SKIN_RPANE_SPLIT].left=",
		"[SKIN_RPANE_SPLIT].right=",
		"[SKIN_RPANE_SPLIT].left=[SKIN_OUTPUT_PANE]",
		"[SKIN_RPANE_SPLIT].splitter=100",
	), ";")

/// The radios a mob speaks into with a channel prefix (the chat input row's radio selector). None by default.
/mob/proc/chat_radio_sets()
	return list()

/mob/living/carbon/human/chat_radio_sets()
	. = list()
	for(var/slot in list(SLOT_ID_EAR_L, SLOT_ID_EAR_R))
		var/obj/item/radio/R = get_equipped_item(slot)
		if(isradio(R))
			. += R

/mob/living/silicon/robot/chat_radio_sets()
	return radio ? list(radio) : list()

/mob/living/silicon/ai/chat_radio_sets()
	return aiRadio ? list(aiRadio) : list()

/// The department prefixes the chat input row offers for these radio channel names: list of list("key" = ":m", "label" = "Medical"),
/// the :h department key first, then one per channel that has a key. Common (";") is the row's own default and is not listed.
/proc/chat_radio_rows(list/channel_names)
	. = list()
	if(!LAZYLEN(channel_names))
		return
	var/list/seen = list()
	. += list(list("key" = ":h", "label" = "Dept"))
	seen[":h"] = TRUE
	for(var/channel_name in channel_names)
		var/key = get_radio_key_from_channel(channel_name)
		if(!key || seen[key])
			continue
		seen[key] = TRUE
		. += list(list("key" = key, "label" = "[channel_name]"))

/// The prefixes this client's mob can use on the radio: the on channels of its headsets.
/client/proc/chat_radio_options()
	var/list/names = list()
	for(var/obj/item/radio/R as anything in mob?.chat_radio_sets())
		for(var/channel_name in R.channels)
			if(R.channels[channel_name])
				names |= channel_name
	return chat_radio_rows(names)

/// Tells the chat input row which radio prefixes the speaker has.
/client/proc/chat_send_radio_options()
	if(!tgui_panel?.is_ready())
		return
	var/list/rows = chat_radio_options()
	chat_window()?.send_message("chat/radioChannels", list("channels" = rows))
	log_tgui(src, "Chat radio prefixes sent: [length(rows)].", context = "chat_float")
