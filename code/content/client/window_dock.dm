// The window dock (doc/rewrite/proposals/window_system.md): any pooled tgui window can be docked into the right-hand column. A docked
// UI keeps its own BYOND window, page and /datum/tgui (routing is unchanged); it only loses its OS chrome, and the stat panel page frames
// it (titlebar, tabs, collapse, float, close) and places it over a placeholder (tgui-panel/statpanel/windowDock.ts is the layout).
//
// The server's part: which UIs are docked (config.window.docked), which are hidden (collapsed or behind a tab: no data pushes while
// hidden, one full update when shown again), the messages between the UI pages, the stat panel and the UIs, and the saved layout.

/// The saved layout's limit in characters (the stat panel trims to this, windowDock.ts DOCK_SAVE_MAX).
#define WINDOW_DOCK_LAYOUT_MAX 8000

/// The player's dock layout: interface name -> placement, as the stat panel saves it (JSON). The server reads only each entry's `dock`.
/datum/preference/text/window_layout
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "WINDOW_LAYOUT"
	savefile_identifier = PREFERENCE_PLAYER
	maximum_value_length = WINDOW_DOCK_LAYOUT_MAX
	should_strip_html = FALSE

/datum/preference/text/window_layout/create_default_value()
	return ""

/// The client's dock, made on first use.
/proc/window_dock_of(client/player)
	RETURN_TYPE(/datum/window_dock)
	if(!player)
		return null
	if(!player.window_dock)
		rel_set(player, nameof(/client::window_dock), new /datum/window_dock(player))
	return player.window_dock

/datum/window_dock
	/// The client whose windows these are: a one-sided back view (the client owns the dock).
	var/client/owner
	/// Interface name -> TRUE for the interfaces the saved layout docks, or null before it was read.
	var/list/wants_cache

/datum/window_dock/New(client/owner)
	rel_set(src, nameof(owner), owner)

CAPABILITIES(/datum/window_dock)
	ref_one(nameof(owner))

/// The client using the dock.
/datum/window_dock/proc/owner() as /client
	return owner

/// The docked UIs of this client that are open now.
/datum/window_dock/proc/docked_uis()
	. = list()
	var/client/player = owner()
	for(var/window_id in player?.session?.tgui_windows)
		var/datum/tgui_window/window = player.session.tgui_windows[window_id]
		var/datum/tgui/ui = window?.locked_by()
		if(ui?.docked && !ui.closing)
			. += ui

/// The docked UI in window `window_id` of this client, or null (the panel's ids are never trusted further than this).
/datum/window_dock/proc/docked_ui(window_id)
	var/client/player = owner()
	if(!istext(window_id) || !player?.session)
		return null
	var/datum/tgui_window/window = player.session.tgui_windows[window_id]
	var/datum/tgui/ui = window?.locked_by()
	if(!ui?.docked || ui.closing || ui.user?.client != player)
		return null
	return ui

/// Whether the saved layout docks `interface` when it opens.
/datum/window_dock/proc/wants(interface)
	if(isnull(wants_cache))
		wants_cache = window_dock_wanted(owner()?.prefs?.read_preference(/datum/preference/text/window_layout))
	return !!wants_cache[interface]

/// The interfaces a saved layout's text docks, as an interface-keyed list.
/proc/window_dock_wanted(text)
	. = list()
	if(!istext(text) || !length(text))
		return
	var/list/layout = safe_json_decode(text)
	if(!islist(layout))
		return
	for(var/interface in layout)
		var/list/place = layout[interface]
		if(istext(interface) && islist(place) && place["dock"])
			.[interface] = TRUE

/// The stat panel's message for the dock.
/datum/window_dock/proc/panel_message(type, list/payload)
	switch(type)
		if("WM-Ready")
			send_init()
		if("WM-View")
			set_hidden(islist(payload) ? payload["hidden"] : null)
		if("WM-Float")
			var/datum/tgui/ui = docked_ui(payload?["id"])
			if(ui)
				undock(ui)
		if("WM-Close")
			var/datum/tgui/ui = docked_ui(payload?["id"])
			ui?.close()
		if("WM-Save")
			save(payload?["layout"])

/// Tells a (re)loaded panel the saved layout and the windows docked now.
/datum/window_dock/proc/send_init()
	var/client/player = owner()
	if(!player?.stat_panel?.is_ready())
		return
	var/list/windows = list()
	for(var/datum/tgui/ui as anything in docked_uis())
		windows += list(ui.dock_entry())
	player.stat_panel.send_message("wm/init", list(
		"saved" = player.prefs?.read_preference(/datum/preference/text/window_layout) || "",
		"windows" = windows,
	))

/// The panel reports which docked windows are off screen: they stop getting data until shown again.
/datum/window_dock/proc/set_hidden(list/hidden)
	var/list/hidden_set = list()
	for(var/window_id in hidden)
		if(istext(window_id))
			hidden_set[window_id] = TRUE
	for(var/datum/tgui/ui as anything in docked_uis())
		ui.dock_hide(!!hidden_set[ui.window()?.id])

/// Keeps the layout the panel saved.
/datum/window_dock/proc/save(text)
	var/client/player = owner()
	if(!istext(text) || length(text) > WINDOW_DOCK_LAYOUT_MAX || !player?.prefs)
		return
	wants_cache = window_dock_wanted(text)
	if(text == player.prefs.read_preference(/datum/preference/text/window_layout))
		return
	player.prefs.update_preference_by_type(/datum/preference/text/window_layout, text)

/// Docks `ui` (its page asked: the dock button or a drop on the column).
/datum/window_dock/proc/dock(datum/tgui/ui)
	if(!ui.dockable() || ui.docked)
		return FALSE
	ui.docked = TRUE
	if(wants_cache)
		wants_cache[ui.interface] = TRUE
	ui.apply_dock_chrome()
	log_tgui(owner(), "Window dock: [ui.interface] docked.", window = ui.window())
	ui.send_full_update()
	return TRUE

/// Floats a docked `ui`: its chrome comes back and its page places itself where it last floated.
/datum/window_dock/proc/undock(datum/tgui/ui)
	if(!ui.docked)
		return FALSE
	ui.docked = FALSE
	if(wants_cache)
		wants_cache -= ui.interface
	ui.apply_dock_chrome()
	ui.dock_hide(FALSE)
	owner()?.stat_panel?.send_message("wm/close", list("id" = ui.window()?.id))
	log_tgui(owner(), "Window dock: [ui.interface] floated.", window = ui.window())
	ui.send_full_update()
	return TRUE

/// A docked UI's page is up: the panel frames it.
/datum/window_dock/proc/window_ready(datum/tgui/ui)
	if(!ui.docked)
		return
	owner()?.stat_panel?.send_message("wm/open", ui.dock_entry())

/// A docked UI closed: the panel drops it and the pooled window gets its chrome back for its next owner.
/datum/window_dock/proc/window_closed(datum/tgui/ui)
	ui.docked = FALSE
	ui.view_hidden = FALSE
	ui.apply_dock_chrome()
	owner()?.stat_panel?.send_message("wm/close", list("id" = ui.window()?.id))

/// The pooled window's OS chrome: none while docked (the panel frames it), the player's own while floating.
/datum/tgui/proc/apply_dock_chrome()
	var/client/player = user?.client
	if(!player || !window())
		return
	var/framed = !docked && !user.read_preference(/datum/preference/toggle/tgui_fancy)
	winset(player, window().id, "titlebar=[framed ? "true" : "false"];can-resize=[framed ? "true" : "false"]")

/datum/tgui/dock_on_open()
	docked = dockable() && window_dock_of(user?.client)?.wants(interface)
	if(docked)
		apply_dock_chrome()

/datum/tgui/dock_on_close()
	window_dock_of(user?.client)?.window_closed(src)

/datum/tgui/dock_message(type)
	var/datum/window_dock/dock = window_dock_of(user?.client)
	switch(type)
		if("wm/dock")
			dock?.dock(src)
		if("wm/ready")
			dock?.window_ready(src)

/client/var/tmp/datum/window_dock/window_dock

#undef WINDOW_DOCK_LAYOUT_MAX
