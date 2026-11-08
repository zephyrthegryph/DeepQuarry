// The window dock (doc/rewrite/proposals/window_system.md): any pooled tgui window can be docked into the right-hand column. A docked
// UI keeps its own BYOND window, page and /datum/tgui (routing is unchanged); it only loses its OS chrome, and the stat panel page frames
// it (titlebar, tabs, collapse, float, close) and places it over a placeholder (tgui-panel/statpanel/windowDock.ts is the layout).
//
// The server's part: which UIs are docked (config.window.docked), which are hidden (collapsed or behind a tab: no data pushes while
// hidden, one full update when shown again), the messages between the UI pages, the stat panel and the UIs, and the saved layout.

/// The saved layout's limit in characters (the stat panel trims to this, windowDock.ts DOCK_SAVE_MAX).
#define WINDOW_DOCK_LAYOUT_MAX 8000
/// A docked window's weight in the column against the stat panel's (dock_column_winsets()).
#define WINDOW_DOCK_SHARE 35
#define WINDOW_DOCK_STAT_SHARE 40

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
	/// The docked windows' ids, top to bottom: each is a native pane in the chain of splits in the stat panel's place (dock_column.dm).
	var/list/column_ids
	/// How many link panes this client's skin has (cloned once each, kept for the session).
	var/links_made = 0

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
		if("WM-Log")
			// The panel's own account of a placement: what it sent and what the client reads back (hard to see any other way).
			log_tgui(owner(), "Window dock (panel): [copytext(json_encode(payload), 1, 2000)]", context = "window_dock")

/// Tells a (re)loaded panel the saved layout and the windows docked now.
/datum/window_dock/proc/send_init()
	// The stat panel (re)loaded: it frames nothing any more (docked windows are native panes), but a reload of the skin's panes
	// can drop the chain, so it is seated again.
	if(LAZYLEN(column_ids))
		relayout()

/// Keeps the saved layout (remember() writes it).
/datum/window_dock/proc/save(text)
	var/client/player = owner()
	if(!istext(text) || length(text) > WINDOW_DOCK_LAYOUT_MAX || !player?.prefs)
		return
	wants_cache = window_dock_wanted(text)
	if(text == player.prefs.read_preference(/datum/preference/text/window_layout))
		return
	player.prefs.update_preference_by_type(/datum/preference/text/window_layout, text)

/// The pane standing in the stat panel's place in the right-hand column (the chat's layout seats it).
/datum/window_dock/proc/column_slot()
	return dock_column_slot(LAZYLEN(column_ids))

/**
 * Lays the docked windows out as native panes: each docked window is a pane in the chain of splits that stands in the stat panel's
 * place (dock_column.dm), exactly as the chat pane sits in the column. One winset: the column's slot and every link are emptied
 * first (a pane is in one place at a time), then the chain is filled and seated. `released` is a window id that just left the dock
 * (it stops being a pane).
 */
/datum/window_dock/proc/relayout(released)
	var/client/player = owner()
	if(!player)
		return
	for(var/window_id in LAZYCOPY(column_ids))
		var/datum/tgui_window/window = player.session?.tgui_windows[window_id]
		if(!window?.locked_by()?.docked)
			LAZYREMOVE(column_ids, window_id)
	var/count = LAZYLEN(column_ids)
	while(links_made < count)
		links_made++
		winclone(player, SKIN_DOCK_LINK_TEMPLATE, dock_link_id(links_made))
	var/side = player.chat_on_top() ? "right" : "left"
	var/list/steps = list()
	steps += "[SKIN_RPANE_SPLIT].[side]="
	for(var/n in 1 to links_made)
		steps += "[dock_link_id(n)].split.left="
		steps += "[dock_link_id(n)].split.right="
	if(released)
		steps += "[released].is-pane=false"
	var/list/entries = list()
	var/list/shares = list()
	for(var/window_id in column_ids)
		steps += "[window_id].is-pane=true"
		steps += "[window_id].titlebar=false"
		steps += "[window_id].can-resize=false"
		steps += "[window_id].alpha=255"
		steps += "[window_id].is-visible=true"
		entries += window_id
		shares += WINDOW_DOCK_SHARE
	entries += SKIN_STAT_PANE
	shares += WINDOW_DOCK_STAT_SHARE
	var/list/splits = dock_column_winsets(entries, shares)
	for(var/split_id in splits)
		var/list/split = splits[split_id]
		for(var/param in split)
			steps += "[split_id].[param]=[split[param]]"
	steps += "[SKIN_RPANE_SPLIT].[side]=[column_slot()]"
	var/text = jointext(steps, ";")
	winset(player, null, text)
	log_tgui(player, "Window dock: column [count ? jointext(column_ids, ", ") : "empty"]. winset: [text]", context = "window_dock")

/// Remembers in the saved layout whether `interface` is docked (the server keeps it: the stat panel no longer frames windows).
/datum/window_dock/proc/remember(interface, docked)
	var/client/player = owner()
	if(!player?.prefs)
		return
	var/list/layout = safe_json_decode(player.prefs.read_preference(/datum/preference/text/window_layout) || "{}")
	if(!islist(layout))
		layout = list()
	var/list/place = islist(layout[interface]) ? layout[interface] : list("group" = interface)
	place["dock"] = docked ? TRUE : FALSE
	layout[interface] = place
	save(json_encode(layout))

/// Docks `ui` (its page asked: the dock button or a drop on the column): its window becomes a pane in the column.
/datum/window_dock/proc/dock(datum/tgui/ui)
	if(!ui.dockable() || ui.docked)
		return FALSE
	ui.docked = TRUE
	if(wants_cache)
		wants_cache[ui.interface] = TRUE
	var/window_id = ui.window()?.id
	if(window_id && !(window_id in column_ids))
		LAZYADD(column_ids, window_id)
	ui.apply_dock_chrome()
	relayout()
	remember(ui.interface, TRUE)
	log_tgui(owner(), "Window dock: [ui.interface] docked as a pane.", window = ui.window())
	ui.send_full_update()
	return TRUE

/// Floats a docked `ui`: its chrome comes back and its page places itself where it last floated.
/datum/window_dock/proc/undock(datum/tgui/ui, at)
	if(!ui.docked)
		return FALSE
	ui.docked = FALSE
	if(wants_cache)
		wants_cache -= ui.interface
	LAZYREMOVE(column_ids, ui.window()?.id)
	relayout(ui.window()?.id)
	remember(ui.interface, FALSE)
	ui.apply_dock_chrome()
	ui.dock_hide(FALSE)
	log_tgui(owner(), "Window dock: [ui.interface] floated[at ? " under the pointer at [at]" : ""].", window = ui.window())
	ui.float_at = at
	ui.send_full_update()
	ui.float_at = null
	return TRUE

/// A docked UI's page is up: its pane is (re)seated in the column (a UI that opened docked joins it here).
/datum/window_dock/proc/window_ready(datum/tgui/ui)
	if(!ui.docked)
		return
	var/window_id = ui.window()?.id
	if(window_id && !(window_id in column_ids))
		LAZYADD(column_ids, window_id)
	relayout()

/// A docked UI closed: the panel drops it and the pooled window gets its chrome back for its next owner.
/datum/window_dock/proc/window_closed(datum/tgui/ui)
	ui.docked = FALSE
	ui.view_hidden = FALSE
	var/window_id = ui.window()?.id
	if(window_id && (window_id in column_ids))
		LAZYREMOVE(column_ids, window_id)
		relayout(window_id)
	ui.apply_dock_chrome()

/// The pooled window's OS chrome: none while docked (the panel frames it), the player's own while floating.
/datum/tgui/proc/apply_dock_chrome()
	var/client/player = user?.client
	if(!player || !window())
		return
	var/framed = !docked && FALSE
	winset(player, window().id, "titlebar=[framed ? "true" : "false"];can-resize=[framed ? "true" : "false"]")

/datum/tgui/dock_on_open()
	docked = dockable() && window_dock_of(user?.client)?.wants(interface)
	if(docked)
		apply_dock_chrome()

/datum/tgui/dock_on_close()
	window_dock_of(user?.client)?.window_closed(src)

/datum/tgui/dock_message(type, list/payload)
	var/datum/window_dock/dock = window_dock_of(user?.client)
	switch(type)
		if("wm/dock")
			dock?.dock(src)
		if("wm/ready")
			dock?.window_ready(src)
		if("wm/float")
			// The float button in a docked window's own title bar.
			dock?.undock(src)
		if("wm/log")
			// The window page's account of a dock decision (a drop over the panel or not, and why).
			log_tgui(user, "Window dock (page): [copytext(json_encode(payload), 1, 2000)]", context = "window_dock", window = window())

/client/var/tmp/datum/window_dock/window_dock

#undef WINDOW_DOCK_LAYOUT_MAX
#undef WINDOW_DOCK_SHARE
#undef WINDOW_DOCK_STAT_SHARE
