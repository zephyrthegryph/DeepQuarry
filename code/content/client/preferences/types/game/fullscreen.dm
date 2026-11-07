// Borderless fullscreen for the main window. It is the default: the preference starts on, so a player who never chose gets it. BYOND's
// own is-fullscreen puts the window on the monitor it is on and no further (maximizing a window whose title bar was switched off let
// it spill onto the neighbouring monitor). Login applies every preference before the skin's browsers have loaded, and winsets on the
// main window then stalled the client, so nothing changes until the chat page is ready (chat_layout_sync()).

/datum/preference/toggle/borderless_fullscreen
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "BORDERLESS_FULLSCREEN"
	default_value = TRUE
	savefile_identifier = PREFERENCE_PLAYER

/datum/preference/toggle/borderless_fullscreen/apply_to_client(client/client, value)
	client.fullscreen_apply()

/client
	/// Whether this client's main window was last put into borderless fullscreen by fullscreen_apply().
	var/fullscreen_applied = FALSE

SCHEMA(/client, fullscreen_applied, num())

/// Puts the main window in or out of borderless fullscreen as the preference says, once the chat page is up.
/client/proc/fullscreen_apply()
	if(!prefs)
		return
	if(!tgui_panel?.is_ready())
		log_tgui(src, "Fullscreen change waits for the chat page.", context = "fullscreen")
		return
	var/want = !!prefs.read_preference(/datum/preference/toggle/borderless_fullscreen)
	if(want == !!fullscreen_applied)
		return
	fullscreen_applied = want
	var/params = want ? "is-fullscreen=true" : "is-fullscreen=false;titlebar=true;can-resize=true;is-maximized=true"
	winset(src, SKIN_MAINWINDOW, params)
	log_tgui(src, "Fullscreen -> [want ? "on" : "off"]. winset: [params]", context = "fullscreen")
	dx_winget(src, src, SKIN_MAINWINDOW, "is-fullscreen;is-maximized;screen-pos;screen-size;outer-pos;outer-size", PROC_REF(fullscreen_measured))

/// dx_winget() callback for fullscreen_apply(): records where the window ended up, so a window that spills past its monitor shows in the log.
/client/proc/fullscreen_measured(list/result)
	log_tgui(src, "Fullscreen result: [json_encode(result)]", context = "fullscreen")

/client/verb/toggle_fullscreen()
	set name = "toggle-fullscreen"
	set hidden = TRUE // the Menu page and the Borderless fullscreen setting

	prefs?.update_preference_by_type(/datum/preference/toggle/borderless_fullscreen, !prefs.read_preference(/datum/preference/toggle/borderless_fullscreen))
