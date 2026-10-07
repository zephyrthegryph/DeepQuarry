/*!
 * External tgui definitions, such as src_object APIs.
 *
 * Copyright (c) 2020 Aleksej Komarov
 * SPDX-License-Identifier: MIT
 */

/**
 * public
 *
 * Used to open and update UIs.
 * If this proc is not implemented properly, the UI will not update correctly.
 *
 * required user mob The mob who opened/is using the UI.
 * optional ui datum/tgui The UI to be updated, if it exists.
 * optional parent_ui datum/tgui A parent UI that, when closed, closes this UI as well.
 */

/datum/proc/tgui_interact(mob/user, datum/tgui/ui = null, datum/tgui/parent_ui = null, custom_state = null)
	// The type's declared interface entries open the window.
	return ui_open(src, user, ui, parent_ui, custom_state)

/// TRUE when `user` is a ghost looking at a window it may not act in: the read-only view (an admin's interactive window is not one).
/proc/tgui_is_observer_view(mob/user, datum/tgui/ui)
	return isobserver(user) && (!ui || ui.status != STATUS_INTERACTIVE)

/**
 * public
 *
 * Data to be sent to the UI.
 * This must be implemented for a UI to work.
 *
 * required user mob The mob interacting with the UI.
 *
 * return list Data to be sent to the UI.
 */
/datum/proc/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	. = list()
	if(isatom(src))
		var/atom/A = src
		caps_ui_data(A, user, .) // capabilities add theirs (code/datums/capabilities/)
	present_tgui_data(src, user, ., tgui_is_observer_view(user, ui)) // the type's ui_data(A) output and its engine capabilities' data (code/engine/present/outputs.dm)

/**
 * public
 *
 * Static Data to be sent to the UI.
 *
 * Static data differs from normal data in that it's large data that should be
 * sent infrequently. This is implemented optionally for heavy uis that would
 * be sending a lot of redundant data frequently. Gets squished into one
 * object on the frontend side, but the static part is cached.
 *
 * required user mob The mob interacting with the UI.
 *
 * return list Statuic Data to be sent to the UI.
 */
/datum/proc/tgui_static_data(mob/user)
	return list()

/**
 * public
 *
 * The om change channels that raise a coalesced push to this datum's open UIs.
 */
/datum/proc/tgui_change_mask()
	return CHANGE_GENERIC_MASK

/**
 * public
 *
 * Forces an update on static data. Should be done manually whenever something
 * happens to change static data.
 *
 * required user the mob currently interacting with the ui
 * optional ui ui to be updated
 */
/datum/proc/update_tgui_static_data(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	// If there was no ui to update, there's no static data to update either.
	if(!ui)
		ui = SStgui.get_open_ui(user, src)
	if(ui)
		ui.send_full_update()

/**
 * public
 *
 * Will force an update on static data for all viewers.
 * Should be done manually whenever something happens to
 * change static data.
 */
/datum/proc/update_static_data_for_all_viewers()
	for (var/datum/tgui/window as anything in open_tguis)
		window.send_full_update()

/**
 * public
 *
 * Called on a UI when the UI receieves a href.
 * Think of this as Topic().
 *
 * required action string The action/button that has been invoked by the user.
 * required params list A list of parameters attached to the button.
 *
 * return bool If the UI should be updated or not.
 */
/datum/proc/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	SHOULD_CALL_PARENT(TRUE)
	PUBLISH_LEGACY(src, /datum/notice/ui_act, ui.user, action)
	// If UI is not interactive or usr calling Topic is not the UI user, bail.
	if(!ui || ui.status != STATUS_INTERACTIVE)
		if(ui && isobserver(ui.user))
			log_world("UI: [ui.user] (observer) pressed [action] in [src.type]'s window: refused, an observer's window is read-only")
		return TRUE
	// A window button is an op with a ui_act() binding: it runs first (code/engine/present/outputs.dm, present_ui_act()).
	var/datum/op_result/button = present_ui_act(src, ui.user, action, params, ui)
	if(button)
		return TRUE
	// A named action proc, ui_<action>(mob/user, named args...) (code/datums/capabilities/ui_actions.dm).
	var/list/named = ui_named_dispatch(src, action, params, ui)
	if(named)
		return named[2]
	// The one action every window has: the layout toggle (tgui LayoutToggle) writes the viewer's layout preference
	// (write_preference() validates the value).
	if(action == "change_ui_state")
		var/new_state = params?["new_state"]
		if(istext(new_state) && length(new_state) <= 64)
			ui.user?.client?.prefs.write_preference(GLOB.preference_entries[/datum/preference/choiced/tgui_layout], new_state)
		return FALSE
	return FALSE // no op, capability or named proc answers `action`

/**
 * public
 *
 * Called on a UI when the UI crashed.
 *
 * required payload list A list of the payload supposed to be set on the regular UI.
 */
/datum/proc/tgui_fallback(list/payload, mob/user)
	SHOULD_CALL_PARENT(TRUE)

/**
 * public
 *
 * Called on an object when a tgui object is being created, allowing you to
 * push various assets to tgui, for examples spritesheets.
 *
 * return list List of asset datums or file paths.
 */
/datum/proc/ui_assets(mob/user)
	return list()

/**
 * private
 *
 * The UI's host object (usually src_object).
 * This allows modules/datums to have the UI attached to them,
 * and be a part of another object.
 */
/datum/proc/tgui_host(mob/user)
	return src // Default src.

/**
 * private
 *
 * The UI's state controller to be used for created uis
 * This is a proc over a var for memory reasons
 */
/datum/proc/tgui_state(mob/user)
	// interface(state =, rights =): the state the window's declaration carries, else ui_rights (an admin panel); an instance-dependent
	// state overrides this.
	var/datum/tgui_state/declared = interface_state(src)
	if(declared)
		return declared
	if(ui_rights)
		return ADMIN_STATE(ui_rights)
	return GLOB.tgui_default_state

/**
 * global
 *
 * Associative list of JSON-encoded shared states that were set by
 * tgui clients.
 */
/datum/var/tmp/list/tgui_shared_states

/**
 * global
 *
 * Tracks open UIs for a user.
 */
/mob/var/list/tgui_open_uis = list()

/**
 * global
 *
 * Tracks open windows for a user.
 */
/client/var/list/tgui_windows = list()

/// Last successfully revealed native size and position by interface.
/client/var/list/tgui_resolved_geometries
/// The all-interface HTTP chunk manifest has been dispatched to one browser
/// shell for this client. Chromium's cache is shared by that client's shells.
/client/var/tgui_chunk_warm_started = FALSE

/**
 * global
 *
 * TRUE if cache was reloaded by tgui dev server at least once.
 */
/client/var/tgui_cache_reloaded = FALSE

/**
 * public
 *
 * Called on a UI's object when the UI is closed, not to be confused with
 * client/verb/uiclose(), which closes the ui window
 */
/datum/proc/tgui_close(mob/user)

/**
 * verb
 *
 * Used by a client to fix broken TGUI windows caused by opening a UI window before assets load.
 * Probably not very performant and forcibly destroys a bunch of windows, so it has some warnings attached.
 * Conveniently, also allows devs to force a dev server reattach without relogging, since it yeets windows.
 */
/client/verb/tgui_fix_white()
	set desc = "Only use this if you have a broken TGUI window occupying your screen!"
	set name = "Fix TGUI"
	set category = VERB_CAT_OOC_DEBUG

	if(alert(src, "Only use this verb if you have a white TGUI window stuck on your screen.", "Fix TGUI", "Continue", "Nevermind") != "Continue") // ALLOW(scheduler): fixes broken tgui windows, so it cannot use a tgui prompt
		return

	SStgui.close_user_uis(mob)
	if(alert(src, "Did that fix the problem?", "Fix TGUI", "Yes", "No") == "No") // ALLOW(scheduler): fixes broken tgui windows, so it cannot use a tgui prompt
		SStgui.force_close_all_windows(mob)
		alert(src, "UIs should be fixed now. If not, please cry to your nearest coder.", "Fix TGUI") // ALLOW(scheduler): fixes broken tgui windows, so it cannot use a tgui prompt

/**
 * verb
 *
 * Called by UIs when they are closed.
 * Must be a verb so winset() can call it.
 *
 * required uiref ref The UI that was closed.
 */
/client/verb/tguiclose(window_id as text)
	// Name the verb, and hide it from the user panel.
	set name = "uiclose"
	set hidden = TRUE
	var/mob/user = src?.mob
	if(!user)
		return
	// Close all tgui datums based on window_id.
	SStgui.force_close_window(user, window_id)

/**
 * A few edge cases that need to bypass topic limits currently, comment why!
 *
 * returns TRUE for bypass
 */
/proc/bypass_topic_limit(href_list)
	// Deviation from TG. Our statbrowser has so many commands that logging in as a borg can cause it to rate limit you. This needs fixing eventually.
	// ALLOW(sys_topic_raw_dispatch): the tgui message protocol (tgui=1;type=...), not a datum href action; its messages reach tgui_act().
	if(href_list["window_id"] == SKIN_STAT_BROWSER)
		return TRUE
	// Chunked messages will exceed the limit
	// ALLOW(sys_topic_raw_dispatch): the tgui message protocol (tgui=1;type=...), not a datum href action; its messages reach tgui_act().
	if(href_list["tgui"] && href_list["type"] == "payloadChunk")
		return TRUE
	return FALSE

/**
 * Middleware for /client/Topic.
 *
 * return bool Whether the topic is passed (TRUE), or cancelled (FALSE).
 */
/proc/tgui_Topic(href_list, mob/user)
	// Skip non-tgui topics
	// ALLOW(sys_topic_raw_dispatch): the tgui message protocol (tgui=1;type=...), not a datum href action; its messages reach tgui_act().
	if(!href_list["tgui"])
		return FALSE
	var/type = href_list["type"]
	// Unconditionally collect tgui logs
	if(type == "log")
		var/context = href_list["window_id"]
		// ALLOW(sys_topic_raw_dispatch): the tgui message protocol (tgui=1;type=...), not a datum href action; its messages reach tgui_act().
		if (href_list["ns"])
			context += " ([href_list["ns"]])"
		log_tgui(user, href_list["message"],
			context = context)
	// Reload all tgui windows
	if(type == "cacheReloaded")
		#ifdef DEBUG
		if(user.client.address != "127.0.0.1" && user.client.address != "::1")
			return TRUE
		// Every development build may assign new async chunk ids. Refresh the
		// manifest and registrations before any browser is told to reload.
		if(!SStgui.reload_development_chunks())
			return TRUE
		#else
		if(user.client.tgui_cache_reloaded)
			return TRUE
		#endif
		// Mark as reloaded
		user.client.tgui_cache_reloaded = TRUE
		// Notify windows
		var/list/windows = user.client.tgui_windows
		for(var/window_id in windows)
			var/datum/tgui_window/window = windows[window_id]
			if (window.status == TGUI_WINDOW_READY)
				window.on_message(type, null, href_list)
		return TRUE
	// Locate window
	var/window_id = href_list["window_id"]
	var/datum/tgui_window/window
	if(window_id)
		window = user.client.tgui_windows[window_id]
		if(!window)
			log_tgui(user,
				"Error: Couldn't find the window datum, force closing.",
				context = window_id)
			SStgui.force_close_window(user, window_id)
			return TRUE

	// Decode payload
	var/payload
	// ALLOW(sys_topic_raw_dispatch): the tgui message protocol (tgui=1;type=...), not a datum href action; its messages reach tgui_act().
	if(href_list["payload"])
		var/payload_text = href_list["payload"]

		if (!rustg_json_is_valid(payload_text))
			log_tgui(user, "Error: Invalid JSON")
			return TRUE

		payload = json_decode(payload_text)

	// Pass message to window
	if(window)
		window.on_message(type, payload, href_list)
	return TRUE
