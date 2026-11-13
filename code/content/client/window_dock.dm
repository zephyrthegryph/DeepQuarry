// The window dock (doc/rewrite/proposals/window_system.md section 12): the right-hand column is one page, the chat's, and every docked tgui
// interface is a window inside it (a column part, code/library/ui/tgui/column_part.dm), framed, stacked, collapsed and moved by the page's
// own window manager exactly like the chat and the stat panel. A floating interface is a pooled native window. Docking or floating a UI
// reopens it on the other side (the server keeps no second copy); the saved layout says which interfaces open docked.

/// The saved layout's limit in characters.
#define WINDOW_DOCK_LAYOUT_MAX 8000
/// The id prefix of a column window (col-1, col-2, ...): a window's id is never an interface name, so no saved layout holds one.
#define WINDOW_DOCK_PART_PREFIX "col-"

/// The player's dock layout: interface name -> placement (JSON). The server writes `dock`; the column page keeps its arrangement too.
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
	/// Column window ids handed out so far (col-1, col-2, ...).
	var/parts_made = 0
	/// Interface name -> the column list index a drop asked for, used by the next column window of that interface.
	var/list/drop_index
	/// Interface name -> the screen point ("x,y") a drag out of the column ended at: its next native window opens under it.
	var/list/float_points

/datum/window_dock/New(client/owner)
	rel_set(src, nameof(owner), owner)

CAPABILITIES(/datum/window_dock)
	ref_one(nameof(owner))

/// The client using the dock.
/datum/window_dock/proc/owner() as /client
	return owner

/// Whether `interface` opens docked: what the saved layout says, else its default (window_dock_default_docked).
/datum/window_dock/proc/wants(interface)
	if(GLOB.window_dock_always_docked[interface])
		return TRUE
	if(isnull(wants_cache))
		wants_cache = window_dock_wanted(owner()?.prefs?.read_preference(/datum/preference/text/window_layout))
	if(interface in wants_cache)
		return !!wants_cache[interface]
	return !!GLOB.window_dock_default_docked[interface]

/// Whether `name` is a column window's id rather than an interface name (older layouts saved those by mistake).
/proc/window_dock_is_part_id(name)
	return istext(name) && copytext(name, 1, length(WINDOW_DOCK_PART_PREFIX) + 1) == WINDOW_DOCK_PART_PREFIX

/// What a saved layout's text says of each interface it names: interface -> TRUE (opens docked) or FALSE (floats).
/proc/window_dock_wanted(text)
	. = list()
	if(!istext(text) || !length(text))
		return
	var/list/layout = safe_json_decode(text)
	if(!islist(layout))
		return
	for(var/interface in layout)
		var/list/place = layout[interface]
		if(window_dock_is_part_id(interface))
			continue
		if(istext(interface) && islist(place) && !isnull(place["dock"]) && !GLOB.window_dock_always_open[interface])
			.[interface] = place["dock"] ? TRUE : FALSE

/// The column page's messages for the dock (they come through the stat panel's routing).
/datum/window_dock/proc/panel_message(type, list/payload)
	switch(type)
		if("WM-Log")
			log_tgui(owner(), "Window dock (column): [copytext(json_encode(payload), 1, 2000)]", context = "window_dock")
		if("WM-Error")
			log_tgui_client_error(owner(), payload)
		if("WM-Drop")
			drop_answer(payload)
		if("WM-Save")
			arrange(payload?["layout"])
		if("WM-FloatDone")
			float_done(payload?["window"])

/// Keeps the saved layout.
/datum/window_dock/proc/save(text)
	var/client/player = owner()
	if(!istext(text) || length(text) > WINDOW_DOCK_LAYOUT_MAX || !player?.prefs)
		return
	var/list/wanted = window_dock_wanted(text)
	// A float of an always-open interface is this connection's alone: the saved text never carries it.
	for(var/interface in GLOB.window_dock_always_open)
		if(interface in wants_cache)
			wanted[interface] = wants_cache[interface]
	wants_cache = wanted
	if(text == player.prefs.read_preference(/datum/preference/text/window_layout))
		return
	player.prefs.update_preference_by_type(/datum/preference/text/window_layout, text)

/// Keeps the column page's arrangement (groups, order, tabs, collapse, heights), with the server's own word on what opens docked: an
/// interface the server floated stays floating whatever the page last saw.
/datum/window_dock/proc/arrange(text)
	var/client/player = owner()
	if(!istext(text) || length(text) > WINDOW_DOCK_LAYOUT_MAX || !player?.prefs)
		return
	var/list/page = safe_json_decode(text)
	if(!islist(page))
		return
	var/list/stored = safe_json_decode(player.prefs.read_preference(/datum/preference/text/window_layout) || "{}")
	if(!islist(stored))
		stored = list()
	// Column window ids never name an interface: scrub the ones an older layout kept.
	for(var/interface in stored.Copy())
		if(window_dock_is_part_id(interface))
			stored -= interface
	for(var/interface in page)
		var/list/place = page[interface]
		if(!istext(interface) || !islist(place) || window_dock_is_part_id(interface))
			continue
		var/list/before = stored[interface]
		place["dock"] = islist(before) ? !!before["dock"] : !!place["dock"]
		stored[interface] = place
	save(json_encode(stored))

/// Remembers in the saved layout whether `interface` opens docked.
/datum/window_dock/proc/remember(interface, docked)
	if(GLOB.window_dock_always_open[interface])
		wants(interface) // reads the saved layout into wants_cache first
		wants_cache[interface] = docked ? TRUE : FALSE
		return
	var/client/player = owner()
	if(!player?.prefs)
		return
	var/list/layout = safe_json_decode(player.prefs.read_preference(/datum/preference/text/window_layout) || "{}")
	if(!islist(layout))
		layout = list()
	var/list/place = islist(layout[interface]) ? layout[interface] : list()
	place["dock"] = docked ? TRUE : FALSE
	layout[interface] = place
	save(json_encode(layout))

/// A fresh column window for a docked UI (its id is new each time, so a closed one's late messages reach nothing).
/datum/window_dock/proc/new_part(interface)
	var/client/player = owner()
	if(!player)
		return null
	parts_made++
	var/datum/tgui_window/column_part/part = new(player, "[WINDOW_DOCK_PART_PREFIX][parts_made]", COLUMN_PART_TGUI)
	var/at = LAZYACCESS(drop_index, interface)
	if(isnum(at))
		part.at = at
		LAZYREMOVE(drop_index, interface)
	return part

/// Reopens `ui` on the other side: closed here, opened again by its host, which picks the column or a native window by wants().
/datum/window_dock/proc/reopen(datum/tgui/ui)
	var/datum/host = ui.src_object()
	var/mob/user = ui.user
	ui.close()
	if(host && !QDELETED(host) && user)
		return host.tgui_interact(user)
	return null

/// Docks `ui` into the column (its dock button, or a drop on the column), at list index `at` when a drop gave one.
/datum/window_dock/proc/dock(datum/tgui/ui, at)
	if(!ui.dockable() || ui.docked)
		return FALSE
	remember(ui.interface, TRUE)
	if(isnum(at))
		LAZYSET(drop_index, ui.interface, at)
	log_tgui(owner(), "Window dock: [ui.interface] docked[isnum(at) ? " at [at]" : ""].", window = ui.window())
	reopen(ui)
	return TRUE

/// The client's windows docked in the column now (open, not closing).
/datum/window_dock/proc/docked_count()
	var/client/player = owner()
	. = 0
	for(var/window_id in player?.session?.tgui_windows)
		var/datum/tgui_window/column_part/part = player.session.tgui_windows[window_id]
		if(!istype(part) || part.status == TGUI_WINDOW_CLOSED)
			continue
		var/datum/tgui/held = part.locked_by()
		if(held && !held.closing)
			.++

/// Whether docked `ui` may leave the column: an always-docked interface never floats or closes, and the last docked window stays.
/datum/window_dock/proc/may_leave(datum/tgui/ui)
	if(!ui?.docked)
		return TRUE
	if(GLOB.window_dock_always_docked[ui.interface])
		return FALSE
	return docked_count() > 1

/datum/tgui/may_leave_column(closing)
	if(closing && GLOB.window_dock_always_open[interface])
		return FALSE
	var/datum/window_dock/dock = window_dock_of(user?.client)
	return dock ? dock.may_leave(src) : TRUE

/// Floats a docked `ui` out of the column into a native window (under the point `at`, "x,y", when the drag gave one).
/datum/window_dock/proc/undock(datum/tgui/ui, at)
	if(!ui.docked)
		return FALSE
	if(!may_leave(ui))
		log_tgui(owner(), "Window dock: refused to float [ui.interface] ([GLOB.window_dock_always_docked[ui.interface] ? "always docked" : "the column's last window"]).", window = ui.window())
		return FALSE
	remember(ui.interface, FALSE)
	log_tgui(owner(), "Window dock: [ui.interface] floated[at ? " under [at]" : ""].", window = ui.window())
	if(at)
		LAZYSET(float_points, ui.interface, at)
	reopen(ui)
	return TRUE

/// A window the column floated with the button still down is released: its page keeps the place the drag left it at.
/datum/window_dock/proc/float_done(window_id)
	var/client/player = owner()
	if(!istext(window_id) || !player?.session)
		return
	var/datum/tgui_window/window = player.session.tgui_windows[window_id]
	if(!window || window.status == TGUI_WINDOW_CLOSED || istype(window, /datum/tgui_window/column_part))
		return
	log_tgui(player, "Window dock: live float drag of [window_id] released.", window = window)
	window.send_message("floatdone")

/// A native window was dropped (its titlebar drag ended at screen point `point`): the column page judges whether that is over it.
/datum/window_dock/proc/dropped(datum/tgui/ui, list/point)
	var/client/player = owner()
	if(!ui.dockable() || ui.docked || !player?.tgui_panel?.window || isnull(dock_point_text(point)))
		return
	player.tgui_panel.window.send_message("col/drop-check", list("wid" = ui.window()?.id, "x" = point["x"], "y" = point["y"]))

/// The column page's answer to a drop check: window `wid` was dropped over it, at list index `index`.
/datum/window_dock/proc/drop_answer(list/payload)
	var/client/player = owner()
	var/wid = payload?["wid"]
	if(!istext(wid) || !player?.session)
		return
	var/datum/tgui_window/window = player.session.tgui_windows[wid]
	var/datum/tgui/ui = window?.locked_by()
	if(!ui || ui.closing || ui.docked || ui.user?.client != player)
		return
	var/index = payload?["index"]
	dock(ui, isnum(index) ? max(0, round(index)) : null)

/datum/tgui_panel/column_page_message(list/payload)
	if(!islist(payload) || !istext(payload["type"]))
		return FALSE
	window_dock_of(client())?.panel_message(payload["type"], islist(payload["payload"]) ? payload["payload"] : null)
	return TRUE

/datum/tgui_panel/column_message(list/payload)
	return column_route(client(), payload)

/datum/tgui_panel/column_page_loaded()
	var/client/player = client()
	window.send_message("col/init", list("saved" = player?.prefs?.read_preference(/datum/preference/text/window_layout) || ""))
	// Every column window opens in the page again; its UI gets a full update when the page reports it ready.
	for(var/window_id in player?.session?.tgui_windows)
		var/datum/tgui_window/column_part/part = player.session.tgui_windows[window_id]
		if(istype(part) && part.status != TGUI_WINDOW_CLOSED)
			part.reinitialize()

/// The column page's message for one of its windows (`col/msg`): handed to that window as if its own page sent it. Only a column part of
/// this client is ever reached; anything else is dropped.
/proc/column_route(client/player, list/payload)
	if(!player?.session || !islist(payload))
		return FALSE
	var/wid = payload["wid"]
	var/type = payload["type"]
	if(!istext(wid) || !istext(type))
		return FALSE
	var/datum/tgui_window/column_part/part = player.session.tgui_windows[wid]
	if(!istype(part))
		return FALSE
	part.on_message(type, payload["payload"], list())
	return TRUE

/datum/tgui/dock_window()
	if(!dockable_interface())
		return null
	var/datum/window_dock/dock = window_dock_of(user?.client)
	if(!dock)
		return null
	if(!dock.wants(interface))
		// Floating: a drag out of the column left a point for it, so its window opens under the pointer (one update carries it).
		var/at = LAZYACCESS(dock.float_points, interface)
		if(at)
			float_at = at
			LAZYREMOVE(dock.float_points, interface)
		return null
	return dock.new_part(interface)

/datum/tgui/dock_message(type, list/payload)
	var/datum/window_dock/dock = window_dock_of(user?.client)
	switch(type)
		if("wm/dock")
			// The dock button in a native window's title bar.
			dock?.dock(src)
		if("wm/float")
			// The float button (or a drag out) on a docked window in the column; `at` is the screen point it was dragged to.
			dock?.undock(src, dock_point_text(payload?["at"], payload?["size"]))
		if("wm/floated")
			// A window floated out of the column is up: the column page may be moving it with the pointer (a drag that left with the button down).
			var/client/player = user?.client
			if(player?.tgui_panel?.window && istext(payload?["window"]))
				player.tgui_panel.window.send_message("col/floated", list("window" = payload["window"]))
		if("wm/dropped")
			// A native window's titlebar drag ended at screen point `pointer`: maybe over the column.
			dock?.dropped(src, payload?["pointer"])
		if("wm/view")
			// The column page: this docked window's entry is collapsed or behind another tab (no data pushes), or shown again (one update).
			if(docked)
				dock_hide(!!payload?["hidden"])
		if("wm/log")
			log_tgui(user, "Window dock (page): [copytext(json_encode(payload), 1, 2000)]", context = "window_dock", window = window())

/client/var/tmp/datum/window_dock/window_dock

#undef WINDOW_DOCK_LAYOUT_MAX
#undef WINDOW_DOCK_PART_PREFIX
