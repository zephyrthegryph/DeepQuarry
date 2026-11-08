// A window inside the right-hand column's page (doc/rewrite/proposals/window_system.md section 12). The column is one browser, the
// chat's (tgui_panel); the stat panel and every docked tgui interface are windows in that page, each a column part: a /datum/tgui_window
// with its own id in the client's session, but no browser of its own. What it sends goes through the panel's window wrapped as
// `col/msg {wid, raw}`; what the page sends for it comes back as `col/msg {wid, type, payload}` (tgui_panel on_message) and is handed to
// on_message() as if from its own page. A UI in a column part is routed, updated and closed exactly as in a native window.

/datum/tgui_window/column_part
	/// What the column page shows for it: COLUMN_PART_STAT (the stat panel) or COLUMN_PART_TGUI (a tgui interface).
	var/kind = COLUMN_PART_TGUI
	/// The column list index a drop asked for (null: wherever the page's saved arrangement puts this interface).
	var/at

/datum/tgui_window/column_part/New(client/client, id, kind = COLUMN_PART_TGUI)
	..(client, id, FALSE)
	src.kind = kind

/// The page that hosts the column: the chat's panel window.
/datum/tgui_window/column_part/proc/host() as /datum/tgui_window
	return client()?.tgui_panel?.window

/datum/tgui_window/column_part/reachable()
	return ..() && !!host()

/// Opens this window in the column page: no browse(), the page makes a window for it and reports `ready` through col/msg.
/datum/tgui_window/column_part/initialize(
		strict_mode = FALSE,
		fancy = FALSE,
		assets = list(),
		inline_html = "",
		inline_js = "",
		inline_css = "")
	if(!reachable())
		return
	rel_set(src, nameof(asset_generation), SStgui.get_current_asset_generation())
	initial_assets = assets
	status = TGUI_WINDOW_LOADING
	opening = FALSE
	fatally_errored = FALSE
	last_sent = null
	var/static/document_sequence = 0
	document_id = "[id]-[world.time]-[++document_sequence]"
	for(var/datum/asset/asset in assets)
		asset.send(client())
	host().send_message("col/open", list("wid" = id, "kind" = kind, "document" = document_id, "at" = at))
	at = null
	log_tgui(client(), "Column window opened ([kind], [document_id]).", window = src)

/// Everything this window sends leaves through the column page, tagged with its id.
/datum/tgui_window/column_part/deliver(message)
	host()?.send_message("col/msg", list("wid" = id, "raw" = message))

/datum/tgui_window/column_part/close(can_be_suspended = TRUE)
	last_sent = null
	release_lock()
	visible = FALSE
	status = TGUI_WINDOW_CLOSED
	message_queue = null
	if(reachable())
		host().send_message("col/close", list("wid" = id))
	log_tgui(client(), "Column window closed.", window = src)

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
