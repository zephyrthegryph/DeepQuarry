/*!
 * Copyright (c) 2020 Aleksej Komarov
 * SPDX-License-Identifier: MIT
 */

/client/var/datum/tgui_panel/tgui_panel

/**
 * tgui panel / chat troubleshooting verb
 */
/client/verb/fix_tgui_panel()
	set name = "Fix chat"
	set category = VERB_CAT_OOC_DEBUG
	var/action
	log_tgui(src, "Started fixing.", context = "verb/fix_tgui_panel")

	nuke_chat()

	// BYOND's native alert() instead of tg_alert (which used a
	// browser-rendered modal). Native alert is safe here even when the
	// TGUI panel is broken (the whole point of this verb).
	action = alert(src.mob, "Did that work?", "", "Yes", "No, switch to old ui") // ALLOW(scheduler): repairs a broken tgui panel, so it cannot use a tgui prompt
	if (action == "No, switch to old ui")
		winset(src, SKIN_LEGACY_OUTPUT_SELECTOR, "left=output_legacy")
		log_tgui(src, "Failed to fix.", context = "verb/fix_tgui_panel")

/client/proc/nuke_chat()
	// Catch all solution (kick the whole thing in the pants)
	winset(src, SKIN_LEGACY_OUTPUT_SELECTOR, "left=output_legacy")
	if(!tgui_panel || !istype(tgui_panel))
		log_tgui(src, "tgui_panel datum is missing",
			context = "verb/fix_tgui_panel")
		tgui_panel = new /datum/tgui_panel(src) // ALLOW(ownership): /client is not a datum and is the one owner of this by design
	tgui_panel.initialize(force = TRUE)
	// Force show the panel to see if there are any errors
	winset(src, SKIN_LEGACY_OUTPUT_SELECTOR, "left=output_browser")

	if(prefs?.read_preference(/datum/preference/toggle/browser_dev_tools))
		winset(src, null, "browser-options=[DEFAULT_CLIENT_BROWSER_OPTIONS],devtools")

/client/verb/refresh_tgui()
	set name = "Refresh TGUI"
	set category = VERB_CAT_OOC_DEBUG

	for(var/window_id in tgui_windows)
		var/datum/tgui_window/window = tgui_windows[window_id]
		window.reinitialize()

