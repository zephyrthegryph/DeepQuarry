/*!
 * Copyright (c) 2020 Aleksej Komarov
 * SPDX-License-Identifier: MIT
 */

/client/var/datum/tgui_panel/tgui_panel

/**
 * The one UI repair verb: closes stuck TGUI windows, reloads the ones left, and reloads the chat panel.
 * Also lets devs reattach a dev server without relogging, since it reinitializes the windows.
 */
/client/verb/fix_ui()
	set name = "Fix UI"
	set desc = "Use this if the chat panel or a TGUI window is broken or stuck on your screen."
	set category = VERB_CAT_OOC_DEBUG
	log_tgui(src, "Started fixing.", context = "verb/fix_ui")

	SStgui.close_user_uis(mob)
	refresh_tgui()
	nuke_chat()
	to_chat(src, span_notice("UI reloaded. If something is still broken, try again or ask an admin."))

/client/proc/nuke_chat()
	// Catch all solution (kick the whole thing in the pants)
	winset(src, SKIN_LEGACY_OUTPUT_SELECTOR, "left=output_legacy")
	if(!tgui_panel || !istype(tgui_panel))
		log_tgui(src, "tgui_panel datum is missing",
			context = "verb/fix_ui")
		rel_set(src, nameof(tgui_panel), new /datum/tgui_panel(src))
	tgui_panel.initialize(force = TRUE)
	// Force show the panel to see if there are any errors
	winset(src, SKIN_LEGACY_OUTPUT_SELECTOR, "left=output_browser")

	if(prefs?.read_preference(/datum/preference/toggle/browser_dev_tools))
		winset(src, null, "browser-options=[DEFAULT_CLIENT_BROWSER_OPTIONS],devtools")

/// Reinitializes every open TGUI window of this client.
/client/proc/refresh_tgui()
	var/alist/windows = session?.tgui_windows || alist()
	for(var/window_id in windows)
		var/datum/tgui_window/window = windows[window_id]
		window.reinitialize()

