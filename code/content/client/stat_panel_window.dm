// The stat panel as a tgui interface (doc/rewrite/proposals/window_system.md section 12): one per client, the "StatPanel" window. It docks
// in the right-hand column by default and floats like any other window. Its protocol is unchanged: the server's stat panel code sends named
// messages to `client.stat_panel` (whichever window the UI is in now, a column window or a native one), and what the page sends comes back
// through ui_raw_message() to /client/proc/on_stat_panel_message().

/datum/stat_panel_ui
	/// The client whose panel this is: a one-sided back view (the client owns it).
	var/client/owner

/datum/stat_panel_ui/New(client/owner)
	rel_set(src, nameof(owner), owner)

CAPABILITIES(/datum/stat_panel_ui)
	ref_one(nameof(owner))
	interface("StatPanel", title = "Status", state = nameof(GLOB.tgui_always_state), pinned = TRUE)
	// The panel carries its data in its own messages (update_verbs, update_stat, ...); its ui_data only names whose it is.
	ui_shape(ckey = schema_text())

/// The client using the panel.
/datum/stat_panel_ui/proc/owner() as /client
	return owner

/datum/stat_panel_ui/ui_prepare(mob/user, datum/tgui/ui)
	return !!owner() && user?.client == owner()

/datum/stat_panel_ui/ui_data(datum/act/eval/A)
	return list("ckey" = owner()?.ckey)

/// Its window, docked or floating, is where the stat panel's messages go.
/datum/stat_panel_ui/ui_opened(mob/user, datum/tgui/ui)
	var/client/player = owner()
	if(!player || !ui?.window())
		return
	rel_set(player, nameof(/client::stat_panel), ui.window())
	log_tgui(player, "Stat panel opened in [ui.window().id] ([ui.docked ? "docked" : "floating"]).", context = "stat_panel")

/// The page's stat panel messages (Set-Tab, Update-Verbs, Inspect-Act, ...).
/datum/stat_panel_ui/ui_raw_message(mob/user, type, list/payload)
	var/client/player = owner()
	if(!player || user?.client != player)
		return FALSE
	player.on_stat_panel_message(type, payload)
	return TRUE

/// Opens (or re-opens) the client's stat panel window: docked unless the player floated it.
/proc/stat_panel_open(client/player)
	if(!player?.mob)
		return null
	if(!player.stat_panel_ui)
		rel_set(player, nameof(/client::stat_panel_ui), new /datum/stat_panel_ui(player))
	return player.stat_panel_ui.tgui_interact(player.mob)

/// The client's stat panel interface (its window is `stat_panel`).
/client/var/tmp/datum/stat_panel_ui/stat_panel_ui
