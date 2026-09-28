// The lobby window watchdog world service (was SSlobby_monitor): every 2 s in every runlevel it
// reinitializes lobby windows that failed to open; on shutdown it shows the restart animation.
GLOBAL_DATUM_INIT(lobby_monitor_service, /datum/world_service/lobby_monitor, new)

/datum/world_service/lobby_monitor
	name = "Lobby Art"
	lane = /datum/om/behaviour/world/lobby_monitor

	/// The clients who we've waited a lane interval to start working. If they haven't, we reboot them
	var/to_reinitialize = list()

/datum/world_service/lobby_monitor/service_step(resumed)
	var/list/new_players = REGISTRY_MEMBERS(REGISTRY_NEW_PLAYERS)

	for(var/mob/new_player/player as anything in to_reinitialize)
		if(!player.client)
			continue

		var/datum/tgui/ui = SStgui.get_open_ui(player, player)
		if(ui && player.lobby_window && player.lobby_window.status > TGUI_WINDOW_CLOSED)
			continue

		log_tgui(player, "Reinitialized [player.client.ckey]'s lobby window: [ui ? "ui" : "no ui"], status: [player.lobby_window?.status].", "lobby_monitor/Fire")
		INVOKE_ASYNC(src, PROC_REF(do_reinit), player) // ALLOW(scheduler): lobby window initialize may block on winexists/asset sends

	var/initialize_queue = list()
	for(var/mob/new_player/player as anything in new_players)
		if(!player.client)
			continue

		if(player in to_reinitialize)
			continue

		var/datum/tgui/ui = SStgui.get_open_ui(player, player)
		if(ui && player.lobby_window && player.lobby_window.status > TGUI_WINDOW_CLOSED)
			continue

		initialize_queue += player

	to_reinitialize = initialize_queue
	return TRUE

/datum/world_service/lobby_monitor/proc/do_reinit(mob/new_player/player)
	var/datum/tgui/ui = SStgui.get_open_ui(player, player)
	if(ui && player.lobby_window && player.lobby_window.status > TGUI_WINDOW_CLOSED)
		return
	player.initialize_lobby_screen()

/datum/world_service/lobby_monitor/on_shutdown()
	var/datum/asset/our_asset = get_asset_datum(/datum/asset/simple/restart_animation)
	var/to_send = "<!DOCTYPE html><html lang='en'><head><meta http-equiv='X-UA-Compatible' content='IE=edge' /></head><body style='overflow: hidden;padding: 0 !important;margin: 0 !important'><div style='background-image: url([our_asset.get_url_mappings()["loading"]]);background-position:center;background-size:cover;position:absolute;width:100%;height:100%'></body></html>"

	for(var/client/client as anything in GLOB.clients)
		winset(client, "lobby_browser", "is-disabled=false;is-visible=true")

		client << browse(to_send, "window=lobby_browser")

/// lobby monitor
/datum/om/behaviour/world/lobby_monitor
	name = "world: lobby monitor"
	every = 2 SECONDS
	runlevels = 0

/datum/om/behaviour/world/lobby_monitor/service()
	return GLOB.lobby_monitor_service
