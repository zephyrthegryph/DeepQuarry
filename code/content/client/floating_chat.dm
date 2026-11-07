// Pinned and floating chat. The chat pane (outputwindow) is hosted by the right-hand split (rpane.rpanewindow), at its
// bottom (the default, the skin's own layout) or its top with the stat panel (statwindow) taking the rest of the column, or
// by the chat_float window's child control (floating). Moving the pane re-parents the same browser control, so the chat page
// and its scrollback are the same page in every layout. The float window has no title bar: the chat page draws a header strip
// that drags it, a grip that resizes it, and buttons that pin it (tgui-panel/layout); it reports the pin and the share of the
// column over the panel's messages (layout/pin, layout/share), and this file decides where the pane lives.
// Typing goes through the chat page's input row (tgui-panel/input), whose messages the panel forwards to
// tgui_say (see tgui_panel.dm), so the speech path is the popup's. The T/M/O hotkeys focus the row; with the
// inline-input preference off they open the tgui_say popup.

/// Where the chat pane is: the bottom or top of the right-hand column (pinned), or its own window.
#define CHAT_MODE_BOTTOM "bottom"
#define CHAT_MODE_TOP "top"
#define CHAT_MODE_FLOAT "float"
#define CHAT_DOCK_BOTTOM_RIGHT "Bottom right"
#define CHAT_DOCK_TOP_RIGHT "Top right"
/// The pinned chat's share of the right-hand column, in percent.
#define CHAT_SHARE_DEFAULT 40
#define CHAT_SHARE_MIN 20
#define CHAT_SHARE_MAX 80
#define CHAT_CHANGE_NONE 0
#define CHAT_CHANGE_SPLITTER 1
#define CHAT_CHANGE_LAYOUT 2

#define CHAT_FLOAT_DEFAULT_POS "60,60"
#define CHAT_FLOAT_DEFAULT_SIZE "560x420"
/// Pixels of the float window that must stay on the screen, or it is put back.
#define CHAT_FLOAT_MIN_VISIBLE 48

/// Whether the chat is a floating window or pinned to the right-hand column (default).
/datum/preference/toggle/chat_floating
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "CHAT_FLOATING"
	default_value = FALSE
	savefile_identifier = PREFERENCE_PLAYER

/datum/preference/toggle/chat_floating/apply_to_client(client/client, value)
	client.chat_layout_pref_changed()

/// Which end of the right-hand column the pinned chat takes; the stat panel has the rest.
/datum/preference/choiced/chat_dock_side
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "CHAT_DOCK_SIDE"
	savefile_identifier = PREFERENCE_PLAYER

TYPE_TABLE(/datum/preference/choiced/chat_dock_side, pref_choices, list(CHAT_DOCK_BOTTOM_RIGHT, CHAT_DOCK_TOP_RIGHT))

/datum/preference/choiced/chat_dock_side/create_default_value()
	return CHAT_DOCK_BOTTOM_RIGHT

/datum/preference/choiced/chat_dock_side/apply_to_client(client/client, value)
	client.chat_layout_pref_changed()

/// The share of the right-hand column the pinned chat takes, in percent. The chat page reports it when the player drags the splitter.
/datum/preference/numeric/chat_share
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "CHAT_SHARE"
	savefile_identifier = PREFERENCE_PLAYER
	minimum = CHAT_SHARE_MIN
	maximum = CHAT_SHARE_MAX

/datum/preference/numeric/chat_share/create_default_value()
	return CHAT_SHARE_DEFAULT

/datum/preference/numeric/chat_share/apply_to_client(client/client, value)
	client.chat_layout_pref_changed()

/// Where the chat pane is on this client, and the share it has: the skin starts bottom right with the default share.
/client/var/chat_layout_mode = CHAT_MODE_BOTTOM
/client/var/chat_layout_share = CHAT_SHARE_DEFAULT

/// Whether the T/M/O hotkeys focus the chat page's input row instead of opening the popup.
/datum/preference/toggle/chat_inline_input
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "CHAT_INLINE_INPUT"
	default_value = TRUE
	savefile_identifier = PREFERENCE_PLAYER

/// Sends a speech hotkey to the chat input row. Returns TRUE when the row took it, FALSE to open the popup instead.
/client/proc/chat_focus_input(channel)
	if(channel != SAY_CHANNEL && channel != ME_CHANNEL && channel != OOC_CHANNEL && channel != LOOC_CHANNEL)
		return FALSE
	if(!prefs?.read_preference(/datum/preference/toggle/chat_inline_input))
		return FALSE
	if(!tgui_panel?.is_ready())
		return FALSE
	tgui_panel.window.send_message("chat/focusInput", list("channel" = channel))
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

/// The mode the preferences ask for.
/proc/chat_mode_for(floating, side)
	if(floating)
		return CHAT_MODE_FLOAT
	return (side == CHAT_DOCK_TOP_RIGHT) ? CHAT_MODE_TOP : CHAT_MODE_BOTTOM

/// A chat share held to what the column can show.
/proc/chat_share_clamped(share)
	if(!isnum(share))
		return CHAT_SHARE_DEFAULT
	return clamp(round(share), CHAT_SHARE_MIN, CHAT_SHARE_MAX)

/// The splitter of rpane.rpanewindow (the percent its first pane takes) for a chat share: the chat is the first pane at the top and the second at the bottom.
/proc/chat_splitter_for(mode, share)
	share = chat_share_clamped(share)
	return (mode == CHAT_MODE_TOP) ? share : 100 - share

/// The share of the column the chat takes for a splitter position (the inverse of chat_splitter_for()).
/proc/chat_share_for_splitter(mode, splitter)
	return chat_share_clamped((mode == CHAT_MODE_TOP) ? splitter : 100 - splitter)

/// The winset text that takes the chat pane from the layout `from` to the layout `mode`, one call, in order. The stat panel is the
/// right-column pane that is not the chat: it keeps its place when only the chat pane comes or goes (bottom and float), and is
/// re-seated when the chat takes or leaves the top.
/proc/chat_layout_params(mode, share, from = CHAT_MODE_BOTTOM)
	var/list/steps = list()
	if(from == CHAT_MODE_FLOAT)
		steps += "[SKIN_CHAT_FLOAT_WINDOW].is-visible=false"
		steps += "[SKIN_CHAT_FLOAT_HOST].left="
	if(from == CHAT_MODE_TOP || mode == CHAT_MODE_TOP)
		steps += "[SKIN_RPANE_SPLIT].left="
		steps += "[SKIN_RPANE_SPLIT].right="
	switch(mode)
		if(CHAT_MODE_TOP)
			steps += "[SKIN_RPANE_SPLIT].left=[SKIN_OUTPUT_PANE]"
			steps += "[SKIN_RPANE_SPLIT].right=[SKIN_STAT_PANE]"
			steps += "[SKIN_RPANE_SPLIT].splitter=[chat_splitter_for(mode, share)]"
		if(CHAT_MODE_BOTTOM)
			if(from == CHAT_MODE_TOP)
				steps += "[SKIN_RPANE_SPLIT].left=[SKIN_STAT_PANE]"
			steps += "[SKIN_RPANE_SPLIT].right=[SKIN_OUTPUT_PANE]"
			steps += "[SKIN_RPANE_SPLIT].splitter=[chat_splitter_for(mode, share)]"
		if(CHAT_MODE_FLOAT)
			if(from == CHAT_MODE_TOP)
				steps += "[SKIN_RPANE_SPLIT].left=[SKIN_STAT_PANE]"
			else
				steps += "[SKIN_RPANE_SPLIT].right="
			steps += "[SKIN_CHAT_FLOAT_HOST].left=[SKIN_OUTPUT_PANE]"
			steps += "[SKIN_CHAT_FLOAT_WINDOW].is-visible=true"
	return jointext(steps, ";")

/// What a layout request does: CHAT_CHANGE_NONE, _SPLITTER (the pane stays, its share moves) or _LAYOUT (the pane moves).
/proc/chat_layout_change(mode, share, applied_mode, applied_share)
	if(mode != applied_mode)
		return CHAT_CHANGE_LAYOUT
	if(mode != CHAT_MODE_FLOAT && chat_share_clamped(share) != chat_share_clamped(applied_share))
		return CHAT_CHANGE_SPLITTER
	return CHAT_CHANGE_NONE

/// A layout preference changed. Login applies every preference before the skin's browsers have loaded, and moving the chat pane then
/// stalled the client (the stat panel, chat and tgui windows never finished opening), so nothing moves until the chat page is ready;
/// its ready message runs chat_layout_sync() and so applies what the preferences say by then.
/client/proc/chat_layout_pref_changed()
	if(tgui_panel?.is_ready())
		chat_layout_sync()
	else
		log_tgui(src, "Chat layout change waits for the chat page.", context = "chat_float")

/// Puts the chat pane where the preferences want it and tells the chat page which layout it is in. The pane is left alone when it is
/// there already (a chat page that reloads reports ready again, and a re-parent would reload it once more).
/client/proc/chat_layout_sync()
	if(!prefs)
		return
	var/mode = chat_mode_for(prefs.read_preference(/datum/preference/toggle/chat_floating), prefs.read_preference(/datum/preference/choiced/chat_dock_side))
	var/share = chat_share_clamped(prefs.read_preference(/datum/preference/numeric/chat_share))
	switch(chat_layout_change(mode, share, chat_layout_mode, chat_layout_share))
		if(CHAT_CHANGE_LAYOUT)
			winset(src, null, chat_layout_params(mode, share, chat_layout_mode))
			log_tgui(src, "Chat layout: [chat_layout_mode] -> [mode], share [share].", context = "chat_float")
			chat_layout_mode = mode
			chat_layout_share = share
			if(mode == CHAT_MODE_FLOAT)
				dx_winget(src, src, SKIN_CHAT_FLOAT_WINDOW, "pos;size", PROC_REF(chat_float_measured))
		if(CHAT_CHANGE_SPLITTER)
			winset(src, SKIN_RPANE_SPLIT, "splitter=[chat_splitter_for(mode, share)]")
			log_tgui(src, "Chat share: [chat_layout_share] -> [share].", context = "chat_float")
			chat_layout_share = share
	tgui_panel?.window?.send_message("chat/layout", list("mode" = chat_layout_mode, "share" = chat_layout_share))

/// The chat page pins or floats the chat (its buttons, or a drag that ended near the right edge).
/client/proc/chat_pin(mode)
	if(mode != CHAT_MODE_TOP && mode != CHAT_MODE_BOTTOM && mode != CHAT_MODE_FLOAT)
		log_tgui(src, "Chat pin refused: unknown mode [mode].", context = "chat_float")
		return
	log_tgui(src, "Chat pin asked: [mode].", context = "chat_float")
	if(mode == CHAT_MODE_FLOAT)
		prefs?.update_preference_by_type(/datum/preference/toggle/chat_floating, TRUE)
		return
	// The side first, then the float flag: the flag's apply is the one that moves the pane to the side.
	prefs?.update_preference_by_type(/datum/preference/choiced/chat_dock_side, (mode == CHAT_MODE_TOP) ? CHAT_DOCK_TOP_RIGHT : CHAT_DOCK_BOTTOM_RIGHT)
	prefs?.update_preference_by_type(/datum/preference/toggle/chat_floating, FALSE)

/// The chat page measured its share of the right-hand column after the player moved the splitter.
/client/proc/chat_report_share(share)
	if(chat_layout_mode == CHAT_MODE_FLOAT || !isnum(share))
		return
	share = chat_share_clamped(share)
	if(share == chat_layout_share)
		return
	log_tgui(src, "Chat share reported: [chat_layout_share] -> [share].", context = "chat_float")
	chat_layout_share = share // the splitter is there already; the preference write must not move it again
	prefs?.update_preference_by_type(/datum/preference/numeric/chat_share, share)

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
	chat_pin(CHAT_MODE_FLOAT)
	chat_layout_sync()
