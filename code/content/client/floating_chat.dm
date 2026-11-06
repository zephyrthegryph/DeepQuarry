// Floating chat. The chat pane (outputwindow) is hosted either by the right-hand split
// (rpane.rpanewindow, docked) or by the chat_float window's child control (floating, the
// default). Moving the pane re-parents the same browser control, so the chat page and its
// scrollback are the same page either way. The float window's position and size are saved by
// the client (saved-params in skin.dmf); this file only decides where the pane lives.
// Typing goes through the chat page's input row (tgui-panel/input), whose messages the panel forwards to
// tgui_say (see tgui_panel.dm), so the speech path is the popup's. The T/M/O hotkeys focus the row while
// the chat floats; docked, or with the inline-input preference off, they open the tgui_say popup.

#define CHAT_FLOAT_DEFAULT_POS "60,60"
#define CHAT_FLOAT_DEFAULT_SIZE "480x300"
/// Pixels of the float window that must stay on the screen, or it is put back.
#define CHAT_FLOAT_MIN_VISIBLE 48

/// Whether the chat is a floating window (default) or docked in the right-hand pane.
/datum/preference/toggle/chat_floating
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "CHAT_FLOATING"
	default_value = TRUE
	savefile_identifier = PREFERENCE_PLAYER

/datum/preference/toggle/chat_floating/apply_to_client(client/client, value)
	client.chat_apply_layout(value)

/// Whether the T/M/O hotkeys focus the chat page's input row (while the chat floats) instead of opening the popup.
/datum/preference/toggle/chat_inline_input
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "CHAT_INLINE_INPUT"
	default_value = TRUE
	savefile_identifier = PREFERENCE_PLAYER

/// Sends a speech hotkey to the chat input row. Returns TRUE when the row took it, FALSE to open the popup instead.
/client/proc/chat_focus_input(channel)
	if(channel != SAY_CHANNEL && channel != ME_CHANNEL && channel != OOC_CHANNEL && channel != LOOC_CHANNEL)
		return FALSE
	if(!prefs?.read_preference(/datum/preference/toggle/chat_floating) || !prefs.read_preference(/datum/preference/toggle/chat_inline_input))
		return FALSE
	if(!tgui_panel?.is_ready())
		return FALSE
	tgui_panel.window.send_message("chat/focusInput", list("channel" = channel))
	winset(src, SKIN_CHAT_BROWSER, "focus=true")
	log_tgui(src, "Chat input focused in [channel].", context = "chat_float")
	return TRUE

/// The OOC hotkey: the input row in OOC while the chat floats, else the OOC prompt.
/client/verb/ooc_input()
	set name = ".dq-ooc-input"
	set hidden = TRUE

	if(chat_focus_input(OOC_CHANNEL))
		return
	winset(src, null, "command=ooc")

/// Hosts the chat pane in the float window (floating) or the right-hand split (docked).
/client/proc/chat_apply_layout(floating)
	if(floating)
		winset(src, null, list2params(list(
			"[SKIN_RPANE_SPLIT].right" = "",
			"[SKIN_CHAT_FLOAT_HOST].left" = SKIN_OUTPUT_PANE,
			"[SKIN_CHAT_FLOAT_WINDOW].is-visible" = "true",
		)))
		dx_winget(src, src, SKIN_CHAT_FLOAT_WINDOW, "pos;size", PROC_REF(chat_float_measured))
	else
		winset(src, null, list2params(list(
			"[SKIN_CHAT_FLOAT_WINDOW].is-visible" = "false",
			"[SKIN_CHAT_FLOAT_HOST].left" = "",
			"[SKIN_RPANE_SPLIT].right" = SKIN_OUTPUT_PANE,
		)))
	log_tgui(src, "Chat layout: [floating ? "floating" : "docked"].", context = "chat_float")

/// dx_winget() callback: asks for the screen size once the float window's place is known.
/client/proc/chat_float_measured(window_params)
	var/list/placed = params2list(window_params)
	dx_winget(src, src, SKIN_MAINWINDOW, "screen-size", PROC_REF(chat_float_clamp), placed["pos"], placed["size"])

/// dx_winget() callback: puts the float window back when too little of it is on the screen.
/client/proc/chat_float_clamp(screen_size, pos, size)
	var/list/screen = splittext("[screen_size]", "x")
	var/list/at = splittext("[pos]", ",")
	var/list/extent = splittext("[size]", "x")
	if(length(screen) != 2 || length(at) != 2 || length(extent) != 2)
		log_tgui(src, "Chat float clamp skipped: screen=[screen_size] pos=[pos] size=[size].", context = "chat_float")
		return
	var/screen_w = text2num(screen[1])
	var/screen_h = text2num(screen[2])
	var/x = text2num(at[1])
	var/y = text2num(at[2])
	var/w = text2num(extent[1])
	var/h = text2num(extent[2])
	if(isnull(screen_w) || isnull(screen_h) || isnull(x) || isnull(y) || isnull(w) || isnull(h))
		return
	if(x > screen_w - CHAT_FLOAT_MIN_VISIBLE || y > screen_h - CHAT_FLOAT_MIN_VISIBLE || y < -CHAT_FLOAT_MIN_VISIBLE || w <= 0 || h <= 0)
		log_tgui(src, "Chat float window off screen (pos [pos], size [size], screen [screen_size]); reset.", context = "chat_float")
		chat_float_reset()

/// Puts the float window at its default place and size.
/client/proc/chat_float_reset()
	winset(src, SKIN_CHAT_FLOAT_WINDOW, list2params(list(
		"pos" = CHAT_FLOAT_DEFAULT_POS,
		"size" = CHAT_FLOAT_DEFAULT_SIZE,
		"is-maximized" = "false",
		"is-minimized" = "false",
	)))

/client/verb/toggle_floating_chat()
	set name = "toggle-floating-chat"
	set category = VERB_CAT_OOC_CLIENT_SETTINGS

	prefs?.update_preference_by_type(/datum/preference/toggle/chat_floating, !prefs.read_preference(/datum/preference/toggle/chat_floating))

/client/verb/dock_chat()
	set name = "dock-chat"
	set category = VERB_CAT_OOC_CLIENT_SETTINGS

	prefs?.update_preference_by_type(/datum/preference/toggle/chat_floating, FALSE)

/// Floats the chat if needed and puts its window back at the default place, for a window that got lost.
/client/verb/reset_chat_window()
	set name = "reset-chat-window"
	set category = VERB_CAT_OOC_CLIENT_SETTINGS

	chat_float_reset()
	if(prefs?.read_preference(/datum/preference/toggle/chat_floating))
		chat_apply_layout(TRUE)
	else
		prefs?.update_preference_by_type(/datum/preference/toggle/chat_floating, TRUE)
